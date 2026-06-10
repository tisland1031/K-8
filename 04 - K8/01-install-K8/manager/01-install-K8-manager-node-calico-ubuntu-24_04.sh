#!/bin/bash
set -euxo pipefail

# Define Kubernetes version and Pod Network CIDR
K8S_VERSION="1.35"
POD_CIDR="192.168.0.0/16"

echo "--- 1. Set up initial system configurations ---"
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

echo "--- 1.5 Wait for Ubuntu automatic background updates to finish ---"
while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock >/dev/null 2>&1; do
    echo "Waiting for automatic system updates to release dpkg lock..."
    sleep 3
done

echo "--- 2. Install and configure Containerd (CRI Runtime) ---"
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release containerd

mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/g' > /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

echo "--- 3. Install Kubernetes components (kubelet, kubeadm, kubectl) ---"
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo "--- 4. Configure crictl to use containerd ---"
cat <<EOF >/etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

echo "--- 5. Initialize the Kubernetes Control Plane (Master) ---"
# Pre-pull images to ensure kubeadm doesn't timeout inside cloud-init
kubeadm config images pull --kubernetes-version="v${K8S_VERSION}.5" || true

# Run kubeadm init safely. If it fails, it will catch it cleanly.
kubeadm init --pod-network-cidr="${POD_CIDR}" --ignore-preflight-errors=all

echo "--- 6. Configure kubectl access for the root user ---"
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chmod 600 /root/.kube/config

# Export the variable explicitly for the rest of this cloud-init session
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "--- 7. Install Calico Pod Network Add-on ---"
# Force kubectl to use the system configuration directly via the --kubeconfig flag
/usr/bin/kubectl --kubeconfig=/etc/kubernetes/admin.conf create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.2/manifests/tigera-operator.yaml

echo "Waiting for Tigera Operator CRDs to be established..."
/usr/bin/kubectl --kubeconfig=/etc/kubernetes/admin.conf wait --for=condition=Established --timeout=60s crd/installations.operator.tigera.io

curl -fsSL https://raw.githubusercontent.com/projectcalico/calico/v3.29.2/manifests/custom-resources.yaml -o /tmp/custom-resources.yaml
/usr/bin/kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f /tmp/custom-resources.yaml

echo "--- Installation Complete ---"

# 1. Check if all nodes (Manager and Joined Workers) are ready
kubectl get nodes

# 2. Check if Calico components are actively running and healthy
kubectl get pods -n calico-system

# 3. Check if the CoreDNS pods have successfully been assigned Calico IPs
kubectl get pods -n kube-system -o wide

# 4. Generate worker join token
kubeadm token create --print-join-command

# if not setup, look at logs at ...
# cat /var/log/cloud-init-output.log
