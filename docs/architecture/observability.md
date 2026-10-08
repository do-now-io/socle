---
title: Observability
description: "The cross-cloud view: OpenTelemetry collects, Victoria stores, Grafana reads, inside each cluster; the cloud's own signals are read from outside."
sidebar:
  order: 4
---

Every cluster carries its own monitoring stack: OpenTelemetry collects,
the Victoria family stores, Grafana reads. Same templates on all four clouds,
no remote-write, no federation,
and no cloud access: every backend stores on a volume.

## Seven modules

One module per chart release:

| Module | Runs as | Default |
| --- | --- | --- |
| [`otel_agent`](../catalog/otel-agent.md) | OpenTelemetry Collector, DaemonSet | on |
| [`otel_gateway`](../catalog/otel-gateway.md) | OpenTelemetry Collector, 1 replica | on |
| [`victoria_metrics`](../catalog/victoria-metrics.md) | 1 pod and a PVC | on |
| [`victoria_logs`](../catalog/victoria-logs.md) | 1 pod and a PVC | on |
| [`victoria_traces`](../catalog/victoria-traces.md) | 1 pod and a PVC | **off**: pre-GA, an upgrade may drop stored traces |
| [`grafana`](../catalog/grafana.md) | 1 replica | on |
| [`alerting`](../catalog/alerting.md) | vmalert and Alertmanager, 1 replica each | **off**: it needs where alerts go |

## What talks to what

```text
applications ──OTLP 4317/4318──▶ otel_gateway ──┐
annotated pods ◀──scrape──────── otel_gateway   │  OTLP over HTTP
Kubernetes API ◀──object state, events── gateway ├─▶ victoria_metrics :8428  /opentelemetry/v1/metrics
                                                 ├─▶ victoria_logs    :9428  /insert/opentelemetry/v1/logs
kubelet, /var/log/pods ◀──── otel_agent ─────────┤
                                                 └─▶ victoria_traces  :10428 /insert/opentelemetry/v1/traces
grafana ──▶ Prometheus, VictoriaLogs and Jaeger datasources, one per backend that is on
alerting: vmalert ──rules──▶ victoria_metrics;  firing ──▶ Alertmanager ──▶ your receivers
```

- **Every signal is OTLP over HTTP**, which all three backends ingest.
- **The agent exports straight to the backends**, not through the gateway.
- **Pipelines follow the modules that are on**: turning a backend off removes
  its pipelines and its datasource in one reconciliation. No `dependsOn`
  links the six.
- **Do not override `fullnameOverride`** in `values`: the endpoints rely on
  it, and the plan does not refuse it.

<details>
<summary>Under the hood</summary>

| Signal | Source | Module | Collector preset |
| --- | --- | --- | --- |
| Node, pod, container resources | kubelet stats API | `otel_agent` | `kubeletMetrics` |
| Container logs | `/var/log/pods`, read-only | `otel_agent` (`logs = true`) | `logsCollection`, no checkpoints |
| Kubernetes metadata | API server | both | `kubernetesAttributes` |
| Object state | API server | `otel_gateway` | `clusterMetrics` |
| Kubernetes events, as logs | API server | `otel_gateway` | `kubernetesEvents` |
| Prometheus endpoints | pods annotated `prometheus.io/scrape` | `otel_gateway` | `prometheus` receiver |
| Application OTLP | gRPC 4317, HTTP 4318 on `otel-gateway.otel-gateway.svc` | `otel_gateway` | `otlp` receiver |

The collectors run the `otelcol-k8s` distribution. Host metrics are off
(they need the node's root filesystem, which Autopilot and the Baseline Pod
Security Standard refuse). Scraping is by annotation, with no
`ServiceMonitor`. Without log checkpoints, a restarted agent loses the lines
written while it was down.

</details>

## Where the data lives

| Module | Retention | Volume |
| --- | --- | --- |
| `victoria_metrics` | `15d` | `20Gi` |
| `victoria_logs` | `7d` | `20Gi` |
| `victoria_traces` | `7d` | `10Gi` |

Both are attributes, `retention` and `storage_size`
([Inputs](../reference/inputs.md)). The claim uses the cluster's default
StorageClass.

- **On EKS, set `storage_size = ""`** until a StorageClass is marked
  default: EKS marks none, and the claim would stay `Pending`. The backend
  then keeps its data in an `emptyDir`, lost when the pod moves.
- **A volume can grow** where the class allows expansion; shrinking is
  refused.

<details>
<summary>Under the hood</summary>

The charts default retention to a month, so the socle sets it. Each backend
runs in `deployment` mode, a standalone PVC rather than a claim template.
VictoriaMetrics caps new series per hour (`-storage.maxHourlySeries`,
100 000) and keeps Prometheus metric names
(`-opentelemetry.usePrometheusNaming`).

</details>

## Reading

Grafana gets one datasource per backend that is on: Prometheus type for
VictoriaMetrics, the `victoriametrics-logs-datasource` plugin, Jaeger type
for VictoriaTraces. Dashboards are ConfigMaps labelled `grafana_dashboard`,
shipped by the module they describe, on OpenTelemetry names.

- **No egress to grafana.com, no logs**: the VictoriaLogs plugin downloads
  at start.
- **No persistence**: everything Grafana shows is provisioned.
- **A route needs `kube.grafana.domain`** and the shared Gateways;
  `private` by default.
- **Grafana is AGPL-3.0**, run unmodified from upstream's images.

## Per cloud

| Cloud | What differs |
| --- | --- |
| AWS | no default StorageClass: `storage_size = ""` until one exists |
| GCP | the agent DaemonSet is billed per Pod request on Autopilot |
| Azure | `/var/log/pods` is a `hostPath`, forbidden once Deployment Safeguards apply: `otel_agent.logs = false` until then. `opentofu/azure` still enables Managed Prometheus and Container Insights |
| Scaleway | nothing; Cockpit keeps Scaleway's own data |

## What is not in the stack

Your own alert rules (#82), anything central (remote-write, federation,
multi-cluster Grafana, one Alertmanager across clusters), backups and high availability of the backends, profiles, SSO on
Grafana.

## Outside the cluster: the cloud's own signals

The cloud's metrics on managed services, and its billing, are designed to be
read by a central plane that is not built yet: service metrics pulled every
300 s, cluster metrics never through the cloud API, one Alertmanager for all
clouds, cost data in your own account.
