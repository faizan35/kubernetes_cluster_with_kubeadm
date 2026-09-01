variable "aws_region" {
  type        = string
  description = "AWS region. KodeKloud playground usually hands you us-east-1."
  default     = "us-east-1"
}

variable "cluster_name" {
  type        = string
  description = "Prefix for all resource names."
  default     = "cka"
}

# ---------------------------------------------------------------------------
# Access
# ---------------------------------------------------------------------------

variable "allowed_cidr" {
  type        = string
  description = <<-EOT
    Your public IP in CIDR form, e.g. "203.0.113.4/32".
    Find it with: curl -s ifconfig.me
    Leave as 0.0.0.0/0 only for short-lived playground accounts.
  EOT
  default     = "0.0.0.0/0"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Public key registered with AWS for your own SSH access."
  default     = "~/.ssh/kubeadm-lab.pub"
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------


variable "instance_ami" {
  type        = string
  description = "AMI for all instances. Looked up, not hardcoded. AMI IDs are region-specific and get deprecated, and a playground account may hand you a different region."
}

variable "base_instance_type" {
  type        = string
  description = "The base jump host runs nothing but SSH. t3.micro is plenty."
  default     = "t3.micro"
}

variable "instance_type" {
  type        = string
  description = "Control plane needs 2 vCPU minimum (kubeadm hard requirement). t3.medium is cheaper and faster than t2.medium."
  default     = "t3.medium"
}

variable "worker_count" {
  type        = number
  description = <<-EOT
    Number of worker nodes.
    1 = enough for most of the plan.
    2 = lets you practise drain properly (workloads relocate somewhere).
  EOT
  default     = 1

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 3
    error_message = "worker_count must be between 1 and 3."
  }
}

variable "root_volume_size" {
  type        = number
  description = "GB. 30 is comfortable for images plus etcd plus logs."
  default     = 30
}

# ---------------------------------------------------------------------------
# Kubernetes
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  type        = string
  description = <<-EOT
    VPC CIDR. Must NOT overlap the pod network CIDR that master.sh passes to
    `kubeadm init` (192.168.0.0/16 for Calico). If you change the pod CIDR in
    master.sh, make sure it still does not collide with this.
  EOT
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type        = string
  description = "Subnet CIDR inside the VPC."
  default     = "10.0.1.0/24"
}
