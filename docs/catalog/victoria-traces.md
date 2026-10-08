---
title: victoria-traces
description: "Traces storage, off by default until VictoriaTraces is GA: single-node, Jaeger API in Grafana."
category: observability
---

VictoriaTraces single-node stores your applications' traces, read in
[grafana](grafana.md) through the Jaeger API. **Off by default**, on every
cloud: VictoriaTraces is not yet GA, and an upgrade may drop the traces it
holds.

## Getting started

Turn it on, knowing an upgrade may drop the traces stored so far:

```hcl title="terraform.tfvars" kube-start="victoria_traces"
kube = {
  victoria_traces = {
    enabled      = true
    retention    = "3d"
    storage_size = "20Gi"
  }
}
```

Then `kubectl -n victoria-traces get pvc,pods` shows the claim `Bound` and
the pod `Running`.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `false` | Turns the module, the gateway's traces pipeline and Grafana's datasource on or off. Off deletes the stored traces. |
| `retention` | `"7d"` | How long traces are kept, in hours, days, weeks or years; at least a day. |
| `storage_size` | `"10Gi"` | The claim's size, in `Gi` or `Ti`. `""`: an `emptyDir`, lost when the pod moves. |
| `values` | `{}` | Any [`victoria-traces-single` chart](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-traces-single) value; yours win. |
| `values_secret` | `""` | A Secret in `victoria-traces` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl title="terraform.tfvars" kube-full="victoria_traces"
kube = {
  victoria_traces = {
    enabled      = false  # off by default; off deletes the claim and its traces
    retention    = "7d"   # how long traces are kept, at least a day
    storage_size = "10Gi" # the claim; "" keeps the traces in an emptyDir

    # Any value of the victoria-traces-single chart 0.1.11; yours win over the socle's.
    values = {
      server = {
        resources = { limits = { memory = "1Gi" } }
      }
    }

    # A Secret you create in victoria-traces, whose values.yaml key holds chart
    # values that must not reach the OpenTofu state; merged last.
    values_secret = "victoria-traces-values"
  }
}
```

## Good to know

- **Send traces to [otel-gateway](otel-gateway.md)**,
  `otel-gateway.otel-gateway.svc:4317` or `:4318`, never here.
- **Every span is kept**: there is no sampling. A sampling processor goes in
  `kube.otel_gateway.values`.
- **On aws, set a default StorageClass or `storage_size = ""`**: EKS has
  none, and the claim stays `Pending`. See
  [victoria-metrics](victoria-metrics.md#good-to-know).
- **`tofu plan` refuses** what it refuses for victoria-metrics: credentials
  in `values`, a `retention` under a day, a `storage_size` not in `Gi` or
  `Ti`. `storage_size` grows where the class allows it, never shrinks.
- **Upgrades**: until VictoriaTraces is GA, a chart upgrade may change the
  storage format and drop the stored traces.

<details>
<summary>Under the hood</summary>

**Installed**: chart `victoria-traces-single` 0.1.11 (VictoriaTraces
v0.11.0) from `oci://ghcr.io/victoriametrics/helm-charts`, in the
`victoria-traces` namespace: a Deployment with strategy `Recreate` and a
standalone claim, in-cluster only at
`victoria-traces.victoria-traces.svc:10428`.

**What the socle sets**: `server.mode: deployment`, `retentionPeriod` and
persistence from the attributes, requests 50m CPU and 128Mi, and
`fullnameOverride: victoria-traces`. Turned on, it adds a traces pipeline to
otel-gateway and a Jaeger datasource to Grafana.

**Cloud access**: none; the traces are on the claim.

**Measured** on floci k3s, 2026-09-30: Ready in 26 s; a span posted to the
gateway found by its trace id 24 s later.

</details>
