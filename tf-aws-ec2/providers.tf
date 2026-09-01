provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "cka-lab"
      ManagedBy = "terraform"
      Ephemeral = "true"
    }
  }
}
