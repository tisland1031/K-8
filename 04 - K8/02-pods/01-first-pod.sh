#!/bin/sh

#On manager node
kubectl get nodes

kubectl apply -f nginx-pod.yaml
# Verbose mode --v=2 , 4, 6, 8 and  --v=10
# kubectl apply -f pod.yaml --v=2

#dry-run without applying
# kubectl apply -f pod.yaml --dry-run=server -o yaml

# Check Pod status and on which node it is running on
kubectl get pods -o wide

#Example output ...
#NAME          READY   STATUS    RESTARTS   AGE   IP            NODE
#nginx-demo    1/1     Running   0          10s   10.244.0.12   ip-172-31-23-9

kubectl describe pod nginx-demo

#From manager
kubectl exec -it nginx-demo -- curl -s localhost
kubectl port-forward pod/nginx-demo 8080:80 &
curl http://localhost:8080

# Local Port Binding
# On your local machine, kubectl binds port 8080.
# Any traffic you send to localhost:8080 is captured by kubectl.
# Traffic Forwarding
# kubectl takes the incoming data from localhost:8080 and sends it securely over the API server connection.
# The API server passes it down to the node’s Kubelet, which finally sends it to port 80 in the pod.
# kubectl port-forward creates a user-space tunnel — not a cluster-level network route
# kube-proxy is completely bypassed (No Service etc ..)

# but  this does not expose it to internet with EC2 instance public IP:8080
#   - The port-forward listens only on localhost (127.0.0.1) by default.
#   - It does not bind to the EC2 network interface, so external traffic can’t reach it.
#   - Only processes running on the same machine can access http://localhost:8080.
# if you want to expose, you need a "service" or service with a LoadBalancer, or ingress- for future demos

#Goto part 2 of demo in README

# Cleanup
kubectl delete pod nginx-demo
