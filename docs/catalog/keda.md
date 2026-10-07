# Catalog module `keda` — event-driven autoscaling

KEDA scales a workload on events rather than on CPU: a `ScaledObject` scales a
Deployment on a queue's depth (SQS, Pub/Sub, Service Bus, Kafka, RabbitMQ…), a
cron window, a PromQL query — and down to zero. The HPA and metrics-server
scale on CPU and memory only; workers behind a queue need KEDA, and with
Karpenter (#53) the nodes follow. Issue #60; the module contract is
`docs/flux-catalog.md` §6.

> **Status: draft PR, every position below measured** — render, `tofu test`
> and the chart's own schema locally, the floci figures in
> [run 36771871849](https://github.com/do-now-io/socle/actions/runs/36771871849)
> of this branch (2026-09-30).

| Question | Position |
| --- | --- |
| Chart | Official `keda` 2.21.0 (app 2.21.0), from `https://kedacore.github.io/charts`. **No OCI chart exists upstream** — `ghcr.io/kedacore/charts/keda` answers 403 to an anonymous pull (measured 2026-09-30) — so an HTTPS `HelmRepository`, pinned exactly |
| Where | Every cloud, the same template. Only the cloud-access block is per cloud: AWS and GCP |
| Default | **Off.** KEDA does nothing until a client writes a `ScaledObject`, and it costs three pods and an API service |
| Cloud access | **None by default.** `kube.keda.services` names the services of the cluster's cloud KEDA's **own** identity may *read*. On AWS — `sqs`, `cloudwatch`, `kinesis`, `dynamodb` — the module declares that role through Crossplane with **one read-only statement per service named**, nothing for the rest, no role at all when the list is empty (§2). On GCP — `pubsub` only — one `roles/monitoring.viewer` binding at project level on the operator's principal (§2, *On GCP*) |
| Identity model | The operator's own identity: on AWS its role, bound by EKS Pod Identity to `keda/keda-operator`; on GCP the Workload Identity principal `…/subject/ns/keda/sa/keda-operator` itself, **no Google service account**. Per-workload roles (`identityOwner: workload`, `roleArn`) are **not possible under the socle's boundary** on AWS — argued in §2 |
| External metrics API | KEDA registers `v1beta1.external.metrics.k8s.io`; nothing else in the catalog does (metrics-server is `metrics.k8s.io`). Asserted Available in the e2e |
| Admission webhooks | Kept, `failurePolicy: Ignore` — the chart's default, stated (§4) |
| CRDs | Installed by the chart, **kept on uninstall**: turning the module off never deletes a client's `ScaledObject` (§4) |
| HTTP scaling | The KEDA HTTP add-on is out of scope in v1 (§8) |

## 1. What is installed

Two `ResourceSet`s, the shape `external_dns` established for a module that
carries its own cloud access
([external-dns.md](external-dns.md), *Ordering*):

- **`keda`** (`oci/catalog/keda/resourceset.yaml`), `dependsOn` the
  `crossplane` ResourceSet — Ready trivially when Crossplane is off:
  1. `Namespace/keda`, `pod-security.kubernetes.io/enforce: restricted`. The
     chart's three pods run non-root, read-only root filesystem, every
     capability dropped, `RuntimeDefault` seccomp, no host network: restricted
     holds (checked on the rendered chart).
  2. On AWS, with Crossplane on **and at least one service named**: the IAM
     `Role/keda-operator` and the `PodIdentityAssociation/keda-operator`,
     [crossplane.md](crossplane.md) §3's contract (§2 below). On GCP, with
     Crossplane on and `pubsub` named: the `ProjectIAMMember/keda-operator`
     (§2, *On GCP*).
  3. The child ResourceSet `keda-workload`, which `dependsOn` the Role and the
     association — on GCP the `ProjectIAMMember` — with `readyExpr` on
     `Ready=True` when they are rendered —
     the explicit expression external-dns measured as necessary, since a
     managed resource not yet created carries no `Ready` condition and
     kstatus reads that as healthy.
- **`keda-workload`**: `HelmRepository/kedacore`, `ConfigMap/keda-socle-values`
  (the socle's defaults, §4), `ConfigMap/keda-client-values`
  (`kube.keda.values` as YAML), and the `HelmRelease/keda` with **no inline
  `values`** and `valuesFrom` in that order, then the client's Secret when
  named, `optional: true`. Both ConfigMaps carry `reconcile.fluxcd.io/watch:
  Enabled`, so a change applies within seconds rather than at the next
  interval.

Every object carries the per-resource reconcile toggle on
`inputs.modules.keda.enabled`; `commonMetadata` is never used.

The chart brings three Deployments — `keda-operator`,
`keda-operator-metrics-apiserver`, `keda-admission-webhooks` — their
ServiceAccounts (`keda-operator`, `keda-metrics-server`, `keda-webhook`),
the six CRDs, the `APIService`, and the `ValidatingWebhookConfiguration`.
**Only the operator talks to the cloud**: since KEDA 2.9 the metrics server
reads the operator over gRPC, and the webhooks read nothing. So the module
binds one identity, to `keda-operator`.

## 2. Cloud access — the operator's own role, one read per service named

### The question

KEDA's operator reads queue metrics *on behalf of the client's workloads*.
Which queues is the client's business, not the socle's — so the module cannot
know what to grant. The issue offered two models:

1. **a role per workload**, the operator assuming each workload's own role —
   least privilege, the operator itself holding nothing;
2. **an operator role**, declared by the module, scoped by the client.

### Why model 1 is not possible here

KEDA's `aws` pod identity provider resolves a workload's role in two ways
(`pkg/scalers/aws/aws_config_cache.go`, v2.21.0): `AssumeRoleWithWebIdentity`
with the pod's projected OIDC token — IRSA — and, when that fails,
`sts:AssumeRole` from the operator's own credentials. The socle runs **EKS Pod
Identity, not IRSA**: there is no OIDC token file in the operator pod, so the
first path never applies. And the second needs `sts:AssumeRole` on the
operator's role — which is **a role Crossplane created inside the boundary**,
and the boundary denies `sts:*` to every such role
([crossplane.md](crossplane.md) §2, *NeverIdentityNorAccount*). `identityOwner:
workload` and `roleArn` in a `TriggerAuthentication` are therefore dead ends
on the socle, by design of the boundary rather than by omission here. A client
who needs them can still make the operator's identity outside the socle
(§2, *Crossplane off*), where the boundary does not apply.

### The model chosen: the operator's role, scoped by service name

The client names, in `kube.keda.services`, the AWS services the operator may
read. The template turns each name into **one read-only statement, the exact
API call the scaler makes** — taken from the scalers' source, v2.21.0, not
from the docs, which name none:

| Service | Statement | Scaler, and the call in its source |
| --- | --- | --- |
| `sqs` | `sqs:GetQueueAttributes` | `aws-sqs-queue` — `GetQueueAttributes` in `aws_sqs_queue_scaler.go` |
| `cloudwatch` | `cloudwatch:GetMetricData` | `aws-cloudwatch` — the one call the docs name too. RDS, ELB, Lambda… metrics are read here: **there is no RDS scaler**, `rds` is refused with that hint |
| `kinesis` | `kinesis:DescribeStreamSummary` | `aws-kinesis-stream` |
| `dynamodb` | `dynamodb:Query`, `dynamodb:DescribeTable`, `dynamodb:DescribeStream` | `aws-dynamodb` (`Query`) and `aws-dynamodb-streams` (`DescribeTable`, then `DescribeStream`) |

A service not named gets **no statement**; an empty list renders **no role and
no association** — the operator runs with no cloud identity at all, which is
what a cron, Prometheus, Kafka, RabbitMQ or Redis trigger needs. Never `*`:
the list is validated against the four names at plan, so a wildcard, `rds`,
or a service the template cannot scope is an error with the list in the
message, not a role that silently grants nothing.

Rendered, with `services = [dynamodb, kinesis, sqs, cloudwatch]`
(`flux-operator build rset`), the role's one inline policy `scalers` is:

```json
{"Version":"2012-10-17","Statement":[
  {"Sid":"ReadSqsQueueAttributes","Effect":"Allow","Action":["sqs:GetQueueAttributes"],"Resource":"*"},
  {"Sid":"ReadCloudWatchMetrics","Effect":"Allow","Action":["cloudwatch:GetMetricData"],"Resource":"*"},
  {"Sid":"ReadKinesisStreamSummary","Effect":"Allow","Action":["kinesis:DescribeStreamSummary"],"Resource":"*"},
  {"Sid":"ReadDynamoDbTablesAndStreams","Effect":"Allow","Action":["dynamodb:Query","dynamodb:DescribeTable","dynamodb:DescribeStream"],"Resource":"*"}
]}
```

The statements are built as a template list and serialised with `toJson`, so
the document is valid JSON for any subset, in any order.

**`Resource: "*"` within each statement, on purpose.** The queues, streams
and tables are named in the client's `ScaledObject`s, which OpenTofu and the
template do not read; the account id is not among the inputs either
(`inputs.cluster` carries name, region, environment, owner). What the socle
scopes is the *action*: a role that can `GetQueueAttributes` on every queue of
the account reads depths, never messages; one that can `Query` every table is
the one real width here, and it is the client's word — `dynamodb` — that
opens it. Resource-level scoping — a list of ARNs per service — is the
obvious v2 and is left out (§8).

**The boundary must name the same services.** The foundations'
`aws.crossplane.allowed_services` is the ceiling of every role Crossplane
creates ([crossplane.md](crossplane.md) §2); a service in `kube.keda.services`
that is not there makes the Role fail at IAM, the child ResourceSet wait, and
`socle-root` stay not Ready — nothing half-deployed, and the reason on the
Role's `Synced` condition. The plan cannot check this: the bootstrap module
does not see the foundations' variable, by the invariance §6 of
`docs/flux-catalog.md` argues. `prod.tfvars.example` shows the two lines
together.

### The managed resources

| Object | What it is |
| --- | --- |
| `iam.aws.m.upbound.io/v1beta1` `Role` `keda/keda-operator` | IAM role `<cluster>-keda-operator` (`crossplane.io/external-name`: IAM names are account-wide), path `/socle/<cluster>/`, `permissionsBoundary` from `kube.crossplane.permissions_boundary` when set, trust `pods.eks.amazonaws.com` for `sts:AssumeRole` and `sts:TagSession`, one inline policy `scalers` |
| `eks.aws.m.upbound.io/v1beta1` `PodIdentityAssociation` `keda/keda-operator` | `inputs.cluster.region`, `inputs.cluster.name`, namespace `keda`, ServiceAccount `keda-operator`, `roleArnRef` to the Role |

Both render only under `and (eq inputs.cloud "aws") inputs.modules.crossplane.enabled inputs.modules.keda.services`
— an empty list is false in the operator's templating, measured.

### When the list changes

EKS Pod Identity hands a pod its credentials **at admission only**: a pod
admitted before its association exists never gets them. Two consequences the
module handles:

- **First enable with a service named**: the chart is in the child
  ResourceSet, which waits for the Role and the association to be `Ready`
  before applying anything. The operator pod is admitted after its
  association exists — the only order that works with Pod Identity.
- **`[]` → `["sqs"]` on a running KEDA**: the operator already runs, without
  credentials. The socle's values write the sorted list into a pod
  annotation, `socle.do-now.io/cloud-access: "sqs"`, so the change rolls the
  operator — and the child ResourceSet gains its `dependsOn` in the same
  reconcile, so the ConfigMap that carries the annotation is applied only
  once the association is Ready. The new pod is admitted with its
  credentials. Adding a second service later changes the annotation again,
  one more roll; reordering the list does not (`sortAlpha`).
- **Back to `[]`**: the Role and the association are garbage-collected, the
  annotation empties, the operator rolls without credentials.

### On GCP — `pubsub`, one Cloud Monitoring read on the operator's principal

On GCP the list may name **`pubsub` only**; OpenTofu refuses every other name
at plan, AWS's included. It turns into one Crossplane managed resource, under
`and (eq inputs.cloud "gcp") inputs.modules.crossplane.enabled (has "pubsub" inputs.modules.keda.services)`:

| Object | What it is |
| --- | --- |
| `cloudplatform.gcp.m.upbound.io/v1beta1` `ProjectIAMMember` `keda/keda-operator` | `project` = `inputs.cluster.projectId`, `role: roles/monitoring.viewer`, `member: principal://iam.googleapis.com/projects/<project number>/locations/global/workloadIdentityPools/<project id>.svc.id.goog/subject/ns/keda/sa/keda-operator` |

**Why Monitoring and not Pub/Sub.** KEDA's `gcp-pubsub` scaler never calls
the Pub/Sub API: it asks Cloud Monitoring for the subscription's
`pubsub.googleapis.com/subscription/num_undelivered_messages` (the default
mode; `oldest_unacked_message_age` and the topic metrics the same way), with an
MQL `QueryTimeSeries` — `GetMetricsAndActivity` in
`pkg/scalers/gcp_pubsub_scaler.go` and `QueryMetrics` in
`pkg/scalers/gcp/gcp_stackdriver_client.go`, v2.21.0. So the operator needs
`monitoring.timeSeries.list`, and `roles/monitoring.viewer` is the narrowest
predefined role that holds it; `roles/pubsub.viewer`, which #68 first listed,
would grant nothing the scaler uses. The socle cannot mint a narrower custom
role for a module: Crossplane's principal may grant only the roles the client
lists ([crossplane.md](crossplane.md) §2). Project level, `Resource "*"`'s
counterpart: the subscriptions are named in the client's `ScaledObject`s,
which the socle does not read. The width is **every metric of the project and
the monitoring configuration, read-only — never a message**. The same binding
serves `gcp-stackdriver`, `gcp-cloudtasks` and the `prometheus` scaler on
Cloud Monitoring's PromQL endpoint, which read the same API; `pubsub` is the
name the client writes because it is the reason he writes it.

**No Google service account.** With `podIdentity.provider: gcp`, KEDA builds
its Monitoring clients with no option at all — `monitoring.NewMetricClient(ctx)`
and `NewQueryClient(ctx)` in `NewStackDriverClientPodIdentity`, and
`google.DefaultTokenSource` in `pkg/scalers/gcp/gcp_common.go` for the
Prometheus path — which is Application Default Credentials, answered on GKE
by the metadata server with a token for the pod's own Kubernetes
ServiceAccount: the principal above, bound directly. The project id comes from
the same metadata server. The chart's `podIdentity.gcp.enabled` is therefore
left **off**: it annotates the ServiceAccount with
`iam.gke.io/gcp-service-account`, which would make the operator impersonate a
Google service account the binding does not name.

**The client allows the role.** Crossplane's own grant on the project is
bounded by `gcp.crossplane.allowed_roles` (`hasOnly`, [crossplane.md](crossplane.md) §2):
`roles/monitoring.viewer` must be in that list, in the same tfvars as
`kube.keda.services`. If it is not, the binding stays `Synced=False` with the
IAM refusal on its condition, the child ResourceSet waits, and `socle-root`
stays not Ready — the AWS boundary's behaviour, nothing half-deployed. The
plan cannot check it, for the same reason as on AWS.

```hcl
gcp = {
  crossplane = { allowed_roles = ["roles/monitoring.viewer"] }
}
kube = {
  crossplane = { enabled = true }
  keda       = { enabled = true, services = ["pubsub"] }
}
```

**When the list changes.** GKE hands the operator a token at each call, not
at admission, so a pod started before its binding reads as soon as IAM has
propagated it (seconds to minutes) — no roll needed. The ordering and the
`socle.do-now.io/cloud-access` annotation are kept anyway, the same chain as
on AWS: the chart waits for the binding on first enable, and adding or
removing `pubsub` rolls the operator. Back to `[]`, Crossplane removes the
binding.

**Two clusters in one project share the principal.** The Workload Identity
pool is the project's, so `…/ns/keda/sa/keda-operator` is the same principal
on both, and both clusters declare the same binding. Turning `pubsub` off on
one — or destroying it — removes the binding for the other too, until its
Crossplane writes it back at the next reconcile.

#### What a client writes

A `TriggerAuthentication` with no secret, and a `ScaledObject` that names it:

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: operator-principal
  namespace: orders
spec:
  podIdentity:
    provider: gcp           # the operator's own principal, the binding above
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: orders-worker
  namespace: orders
spec:
  scaleTargetRef:
    name: orders-worker
  minReplicaCount: 0
  maxReplicaCount: 20
  triggers:
    - type: gcp-pubsub
      authenticationRef:
        name: operator-principal
      metadata:
        subscriptionName: orders-worker   # or projects/<id>/subscriptions/<name>
        mode: SubscriptionSize            # num_undelivered_messages
        value: "50"                       # messages per replica
        activationValue: "0"
```

KEDA has deprecated its MQL-based GCP scalers in favour of the `prometheus`
scaler on Cloud Monitoring's PromQL endpoint
([KEDA blog, 2025-09-15](https://keda.sh/blog/2025-09-15-gcp-deprecations)),
while keeping them as long as Google serves MQL. The same
`TriggerAuthentication` and the same binding serve that form:

```yaml
    - type: prometheus
      authenticationRef:
        name: operator-principal
      metadata:
        serverAddress: https://monitoring.googleapis.com/v1/projects/<project id>/location/global/prometheus
        query: 'max({"__name__"="pubsub.googleapis.com/subscription/num_undelivered_messages","monitored_resource"="pubsub_subscription","subscription_id"="orders-worker"})'
        threshold: "50"
```

**The workload's own access is the client's, not the socle's.** The binding
above lets KEDA *count* the messages; the Deployment it scales must still
*pull* them, as its own principal —
`principal://…/subject/ns/orders/sa/orders-worker` — with
`roles/pubsub.subscriber` on its subscription. That binding belongs to the
client's application, with the subscription, in the client's own
Terraform or Crossplane, never in `kube.keda`: the socle's list grants the
operator a read of metrics, and nothing on any client resource.

```hcl
resource "google_pubsub_subscription_iam_member" "orders_worker" {
  subscription = google_pubsub_subscription.orders_worker.name
  role         = "roles/pubsub.subscriber"
  member       = "principal://iam.googleapis.com/projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${data.google_project.this.project_id}.svc.id.goog/subject/ns/orders/sa/orders-worker"
}
```

### What `services` is not

`services` is **not** the list of sources KEDA watches. Every scaler works
on every cloud from this PR on — Service Bus, Storage Queues, Pub/Sub,
Scaleway Messaging, Kafka, RabbitMQ, Redis, Postgres, Prometheus, cron —
because KEDA takes its credentials from a `TriggerAuthentication`
referencing a Secret in the client's namespace, which the module never
touches. `services` is only a shortcut on top of that: *let Crossplane mint
the operator's own role from a list of names, so no credential is needed at
all*. The list is always **the services of the cluster's cloud**: a role on
AWS cannot read Pub/Sub, so `["sqs", "pubsub"]` is refused, as is `rds`; on
GCP `["sqs"]` is refused the same way.

| The source is… | How KEDA reaches it |
| --- | --- |
| An API of the cluster's cloud, with a Crossplane provider (aws, gcp) | `services`: the operator's own identity, no credential anywhere |
| An API of the cluster's cloud, no Crossplane provider yet (azure) | The client binds an identity he made through `values` (`podIdentity.azureWorkload`); `services` is refused until the branch lands |
| An API of another cloud, Scaleway Messaging, or not a cloud API at all (Kafka, RabbitMQ, Redis, Postgres) | A `TriggerAuthentication` referencing the client's Secret — what the e2e does on floci |
| Prometheus, cron | Nothing to grant |

RDS, the usual question: there is no RDS scaler. A table's depth is the
`postgresql` scaler with a connection string in a Secret; an instance metric
(connections, CPU) is the `aws-cloudwatch` scaler on the `AWS/RDS` namespace,
which `services = ["cloudwatch"]` grants to the operator's role.

### An unavailable metrics apiserver blocks namespace deletion

KEDA registers `external.metrics.k8s.io` as an aggregated API, served by
`keda-operator-metrics-apiserver`. While that Deployment cannot run, the
group goes stale and the namespace controller's discovery fails for the whole
cluster, not for `keda` alone. Measured on the GKE sandbox (2026-10-07): with
the metrics apiserver Pending, `external.metrics.k8s.io` went stale and a
terminating namespace hung on "Discovery failed". Keep the metrics apiserver
schedulable (capacity, no failing admission) before tearing anything down.

### Crossplane off, or another cloud

With Crossplane off the list must be empty — refused at plan otherwise, with
both ways out named. A client who made the operator's identity outside the
socle (on AWS: a role and a Pod Identity association for `keda/keda-operator`)
just leaves the list empty; the module renders no role and the pod picks the
association up. On GKE the same holds with no `values` at all: a client who
binds `roles/monitoring.viewer` to `…/ns/keda/sa/keda-operator` himself
leaves the list empty, and the operator reads with its own principal (or he
sets `podIdentity.gcp.enabled` with `gcpIAMServiceAccount` to use a Google
service account he made). On AKS the chart's own switch does the binding
through `values`: `podIdentity.azureWorkload.enabled` with `clientId` and
`tenantId`. Azure gets a `services` branch when its Crossplane provider lands
([crossplane.md](crossplane.md) §2), and `services` is refused there until
then rather than silently ignored.

## 3. What the client may set — `kube.keda`

| Attribute | Default | Rule, checked at plan |
| --- | --- | --- |
| `enabled` | `false` | bool |
| `services` | `[]` | On aws, a list drawn from `sqs`, `cloudwatch`, `kinesis`, `dynamodb`; on gcp, `pubsub` only. Non-empty needs `kube.crossplane.enabled`, `cloud` aws or gcp, and on aws a non-empty `region` (the association is regional) |
| `values` | `{}` | Free-form chart values, secrets refused (below) |
| `values_secret` | `""` | A Secret name in `keda` with a `values.yaml` key, merged last, never read by OpenTofu |

### Free-form values — `values` and `values_secret`

`kube.keda.values` is any value of chart 2.21.0, deep-merged by
helm-controller over the socle's document, the client's winning, and passed
through by OpenTofu untouched (`tofu test`). What the socle sets is a
convenience, not a lock: a client who renames `serviceAccount.operator.name`
breaks the binding to the role, and is told so in the template.

**Secrets are refused at plan.** The chart takes no credential of its own —
KEDA's credentials belong in `TriggerAuthentication`s, which is the point of
the CRD — so the refusal covers the two places one could still be smuggled
in:

| Chart path | Why it is refused |
| --- | --- |
| `extraObjects[]` with `kind: Secret` | Would be written in clear in the state and the ConfigMap |
| `env[]`, `operator.env[]`, `metricsServer.env[]`, `webhooks.env[]` with a literal `value` under a credential-like name | `AWS_SECRET_ACCESS_KEY`, `*_TOKEN`, `*_PASSWORD`… A `valueFrom` reference passes |

Both land in `values_secret` instead — or, better, in a Secret a
`TriggerAuthentication` names, which is what the e2e does (§6).

## 4. Fixed by the socle, not by a named attribute

Each is a default in `keda-socle-values`; `values` can still override it.

- **`serviceAccount.operator.name: keda-operator`** — the subject of the
  Pod Identity association on AWS and of the principal on GCP, named so the
  binding is visible in one place.
- **`crds.install: true`, `crds.additionalAnnotations: helm.sh/resource-policy:
  keep`.** The chart ships its CRDs as templates, so Helm would delete them at
  uninstall — and every `ScaledObject` with them, while the operator that
  would restore each Deployment's replicas may already be gone. Kept, the
  client's objects outlive the module: a `ScaledObject` left behind keeps its
  HPA, whose external metric no longer answers, so the Deployment stays at
  its current count and nothing scales to zero. Re-enabling adopts the CRDs
  (same release name and namespace). The `gateway_api` module made the same
  call for the Gateway CRDs.
- **`metricsServer.registerAPIService: true`** — the external metrics API,
  one per cluster, this module's to register.
- **`webhooks.enabled: true`, `failurePolicy: Ignore`** — the chart's
  default, written down. The webhooks validate `ScaledObject`s,
  `ScaledJob`s and `TriggerAuthentication`s; with `Fail`, a webhook outage
  would refuse every write to those kinds, and the operator refuses an
  invalid object at reconcile anyway (`Ready=False` on the object). `Ignore`
  costs one round-trip of error reporting, never availability.
- **`podAnnotations.keda."socle.do-now.io/cloud-access"`** — the sorted
  service list, the roll trigger of §2.
- **Requests, and the chart's limits kept.** `operator` 50m/128Mi,
  `metricServer` 25m/64Mi, `webhooks` 10m/32Mi; the chart's limits (1 CPU,
  1000Mi each) stay as a ceiling. Idle on floci's k3s, right after install
  (§6): operator 28Mi, metrics server 35Mi, webhooks 13Mi, 0–5m of CPU each
  — the requests leave room for a few hundred `ScaledObject`s.
- **Chart source.** HTTPS `HelmRepository`, as the position table says; the
  catalog's second non-OCI chart after external-dns.

Left at the chart's defaults: one replica of each Deployment, Prometheus
metrics off (a VictoriaMetrics module, #46, is where `prometheus.operator`
turns on), TLS between operator and metrics server from the chart's
self-signed CA, no `nodeSelector`, no `priorityClassName`.

## 5. Ordering

The `keda` ResourceSet `dependsOn` the `crossplane` ResourceSet, so the
providers' CRDs exist before a `Role` is applied, and nothing waits when
Crossplane is off. Then the chart only after the association — the child
ResourceSet `keda-workload`, its `dependsOn` with `readyExpr` on
`Ready=True`, external-dns's pattern verbatim. A role that never turns Ready
(boundary refused, `sqs` not in the client's allowlist) leaves the child
waiting, the parent not Ready, and `socle-root` with it; nothing is
half-deployed.

**Turning Crossplane off together with the module** leaves the two managed
resources without a provider to delete them: their finalizers hold the
namespace. Turn the module off first, Crossplane after — the crossplane
module's own warning.

**Turning the module off** removes the three Deployments, the `APIService`
and the webhooks, keeps the CRDs (§4). Delete or keep your `ScaledObject`s
knowingly: while KEDA runs, deleting one hands the Deployment back at its
current replica count; after, the object is inert.

## 6. Measured

- **Render.** `flux-operator build rset` with `oci/.ci/inputs-sample.yaml`
  (aws, Crossplane on, `services: [sqs, cloudwatch]`): `Namespace`, `Role`,
  `PodIdentityAssociation`, the child `ResourceSet` — 4 objects, `kubeconform
  -strict` valid. With `services: []`: `Namespace` and the child
  only, no `dependsOn`, the annotation `""`. With all four services: the
  policy of §2, valid JSON. The raw template passes `kubeconform -strict`
  too.
- **Render on gcp** (2026-10-07), the gcp sample with `services: [pubsub]`
  and Crossplane on: `Namespace`, `ProjectIAMMember` (`roles/monitoring.viewer`,
  the principal of `ns/keda/sa/keda-operator` in project `sandbox-2bace`,
  number `320449067541`), the child `ResourceSet` with its one `dependsOn` —
  3 objects, `kubeconform -strict` valid against the `ProjectIAMMember` CRD of
  provider-upjet-gcp v3.0.0 (`package/crds/cloudplatform.gcp.m.upbound.io_projectiammembers.yaml`).
  With `services: []`, or Crossplane off: `Namespace` and the child only, no
  `dependsOn`, the annotation `""`. The AWS renders (the sample, `[]`, all
  four services) are byte-identical before and after the gcp branch.
- **The chart's own schema.** The socle's document and a client override
  (`resources.operator.requests.memory: 160Mi`), merged in that order, pass
  `helm template` of chart 2.21.0, whose `values.schema.json` refuses an
  unknown key. The rendered operator Deployment carries the client's memory
  request, the socle's cpu request, the annotation, and the security context
  restricted needs.
- **`tofu test`.** The bootstrap's runs pass; each of the six validations
  has a failing case (`rds`, `*`, no Crossplane, `sqs` on gcp, empty region, a
  credential in `operator.env`, a Secret in `extraObjects`, a non-list, a
  non-object, a bad Secret name), and four passing runs cover the defaults,
  the services flowing through, on-without-services planning with no
  Crossplane, and values with a `valueFrom` credential.
- **e2e, disabled.** Both jobs assert the `keda` ResourceSet Ready while
  disabled, and its namespace absent (`wait-converged.sh`).
- **e2e, on floci** — `e2e-aws-catalog`, phases of `.github/scripts/e2e/keda.sh`,
  run 36771871849. The job takes **15m36s** with the KEDA phases; the
  Crossplane step, which now carries external-dns's and KEDA's access
  phases, 5m52s; KEDA on and scale 1m47s; off 13s.

  | Phase | With | What it proves |
  | --- | --- | --- |
  | `access` | Crossplane on, `services=["sqs"]` | The `Role` became IAM role `socle-e2e-catalog-keda-operator` under `/socle/socle-e2e-catalog/` **1 s** after the seam was applied, trusted by `pods.eks.amazonaws.com`, its `scalers` policy carrying `ReadSqsQueueAttributes` / `sqs:GetQueueAttributes` **and none of** `cloudwatch:`, `kinesis:`, `dynamodb:`, `sqs:*`, `sqs:SendMessage`, `sqs:ReceiveMessage`; the association stayed `Synced=False`, and one minute later there was still no `HelmRelease` — `keda-workload` reporting *dependency PodIdentityAssociation/keda/keda-operator not ready* |
  | `access-off` | module off | The IAM role deleted, the namespace gone |
  | `on` | Crossplane off, no service, `values.resources.operator.requests.memory=160Mi` | ResourceSet Ready and the three Deployments Available **51 s** after the apply returned; `v1beta1.external.metrics.k8s.io` Available; the live operator Deployment requests `{"cpu":"50m","memory":"160Mi"}` — the client's memory, the socle's cpu; no `Role`, annotation empty; `kubectl top`: operator 28Mi, metrics server 35Mi, webhooks 13Mi |
  | `scale` | an SQS queue in floci, a `TriggerAuthentication` on static keys, `awsEndpoint` at floci | `ScaledObject` Ready at once; the Deployment at 1 went to **0** on the empty queue in 1 s; 10 messages with `queueLength: 5` took it to **2** in 12 s (`keda-hpa-worker 10/5 (avg)`); a purge took it back to **0** in 12 s. The namespace was then deleted while KEDA ran |
  | `off` | module off | Namespace and `APIService` gone within 13 s; the six `keda.sh` CRDs still present |

**e2e, through Chainsaw** (`tests/e2e/chainsaw-test.yaml`, since the e2e moved
into the modules — `docs/flux-catalog.md` §8). The table above is the bash phase
this module shipped with; the same proof now runs on every push in the `root`
job (`keda-health`, the disabled shape and no external metrics APIService) and
the module's own job (`keda-module-aws`): on without a service — the three
Deployments, the APIService Available, the client's 160Mi over the socle's
128Mi, the Secret in `values_secret` merged last, no Role and an empty
cloud-access annotation; the SQS scale loop (1 → 0 on an empty queue, 0 → 2 on
ten messages, back to 0 on a purge) with `sqs.sh` beside the test for the queue
calls; off with the CRDs kept; then Crossplane on and `services = ["sqs"]`:
the Role read from `status.atProvider` under `/socle/<cluster>/` with the one
`sqs:GetQueueAttributes` statement and none of the other services, the
association `Synced=False` and the workload withheld (the two floci seams, steps
of their own), off deleting the IAM role.

**e2e on GKE** (`keda-module-gcp`, `cloud: gcp`, `platform: gke`), run
against the sandbox with the module as its tfvars leave it: the
`ProjectIAMMember` Synced and Ready with the role and the principal of
`ns/keda/sa/keda-operator` in the binding's own project; `keda-workload`
depending on it and Ready; the operator's ServiceAccount carrying **no**
`iam.gke.io/gcp-service-account`; the annotation `pubsub`; the three
Deployments and the external metrics API Available. Then the functional
proof: a `ScaledObject` on `gcp-pubsub` through a `TriggerAuthentication`
with `podIdentity.provider: gcp`, on a subscription that does not exist and
`valueIfNull: "0"`, takes a Deployment from one to **zero**. KEDA never
scales on a scaler error, so zero is reached only through a query Cloud
Monitoring authorised for the operator's principal — no script, no Pub/Sub
resource to create. Figures land here with the sandbox run.

### What floci proves, and what needs a real account

floci implements IAM and SQS, so the role's shape and the scaler's loop are
proven for real. Not provable there, for the reasons
[external-dns.md](external-dns.md) lists: the association reaching EKS
(no `CreatePodIdentityAssociation`), the operator getting the role's
credentials (no Pod Identity Agent on k3s), IAM enforcing the `scalers`
policy and the boundary (floci enforces none). The `scale` phase therefore
runs with static keys, the way a client without a cloud role would. The proof
that KEDA reads a queue **as its own role**, that a service not named is
refused by IAM, and that adding a service rolls the operator into its
credentials, is the sandbox EKS apply — issue #60's *next step 2*.

## 7. Prerequisites and assumptions for the coordinator

- **The EKS Pod Identity Agent add-on.** The module's role on AWS depends on
  it, as external-dns's does; routed to the foundations
  ([external-dns.md](external-dns.md), *Prerequisites*).
- **The boundary and `kube.keda.services` are two lists the client keeps in
  step**, in one tfvars. A drift fails visibly at IAM, not at plan (§2).
- **Karpenter (#53).** A Deployment scaled from zero needs a node; nothing
  here assumes Karpenter, and nothing conflicts with it. The sandbox proof
  should run both.
- **VictoriaMetrics (#46).** `prometheus.operator.enabled` and the
  `ServiceMonitor` are that module's to turn on through `values`, or a socle
  default once it exists.

## 8. Out of scope in v1, on purpose

- **The KEDA HTTP add-on** — a separate chart, an interceptor in the request
  path. Not this module.
- **Resource-level scoping** (`Resource` as a list of queue/table ARNs per
  service). The natural v2 of `services`: `services = { sqs = ["arn:…"] }`,
  or a sibling attribute. The action scoping ships first because it is what
  a client asks for and what the boundary mirrors.
- **`services` on azure, scaleway** — each waits for its Crossplane
  provider; the chart's own workload-identity switches serve meanwhile.
  `cloudtasks` and `monitoring` on gcp, which #68 listed, are not separate
  names: the `pubsub` binding already grants the Cloud Monitoring read those
  scalers make (§2, *On GCP*).
- **`ScaledJob`s, `ClusterTriggerAuthentication`s** — the client's objects;
  the module installs the CRDs and nothing more.
- **An operator role assuming workload roles** — refused by the boundary,
  §2, and the reason the module scopes the operator's own role instead.
