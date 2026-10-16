#!/usr/bin/env bash
# Every catalog module ships its page, and the dependency graph the site draws
# from those pages holds (docs/reference/catalog-module-standard.md):
#
#   - each module in opentofu/bootstrap/catalog.tf has docs/catalog/<module>.md
#     with a title, a description and a category in its frontmatter;
#   - each `requires` names a module that exists, on clouds where both are
#     offered (catalog_clouds);
#   - each `requires` is also an `after`: a module that needs another waits
#     for it, through a top-level spec.dependsOn on the other's ResourceSet,
#     in oci/catalog/<module>/resourceset.yaml or, on one cloud, added by
#     oci/clusters/<cloud>/<module>/patch.yaml;
#   - on no cloud does the graph (requires and after) have a cycle.
#
# The same parse as site/src/catalog.mjs, which draws the graph and writes
# catalog.json.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
python3 - <<'PY'
import re, glob, os
src = open("opentofu/bootstrap/catalog.tf").read()
body = re.search(r"^  catalog += \{\n(.*?)^  \}", src, re.S | re.M).group(1)
modules = [m.replace("_", "-") for m in re.findall(r"^    ([a-z][a-z0-9_]*) *= *\{", body, re.M)]
clouds_body = re.search(r"^  catalog_clouds += \{(.*?)\}", src, re.S | re.M).group(1)
restricted = {m.replace("_", "-"): re.findall(r'"([a-z]+)"', lst)
              for m, lst in re.findall(r"^\s*([a-z][a-z0-9_]*) *= *\[([^\]]*)\]", clouds_body, re.M)}
all_clouds = sorted(p.split("/")[2] for p in glob.glob("oci/clusters/*/kustomization.yaml"))
offered = lambda m, c: c in restricted.get(m, all_clouds)
fail = 0

def error(path, msg):
    global fail
    print(f"::error file={path}::{msg}")
    fail = 1

def resourcesets(text):
    """The ResourceSet names in a dependsOn list, as YAML text."""
    return re.findall(r"kind: *ResourceSet\n\s+name: *([a-z0-9-]+)", text)

def after(m, cloud):
    """What the module's ResourceSet waits for on that cloud."""
    found = set()
    first = open(f"oci/catalog/{m}/resourceset.yaml").read().split("\n---")[0]
    spec = re.search(r"^spec:\n((?: {2}.*\n|\n)*)", first, re.M)
    deps = spec and re.search(r"^ {2}dependsOn:\n((?: {4}.*\n)*)", spec.group(1), re.M)
    if deps:
        found |= set(resourcesets(deps.group(1)))
    patch = f"oci/clusters/{cloud}/{m}/patch.yaml"
    if os.path.isfile(patch):
        for op in re.findall(r"^- op: add\n  path: /spec/dependsOn(?:/-)?\n  value:\n((?: {4}.*\n|\n)*)", open(patch).read(), re.M):
            found |= set(resourcesets(op))
    return found - {m}

pages = {}
for m in modules:
    path = f"docs/catalog/{m}.md"
    if not os.path.isfile(path):
        error("opentofu/bootstrap/catalog.tf", f"{m} has no {path} (docs/reference/catalog-module-standard.md)")
        continue
    head = re.match(r"---\n(.*?)\n---", open(path).read(), re.S)
    head = head.group(1) if head else ""
    for field in ("title", "description", "category"):
        if not re.search(rf"^{field}: *\S", head, re.M):
            error(path, f"the frontmatter has no {field}")
    pages[m] = [(r.group(1).replace("_", "-"), [c.strip() for c in r.group(2).split(",")] if r.group(2) else None)
                for r in re.finditer(r"^  - module: *([a-z0-9_-]+)\n(?: {4}clouds: *\[([^\]]*)\]\n)?", head, re.M)]

edges = {c: {m: set() for m in modules if offered(m, c)} for c in all_clouds}
for m, requires in pages.items():
    path = f"docs/catalog/{m}.md"
    for other, clouds in requires:
        if other not in modules:
            error(path, f"requires {other}, which is not a catalog module")
            continue
        for c in clouds or all_clouds:
            if c not in all_clouds:
                error(path, f"requires {other} on {c}, which is not a cloud")
            elif clouds and not (offered(m, c) and offered(other, c)):
                error(path, f"requires {other} on {c}, where {m if not offered(m, c) else other} is not offered")
            elif offered(m, c) and offered(other, c):
                if other not in after(m, c):
                    error(path, f"requires {other} on {c} but its ResourceSet does not wait for it: "
                                f"no spec.dependsOn on the ResourceSet {other} (oci/catalog/{m}/ or oci/clusters/{c}/{m}/patch.yaml)")
                edges[c][m].add(other)
for c in all_clouds:
    for m in edges[c]:
        edges[c][m] |= {o for o in after(m, c) if o in edges[c]}

# No cycle, cloud by cloud.
for c in all_clouds:
    state = {}
    def visit(m, trail):
        if state.get(m) == "done":
            return
        if state.get(m) == "open":
            error("opentofu/bootstrap/catalog.tf", f"a dependency cycle on {c}: {' → '.join(trail[trail.index(m):] + [m])}")
            return
        state[m] = "open"
        for o in sorted(edges[c][m]):
            visit(o, trail + [m])
        state[m] = "done"
    for m in sorted(edges[c]):
        visit(m, [])

if fail:
    raise SystemExit(1)
n = sum(len(e) for cloud in edges.values() for e in cloud.values())
print(f"### Catalog pages ✅\n{len(pages)} modules, each with its page; every `requires` waits for what it needs; "
      f"no cycle on {', '.join(all_clouds)} ({n} edges in all).")
PY
