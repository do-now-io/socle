---
title: keda
description: Event-driven autoscaling down to zero, with an optional read-only role for your aws queues.
category: autoscaling
requires:
  - module: crossplane
    clouds: [aws]
    why: "only when services is set: the operator's role is a Crossplane managed resource"
---

KEDA scales a workload on events rather than CPU, down to zero: a
`ScaledObject` scales a Deployment on a queue's depth, a cron window or a
PromQL query. Turn it on for workers behind a queue. **Off by default**, on
every cloud; the operator's own role (`services`) is aws only.

## Getting started

Turn it on; for aws queues, add their services to
`aws.crossplane.allowed_services` and name them in `services`:

```hcl title="terraform.tfvars" kube-start="keda"
kube = {
  crossplane = { enabled = true }
  keda = {
    enabled  = true
    services = ["sqs", "cloudwatch"]
  }
}
```

Then `kubectl get apiservice v1beta1.external.metrics.k8s.io` is `Available`.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on or off. |
| `services` | `[]` | aws: the services the operator's role may read: `sqs`, `cloudwatch`, `kinesis`, `dynamodb`. `[]`: no role. |
| `values` | `{}` | Any [`keda` chart](https://artifacthub.io/packages/helm/kedacore/keda) value; yours win. |
| `values_secret` | `""` | A Secret in `keda` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

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

## Good to know

- **`services` needs crossplane and aws.** `tofu plan` refuses it otherwise,
  even with the module off: leave it empty there. RDS, ELB and Lambda
  metrics go through `cloudwatch`.
- **The plan cannot see `aws.crossplane.allowed_services`.** A service
  missing there makes the role fail at IAM and the module wait, with the
  reason on the Role's `Synced` condition.
- **Use the operator's role** (`identityOwner: keda`, the default). A
  `TriggerAuthentication` with `identityOwner: workload` or a `roleArn` does
  not work under the socle's boundary. Any other source (gcp, azure, Kafka,
  Redis...) takes a `TriggerAuthentication` on a Secret of yours.
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
`PodIdentityAssociation/keda-operator`.

**What the socle sets**: CRDs kept on removal, webhooks failing open
(`Ignore`), requests under the chart's limits, and an annotation that rolls
the operator when `services` changes. Your `values` are merged over these
([SOCLE-06](../decisions/socle.md#socle-06-the-clients-values-win)).

**Cloud access**: on aws, the role `<cluster>-keda-operator` holds one
read-only statement per service named, the exact calls each scaler makes, on
every resource: depths, never messages; `dynamodb` grants `Query` on every
table ([KEDA-01](../decisions/keda.md#keda-01-the-operators-role-scoped-per-aws-service)).

**Ordering**: waits for the `crossplane` ResourceSet; on aws the chart waits
for the role and its association. Turn the module off before crossplane,
never in the same apply.

**Measured** on floci, 2026-09-30: 10 messages with `queueLength: 5` scaled
a Deployment from 0 to 2 in 12 s, and a purge back to 0 in 12 s.

**Decisions**: [keda decisions](../decisions/keda.md).

</details>
