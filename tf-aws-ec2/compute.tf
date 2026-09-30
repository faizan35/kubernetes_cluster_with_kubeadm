# ---------------------------------------------------------------------------
# AMI — two modes, no code editing needed to switch
# ---------------------------------------------------------------------------
#   var.instance_ami = "ami-0b6d..."  -> use that ID directly. No API lookup,
#                                        fastest apply. This is the lab default.
#   var.instance_ami = ""             -> look up the latest Ubuntu 24.04 AMI
#                                        for whatever region you are in.

data "aws_ami" "ubuntu" {
  count = var.instance_ami == "" ? 1 : 0

  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

locals {
  ami_id = var.instance_ami != "" ? var.instance_ami : data.aws_ami.ubuntu[0].id
}

# ---------------------------------------------------------------------------
# Keys
# ---------------------------------------------------------------------------

# Your key. Registered with AWS so you can SSH from your laptop to base.
resource "aws_key_pair" "lab" {
  key_name   = "${var.cluster_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# Throwaway key for base -> node SSH. Regenerated on every apply.
# The PRIVATE half goes only to base. Cluster nodes get the public half only,
# which is what makes nested SSH fail here exactly as it does in the exam.
resource "tls_private_key" "cluster" {
  algorithm = "ED25519"
}

# ---------------------------------------------------------------------------
# base — the jump host
# ---------------------------------------------------------------------------
# No kubectl, no cluster tools, no Kubernetes packages. Same as the exam's
# base system. This is where every task starts.

resource "aws_instance" "base" {
  ami                    = local.ami_id
  instance_type          = var.base_instance_type
  subnet_id              = aws_subnet.main.id
  private_ip             = local.base_ip
  vpc_security_group_ids = [aws_security_group.cluster.id]
  key_name               = aws_key_pair.lab.key_name

  # WITHOUT THIS, EDITING scripts/*.sh SILENTLY DOES NOTHING.
  #
  # Since AWS provider 4.x, a user_data change does NOT replace the instance --
  # it updates the attribute and stops/starts the machine. cloud-init runs
  # per-instance, so it will not re-execute on that reboot. You get a clean
  # `terraform apply` and a node still configured by the OLD script.
  #
  # All node setup here is first-boot work, so a script change must mean a new
  # instance. Week 5's upgrade lab (edit K8S_MINOR, rebuild) depends on this.
  user_data_replace_on_change = true

  # EC2 caps user data at 16 KB. The rendered script -- this template plus
  # master.sh, worker.sh and common.sh inlined -- lands within a few BYTES of
  # that, so "cp" fits and "node01" does not, purely because the hostname is
  # four characters longer. Any comment added to any of those scripts breaks
  # provisioning with a wall-of-text error that does not mention size.
  #
  # base64gzip takes it to roughly half the limit. cloud-init detects the gzip
  # magic bytes and decompresses before running it, so nothing else changes.
  user_data_base64 = base64gzip(templatefile("${path.module}/templates/user-data.sh.tftpl", merge(
    local.user_data_common,
    {
      node_name           = local.base_name
      cluster_private_key = tls_private_key.cluster.private_key_openssh
      is_jump_host        = true
    }
  )))

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.cluster_name}-${local.base_name}"
    Role = "jump-host"
  }
}

# ---------------------------------------------------------------------------
# Control plane
# ---------------------------------------------------------------------------

resource "aws_instance" "control_plane" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.main.id
  private_ip             = local.control_plane_ip
  vpc_security_group_ids = [aws_security_group.cluster.id]
  key_name               = aws_key_pair.lab.key_name

  # WITHOUT THIS, EDITING scripts/*.sh SILENTLY DOES NOTHING.
  #
  # Since AWS provider 4.x, a user_data change does NOT replace the instance --
  # it updates the attribute and stops/starts the machine. cloud-init runs
  # per-instance, so it will not re-execute on that reboot. You get a clean
  # `terraform apply` and a node still configured by the OLD script.
  #
  # All node setup here is first-boot work, so a script change must mean a new
  # instance. Week 5's upgrade lab (edit K8S_MINOR, rebuild) depends on this.
  user_data_replace_on_change = true

  # EC2 caps user data at 16 KB. The rendered script -- this template plus
  # master.sh, worker.sh and common.sh inlined -- lands within a few BYTES of
  # that, so "cp" fits and "node01" does not, purely because the hostname is
  # four characters longer. Any comment added to any of those scripts breaks
  # provisioning with a wall-of-text error that does not mention size.
  #
  # base64gzip takes it to roughly half the limit. cloud-init detects the gzip
  # magic bytes and decompresses before running it, so nothing else changes.
  user_data_base64 = base64gzip(templatefile("${path.module}/templates/user-data.sh.tftpl", merge(
    local.user_data_common,
    {
      node_name           = local.control_plane_name
      cluster_private_key = "" # nodes never hold the private half
      is_jump_host        = false
    }
  )))

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.cluster_name}-${local.control_plane_name}"
    Role = "control-plane"
  }
}

# ---------------------------------------------------------------------------
# Workers
# ---------------------------------------------------------------------------

resource "aws_instance" "worker" {
  count = var.worker_count

  ami                    = local.ami_id
  instance_type          = var.worker_instance_type
  subnet_id              = aws_subnet.main.id
  private_ip             = local.worker_ips[count.index]
  vpc_security_group_ids = [aws_security_group.cluster.id]
  key_name               = aws_key_pair.lab.key_name

  # WITHOUT THIS, EDITING scripts/*.sh SILENTLY DOES NOTHING.
  #
  # Since AWS provider 4.x, a user_data change does NOT replace the instance --
  # it updates the attribute and stops/starts the machine. cloud-init runs
  # per-instance, so it will not re-execute on that reboot. You get a clean
  # `terraform apply` and a node still configured by the OLD script.
  #
  # All node setup here is first-boot work, so a script change must mean a new
  # instance. Week 5's upgrade lab (edit K8S_MINOR, rebuild) depends on this.
  user_data_replace_on_change = true

  # EC2 caps user data at 16 KB. The rendered script -- this template plus
  # master.sh, worker.sh and common.sh inlined -- lands within a few BYTES of
  # that, so "cp" fits and "node01" does not, purely because the hostname is
  # four characters longer. Any comment added to any of those scripts breaks
  # provisioning with a wall-of-text error that does not mention size.
  #
  # base64gzip takes it to roughly half the limit. cloud-init detects the gzip
  # magic bytes and decompresses before running it, so nothing else changes.
  user_data_base64 = base64gzip(templatefile("${path.module}/templates/user-data.sh.tftpl", merge(
    local.user_data_common,
    {
      node_name           = local.worker_names[count.index]
      cluster_private_key = ""
      is_jump_host        = false
    }
  )))

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.cluster_name}-${local.worker_names[count.index]}"
    Role = "worker"
  }
}
