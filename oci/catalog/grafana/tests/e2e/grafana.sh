# Sourced by the `script` steps of chainsaw-test.yaml: Grafana's own API,
# what a person opening it sees. Reached with a port-forward — the image is
# distroless, the API needs the admin's basic auth, and the API server's
# service proxy carries no credential of its own. Needs KUBECONFIG.
gf_up() {
  pass="$(kubectl -n grafana get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
  kubectl -n grafana port-forward svc/grafana 13000:80 > /dev/null 2>&1 &
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
urlq() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"; }
# datasources <logs:true|false>: exactly the ones the socle provisions.
datasources() {
  ds="$(gf /api/datasources)"
  printf '%s' "$ds" | python3 -c '
import sys, json
ds = json.load(sys.stdin)
print("grafana datasources: " + ", ".join("%s (%s) %s default=%s" % (d["name"], d["type"], d["url"], d["isDefault"]) for d in ds))
vm = [d for d in ds if d["uid"] == "victoria-metrics"]
logs = sys.argv[1] == "true"
vl = [d for d in ds if d["uid"] == "victoria-logs"]
assert len(ds) == 1 + logs and len(vm) == 1 and len(vl) == logs, ds
assert vm[0]["type"] == "prometheus" and vm[0]["url"] == "http://victoria-metrics.victoria-metrics.svc:8428" and vm[0]["isDefault"], vm
assert not logs or (vl[0]["type"] == "victoriametrics-logs-datasource" and vl[0]["url"] == "http://victoria-logs.victoria-logs.svc:9428"), vl
' "$1"
}
# dashboard <uid>: loaded by the sidecar from the module's own namespace.
dashboard() {
  for _ in $(seq 1 30); do
    gf "/api/dashboards/uid/$1" > /dev/null 2>&1 && break
    sleep 2
  done
  gf "/api/dashboards/uid/$1" | python3 -c 'import sys,json; d=json.load(sys.stdin)["dashboard"]; print("dashboard %s: %s, %d panels" % (d["uid"], d["title"], len(d["panels"])))'
}
# through <promql> [attempts of 5 s]: how many series Grafana's own datasource
# proxy returns, polled — the health tests run side by side, and the
# collectors may not have written yet when Grafana is up.
through() {
  for _ in $(seq 1 "${2:-36}"); do
    n="$(gf "/api/datasources/proxy/uid/victoria-metrics/api/v1/query?query=$(urlq "count($1)")" \
      | python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else 0)' 2>/dev/null || echo 0)"
    [ "$n" != 0 ] && { echo "$n"; return 0; }
    sleep 5
  done
  echo 0
}
