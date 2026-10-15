# Sourced by the `script` steps of chainsaw-test.yaml: what the cluster's
# objects do not show, a series in the monitoring module's VictoriaMetrics.
# Reached through the API server's service proxy — no port-forward, no
# client image. Needs KUBECONFIG.
vm=/api/v1/namespaces/monitoring/services/vmsingle-monitoring:8428/proxy
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
