#!/usr/bin/env bash
# The proof both e2e jobs share: socle-root, hello and gateway-api Ready, the
# Gateway API CRDs established, the artifact pulled by the exact tag TAG with
# its signature verified, podinfo at 1 replica.
# The proof both e2e jobs share: socle-root, external-dns (disabled) and hello Ready, the artifact
# pulled by the exact tag TAG with its signature verified, podinfo at 1 replica.
# Optional expectations come from the environment, one variable per module
# (EXPECT_UI_COLOR, EXPECT_ARGOCD, EXPECT_VICTORIA_METRICS, EXPECT_OTEL_AGENT,
# EXPECT_OTEL_GATEWAY, EXPECT_GRAFANA): the job says what the catalog defaults
# and its tfvars make true, the script checks it.
set -euo pipefail
# wait_ready <resourceset> [attempts of 5 s, default 60]
wait_ready() {
  for _ in $(seq 1 "${2:-60}"); do
    status="$(kubectl -n flux-system get resourceset "$1" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    [ "$status" = True ] && { echo "resourceset/$1 Ready"; return 0; }
    sleep 5
  done
  echo "::error::resourceset $1 never became Ready"
  return 1
}
# VictoriaMetrics, through the API server's service proxy: no port-forward, no
# client image on the runner.
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
  n=0
  for _ in $(seq 1 "${2:-36}"); do
    kubectl get --raw "$vm/internal/force_flush" > /dev/null 2>&1 || true
    n="$(series "$1")"
    [ "$n" != 0 ] && return 0
    sleep 5
  done
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
  [ -z "$missing" ] || { echo "::error::dashboard $2 reads metrics victoria-metrics does not have:$missing"; return 1; }
}
# argocd first when expected: socle-root only turns Ready once every module
# has, and ArgoCD is the slow one (five images on a fresh node), so it gets the
# long budget and the shared waits below keep theirs. The elapsed time is the
# convergence figure docs/catalog/argocd.md quotes.
if [ "${EXPECT_ARGOCD:-}" = true ]; then
  SECONDS=0
  wait_ready argocd 120
  kubectl -n argocd wait deploy/argocd-server --for=condition=Available --timeout=120s
  echo "argocd converged: resourceset Ready and argocd-server Available after ${SECONDS}s"
  # kube.argocd.values merged by helm-controller over the socle's defaults:
  # the client's account must be in argocd-cm, next to the socle's own keys.
  if [ -n "${EXPECT_ARGOCD_ACCOUNT:-}" ]; then
    cm="$(kubectl -n argocd get cm argocd-cm -o json)"
    acct="$(printf '%s' "$cm" | python3 -c "import sys,json; print(json.load(sys.stdin)['data'].get('accounts.$EXPECT_ARGOCD_ACCOUNT',''))")"
    admin="$(printf '%s' "$cm" | python3 -c "import sys,json; print(json.load(sys.stdin)['data'].get('admin.enabled',''))")"
    echo "argocd-cm accounts.$EXPECT_ARGOCD_ACCOUNT='$acct' admin.enabled='$admin'"
    [ -n "$acct" ] || { echo "::error::kube.argocd.values did not reach argocd-cm"; exit 1; }
    [ "$admin" = true ] || { echo "::error::the socle's own argocd-cm keys were lost in the merge"; exit 1; }
  fi
  # Precedence, on a key the socle itself sets: the client's value must be on
  # the live Deployment, and the socle's sibling key must survive the merge.
  if [ -n "${EXPECT_ARGOCD_SERVER_MEMORY:-}" ]; then
    req="$(kubectl -n argocd get deploy argocd-server \
      -o jsonpath='{.spec.template.spec.containers[?(@.name=="server")].resources.requests}')"
    mem="$(printf '%s' "$req" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("memory",""))')"
    cpu="$(printf '%s' "$req" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("cpu",""))')"
    echo "argocd-server requests memory=$mem cpu=$cpu"
    [ "$mem" = "$EXPECT_ARGOCD_SERVER_MEMORY" ] || { echo "::error::client value lost to the socle default: memory '$mem', expected '$EXPECT_ARGOCD_SERVER_MEMORY'"; exit 1; }
    [ "$cpu" = 50m ] || { echo "::error::the socle's cpu request did not survive the merge: '$cpu'"; exit 1; }
  fi
fi
# victoria_metrics when expected, before socle-root for the same reason as
# argocd: the module converges, its claim is Bound on the cluster's default
# class (local-path on floci), and a sample written through the import API is
# read back through PromQL — storage proven end to end before any collector
# exists. Reached through the API server's service proxy, so no port-forward
# and no client image on the runner.
if [ "${EXPECT_VICTORIA_METRICS:-}" = true ]; then
  SECONDS=0
  wait_ready victoria-metrics 120
  kubectl -n victoria-metrics wait deploy/victoria-metrics --for=condition=Available --timeout=120s
  echo "victoria-metrics converged: resourceset Ready and the server Available after ${SECONDS}s"
  pvc="$(kubectl -n victoria-metrics get pvc victoria-metrics -o jsonpath='{.status.phase}')"
  echo "victoria-metrics pvc phase=$pvc ($(kubectl -n victoria-metrics get pvc victoria-metrics -o jsonpath='{.spec.storageClassName} {.status.capacity.storage}'))"
  [ "$pvc" = Bound ] || { echo "::error::the victoria-metrics claim is '$pvc', expected Bound"; exit 1; }
  # A minute in the past: newer samples sit inside -search.latencyOffset (30 s)
  # and an instant query would not return them yet.
  probe="$(mktemp)"
  printf '{"metric":{"__name__":"socle_e2e_probe","job":"e2e"},"values":[42],"timestamps":[%s]}\n' \
    "$(( ($(date +%s) - 60) * 1000 ))" > "$probe"
  kubectl create --raw "$vm/api/v1/import" -f "$probe" > /dev/null
  got=""
  for _ in $(seq 1 12); do
    kubectl get --raw "$vm/internal/force_flush" > /dev/null || true
    got="$(kubectl get --raw "$vm/api/v1/query?query=socle_e2e_probe" 2>/dev/null \
      | python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "")' \
      2>/dev/null || true)"
    [ "$got" = 42 ] && break
    sleep 5
  done
  echo "victoria-metrics read back socle_e2e_probe=$got"
  [ "$got" = 42 ] || { echo "::error::a sample written to victoria-metrics was not read back"; exit 1; }
  # Precedence, on a flag the socle itself sets: -storage.maxHourlySeries is
  # 100000 in the socle's document, and the job says what the tfvars make it.
  # The socle's sibling flags must survive the merge.
  args="$(kubectl -n victoria-metrics get deploy victoria-metrics \
    -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}')"
  echo "victoria-metrics args: $(printf '%s' "$args" | tr '\n' ' ')"
  if [ -n "${EXPECT_VM_MAX_HOURLY_SERIES:-}" ]; then
    printf '%s\n' "$args" | grep -qx -- "--storage.maxHourlySeries=$EXPECT_VM_MAX_HOURLY_SERIES" \
      || { echo "::error::expected --storage.maxHourlySeries=$EXPECT_VM_MAX_HOURLY_SERIES on the live Deployment"; exit 1; }
  fi
  printf '%s\n' "$args" | grep -qx -- "--opentelemetry.usePrometheusNaming" \
    || { echo "::error::the socle's --opentelemetry.usePrometheusNaming did not survive the merge"; exit 1; }
  printf '%s\n' "$args" | grep -qx -- "--retentionPeriod=15d" \
    || { echo "::error::expected the catalog's default --retentionPeriod=15d"; exit 1; }
  # The idle figure docs/catalog/victoria-metrics.md quotes. Best effort: it
  # needs metrics-server, which k3s ships.
  kubectl -n victoria-metrics top pod --no-headers 2>/dev/null \
    | awk '{print "victoria-metrics idle: " $1 " cpu=" $2 " memory=" $3}' || true
fi
# otel_agent when expected, after victoria_metrics, which it writes to: the
# DaemonSet runs on every node, a kubelet metric is queryable by name, and
# every metric the module's nodes and pods dashboard reads has series — the
# dashboard is written on the names VictoriaMetrics stores, and this is what
# keeps it honest. EXPECT_OTEL_AGENT_MEMORY asserts the client's value on a
# request the socle sets.
if [ "${EXPECT_OTEL_AGENT:-}" = true ]; then
  SECONDS=0
  wait_ready otel-agent 120
  kubectl -n otel-agent rollout status daemonset/otel-agent-agent --timeout=180s
  echo "otel-agent converged: resourceset Ready and the DaemonSet rolled out after ${SECONDS}s"
  SECONDS=0
  wait_series k8s_pod_cpu_usage \
    || { echo "::error::no kubelet metric from otel_agent reached victoria-metrics"; exit 1; }
  echo "k8s_pod_cpu_usage: $n series in victoria-metrics, ${SECONDS}s after the agent rolled out"
  # What the agent's metrics are called once stored, for the record.
  kubectl get --raw "$vm/api/v1/label/__name__/values" \
    | python3 -c 'import sys,json; print("stored k8s/container names: " + " ".join(n for n in json.load(sys.stdin)["data"] if n.startswith(("k8s_", "container_"))))'
  check_dashboard otel-agent otel-agent-dashboard-nodes-pods nodes-pods.json '\b(?:k8s|container)_[a-z0-9_]+\b'
  # Precedence, on a request the socle itself sets (128Mi): the client's value
  # must be on the live DaemonSet, the socle's sibling cpu request and memory
  # limit intact.
  res="$(kubectl -n otel-agent get daemonset otel-agent-agent -o jsonpath='{.spec.template.spec.containers[0].resources}')"
  echo "otel-agent resources: $res"
  if [ -n "${EXPECT_OTEL_AGENT_MEMORY:-}" ]; then
    printf '%s' "$res" | python3 -c '
import sys, json
r = json.load(sys.stdin); want = sys.argv[1]
assert r["requests"]["memory"] == want, "client value lost to the socle default: memory %s, expected %s" % (r["requests"]["memory"], want)
assert r["requests"]["cpu"] == "50m", "the socle cpu request did not survive the merge: %s" % r["requests"]["cpu"]
assert r["limits"]["memory"] == "512Mi", "the socle memory limit did not survive the merge: %s" % r["limits"].get("memory")
' "$EXPECT_OTEL_AGENT_MEMORY" || { echo "::error::otel_agent precedence"; exit 1; }
  fi
  kubectl -n otel-agent top pod --no-headers 2>/dev/null \
    | awk '{print "otel-agent: " $1 " cpu=" $2 " memory=" $3}' || true
  kubectl -n victoria-metrics top pod --no-headers 2>/dev/null \
    | awk '{print "victoria-metrics under the agent: " $1 " cpu=" $2 " memory=" $3}' || true
fi
# otel_gateway when expected, after victoria_metrics: the Deployment is
# Available, and each of its three inputs reaches storage — Kubernetes object
# state from k8s_cluster, a scraped endpoint (victoria-metrics' own, which its
# module annotates prometheus.io/scrape), and an application's OTLP, sent by an
# application: podinfo (the hello module, on in both jobs) posts it to the
# gateway's Service, and it must come back enriched by k8s_attributes with the
# sender's workload. Neither the API server's service proxy (kubectl create
# --raw sends a content type the receiver refuses, 415) nor a port-forward
# (the chart binds the receivers to the pod IP, and port-forward dials the
# pod's localhost) can carry it — both measured. Then the workloads
# dashboard, and EXPECT_OTEL_GATEWAY_MEMORY on a request the socle sets
# (128Mi).
if [ "${EXPECT_OTEL_GATEWAY:-}" = true ]; then
  SECONDS=0
  wait_ready otel-gateway 120
  kubectl -n otel-gateway rollout status deployment/otel-gateway --timeout=180s
  echo "otel-gateway converged: resourceset Ready and the Deployment rolled out after ${SECONDS}s"
  SECONDS=0
  wait_series k8s_deployment_available \
    || { echo "::error::no k8s_cluster metric from otel_gateway reached victoria-metrics"; exit 1; }
  echo "k8s_deployment_available: $n series, ${SECONDS}s after the gateway rolled out"
  wait_series 'vm_app_version{k8s_namespace_name="victoria-metrics"}' \
    || { echo "::error::the gateway did not scrape victoria-metrics' annotated pod"; exit 1; }
  echo "scraped: vm_app_version from the annotated victoria-metrics pod, ${SECONDS}s after the gateway rolled out"
  kubectl get --raw "$vm/api/v1/query?query=$(urlq 'up')" \
    | python3 -c 'import sys,json; print("scrape targets: " + " ".join("%s/%s=%s" % (r["metric"].get("k8s_namespace_name", "-"), r["metric"].get("k8s_pod_name", r["metric"].get("service_name", "?")), r["value"][1]) for r in json.load(sys.stdin)["data"]["result"]))'
  # An application's OTLP: one gauge point, a minute old so an instant query
  # sees it past -search.latencyOffset, as OTLP/JSON to /v1/metrics, from
  # podinfo's own curl.
  payload="$(printf '{"resourceMetrics":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"socle-e2e"}}]},"scopeMetrics":[{"metrics":[{"name":"socle.e2e.otlp_probe","gauge":{"dataPoints":[{"asDouble":7,"timeUnixNano":"%s"}]}}]}]}]}' \
    "$(( ($(date +%s) - 60) * 1000000000 ))")"
  kubectl -n hello exec deploy/podinfo -- curl -sSf -H 'Content-Type: application/json' \
    --data-binary "$payload" http://otel-gateway.otel-gateway.svc:4318/v1/metrics > /dev/null
  wait_series 'socle_e2e_otlp_probe{service_name="socle-e2e"}' 24 \
    || { echo "::error::an OTLP metric pushed to the gateway did not reach victoria-metrics"; exit 1; }
  echo "otlp: socle.e2e.otlp_probe sent by hello/podinfo, read back as socle_e2e_otlp_probe"
  # k8s_attributes matched the sender by its connection IP.
  wait_series 'socle_e2e_otlp_probe{k8s_namespace_name="hello",k8s_deployment_name="podinfo"}' 6 \
    || { echo "::error::the gateway's k8s_attributes did not tag the OTLP with its sender's workload"; exit 1; }
  echo "otlp: enriched by k8s_attributes with k8s_namespace_name=hello, k8s_deployment_name=podinfo"
  kubectl get --raw "$vm/api/v1/label/__name__/values" \
    | python3 -c 'import sys,json; print("stored k8s names now: " + " ".join(n for n in json.load(sys.stdin)["data"] if n.startswith("k8s_")))'
  check_dashboard otel-gateway otel-gateway-dashboard-workloads workloads.json '\b(?:k8s_[a-z0-9_]+|up)\b'
  res="$(kubectl -n otel-gateway get deployment otel-gateway -o jsonpath='{.spec.template.spec.containers[0].resources}')"
  echo "otel-gateway resources: $res"
  if [ -n "${EXPECT_OTEL_GATEWAY_MEMORY:-}" ]; then
    printf '%s' "$res" | python3 -c '
import sys, json
r = json.load(sys.stdin); want = sys.argv[1]
assert r["requests"]["memory"] == want, "client value lost to the socle default: memory %s, expected %s" % (r["requests"]["memory"], want)
assert r["requests"]["cpu"] == "100m", "the socle cpu request did not survive the merge: %s" % r["requests"]["cpu"]
assert r["limits"]["memory"] == "1Gi", "the socle memory limit did not survive the merge: %s" % r["limits"].get("memory")
' "$EXPECT_OTEL_GATEWAY_MEMORY" || { echo "::error::otel_gateway precedence"; exit 1; }
  fi
  kubectl -n otel-gateway top pod --no-headers 2>/dev/null \
    | awk '{print "otel-gateway: " $1 " cpu=" $2 " memory=" $3}' || true
  kubectl -n victoria-metrics top pod --no-headers 2>/dev/null \
    | awk '{print "victoria-metrics under both collectors: " $1 " cpu=" $2 " memory=" $3}' || true
fi
# grafana when expected, last of the stack: Grafana answers, it has exactly
# the datasource the socle provisions for victoria_metrics, its sidecar loaded
# the collectors' dashboards from their own namespaces, and a query through
# Grafana's own datasource proxy returns the collectors' metrics — what a
# person opening Grafana sees. Reached with a port-forward: the image is
# distroless, the API needs the admin's basic auth, and the service proxy
# carries no credential of its own. EXPECT_GRAFANA_MEMORY asserts the client's
# value on a request the socle sets (256Mi).
if [ "${EXPECT_GRAFANA:-}" = true ]; then
  SECONDS=0
  wait_ready grafana 120
  kubectl -n grafana rollout status deployment/grafana --timeout=180s
  echo "grafana converged: resourceset Ready and the Deployment rolled out after ${SECONDS}s"
  pass="$(kubectl -n grafana get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
  kubectl -n grafana port-forward svc/grafana 13000:80 > /tmp/grafana-port-forward.log 2>&1 &
  pf=$!
  trap 'kill "$pf" 2> /dev/null || true' EXIT
  for _ in $(seq 1 30); do
    curl -sf http://127.0.0.1:13000/api/health > /dev/null 2>&1 && break
    sleep 2
  done
  gf() { curl -sf -u "admin:$pass" "http://127.0.0.1:13000$1"; }
  echo "grafana health: $(curl -sf http://127.0.0.1:13000/api/health | tr -d '\n ')"
  ds="$(gf /api/datasources)"
  echo "grafana datasources: $(printf '%s' "$ds" | python3 -c 'import sys,json; print(", ".join("%s (%s) %s default=%s" % (d["name"], d["type"], d["url"], d["isDefault"]) for d in json.load(sys.stdin)))')"
  printf '%s' "$ds" | python3 -c '
import sys, json
ds = json.load(sys.stdin)
vm = [d for d in ds if d["uid"] == "victoria-metrics"]
assert len(ds) == 1 and len(vm) == 1, ds
assert vm[0]["type"] == "prometheus" and vm[0]["url"] == "http://victoria-metrics.victoria-metrics.svc:8428" and vm[0]["isDefault"], vm
' || { echo "::error::grafana does not have exactly the VictoriaMetrics datasource the socle provisions"; exit 1; }
  # The modules' dashboards, found by the sidecar in their own namespaces.
  for uid in socle-otel-nodes-pods socle-otel-workloads; do
    found=false
    for _ in $(seq 1 30); do
      gf "/api/dashboards/uid/$uid" > /dev/null 2>&1 && { found=true; break; }
      sleep 2
    done
    [ "$found" = true ] || { echo "::error::dashboard $uid was not loaded by grafana's sidecar"; exit 1; }
    echo "grafana dashboard $uid: $(gf "/api/dashboards/uid/$uid" | python3 -c 'import sys,json; d=json.load(sys.stdin)["dashboard"]; print("%s, %d panels" % (d["title"], len(d["panels"])))')"
  done
  # End to end: the collectors' metric, read through Grafana's datasource.
  through="$(gf "/api/datasources/proxy/uid/victoria-metrics/api/v1/query?query=$(urlq 'count(k8s_pod_cpu_usage)')" \
    | python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else 0)')"
  echo "through grafana's datasource: count(k8s_pod_cpu_usage) = $through"
  [ "$through" != 0 ] || { echo "::error::grafana's datasource returns no collector metric"; exit 1; }
  res="$(kubectl -n grafana get deployment grafana -o jsonpath='{.spec.template.spec.containers[?(@.name=="grafana")].resources}')"
  echo "grafana resources: $res"
  if [ -n "${EXPECT_GRAFANA_MEMORY:-}" ]; then
    printf '%s' "$res" | python3 -c '
import sys, json
r = json.load(sys.stdin); want = sys.argv[1]
assert r["requests"]["memory"] == want, "client value lost to the socle default: memory %s, expected %s" % (r["requests"]["memory"], want)
assert r["requests"]["cpu"] == "50m", "the socle cpu request did not survive the merge: %s" % r["requests"]["cpu"]
' "$EXPECT_GRAFANA_MEMORY" || { echo "::error::grafana precedence"; exit 1; }
  fi
  kubectl -n grafana top pod --no-headers --containers 2>/dev/null \
    | awk '{print "grafana: " $1 "/" $2 " cpu=" $3 " memory=" $4}' || true
  kill "$pf" 2> /dev/null || true
  trap - EXIT
fi
wait_ready socle-root
# external-dns is off by default (it needs a zone and a credential): Ready
# here proves the template renders on the real operator and that a disabled
# module applies nothing.
wait_ready external-dns
if kubectl get namespace external-dns > /dev/null 2>&1; then
  echo "::error::external-dns is disabled but its namespace exists"; exit 1
fi
wait_ready hello
# Gateway API for every client: the gateway_api module brings the standard
# CRDs from upstream, pinned by commit, through Flux — nothing is vendored.
wait_ready gateway-api
for crd in gatewayclasses gateways httproutes grpcroutes referencegrants; do
  established="$(kubectl get crd "$crd.gateway.networking.k8s.io" \
    -o jsonpath='{.status.conditions[?(@.type=="Established")].status}')"
  [ "$established" = True ] || { echo "::error::crd $crd.gateway.networking.k8s.io not established"; exit 1; }
done
echo "Gateway API standard CRDs established: $(kubectl get gitrepository -n flux-system gateway-api -o jsonpath='{.status.artifact.revision}')"
rev="$(kubectl -n flux-system get ocirepository socle -o jsonpath='{.status.artifact.revision}')"
verified="$(kubectl -n flux-system get ocirepository socle \
  -o jsonpath='{.status.conditions[?(@.type=="SourceVerified")].status}')"
echo "revision=$rev SourceVerified=$verified"
case "$rev" in
  "$TAG@"*) ;;
  *) echo "::error::pulled '$rev', expected '$TAG@...'"; exit 1 ;;
esac
[ "$verified" = True ] || { echo "::error::signature not verified"; exit 1; }
replicas="$(kubectl -n hello get deploy podinfo -o jsonpath='{.spec.replicas}')"
echo "hello/podinfo replicas=$replicas"
[ "$replicas" = 1 ] || { echo "::error::expected 1 replica, got '$replicas'"; exit 1; }
# The per-cloud overlay patch: podinfo wears the cloud's colour. Asserted only
# when the job says which one to expect.
if [ -n "${EXPECT_UI_COLOR:-}" ]; then
  color="$(kubectl -n hello get deploy podinfo \
    -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="PODINFO_UI_COLOR")].value}')"
  echo "hello/podinfo ui color=$color"
  [ "$color" = "$EXPECT_UI_COLOR" ] || { echo "::error::expected ui colour '$EXPECT_UI_COLOR', got '$color'"; exit 1; }
fi
