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
    │  CKA lab provisioning — exam-shaped topology                         │
    └──────────────────────────────────────────────────────────────────────┘

      base    ${aws_instance.base.private_ip}    jump host, NO kubectl (public ${aws_instance.base.public_ip})
      cp      ${aws_instance.control_plane.private_ip}    control plane
    ${join("\n    ", [for i, ip in aws_instance.worker[*].private_ip : "  ${local.worker_names[i]}  ${ip}    worker"])}

    1. Wait for bootstrap (~4-5 min; nodes install k8s, helm, yq, etcdctl):

       ssh -i ${replace(var.ssh_public_key_path, ".pub", "")} ubuntu@${aws_instance.base.public_ip} 'cloud-init status --wait'

    2. SSH into base. This is your ONLY entry point, same as the exam:

       ssh -i ${replace(var.ssh_public_key_path, ".pub", "")} ubuntu@${aws_instance.base.public_ip}

    3. From base, initialise the control plane:

       ssh cp
       cloud-init status --wait        # make sure node prep finished
       bash ~/master.sh                # copy the join command
       exit                            # BACK TO BASE — nested ssh will fail

    4. From base, join each worker:

       ssh ${local.worker_names[0]}
       bash ~/worker.sh "<join command>"
       exit

    5. Verify from base:

       ssh cp
       kubectl get nodes -o wide       # all Ready, v1.35.x
       crictl version                  # containerd
       exit

    Bootstrap log:  sudo cat /var/log/cka-bootstrap.log
    Tear down:      terraform destroy -auto-approve

  EOT
}
