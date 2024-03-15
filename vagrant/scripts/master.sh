#!/bin/bash

# Check if control plane IP argument is provided, otherwise exit
if [ $# -ne 1 ]; then
    echo "Usage: $0 <control_plane_ip>"
    exit 1
fi


# Replace the control plane IP with the appropriate IP address
control_plane_ip="$1"

echo "Downloading All Required Images..."

sudo kubeadm config images pull

sudo kubeadm init --apiserver-advertise-address=$control_plane_ip --apiserver-cert-extra-sans=$control_plane_ip --pod-network-cidr=172.16.1.0/16 --service-cidr=172.17.1.0/18 --node-name "$(hostname -s)" --ignore-preflight-errors Swap

mkdir -p "$HOME"/.kube
sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
sudo chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config

#  Install Calico Network Plugin
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml

kubeadm token create --print-join-command

# ================================   PORT   ====================================


sudo ufw status


#####################################################################
