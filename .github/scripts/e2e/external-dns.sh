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
# And two more, called from the Crossplane step while Crossplane is on, for
# the module's own AWS access (docs/catalog/crossplane.md §3):
#
#   access      the access step rendered the Role and the Pod Identity
#               association; the Role, pointed at floci, becomes an IAM role
#               under /socle/<cluster>/ with the Route 53 policy scoped to
#               domain_filters; the association never syncs on floci, so the
#               child ResourceSet external-dns-workload is withheld — no
#               HelmRelease is applied before the association exists
#   access-off  the module turned off: the IAM role is deleted, the
#               namespace goes
#
# floci runs no Pod Identity and implements no association API: what the
# access phases cannot prove — the association reaching EKS, the pod getting
# the role's credentials, IAM enforcing the policy — needs a real account
# (docs/catalog/external-dns.md).
#
# Runs on the host: aws talks to floci on AWS_ENDPOINT_URL (localhost), the
# pod talks to floci on the Docker bridge, where floci and its k3s both live.
set -euo pipefail

ZONE="${ZONE:-e2e.socle.test}"
OWNER="${OWNER:-}"
CLUSTER="${CLUSTER:-socle-e2e-catalog}"
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
  : "${OWNER:?the TXT owner id the records must carry}"
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

# The module's managed resources, by their full kind.
ROLE=role.iam.aws.m.upbound.io
PIA=podidentityassociation.eks.aws.m.upbound.io

case "${1:?prepare, publish, kept, deleted, access or access-off}" in
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
  access)
    for _ in $(seq 1 60); do
      kubectl -n "$NS" get "$ROLE" external-dns > /dev/null 2>&1 \
        && kubectl -n "$NS" get "$PIA" external-dns > /dev/null 2>&1 && break
      sleep 5
    done
    kubectl -n "$NS" get "$ROLE" external-dns > /dev/null \
      || { echo "::error::the access step rendered no Role"; kubectl -n flux-system get resourceset external-dns -o yaml || true; exit 1; }
    # The one seam, as in crossplane.sh: the module leaves providerConfigRef
    # at its default, the socle's Pod Identity ClusterProviderConfig, which
    # floci cannot serve; floci's own is named after the fact.
    for kind in "$ROLE" "$PIA"; do
      kubectl -n "$NS" patch "$kind" external-dns --type merge \
        -p '{"spec":{"providerConfigRef":{"kind":"ClusterProviderConfig","name":"floci"}}}'
    done
    role="$CLUSTER-external-dns"
    SECONDS=0
    arn=""
    for _ in $(seq 1 60); do
      arn="$(aws iam get-role --role-name "$role" --query Role.Arn --output text 2>/dev/null || true)"
      [ -n "$arn" ] && break
      sleep 5
    done
    [ -n "$arn" ] || { echo "::error::the module's Role never became IAM role $role"; kubectl -n "$NS" get "$ROLE" external-dns -o yaml || true; exit 1; }
    echo "Role → IAM role $arn after ${SECONDS}s"
    case "$arn" in
      */socle/"$CLUSTER"/"$role") ;;
      *) echo "::error::the role is not under /socle/$CLUSTER/: $arn"; exit 1 ;;
    esac
    aws iam get-role --role-name "$role" --query Role.AssumeRolePolicyDocument --output json \
      | grep -q pods.eks.amazonaws.com \
      || { echo "::error::the role does not trust pods.eks.amazonaws.com"; exit 1; }
    policy="$(aws iam get-role-policy --role-name "$role" --policy-name route53 --query PolicyDocument --output json)"
    echo "$policy"
    for want in route53:ChangeResourceRecordSetsNormalizedRecordNames '"*.e2e.socle.test"' '"e2e.socle.test"' route53:ListHostedZones; do
      case "$policy" in *"$want"*) ;; *) echo "::error::the route53 policy lacks $want"; exit 1 ;; esac
    done
    # Ordering: the association cannot sync on floci, so the workload's
    # dependsOn is never met and the chart must never have been applied. One
    # full minute after the Role turned into IAM, the HelmRelease is still
    # absent. (A step's health check alone did not hold it: an MR that was
    # never created has no Ready condition, which kstatus reads as healthy.)
    sleep 60
    echo "association: Synced=$(kubectl -n "$NS" get "$PIA" external-dns \
      -o jsonpath='{.status.conditions[?(@.type=="Synced")].status}') (floci has no association API, expected not True)"
    if kubectl -n "$NS" get helmrelease external-dns > /dev/null 2>&1; then
      echo "::error::the workload step was applied before the association existed"; exit 1
    fi
    if kubectl -n "$NS" get deploy external-dns > /dev/null 2>&1; then
      echo "::error::external-dns runs without its association"; exit 1
    fi
    echo "workload withheld while the association is not Ready: $(kubectl -n flux-system get resourceset external-dns-workload \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}')"
    ;;
  access-off)
    # The association's finalizer waits on an API floci does not have:
    # released by hand, the only thing done here that a real cluster does
    # not need.
    for _ in $(seq 1 36); do
      kubectl -n "$NS" get "$PIA" external-dns > /dev/null 2>&1 || break
      kubectl -n "$NS" patch "$PIA" external-dns --type merge -p '{"metadata":{"finalizers":[]}}' > /dev/null 2>&1 || true
      sleep 5
    done
    role="$CLUSTER-external-dns"
    for _ in $(seq 1 36); do
      aws iam get-role --role-name "$role" > /dev/null 2>&1 || break
      sleep 5
    done
    if aws iam get-role --role-name "$role" > /dev/null 2>&1; then
      echo "::error::IAM role $role survived the module turned off"; exit 1
    fi
    echo "module off → IAM role $role gone"
    for _ in $(seq 1 36); do
      kubectl get namespace "$NS" > /dev/null 2>&1 || { echo "namespace $NS is gone"; exit 0; }
      sleep 5
    done
    echo "::error::namespace $NS still present after 180 s"
    kubectl -n "$NS" get managed -o yaml || true
    exit 1
    ;;
  *)
    echo "usage: $0 prepare|publish|kept|deleted|access|access-off" >&2
    exit 2
    ;;
esac
