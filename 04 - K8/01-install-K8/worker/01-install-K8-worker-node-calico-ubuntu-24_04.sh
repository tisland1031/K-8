#!/bin/bash
set -euxo pipefail

# Kubernetes version (must match control plane)
K8S_VERSION="1.30"

echo "--- 1. Set up initial system configurations ---"
# Disable swap (required by Kubernetes)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set sysctl params required by Kubernetes networking
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

# Apply sysctl params immediately
sudo sysctl --system

echo "--- 2. Install and configure Containerd (CRI runtime) ---"
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release containerd

# Generate default config for containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

# Set containerd to use the systemd cgroup driver (important for cgroup v2)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart and enable containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

echo "--- 3. Install Kubernetes components (kubelet, kubeadm, kubectl) ---"
# Add the Kubernetes signing key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add the Kubernetes APT repository
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install kubelet, kubeadm, and kubectl
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "--- 4. Configure crictl to use containerd ---"
sudo bash -c 'cat <<EOF >/etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF'

echo "--- 5. Enable kubelet service ---"
sudo systemctl enable kubelet

echo "--- Installation Complete ---"
echo "Worker node software installed and ready to join the cluster."
echo ""
echo "Once your control plane is ready, join this node using the command printed by: (must be executed on manager node)"
echo "   sudo kubeadm token create --print-join-command"
echo ""
echo "Example:"
echo "   sudo kubeadm join <CONTROL_PLANE_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>"