#!/usr/bin/env bash
# Assembles the whole GitHub Pages site into one directory. A Pages
# deployment replaces the site, so every deploy rebuilds every part of it:
#   <out>/          latest: the last release tag (X.Y.Z), or main until there is one
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

tag=""
for t in $(git tag --list --sort=-v:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true); do
  if git cat-file -e "${t}:site/package.json" 2>/dev/null; then tag="${t}"; break; fi
done
released=$([ -n "${tag}" ] && echo true || echo false)
echo "### Docs site" >> "${summary}"

build . "${out}/dev" SOCLE_CHANNEL=dev SOCLE_REF=main SOCLE_RELEASED="${released}"
echo "- dev: \`$(git rev-parse --short HEAD)\` ✅" >> "${summary}"

if [ -n "${tag}" ]; then
  build "$(checkout latest "${tag}")" "${out}" SOCLE_CHANNEL=latest SOCLE_REF="${tag}" SOCLE_RELEASED=true
else
  build . "${out}" SOCLE_CHANNEL=latest SOCLE_REF=main SOCLE_RELEASED=false
fi
echo "- latest: \`${tag:-main, no release yet}\` ✅" >> "${summary}"

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
