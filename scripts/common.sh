#!/bin/bash
# common.sh — runs on the CONTROL PLANE and WORKERS (not on base)
# Prepares a bare Ubuntu 24.04 box to be a Kubernetes node, and installs the
# same tooling the CKA exam pre-installs on every host.
#
# Run automatically at boot via cloud-init.

set -euo pipefail

K8S_MINOR="v1.35"
K8S_PKG="1.35.1-*"          # check available: apt-cache madison kubeadm
YQ_VERSION="v4.44.3"

# ---------------------------------------------------------------------------
# 1. Node prerequisites
# ---------------------------------------------------------------------------

echo "==> Disabling swap"
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

echo "==> Kernel modules"
cat <<'EOF' > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

echo "==> sysctl"
cat <<'EOF' > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# ---------------------------------------------------------------------------
# 2. Exam-parity tooling
#    The CKA exam pre-installs kubectl (aliased to k, with completion), yq,
#    curl, wget and man on every host. Match that so nothing you rely on in
#    the exam is missing here, and nothing is here that isn't there.
# ---------------------------------------------------------------------------

echo "==> Base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  apt-transport-https ca-certificates curl wget gpg jq \
  bash-completion vim less tree \
  man-db manpages \
  etcd-client

# Ubuntu cloud images strip man pages via a dpkg exclusion. Removing it means
# anything installed from here on ships its pages. Full parity would need
# `unminimize`, which is too slow for a lab you rebuild constantly.
rm -f /etc/dpkg/dpkg.cfg.d/excludes || true

echo "==> yq (mikefarah build — the one the exam has)"
curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
  -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq

echo "==> helm (curriculum: 'Use Helm and Kustomize to install cluster components')"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ---------------------------------------------------------------------------
# 3. containerd
# ---------------------------------------------------------------------------

echo "==> containerd"
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Cgroup driver mismatch between containerd and the kubelet is the #1 reason a
# hand-built cluster fails. Verify the edit actually landed.
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
if ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml; then
  echo "!! SystemdCgroup was NOT set. containerd config format may have changed."
  exit 1
fi

systemctl restart containerd
systemctl enable containerd

# ---------------------------------------------------------------------------
# 4. Kubernetes
# ---------------------------------------------------------------------------

echo "==> Kubernetes ${K8S_MINOR}"
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y \
  kubelet="${K8S_PKG}" \
  kubeadm="${K8S_PKG}" \
  kubectl="${K8S_PKG}" \
  cri-tools

apt-mark hold kubelet kubeadm kubectl

crictl config runtime-endpoint unix:///run/containerd/containerd.sock
crictl config image-endpoint unix:///run/containerd/containerd.sock

systemctl enable --now kubelet

# ---------------------------------------------------------------------------
# 5. Shell environment — on EVERY node, matching the exam
#    In the exam, `k` and bash completion are already configured wherever you
#    land. Set them up here too so you never waste exam time recreating them,
#    and never get caught out by them being absent.
# ---------------------------------------------------------------------------

echo "==> Shell environment for ubuntu user"
# ONLY what the exam itself pre-configures: the `k` alias and completion.
#
# Deliberately NOT set here: $do, $now, and ~/.vimrc. The exam does NOT
# pre-configure those -- you type them yourself on every host, every time.
# Pre-baking them into the lab would rob you of the reps and leave you slower
# on exam day, which is the exact opposite of what this lab is for.
cat >> /home/ubuntu/.bashrc <<'BASHRC_EOF'

# ---- matches the CKA exam's pre-installed state ----
source /usr/share/bash-completion/bash_completion
alias k=kubectl
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
BASHRC_EOF

chown ubuntu:ubuntu /home/ubuntu/.bashrc

# Root gets the same, since `sudo -i` is how most control plane work happens.
cat >> /root/.bashrc <<'ROOT_BASHRC_EOF'

source /usr/share/bash-completion/bash_completion
alias k=kubectl
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
ROOT_BASHRC_EOF

# Your 20-second exam warm-up, kept as a reference you must TYPE, not source.
# Read it if you blank; do not get into the habit of running it.
cat > /home/ubuntu/EXAM-WARMUP.txt <<'WARMUP_EOF'
Type these on every host you ssh into. The exam does not set them for you.

  export do="--dry-run=client -o yaml"
  export now="--force --grace-period=0"

  vim ~/.vimrc
    set expandtab tabstop=2 shiftwidth=2 number

Already done for you by the exam (and by this lab): k alias, bash completion.
WARMUP_EOF
chown ubuntu:ubuntu /home/ubuntu/EXAM-WARMUP.txt

echo
echo "===================================================="
echo " Node prepared: $(hostname)"
kubeadm version -o short
echo " containerd $(containerd --version | awk '{print $3}')"
echo " helm       $(helm version --short 2>/dev/null || echo 'n/a')"
echo " yq         $(yq --version 2>/dev/null || echo 'n/a')"
echo " etcdctl    $(etcdctl version 2>/dev/null | head -1 || echo 'n/a')"
echo "===================================================="
