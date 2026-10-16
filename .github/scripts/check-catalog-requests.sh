#!/usr/bin/env bash
# Every container the catalog runs states what it needs: a cpu, a memory and
# an ephemeral-storage request. GKE Autopilot reserves — and bills — each pod
# from its declared requests, and gives a container that declares none the
# general-purpose defaults: 500m CPU, 2 GiB memory, 1 GiB ephemeral storage
# (docs/clouds/gcp/sizing.md). A request left out on any cloud is a pod sized by
# someone else.
#
# Usage: check-catalog-requests.sh <rendered-dir> [report.tsv]
#   <rendered-dir> holds one `flux-operator build rset` output per module, as
#   one cloud's overlay deploys it (pr-static.yaml renders aws, gcp, and aws
#   with every `ha` input on). Every HelmRelease found there — child
#   ResourceSets' included — is rendered with `helm template` at its pinned
#   chart version, with the socle's values alone: its inline values and its
#   valuesFrom ConfigMaps — the socle's and the cloud step's — but the
#   client's (`<module>-client-values`, and the values Secret he names, which
#   is not in the render anyway). A client value merged in could mask a gap —
#   the samples set memory requests on several modules — and the socle's
#   defaults are what a client who sets nothing gets, so they are what is
#   checked. An optional valuesFrom absent from the render (a module with no
#   cloud step has no `<module>-cloud-values`) is skipped, as helm-controller
#   skips it.
#
# Pod templates are read from: the charts' workloads (Deployment, StatefulSet,
# DaemonSet, Job, CronJob, Pod); the plain manifests a module's Kustomizations
# apply from the artifact (oci/catalog/<module>/<dir>/*.yaml); the objects a
# module's steps apply directly (its render); a Crossplane
# DeploymentRuntimeConfig (the provider's package-runtime container); and the
# VictoriaMetrics operator's custom resources the monitoring module's chart
# creates, whose pods the operator builds: spec.resources for the main
# container of every kind that has one, spec.configReloaderResources for the
# config-reloader sidecar of VMAgent, VMAlert, VMAlertmanager and VMAuth, and
# spec.initContainers as written. With a second argument, every container is
# written there as one TSV row (the sizing table of docs/clouds/gcp/sizing.md is
# built from it).
#
# A chart that cannot be pulled fails the check with helm's own message,
# after three attempts. CHART_CACHE, when set, keeps the pulled charts
# between runs (pr-static.yaml caches it across workflow runs).
set -euo pipefail
rendered="${1:?usage: $0 <rendered-dir> [report.tsv]}"
report="${2:-}"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
charts="${CHART_CACHE:-${work}/charts}"
mkdir -p "${work}/json" "${charts}" "${work}/out"
for f in "${rendered}"/*.yaml; do
  yq ea -o=json '[.]' "${f}" > "${work}/json/$(basename "${f}" .yaml).json"
done
# The plain manifests a module's Kustomizations apply from the artifact
# (gateway-api/cilium/, the monitoring/ dashboards and rules): read as they
# are, for each Flux Kustomization of the render that points into the
# catalog and is not switched off — the cilium one is, on a cloud without
# the socle's Cilium.
root="$(cd "$(dirname "$0")/../.." && pwd)"
yq e -N 'select(.kind == "Kustomization" and (.apiVersion | test("^kustomize.toolkit.fluxcd.io/"))
    and .metadata.annotations["fluxcd.controlplane.io/reconcile"] != "disabled") | .spec.path' \
    "${rendered}"/*.yaml | sed -n 's|^\./catalog/||p' | sort -u \
  | while read -r path; do
    for f in "${root}/oci/catalog/${path}"/*.yaml; do
      [ -f "${f}" ] || continue
      yq ea -o=json '[.]' "${f}" > "${work}/json/${path%%/*}~$(basename "${path}")-$(basename "${f}" .yaml).json"
    done
  done

# 1. Plan: one helm template per HelmRelease, its sources and values resolved.
python3 - "${work}" > "${work}/plan.tsv" <<'PY'
import json, glob, os, sys
work = sys.argv[1]
def walk(objs):
    for o in objs or []:
        if isinstance(o, dict):
            yield o
            if o.get("kind") == "ResourceSet":
                yield from walk(o.get("spec", {}).get("resources"))
for path in sorted(glob.glob(f"{work}/json/*.json")):
    module = os.path.basename(path)[:-5]
    objs = list(walk(json.load(open(path))))
    find = lambda kind, ns, name: next((o for o in objs if o.get("kind") == kind
        and o["metadata"].get("namespace") == ns and o["metadata"]["name"] == name), None)
    for i, hr in enumerate(o for o in objs if o.get("kind") == "HelmRelease"):
        ns, spec = hr["metadata"]["namespace"], hr["spec"]
        if "chartRef" in spec:
            src = find(spec["chartRef"]["kind"], ns, spec["chartRef"]["name"])
            chart = (src["spec"]["url"], "-", src["spec"]["ref"]["tag"])
        else:
            c = spec["chart"]["spec"]
            src = find(c["sourceRef"]["kind"], ns, c["sourceRef"]["name"])
            chart = (src["spec"]["url"], c["chart"], c["version"])
        files = []
        for ref in spec.get("valuesFrom", []):
            if ref["kind"] != "ConfigMap" or ref["name"].endswith("-client-values"):
                continue  # the client's: the socle's defaults are checked alone
            cm = find("ConfigMap", ns, ref["name"])
            if cm is None:
                if ref.get("optional"):
                    continue  # helm-controller skips an optional one that is absent
                sys.exit(f"{module}: {ns}/{ref['name']} not in the render")
            files.append(cm["data"][ref.get("valuesKey", "values.yaml")])
        if spec.get("values"):
            files.append(json.dumps(spec["values"]))
        vals = []
        for j, text in enumerate(files):
            p = f"{work}/out/{module}-{i}-values-{j}.yaml"
            open(p, "w").write(text)
            vals.append(p)
        print("\t".join([module, spec.get("releaseName", hr["metadata"]["name"]),
                         spec.get("targetNamespace", ns), *chart, ",".join(vals)]))
PY

# 2. Render: pull each chart once, template it with those values.
pull() { # <dest> <helm pull args...>: three attempts, helm's error kept
  local dest="$1" err n
  shift
  for n in 1 2 3; do
    if err="$(helm pull "$@" --untar --untardir "${dest}" 2>&1 > /dev/null < /dev/null)"; then
      return 0
    fi
    rm -rf "${dest}"
    echo "helm pull $* (attempt ${n}/3): ${err}" >&2
    [ "${n}" = 3 ] || sleep $((n * 5))
  done
  echo "::error::cannot pull $*: ${err}"
  exit 1
}
while IFS=$'\t' read -r module release ns url chart version values; do
  dest="${charts}/$(printf '%s' "${url}${chart}${version}" | tr -c 'a-zA-Z0-9.' _)"
  if [ ! -d "${dest}" ]; then
    if [ "${chart}" = - ]; then
      pull "${dest}" "${url}" --version "${version}" # an OCIRepository: the chart itself
    elif [[ "${url}" == oci://* ]]; then
      pull "${dest}" "${url}/${chart}" --version "${version}" # a HelmRepository of type oci
    else
      pull "${dest}" "${chart}" --repo "${url}" --version "${version}"
    fi
  fi
  args=()
  IFS=, read -ra files <<< "${values}"
  for v in "${files[@]}"; do args+=(--values "${v}"); done
  helm template "${release}" "${dest}"/* --namespace "${ns}" "${args[@]}" \
    | yq ea -o=json '[.]' > "${work}/out/${module}-${release}.json"
done < "${work}/plan.tsv"

# 3. Check every pod template: the charts' and the catalog's own.
python3 - "${work}" "${report}" <<'PY'
import json, glob, os, sys
work, report = sys.argv[1], sys.argv[2]
def walk(objs):
    for o in objs or []:
        if isinstance(o, dict):
            yield o
            if o.get("kind") == "ResourceSet":
                yield from walk(o.get("spec", {}).get("resources"))
# The VictoriaMetrics operator's kinds whose pods it builds from the custom
# resource (operator v0.75.0, the monitoring module's chart): the main
# container's name, and whether a config-reloader sidecar runs beside it.
VM = {"VMSingle": ("vmsingle", False), "VMAgent": ("vmagent", True),
      "VMAlert": ("vmalert", True), "VMAlertmanager": ("alertmanager", True),
      "VMAuth": ("vmauth", True), "VMAnomaly": ("vmanomaly", False),
      "VLSingle": ("vlsingle", False), "VLAgent": ("vlagent", False),
      "VTSingle": ("vtsingle", False), "VTAgent": ("vtagent", False)}
def pods(o):
    k, s = o.get("kind"), o.get("spec") or {}
    if k in ("Deployment", "StatefulSet", "DaemonSet", "ReplicaSet"):
        yield s.get("template", {}).get("spec", {}), s.get("replicas", 1)
    elif k == "Job":
        yield s.get("template", {}).get("spec", {}), 1
    elif k == "CronJob":
        yield s.get("jobTemplate", {}).get("spec", {}).get("template", {}).get("spec", {}), 1
    elif k == "Pod":
        yield s, 1
    elif k == "DeploymentRuntimeConfig":
        yield s.get("deploymentTemplate", {}).get("spec", {}).get("template", {}).get("spec", {}), 1
    elif k in VM and str(o.get("apiVersion", "")).startswith("operator.victoriametrics.com/"):
        main, reloader = VM[k]
        cs = [{"name": main, "resources": s.get("resources")}]
        if reloader:
            cs.append({"name": "config-reloader", "resources": s.get("configReloaderResources")})
        yield {"containers": cs, "initContainers": s.get("initContainers")}, s.get("replicaCount", 1)
plan = [l.rstrip("\n").split("\t") for l in open(f"{work}/plan.tsv")]
sources = [(os.path.basename(p)[:-5].split("~")[0], p) for p in sorted(glob.glob(f"{work}/json/*.json"))]
sources += [(m, f"{work}/out/{m}-{r}.json") for m, r, *_ in plan]
rows, missing = [], []
for module, path in sources:
    for o in walk(json.load(open(path))):
        for spec, replicas in pods(o):
            hook = (o["metadata"].get("annotations") or {}).get("helm.sh/hook", "")
            if any(h.strip() in ("test", "test-success") for h in hook.split(",")):
                continue  # helm test pods: helm-controller runs none (spec.test)
            for kind, cs in (("init", spec.get("initContainers")), ("main", spec.get("containers"))):
                for c in cs or []:
                    if c.get("restartPolicy") == "Always" and kind == "init":
                        kind = "sidecar"
                    if o["kind"] == "DeploymentRuntimeConfig" and c["name"] != "package-runtime":
                        continue
                    r = c.get("resources") or {}
                    req, lim = r.get("requests") or {}, r.get("limits") or {}
                    where = f"{module}: {o['kind']} {o['metadata'].get('namespace', '-')}/{o['metadata']['name']} {kind} {c['name']}"
                    for res in ("cpu", "memory", "ephemeral-storage"):
                        if res not in req:
                            missing.append(f"{where}: no {res} request")
                    rows.append([module, o["kind"], o["metadata"]["name"], str(replicas),
                                 "hook" if hook else "", kind, c["name"]] +
                                [str(d.get(res, "")) for d in (req, lim)
                                 for res in ("cpu", "memory", "ephemeral-storage")])
if report:
    with open(report, "w") as f:
        f.write("\t".join(["module", "kind", "name", "replicas", "hook", "type", "container",
                           "req_cpu", "req_mem", "req_eph", "lim_cpu", "lim_mem", "lim_eph"]) + "\n")
        for r in sorted(rows):
            f.write("\t".join(r) + "\n")
for m in missing:
    print(f"::error::{m}")
if missing:
    print(f"{len(missing)} missing request(s) over {len(rows)} container(s)")
    sys.exit(1)
print(f"every container states its cpu, memory and ephemeral-storage requests: {len(rows)} container(s)")
PY
