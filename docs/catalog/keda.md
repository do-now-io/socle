---
title: keda
description: Event-driven autoscaling down to zero, with optional read-only access to your aws queues or gcp Pub/Sub subscriptions.
category: autoscaling
requires:
  - module: crossplane
    clouds: [aws, gcp]
    why: "only when services is set: the operator's access is a Crossplane managed resource"
---

KEDA scales a workload on events rather than CPU, down to zero: a
`ScaledObject` scales a Deployment on a queue's depth, a cron window or a
PromQL query. Turn it on for workers behind a queue. **Off by default**, on
every cloud; the operator's own access (`services`) is aws and gcp only.

## Getting started

Turn it on; for aws queues, add their services to
`aws.crossplane.allowed_services` and name them in `services`:

```hcl kube-start="keda"
kube = {
  crossplane = { enabled = true }
  keda = {
    enabled  = true
    services = ["sqs", "cloudwatch"]
  }
}
```

On gcp, for Pub/Sub, add `roles/monitoring.viewer` to
`gcp.crossplane.allowed_roles` and name `pubsub`:

```hcl
kube = {
  crossplane = { enabled = true }
  keda = {
    enabled  = true
    services = ["pubsub"]
  }
}
```

Then `kubectl get apiservice v1beta1.external.metrics.k8s.io` is `Available`.
On gcp a `ScaledObject` reads Pub/Sub as the operator through a
`TriggerAuthentication` with no secret:

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: operator-principal
  namespace: orders
spec:
  podIdentity:
    provider: gcp # the operator's own principal
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
        subscriptionName: orders-worker
        value: "50" # messages per replica
```

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on or off. |
| `services` | `[]` | aws: the services the operator's role may read: `sqs`, `cloudwatch`, `kinesis`, `dynamodb`. gcp: `pubsub`. `[]`: no role. |
| `values` | `{}` | Any [`keda` chart](https://artifacthub.io/packages/helm/kedacore/keda) value; yours win. |
| `values_secret` | `""` | A Secret in `keda` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl kube-full="keda"
kube = {
  keda = {
    enabled  = false # off by default
    services = []    # aws: "sqs", "cloudwatch", "kinesis", "dynamodb"; gcp: "pubsub"; [] = no role

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

## Good to know

- **`services` needs crossplane, and names the cluster's cloud's
  services.** `tofu plan` refuses it otherwise, even with the module off:
  leave it empty there. On aws, RDS, ELB and Lambda metrics go through
  `cloudwatch`; `["sqs"]` on gcp or `["pubsub"]` on aws is refused.
- **The plan cannot see `aws.crossplane.allowed_services` or
  `gcp.crossplane.allowed_roles`.** A service missing on aws, or
  `roles/monitoring.viewer` missing on gcp, makes the role or the binding
  fail at IAM and the module wait, with the reason on its `Synced`
  condition.
- **Use the operator's identity.** On aws, `identityOwner: keda` (the
  default): a `TriggerAuthentication` with `identityOwner: workload` or a
  `roleArn` does not work under the socle's boundary. On gcp, a
  `TriggerAuthentication` with `podIdentity.provider: gcp` and nothing else;
  leave the chart's `podIdentity.gcp.enabled` off, it would make the operator
  impersonate a Google service account the binding does not name. Any other
  source (azure, Kafka, Redis...) takes a `TriggerAuthentication` on a Secret
  of yours.
- **`pubsub` lets KEDA count, not pull.** The binding reads Cloud Monitoring
  only. Your Deployment still pulls as its own principal
  (`…/subject/ns/<namespace>/sa/<serviceaccount>`), with
  `roles/pubsub.subscriber` on its subscription, granted in your own
  Terraform with the subscription.
- **Keep the metrics server schedulable.** KEDA serves
  `external.metrics.k8s.io`, an aggregated API: while
  `keda-operator-metrics-apiserver` cannot run, discovery fails cluster-wide
  and terminating namespaces hang (measured on GKE, 2026-10-07). Keep it
  schedulable (capacity, no failing admission) before tearing anything down.
- **Credentials never go in `values`**: `tofu plan` refuses them. A scaler's
  go in a Secret its `TriggerAuthentication` names.
- **Upgrades**: the chart moves with `socle_version`. The CRDs are kept when
  the module is off; a `ScaledObject` left behind then stops scaling, at its
  current replica count.

<details>
<summary>Under the hood</summary>

**Installed**: chart `keda` 2.21.0 from `https://kedacore.github.io/charts`, in
`keda` (Pod Security `restricted`): the operator, the metrics server and the
admission webhooks, the `v1beta1.external.metrics.k8s.io` APIService and six
CRDs. On aws with `services`, `Role/keda-operator` and
`PodIdentityAssociation/keda-operator`; on gcp with `pubsub`,
`ProjectIAMMember/keda-operator`.

**What the socle sets**: CRDs kept on removal, webhooks failing open
(`Ignore`), requests under the chart's limits, and an annotation that rolls
the operator when `services` changes. Your `values` are merged over these.

**Cloud access**: on aws, the role `<cluster>-keda-operator` holds one
read-only statement per service named, the exact calls each scaler makes, on
every resource: depths, never messages; `dynamodb` grants `Query` on every
table. On gcp, `pubsub` is one project-level `ProjectIAMMember/keda-operator`
granting `roles/monitoring.viewer` to the operator's Workload Identity
principal — the pod's own ServiceAccount, no Google service account: KEDA's
`gcp-pubsub` scaler reads the subscription's depth from Cloud Monitoring,
never from Pub/Sub, so the grant is every metric of the project, read-only,
never a message.

**Ordering**: on aws the role is a step of its own, `cloud`, which aws adds
to the module
([`oci/clusters/aws/keda/patch.yaml`](../../oci/clusters/aws/keda/patch.yaml),
[SOCLE-32](../decisions/socle.md#socle-32-what-only-one-cloud-has-that-cloud-adds-to-the-module-as-steps)): the module waits for the `crossplane`
ResourceSet, and the chart's step starts only once the role and its
association are Ready (`keda-access`), since Pod Identity hands credentials
at admission only. On gcp the binding is gcp's `cloud` step
([`oci/clusters/gcp/keda/patch.yaml`](../../oci/clusters/gcp/keda/patch.yaml)),
with the same `keda-access` wait; GKE hands out tokens at call time, so there
the order only spares the operator minutes of denied reads. Turn the module
off before crossplane, never in the same apply. Why monitoring and no Google
service account: [KEDA-02](../decisions/keda.md#keda-02-on-gcp-one-cloud-monitoring-read-on-the-operators-principal).

**Measured** on floci, 2026-09-30: 10 messages with `queueLength: 5` scaled
a Deployment from 0 to 2 in 12 s, and a purge back to 0 in 12 s.

</details>
