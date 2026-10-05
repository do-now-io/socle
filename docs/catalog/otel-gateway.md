---
title: otel-gateway
description: "Cluster-level OpenTelemetry collector: object state, annotated Prometheus scrapes, and your applications' OTLP."
category: observability
---

The OpenTelemetry Collector as a one-replica Deployment, for what lives in the
cluster rather than on a node: the state of Kubernetes objects, the
Prometheus endpoints of annotated pods, Kubernetes events, and the OTLP your
applications send. It writes to [victoria-metrics](victoria-metrics.md),
[victoria-logs](victoria-logs.md) and [victoria-traces](victoria-traces.md),
whichever are on, and ships the workloads dashboard to [grafana](grafana.md).
On by default. How it fits the rest of the stack:
[Observability](../architecture/observability.md).

## Getting started

On by default, with nothing to name: what you set first, if anything, is a
second replica.

```hcl title="terraform.tfvars" kube-start="otel_gateway"
kube = {
  otel_gateway = {
    values = {
      replicaCount = 2
    }
  }
}
```

After apply, `kubectl -n otel-gateway get deployment otel-gateway` shows its
replicas ready, and your applications send OTLP to
`otel-gateway.otel-gateway.svc:4317` or `:4318`.

## What it installs

| | |
| --- | --- |
| Chart | `opentelemetry-collector` `0.173.1` (collector 0.160.0) from `oci://ghcr.io/open-telemetry/opentelemetry-helm-charts`, in `deployment` mode, one replica |
| Namespace | `otel-gateway` |
| Objects | the namespace, the chart source, the socle's and your values ConfigMaps, one `HelmRelease` (Deployment, Service and ConfigMap all named `otel-gateway`), and a Flux `Kustomization` applying the dashboard ConfigMap |

**Send your OTLP here:** `otel-gateway.otel-gateway.svc:4317` (gRPC) or
`:4318` (HTTP). The Service is `ClusterIP`; there is no `hostPort`. Jaeger and
Zipkin receivers are off.

What it collects, and where it goes:

| Pipeline | Inputs | Exported to |
| --- | --- | --- |
| metrics | `k8s_cluster` every 10 s (Deployments, DaemonSets, StatefulSets, ReplicaSets, Jobs, pods, containers, nodes, namespaces); every running pod annotated `prometheus.io/scrape: "true"`, every 30 s; the collector's own telemetry; your OTLP metrics | victoria-metrics while it is on, nowhere (`nop`) otherwise |
| logs | Kubernetes events (`k8sobjects` on `events.k8s.io`, deleted events excluded); your OTLP logs | victoria-logs, only while it is on |
| traces | your OTLP traces | victoria-traces, only while it is on |

`k8s_attributes` puts the sending pod's workload, namespace and labels on
your OTLP, matched by the connection's IP.

**Scraping.** A pod is scraped when it carries `prometheus.io/scrape: "true"`
and runs. Its `prometheus.io/port`, `prometheus.io/path` and
`prometheus.io/scheme` annotations say where. Every scraped series gets
`k8s_namespace_name`, `k8s_pod_name` and `k8s_node_name`, the labels the
kubelet and cluster metrics carry, so one dashboard variable filters them
all. There is no `ServiceMonitor` or `PodMonitor` support
([OTEL-GATEWAY-01](../decisions/otel-gateway.md#otel-gateway-01-scraping-by-annotation-no-servicemonitor)).

**Resources.** Requests 100m CPU and 128Mi memory, a 1Gi memory limit
([OTEL-GATEWAY-03](../decisions/otel-gateway.md#otel-gateway-03-a-1gi-memory-limit-so-gomemlimit-applies)).

**The workloads dashboard**, *Kubernetes / Workloads*: nodes ready, pods by
phase, scrape targets up, Deployments missing replicas, DaemonSets missing
nodes, StatefulSets missing pods, the top 10 container restarts, CPU and
memory requested by namespace. The "missing" panels are empty when everything
is whole.

## What you can set

Under `kube.otel_gateway` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on. Off removes the release, the namespace and the dashboard. |
| `values` | `{}` | Any `opentelemetry-collector` chart value; yours win over the socle's. |
| `values_secret` | `""` | A Secret you create in `otel-gateway` with a `values.yaml` key, merged last. |

Every other knob is chart configuration: a second scrape job, a `filter`
processor to drop a noisy metric, a sampling processor, an exporter to your
own backend. Lists are replaced, not merged: write a pipeline's whole
`receivers` or `exporters` list, the socle's entries included.

Two replicas: set `replicaCount`. The chart then turns on a leader election
for `k8s_cluster`, so objects are not reported twice
([OTEL-GATEWAY-02](../decisions/otel-gateway.md#otel-gateway-02-one-replica-ha-through-values)).

Refused at plan, as for [otel-agent](otel-agent.md#what-you-can-set): a
literal token, password or client secret in a `config.extensions`
authenticator, a literal `Authorization` or API-key header in a
`config.exporters` entry, an `extraEnvs` entry with a literal value named like
a credential, and a `Secret` in `extraManifests`. `${env:NAME}`, set from a
Secret through `extraEnvs` `valueFrom`, is accepted.

### Every setting

Every attribute, at its default, and how chart values and secrets go in:

```hcl title="terraform.tfvars" kube-full="otel_gateway"
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

## Per cloud

The same template on aws, gcp, azure and scaleway. On GKE Autopilot the one
replica is billed by its requests.

## Cloud access

None.

## Ordering

No `dependsOn`. Each exporter and each logs or traces pipeline follows its
backend's `enabled`, in the same reconciliation; the values ConfigMaps carry
`reconcile.fluxcd.io/watch: Enabled`, so the release is upgraded at once. A
backend that is on but not yet running is retried.

## Upgrade notes

- The chart lists Helm 4.0 as a prerequisite. Flux v2.9.5's helm-controller
  installs, upgrades and uninstalls it.
- The relabelling in the socle's scrape job writes `$$1:$$2`: the collector
  expands `$` in its own configuration. A scrape job you add through `values`
  doubles its dollar signs the same way.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-09-29 | floci, k3s, one node | the gateway at 5–6m CPU and 45–50Mi; `k8s_deployment_available` queryable 1–2 s after the rollout; an OTLP gauge posted from podinfo read back with `k8s_namespace_name=hello` and `k8s_deployment_name=podinfo`; scraped targets included the Flux controllers, which annotate their pods |

Its decisions: [otel-gateway decisions](../decisions/otel-gateway.md).
