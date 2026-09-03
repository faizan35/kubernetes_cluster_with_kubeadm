# `ansible` branch — zero-touch cluster

Same lab as `main`, except **the cluster builds itself.** No `master.sh`, no copying join commands, no `worker.sh`. `terraform apply`, wait, and you have a Ready cluster.

---

## Which branch, which day

Keep both. They're for different things.

|                         | `main`                                  | `ansible`                            |
| ----------------------- | --------------------------------------- | ------------------------------------ |
| `kubeadm init` / `join` | **you type them**                       | Ansible runs them                    |
| Time to Ready           | ~15 min, hands-on                       | ~10–12 min, unattended               |
| Use it for              | days where **building is the exercise** | days where you just need _a_ cluster |

**Use `main` for:** W1 D3–D4 (build by hand, timed rebuilds), W1 D5–D6 (break the control plane, etcd), W2 D8–D9 (upgrades, certs, node lifecycle). On those days the manual steps _are_ the practice — automating them removes the thing you're there to learn.

**Use `ansible` for:** W2 D10–D13 (RBAC, Helm, CRDs), all of W3 (networking, storage), W4 D22–D26 (workloads, scheduling, app troubleshooting), W5 (mocks and repair). On those ~20 days the cluster is scaffolding, and hand-initialising it two or three times a day is 15 minutes of pure waste per session.

> `master.sh` and `worker.sh` are still on the nodes in this branch. If Ansible fails, or you want to do it by hand once, they're there.

---

## What changed from `main`

| File                                      | Change                                                                          |
| ----------------------------------------- | ------------------------------------------------------------------------------- |
| `ansible/ansible.cfg`                     | **new** — inventory path, no host key checking, pipelining                      |
| `ansible/group_vars/all.yml`              | **new** — pod CIDR, Calico version, token TTL                                   |
| `ansible/site.yml`                        | **new** — the four-play cluster build                                           |
| `tf-aws-ec2/locals.tf`                    | generates the inventory from the static node IPs; reads the three Ansible files |
| `tf-aws-ec2/templates/user-data.sh.tftpl` | base now installs `ansible-core`, writes `~/ansible/`, and runs the playbook    |
| `tf-aws-ec2/outputs.tf`                   | `next_steps` rewritten for the zero-touch flow                                  |

Everything else is byte-identical to `main`.

---

## How it works

Ansible runs **from `base`**, not from your laptop. base already holds the SSH key for every node, so there's nothing to configure — and it keeps the topology honest: your laptop still only ever talks to `base`.

The inventory is baked in at plan time rather than generated at runtime, because node IPs are static:

```ini
[control_plane]
cp ansible_host=10.0.1.10

[workers]
node01 ansible_host=10.0.1.11

[cluster:children]
control_plane
workers
```

`site.yml` runs four plays:

1. **Wait** — `wait_for_connection` on every node, then block on `/var/log/cka-bootstrap-done`, the marker `common.sh` writes when node prep finishes. This is what makes the whole thing race-free: Ansible never touches a node that's still installing Kubernetes.
2. **Control plane** — `kubeadm init`, kubeconfig for `ubuntu` _and_ `root`, Calico, wait for Ready, generate a join command.
3. **Workers** — `serial: 1`, and it reproduces the containerd fix from `worker.sh`: remove stale CNI config, restart containerd, **poll `crictl info` until it answers**, then join. Without that wait the join fires into a dead socket and fails with `connection refused`.
4. **Verify** — wait for all nodes Ready and CoreDNS rolled out. Fails loudly here rather than leaving you a half-built cluster you discover twenty minutes later.

### The nice consequence

Because the playbook runs at the end of base's cloud-init, this:

```bash
ssh -i ~/.ssh/kubeadm-lab ubuntu@$BASE_IP 'cloud-init status --wait'
```

returns only when the **cluster is Ready** — not merely when the VM booted. One command, one wait, then work.

---

## Usage

```bash
cd tf-aws-ec2
terraform init && terraform apply -auto-approve
terraform output next_steps

BASE_IP=$(terraform output -raw base_public_ip)

# returns when the CLUSTER is ready (~10-12 min)
ssh -i ~/.ssh/kubeadm-lab ubuntu@$BASE_IP 'cloud-init status --wait'

ssh -i ~/.ssh/kubeadm-lab ubuntu@$BASE_IP
ssh cp
kubectl get nodes -o wide
```

Watch it build:

```bash
ssh -i ~/.ssh/kubeadm-lab ubuntu@$BASE_IP 'sudo tail -f /var/log/cka-ansible.log'
```

---

## When it goes wrong

**Read the log first.** It's separate from cloud-init's so you're not wading through package installs:

```bash
sudo cat /var/log/cka-ansible.log
```

**Re-run it.** The playbook is idempotent — an initialised control plane and joined workers are skipped, not reset:

```bash
ssh base
cd ~/ansible && ansible-playbook site.yml
```

**Fall back to manual.** `~/master.sh` and `~/worker.sh` are still on the nodes.

**Check the marker.** `/var/log/cka-cluster-ready` exists only if the playbook completed:

```bash
ls -l /var/log/cka-cluster-ready
```

**Common causes:** a node's own cloud-init failed, so `/var/log/cka-bootstrap-done` never appeared and play 1 timed out after 15 minutes — check `/var/log/cka-bootstrap.log` on that node. Or the AMI/region mismatch from `main`, which fails earlier at `RunInstances`.

---

## One habit this does not build

On `main` you type `ssh cp`, run `master.sh`, copy a join command, `exit`, `ssh node01`, `worker.sh`, `exit` — which is exactly the exam's rhythm. This branch skips all of that.

**The SSH discipline still matters and still applies here.** Every task: `ssh <host>` → `hostname` → work → `exit`. Nested SSH still fails by design. But do your kubeadm reps on `main` — that's what it's for.
