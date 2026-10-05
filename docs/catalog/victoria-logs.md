---
title: victoria-logs
description: "Logs storage: VictoriaLogs single-node, 7 days on a volume, LogsQL in Grafana."
category: observability
---

VictoriaLogs single-node stores your containers' logs, Kubernetes events and
your applications' OTLP logs, read in [grafana](grafana.md) in LogsQL.
**On by default**, on every cloud. How it fits the rest of the stack:
[Observability](../architecture/observability.md).

## Getting started

It is already on. Set how long logs are kept and how big their volume is:

```hcl title="terraform.tfvars" kube-start="victoria_logs"
kube = {
  victoria_logs = {
    retention    = "14d"
    storage_size = "50Gi"
  }
}
```

Then `kubectl -n victoria-logs get pvc,pods` shows the claim `Bound` and the
pod `Running`.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on or off. Off deletes the claim and its logs. |
| `retention` | `"7d"` | How long logs are kept, in hours, days, weeks or years; at least a day. |
| `storage_size` | `"20Gi"` | The claim's size, in `Gi` or `Ti`. `""`: an `emptyDir`, lost when the pod moves. |
| `values` | `{}` | Any [`victoria-logs-single` chart](https://artifacthub.io/packages/helm/victoriametrics/victoria-logs-single) value; yours win. |
| `values_secret` | `""` | A Secret in `victoria-logs` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl title="terraform.tfvars" kube-full="victoria_logs"
kube = {
  victoria_logs = {
    enabled      = true   # on by default; off deletes the claim and its logs
    retention    = "7d"   # how long logs are kept, at least a day
    storage_size = "20Gi" # the claim; "" keeps the logs in an emptyDir

    # Any value of the victoria-logs-single chart 0.13.9; yours win over the socle's.
    values = {
      server = {
        resources = { limits = { memory = "1Gi" } }
      }
    }

    # A Secret you create in victoria-logs, whose values.yaml key holds chart
    # values that must not reach the OpenTofu state; merged last.
    values_secret = "victoria-logs-values"
  }
}
```

## Good to know

- **On aws, set a default StorageClass or `storage_size = ""`**: EKS has
  none, and the claim stays `Pending`. See
  [victoria-metrics](victoria-metrics.md#good-to-know).
- **Turning it on feeds it**: [otel-agent](otel-agent.md) ships container
  logs (unless `kube.otel_agent.logs = false`), [otel-gateway](otel-gateway.md)
  events and your OTLP logs, and Grafana gets a VictoriaLogs datasource.
- **Kubernetes events have no `_msg`**: their message is `object.note`, so a
  phrase search misses them; find them with `k8s.resource.name:=events`.
- **`storage_size` grows, never shrinks**, and only where the StorageClass
  allows expansion; to or from `""` replaces the volume.
- **`tofu plan` refuses** credentials in `values` (auth flags, literal
  credential env values, a `Secret` in `extraObjects`), a `retention` under a
  day and a `storage_size` not in `Gi` or `Ti`.
- **Grafana downloads the logs plugin from grafana.com** when it starts: with
  no egress there, it has no logs datasource.

<details>
<summary>Under the hood</summary>

**Installed**: chart `victoria-logs-single` 0.13.9 (VictoriaLogs v1.52.0)
from `oci://ghcr.io/victoriametrics/helm-charts`, in the `victoria-logs`
namespace: a Deployment with strategy `Recreate` and a standalone claim.
In-cluster only, no authentication, at `victoria-logs.victoria-logs.svc:9428`.

**What the socle sets**: `server.mode: deployment`, `retentionPeriod` and
persistence from the attributes, requests 50m CPU and 128Mi, and
`fullnameOverride: victoria-logs`, which the collectors and Grafana rely on.

**Cloud access**: none; the logs are on the claim.

**Measured** on floci k3s, 2026-09-30: a container's line found 6 s after
its pod was created; VictoriaLogs at 2m CPU and 32–47Mi.

**Decisions**: [victoria-logs decisions](../decisions/victoria-logs.md).

</details>
