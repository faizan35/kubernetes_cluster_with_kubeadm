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
# supports BOTH the cluster nodes and the base host.

data "aws_ec2_instance_type_offerings" "cluster_nodes" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

data "aws_ec2_instance_type_offerings" "base_host" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.base_instance_type]
  }
}

# Only AZs that can run BOTH types are usable.
locals {
  supported_azs = sort(tolist(setintersection(
    toset(data.aws_ec2_instance_type_offerings.cluster_nodes.locations),
    toset(data.aws_ec2_instance_type_offerings.base_host.locations)
  )))

  availability_zone = var.availability_zone != "" ? var.availability_zone : (
    length(local.supported_azs) > 0 ? local.supported_azs[0] : ""
  )
}

# Fail early with a readable message rather than three cryptic RunInstances
# errors several minutes into the apply.
check "availability_zone_is_usable" {
  assert {
    condition     = local.availability_zone != ""
    error_message = <<-EOT
      No Availability Zone in ${var.aws_region} supports both
      "${var.instance_type}" (cluster nodes) and "${var.base_instance_type}" (base).
      Pick different instance types, or set availability_zone explicitly.
    EOT
  }
}
