resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true

  # Pinned deliberately. Left unset, AWS picks any AZ in the region -- and some
  # AZs (us-east-1e is the classic) offer no t3 instances at all, so every
  # RunInstances call fails with "instance type not supported in your
  # requested Availability Zone". See locals.tf: the AZ is computed from the
  # instance types you actually asked for.
  availability_zone = local.availability_zone

  # Blocking assertion. See the note at the bottom of az.tf for why this is a
  # precondition and not a `check` block: check blocks only warn, and a warning
  # here would let the apply proceed with AWS picking the AZ -- the precise
  # failure this whole mechanism exists to prevent.
  lifecycle {
    precondition {
      condition     = local.availability_zone != ""
      error_message = "No Availability Zone in ${var.aws_region} supports all of ${var.instance_type} (control plane), ${var.worker_instance_type} (workers) and ${var.base_instance_type} (base). Pick different instance types, or set availability_zone explicitly."
    }
  }

  tags = {
    Name = "${var.cluster_name}-subnet"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.cluster_name}-rt"
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.rt.id
}
