#!/usr/bin/env bash
# The catalog is declared twice, on purpose: opentofu/bootstrap/catalog.tf says
# what a client may configure (and, through catalog_clouds, on which clouds),
# and oci/clusters/<cloud>/kustomization.yaml says what Flux deploys there.
# This fails when the two disagree, in either direction — and when a module
# ships no tests/e2e/chainsaw-test.yaml, the proof e2e.yaml discovers it by.
#
# It also holds the line between a module and its clouds
# (docs/decisions/socle.md, SOCLE-32): nothing under oci/catalog/ reads
# inputs.cloud; what one cloud adds to a module is oci/clusters/<cloud>/
# <module>/patch.yaml, listed by that cloud's overlay as a patch on the
# module's ResourceSet, and nothing else lives in oci/clusters/<cloud>/.
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
# What a cloud adds to a module: oci/clusters/<cloud>/<module>/patch.yaml.
patched = 0
for path in overlays:
    cloud = path.split("/")[2]
    text = open(path).read()
    deployed = set(re.findall(r"catalog/([a-z0-9-]+)/resourceset\.yaml", text))
    listed = dict(re.findall(r"^  - path: ([a-z0-9-]+)/patch\.yaml\n    target:\n      kind: ResourceSet\n      name: ([a-z0-9-]+)$", text, re.M))
    for folder, target in sorted(listed.items()):
        if folder != target:
            print(f"::error file={path}::{folder}/patch.yaml must target the ResourceSet {folder}, not {target}"); fail = 1
    on_disk = set()
    for f in sorted(glob.glob(f"oci/clusters/{cloud}/**/*", recursive=True)):
        if os.path.isdir(f) or f == path:
            continue
        m = re.fullmatch(rf"oci/clusters/{cloud}/([a-z0-9-]+)/patch\.yaml", f)
        if not m:
            print(f"::error file={f}::only kustomization.yaml and <module>/patch.yaml belong in oci/clusters/{cloud}/ (SOCLE-32)"); fail = 1
            continue
        on_disk.add(m.group(1))
    for extra in sorted(on_disk - set(listed)):
        print(f"::error file={path}::oci/clusters/{cloud}/{extra}/patch.yaml exists but {path} does not apply it"); fail = 1
    for missing in sorted(set(listed) - on_disk):
        print(f"::error file={path}::{path} applies {missing}/patch.yaml, which does not exist"); fail = 1
    for stray in sorted(on_disk - deployed):
        print(f"::error file=oci/clusters/{cloud}/{stray}/patch.yaml::a patch for {stray}, which {cloud} does not deploy"); fail = 1
    patched += len(on_disk & deployed)
# The module is the same on every cloud: what differs is the cloud's part.
for f in sorted(glob.glob("oci/catalog/**/*", recursive=True)):
    if os.path.isfile(f) and f.endswith((".yaml", ".yml")):
        for n, line in enumerate(open(f), 1):
            if "inputs.cloud" in line:
                print(f"::error file={f},line={n}::inputs.cloud in oci/catalog/ — what is a cloud's goes in oci/clusters/<cloud>/<module>/ (SOCLE-32)"); fail = 1
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
        print(f"::error file={folder}/resourceset.yaml::{m} ships no {folder}/tests/e2e/chainsaw-test.yaml — its e2e proof (docs/reference/catalog-module-standard.md)"); fail = 1
if not fail:
    print(f"catalog and overlays agree: {len(modules)} module(s) on {len(all_clouds)} cloud(s), {len(restricted)} cloud-bound, "
          f"{patched} cloud patch(es), none reading inputs.cloud in oci/catalog/, every module with its tests/e2e")
sys.exit(fail)
PY
