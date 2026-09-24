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
# An existing release tag is not an error by itself: the promote job tags two
# packages, and a re-run after it failed between them finds the first one
# done. It is checked against this commit's alpha below.
released=""
if released="$(crane digest "$repo:$base" 2>&1)"; then
  :
elif printf '%s' "$released" | grep -qE 'MANIFEST_UNKNOWN|NAME_UNKNOWN'; then
  released=""
else
  echo "::error::cannot tell whether $repo:$base exists: $released"
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
if [ -n "$released" ]; then
  # Already this commit's alpha: the promotion happened, nothing to redo. Any
  # other digest means the tag was cut elsewhere, and is never overwritten.
  if [ "$released" != "$digest" ]; then
    echo "::error::$base is already released as $released, not as $alpha ($digest) — a release tag is never overwritten"
    exit 1
  fi
else
  crane tag "$repo@$digest" "$base"
fi
echo "tag=$base"
echo "alpha=$alpha"
echo "digest=$digest"
