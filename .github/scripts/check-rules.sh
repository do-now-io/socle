#!/usr/bin/env bash
# The socle's alerting rules ship as ConfigMaps labelled vmalert_rules, under
# oci/catalog/<module>/rules/. vmalert reads its rule files all or nothing —
# one bad file freezes every rule change, and stops it from starting at all
# (docs/catalog/alerting.md, measured) — so every file is checked here, on
# its own, with vmalert's own -dryRun, before the artifact is published.
# VMALERT names the binary; yq (mikefarah, on the runners) reads the YAML.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
vmalert="${VMALERT:-vmalert-prod}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
checked=0 fail=0
for f in oci/catalog/*/rules/*.yaml; do
  [ -e "$f" ] || continue
  [ "$(yq '.kind' "$f")" = ConfigMap ] || continue
  [ "$(yq '.metadata.labels.vmalert_rules' "$f")" = 1 ] || continue
  module="$(basename "$(dirname "$(dirname "$f")")")"
  while IFS= read -r key; do
    yq ".data[\"$key\"]" "$f" > "$tmp/$module-$key"
    if "$vmalert" -dryRun -rule="$tmp/$module-$key" > "$tmp/log" 2>&1; then
      checked=$((checked + 1))
    else
      echo "::error file=$f::$key does not load in vmalert: $(grep -m1 -i -E 'fatal|error' "$tmp/log")"
      fail=1
    fi
  done < <(yq '.data | keys | .[]' "$f")
done
[ "$fail" = 0 ] || exit 1
echo "vmalert -dryRun: $checked rule file(s), every one loads. ✅"
