# Sourced by the `script` steps of chainsaw-test.yaml: what the cluster's
# objects do not show — a series in VictoriaMetrics, a record in
# VictoriaLogs, a rule's health in vmalert, a notification in Alertmanager,
# what Grafana serves. Reached through the API server's service proxy, no
# port-forward, no client image, except Grafana (gf_up). Needs KUBECONFIG.
proxy() { echo "/api/v1/namespaces/monitoring/services/$1/proxy"; }
vm="$(proxy vmsingle-monitoring:8428)"
vl="$(proxy vlsingle-monitoring:9428)"
urlq() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"; }
# eventually <seconds> <command…>: retried every 5 s until it succeeds.
eventually() {
  t="$1"; shift
  for _ in $(seq 1 $((t / 5))); do
    "$@" && return 0
    sleep 5
  done
  "$@"
}

# series <promql>: how many series an instant query returns, 0 on any error.
series() {
  kubectl get --raw "$vm/api/v1/query?query=$(urlq "count($1)")" 2>/dev/null \
    | python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else 0)' \
    2>/dev/null || echo 0
}
has_series() { n="$(series "$1")"; echo "$1: $n series"; [ "$n" != 0 ]; }
# scrape_targets: every vmagent target's job and health, for the record.
scrape_targets() {
  kubectl get --raw "$vm/api/v1/query?query=$(urlq 'count by (job) (up == 1)')" | python3 -c '
import sys, json
r = json.load(sys.stdin)["data"]["result"]
print("scraped jobs: " + " ".join(sorted("%s=%s" % (m["metric"].get("job", "?"), m["value"][1]) for m in r)))'
}
# post_otlp_metric <name> <value>: one gauge point, a minute old so an instant
# query sees it past -search.latencyOffset, as OTLP/JSON to the gateway, from
# podinfo's own curl (the hello module): the API server's service proxy sends
# a content type the OTLP receiver refuses (415).
post_otlp_metric() {
  payload="$(printf '{"resourceMetrics":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"socle-e2e"}}]},"scopeMetrics":[{"metrics":[{"name":"%s","gauge":{"dataPoints":[{"asDouble":%s,"timeUnixNano":"%s"}]}}]}]}]}' \
    "$1" "$2" "$(( ($(date +%s) - 60) * 1000000000 ))")"
  kubectl -n hello exec deploy/podinfo -- curl -sSf -H 'Content-Type: application/json' \
    --data-binary "$payload" http://otel-gateway.otel-gateway.svc:4318/v1/metrics > /dev/null
}

# hits <logsql>: how many records match, 0 on any error.
hits() {
  kubectl get --raw "$vl/select/logsql/query?query=$(urlq "$1")&limit=10" 2>/dev/null | grep -c . || true
}
has_hits() { h="$(hits "$1")"; echo "$1: ${h:-0} record(s)"; [ "${h:-0}" != 0 ]; }
# post_otlp_log <body>: one OTLP/JSON log record posted to the gateway by podinfo.
post_otlp_log() {
  payload="$(printf '{"resourceLogs":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"socle-e2e"}}]},"scopeLogs":[{"logRecords":[{"timeUnixNano":"%s","severityText":"INFO","body":{"stringValue":"%s"}}]}]}]}' \
    "$(( $(date +%s) * 1000000000 ))" "$1")"
  kubectl -n hello exec deploy/podinfo -- curl -sSf -H 'Content-Type: application/json' \
    --data-binary "$payload" http://otel-gateway.otel-gateway.svc:4318/v1/logs > /dev/null
}

# post_span: one span, OTLP/JSON, posted by podinfo to the gateway; prints
# the trace id.
post_span() {
  now="$(date +%s)"
  trace_id="$(printf '%08x' "$now")$(printf '%024x' 42)"
  payload="$(printf '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"socle-e2e"}}]},"scopeSpans":[{"spans":[{"traceId":"%s","spanId":"%016x","name":"socle-e2e-probe","kind":1,"startTimeUnixNano":"%s","endTimeUnixNano":"%s"}]}]}]}' \
    "$trace_id" 7 "$(( (now - 2) * 1000000000 ))" "$(( (now - 1) * 1000000000 ))")"
  kubectl -n hello exec deploy/podinfo -- curl -sSf -H 'Content-Type: application/json' \
    --data-binary "$payload" http://otel-gateway.otel-gateway.svc:4318/v1/traces > /dev/null
  echo "$trace_id"
}
# has_trace <trace id>: the Jaeger query API knows it.
has_trace() {
  got="$(kubectl get --raw "$(proxy vtsingle-monitoring:10428)/select/jaeger/api/traces/$1" 2>/dev/null \
    | python3 -c 'import sys,json; d=json.load(sys.stdin).get("data") or []; print(d[0]["traceID"] if d else "")' \
    2>/dev/null || true)"
  [ "$got" = "$1" ]
}

vmalert() { kubectl get --raw "$(proxy vmalert-monitoring:8080)$1"; }
alertmanager() { kubectl get --raw "$(proxy vmalertmanager-monitoring:9093)$1"; }
# rule_groups: the rule groups vmalert has loaded, one per line.
rule_groups() { vmalert /api/v1/rules | python3 -c 'import sys, json; [print(g["name"]) for g in json.load(sys.stdin)["data"]["groups"]]'; }
has_group() { rule_groups | grep -qx "$1"; }
# rules_healthy <at least>: that many rules or more, every one evaluated
# without error.
rules_healthy() {
  vmalert /api/v1/rules | python3 -c '
import sys, json
rules = [r for g in json.load(sys.stdin)["data"]["groups"] for r in g["rules"]]
bad = [r["name"] for r in rules if r.get("health") != "ok" or r.get("lastError")]
print("%d rules, %d alerting; unhealthy: %s" % (len(rules), sum(r["type"] == "alerting" for r in rules), " ".join(bad) or "none"))
sys.exit(1 if bad or len(rules) < int(sys.argv[1]) else 0)' "$1"
}
# firing <alertname>: vmalert holds it firing.
firing() {
  vmalert /api/v1/alerts | python3 -c '
import sys, json
alerts = json.load(sys.stdin)["data"]["alerts"]
sys.exit(0 if any(a["name"] == sys.argv[1] and a["state"] == "firing" for a in alerts) else 1)' "$1"
}
# metric <name> <label filter>: the sum of a metric's samples on a /metrics
# page, the lines whose labels contain the filter.
metric() { awk -v n="$1" -v f="$2" '$1 ~ "^"n"({|$)" && index($1, f) { s += $2 } END { print s + 0 }'; }
# delivered: Alertmanager delivered through its webhook integration, and
# never failed to.
delivered() {
  m="$(alertmanager /metrics)"
  sent="$(printf '%s\n' "$m" | metric alertmanager_notifications_total 'integration="webhook"')"
  failed="$(printf '%s\n' "$m" | metric alertmanager_notifications_failed_total 'integration="webhook"')"
  echo "webhook notifications: $sent sent, $failed failed"
  [ "$sent" -gt 0 ] && [ "$failed" -eq 0 ]
}

# Grafana's own API, what a person opening it sees: a port-forward — the
# image is distroless, the API needs the admin's basic auth, and the API
# server's service proxy carries no credential of its own.
gf_up() {
  pass="$(kubectl -n monitoring get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
  kubectl -n monitoring port-forward svc/grafana 13000:80 > /dev/null 2>&1 &
  pf=$!
  trap 'kill "$pf" 2> /dev/null || true' EXIT
  for _ in $(seq 1 30); do
    curl -sf http://127.0.0.1:13000/api/health > /dev/null 2>&1 && return 0
    sleep 2
  done
  echo "grafana never answered on the port-forward"
  return 1
}
gf() { curl -sf -u "admin:$pass" "http://127.0.0.1:13000$1"; }
# datasources <name…>: exactly these, by name, and each healthy.
datasources() {
  gf /api/datasources | python3 -c '
import sys, json
ds = json.load(sys.stdin)
print("grafana datasources: " + ", ".join("%s (%s) %s" % (d["name"], d["type"], d["url"]) for d in ds))
want = sorted(sys.argv[1:])
assert sorted(d["name"] for d in ds) == want, want' "$@"
}
# dashboards <at least>: how many the sidecar loaded, every folder.
dashboards() {
  n="$(gf '/api/search?type=dash-db&limit=5000' | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')"
  echo "grafana dashboards: $n"
  [ "$n" -ge "$1" ]
}
# through <promql>: how many series Grafana's own datasource proxy returns.
through() {
  gf "/api/datasources/proxy/uid/VictoriaMetrics/api/v1/query?query=$(urlq "count($1)")" \
    | python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else 0)' 2>/dev/null || echo 0
}
