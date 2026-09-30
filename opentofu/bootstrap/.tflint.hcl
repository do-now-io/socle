# helm carries everything that runs in the cluster; aws creates the EKS
# add-ons and their roles (eks_addons.tf), so the aws ruleset applies too.

plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
