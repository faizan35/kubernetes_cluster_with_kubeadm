output "availability_zone" {
  description = "AZ chosen for the subnet (auto-selected unless overridden)"
  value       = local.availability_zone
}

output "base_public_ip" {
  description = "Public IP of the base jump host. This is your only entry point."
  value       = aws_instance.base.public_ip
}

output "control_plane_private_ip" {
  value = aws_instance.control_plane.private_ip
}

output "worker_private_ips" {
  value = aws_instance.worker[*].private_ip
}

output "ssh_base" {
  description = "SSH into base. Everything starts here."
  value       = "ssh -i ${replace(var.ssh_public_key_path, ".pub", "")} ubuntu@${aws_instance.base.public_ip}"
}

# Emergency access only. Using these routinely defeats the point of base.
output "direct_node_ips_break_glass" {
  description = "Public IPs of cluster nodes, for debugging a broken bootstrap only"
  value = {
    cp = aws_instance.control_plane.public_ip
    workers = { for i, ip in aws_instance.worker[*].public_ip :
    local.worker_names[i] => ip }
  }
}

output "next_steps" {
  value = <<-EOT

    ┌──────────────────────────────────────────────────────────────────────┐
    │  CKA lab — ANSIBLE branch (cluster builds itself)                    │
    └──────────────────────────────────────────────────────────────────────┘

      base    ${aws_instance.base.private_ip}    jump host, NO kubectl (public ${aws_instance.base.public_ip})
      cp      ${aws_instance.control_plane.private_ip}    control plane
    ${join("\n    ", [for i, ip in aws_instance.worker[*].private_ip : "  ${local.worker_names[i]}  ${ip}    worker"])}

    There are NO manual steps. base installs Ansible, waits for every node to
    finish its own bootstrap, then runs kubeadm init + join for you.

    1. Wait for the whole cluster (~10-12 min). This returns only when the
       cluster is genuinely Ready, not merely when the VM has booted:

       ssh -i ${replace(var.ssh_public_key_path, ".pub", "")} ubuntu@${aws_instance.base.public_ip} 'cloud-init status --wait'

       Watch it work, if you like:
       ssh -i ${replace(var.ssh_public_key_path, ".pub", "")} ubuntu@${aws_instance.base.public_ip} 'sudo tail -f /var/log/cka-ansible.log'

    2. Confirm it succeeded:

       ssh -i ${replace(var.ssh_public_key_path, ".pub", "")} ubuntu@${aws_instance.base.public_ip} 'ls /var/log/cka-cluster-ready'

    3. Use it. base is still your only entry point, same as the exam:

       ssh -i ${replace(var.ssh_public_key_path, ".pub", "")} ubuntu@${aws_instance.base.public_ip}
       ssh cp
       kubectl get nodes -o wide

    If Ansible failed:   sudo cat /var/log/cka-ansible.log
    Re-run it:           ssh base ; cd ~/ansible ; ansible-playbook site.yml
    Manual fallback:     ~/master.sh and ~/worker.sh are still on the nodes

    Tear down:           terraform destroy -auto-approve

  EOT
}
