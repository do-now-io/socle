# Sourced by the `script` steps of chainsaw-test.yaml: vmalert's and
# Alertmanager's own HTTP APIs, through the API server's service proxy —
# neither asks for a credential. Needs KUBECONFIG.
vmalert() { kubectl get --raw "/api/v1/namespaces/alerting/services/alerting-server:8880/proxy$1"; }
alertmanager() { kubectl get --raw "/api/v1/namespaces/alerting/services/alerting-alertmanager:9093/proxy$1"; }
# eventually <seconds> <command…>: retried every 5 s until it succeeds.
eventually() {
  t="$1"; shift
  for _ in $(seq 1 $((t / 5))); do
    "$@" && return 0
    sleep 5
  done
  "$@"
}
# rule_groups: the rule groups vmalert has loaded, one per line.
rule_groups() { vmalert /api/v1/rules | python3 -c 'import sys, json; [print(g["name"]) for g in json.load(sys.stdin)["data"]["groups"]]'; }
has_group() { rule_groups | grep -qx "$1"; }
# rules_healthy: every rule vmalert holds has been evaluated, without error.
rules_healthy() {
  vmalert /api/v1/rules | python3 -c '
import sys, json
rules = [r for g in json.load(sys.stdin)["data"]["groups"] for r in g["rules"]]
bad = [r["name"] for r in rules if r.get("health") != "ok" or r.get("lastError")]
print("unhealthy:", " ".join(bad)) if bad else None
sys.exit(1 if bad or not rules else 0)'
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
reloaded_ok() {
  ok="$(vmalert /metrics | metric vmalert_config_last_reload_successful '')"
  echo "vmalert_config_last_reload_successful $ok"
  [ "$ok" = 1 ]
}
