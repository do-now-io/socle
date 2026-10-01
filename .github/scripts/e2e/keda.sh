#!/usr/bin/env bash
# The keda module on floci, in phases called by e2e-aws-catalog around its
# tofu applies. docs/catalog/keda.md quotes the timings.
#
# Two phases run from the Crossplane step, while Crossplane is on, for the
# module's own AWS access (docs/catalog/crossplane.md §3) with
# kube.keda.services = ["sqs"]:
#
#   access      the module rendered its Role and Pod Identity association;
#               the Role, pointed at floci, becomes an IAM role under
#               /socle/<cluster>/ whose one inline policy reads SQS queue
#               attributes and nothing else — cloudwatch, kinesis and
#               dynamodb were not named, so they are not there; the
#               association never syncs on floci, so the child ResourceSet
#               keda-workload is withheld: no HelmRelease before the
#               association exists
#   access-off  the module turned off: the IAM role is deleted, the
#               namespace goes
#
# Three more, with Crossplane off and no service named — KEDA as a client
# with a cron or credential-based trigger gets it:
#
#   on     the ResourceSet Ready, the three Deployments Available, the
#          external metrics APIService Available, the client's
#          kube.keda.values overriding a socle default (the operator's memory
#          request, EXPECT_OPERATOR_MEMORY) on the live Deployment while the
#          socle's sibling cpu request survives, the cloud-access annotation
#          empty
#   scale  a Deployment at zero, scaled by a ScaledObject on the depth of an
#          SQS queue in floci — static test keys through a
#          TriggerAuthentication, awsEndpoint pointed at floci — up when
#          messages arrive, back to zero when the queue is purged
#   off    the module off: the HelmRelease and the namespace gone, the
#          APIService gone, the CRDs kept (helm.sh/resource-policy: keep) so
#          a client's ScaledObjects outlive the module
#
# floci implements IAM and SQS, not the EKS Pod Identity association API,
# and enforces no IAM policy: the role and the scaler are proven for real,
# the association and the boundary are not (docs/catalog/keda.md).
#
# Runs on the host: aws talks to floci on AWS_ENDPOINT_URL (localhost), the
# operator pod talks to floci on the Docker bridge, where floci and its k3s
# both live.
set -euo pipefail

CLUSTER="${CLUSTER:-socle-e2e-catalog}"
NS=keda
APPS=e2e-keda
QUEUE=e2e-keda

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

# wait_replicas <deployment> <want> [attempts of 5 s]
wait_replicas() {
  local got=""
  for _ in $(seq 1 "${3:-36}"); do
    got="$(kubectl -n "$APPS" get deploy "$1" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
    [ "$got" = "$2" ] && { echo "$APPS/$1 replicas=$got after ${SECONDS}s"; return 0; }
    sleep 5
  done
  echo "::error::$APPS/$1 replicas is '$got', expected $2"
  kubectl -n "$APPS" get scaledobject,hpa -o wide || true
  kubectl -n "$APPS" describe scaledobject worker || true
  kubectl -n "$NS" logs deploy/keda-operator --tail=40 || true
  return 1
}

queue_url() {  # as the operator pod reaches it, through the Docker bridge
  local ip
  ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' floci)"
  echo "http://$ip:4566/000000000000/$QUEUE"
}

# The module's managed resources, by their full kind.
ROLE=role.iam.aws.m.upbound.io
PIA=podidentityassociation.eks.aws.m.upbound.io

case "${1:?access, access-off, on, scale or off}" in
  access)
    for _ in $(seq 1 60); do
      kubectl -n "$NS" get "$ROLE" keda-operator > /dev/null 2>&1 \
        && kubectl -n "$NS" get "$PIA" keda-operator > /dev/null 2>&1 && break
      sleep 5
    done
    kubectl -n "$NS" get "$ROLE" keda-operator > /dev/null \
      || { echo "::error::the module rendered no Role"; kubectl -n flux-system get resourceset keda -o yaml || true; exit 1; }
    # The one seam, as in crossplane.sh: the module leaves providerConfigRef
    # at its default, the socle's Pod Identity ClusterProviderConfig, which
    # floci cannot serve; floci's own is named after the fact.
    for kind in "$ROLE" "$PIA"; do
      kubectl -n "$NS" patch "$kind" keda-operator --type merge \
        -p '{"spec":{"providerConfigRef":{"kind":"ClusterProviderConfig","name":"floci"}}}'
    done
    role="$CLUSTER-keda-operator"
    SECONDS=0
    arn=""
    for _ in $(seq 1 60); do
      arn="$(aws iam get-role --role-name "$role" --query Role.Arn --output text 2>/dev/null || true)"
      [ -n "$arn" ] && break
      sleep 5
    done
    [ -n "$arn" ] || { echo "::error::the module's Role never became IAM role $role"; kubectl -n "$NS" get "$ROLE" keda-operator -o yaml || true; exit 1; }
    echo "Role → IAM role $arn after ${SECONDS}s"
    case "$arn" in
      */socle/"$CLUSTER"/"$role") ;;
      *) echo "::error::the role is not under /socle/$CLUSTER/: $arn"; exit 1 ;;
    esac
    aws iam get-role --role-name "$role" --query Role.AssumeRolePolicyDocument --output json \
      | grep -q pods.eks.amazonaws.com \
      || { echo "::error::the role does not trust pods.eks.amazonaws.com"; exit 1; }
    policy="$(aws iam get-role-policy --role-name "$role" --policy-name scalers --query PolicyDocument --output json)"
    echo "$policy"
    # Named: sqs, so its one read call. Not named: everything else — the
    # policy must carry no other service, and no wildcard action.
    case "$policy" in *'"sqs:GetQueueAttributes"'*) ;; *) echo "::error::the scalers policy lacks sqs:GetQueueAttributes"; exit 1 ;; esac
    for absent in cloudwatch: kinesis: dynamodb: '"sqs:*"' '"*:' 'sqs:SendMessage' 'sqs:ReceiveMessage'; do
      case "$policy" in *"$absent"*) echo "::error::the scalers policy carries $absent, which was not asked for"; exit 1 ;; esac
    done
    echo "policy scoped to the one service named: sqs:GetQueueAttributes only"
    # Ordering: the association cannot sync on floci, so the workload's
    # dependsOn is never met and the chart must never have been applied.
    sleep 60
    echo "association: Synced=$(kubectl -n "$NS" get "$PIA" keda-operator \
      -o jsonpath='{.status.conditions[?(@.type=="Synced")].status}') (floci has no association API, expected not True)"
    if kubectl -n "$NS" get helmrelease keda > /dev/null 2>&1; then
      echo "::error::the workload was applied before the association existed"; exit 1
    fi
    if kubectl -n "$NS" get deploy keda-operator > /dev/null 2>&1; then
      echo "::error::keda-operator runs without its association"; exit 1
    fi
    echo "workload withheld while the association is not Ready: $(kubectl -n flux-system get resourceset keda-workload \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}')"
    ;;
  access-off)
    # The association's finalizer waits on an API floci does not have:
    # released by hand, the only thing done here that a real cluster does
    # not need.
    for _ in $(seq 1 36); do
      kubectl -n "$NS" get "$PIA" keda-operator > /dev/null 2>&1 || break
      kubectl -n "$NS" patch "$PIA" keda-operator --type merge -p '{"metadata":{"finalizers":[]}}' > /dev/null 2>&1 || true
      sleep 5
    done
    role="$CLUSTER-keda-operator"
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
  on)
    : "${EXPECT_OPERATOR_MEMORY:?the operator memory request kube.keda.values sets}"
    SECONDS=0
    ready resourceset keda flux-system
    kubectl -n "$NS" wait deploy/keda-operator deploy/keda-operator-metrics-apiserver deploy/keda-admission-webhooks \
      --for=condition=Available --timeout=180s
    echo "keda converged: resourceset Ready and the three Deployments Available after ${SECONDS}s"
    # The external metrics API, registered by the metrics server and
    # answered by it: the HPA controller reads ScaledObject metrics there.
    for _ in $(seq 1 24); do
      [ "$(kubectl get apiservice v1beta1.external.metrics.k8s.io \
        -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)" = True ] && break
      sleep 5
    done
    [ "$(kubectl get apiservice v1beta1.external.metrics.k8s.io \
      -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')" = True ] \
      || { echo "::error::v1beta1.external.metrics.k8s.io is not Available"; kubectl get apiservice v1beta1.external.metrics.k8s.io -o yaml; exit 1; }
    echo "apiservice v1beta1.external.metrics.k8s.io Available"
    # Precedence, on a key the socle itself sets: the client's memory request
    # must be on the live Deployment, and the socle's sibling cpu request
    # must survive the merge (docs/flux-catalog.md §6).
    req="$(kubectl -n "$NS" get deploy keda-operator \
      -o jsonpath='{.spec.template.spec.containers[0].resources.requests}')"
    echo "keda-operator requests: $req"
    case "$req" in *"\"memory\":\"$EXPECT_OPERATOR_MEMORY\""*) ;; *) echo "::error::client value lost to the socle default: want memory $EXPECT_OPERATOR_MEMORY in $req"; exit 1 ;; esac
    case "$req" in *'"cpu":"50m"'*) ;; *) echo "::error::the socle's cpu request did not survive the merge: $req"; exit 1 ;; esac
    # No service named: no role, and the annotation that would roll the
    # operator when one appears is empty.
    access="$(kubectl -n "$NS" get deploy keda-operator \
      -o jsonpath='{.spec.template.metadata.annotations.socle\.do-now\.io/cloud-access}')"
    [ -z "$access" ] || { echo "::error::cloud-access annotation is '$access', expected empty"; exit 1; }
    if kubectl -n "$NS" get "$ROLE" keda-operator > /dev/null 2>&1; then
      echo "::error::a Role was rendered with no service named"; exit 1
    fi
    echo "no service named: no Role, cloud-access annotation empty"
    kubectl -n "$NS" top pod 2>/dev/null || echo "(kubectl top unavailable: no metrics-server on this k3s)"
    ;;
  scale)
    aws sqs create-queue --queue-name "$QUEUE" > /dev/null
    url="$(queue_url)"
    endpoint="${url%/000000000000/*}"
    echo "queue $QUEUE, as the operator reaches it: $url (endpoint $endpoint)"
    kubectl create namespace "$APPS" --dry-run=client -o yaml | kubectl apply -f -
    # Static test keys, the way a client without a cloud role hands KEDA a
    # credential: a Secret referenced by a TriggerAuthentication — never
    # through kube.keda.values, which refuses them.
    kubectl -n "$APPS" create secret generic sqs-keys \
      --from-literal=AWS_ACCESS_KEY_ID=test \
      --from-literal=AWS_SECRET_ACCESS_KEY=test \
      --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n "$APPS" apply -f - <<EOF
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: sqs-keys
spec:
  secretTargetRef:
    - parameter: awsAccessKeyID
      name: sqs-keys
      key: AWS_ACCESS_KEY_ID
    - parameter: awsSecretAccessKey
      name: sqs-keys
      key: AWS_SECRET_ACCESS_KEY
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
spec:
  replicas: 1
  selector:
    matchLabels: { app: worker }
  template:
    metadata:
      labels: { app: worker }
    spec:
      containers:
        - name: worker
          image: registry.k8s.io/pause:3.10
          securityContext:
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            runAsUser: 65534
            capabilities: { drop: [ALL] }
            seccompProfile: { type: RuntimeDefault }
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: worker
spec:
  scaleTargetRef:
    name: worker
  minReplicaCount: 0
  maxReplicaCount: 3
  pollingInterval: 5
  cooldownPeriod: 15
  triggers:
    - type: aws-sqs-queue
      authenticationRef:
        name: sqs-keys
      metadata:
        queueURL: $url
        queueLength: "5"
        awsRegion: eu-west-3
        awsEndpoint: $endpoint
EOF
    SECONDS=0
    ready scaledobject worker "$APPS" 24
    echo "scaledobject Ready after ${SECONDS}s: $(kubectl -n "$APPS" get scaledobject worker -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}')"
    # Empty queue: KEDA takes the Deployment from 1 to 0.
    wait_replicas worker 0
    # Ten messages, queueLength 5: two replicas.
    for i in $(seq 1 10); do
      aws sqs send-message --queue-url "http://localhost:4566/000000000000/$QUEUE" --message-body "job-$i" > /dev/null
    done
    echo "10 messages sent; ApproximateNumberOfMessages=$(aws sqs get-queue-attributes --queue-url "http://localhost:4566/000000000000/$QUEUE" --attribute-names ApproximateNumberOfMessages --query Attributes.ApproximateNumberOfMessages --output text)"
    SECONDS=0
    wait_replicas worker 2
    kubectl -n "$APPS" get hpa -o wide
    # Purged: back to zero after the cooldown.
    aws sqs purge-queue --queue-url "http://localhost:4566/000000000000/$QUEUE"
    SECONDS=0
    wait_replicas worker 0
    # The ScaledObject goes while the operator still runs: its finalizer
    # hands the Deployment back at the last count, cleanly.
    kubectl delete namespace "$APPS" --wait=true --timeout=120s
    aws sqs delete-queue --queue-url "http://localhost:4566/000000000000/$QUEUE"
    ;;
  off)
    for _ in $(seq 1 36); do
      if out="$(kubectl get namespace "$NS" 2>&1)"; then
        sleep 5
        continue
      fi
      case "$out" in
        *NotFound*|*"not found"*) echo "namespace $NS is gone: $out"; break ;;
        *) echo "::error::kubectl failed for a reason other than NotFound: $out"; exit 1 ;;
      esac
    done
    kubectl get namespace "$NS" > /dev/null 2>&1 && { echo "::error::namespace $NS still present after 180 s"; exit 1; }
    if kubectl get apiservice v1beta1.external.metrics.k8s.io > /dev/null 2>&1; then
      echo "::error::v1beta1.external.metrics.k8s.io survived the module turned off"; exit 1
    fi
    echo "apiservice v1beta1.external.metrics.k8s.io gone"
    # Kept on purpose: a client's ScaledObjects outlive the module.
    kubectl get crd scaledobjects.keda.sh > /dev/null \
      || { echo "::error::the KEDA CRDs were deleted with the module; helm.sh/resource-policy: keep did not hold"; exit 1; }
    echo "CRDs kept: $(kubectl get crd -o name | grep -c 'keda.sh') keda.sh CRDs still present"
    ;;
  *)
    echo "usage: $0 access|access-off|on|scale|off" >&2
    exit 2
    ;;
esac
