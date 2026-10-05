---
title: victoria-logs
description: "Logs storage: VictoriaLogs single-node, 7 days on a volume, LogsQL in Grafana."
category: observability
---

VictoriaLogs single-node, where your containers' logs, Kubernetes events and
your applications' OTLP logs are stored, read in [grafana](grafana.md) in
LogsQL. On by default. How it fits the rest of the stack:
[Observability](../architecture/observability.md).

## What it installs

| | |
| --- | --- |
| Chart | `victoria-logs-single` `0.13.9` (VictoriaLogs v1.52.0) from `oci://ghcr.io/victoriametrics/helm-charts` |
| Namespace | `victoria-logs` |
| Objects | the namespace, the chart source, the socle's and your values ConfigMaps, one `HelmRelease`: a Deployment with strategy `Recreate`, a standalone `PersistentVolumeClaim`, a headless Service |

**Address:** `victoria-logs.victoria-logs.svc:9428`, in-cluster only: no
route, no authentication. OTLP comes in at `/insert/opentelemetry/v1/logs`.

The socle's values: `server.mode: deployment`, as
[victoria-metrics](victoria-metrics.md#what-it-installs) and for its reason;
`retentionPeriod` from `retention` (the chart's own default is a month);
persistence from `storage_size`, on the cluster's default StorageClass; the
`prometheus.io/*` annotations on port 9428; requests 50m CPU and 128Mi
memory; `fullnameOverride: victoria-logs`. The chart's Vector subchart stays
off.

**What turning it on adds to the other modules**, each under a test on
`victoria_logs.enabled`, and removed in the same reconciliation when you turn
it off:

| Module | What it gains |
| --- | --- |
| [otel-agent](otel-agent.md) | every container's log from `/var/log/pods`, while `kube.otel_agent.logs` is `true`: a read-only `hostPath`, and the agent running as root with every capability dropped ([OTEL-AGENT-03](../decisions/otel-agent.md#otel-agent-03-root-to-read-container-logs-with-nothing-else)) |
| [otel-gateway](otel-gateway.md) | Kubernetes events, and a logs pipeline for your OTLP logs on `:4317` and `:4318` |
| [grafana](grafana.md) | a read-only `VictoriaLogs` datasource, uid `victoria-logs`, and its plugin `victoriametrics-logs-datasource` 0.32.0, downloaded from grafana.com when Grafana starts |

**Reading logs.** In Grafana, Explore, then VictoriaLogs. The OpenTelemetry
resource attributes are fields: `k8s.namespace.name:=argocd`,
`k8s.pod.name:~"flux"`. A container's line has `_msg`, `_time`, `_stream`
and the `k8s.*` fields of its pod and container. Kubernetes events are
`k8s.resource.name:=events`; they are stored as their whole watch object, so
their message is `object.note` and they have **no `_msg`**: a phrase search
does not find them, and Grafana shows "missing _msg field".

## What you can set

Under `kube.victoria_logs` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on. Off removes the release and the namespace, **the claim and its logs included**, and the logs path from both collectors and Grafana. |
| `retention` | `"7d"` | How long logs are kept: a whole number of hours, days, weeks or years, at least a day. |
| `storage_size` | `"20Gi"` | The claim's size, in `Gi` or `Ti`. `""` renders no claim: the logs live in an `emptyDir` and go when the pod moves. |
| `values` | `{}` | Any `victoria-logs-single` chart value; yours win over the socle's. |
| `values_secret` | `""` | A Secret you create in `victoria-logs` with a `values.yaml` key, merged last. |

`kube.otel_agent.logs = false` keeps container logs out while events and
OTLP logs still arrive.

Changing `storage_size` follows the rules of
[victoria-metrics](victoria-metrics.md#what-you-can-set): growing where the
class allows it, never shrinking, `""` replaces the volume. Write numeric
flags in `values` as strings.

Refused at plan, as for victoria-metrics: an auth flag in
`server.extraArgs`, a `server.env` entry with a literal value named like a
credential, a `Secret` in `extraObjects`, a `retention` under a day, a
`storage_size` not in `Gi` or `Ti`.

## Per cloud

The template is the same everywhere.

| Cloud | What to know |
| --- | --- |
| aws | No default StorageClass: the claim stays `Pending` until you set `storage_size = ""` or create a default class, as for [victoria-metrics](victoria-metrics.md#per-cloud). |
| azure | Container logs need otel-agent's read-only `hostPath`, which the Baseline Pod Security Standard forbids. If you apply AKS Deployment Safeguards, set `kube.otel_agent.logs = false`: events and OTLP logs still arrive. |
| gcp, scaleway | Nothing. |

Grafana downloads the logs plugin from grafana.com when it starts: a cluster
with no egress to grafana.com gets Grafana without its logs datasource.

## Cloud access

None: the logs are on the claim.

## Ordering

None. The collectors export here only while the module is on, and retry
while it starts.

## Upgrade notes

- With strategy `Recreate`, an upgrade stops the pod before the new one
  starts: logs sent in between are retried by the collectors, within their
  queue.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-09-30 | floci, k3s, one node | VictoriaLogs at 2m CPU and 32–47Mi; a container's line found 6 s after its pod was created; Kubernetes events and an OTLP log posted from podinfo stored; Grafana's datasource health OK, plugin signature valid |

Its decisions: [victoria-logs decisions](../decisions/victoria-logs.md).
