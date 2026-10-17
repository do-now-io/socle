# The generic ruleset alone catches almost nothing cloud-specific, so each
# module carries its cloud's provider plugin.

plugin "google" {
  enabled = true
  version = "0.34.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
