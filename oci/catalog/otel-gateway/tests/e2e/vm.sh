# Sourced by the `script` steps of the monitoring tests: what the cluster's
# objects do not show, a series in VictoriaMetrics. Reached through the API
# server's service proxy — no port-forward, no client image. Needs KUBECONFIG.
vm=/api/v1/namespaces/victoria-metrics/services/victoria-metrics:http/proxy
urlq() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"; }
# series <promql>: how many series an instant query returns, 0 on any error.
series() {
  kubectl get --raw "$vm/api/v1/query?query=$(urlq "count($1)")" 2>/dev/null \
    | python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else 0)' \
    2>/dev/null || echo 0
}
# wait_series <promql> [attempts of 5 s, default 36]: until it has series.
wait_series() {
  for _ in $(seq 1 "${2:-36}"); do
    kubectl get --raw "$vm/internal/force_flush" > /dev/null 2>&1 || true
    n="$(series "$1")"
    [ "$n" != 0 ] && { echo "$1: $n series"; return 0; }
    sleep 5
  done
  echo "$1: no series"
  return 1
}
# check_dashboard <namespace> <configmap> <key> <metric regex>: every metric an
# expression or a variable of the dashboard names has series. Label names are
# the tokens ending in _name (k8s_node_name, k8s_deployment_name…); no metric
# the collectors store ends that way. A dashboard is written on the names
# VictoriaMetrics stores, and this is what keeps it honest.
check_dashboard() {
  metrics="$(kubectl -n "$1" get configmap "$2" -o json | python3 -c '
import sys, json, re
key, pattern = sys.argv[1], sys.argv[2]
d = json.loads(json.load(sys.stdin)["data"][key])
exprs = [t["expr"] for p in d["panels"] for t in p.get("targets", [])]
exprs += [v["query"]["query"] for v in d["templating"]["list"] if isinstance(v.get("query"), dict)]
names = {m for e in exprs for m in re.findall(pattern, e) if not m.endswith("_name")}
print(" ".join(sorted(names)))' "$3" "$4")"
  missing=""
  for m in $metrics; do
    c="$(series "$m")"
    echo "dashboard $2 metric $m: $c series"
    [ "$c" != 0 ] || missing="$missing $m"
  done
  [ -z "$missing" ] || { echo "dashboard $2 reads metrics victoria-metrics does not have:$missing"; return 1; }
}
# stored_names <prefix…>: the metric names VictoriaMetrics stores, for the record.
stored_names() {
  kubectl get --raw "$vm/api/v1/label/__name__/values" \
    | python3 -c 'import sys,json; p=tuple(sys.argv[1:]); print("stored names: " + " ".join(n for n in json.load(sys.stdin)["data"] if n.startswith(p)))' "$@"
}
# scrape_targets: every `up` series, as namespace/pod=value.
scrape_targets() {
  kubectl get --raw "$vm/api/v1/query?query=$(urlq 'up')" | python3 -c '
import sys, json
r = json.load(sys.stdin)["data"]["result"]
print("scrape targets: " + " ".join("%s/%s=%s" % (m["metric"].get("k8s_namespace_name", "-"),
      m["metric"].get("k8s_pod_name", m["metric"].get("service_name", "?")), m["value"][1]) for m in r))'
}
# post_otlp_metric <name> <value>: one gauge point, a minute old so an instant
# query sees it past -search.latencyOffset, as OTLP/JSON to the gateway, from
# podinfo's own curl (the hello module): the API server's service proxy
# sends a content type the OTLP receiver refuses (415), and a port-forward
# dials the pod's localhost while the chart binds the receivers to the pod IP.
post_otlp_metric() {
  payload="$(printf '{"resourceMetrics":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"socle-e2e"}}]},"scopeMetrics":[{"metrics":[{"name":"%s","gauge":{"dataPoints":[{"asDouble":%s,"timeUnixNano":"%s"}]}}]}]}]}' \
    "$1" "$2" "$(( ($(date +%s) - 60) * 1000000000 ))")"
  kubectl -n hello exec deploy/podinfo -- curl -sSf -H 'Content-Type: application/json' \
    --data-binary "$payload" http://otel-gateway.otel-gateway.svc:4318/v1/metrics > /dev/null
}
