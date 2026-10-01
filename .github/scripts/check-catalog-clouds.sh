#!/usr/bin/env bash
# The catalog is declared twice, on purpose: opentofu/bootstrap/catalog.tf says
# what a client may configure (and, through catalog_clouds, on which clouds),
# and oci/clusters/<cloud>/kustomization.yaml says what Flux deploys there.
# This fails when the two disagree, in either direction — and when a module
# ships no tests/e2e/chainsaw-test.yaml, the proof e2e.yaml discovers it by.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
python3 - <<'PY'
import re, sys, glob, os
src = open("opentofu/bootstrap/catalog.tf").read()
# catalog = { <4-space-indented keys> }
body = re.search(r"^  catalog += \{\n(.*?)^  \}", src, re.S | re.M).group(1)
modules = re.findall(r"^    ([a-z][a-z0-9_]*) *= *\{", body, re.M)
clouds_body = re.search(r"^  catalog_clouds += \{(.*?)\}", src, re.S | re.M).group(1)
restricted = {m: re.findall(r'"([a-z]+)"', lst)
              for m, lst in re.findall(r"^\s*([a-z][a-z0-9_]*) *= *\[([^\]]*)\]", clouds_body, re.M)}
overlays = sorted(glob.glob("oci/clusters/*/kustomization.yaml"))
all_clouds = [p.split("/")[2] for p in overlays]
fail = 0
for path in overlays:
    cloud = path.split("/")[2]
    listed = set(re.findall(r"catalog/([a-z0-9-]+)/resourceset\.yaml", open(path).read()))
    expected = {m.replace("_", "-") for m in modules if cloud in restricted.get(m, all_clouds)}
    for extra in sorted(listed - expected):
        print(f"::error file={path}::{cloud} deploys catalog/{extra} but catalog.tf does not offer it on {cloud}"); fail = 1
    for missing in sorted(expected - listed):
        print(f"::error file={path}::catalog.tf offers {missing.replace('-', '_')} on {cloud} but {path} does not deploy it"); fail = 1
for m, cl in restricted.items():
    if m not in modules:
        print(f"::error file=opentofu/bootstrap/catalog.tf::catalog_clouds names {m}, which is not in catalog"); fail = 1
    for c in cl:
        if c not in all_clouds:
            print(f"::error file=opentofu/bootstrap/catalog.tf::catalog_clouds names cloud {c} for {m}, no oci/clusters/{c}/ overlay"); fail = 1
for m in modules:
    folder = f"oci/catalog/{m.replace('_', '-')}"
    if not os.path.isdir(folder):
        print(f"::error file=opentofu/bootstrap/catalog.tf::{m} has no {folder}/ folder"); fail = 1
    # The module's e2e proof travels with it: .github/workflows/e2e.yaml
    # discovers the matrix from these folders and never names a module.
    elif not os.path.isfile(f"{folder}/tests/e2e/chainsaw-test.yaml"):
        print(f"::error file={folder}/resourceset.yaml::{m} ships no {folder}/tests/e2e/chainsaw-test.yaml — its e2e proof (docs/flux-catalog.md §6)"); fail = 1
if not fail:
    print(f"catalog and overlays agree: {len(modules)} module(s) on {len(all_clouds)} cloud(s), {len(restricted)} cloud-bound, every module with its tests/e2e")
sys.exit(fail)
PY
