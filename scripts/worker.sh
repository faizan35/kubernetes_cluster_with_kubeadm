#!/bin/bash
# worker.sh — run BY HAND on a worker, after SSHing in from base.
#
# Usage:
#   bash ~/worker.sh "kubeadm join 10.0.1.10:6443 --token abc.123 --discovery-token-ca-cert-hash sha256:..."
#
# Quote the join command. It contains spaces and will not survive unquoted.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: bash ~/worker.sh \"<full kubeadm join command>\""
  echo
  echo "Get it on the control plane with:"
  echo "  kubeadm token create --print-join-command"
  exit 1
fi

JOIN_CMD="$*"

echo "==> Clearing any previous join attempt"
sudo kubeadm reset -f >/dev/null 2>&1 || true

# Deleting /etc/cni/net.d while containerd is running crashes it — containerd
# watches that directory and its CNI monitor exits fatally when it disappears
# out from under it ("cni conf dir is removed, stop watching"). systemd then
# auto-restarts containerd, but that takes a few seconds, and if kubeadm join
# runs in that window it fails with "connection refused" even though nothing
# is actually broken — the socket just isn't up yet.
#
# Fix: do the cleanup, then explicitly restart containerd and WAIT for the
# socket to answer before doing anything else.
sudo rm -rf /etc/cni/net.d
sudo systemctl restart containerd

echo "==> Waiting for containerd to be ready"
for i in $(seq 1 15); do
  if sudo crictl info >/dev/null 2>&1; then
    echo "    containerd is ready (after ${i}s)"
    break
  fi
  if [[ $i -eq 15 ]]; then
    echo "!! containerd did not come up after 15s. Diagnose with:"
    echo "     sudo systemctl status containerd"
    echo "     sudo journalctl -u containerd -n 50 --no-pager"
    exit 1
  fi
  sleep 1
done

echo "==> Joining the cluster"
sudo ${JOIN_CMD} --v=5

echo
echo "======================================================================"
echo " $(hostname) joined."
echo " Verify from the control plane:  kubectl get nodes -o wide"
echo "======================================================================"
