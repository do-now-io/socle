# The generic ruleset alone catches almost nothing cloud-specific, so each
# module carries its cloud's provider plugin.

plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
