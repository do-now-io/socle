#!/usr/bin/env bash
# The proof both e2e jobs share: socle-root and hello Ready, the artifact
# pulled by the exact tag TAG with its signature verified, podinfo at 1 replica,
# and, when the inputs enable gateway_api, its ResourceSet Ready with the socle
# GatewayClass present and accepted by the implementation.
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

# gateway_api: read the module's own inputs off the cluster rather than an env
# var, so the check follows whatever the root under test declared. The class
# is what the other modules rely on; Accepted=True is the implementation's
# controller saying it runs — on k3s this needs no cloud load balancer, since
# the module creates no Gateway (docs/catalog/gateway-api.md).
gw_enabled="$(kubectl -n flux-system get resourcesetinputprovider socle \
  -o jsonpath='{.spec.defaultValues.modules.gateway_api.enabled}')"
gw_impl="$(kubectl -n flux-system get resourcesetinputprovider socle \
  -o jsonpath='{.spec.defaultValues.modules.gateway_api.implementation}')"
echo "gateway_api enabled=$gw_enabled implementation=$gw_impl"
if [ "$gw_enabled" = true ]; then
  wait_ready gateway-api
  if [ "$gw_impl" != managed ]; then
    for _ in $(seq 1 60); do
      accepted="$(kubectl get gatewayclass socle \
        -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)"
      [ "$accepted" = True ] && break
      sleep 5
    done
    controller="$(kubectl get gatewayclass socle -o jsonpath='{.spec.controllerName}' 2>/dev/null || true)"
    echo "gatewayclass/socle controllerName=$controller Accepted=$accepted"
    [ -n "$controller" ] || { echo "::error::gatewayclass socle does not exist"; exit 1; }
    [ "$accepted" = True ] || { echo "::error::gatewayclass socle never Accepted by $gw_impl"; exit 1; }
  fi
fi
