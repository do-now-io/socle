#!/usr/bin/env bash
# Release = give the alpha built from the released commit a second tag, the
# version itself. No second build: cosign signed the digest, so the new tag
# carries the same signature and the same identity (main). Prints `tag=`,
# `alpha=`, `digest=` lines for $GITHUB_OUTPUT.
# Needs RELEASE_TAG (the GitHub release's tag), SHA (the commit it points
# to), REGISTRY, REPOSITORY; reads VERSION at that commit; uses crane.
set -euo pipefail
repo="$REGISTRY/$REPOSITORY"
base="$(tr -d '[:space:]' < VERSION)"
# The release tag is what clients write in socle_version, and what the modules
# package is tagged with: it has to be VERSION, no `v`, nothing else.
if [ "$RELEASE_TAG" != "$base" ]; then
  echo "::error::release tag '$RELEASE_TAG' is not the VERSION of the tagged commit ('$base') — tag the release '$base', or bump VERSION first"
  exit 1
fi
if err="$(crane manifest "$repo:$base" 2>&1 > /dev/null)"; then
  echo "::error::$base is already released — a release tag is never overwritten"
  exit 1
elif ! printf '%s' "$err" | grep -qE 'MANIFEST_UNKNOWN|NAME_UNKNOWN'; then
  echo "::error::cannot tell whether $repo:$base exists: $err"
  exit 1
fi
# The alpha to promote is the one built from this very commit: only pushes to
# main produce alphas, so a match also proves the commit is on main.
want="main@sha1:$SHA"
alpha=""
for candidate in $( { crane ls "$repo" | grep -E "^${base//./\\.}-alpha\.[0-9]+$" || true; } | sort -t. -k4 -n); do
  revision="$(crane manifest "$repo:$candidate" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("annotations",{}).get("org.opencontainers.image.revision",""))')"
  if [ "$revision" = "$want" ]; then alpha="$candidate"; fi
done
if [ -z "$alpha" ]; then
  echo "::error::no ${base}-alpha.N was built from $want — is the tagged commit on main, and has its push finished publishing?"
  exit 1
fi
digest="$(crane digest "$repo:$alpha")"
crane tag "$repo@$digest" "$base"
echo "tag=$base"
echo "alpha=$alpha"
echo "digest=$digest"
