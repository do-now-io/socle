#!/usr/bin/env bash
# The proof both e2e jobs share: socle-root, hello and gateway-api Ready, the
# Gateway API CRDs established, the artifact pulled by the exact tag TAG with
# its signature verified, podinfo at 1 replica.
# The proof both e2e jobs share: socle-root, external-dns (disabled) and hello Ready, the artifact
# pulled by the exact tag TAG with its signature verified, podinfo at 1 replica.
# Optional expectations come from the environment, one variable per module
# (EXPECT_UI_COLOR, EXPECT_ARGOCD, EXPECT_VICTORIA_METRICS): the job says what
# the catalog defaults and its tfvars make true, the script checks it.
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
  vm=/api/v1/namespaces/victoria-metrics/services/victoria-metrics:http/proxy
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
