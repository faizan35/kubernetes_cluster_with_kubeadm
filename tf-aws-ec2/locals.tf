locals {
  # Static private IPs so a complete /etc/hosts can be baked into every node at
  # boot. This is what makes `ssh cp` and `ssh node01` work by name from base,
  # matching the exam, where every task names a host you must SSH to.
  #
  # AWS reserves the first four addresses in a subnet, so start at .5 / .10.
  base_ip          = cidrhost(var.subnet_cidr, 5)
  control_plane_ip = cidrhost(var.subnet_cidr, 10)
  worker_ips       = [for i in range(var.worker_count) : cidrhost(var.subnet_cidr, 11 + i)]

  base_name          = "base"
  control_plane_name = "cp"
  worker_names       = [for i in range(var.worker_count) : format("node%02d", i + 1)]

  hosts_entries = join("\n", concat(
    ["${local.base_ip} ${local.base_name}"],
    ["${local.control_plane_ip} ${local.control_plane_name}"],
    [for i, ip in local.worker_ips : "${ip} ${local.worker_names[i]}"]
  ))

  # Scripts injected into user_data. common.sh runs during boot on cluster
  # nodes; master.sh and worker.sh are written to /home/ubuntu to run by hand.
  common_sh = file("${path.module}/../scripts/common.sh")

  # --- Ansible (this branch) --------------------------------------------
  # Inventory is fully known at plan time because node IPs are static, so it
  # can be baked into base's user_data rather than generated at runtime.
  ansible_inventory = join("\n", concat(
    ["[control_plane]"],
    ["${local.control_plane_name} ansible_host=${local.control_plane_ip}"],
    [""],
    ["[workers]"],
    [for i, ip in local.worker_ips : "${local.worker_names[i]} ansible_host=${ip}"],
    [""],
    ["[cluster:children]", "control_plane", "workers"],
    [""],
    ["[all:vars]", "ansible_user=ubuntu", "ansible_ssh_private_key_file=/home/ubuntu/.ssh/id_ed25519"]
  ))

  ansible_cfg      = file("${path.module}/../ansible/ansible.cfg")
  ansible_site_yml = file("${path.module}/../ansible/site.yml")
  ansible_all_vars = file("${path.module}/../ansible/group_vars/all.yml")
  master_sh = file("${path.module}/../scripts/master.sh")
  worker_sh = file("${path.module}/../scripts/worker.sh")

  # Shared by every instance's user_data render.
  user_data_common = {
    ansible_inventory  = local.ansible_inventory
    ansible_cfg        = local.ansible_cfg
    ansible_site_yml   = local.ansible_site_yml
    ansible_all_vars   = local.ansible_all_vars
    hosts_entries      = local.hosts_entries
    cluster_public_key = trimspace(tls_private_key.cluster.public_key_openssh)
    common_sh          = local.common_sh
    master_sh          = local.master_sh
    worker_sh          = local.worker_sh
  }
}
