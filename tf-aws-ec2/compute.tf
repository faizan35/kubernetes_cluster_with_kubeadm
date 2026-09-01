# ---------------------------------------------------------------------------
# AMI
# ---------------------------------------------------------------------------
# Looked up, not hardcoded. AMI IDs are region-specific and get deprecated,
# and a playground account may hand you a different region.

# data "aws_ami" "ubuntu" {
#   most_recent = true
#   owners      = ["099720109477"] # Canonical

#   filter {
#     name   = "name"
#     values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
#   }

#   filter {
#     name   = "virtualization-type"
#     values = ["hvm"]
#   }

#   filter {
#     name   = "root-device-type"
#     values = ["ebs"]
#   }
# }

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
  ami                    = var.instance_ami
  instance_type          = var.base_instance_type
  subnet_id              = aws_subnet.main.id
  private_ip             = local.base_ip
  vpc_security_group_ids = [aws_security_group.cluster.id]
  key_name               = aws_key_pair.lab.key_name

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", merge(
    local.user_data_common,
    {
      node_name           = local.base_name
      cluster_private_key = tls_private_key.cluster.private_key_openssh
      is_jump_host        = true
    }
  ))

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
  ami                    = var.instance_ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.main.id
  private_ip             = local.control_plane_ip
  vpc_security_group_ids = [aws_security_group.cluster.id]
  key_name               = aws_key_pair.lab.key_name

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", merge(
    local.user_data_common,
    {
      node_name           = local.control_plane_name
      cluster_private_key = "" # nodes never hold the private half
      is_jump_host        = false
    }
  ))

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

  ami                    = var.instance_ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.main.id
  private_ip             = local.worker_ips[count.index]
  vpc_security_group_ids = [aws_security_group.cluster.id]
  key_name               = aws_key_pair.lab.key_name

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", merge(
    local.user_data_common,
    {
      node_name           = local.worker_names[count.index]
      cluster_private_key = ""
      is_jump_host        = false
    }
  ))

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
