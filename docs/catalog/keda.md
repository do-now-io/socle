---
title: keda
description: Event-driven autoscaling down to zero, with an optional read-only role for your aws queues.
category: autoscaling
requires:
  - module: crossplane
    clouds: [aws]
    why: "only when services is set: the operator's role is a Crossplane managed resource"
---

KEDA scales a workload on events rather than on CPU: a `ScaledObject` scales
a Deployment on a queue's depth, a cron window or a PromQL query, and down to
zero. Turn it on for workers behind a queue. It is **off by default**: it
does nothing until you write a `ScaledObject`, and it costs three pods and
an API service.

## Getting started

Turn it on. For queues on aws, also let Crossplane's boundary allow their
services, and name them in `services` for the operator's own role:

```hcl
# opentofu/clusters/aws, in your tfvars
aws = { crossplane = { allowed_services = ["sqs", "cloudwatch"] } }
```

```hcl title="terraform.tfvars" kube-start="keda"
kube = {
  crossplane = { enabled = true }
  keda = {
    enabled  = true
    services = ["sqs", "cloudwatch"]
  }
}
```

Without an aws source, `keda = { enabled = true }` alone. After the apply,
`kubectl -n flux-system get resourceset keda` is Ready and
`kubectl get apiservice v1beta1.external.metrics.k8s.io` is `Available`.

## What it installs

| | |
| --- | --- |
| Chart | `keda` `2.21.0` from `https://kedacore.github.io/charts` (a `HelmRepository`: upstream publishes no public OCI chart) |
| Namespace | `keda`, Pod Security `restricted` enforced |
| Objects | `Namespace/keda`; on aws with crossplane on and `services` set, `Role/keda-operator` and `PodIdentityAssociation/keda-operator`; the child `ResourceSet/keda-workload` holding `HelmRepository/kedacore`, `ConfigMap/keda-socle-values`, `ConfigMap/keda-client-values` and `HelmRelease/keda` |

The chart brings three Deployments, `keda-operator`,
`keda-operator-metrics-apiserver` and `keda-admission-webhooks`, the six
CRDs, the `v1beta1.external.metrics.k8s.io` APIService and a
`ValidatingWebhookConfiguration`. Only the operator talks to the cloud.

The socle's values:

| Value | Setting |
| --- | --- |
| `serviceAccount.operator.name` | `keda-operator`, the subject of the module's role. Renamed through `values`, the binding breaks |
| `crds.install`, `crds.additionalAnnotations` | `true`, `helm.sh/resource-policy: keep`: your `ScaledObject`s outlive the module |
| `metricsServer.registerAPIService` | `true`: the external metrics API, one per cluster; nothing else in the catalog registers it |
| `webhooks.enabled`, `webhooks.failurePolicy` | `true`, `Ignore`: a webhook outage never blocks a write, and the operator still refuses an invalid object at reconcile |
| `podAnnotations.keda."socle.do-now.io/cloud-access"` | the sorted `services`, so a change rolls the operator |
| Requests | operator 50m / 128Mi, metrics server 25m / 64Mi, webhooks 10m / 32Mi; the chart's limits (1 CPU, 1000Mi each) kept |

Left at the chart's defaults: one replica each, Prometheus metrics off, the
chart's self-signed TLS between operator and metrics server.

## What you can set

Under `kube.keda` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on. |
| `services` | `[]` | The AWS services the operator's own role may read: `sqs`, `cloudwatch`, `kinesis`, `dynamodb`. Empty means no role. |
| `values` | `{}` | Any `keda` chart value; yours win over the socle's ([SOCLE-06](../decisions/socle.md#socle-06-the-clients-values-win)). |
| `values_secret` | `""` | The name of a Secret you create in `keda`, with a `values.yaml` key, merged last. Label it `reconcile.fluxcd.io/watch: Enabled` for a change to apply before the next interval. |

Refused at plan:

- A `services` entry outside `sqs`, `cloudwatch`, `kinesis`, `dynamodb`. RDS
  has no scaler: its metrics go through `cloudwatch`.
- A non-empty `services` with `kube.crossplane.enabled` off, on a cloud other
  than aws, or on aws with an empty `region` in the bootstrap module (the
  aws root passes `aws.region`). These three checks read `services` whether
  the module is enabled or not: leave the list empty while it is off.
- In `values`: a `Secret` among `extraObjects`, and an `env`, `operator.env`,
  `metricsServer.env` or `webhooks.env` entry with a literal value whose name
  looks like a credential (`valueFrom` passes). A scaler's credentials go in
  a Secret a `TriggerAuthentication` names.
- `values_secret` that is not a valid Secret name.

The plan cannot check that `aws.crossplane.allowed_services` names the same
services: the bootstrap module does not see the foundations' variable. A
service missing there makes the Role fail at IAM, `keda-workload` wait, and
`socle-root` stay not Ready, with the reason on the Role's `Synced`
condition.

### Every setting

Every attribute, at its default, and how chart values and secrets go in:

```hcl title="terraform.tfvars" kube-full="keda"
kube = {
  keda = {
    enabled  = false # off by default
    services = []    # aws: "sqs", "cloudwatch", "kinesis", "dynamodb"; [] = no role

    # Any value of the keda chart 2.21.0; yours win over the socle's.
    values = {
      logging = {
        operator = { level = "debug", format = "json" }
      }
    }

    # A Secret you create in keda, whose values.yaml key holds chart values
    # that must not reach the OpenTofu state, such as an operator.env proxy
    # URL with a password in it.
    values_secret = "keda-values"
  }
}
```

## Per cloud

Every scaler works on every cloud through a `TriggerAuthentication` that
references a Secret in your namespace; the module never touches it.
`services` is a shortcut on top, aws only:

| The source is | How KEDA reaches it |
| --- | --- |
| An aws service, with crossplane on | `services`: the operator's own role, no credential anywhere |
| A gcp or azure service | An identity you made, bound to `keda/keda-operator` through `values`: `podIdentity.gcp` with `gcpIAMServiceAccount`, or `podIdentity.azureWorkload` with `clientId` and `tenantId` |
| Another cloud's API, Scaleway Messaging, Kafka, RabbitMQ, Redis, Postgres | A `TriggerAuthentication` referencing your Secret |
| Prometheus, cron | Nothing to grant |
| An aws service, with crossplane off | Leave `services` empty and make a role and a Pod Identity association for `keda/keda-operator` yourself; the pod picks it up |

## Cloud access

On aws with crossplane on and `services` set, the module declares the
operator's IAM role, `<cluster>-keda-operator` under `/socle/<cluster>/`,
carrying the permissions boundary, bound by Pod Identity to
`keda/keda-operator`. Its inline policy `scalers` holds one read-only
statement per service named, the exact calls each scaler makes in KEDA
2.21.0, and nothing for the rest:

| Service | Actions | Scalers |
| --- | --- | --- |
| `sqs` | `sqs:GetQueueAttributes` | `aws-sqs-queue` |
| `cloudwatch` | `cloudwatch:GetMetricData` | `aws-cloudwatch`, RDS, ELB and Lambda metrics included |
| `kinesis` | `kinesis:DescribeStreamSummary` | `aws-kinesis-stream` |
| `dynamodb` | `dynamodb:Query`, `dynamodb:DescribeTable`, `dynamodb:DescribeStream` | `aws-dynamodb`, `aws-dynamodb-streams` |

Each statement is on `Resource: "*"`: the queues and tables are named in
your `ScaledObject`s, which the socle does not read. A role that can
`GetQueueAttributes` on every queue reads depths, never messages; `dynamodb`
grants `Query` on every table, the one real width, opened by your word.
`identityOwner: workload` and a `roleArn` in a `TriggerAuthentication` do not
work under the socle's boundary
([KEDA-01](../decisions/keda.md#keda-01-the-operators-role-scoped-per-aws-service)).

**When the list changes.** EKS Pod Identity hands a pod its credentials at
admission only. On first enable, `keda-workload` waits for the Role and the
association before applying the chart. From `[]` to `["sqs"]` on a running
KEDA, the annotation changes and rolls the operator once the association is
Ready. Reordering the list does not roll it. Back to `[]`, the Role and the
association are removed and the operator rolls without credentials.

## Ordering

On aws with `services` set, it requires crossplane: the role is a Crossplane
managed resource, and the plan refuses the list without it. Otherwise it
requires nothing. It waits for crossplane: the `keda` ResourceSet `dependsOn`
the `crossplane` ResourceSet, Ready trivially when crossplane is off, and
`keda-workload` `dependsOn` the Role and the association being `Ready`
([Module-owned cloud access](../architecture/module-iam.md)). Turn the module
off before crossplane, never in the same apply.

## Upgrade notes

Turning the module off removes the three Deployments, the APIService and the
webhooks, and keeps the CRDs. A `ScaledObject` left behind keeps its HPA,
whose external metric no longer answers: the Deployment stays at its current
replica count and nothing scales to zero. Turned back on, the release adopts
the CRDs. The chart pin moves with `socle_version`.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-09-30 | floci, GitHub `ubuntu-latest` runner, crossplane off, no service | ResourceSet Ready and the three Deployments Available 51 s after the apply returned; idle, operator 28Mi, metrics server 35Mi, webhooks 13Mi, 0–5m CPU each |
| 2026-09-30 | floci, an SQS queue, a `TriggerAuthentication` on static keys | The Deployment went from 1 to 0 on the empty queue in 1 s; 10 messages with `queueLength: 5` took it to 2 in 12 s; a purge took it back to 0 in 12 s |
| 2026-09-30 | floci, crossplane on, `services = ["sqs"]` | The Role in floci's IAM 1 s after the seam was applied, holding only `sqs:GetQueueAttributes`; the workload withheld while the association did not sync |
| 2026-09-30 | floci, module off | Namespace and APIService gone within 13 s; the six CRDs still present |

Its decisions: [keda decisions](../decisions/keda.md).
