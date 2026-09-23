#!/usr/bin/env bash
# The Gateway API CRDs the bootstrap module applies before Cilium are vendored
# verbatim (opentofu/bootstrap/gateway-api-crds/templates/standard-install.yaml).
# This fails when that file is not, byte for byte, the standard-channel asset
# of the release its Chart.yaml names — so a hand edit, a partial update or a
# version bump that forgot the file cannot pass review as "the upstream CRDs".
# It also fails when the chart and cilium.tf disagree on the version.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
chart=opentofu/bootstrap/gateway-api-crds
version="$(sed -n -E 's/^appVersion: *"?v?([0-9][^" #]*)"?( *#.*)?$/\1/p' "$chart/Chart.yaml")"
chart_version="$(sed -n -E 's/^version: *"?([0-9][^" #]*)"?( *#.*)?$/\1/p' "$chart/Chart.yaml")"
pinned="$(sed -n 's/^ *gateway_api_version *= *"\([^"]*\)".*/\1/p' opentofu/bootstrap/cilium.tf)"
fail=0
if [ "$version" != "$chart_version" ] || [ "$version" != "$pinned" ]; then
  echo "::error file=$chart/Chart.yaml::appVersion v$version, version $chart_version and cilium.tf's gateway_api_version $pinned must agree"
  fail=1
fi
url="https://github.com/kubernetes-sigs/gateway-api/releases/download/v${version}/standard-install.yaml"
upstream="$(mktemp)"
trap 'rm -f "$upstream"' EXIT
curl -fsSL --retry 3 -o "$upstream" "$url"
want="$(shasum -a 256 "$upstream" | cut -d' ' -f1)"
got="$(shasum -a 256 "$chart/templates/standard-install.yaml" | cut -d' ' -f1)"
if [ "$want" != "$got" ]; then
  echo "::error file=$chart/templates/standard-install.yaml::not the upstream v$version standard-install.yaml (sha256 $got, upstream $want)"
  fail=1
fi
[ "$fail" = 0 ] && echo "gateway-api-crds carries Gateway API v$version, verbatim (sha256 $got)"
exit "$fail"
