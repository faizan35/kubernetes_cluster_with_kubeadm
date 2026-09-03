# Usage

Step-by-step for standing up and using the CKA lab cluster.

## Topology you're about to build

```
   your laptop
        │  ssh (public IP)
        ▼
   ┌─────────┐
   │  base   │  10.0.1.5    jump host — NO kubectl, by design
   └─────────┘
        │  ssh cp / ssh node01  (by hostname, key already in place)
        ├──────────────┬──────────────┐
        ▼              ▼              ▼
   ┌─────────┐   ┌──────────┐   ┌──────────┐
   │   cp    │   │  node01  │   │  node02  │
   │10.0.1.10│   │10.0.1.11 │   │10.0.1.12 │
   └─────────┘   └──────────┘   └──────────┘
```

**`base` is your only entry point.** Nodes cannot SSH to each other — that's deliberate, and it mirrors the exam, which does not support nested SSH.

---

## Prerequisites

- **Terraform** >= 1.10
- **AWS credentials** configured — `aws configure`, or export the env vars your playground gives you
- **An SSH keypair**, created once:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/kubeadm-lab -N ""
```

That produces `~/.ssh/kubeadm-lab` (private, stays on your laptop) and `~/.ssh/kubeadm-lab.pub` (public, registered with AWS by Terraform).

---

## Step 1 — Configure

```bash
cd tf-aws-ec2
cp terraform.tfvars.example terraform.tfvars
```

Only three values are worth thinking about:

```hcl
aws_region   = "us-east-1"     # whatever your playground gives you
allowed_cidr = "0.0.0.0/0"     # tighten to "$(curl -s ifconfig.me)/32" if not ephemeral
worker_count = 1               # 2 if you want to practise `kubectl drain` properly
```

Everything else has a sensible default.

---

## Step 2 — Provision

```bash
terraform init
terraform apply -auto-approve
```

Takes about 3 minutes. Then:

```bash
terraform output next_steps
```

That prints your node table and the exact commands with real IPs substituted. Keep it on screen.

---

## Step 3 — Wait for bootstrap

Two different waits, and the second is the one people skip.

**3a. Wait for `base`** (~1–2 min — it installs almost nothing):

```bash
BASE_IP=$(terraform output -raw base_public_ip)
ssh -i ~/.ssh/kubeadm-lab ubuntu@$BASE_IP 'cloud-init status --wait'
```

If you get _Connection refused_, the instance is still booting. Wait 30 seconds and retry.

**3b. Wait for the cluster nodes** (~4–6 min — they install containerd, Kubernetes, helm, yq, etcdctl).

SSH into base first, then wait on each node from there:

```bash
ssh -i ~/.ssh/kubeadm-lab ubuntu@$BASE_IP

# now on base:
for h in cp node01; do
  until ssh -o ConnectTimeout=5 $h 'cloud-init status --wait' 2>/dev/null; do
    echo "waiting for $h..."; sleep 10
  done
  echo "$h ready"
done
```

> ⚠️ **Do not skip 3b.** Running `master.sh` before node prep finishes is the most common self-inflicted failure — `kubeadm` won't be installed yet and you'll get a confusing "command not found". A brief _Permission denied_ while waiting is also normal: the SSH key is written early in `user_data`, but there's a short window before it lands.

---

## Step 4 — Initialise the control plane

You're on `base`. Go to `cp`:

```bash
ssh cp
hostname          # confirm you're on cp — build this reflex now
bash ~/master.sh
```

Takes 2–3 minutes. At the end it prints a join command:

```
kubeadm join 10.0.1.10:6443 --token abc123.xxxxxxxx \
  --discovery-token-ca-cert-hash sha256:1a2b3c...
```

**Copy that whole line.** Then return to base:

```bash
exit
```

> `master.sh` refuses to run as root — it uses `sudo` internally. Run it as `ubuntu`.

---

## Step 5 — Join the workers

From **base** (not from `cp` — that would be nested SSH and it will fail):

```bash
ssh node01
bash ~/worker.sh "kubeadm join 10.0.1.10:6443 --token abc123.xxxxxxxx --discovery-token-ca-cert-hash sha256:1a2b3c..."
exit
```

**The quotes are required.** The join command contains spaces and won't survive unquoted.

Repeat for `node02` if you set `worker_count = 2`.

---

## Step 6 — Verify

From base, hop to `cp`:

```bash
ssh cp
```

**Basic health:**

```bash
kubectl get nodes -o wide         # all Ready, VERSION column reads v1.35.x
kubectl get pods -A               # CoreDNS Running, not Pending
```

**Exam-parity tooling** — confirm nothing is missing before you rely on it:

```bash
crictl version | grep -i runtime  # containerd, not cri-o
helm version --short
yq --version
etcdctl version | head -1
k get nodes                       # the `k` alias works
k get no<TAB>                     # completion works
```

**The checks that actually matter** — these prove the security group is right, and they're the failures that hide for days:

```bash
kubectl create deploy web --image=nginx --replicas=4
kubectl get pods -o wide                     # spread across cp and node01

kubectl logs deploy/web                      # must NOT hang  → port 10250 open
kubectl exec deploy/web -- echo ok           # must NOT hang  → port 10250 open

# cross-node pod-to-pod → proves Calico BGP/VXLAN is passing
POD_IP=$(kubectl get pod -o jsonpath='{.items[0].status.podIP}')
kubectl exec deploy/web -- curl -s --max-time 5 $POD_IP | head -3
```

If `kubectl logs` hangs, port 10250 is blocked. If cross-node curl times out but same-node works, Calico is blocked. Both point at the security group, not at Kubernetes.

Clean up the test:

```bash
kubectl delete deploy web
exit                              # back to base
```

---

## Daily session workflow

Once you've done it once, a session is four commands:

```bash
# laptop
cd tf-aws-ec2 && terraform apply -auto-approve
BASE_IP=$(terraform output -raw base_public_ip)
ssh -i ~/.ssh/kubeadm-lab ubuntu@$BASE_IP 'cloud-init status --wait'
ssh -i ~/.ssh/kubeadm-lab ubuntu@$BASE_IP

# on base
until ssh -o ConnectTimeout=5 cp 'cloud-init status --wait' 2>/dev/null; do sleep 10; done
ssh cp && bash ~/master.sh          # copy join command, then exit
ssh node01 && bash ~/worker.sh "<join>"   # then exit
```

**~12–15 minutes** to a working cluster, most of it waiting on AWS.

### The habit to build

Every task, without exception:

```bash
ssh <host>        # the host the task names
hostname          # confirm — 2 seconds, prevents scoring zero on correct work
sudo -i           # only if you need root
# ... work ...
exit              # leave root
exit              # BACK TO BASE before the next task
```

This is the single most transferable thing about practising on this topology.

---

## Resetting without rebuilding

Much faster than `terraform destroy`, and it's the same operation an exam task might ask for.

**Reset one node** (~90 seconds):

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d /etc/kubernetes $HOME/.kube
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
sudo systemctl restart containerd
```

**Rebuild the whole cluster** — reset `cp` and every worker, then re-run `master.sh` and `worker.sh`. About 5 minutes versus 15 for a full Terraform cycle.

> **Week 1 Days 3–4 of the study plan gate on building a cluster in under 40 minutes.** Use `kubeadm reset` for those timed rebuilds, not `terraform destroy` — you're practising kubeadm, not Terraform.

---

## Troubleshooting

**`Unsupported: Your requested instance type (t3.medium) is not supported in your requested Availability Zone (us-east-1e)`**

Not every AZ offers every instance type — `us-east-1e` has no t3 capacity at all. The config now asks the EC2 API which AZs support both your instance types and pins the subnet to one of them, so this shouldn't recur.

If you hit it on an older copy of the config, or want a specific AZ:

```hcl
# terraform.tfvars
availability_zone = "us-east-1a"
```

Then `terraform apply` again. Changing the AZ replaces the subnet, which is fine — the instances failed to create anyway. Confirm afterwards with `terraform output availability_zone`.

**`cloud-init status --wait` never returns**

```bash
sudo cat /var/log/cka-bootstrap.log      # our script's output
sudo cat /var/log/cloud-init-output.log  # everything cloud-init ran
```

**`ssh cp` from base says Permission denied**

Node prep hasn't written `authorized_keys` yet. Wait 30 seconds and retry. If it persists past 5 minutes, use break-glass access:

```bash
terraform output direct_node_ips_break_glass
ssh -i ~/.ssh/kubeadm-lab ubuntu@<cp-public-ip> 'sudo tail -50 /var/log/cka-bootstrap.log'
```

**`ssh node01` from `cp` fails**

That's correct behaviour. Nodes hold no private key, matching the exam's no-nested-SSH rule. `exit` to base first.

**kubelet crashlooping after `kubeadm init`**

Almost always the cgroup driver:

```bash
sudo journalctl -u kubelet -n 50 --no-pager
grep SystemdCgroup /etc/containerd/config.toml    # must be true
```

**CoreDNS stuck `Pending`**

No CNI yet. Expected before `master.sh` installs Calico; a real problem after.

**`kubectl logs` hangs on a worker pod**

Port 10250 blocked. Check the self-referencing security group rule exists.

**Cross-node pod-to-pod fails, same-node works**

Calico BGP/VXLAN blocked. Same rule.

**Worker won't join**

Check in order:

1. Reachability — `nc -zv 10.0.1.10 6443` from the worker
2. Token validity — `kubeadm token list` on `cp`
3. CA cert hash — regenerate the whole command with `kubeadm token create --print-join-command`

**`kubeadm join` fails with `CRI... connection refused`, but `sudo crictl ps` works fine seconds later**

Not a real failure — a timing race in `worker.sh`'s cleanup step. Deleting `/etc/cni/net.d` while containerd is running crashes it (containerd watches that directory), and systemd's auto-restart takes a few seconds. If the join attempt fires in that gap, it sees a dead socket. This was fixed by making `worker.sh` explicitly restart containerd and wait for `crictl info` to succeed before joining. If you're still hitting this, confirm you have the current `worker.sh` — check for the `Waiting for containerd to be ready` line near the top of its output. If that line is missing, redeploy from this repo. Otherwise just re-run the same command; it's idempotent.

**`kubectl` works as `ubuntu` but not under `sudo -i`**

`master.sh` copies the kubeconfig to `/root/.kube/config`. If you reset and re-ran `kubeadm init` manually, redo that copy.

---

## Teardown

```bash
cd tf-aws-ec2
terraform destroy -auto-approve
```

**Always run this on a real AWS account.** Two `t3.medium` instances plus a `t3.micro` left running cost real money. On a time-limited playground the account is reclaimed anyway, but keep the habit.

---

## Note on time-limited playgrounds

If you're on 3-hour AWS accounts, this setup fits some study-plan days far better than others.

**Works well** — anything where building or destroying _is_ the exercise: hand-building a cluster, timed rebuilds, breaking the control plane, etcd backup and restore, kubeadm upgrades. Rebuilding every session is the drill.

**Works badly** — the many days that assume you build once and then work: RBAC, Helm, Kustomize, CRDs, Services, CoreDNS, Ingress, Gateway API, NetworkPolicy, storage, scheduling. Losing state every three hours costs ~15 minutes of rebuild plus everything you'd set up.

For those days, a cheap always-on VPS (two small nodes, roughly €8–12/month) makes a better primary lab, with this Terraform reserved for the build-and-destroy days.
