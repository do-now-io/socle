---
title: victoria-traces
description: "Traces storage, off by default until VictoriaTraces is GA: single-node, Jaeger API in Grafana."
category: observability
---

VictoriaTraces single-node, where your applications' traces are stored,
read in [grafana](grafana.md) through the Jaeger API. **Off by default:**
VictoriaTraces is not yet GA and its storage format is not committed, so an
upgrade may drop the traces it has stored. Turning it on accepts that
([VICTORIA-TRACES-01](../decisions/victoria-traces.md#victoria-traces-01-off-by-default-until-victoriatraces-is-ga)).
How it fits the rest of the stack:
[Observability](../architecture/observability.md).

## Getting started

Turn it on, knowing an upgrade may drop the traces stored so far; retention
and the volume are what you set next.

```hcl title="terraform.tfvars" kube-start="victoria_traces"
kube = {
  victoria_traces = {
    enabled      = true
    retention    = "3d"
    storage_size = "20Gi"
  }
}
```

After apply, `kubectl -n victoria-traces get pvc,pods` shows the claim
`Bound` and the pod `Running`, and Grafana's datasources list
VictoriaTraces; on aws, a claim left `Pending` needs a default StorageClass
([Per cloud](#per-cloud)).

## What it installs

| | |
| --- | --- |
| Chart | `victoria-traces-single` `0.1.11` (VictoriaTraces v0.11.0) from `oci://ghcr.io/victoriametrics/helm-charts` |
| Namespace | `victoria-traces` |
| Objects | the namespace, the chart source, the socle's and your values ConfigMaps, one `HelmRelease`: a Deployment with strategy `Recreate`, a standalone `PersistentVolumeClaim`, a headless Service |

**Address:** `victoria-traces.victoria-traces.svc:10428`, in-cluster only.
OTLP over HTTP comes in at `/insert/opentelemetry/v1/traces`, protobuf only,
which is what otel-gateway sends. Your applications send their traces to
[otel-gateway](otel-gateway.md) (`otel-gateway.otel-gateway.svc:4317` or
`:4318`), never here.

The socle's values: `server.mode: deployment`, as
[victoria-metrics](victoria-metrics.md#what-it-installs) and for its reason;
`retentionPeriod` from `retention` (the chart's own default is a month);
persistence from `storage_size`, on the cluster's default StorageClass; the
`prometheus.io/*` annotations on port 10428; requests 50m CPU and 128Mi
memory; `fullnameOverride: victoria-traces`.

**What turning it on adds to the other modules**, removed in the same
reconciliation when you turn it off:

| Module | What it gains |
| --- | --- |
| [otel-gateway](otel-gateway.md) | a traces pipeline: your OTLP traces, enriched with the sender's workload by `k8s_attributes` |
| [grafana](grafana.md) | a read-only `VictoriaTraces` datasource, uid `victoria-traces`, of the built-in Jaeger type, at `…:10428/select/jaeger` |

Every span your applications send is kept: there is no sampling. A
probability or tail sampling processor goes in `kube.otel_gateway.values`.

## What you can set

Under `kube.victoria_traces` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on, and the gateway's traces pipeline and Grafana's datasource with it. Off removes all three, **the stored traces included**. |
| `retention` | `"7d"` | How long traces are kept: a whole number of hours, days, weeks or years, at least a day. |
| `storage_size` | `"10Gi"` | The claim's size, in `Gi` or `Ti`. `""` renders no claim: the traces live in an `emptyDir` and go when the pod moves. |
| `values` | `{}` | Any `victoria-traces-single` chart value; yours win over the socle's. |
| `values_secret` | `""` | A Secret you create in `victoria-traces` with a `values.yaml` key, merged last. |

```hcl
kube = {
  victoria_traces = { enabled = true }
}
```

Changing `storage_size` follows the rules of
[victoria-metrics](victoria-metrics.md#what-you-can-set). Refused at plan, as
for victoria-metrics: an auth flag in `server.extraArgs`, a `server.env`
entry with a literal value named like a credential, a `Secret` in
`extraObjects`, a `retention` under a day, a `storage_size` not in `Gi` or
`Ti`.

### Every setting

Every attribute, at its default, and how chart values and secrets go in:

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

## Per cloud

The template is the same everywhere. On aws there is no default
StorageClass: the claim stays `Pending` until you set `storage_size = ""` or
create a default class, as for
[victoria-metrics](victoria-metrics.md#per-cloud).

## Cloud access

None: the traces are on the claim.

## Ordering

None. The gateway exports here only while the module is on, and retries while
it starts.

## Upgrade notes

- Until VictoriaTraces is GA, an upgrade of its chart may change the storage
  format and drop the traces stored so far.
- With strategy `Recreate`, an upgrade stops the pod before the new one
  starts.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-09-30 | floci, k3s, one node | turned on, Ready on a `Bound` claim in 26 s; one span posted from podinfo to the gateway found by its trace id through `/select/jaeger/api/traces/<id>` 24 s later; VictoriaTraces at 2m CPU and 10Mi |

Its decisions: [victoria-traces decisions](../decisions/victoria-traces.md).
