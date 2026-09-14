# The generic ruleset alone catches almost nothing cloud-specific, so each
# module carries its cloud's provider plugin.
#
# Scaleway is the exception the conformance checklist has to record: there is
# no tflint-ruleset-scaleway, from terraform-linters or anyone else. The
# recommended terraform preset is what is available, and the module leans
# harder on `tofu test` to cover what a provider ruleset would have caught.

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
