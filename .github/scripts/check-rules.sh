#!/usr/bin/env bash
# The socle's own alerting rules ship as VMRules under
# oci/catalog/<module>/rules/ and oci/catalog/<module>/monitoring/ (with the
# awesome-prometheus-alerts copies); the stack's come from upstream at pinned tags
# (docs/catalog/monitoring.md). The operator checks a VMRule before vmalert
# reads it, and refuses one that does not load — a rule the socle ships that
# never fires — so every file is checked here, on its own, with vmalert's own
# -dryRun, before the artifact is published. VMALERT names the binary; yq
# (mikefarah, on the runners) reads the YAML.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
vmalert="${VMALERT:-vmalert-prod}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
checked=0 fail=0
for f in oci/catalog/*/rules/*.yaml oci/catalog/*/monitoring/*.yaml; do
  [ -e "$f" ] || continue
  [ "$(yq '.kind' "$f")" = VMRule ] || continue
  module="$(basename "$(dirname "$(dirname "$f")")")"
  name="$(yq '.metadata.name' "$f")"
  yq '{"groups": .spec.groups}' "$f" > "$tmp/$module-$name.yaml"
  if "$vmalert" -dryRun -rule="$tmp/$module-$name.yaml" > "$tmp/log" 2>&1; then
    checked=$((checked + 1))
  else
    echo "::error file=$f::$name does not load in vmalert: $(grep -m1 -i -E 'fatal|error' "$tmp/log")"
    fail=1
  fi
done
[ "$fail" = 0 ] || exit 1
echo "vmalert -dryRun: $checked VMRule(s), every one loads. ✅"
