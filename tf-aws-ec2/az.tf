# ---------------------------------------------------------------------------
# Availability Zone selection
# ---------------------------------------------------------------------------
# Not every AZ offers every instance type. us-east-1e, for example, has no t3
# capacity at all. If the subnet is left unpinned, AWS may place it there and
# every RunInstances call fails with:
#
#   Unsupported: Your requested instance type (t3.medium) is not supported in
#   your requested Availability Zone (us-east-1e).
#
# So rather than hardcoding "us-east-1a" and hoping, ask the API which AZs
# actually offer the instance types this config uses, and take one that
# supports ALL THREE: control plane, workers, and the base host.

data "aws_ec2_instance_type_offerings" "control_plane" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

data "aws_ec2_instance_type_offerings" "worker_nodes" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.worker_instance_type]
  }
}

data "aws_ec2_instance_type_offerings" "base_host" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.base_instance_type]
  }
}

# Only AZs that can run ALL of them are usable.
#
# Note: a single data source with multiple filter values would OR them, not AND
# them -- it returns AZs offering *any* of the types. Three separate lookups
# intersected is the only way to get "supports all of these".
locals {
  supported_azs = sort(tolist(setintersection(
    toset(data.aws_ec2_instance_type_offerings.control_plane.locations),
    toset(data.aws_ec2_instance_type_offerings.worker_nodes.locations),
    toset(data.aws_ec2_instance_type_offerings.base_host.locations)
  )))

  availability_zone = var.availability_zone != "" ? var.availability_zone : (
    length(local.supported_azs) > 0 ? local.supported_azs[0] : ""
  )
}

# ---------------------------------------------------------------------------
# Why there is no `check` block here
# ---------------------------------------------------------------------------
# A `check` block was the obvious home for this assertion, but check blocks
# emit WARNINGS, not errors -- the apply continues regardless. If no AZ
# qualified, local.availability_zone would be "", aws_subnet would fall back to
# letting AWS choose an AZ, and you would land in exactly the us-east-1e
# situation this file exists to prevent, with a warning you scrolled past.
#
# The assertion lives in network.tf as a lifecycle precondition on the subnet,
# which HALTS the apply. `check` = continuous validation, advisory.
# `precondition` = assertion, blocking.
