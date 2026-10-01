# Sourced by the `script` steps of chainsaw-test.yaml: a record in
# VictoriaLogs, queried in LogsQL through the API server's service proxy —
# no port-forward, no client image. Needs KUBECONFIG.
vl=/api/v1/namespaces/victoria-logs/services/victoria-logs:http/proxy
urlq() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"; }
# hits <logsql>: how many records match, 0 on any error.
hits() {
  kubectl get --raw "$vl/select/logsql/query?query=$(urlq "$1")&limit=10" 2>/dev/null | grep -c . || true
}
# wait_hits <logsql> [attempts of 5 s]: until at least one record matches.
wait_hits() {
  for _ in $(seq 1 "${2:-36}"); do
    h="$(hits "$1")"
    [ "${h:-0}" != 0 ] && { echo "$1: $h record(s)"; return 0; }
    sleep 5
  done
  echo "$1: no record"
  return 1
}
# fields <logsql>: the field names of the first matching record.
fields() {
  kubectl get --raw "$vl/select/logsql/query?query=$(urlq "$1")&limit=1" \
    | python3 -c 'import sys,json; r=json.loads(sys.stdin.readline()); print("  fields: " + ", ".join(sorted(k for k in r if k.startswith(("k8s.", "_")))))'
}
# post_otlp_log <body>: one OTLP/JSON log record posted to the gateway by
# podinfo's own curl, as the metrics probe (docs/catalog/otel-gateway.md).
post_otlp_log() {
  payload="$(printf '{"resourceLogs":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"socle-e2e"}}]},"scopeLogs":[{"logRecords":[{"timeUnixNano":"%s","severityText":"INFO","body":{"stringValue":"%s"}}]}]}]}' \
    "$(( $(date +%s) * 1000000000 ))" "$1")"
  kubectl -n hello exec deploy/podinfo -- curl -sSf -H 'Content-Type: application/json' \
    --data-binary "$payload" http://otel-gateway.otel-gateway.svc:4318/v1/logs > /dev/null
}
