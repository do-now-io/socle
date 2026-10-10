#!/usr/bin/env bash
# Assembles the whole GitHub Pages site into one directory. A Pages
# deployment replaces the site, so every deploy rebuilds every part of it:
#   <out>/          latest: the last release tag (X.Y.Z) that has a site/, or main
#                   until there is one (0.1.0 was tagged before site/ existed)
#   <out>/dev/      dev: the commit checked out (main, in pages.yaml)
#   <out>/pr/<N>/   one preview per line of the PR list, built from its head
# Usage: build-pages.sh <out> [<pr-list>]
#   <pr-list> holds "<number> <head sha>" lines. Their commits must already
#   be fetched. Listing them needs a token, which this script never sees: the
#   code it builds is a pull request's.
# A preview that fails to build is skipped, not fatal: the PR's own strict
# build (docs.yaml) already reports why, and the rest of the site still ships.
# Writes "<number> <sha>" for every preview it built to <out>/../previews.txt.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
out="$(mkdir -p "$1" && cd "$1" && pwd)"
prs="${2:-/dev/null}"
work="$(mktemp -d)"
previews="$(dirname "${out}")/previews.txt"
: > "${previews}"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"

cleanup() {
  for tree in "${work}"/*/; do
    [ -d "${tree}" ] && git worktree remove --force "${tree}"
  done
  rm -rf "${work}"
  git worktree prune
}
trap cleanup EXIT

# build <tree> <dest> [ENV=value…]: the site of <tree>, built strict, into <dest>.
build() {
  local tree="$1" dest="$2"
  shift 2
  # Every command checks itself: under `if build …`, set -e is off.
  (
    cd "${tree}/site" || exit 1
    npm ci --ignore-scripts --no-audit --no-fund > "${work}/build.log" 2>&1 \
      && env "$@" npm run build >> "${work}/build.log" 2>&1 \
      || { tail -40 "${work}/build.log"; exit 1; }
  ) || return 1
  mkdir -p "${dest}" && cp -R "${tree}/site/dist/." "${dest}/"
}

checkout() {
  git worktree add --detach "${work}/$1" "$2" > /dev/null 2>&1 || return 1
  echo "${work}/$1"
}

# release: the last X.Y.Z tag. tag: the last one that has a site to build.
# They differ while the last release predates site/: the root then serves
# main, and its banner names the release rather than claiming there is none.
release="" tag=""
for t in $(git tag --list --sort=-v:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true); do
  [ -n "${release}" ] || release="${t}"
  if git cat-file -e "${t}:site/package.json" 2>/dev/null; then tag="${t}"; break; fi
done
released=$([ -n "${tag}" ] && echo true || echo false)
echo "### Docs site" >> "${summary}"

build . "${out}/dev" SOCLE_CHANNEL=dev SOCLE_REF=main SOCLE_RELEASED="${released}" SOCLE_RELEASE="${release}"
echo "- dev: \`$(git rev-parse --short HEAD)\` ✅" >> "${summary}"

if [ -n "${tag}" ]; then
  build "$(checkout latest "${tag}")" "${out}" SOCLE_CHANNEL=latest SOCLE_REF="${tag}" SOCLE_RELEASED=true SOCLE_RELEASE="${release}"
else
  build . "${out}" SOCLE_CHANNEL=latest SOCLE_REF=main SOCLE_RELEASED=false SOCLE_RELEASE="${release}"
fi
echo "- latest: \`${tag:-main}\` (last release: ${release:-none}) ✅" >> "${summary}"

while read -r number sha; do
  [ -n "${number}" ] || continue
  if ! git cat-file -e "${sha}:site/package.json" 2>/dev/null; then
    echo "- PR #${number}: no site/ at \`${sha:0:7}\`, no preview" >> "${summary}"
    continue
  fi
  if tree="$(checkout "pr-${number}" "${sha}")" && build "${tree}" "${out}/pr/${number}" \
    SOCLE_CHANNEL=pr SOCLE_PR="${number}" SOCLE_REF="${sha}" SOCLE_RELEASED="${released}"; then
    echo "${number} ${sha}" >> "${previews}"
    echo "- PR #${number}: \`${sha:0:7}\` ✅" >> "${summary}"
  else
    rm -rf "${out}/pr/${number}"
    echo "- PR #${number}: \`${sha:0:7}\` does not build, no preview ❌" >> "${summary}"
  fi
done < "${prs}"
