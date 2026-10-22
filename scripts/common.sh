#!/bin/bash
# common.sh — runs on the CONTROL PLANE and WORKERS (not on base)
# Prepares a bare Ubuntu 24.04 box to be a Kubernetes node, and installs the
# same tooling the CKA exam pre-installs on every host.
#
# Run automatically at boot via cloud-init.

set -euo pipefail

# Any failure here leaves a node that LOOKS fine over SSH but has no kubeadm.
# That surfaces much later as "kubeadm: command not found" when you run
# master.sh, and looks identical to not having waited for cloud-init. Make the
# failure loud and greppable in /var/log/cka-bootstrap.log instead.
trap 'echo "!! =================================================="
      echo "!! common.sh FAILED at line ${LINENO} (exit $?)"
      echo "!! THIS NODE IS NOT PREPARED. Do not run master.sh on it."
      echo "!! =================================================="' ERR

BOOTSTRAP_START=$(date +%s)

# Kubernetes version for a fresh, disposable Ubuntu 24.04 node.
# Normal CKA lab: v1.37. Week 8's upgrade SOURCE fixture: v1.36.
# Pass K8S_MINOR=v1.36 in the cloud-init/root process environment for that fixture.
# K8S_PKG pins an exact apt package version within the selected minor; omit it
# to receive the newest patch available from that minor-specific repository.
#   apt-cache madison kubeadm  # inspect actual package versions
# These overrides let Terraform/cloud-init choose a minor without editing this file.
: "${K8S_MINOR:=v1.37}"
: "${K8S_PKG:=}"
: "${CONTAINERD_PKG:=}"  # optional exact containerd.io apt package version
YQ_VERSION="v4.44.3"

case "$K8S_MINOR" in
  v1.36|v1.37) ;;
  *) echo "!! Unsupported fixture K8S_MINOR=$K8S_MINOR (expected v1.36 or v1.37)"; exit 1 ;;
esac

# Never run a node-preparation script over a joined or initialized cluster node.
if [[ -f /etc/kubernetes/kubelet.conf || -f /etc/kubernetes/admin.conf ]]; then
  echo '!! This node already has Kubernetes credentials. Use the kubeadm upgrade procedure instead.'
  exit 1
fi

# ---------------------------------------------------------------------------
# 0. Retry helper
#    Every network call below can fail transiently. On a 3-hour playground one
#    flaky apt mirror or GitHub hiccup otherwise costs you the whole session,
#    and you find out ten minutes later on the wrong host.
# ---------------------------------------------------------------------------

retry() {
  local n=0 max=5 delay=5
  until "$@"; do
    n=$((n + 1))
    if [ "$n" -ge "$max" ]; then
      echo "!! giving up after ${max} attempts: $*"
      return 1
    fi
    echo "   retry ${n}/${max} in ${delay}s: $*"
    sleep "$delay"
  done
}

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

# Verify the prerequisites actually took.
#
# This is the most important check in the file, because this whole family of
# settings fails SILENTLY. With bridge-nf-call-iptables unset the cluster
# builds, every node reports Ready, endpoints populate, iptables rules appear --
# and Services simply do not work, with nothing in any log. Better to refuse to
# finish the bootstrap than to hand you a cluster that lies to you.
echo "==> Verifying node prerequisites"
prereq_fail=0
lsmod | grep -q '^overlay'      || { echo "!! overlay module not loaded";      prereq_fail=1; }
lsmod | grep -q '^br_netfilter' || { echo "!! br_netfilter module not loaded"; prereq_fail=1; }
[ "$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || echo 0)" = "1" ] \
  || { echo "!! bridge-nf-call-iptables != 1 (Services would silently fail)"; prereq_fail=1; }
[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" = "1" ] \
  || { echo "!! ip_forward != 1 (cross-node pod traffic would fail)"; prereq_fail=1; }
[ -z "$(swapon --show)" ] \
  || { echo "!! swap still enabled (kubelet will refuse to start)"; prereq_fail=1; }
[ "$prereq_fail" -eq 0 ] || { echo "!! node prerequisites FAILED"; exit 1; }
echo "    ok: overlay, br_netfilter, bridge-nf-call-iptables, ip_forward, swap off"

# Kubernetes v1.37 needs a usable cgroup v2 host; inspect explicitly rather
# than discovering a kubelet startup failure much later.
if [[ "$(stat -fc %T /sys/fs/cgroup)" != "cgroup2fs" ]]; then
  echo "!! cgroup v2 required for this lab; /sys/fs/cgroup is not cgroup2fs"
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Exam-parity tooling
#    The CKA exam pre-installs kubectl (aliased to k, with completion), yq,
#    curl, wget and man on task hosts. Keep the exam-like shell behaviour,
#    but remember this lab also adds helpers (Helm, jq, etcd-client, etc.).
# ---------------------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

# MUST come BEFORE the installs below. Ubuntu cloud images ship a dpkg
# path-exclude that drops /usr/share/man/* as packages unpack. Removing the
# exclusion afterwards is too late: man-db and manpages would already have been
# unpacked WITHOUT their pages, so `man` exists and `man kubectl` comes up empty
# -- on a host where the exam has both. Full parity for the base image would
# need `unminimize`, which is far too slow for a lab you rebuild constantly.
rm -f /etc/dpkg/dpkg.cfg.d/excludes || true

echo "==> Base packages"
retry apt-get update -y
retry apt-get install -y \
  apt-transport-https ca-certificates curl wget gpg jq \
  bash-completion vim less tree \
  man-db manpages \
  etcd-client

echo "==> yq (mikefarah build — the one the exam has)"
retry curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
  -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq

echo "==> helm (curriculum: 'Use Helm and Kustomize to install cluster components')"
# Note: this installer tracks helm's main branch and is not pinned. If helm ever
# changes the script, bootstrap breaks here -- and the trap above will say so.
retry bash -c 'curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash' 

# ---------------------------------------------------------------------------
# 3. containerd
# ---------------------------------------------------------------------------

echo "==> containerd (CRI v1; supported 2.3.x / 2.4.x baseline)"
# Ubuntu's unversioned 'containerd' package can select a 1.x release. Use the
# separately signed Docker APT repository for the 'containerd.io' package only.
# Docker Engine itself is NOT installed on these Kubernetes nodes.
. /etc/os-release
if [[ "${ID}" != "ubuntu" || "${VERSION_ID}" != "24.04" ]]; then
  echo "!! This lab's containerd repository instructions target Ubuntu 24.04 only."
  exit 1
fi
install -m 0755 -d /etc/apt/keyrings
retry curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-${VERSION_CODENAME}}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
retry apt-get update -y
containerd_candidate=$(apt-cache policy containerd.io | awk '/Candidate:/ { print $2 }')
selected_containerd="${CONTAINERD_PKG:-$containerd_candidate}"
if [[ -z "$selected_containerd" || "$selected_containerd" == "(none)" ]] ||
   ! dpkg --compare-versions "$selected_containerd" ge '2.3.0' ||
   ! dpkg --compare-versions "$selected_containerd" lt '3.0.0'; then
  echo "!! containerd.io 2.3.x/2.4.x required; selected package is: $selected_containerd"
  echo "!! Check: apt-cache madison containerd.io"
  exit 1
fi
retry apt-get install -y "containerd.io=$selected_containerd"
installed_containerd=$(containerd --version | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if ! dpkg --compare-versions "${installed_containerd#v}" ge '2.3.0' ||
   ! dpkg --compare-versions "${installed_containerd#v}" lt '3.0.0'; then
  echo "!! Unsupported installed containerd version: $installed_containerd"
  exit 1
fi

mkdir -p /etc/containerd
# Fresh-node baseline only (this script refuses an initialized/joined node).
containerd config default > /etc/containerd/config.toml
# containerd 2.x uses version=3 and the io.containerd.cri.v1.runtime plugin.
if ! grep -Fq 'io.containerd.cri.v1.runtime' /etc/containerd/config.toml ||
   ! grep -Eq '^[[:space:]]*version[[:space:]]*=[[:space:]]*3' /etc/containerd/config.toml ||
   ! grep -Eq '^[[:space:]]*SystemdCgroup[[:space:]]*=[[:space:]]*false' /etc/containerd/config.toml; then
  echo "!! Unexpected containerd 2.x default config format; inspect config.toml."
  exit 1
fi
sed -i -E 's/^([[:space:]]*SystemdCgroup[[:space:]]*=[[:space:]]*)false/\1true/' /etc/containerd/config.toml
if ! grep -Eq '^[[:space:]]*SystemdCgroup[[:space:]]*=[[:space:]]*true' /etc/containerd/config.toml; then
  echo "!! containerd runc SystemdCgroup was not enabled."
  exit 1
fi
systemctl enable --now containerd
systemctl restart containerd

# ---------------------------------------------------------------------------
# 4. Kubernetes
# ---------------------------------------------------------------------------

echo "==> Kubernetes ${K8S_MINOR}"
mkdir -p /etc/apt/keyrings
retry bash -c "curl -fsSL 'https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key' \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

retry apt-get update -y
if [ -n "${K8S_PKG}" ]; then
  echo "==> pinning patch ${K8S_PKG}"
  retry apt-get install -y \
    kubelet="${K8S_PKG}" \
    kubeadm="${K8S_PKG}" \
    kubectl="${K8S_PKG}" \
    cri-tools
else
  # No pin: newest patch available in the K8S_MINOR repo.
  retry apt-get install -y kubelet kubeadm kubectl cri-tools
fi

echo "==> installed $(kubeadm version -o short)"
apt-mark hold kubelet kubeadm kubectl

crictl config runtime-endpoint unix:///run/containerd/containerd.sock
crictl config image-endpoint unix:///run/containerd/containerd.sock

# Validate the CRI API after crictl becomes available, not just the systemd service.
if ! timeout 20 crictl info >/dev/null 2>&1; then
  echo "!! CRI v1 endpoint is not responding: unix:///run/containerd/containerd.sock"
  systemctl status containerd --no-pager || true
  exit 1
fi
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

BOOTSTRAP_SECS=$(( $(date +%s) - BOOTSTRAP_START ))

echo
echo "===================================================="
echo " Node prepared: $(hostname)   in ${BOOTSTRAP_SECS}s"
kubeadm version -o short
echo " containerd $(containerd --version | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
echo " helm       $(helm version --short 2>/dev/null || echo 'n/a')"
echo " yq         $(yq --version 2>/dev/null || echo 'n/a')"
echo " etcdctl    $(etcdctl version 2>/dev/null | head -1 || echo 'n/a')"
echo "===================================================="
