#!/bin/bash

# # Check if control plane IP argument is provided, otherwise exit
# if [ $# -ne 1 ]; then
#     echo "Usage: $0 <control_plane_ip>"
#     exit 1
# fi


# # Replace the control plane IP with the appropriate IP address
# control_plane_ip="$1"

# echo "Downloading All Required Images..."

# sudo kubeadm config images pull

# sudo kubeadm init --apiserver-advertise-address=$control_plane_ip --apiserver-cert-extra-sans=$control_plane_ip --pod-network-cidr=172.16.1.0/16 --service-cidr=172.17.1.0/18 --node-name "$(hostname -s)" --ignore-preflight-errors Swap


# Get the IP address of eth1 dynamically
control_plane_ip=$(ip addr show eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Check if control plane IP is obtained, otherwise exit
if [ -z "$control_plane_ip" ]; then
    echo "Failed to retrieve control plane IP. Check network configuration."
    exit 1
fi

echo "Control Plane IP: $control_plane_ip"

# Proceed with the rest of your script using $control_plane_ip
# Replace the control plane IP with the appropriate IP address
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
