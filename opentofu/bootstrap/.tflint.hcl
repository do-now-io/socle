# This module targets no cloud, so there is no provider ruleset to add: the
# recommended terraform preset is the whole of it. What a provider ruleset
# would have caught here — a chart that does not exist, a value key the chart
# ignores — no linter checks anyway. `tofu test` covers the interface, and the
# first real apply covers the rest.

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
