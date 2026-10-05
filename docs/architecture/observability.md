---
title: Observability
description: "The cross-cloud view: OpenTelemetry collects, Victoria stores, Grafana reads, inside each cluster; the cloud's own signals are read from outside."
sidebar:
  order: 4
---

Every socle cluster carries its own monitoring stack: metrics, logs and
traces from every workload and from the cluster itself, collected by
OpenTelemetry, stored in the Victoria family, read in Grafana. The same
templates run on all four clouds, and each cluster is self-contained: no
remote-write, no federation, no central Alertmanager
([SOCLE-03](../decisions/socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud)).
The stack needs no cloud access: every backend stores on a volume, so it
creates no bucket, no key and no role.

## Six modules

One module per chart release, one namespace each
([SOCLE-27](../decisions/socle.md#socle-27-one-module-per-chart-release-two-collector-modules)):

| Module | Runs as | Default | Page |
| --- | --- | --- | --- |
| `otel_agent` | OpenTelemetry Collector, DaemonSet | on | [otel-agent](../catalog/otel-agent.md) |
| `otel_gateway` | OpenTelemetry Collector, Deployment, 1 replica | on | [otel-gateway](../catalog/otel-gateway.md) |
| `victoria_metrics` | VictoriaMetrics single-node, 1 pod and a PVC | on | [victoria-metrics](../catalog/victoria-metrics.md) |
| `victoria_logs` | VictoriaLogs single-node, 1 pod and a PVC | on | [victoria-logs](../catalog/victoria-logs.md) |
| `victoria_traces` | VictoriaTraces single-node, 1 pod and a PVC | **off**: pre-GA, an upgrade may drop stored traces | [victoria-traces](../catalog/victoria-traces.md) |
| `grafana` | Grafana, Deployment, 1 replica | on | [grafana](../catalog/grafana.md) |

The agent and the gateway are the same chart in two modes. Two modules keep
`kube.<module>.values` meaning one chart's values, and let a client run the
gateway alone where DaemonSets are unwelcome. Chart versions are on each
module page and in [Compatibility](../reference/compatibility.md).

## What talks to what

```text
applications ──OTLP 4317/4318──▶ otel_gateway ──┐
annotated pods ◀──scrape──────── otel_gateway   │  OTLP over HTTP
Kubernetes API ◀──object state, events── gateway ├─▶ victoria_metrics :8428  /opentelemetry/v1/metrics
                                                 ├─▶ victoria_logs    :9428  /insert/opentelemetry/v1/logs
kubelet, /var/log/pods ◀──── otel_agent ─────────┤
                                                 └─▶ victoria_traces  :10428 /insert/opentelemetry/v1/traces
grafana ──▶ Prometheus, VictoriaLogs and Jaeger datasources, one per backend that is on
```

- **Every signal crosses as OTLP over HTTP.** All three backends ingest it
  natively, which lets the collectors run the `otelcol-k8s` distribution: one
  `otlphttp` exporter, three signal endpoints
  ([SOCLE-28](../decisions/socle.md#socle-28-otlp-everywhere-the-otelcol-k8s-collector-no-remote-write)).
- **The agent exports straight to the backends**, not through the gateway:
  node data does not depend on one Deployment staying up.
- **Pipelines follow the modules that are on.** Each collector adds a
  signal's exporter only when that backend is on, and Grafana a datasource
  under the same test. Every module's `enabled` is always in the inputs, so
  turning `victoria_logs` off removes the logs pipeline from both collectors
  and the datasource from Grafana in one reconciliation. No `dependsOn`
  links the six: a collector retries an absent backend, Grafana starts
  without its datasources answering
  ([SOCLE-29](../decisions/socle.md#socle-29-no-dependson-between-the-monitoring-modules)).
- **Service names are constants.** Each Victoria module sets
  `fullnameOverride`, so the endpoint is, for instance,
  `http://victoria-metrics.victoria-metrics.svc:8428`. A client who
  overrides `fullnameOverride` in `values` breaks the wiring; the plan does
  not refuse it.

### Where each signal comes from

| Signal | Source | Module | Collector preset |
| --- | --- | --- | --- |
| Node, pod and container CPU, memory, filesystem, network | kubelet stats API | `otel_agent` | `kubeletMetrics` |
| Container logs | `/var/log/pods`, read-only | `otel_agent` (`logs = true`) | `logsCollection`, read from the end of each file, no checkpoints |
| Kubernetes metadata on every record | API server | both | `kubernetesAttributes` |
| Object state (deployments, pods, nodes, HPA) | API server | `otel_gateway` | `clusterMetrics` |
| Kubernetes events, as logs | API server | `otel_gateway` | `kubernetesEvents` |
| Prometheus endpoints (Cilium, Flux, ArgoCD, Crossplane, the backends) | pods annotated `prometheus.io/scrape` | `otel_gateway` | `prometheus` receiver |
| Application metrics, logs, traces | OTLP gRPC 4317, HTTP 4318 on `otel-gateway.otel-gateway.svc` | `otel_gateway` | `otlp` receiver |

Host metrics are off: they need the node's root filesystem mounted into the
pod, which GKE Autopilot refuses and the Baseline Pod Security Standard
forbids. Scraping is annotation-based, from the one gateway replica: no
`ServiceMonitor`, no target allocator. Container log checkpoints are off,
because they make the collector write to the node: a restarted agent loses
the lines written while it was down.

## Where the data lives

| Module | Retention | Volume |
| --- | --- | --- |
| `victoria_metrics` | `15d` | `20Gi` |
| `victoria_logs` | `7d` | `20Gi` |
| `victoria_traces` | `7d` | `10Gi` |

Both are attributes (`retention`, `storage_size`), listed in
[Inputs](../reference/inputs.md). The socle sets each backend's retention
explicitly: the charts default it to one month. VictoriaMetrics bounds new
series per hour (`-storage.maxHourlySeries`, 100 000), so a label explosion
drops series with a log line instead of filling the disk, and keeps
Prometheus metric names (`-opentelemetry.usePrometheusNaming`), so a metric
scraped from Cilium or Flux reads with its upstream name.

Each backend runs in its chart's `deployment` mode, which renders a
standalone PVC rather than a StatefulSet's claim template: growing
`storage_size` works where the class allows expansion, shrinking is refused
by the API server.

**The claim uses the cluster's default StorageClass**, with no class named in
the template ([SOCLE-30](../decisions/socle.md#socle-30-a-pvc-by-default-an-emptydir-on-request)).
GKE, AKS and Kapsule ship one. On EKS the bootstrap installs the EBS CSI
driver by default, but nothing marks a StorageClass default, and EKS itself
has marked none since 1.30: a claim stays `Pending` and the backend never
starts. Until a default class exists, an AWS client sets `storage_size = ""`,
which renders no claim at all: the backend keeps its data in an `emptyDir`,
lost when the pod moves. `prod.tfvars.example` does so.

## Reading

Grafana's datasources are provisioned by the socle, each under its backend's
`enabled`: the built-in Prometheus type for VictoriaMetrics (the default), the
`victoriametrics-logs-datasource` plugin for VictoriaLogs, the built-in
Jaeger type for VictoriaTraces. The VictoriaLogs plugin is downloaded from
grafana.com when Grafana starts: a cluster without egress to it gets Grafana
without logs.

Dashboards are ConfigMaps labelled `grafana_dashboard`, picked up by
Grafana's sidecar in every namespace. A module that has something to show
ships its own, under its own toggle: nodes and pods from `otel_agent`,
workloads from `otel_gateway`, on the OpenTelemetry names VictoriaMetrics
stores. No kube-state-metrics, no node-exporter
([SOCLE-31](../decisions/socle.md#socle-31-the-socles-dashboards-on-opentelemetry-names)).

Grafana has no persistence: everything it shows is provisioned. It is a
ClusterIP Service; with `kube.grafana.domain` set and the shared Gateways
present, an `HTTPRoute` attaches it to the `private` Gateway by default
(`kube.grafana.gateway`). Grafana is AGPL-3.0, run unmodified from upstream's
images.

## Per cloud

| Cloud | What differs |
| --- | --- |
| AWS | No default StorageClass: `storage_size = ""` until one exists |
| GCP | The agent DaemonSet is billed per Pod request on Autopilot, on every node. Read-only `/var/log` is allowed there. GKE's free system metrics are unaffected |
| Azure | `/var/log/pods` is a `hostPath`, which the Baseline Pod Security Standard forbids once Deployment Safeguards are applied; `otel_agent.logs = false` is the way out until then. `opentofu/azure` still enables Managed Prometheus and Container Insights |
| Scaleway | Nothing. Cockpit keeps Scaleway's own free data |

## What is not in the stack

- **Alerting**: no vmalert, no Alertmanager, no rules, no Grafana contact
  points.
- **Anything central**: remote-write, federation, multi-cluster Grafana.
- **Backups of the backends**, high availability of any backend (one pod,
  one disk), profiles, SSO on Grafana.

## Outside the cluster: the cloud's own signals

What the cloud measures about the managed services around a cluster
(databases, queues, load balancers, NAT, quotas) and what it bills is
designed to be read from a central observability plane, not by each cluster.
That plane is not built; the per-cloud designs share one shape:

- **Service metrics are read every 300 s** from the cloud's metrics API
  (CloudWatch `GetMetricData` through YACE, Cloud Monitoring through
  `stackdriver_exporter`, Azure `metrics:getBatch`, Scaleway Cockpit's
  `/federate`), never pushed. 300 s keeps the read cost to a few dollars a
  month per estate.
- **Cluster metrics never take that path.** They stay in the cluster's own
  stack; through a cloud API they cost one to two orders of magnitude more.
- **Alerting is the socle's**: one Alertmanager for four clouds, never the
  cloud's alert policies.
- **Cost data lands in the client's own account** (CUR on AWS, the detailed
  billing export on GCP, Cost Management exports on Azure, the Consumption
  API on Scaleway), so a figure is one the client can recompute.
- **Quota usage** is in the standard perimeter on every cloud.

Each cloud's figures and choices are in its decision file:
[AWS](../decisions/aws.md), [GCP](../decisions/gcp.md),
[Azure](../decisions/azure.md), [Scaleway](../decisions/scaleway.md).
