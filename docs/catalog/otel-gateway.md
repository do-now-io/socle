---
title: otel-gateway
description: "Cluster-level OpenTelemetry collector: object state, annotated Prometheus scrapes, and your applications' OTLP."
category: observability
---

The OpenTelemetry Collector as a one-replica Deployment, for what lives in
the cluster rather than on a node: Kubernetes object state and events, the
Prometheus endpoints of annotated pods, and the OTLP your applications send.
It writes to whichever of [victoria-metrics](victoria-metrics.md),
[victoria-logs](victoria-logs.md) and [victoria-traces](victoria-traces.md)
are on. **On by default**, on every cloud.

## Getting started

It is already on, with nothing to name. What you may set first is a second
replica:

```hcl kube-start="otel_gateway"
kube = {
  otel_gateway = {
    values = {
      replicaCount = 2
    }
  }
}
```

Then `kubectl -n otel-gateway get deployment otel-gateway` shows its replicas
ready.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on or off, its dashboard with it. |
| `values` | `{}` | Any [`opentelemetry-collector` chart](https://artifacthub.io/packages/helm/opentelemetry-helm/opentelemetry-collector) value; yours win. |
| `values_secret` | `""` | A Secret in `otel-gateway` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl kube-full="otel_gateway"
kube = {
  otel_gateway = {
    enabled = true # on by default; off removes the release and the dashboard

    # Any value of the opentelemetry-collector chart 0.173.1; yours win over the socle's.
    values = {
      replicaCount = 2
      resources    = { limits = { memory = "2Gi" } }
    }

    # A Secret you create in otel-gateway, whose values.yaml key holds chart values
    # that must not reach the OpenTofu state, an exporter's headers say; merged last.
    values_secret = "otel-gateway-values"
  }
}
```

## Good to know

- **Send your OTLP to `otel-gateway.otel-gateway.svc:4317`** (gRPC) or
  `:4318` (HTTP). It adds the sender's workload, namespace and labels.
- **A pod is scraped when annotated** `prometheus.io/scrape: "true"`, with
  `prometheus.io/port`, `path` and `scheme` saying where. There is no
  `ServiceMonitor` or `PodMonitor` support.
- **Lists in `values` are replaced, not merged**: to add an exporter, write
  the pipeline's whole `exporters` list, the socle's entries included. A
  scrape job you add doubles its `$` signs (`$$1`).
- **`tofu plan` refuses** literal credentials in `values` (authenticators,
  exporter headers, `extraEnvs`, a `Secret` in `extraManifests`). Write
  `${env:NAME}`, with `NAME` set from a Secret by `extraEnvs` `valueFrom`.
- **Its alert rules ship with it**: the gateway's own health, refused or
  failed data and a full queue ([every rule](../reference/alert-rules.md)).
  They fire once [alerting](alerting.md) is on. The Kubernetes rules ship
  with [kube_state_metrics](kube-state-metrics.md), which this module scrapes.
- **Keep one replica**: the socle configures no leader election, so with
  `replicaCount = 2` every object's state is reported twice.

<details>
<summary>Under the hood</summary>

**Installed**: chart `opentelemetry-collector` 0.173.1 (collector 0.160.0)
from `oci://ghcr.io/open-telemetry/opentelemetry-helm-charts`, in
`deployment` mode, in the `otel-gateway` namespace, with a `ClusterIP`
Service and the *Kubernetes / Workloads* dashboard for Grafana.

**What the socle sets**: `k8s_cluster` every 10 s, annotated scrapes every
30 s, kube-state-metrics' two ports every 30 s while that module is on, Kubernetes events, OTLP receivers; each exporter and the logs and
traces pipelines follow their backend's `enabled`. Requests 100m CPU and
128Mi, a 1Gi memory limit.

**Cloud access**: none.

**Measured** on floci k3s, 2026-09-29: 5–6m CPU and 45–50Mi; an OTLP gauge
from podinfo read back with its namespace and deployment labels.

</details>
