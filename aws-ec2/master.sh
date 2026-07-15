#!/bin/bash

echo "Pulling kubeadm Images..."
sudo kubeadm config images pull

# Initialize the cluster with the specific Pod Network CIDR required by Calico
sudo kubeadm init --pod-network-cidr=192.168.0.0/16

# Configure kubeconfig for the standard Ubuntu user
mkdir -p "$HOME"/.kube
sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
sudo chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config

# Install Calico Network Plugin
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml

echo "====================================================================="
echo "Cluster initialized successfully!"
echo "Use the following join command on your worker node(s):"
echo "====================================================================="
kubeadm token create --print-join-command