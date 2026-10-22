#!/bin/bash
# master.sh — run BY HAND on the control plane, after SSHing in from base.
#
# Left manual on purpose: `kubeadm init` is an exam task. Automating it away
# would remove the practice.

set -euo pipefail

# Calico v3.33 is tested upstream on Kubernetes v1.35, v1.36 and v1.37.
# We keep the explicit manifests-based CNI install for exam practice; Calico's
# operator-based install is preferred for its lifecycle management in production.
# docs.tigera.io/calico/latest/getting-started/kubernetes/requirements
: "${CALICO_VERSION:=v3.33.0}"
# The packaged calico.yaml uses 192.168.0.0/16 by default. To change it,
# update the Calico IP pool manifest as well as this kubeadm CIDR.
POD_CIDR="192.168.0.0/16"

if [[ $EUID -eq 0 ]]; then
  echo "Run as the ubuntu user, not root. The script uses sudo where needed."
  exit 1
fi

# This workflow intentionally creates a fresh single-control-plane kubeadm lab.
if [[ -f /etc/kubernetes/admin.conf ]]; then
  echo "!! Control plane already initialized; refusing to run kubeadm init again."
  exit 1
fi

echo "==> Pre-pulling control plane images"
sudo kubeadm config images pull

echo "==> kubeadm init"
sudo kubeadm init --pod-network-cidr="${POD_CIDR}"

echo "==> kubeconfig for ubuntu user"
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# root needs it too — most control plane work happens under `sudo -i`
sudo mkdir -p /root/.kube
sudo cp -f /etc/kubernetes/admin.conf /root/.kube/config

echo "==> Calico ${CALICO_VERSION}"
kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"

echo "==> Waiting for Calico DaemonSet to roll out"
kubectl -n kube-system rollout status ds/calico-node --timeout=180s || {
  echo "!! Calico not healthy. Check: kubectl -n kube-system get pods -l k8s-app=calico-node"
  exit 1
}

# CoreDNS may remain Pending while the control-plane taint prevents scheduling;
# validate CoreDNS AFTER workers have joined, not before.
echo "==> Waiting for the control plane to become Ready (up to 3 min)"
kubectl wait --for=condition=Ready node --all --timeout=180s || {
  echo "!! Node not Ready."
  echo "   kubectl get pods -A"
  echo "   sudo journalctl -u kubelet -n 50 --no-pager"
  exit 1
}

echo
echo "======================================================================"
echo " Control plane ready. Join command for workers:"
echo "======================================================================"
kubeadm token create --kubeconfig="$HOME/.kube/config" --ttl 0 --print-join-command
echo "======================================================================"
echo
echo " --ttl 0 makes this token non-expiring, which is what you want for a"
echo " DISPOSABLE lab. Never use a permanent bootstrap token in production."
echo " For CKA task practice, use the default 24h expiry and"
echo " regenerate with:  kubeadm token create --kubeconfig="$HOME/.kube/config" --print-join-command"
echo
echo " Next: return to base, then ssh to each worker."
echo "   exit"
echo "   ssh node01"
echo "   bash ~/worker.sh \"<join command above>\""
echo
kubectl get nodes -o wide