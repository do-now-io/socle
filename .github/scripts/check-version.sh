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
# Every line that ends in the annotation, whatever the file (a doc, the
# landing page, a test): its version is VERSION, and its file is one of
# release-please-config.json's extra-files. An annotated line in a file
# release-please does not list is never rewritten, and stays behind on the
# next release.
python3 - "$want" <<'PY' || fail=1
import json, re, subprocess, sys
want = sys.argv[1]
listed = {f["path"] for f in json.load(open("release-please-config.json"))["extra-files"]}
annotated = re.compile(r"(#|//)[^\n]*x-release-please-version\s*$")
semver = re.compile(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?")
bad = 0
for path in subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True).stdout.split():
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError):
        continue
    for n, line in enumerate(lines, 1):
        if not annotated.search(line):
            continue
        if path not in listed:
            print(f"::error file={path},line={n}::annotated for release-please but missing from extra-files in release-please-config.json")
            bad = 1
        got = semver.search(line)
        if not got or got.group(0) != want:
            print(f"::error file={path},line={n}::version is {got.group(0) if got else 'missing'}, VERSION is {want}")
            bad = 1
sys.exit(bad)
PY
[ "$fail" = 0 ] && echo "VERSION $want is consistent"
exit "$fail"
