#!/usr/bin/env bash
# One version, stamped in several places. This fails when any of them drifts
# from VERSION: the modules' local.socle_version, the bootstrap envelope's
# chart version, which the helm provider uses to decide whether to re-apply,
# and the release-please manifest. release-please writes them all in its
# release PR (the `# x-release-please-version` lines); this is the net under it.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
want="$(tr -d '[:space:]' < VERSION)"
fail=0
for f in opentofu/*/main.tf; do
  got="$(sed -n 's/^ *socle_version *= *"\([^"]*\)".*/\1/p' "$f" | head -1)"
  [ -n "$got" ] || continue
  if [ "$got" != "$want" ]; then
    echo "::error file=$f::local.socle_version is $got, VERSION is $want"
    fail=1
  fi
done
chart=opentofu/bootstrap/manifests/Chart.yaml
if [ -f "$chart" ]; then
  # `version: X.Y.Z # x-release-please-version` — the annotation is stripped.
  got="$(sed -n -E 's/^version: *"?([0-9][^" #]*)"?( *#.*)?$/\1/p' "$chart")"
  if [ "$got" != "$want" ]; then
    echo "::error file=$chart::chart version is $got, VERSION is $want"
    fail=1
  fi
fi
manifest=.release-please-manifest.json
if [ -f "$manifest" ]; then
  got="$(python3 -c 'import sys,json; print(json.load(open(sys.argv[1]))["."])' "$manifest")"
  if [ "$got" != "$want" ]; then
    echo "::error file=$manifest::release-please manifest says $got, VERSION is $want"
    fail=1
  fi
fi
[ "$fail" = 0 ] && echo "VERSION $want is consistent"
exit "$fail"
