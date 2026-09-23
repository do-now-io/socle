#!/usr/bin/env bash
# Which tag this push publishes. Prints `tag=`, `kind=` and `base=` lines for
# $GITHUB_OUTPUT. Needs REF_NAME, SHA, REGISTRY, REPOSITORY; reads VERSION;
# uses crane (already logged in) and git (full history and tags).
#   other branch  → 0.0.0-<branch>.<sha>, deletable.
#   main          → <next>-alpha.N, N = 1 + the highest alpha already published
#                   for <next>. VERSION is the last release (release-please
#                   writes it); <next> is what release-please will propose for
#                   the commits since that release, computed the same way:
#                   Release-As footer wins; else a breaking change bumps the
#                   major (the minor before 1.0.0), feat the minor, anything
#                   else the patch. Before the first release <next> is the
#                   config's initial-version. On the release commit itself —
#                   VERSION not yet in the registry — <next> is VERSION.
set -euo pipefail
repo="$REGISTRY/$REPOSITORY"
if [ "$REF_NAME" != "main" ]; then
  slug="$(printf '%s' "$REF_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-//; s/-$//')"
  echo "tag=0.0.0-${slug}.${SHA:0:7}"
  echo "kind=prerelease"
  echo "base="
  exit 0
fi
last="$(tr -d '[:space:]' < VERSION)"

released() {  # 0 when $1 is in the registry, 1 when absent, dies otherwise
  local err
  if err="$(crane manifest "$repo:$1" 2>&1 > /dev/null)"; then return 0; fi
  if printf '%s' "$err" | grep -qE 'MANIFEST_UNKNOWN|NAME_UNKNOWN'; then return 1; fi
  echo "::error::cannot tell whether $repo:$1 exists: $err"; exit 1
}

next_version() {  # from the conventional commits since the last release
  local range commits major minor patch bump=patch release_as
  # No release yet: release-please starts at initial-version, whatever the commits say.
  if [ "$last" = "0.0.0" ]; then
    python3 -c 'import json; print(json.load(open("release-please-config.json"))["initial-version"])'
    return
  fi
  IFS=. read -r major minor patch <<< "$last"
  if git rev-parse -q --verify "refs/tags/$last" > /dev/null; then range="$last..HEAD"; else range="HEAD"; fi
  # Subjects and bodies, newest first, one commit per record.
  commits="$(git log "$range" --format='%s%n%b%x00')"
  # Release-As: the most recent one wins, as in release-please.
  release_as="$(printf '%s' "$commits" | grep -m1 -iE '^release-as: *v?[0-9]+\.[0-9]+\.[0-9]+' | sed -E 's/^[Rr]elease-[Aa][Ss]: *v?//' || true)"
  if [ -n "$release_as" ]; then echo "$release_as"; return; fi
  if printf '%s' "$commits" | grep -qE '^[a-z]+(\([^)]*\))?!:|^BREAKING[ -]CHANGE:'; then
    if [ "$major" = 0 ]; then bump=minor; else bump=major; fi
  elif printf '%s' "$commits" | grep -qE '^feat(\([^)]*\))?:'; then
    bump=minor
  fi
  case "$bump" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
  esac
}

if [ "$last" != "0.0.0" ] && ! released "$last"; then
  base="$last"   # the release commit: its alpha is the one that gets promoted
else
  base="$(next_version)"
fi
# The repository may not exist yet (first push ever): an empty list then.
if ! tags="$(crane ls "$repo" 2>&1)"; then
  if printf '%s' "$tags" | grep -qE 'NAME_UNKNOWN'; then tags=""; else
    echo "::error::cannot list $repo: $tags"; exit 1
  fi
fi
# `grep` exits 1 when nothing matches (first alpha of this version): not an error.
highest="$( { printf '%s\n' "$tags" | grep -E "^${base//./\\.}-alpha\.[0-9]+$" || true; } | sed -E 's/.*-alpha\.//' | sort -n | tail -1)"
echo "tag=${base}-alpha.$(( ${highest:-0} + 1 ))"
echo "kind=alpha"
echo "base=$base"
