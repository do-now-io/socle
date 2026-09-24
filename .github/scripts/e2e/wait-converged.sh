#!/usr/bin/env bash
# The proof both e2e jobs share: socle-root, hello and gateway-api Ready, the
# Gateway API CRDs established, the artifact pulled by the exact tag TAG with
# its signature verified, podinfo at 1 replica.
# The proof both e2e jobs share: socle-root, external-dns (disabled) and hello Ready, the artifact
# pulled by the exact tag TAG with its signature verified, podinfo at 1 replica.
# Optional expectations come from the environment, one variable per module
# (EXPECT_UI_COLOR, EXPECT_ARGOCD): the job says what the catalog defaults and
# its tfvars make true, the script checks it.
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
