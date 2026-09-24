#!/usr/bin/env bash
# external-dns against floci's emulated Route 53, in four steps the e2e job
# calls between its tofu applies:
#
#   prepare  a fake hosted zone, the external-dns namespace, and the
#            external-dns-aws Secret the aws block reads (static test keys,
#            floci's endpoint as seen from inside k3s) — before the module is
#            enabled, so the pod starts with them
#   publish  the client's kube.external_dns.values override a socle default
#            (txtOwnerId), and an Ingress and an ExternalName Service become an
#            A and a CNAME, each with a TXT ownership record naming that owner
#   kept     upsert-only: the Ingress is deleted, its A record stays
#   deleted  sync (after the job re-applies with policy = "sync"): the A
#            record and its TXT go, the CNAME whose source still exists stays
#
# Runs on the host: aws talks to floci on AWS_ENDPOINT_URL (localhost), the
# pod talks to floci on the Docker bridge, where floci and its k3s both live.
set -euo pipefail

ZONE="${ZONE:-e2e.socle.test}"
OWNER="${OWNER:?the TXT owner id the records must carry}"
NS=external-dns
APPS=e2e-dns

zone_id() {
  aws route53 list-hosted-zones-by-name --dns-name "$ZONE" \
    --query "HostedZones[?Name=='$ZONE.'].Id | [0]" --output text
}

# "<name> <type>" → the first value of that record set, or empty.
record() {
  aws route53 list-resource-record-sets --hosted-zone-id "$(zone_id)" \
    --query "ResourceRecordSets[?Name=='$1.$ZONE.' && Type=='$2'].ResourceRecords[0].Value | [0]" \
    --output text | sed 's/^None$//'
}

# Poll until `record name type` matches (or, with "absent", is empty).
wait_record() {
  local name="$1" type="$2" want="$3" got=""
  for _ in $(seq 1 36); do
    got="$(record "$name" "$type")"
    if [ "$want" = absent ]; then [ -z "$got" ] && { echo "$name.$ZONE $type: gone"; return 0; }
    else case "$got" in *"$want"*) echo "$name.$ZONE $type: $got"; return 0 ;; esac
    fi
    sleep 5
  done
  echo "::error::$name.$ZONE $type is '$got', expected ${want}"
  aws route53 list-resource-record-sets --hosted-zone-id "$(zone_id)" --output table || true
  kubectl -n "$NS" logs deploy/external-dns --tail=40 || true
  return 1
}

wait_release() {
  for _ in $(seq 1 60); do
    kubectl -n "$NS" get helmrelease external-dns > /dev/null 2>&1 && break
    sleep 5
  done
  kubectl -n "$NS" wait helmrelease/external-dns --for=condition=Ready --timeout=300s
  # A new policy reaches the chart through the socle-values ConfigMap, not
  # the HelmRelease spec: helm-controller picks it up through its watch label,
  # a few seconds after the apply. Poll the Deployment rather than trust the
  # Ready condition of the previous generation.
  args=""
  for _ in $(seq 1 36); do
    args="$(kubectl -n "$NS" get deploy external-dns -o jsonpath='{.spec.template.spec.containers[0].args}')"
    case "$args" in *"--policy=$1"*) break ;; esac
    sleep 5
  done
  echo "external-dns args: $args"
  case "$args" in
    *"--policy=$1"*) ;;
    *) echo "::error::external-dns does not run with --policy=$1 after 180 s"; return 1 ;;
  esac
  kubectl -n "$NS" rollout status deploy/external-dns --timeout=180s
  # Precedence: the socle sets txtOwnerId (to the cluster name, SOCLE_OWNER)
  # and kube.external_dns.values sets it too (OWNER). The client must win —
  # socle-values, then client-values, nothing inline after them
  # (docs/flux-catalog.md §6). A key the socle leaves unset would prove
  # nothing.
  case "$args" in
    *"--txt-owner-id=$OWNER\""*) echo "txt owner: the client's $OWNER, over the socle's ${SOCLE_OWNER:-?}" ;;
    *) echo "::error::kube.external_dns.values did not override the socle's txtOwnerId (want --txt-owner-id=$OWNER)"; return 1 ;;
  esac
}

case "${1:?prepare, publish, kept or deleted}" in
  prepare)
    [ "$(zone_id)" != None ] || aws route53 create-hosted-zone --name "$ZONE" \
      --caller-reference "socle-e2e-$(date +%s)" > /dev/null
    echo "hosted zone $ZONE: $(zone_id)"
    ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' floci)"
    kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n "$NS" create secret generic external-dns-aws \
      --from-literal=AWS_ACCESS_KEY_ID=test \
      --from-literal=AWS_SECRET_ACCESS_KEY=test \
      --from-literal=AWS_ENDPOINT_URL="http://$ip:4566" \
      --dry-run=client -o yaml | kubectl apply -f -
    echo "external-dns-aws points the pod at http://$ip:4566"
    ;;
  publish)
    wait_release upsert-only
    kubectl create namespace "$APPS" --dry-run=client -o yaml | kubectl apply -f -
    # external-dns 0.22 reads external-dns.kubernetes.io/ annotations; the
    # older external-dns.alpha.kubernetes.io/ prefix is ignored.
    kubectl -n "$APPS" apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  annotations:
    external-dns.kubernetes.io/target: 203.0.113.10
spec:
  rules:
    - host: app.$ZONE
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: app, port: { number: 80 } } }
---
apiVersion: v1
kind: Service
metadata:
  name: legacy
  annotations:
    external-dns.kubernetes.io/hostname: legacy.$ZONE
spec:
  type: ExternalName
  externalName: backend.example.org
EOF
    wait_record app A 203.0.113.10
    wait_record legacy CNAME backend.example.org
    wait_record socle-a-app TXT "external-dns/owner=$OWNER"
    wait_record socle-cname-legacy TXT "external-dns/owner=$OWNER"
    ;;
  kept)
    kubectl -n "$APPS" delete ingress app --wait=true
    # One full interval (1m) and more: with upsert-only nothing is deleted,
    # however many loops run.
    sleep 75
    [ -n "$(record app A)" ] || { echo "::error::upsert-only deleted app.$ZONE"; exit 1; }
    echo "app.$ZONE A kept under upsert-only: $(record app A)"
    ;;
  deleted)
    wait_release sync
    wait_record app A absent
    wait_record socle-a-app TXT absent
    wait_record legacy CNAME backend.example.org
    ;;
  *)
    echo "usage: $0 prepare|publish|kept|deleted" >&2
    exit 2
    ;;
esac
