---
title: otel-agent
description: "Node-level OpenTelemetry collector: kubelet metrics and container logs for every node, pod and container."
category: observability
---

The OpenTelemetry Collector as a DaemonSet, one pod per node, for what only a
node can see: the kubelet's metrics for every node, pod and container, and
every container's log. It writes them to
[victoria-metrics](victoria-metrics.md) and [victoria-logs](victoria-logs.md)
and ships the nodes and pods dashboard to [grafana](grafana.md). On by
default. How it fits the rest of the stack:
[Observability](../architecture/observability.md).

## Getting started

On by default, with container logs while victoria-logs is on. What you set
first is whether it reads logs, and the taints it tolerates, so an agent runs
on every node:

```hcl title="terraform.tfvars" kube-start="otel_agent"
kube = {
  otel_agent = {
    logs = true
    values = {
      tolerations = [{ operator = "Exists" }]
    }
  }
}
```

After apply, `kubectl -n otel-agent get daemonset otel-agent-agent` shows as
many pods ready as there are nodes.

## What it installs

| | |
| --- | --- |
| Chart | `opentelemetry-collector` `0.173.1` (collector 0.160.0) from `oci://ghcr.io/open-telemetry/opentelemetry-helm-charts`, in `daemonset` mode |
| Namespace | `otel-agent` |
| Objects | the namespace, the chart source, the socle's and your values ConfigMaps, one `HelmRelease` (DaemonSet `otel-agent-agent`), and a Flux `Kustomization` applying the dashboard ConfigMap |

The collector is the `otelcol-k8s` distribution, upstream's Kubernetes build.

**Metrics.** `kubeletstats` every 20 s, from this node's kubelet over the node
IP with the ServiceAccount token: node, pod and container CPU, memory,
filesystem and network. Plus the collector's own telemetry. `k8s_attributes`
puts the workload, namespace and labels on every point, watching this node's
pods only. Exported over OTLP/HTTP to
`victoria-metrics.victoria-metrics.svc:8428/opentelemetry/v1/metrics` while
`victoria_metrics` is on; to nowhere (`nop`) while it is off.

**Logs.** While `victoria_logs` is on and `logs` is `true` (both by default):
`file_log` on `/var/log/pods/*/*/*.log`, through a read-only `hostPath`,
from the end of each existing file and from the first line of each new one,
the agent's own logs excluded, enriched by `k8s_attributes`, exported to
`victoria-logs.victoria-logs.svc:9428/insert/opentelemetry/v1/logs`. To read
those files the agent runs **as root**, with every capability dropped, no
privilege escalation and a read-only root filesystem
([OTEL-AGENT-03](../decisions/otel-agent.md#otel-agent-03-root-to-read-container-logs-with-nothing-else)).
Otherwise it runs as the image's non-root user, with no `hostPath`. The
agent keeps no checkpoints: a restarted agent starts again from the end of
each file, and the lines written while it was down are lost.

**Receives nothing.** No receiver port and no `hostPort` on the node: your
applications send OTLP to [otel-gateway](otel-gateway.md).

**Resources.** Requests 50m CPU and 128Mi memory, a 512Mi memory limit
([OTEL-AGENT-01](../decisions/otel-agent.md#otel-agent-01-a-memory-limit-so-gomemlimit-applies)).

**The nodes and pods dashboard**, *Kubernetes / Nodes and pods*: CPU, memory
working set, filesystem and network by node; CPU and memory by namespace, the
top 10 pods by each; network by namespace. Variables: the data source, `node`,
`namespace`. Grafana picks it up by its `grafana_dashboard` label.

## What you can set

Under `kube.otel_agent` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on. Off removes the release, the namespace and the dashboard. |
| `logs` | `true` | Container logs to victoria-logs while it is on. `false` keeps the agent to metrics: no `hostPath`, no root. |
| `values` | `{}` | Any `opentelemetry-collector` chart value; yours win over the socle's. |
| `values_secret` | `""` | A Secret you create in `otel-agent` with a `values.yaml` key, merged last. |

**Lists are replaced, not merged.** To add an exporter, write the pipeline's
whole `exporters` list, the socle's `otlp_http/victoria-metrics` included, or
the socle's is dropped:

```hcl
kube = {
  otel_agent = {
    values = {
      extraEnvs = [{ name = "SAAS_TOKEN", valueFrom = { secretKeyRef = { name = "saas", key = "token" } } }]
      config = {
        exporters = { "otlp_http/saas" = { endpoint = "https://otlp.saas.example", headers = { Authorization = "Bearer $${env:SAAS_TOKEN}" } } }
        service   = { pipelines = { metrics = { exporters = ["otlp_http/victoria-metrics", "otlp_http/saas"] } } }
      }
    }
  }
}
```

`$${…}` is how HCL writes a literal `${…}`.

Refused at plan, because `values` lands in the OpenTofu state and in a
ConfigMap: a literal `token`, `client_auth.password`, `htpasswd.inline` or
`client_secret` in a `config.extensions` authenticator; a literal
`Authorization`, `Proxy-Authorization`, `X-API-Key`, `API-Key` or
`X-Auth-Token` header in a `config.exporters` entry; an `extraEnvs` entry with
a literal value named like a credential; a `Secret` in `extraManifests`. A
value written as `${env:NAME}`, with `NAME` set by `extraEnvs` `valueFrom` a
Secret, is accepted: nothing secret reaches the state.

Host metrics (the chart's `hostMetrics` preset) are off: they mount the
node's root filesystem, which GKE Autopilot refuses. You can turn them on
through `values` where your cloud allows it.

### Every setting

Every attribute, at its default, and how chart values and secrets go in:

```hcl title="terraform.tfvars" kube-full="otel_agent"
kube = {
  otel_agent = {
    enabled = true # on by default; off removes the release and the dashboard
    logs    = true # container logs to victoria-logs; false: metrics only, no hostPath, no root

    # Any value of the opentelemetry-collector chart 0.173.1; yours win over the socle's.
    values = {
      tolerations = [{ operator = "Exists" }]
      resources   = { limits = { memory = "1Gi" } }
    }

    # A Secret you create in otel-agent, whose values.yaml key holds chart values
    # that must not reach the OpenTofu state, an exporter's headers say; merged last.
    values_secret = "otel-agent-values"
  }
}
```

## Per cloud

The same template on aws, gcp, azure and scaleway. Around it:

| Cloud | What to know |
| --- | --- |
| aws | Kubelet serving certificates are self-signed, hence `insecure_skip_verify` on the kubelet call ([OTEL-AGENT-02](../decisions/otel-agent.md#otel-agent-02-the-kubelet-call-skips-certificate-verification)). |
| gcp | GKE Autopilot bills a DaemonSet by its pod requests on every node: 50m and 128Mi is the per-node price. A read-only `hostPath` on `/var/log` is allowed there. |
| azure | The read-only `hostPath` on `/var/log/pods` is what the Baseline Pod Security Standard forbids. AKS Deployment Safeguards are not applied by the foundations today; if you apply them, set `logs = false`. |
| scaleway | Nothing. |

## Cloud access

None.

## Ordering

No `dependsOn`. The exporters follow the other modules' `enabled`: turning
`victoria_metrics` or `victoria_logs` off removes the matching exporter and
pipeline in the same reconciliation, and the values ConfigMaps carry
`reconcile.fluxcd.io/watch: Enabled`, so the release is upgraded at once
rather than at its 10-minute interval. A backend that is on but not yet
running is retried.

## Upgrade notes

- The chart lists Helm 4.0 as a prerequisite. Flux v2.9.5's helm-controller
  installs, upgrades and uninstalls it.
- The socle's configuration uses the current component names (`otlp_http`,
  `k8s_attributes`). This chart release rewrites the deprecated ones in your
  `values` with a warning; a later one will stop, so write the new names.
- The dashboard reads the metric names VictoriaMetrics stores. A metric
  renamed upstream fails the module's tests before a socle release.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-09-29 | floci, k3s, one node | the agent at idle, metrics only: 3–5m CPU, 33Mi; DaemonSet rolled out 1 s after victoria-metrics; `k8s_pod_cpu_usage` queryable 2 s after the rollout |
| 2026-09-30 | floci, k3s, one node | the agent collecting logs too: 10–12m CPU, 52Mi |

The per-node cost on a cluster of many nodes, and the call to EKS's own
kubelet, have not been measured.

Its decisions: [otel-agent decisions](../decisions/otel-agent.md).
