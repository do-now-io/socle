#!/usr/bin/env bash
# The proof both e2e jobs share: socle-root, hello and gateway-api Ready, the
# Gateway API CRDs established, the artifact pulled by the exact tag TAG with
# its signature verified, podinfo at 1 replica.
set -euo pipefail
wait_ready() {
  for _ in $(seq 1 60); do
    status="$(kubectl -n flux-system get resourceset "$1" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    [ "$status" = True ] && { echo "resourceset/$1 Ready"; return 0; }
    sleep 5
  done
  echo "::error::resourceset $1 never became Ready"
  return 1
}
wait_ready socle-root
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
