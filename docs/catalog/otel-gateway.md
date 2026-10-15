---
title: otel-gateway
description: "Cluster-level OpenTelemetry collector: your applications' OTLP metrics, logs and traces, and the Kubernetes events."
category: observability
---

The OpenTelemetry Collector as a one-replica Deployment: the OTLP your
applications send, with their workload and namespace added, and the
Kubernetes events as logs, written to whichever of
[monitoring](monitoring.md)'s VictoriaMetrics, VictoriaLogs and
VictoriaTraces are on. **On by default**, on every cloud. It scrapes
nothing: monitoring's vmagent does.

## Getting started

It is already on, with nothing to name. What you may set first is its
memory:

```hcl kube-start="otel_gateway"
kube = {
  otel_gateway = {
    values = {
      resources = { limits = { memory = "2Gi" } }
    }
  }
}
```

Then `kubectl -n otel-gateway get deployment otel-gateway` shows it ready.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on or off, its rules with it. |
| `values` | `{}` | Any [`opentelemetry-collector` chart](https://artifacthub.io/packages/helm/opentelemetry-helm/opentelemetry-collector) value; yours win. |
| `values_secret` | `""` | A Secret in `otel-gateway` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl kube-full="otel_gateway"
kube = {
  otel_gateway = {
    enabled = true # on by default; off removes the release and its rules

    # Any value of the opentelemetry-collector chart 0.173.1; yours win over the socle's.
    values = {
      resources = { limits = { memory = "2Gi" } }
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
- **Prometheus endpoints are not its job**: annotate your pods
  `prometheus.io/scrape: "true"` and monitoring's vmagent scrapes them.
- **Lists in `values` are replaced, not merged**: to add an exporter, write
  the pipeline's whole `exporters` list, the socle's entries included.
- **`tofu plan` refuses** literal credentials in `values` (authenticators,
  exporter headers, `extraEnvs`, a `Secret` in `extraManifests`). Write
  `${env:NAME}`, with `NAME` set from a Secret by `extraEnvs` `valueFrom`.
- **Its alert rules ship with it**: both collectors' health, from
  [awesome-prometheus-alerts](https://samber.github.io/awesome-prometheus-alerts/)
  ([every rule](../reference/alert-rules.md)). They fire once monitoring's
  alerting is on.
- **Keep one replica**: with two, every Kubernetes event is read twice.

<details>
<summary>Under the hood</summary>

**Installed**: chart `opentelemetry-collector` 0.173.1 (collector 0.160.0)
from `oci://ghcr.io/open-telemetry/opentelemetry-helm-charts`, in
`deployment` mode, in the `otel-gateway` namespace, with a `ClusterIP`
Service, and a `VMRule` applied by a Flux `Kustomization` once monitoring
has installed its CRD.

**What the socle sets**: the OTLP receivers, `k8s_attributes`, the
Kubernetes events while monitoring's logs are on; each exporter and the logs
and traces pipelines follow monitoring's parts, `nop` for metrics with
monitoring off; its own telemetry on port 8888, annotated for vmagent.
Requests 100m CPU and 128Mi, a 1Gi memory limit.

**Cloud access**: none.

**Measured** on floci k3s, 2026-09-29: 5–6m CPU and 45–50Mi while it also
collected the cluster's state; an OTLP gauge from podinfo read back with its
namespace and deployment labels.

</details>
