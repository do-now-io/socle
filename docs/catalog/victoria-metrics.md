---
title: victoria-metrics
description: "Metrics storage: VictoriaMetrics single-node, 15 days on a volume, PromQL in Grafana."
category: observability
---

VictoriaMetrics single-node, where [otel-agent](otel-agent.md) and
[otel-gateway](otel-gateway.md) write every metric and [grafana](grafana.md)
reads them back, in PromQL. On by default. How it fits the rest of the stack:
[Observability](../architecture/observability.md).

## What it installs

| | |
| --- | --- |
| Chart | `victoria-metrics-single` `0.48.0` (VictoriaMetrics v1.153.0) from `oci://ghcr.io/victoriametrics/helm-charts` |
| Namespace | `victoria-metrics` |
| Objects | the namespace, the chart source, the socle's and your values ConfigMaps, one `HelmRelease`: a Deployment with strategy `Recreate`, a standalone `PersistentVolumeClaim`, a headless Service |

**Address:** `victoria-metrics.victoria-metrics.svc:8428`, in-cluster only:
no route, no authentication. OTLP comes in at `/opentelemetry/v1/metrics`;
Grafana's Prometheus datasource reads the same address.

The socle's values:

- `server.mode: deployment`, so the volume is a standalone claim you can
  resize ([VICTORIA-METRICS-01](../decisions/victoria-metrics.md#victoria-metrics-01-a-deployment-and-a-standalone-claim-not-a-statefulset));
- `retentionPeriod` from `retention`, persistence from `storage_size`, on the
  cluster's default StorageClass;
- `-opentelemetry.usePrometheusNaming`: OTLP names become Prometheus ones
  (dots to underscores, unit and `_total` suffixes), so a scraped Cilium or
  Flux metric reads as its upstream dashboards expect;
- `-storage.maxHourlySeries=100000`: past that many new series in an hour,
  new series are dropped with a log line
  ([VICTORIA-METRICS-03](../decisions/victoria-metrics.md#victoria-metrics-03-a-cardinality-guard-of-100-000-new-series-an-hour));
- `prometheus.io/scrape` on port 8428, so otel-gateway scrapes its own
  metrics;
- requests 50m CPU and 128Mi memory, no limit;
- `fullnameOverride: victoria-metrics`. Overriding it in `values` breaks the
  collectors' and Grafana's wiring.

## What you can set

Under `kube.victoria_metrics` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on. Off removes the release and the namespace, **the claim and its data included**. |
| `retention` | `"15d"` | How long samples are kept: a whole number of hours, days, weeks or years (`48h`, `15d`, `4w`, `1y`), at least a day. |
| `storage_size` | `"20Gi"` | The claim's size, in `Gi` or `Ti`. `""` renders no claim: the data lives in an `emptyDir` and goes when the pod moves. |
| `values` | `{}` | Any `victoria-metrics-single` chart value; yours win over the socle's. |
| `values_secret` | `""` | A Secret you create in `victoria-metrics` with a `values.yaml` key, merged last. |

```hcl
kube = {
  victoria_metrics = {
    retention    = "30d"
    storage_size = "50Gi"
    values = {
      server = {
        extraArgs = { "storage.maxHourlySeries" = "300000" }
        resources = { requests = { memory = "1Gi" } }
      }
    }
  }
}
```

**Write numeric flags as strings.** Helm renders a number from a million up
as `1e+06`, which an integer flag refuses at start
([VICTORIA-METRICS-02](../decisions/victoria-metrics.md#victoria-metrics-02-numeric-flags-as-strings)).
The plan does not refuse a number.

**Changing `storage_size`.** Growing works where the StorageClass allows
expansion (`allowVolumeExpansion: true`); where it does not, the upgrade
fails and the claim keeps its first size. Shrinking is refused by the API
server. To or from `""` replaces the volume: the data is lost.

Refused at plan, because `values` lands in the OpenTofu state and in a
ConfigMap: a `server.extraArgs` flag named like a password, an auth key or a
token (`httpAuth.password`, `deleteAuthKey`, `snapshotAuthKey`…); a
`server.env` entry with a literal value named like a credential
(`VM_httpAuth_password`); a `Secret` in `extraObjects`. Also refused: a
`retention` under a day, in months or with a fraction, and a `storage_size`
not in `Gi` or `Ti`.

## Per cloud

The template is the same everywhere; the default StorageClass under the
claim is the cluster's.

| Cloud | What to know |
| --- | --- |
| aws | The socle installs the EBS CSI driver (`eks_addons.ebs_csi`) but creates no StorageClass, and EKS marks none as default. The claim stays `Pending` and the pod never starts until you set `storage_size = ""` or create a default class (below). |
| gcp, azure, scaleway | GKE, AKS and Kapsule ship a default class (`standard-rwo`, `managed-csi`, `scw-bssd`). Not yet measured with the socle. |

A default class for EBS, created before or after the module (a claim already
`Pending` is given the new default):

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

## Cloud access

None: the data is on the claim.

## Ordering

None. The collectors export here only while the module is on, and retry
while it starts.

## Upgrade notes

- The chart version is the socle's. A new `storage_size` or `retention`
  reaches the pod at once: the values ConfigMaps carry
  `reconcile.fluxcd.io/watch: Enabled`.
- With strategy `Recreate`, an upgrade stops the pod before the new one
  starts: metrics sent in between are retried by the collectors, within their
  queue.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-09-29 | floci, k3s, `local-path` class | idle: 1–2m CPU, 12Mi, on a 20Gi claim `Bound` |
| 2026-09-29 | floci, k3s | under both collectors on one node: 10–14m CPU, about 150Mi |

Its decisions: [victoria-metrics decisions](../decisions/victoria-metrics.md).
