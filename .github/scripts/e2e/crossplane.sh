#!/usr/bin/env bash
# The crossplane module on floci, in two phases called by e2e-aws-catalog
# around its tofu applies. docs/catalog/crossplane.md quotes the timings.
#
#   crossplane.sh on   — after kube.crossplane.enabled=true with one client
#                        value: the ResourceSet Ready (core, AWS providers,
#                        ProviderConfig), the client's value on
#                        the live Deployment, then what a module declares for
#                        its AWS access — a Role and a PodIdentityAssociation,
#                        following docs/catalog/crossplane.md's contract —
#                        against floci's IAM: the role exists, then goes.
#   crossplane.sh off  — after enabled=false: the HelmRelease is gone, and
#                        what Crossplane leaves behind is printed.
#
# floci is the one seam. The socle's ClusterProviderConfig `default` uses EKS
# Pod Identity, which floci does not run; the module-shaped resources below
# name a second one, `floci`, created here with static test credentials and
# floci's endpoint. floci implements IAM but
# not the EKS Pod Identity association API, and ignores permissions
# boundaries: the role is proven, the association and the boundary are not.
set -euo pipefail

ready() {  # ready <kind> <name> [namespace] [attempts of 5 s]
  local ns=()
  [ -n "${3:-}" ] && ns=(-n "$3")
  for _ in $(seq 1 "${4:-120}"); do
    [ "$(kubectl "${ns[@]}" get "$1" "$2" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)" = True ] && return 0
    sleep 5
  done
  echo "::error::$1/$2 never turned Ready"
  kubectl "${ns[@]}" get "$1" "$2" -o yaml || true
  return 1
}

gone() {  # gone <namespace> <helmrelease> — NotFound, and nothing else, is gone
  for _ in $(seq 1 36); do
    if out="$(kubectl -n "$1" get helmrelease "$2" 2>&1)"; then
      sleep 5
      continue
    fi
    case "$out" in
      *NotFound*|*"not found"*) echo "helmrelease $1/$2 is gone: $out"; return 0 ;;
      *) echo "::error::kubectl failed for a reason other than NotFound: $out"; return 1 ;;
    esac
  done
  echo "::error::helmrelease $1/$2 still present after 180 s"
  return 1
}

on() {
  SECONDS=0
  ready resourceset crossplane flux-system
  kubectl -n crossplane-system wait deploy/crossplane deploy/crossplane-rbac-manager \
    --for=condition=Available --timeout=120s
  echo "crossplane converged — core, AWS providers, ProviderConfig — after ${SECONDS}s"
  kubectl get provider.pkg.crossplane.io

  # valuesFrom order: the socle's ConfigMap, then the client's. The client's
  # 48Mi must beat the socle's 32Mi, and the socle's `limits: null` must
  # still have removed the chart's limits.
  mem="$(kubectl -n crossplane-system get deploy crossplane-rbac-manager \
    -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}')"
  lim="$(kubectl -n crossplane-system get deploy crossplane \
    -o jsonpath='{.spec.template.spec.containers[0].resources.limits}')"
  echo "rbac-manager requests.memory='$mem', crossplane limits='$lim'"
  [ "$mem" = 48Mi ] || { echo "::error::the client's value did not win over the socle's (want 48Mi)"; exit 1; }
  [ -z "$lim" ] || { echo "::error::the socle's limits: null did not reach the chart"; exit 1; }
  kubectl get clusterproviderconfig.aws.m.upbound.io default -o jsonpath='{.spec.credentials.source}' | grep -qx PodIdentity \
    || { echo "::error::the socle's ClusterProviderConfig is not on Pod Identity"; exit 1; }

  # The k3s node floci started shares its Docker network: the pods reach floci
  # at its address there, never at the runner's localhost.
  floci_ip="$(docker inspect floci --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' | awk '{print $1}')"
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: floci-credentials
  namespace: crossplane-system
stringData:
  credentials: |
    [default]
    aws_access_key_id = test
    aws_secret_access_key = test
---
apiVersion: aws.m.upbound.io/v1beta1
kind: ClusterProviderConfig
metadata:
  name: floci
spec:
  credentials:
    source: Secret
    secretRef: { namespace: crossplane-system, name: floci-credentials, key: credentials }
  endpoint:
    hostnameImmutable: true
    services: [iam, eks, sts]
    url: { type: Static, static: "http://${floci_ip}:4566" }
  skip_credentials_validation: true
  skip_metadata_api_check: true
  skip_region_validation: true
  skip_requesting_account_id: true
---
apiVersion: v1
kind: Namespace
metadata:
  name: e2e-probe
---
# Exactly what a module's AWS overlay renders: its role under
# /socle/<cluster>/, trusted by Pod Identity, with its own policy (the
# boundary is empty on this fixture root, which has no foundations), then
# the association with its ServiceAccount.
apiVersion: iam.aws.m.upbound.io/v1beta1
kind: Role
metadata:
  name: probe
  namespace: e2e-probe
  annotations:
    crossplane.io/external-name: socle-e2e-catalog-e2e-probe
spec:
  providerConfigRef: { kind: ClusterProviderConfig, name: floci }
  forProvider:
    path: /socle/socle-e2e-catalog/
    assumeRolePolicy: '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pods.eks.amazonaws.com"},"Action":["sts:AssumeRole","sts:TagSession"]}]}'
    inlinePolicy:
      - name: route53
        policy: '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["route53:ChangeResourceRecordSets"],"Resource":"arn:aws:route53:::hostedzone/*"}]}'
---
apiVersion: eks.aws.m.upbound.io/v1beta1
kind: PodIdentityAssociation
metadata:
  name: probe
  namespace: e2e-probe
spec:
  providerConfigRef: { kind: ClusterProviderConfig, name: floci }
  forProvider:
    region: eu-west-3
    clusterName: socle-e2e-catalog
    namespace: e2e-probe
    serviceAccount: probe
    roleArnRef: { name: probe }
EOF
  SECONDS=0
  role=socle-e2e-catalog-e2e-probe
  for _ in $(seq 1 60); do
    arn="$(aws iam get-role --role-name "$role" --query Role.Arn --output text 2>/dev/null || true)"
    [ -n "$arn" ] && break
    sleep 5
  done
  [ -n "$arn" ] || {
    echo "::error::the module-shaped Role never became IAM role $role in floci"
    kubectl -n e2e-probe get managed -o yaml || true
    exit 1
  }
  echo "Role → IAM role $arn after ${SECONDS}s"
  case "$arn" in
    */socle/socle-e2e-catalog/"$role") ;;
    *) echo "::error::the role is not under /socle/<cluster>/: $arn"; exit 1 ;;
  esac
  aws iam get-role-policy --role-name "$role" --policy-name route53 --query PolicyDocument --output json \
    | grep -q route53:ChangeResourceRecordSets \
    || { echo "::error::the role's inline policy did not reach IAM"; exit 1; }
  echo "Pod Identity association (floci has no such API, expected unsynced):"
  kubectl -n e2e-probe get podidentityassociation.eks.aws.m.upbound.io \
    -o jsonpath='{range .items[*]}{.metadata.name} Synced={.status.conditions[?(@.type=="Synced")].status}{"\n"}{end}' || true

  SECONDS=0
  # The association never synced on floci; its finalizer cannot complete
  # there, so it is not waited for.
  kubectl -n e2e-probe delete podidentityassociation.eks.aws.m.upbound.io probe --wait=false
  kubectl -n e2e-probe delete role.iam.aws.m.upbound.io probe --wait=true --timeout=180s
  for _ in $(seq 1 36); do
    aws iam get-role --role-name "$role" > /dev/null 2>&1 || break
    sleep 5
  done
  if aws iam get-role --role-name "$role" > /dev/null 2>&1; then
    echo "::error::IAM role $role survived its Role"
    exit 1
  fi
  echo "Role deleted → IAM role gone after ${SECONDS}s"
  kubectl -n crossplane-system top pod 2>/dev/null || echo "(no metrics)"
}

off() {
  gone crossplane-system crossplane
  echo "left behind by design (docs/catalog/crossplane.md):" \
    "$(kubectl get crd -o name | grep -c '\.crossplane\.io$') Crossplane CRDs," \
    "$(kubectl get crd -o name | grep -c '\.upbound\.io$') provider CRDs," \
    "$(kubectl get validatingwebhookconfiguration -o name | grep -c crossplane) webhook configuration(s)"
}

"$1"
