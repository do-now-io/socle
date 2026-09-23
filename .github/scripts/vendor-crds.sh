#!/usr/bin/env bash
# Upstream CRDs travel inside the socle artifact, verbatim from a release
# asset, so that every cluster gets them from the one source Flux already
# verifies (cosign) instead of a second trust root at reconcile time — and
# outside Helm, whose release Secret cannot hold a CRD bundle over 1 MiB
# (measured: Envoy Gateway's CRDs chart fails with "Too long: must have at
# most 1048576 bytes"). This script is the only way such a file changes.
#
#   vendor-crds.sh <owner/repo> <tag> <asset> <file>
#       download the release asset, verify it against the digest GitHub
#       publishes for it, write it to <file> behind a header carrying both
#   vendor-crds.sh --check
#       every vendored file under oci/ still hashes to the digest in its
#       header (offline; CI)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
marker="# Vendored, verbatim, from the release asset below."
header_lines=6

if [ "${1:-}" = "--check" ]; then
  files="$(grep -rlF --include='*.yaml' "$marker" oci/ || true)"
  [ -n "$files" ] || { echo "::error::no vendored file found under oci/"; exit 1; }
  fail=0
  for file in $files; do
    expected="$(sed -n "${header_lines}q;s/^# sha256: //p" "$file")"
    actual="$(tail -n +"$((header_lines + 1))" "$file" | shasum -a 256 | cut -d' ' -f1)"
    source="$(sed -n "${header_lines}q;s/^# source: //p" "$file")"
    if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
      echo "::error file=$file::vendored file was edited: header says $expected, body hashes to $actual"
      fail=1
    else
      echo "$file: $source intact (sha256 $actual)"
    fi
  done
  exit "$fail"
fi

repo="${1:?usage: $0 <owner/repo> <tag> <asset> <file> | --check}"
tag="${2:?tag}"
asset="${3:?asset}"
file="${4:?file}"
url="https://github.com/$repo/releases/download/$tag/$asset"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL -o "$tmp" "$url"
actual="$(shasum -a 256 "$tmp" | cut -d' ' -f1)"
published="$(gh api "repos/$repo/releases/tags/$tag" \
  --jq ".assets[] | select(.name == \"$asset\") | .digest" | sed 's/^sha256://')"
[ -n "$published" ] || { echo "::error::GitHub reports no digest for $url"; exit 1; }
[ "$published" = "$actual" ] || { echo "::error::downloaded $actual, GitHub publishes $published"; exit 1; }
{
  echo "$marker Never edited by hand:"
  echo "# .github/scripts/vendor-crds.sh refreshes it and CI fails when the body no"
  echo "# longer hashes to the digest here (vendor-crds.sh --check)."
  echo "# source: $url"
  echo "# sha256: $actual"
  echo "# ---"
  cat "$tmp"
} > "$file"
echo "vendored $url into $file (sha256 $actual)"
