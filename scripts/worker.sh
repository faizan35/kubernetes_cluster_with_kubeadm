#!/bin/bash
# worker.sh — run BY HAND on a worker, after SSHing in from base.
#
# Usage:
#   bash ~/worker.sh "kubeadm join 10.0.1.10:6443 --token abc.123 --discovery-token-ca-cert-hash sha256:..."
#
# Quote the join command. It contains spaces and will not survive unquoted.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: bash ~/worker.sh \"<full kubeadm join command>\""
  echo
  echo "Get it on the control plane with:"
  echo "  kubeadm token create --print-join-command"
  exit 1
fi

# The printed kubeadm join command is whitespace-delimited; it contains no
# shell quoting or substitutions. Read into an array rather than eval/bash -c.
read -r -a JOIN_ARGS <<< "$1"
if [[ ${#JOIN_ARGS[@]} -lt 4 || "${JOIN_ARGS[0]}" != "kubeadm" || "${JOIN_ARGS[1]}" != "join" ]]; then
  echo "!! Expected the complete 'kubeadm join ...' command."
  exit 1
fi
for arg in "${JOIN_ARGS[@]}"; do
  if [[ "$arg" == "--control-plane" ]]; then
    echo "!! worker.sh is for worker nodes only, not additional control planes."
    exit 1
  fi
done

# Never disrupt a node that already joined merely because a command is retried.
# Explicit opt-in for destructive re-join work: RESET_NODE=1 bash worker.sh '...'
if [[ -f /etc/kubernetes/kubelet.conf && "${RESET_NODE:-0}" != "1" ]]; then
  echo "!! Existing kubelet credentials detected. Node may already be joined."
  echo "!! No changes made. For deliberate re-join: RESET_NODE=1 bash ~/worker.sh '<join command>'"
  exit 1
fi

echo "==> Resetting leftover state from any previous join attempt"
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
sudo "${JOIN_ARGS[@]}" --v=5

echo
echo "======================================================================"
echo " $(hostname) joined."
echo " Verify from the control plane: kubectl get nodes -o wide"
echo " Then verify CoreDNS: kubectl -n kube-system rollout status deploy/coredns"
echo "======================================================================"
