---
title: Observability
description: "The cross-cloud view: vmagent scrapes, OpenTelemetry carries OTLP and logs, Victoria stores, Grafana reads, inside each cluster; the cloud's own signals are read from outside."
sidebar:
  order: 4
---

Every cluster carries its own monitoring stack: vmagent scrapes the cluster,
OpenTelemetry carries what applications push and the containers' logs, the
Victoria family stores, Grafana reads, vmalert and Alertmanager alert. Same
templates on all four clouds, no remote-write, no federation, and no cloud
access: every backend stores on a volume.

## Three modules

| Module | Runs as | Default |
| --- | --- | --- |
| [`monitoring`](../catalog/monitoring.md) | the victoria-metrics-k8s-stack chart, one release: the operator, VictoriaMetrics, VictoriaLogs, VictoriaTraces, vmagent, kube-state-metrics, node-exporter, Grafana, vmalert and Alertmanager | on; traces **off** (pre-GA), alerting **off** (it needs where alerts go) |
| [`otel_gateway`](../catalog/otel-gateway.md) | OpenTelemetry Collector, 1 replica | on |
| [`otel_agent`](../catalog/otel-agent.md) | OpenTelemetry Collector, DaemonSet | on, while monitoring's logs are |

## What talks to what

```text
kubelets, cAdvisor, kube-state-metrics,
node-exporter, annotated pods ◀──scrape── vmagent ──▶ VictoriaMetrics :8428
applications ──OTLP 4317/4318──▶ otel_gateway ──┐
Kubernetes API ◀──events────────── otel_gateway │  OTLP over HTTP
                                                ├─▶ VictoriaMetrics :8428  /opentelemetry/v1/metrics
/var/log/pods ◀──── otel_agent ─────────────────┼─▶ VictoriaLogs    :9428  /insert/opentelemetry/v1/logs
                                                └─▶ VictoriaTraces  :10428 /insert/opentelemetry/v1/traces
Grafana ──▶ VictoriaMetrics, VictoriaLogs, VictoriaTraces and Alertmanager datasources
vmalert ──every VMRule──▶ VictoriaMetrics; firing ──▶ Alertmanager ──▶ your receivers
```

- **Metrics are scraped in one place**, vmagent, with the `job` labels the
  upstream rules and dashboards select on. The collectors scrape nothing.
- **OTLP over HTTP** for everything applications push, which all three
  backends ingest. The agent exports straight to VictoriaLogs.
- **Pipelines follow the parts that are on**: turning a backend off removes
  its pipelines and its datasource in one reconciliation; with monitoring
  off, the gateway's metrics end in `nop`.
- **Do not override `fullnameOverride`** in `values`: the endpoints rely on
  it, and the plan does not refuse it.

<details>
<summary>Under the hood</summary>

| Signal | Source | Read by |
| --- | --- | --- |
| Object state | kube-state-metrics | vmagent |
| Nodes | node-exporter | vmagent |
| Pods and containers' resources, volumes' fill | the kubelets and their cAdvisor | vmagent |
| Prometheus endpoints, the collectors' and Flux's included | pods annotated `prometheus.io/scrape` | vmagent |
| Container logs | `/var/log/pods`, read-only | `otel_agent`, no checkpoints |
| Kubernetes events, as logs | API server | `otel_gateway` |
| Application OTLP | gRPC 4317, HTTP 4318 on `otel-gateway.otel-gateway.svc` | `otel_gateway`, with `k8s_attributes` |

The control plane is the cloud's and is not scraped. The collectors run the
`otelcol-k8s` distribution. Without log checkpoints, a restarted agent loses
the lines written while it was down.

</details>

## Where the data lives

| Part | Retention | Volume |
| --- | --- | --- |
| `monitoring.metrics` | `15d` | `20Gi` |
| `monitoring.logs` | `7d` | `20Gi` |
| `monitoring.traces` | `7d` | `10Gi` |

Both are attributes, `retention` and `storage_size`
([Inputs](../reference/inputs.md)). The claims use the cluster's default
StorageClass.

- **A volume can grow** where the class allows expansion; shrinking is
  refused.

<details>
<summary>Under the hood</summary>

The operator creates each backend's Deployment and claim. VictoriaMetrics
caps new series per hour (`-storage.maxHourlySeries`, 100 000) and keeps
Prometheus metric names for OTLP (`-opentelemetry.usePrometheusNaming`).

</details>

## Reading

Grafana gets one datasource per backend that is on: Prometheus type for
VictoriaMetrics, the `victoriametrics-logs-datasource` plugin, Jaeger type
for VictoriaTraces, and Alertmanager with alerting on. The dashboards are the
stack's, kube-prometheus' and VictoriaMetrics', and any ConfigMap labelled
`grafana_dashboard`.

- **No egress to grafana.com, no logs**: the VictoriaLogs plugin downloads
  at start. No egress to raw.githubusercontent.com, no rules and no
  dashboards: the chart's sync job downloads them.
- **No persistence**: everything Grafana shows is provisioned.
- **A route needs `kube.monitoring.grafana.domain`** and the shared
  Gateways; `private` by default.
- **Grafana is AGPL-3.0**, run unmodified from upstream's images.

## Alerting

kube-prometheus-stack's rules and VictoriaMetrics', with the socle's for Flux
and the collectors ([Alert rules](../reference/alert-rules.md)); a client's
own `VMRule`s, in any namespace, load beside them.

## Per cloud

| Cloud | What differs |
| --- | --- |
| AWS | the bootstrap marks `gp3` (EBS, encrypted) default |
| GCP | the agent DaemonSet is billed per Pod request on Autopilot |
| Azure | `/var/log/pods` is a `hostPath`, forbidden once Deployment Safeguards apply: `otel_agent.enabled = false` until then. `opentofu/azure` still enables Managed Prometheus and Container Insights |
| Scaleway | nothing; Cockpit keeps Scaleway's own data |

## What is not in the stack

Anything central (remote-write, federation,
multi-cluster Grafana, one Alertmanager across clusters), backups and high availability of the backends, profiles, SSO on
Grafana.

## Outside the cluster: the cloud's own signals

The cloud's metrics on managed services, and its billing, are designed to be
read by a central plane that is not built yet: service metrics pulled every
300 s, cluster metrics never through the cloud API, one Alertmanager for all
clouds, cost data in your own account.
