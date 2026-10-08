---
title: victoria-metrics
description: "Metrics storage: VictoriaMetrics single-node, 15 days on a volume, PromQL in Grafana."
category: observability
---

VictoriaMetrics single-node, where [otel-agent](otel-agent.md) and
[otel-gateway](otel-gateway.md) write every metric and [grafana](grafana.md)
reads them back, in PromQL. **On by default**, on every cloud. How it fits
the rest of the stack: [Observability](../architecture/observability.md).

## Getting started

It is already on. Set how long samples are kept and how big their volume is:

```hcl title="terraform.tfvars" kube-start="victoria_metrics"
kube = {
  victoria_metrics = {
    retention    = "30d"
    storage_size = "50Gi"
  }
}
```

Then `kubectl -n victoria-metrics get pvc,pods` shows the claim `Bound` and
the pod `Running`.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on or off. Off deletes the claim and its data. |
| `retention` | `"15d"` | How long samples are kept, in hours, days, weeks or years (`48h`, `4w`); at least a day. |
| `storage_size` | `"20Gi"` | The claim's size, in `Gi` or `Ti`. `""`: an `emptyDir`, lost when the pod moves. |
| `values` | `{}` | Any [`victoria-metrics-single` chart](https://artifacthub.io/packages/helm/victoriametrics/victoria-metrics-single) value; yours win. |
| `values_secret` | `""` | A Secret in `victoria-metrics` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl title="terraform.tfvars" kube-full="victoria_metrics"
kube = {
  victoria_metrics = {
    enabled      = true   # on by default; off deletes the claim and its data
    retention    = "15d"  # how long samples are kept, at least a day
    storage_size = "20Gi" # the claim; "" keeps the data in an emptyDir

    # Any value of the victoria-metrics-single chart 0.48.0; yours win over the socle's.
    values = {
      server = {
        extraArgs = { "storage.maxHourlySeries" = "300000" }
        resources = { limits = { memory = "2Gi" } }
      }
    }

    # A Secret you create in victoria-metrics, whose values.yaml key holds chart
    # values that must not reach the OpenTofu state; merged last.
    values_secret = "victoria-metrics-values"
  }
}
```

## Good to know

- **On aws, the claim stays `Pending`**: the socle installs the EBS CSI
  driver but EKS marks no StorageClass as default. Set `storage_size = ""`,
  or create a default class (a claim already `Pending` then binds):

  ```yaml
  apiVersion: storage.k8s.io/v1
  kind: StorageClass
  metadata:
    name: gp3
    annotations:
      storageclass.kubernetes.io/is-default-class: "true"
  provisioner: ebs.csi.aws.com
  volumeBindingMode: WaitForFirstConsumer
  allowVolumeExpansion: true
  parameters:
    type: gp3
  ```

- **`storage_size` grows, never shrinks**, and only where the StorageClass
  allows expansion. To or from `""` replaces the volume: the data is lost.
- **Write numeric flags in `values` as strings**: Helm renders a million as
  `1e+06`, which the flag refuses at start. The plan does not catch it.
- **Past 100,000 new series in an hour, new series are dropped** with a log
  line. Raise `storage.maxHourlySeries` in `server.extraArgs` if you need to.
- **`tofu plan` refuses** credentials in `values` (auth flags, literal
  credential env values, a `Secret` in `extraObjects`), a `retention` under a
  day, in months or with a fraction, and a `storage_size` not in `Gi` or `Ti`.
- **Upgrades**: strategy `Recreate` stops the pod before the new one starts;
  the collectors retry within their queue.

<details>
<summary>Under the hood</summary>

**Installed**: chart `victoria-metrics-single` 0.48.0 (VictoriaMetrics
v1.153.0) from `oci://ghcr.io/victoriametrics/helm-charts`, in the
`victoria-metrics` namespace: a Deployment with strategy `Recreate` and a
standalone claim. In-cluster only, no authentication, at
`victoria-metrics.victoria-metrics.svc:8428`.

**What the socle sets**: `server.mode: deployment`, so the claim can be
resized; `-opentelemetry.usePrometheusNaming`, so OTLP names read as
upstream dashboards expect; `-storage.maxHourlySeries=100000`; requests 50m
CPU and 128Mi, no limit; `fullnameOverride: victoria-metrics`, which the
collectors and Grafana rely on.

**Cloud access**: none; the data is on the claim.

**Measured** on floci k3s, 2026-09-29: under both collectors on one node,
10–14m CPU and about 150Mi.

</details>
