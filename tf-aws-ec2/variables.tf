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

variable "availability_zone" {
  type        = string
  description = <<-EOT
    Leave empty to auto-select an AZ that supports BOTH instance types.
    Set explicitly (e.g. "us-east-1a") only if you need a specific one.
    Never leave the subnet unpinned -- AWS may place it in an AZ with no t3
    capacity (us-east-1e), and every instance will fail to launch.
  EOT
  default     = ""
}

variable "instance_ami" {
  type        = string
  description = <<-EOT
    AMI for all instances.

    Set an ID (e.g. "ami-0b6d9d3d33ba97d99") to skip the AMI lookup entirely --
    fastest apply, and fine for a lab where you control the region.

    Set to "" to auto-look-up the latest Ubuntu 24.04 AMI for the current
    region instead. Do that if you switch regions or the pinned AMI is
    deprecated (symptom on apply: "InvalidAMIID.NotFound").

    AMI IDs are REGION-SPECIFIC. An ID valid in us-east-1 will not exist in
    eu-west-1, and the failure message does not spell that out.
  EOT
  default     = "ami-0b6d9d3d33ba97d99" # Ubuntu 24.04, us-east-1

  validation {
    condition     = var.instance_ami == "" || can(regex("^ami-[0-9a-f]{8,17}$", var.instance_ami))
    error_message = "instance_ami must be empty (to auto-look-up) or a valid AMI ID like ami-0b6d9d3d33ba97d99."
  }
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
