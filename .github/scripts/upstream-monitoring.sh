#!/usr/bin/env bash
# The alert rules and dashboards a module takes from upstream, as they are:
# awesome-prometheus-alerts' files and the projects' own dashboards, each at
# a pinned commit, tag or revision. A module ships them under
# oci/catalog/<module>/monitoring/, applied only while the module and the
# monitoring module are both on (docs/decisions/monitoring.md, MONITORING-12).
#
#   upstream-monitoring.sh write   fetch each source, (re)write its file
#   upstream-monitoring.sh check   fetch each source, fail when a file is not
#                                  the upstream content, or is missing (CI)
#
# A rules file is a VMRule whose spec.groups are the upstream file's groups;
# a dashboard is a ConfigMap labelled grafana_dashboard whose one key is the
# upstream JSON. Nothing is edited in between: to change a rule, bump the
# source, or write the socle's own rule beside it (rules.yaml). yq is
# mikefarah's, on the runners; the comparison is on content parsed by
# Python, so neither yq's formatting nor its version fails it.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
mode="${1:-check}"

# module | kind | file (without .yaml) | url
sources() {
  cat <<'EOF'
argocd|rules|awesome-prometheus-alerts|https://raw.githubusercontent.com/samber/awesome-prometheus-alerts/822af1e59938844e9f32c9c2ff7cbe63e8438655/dist/rules/argocd/embedded-exporter.yml
argocd|dashboard|dashboard-argocd|https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.5/examples/dashboard.json
argocd-image-updater|dashboard|dashboard-argocd-image-updater|https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/v1.3.1/config/example-grafana-dashboard.json
crossplane|dashboard|dashboard-crossplane|https://grafana.com/api/dashboards/24549/revisions/3/download
external-dns|dashboard|dashboard-external-dns|https://grafana.com/api/dashboards/23969/revisions/1/download
karpenter|dashboard|dashboard-karpenter-capacity|https://raw.githubusercontent.com/aws/karpenter-provider-aws/v1.15.0/website/content/en/preview/getting-started/getting-started-with-karpenter/karpenter-capacity-dashboard.json
karpenter|dashboard|dashboard-karpenter-performance|https://raw.githubusercontent.com/aws/karpenter-provider-aws/v1.15.0/website/content/en/preview/getting-started/getting-started-with-karpenter/karpenter-performance-dashboard.json
keda|dashboard|dashboard-keda|https://raw.githubusercontent.com/kedacore/keda/v2.21.0/config/grafana/keda-dashboard.json
velero|dashboard|dashboard-velero|https://grafana.com/api/dashboards/16829/revisions/5/download
EOF
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0 n=0
while IFS='|' read -r module kind name url; do
  dir="oci/catalog/$module/monitoring"
  file="$dir/$name.yaml"
  curl -sfL "$url" -o "$tmp/src"
  n=$((n + 1))
  if [ "$mode" = write ]; then
    mkdir -p "$dir"
    {
      echo "# From $url, as it is: written by .github/scripts/upstream-monitoring.sh,"
      echo "# checked against the source in CI. Do not edit; bump the source."
      if [ "$kind" = rules ]; then
        yq -n ".apiVersion = \"operator.victoriametrics.com/v1beta1\" | .kind = \"VMRule\"
          | .metadata.name = \"$name\" | .spec.groups = load(\"$tmp/src\").groups"
      else
        yq -n ".apiVersion = \"v1\" | .kind = \"ConfigMap\" | .metadata.name = \"$module-$name\"
          | .metadata.labels.grafana_dashboard = \"1\" | .data[\"$name.json\"] = load_str(\"$tmp/src\")"
      fi
    } > "$file"
    echo "wrote $file"
    continue
  fi
  if [ ! -f "$file" ]; then
    echo "::error file=$file::missing: run .github/scripts/upstream-monitoring.sh write"
    fail=1
    continue
  fi
  # Both sides parsed by Python's json, the same on every machine: yq only
  # converts YAML to JSON, or extracts the dashboard's string as it is.
  if [ "$kind" = rules ]; then
    yq -o=json '.groups' "$tmp/src" > "$tmp/want"
    yq -o=json '.spec.groups' "$file" > "$tmp/got"
  else
    cp "$tmp/src" "$tmp/want"
    yq ".data[\"$name.json\"]" "$file" > "$tmp/got"
  fi
  if ! python3 -c 'import json, sys; sys.exit(json.load(open(sys.argv[1])) != json.load(open(sys.argv[2])))' "$tmp/want" "$tmp/got"; then
    echo "::error file=$file::differs from $url: run .github/scripts/upstream-monitoring.sh write, never edit it by hand"
    fail=1
  fi
done < <(sources)
[ "$fail" = 0 ] || exit 1
[ "$mode" = write ] || echo "upstream monitoring: $n file(s), each the upstream content. ✅"
