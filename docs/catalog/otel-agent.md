---
title: otel-agent
description: "Node-level OpenTelemetry collector: every container's log, with its pod's metadata, to VictoriaLogs."
category: observability
---

The OpenTelemetry Collector as a DaemonSet, one pod per node, for what only a
node can read: every container's log, with its pod's workload, labels and
namespace, written to [monitoring](monitoring.md)'s VictoriaLogs. **On by
default**, on every cloud, and running while `monitoring.logs` is on. The
nodes' and pods' metrics are monitoring's vmagent's.

## Getting started

It is already on. Tolerate your nodes' taints so an agent runs on each:

```hcl kube-start="otel_agent"
kube = {
  otel_agent = {
    values = {
      tolerations = [{ operator = "Exists" }]
    }
  }
}
```

Then `kubectl -n otel-agent get daemonset otel-agent-agent` shows as many
pods ready as there are nodes.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on or off. It runs only while `monitoring` and its `logs` are on. |
| `values` | `{}` | Any [`opentelemetry-collector` chart](https://artifacthub.io/packages/helm/opentelemetry-helm/opentelemetry-collector) value; yours win. |
| `values_secret` | `""` | A Secret in `otel-agent` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl kube-full="otel_agent"
kube = {
  otel_agent = {
    enabled = true # on by default; runs while monitoring's logs are on

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

## Good to know

- **Reading logs runs the agent as root**, every capability dropped, with a
  read-only `hostPath` on `/var/log/pods`. Where that is forbidden (AKS
  Deployment Safeguards, the Baseline Pod Security Standard), turn it off:
  `enabled = false`.
- **Lines written while an agent restarts are lost**: it keeps no
  checkpoints and starts again from the end of each file.
- **Lists in `values` are replaced, not merged**: to add an exporter, write
  the pipeline's whole `exporters` list, `otlp_http/victoria-logs`
  included.
- **`tofu plan` refuses** literal credentials in `values` (authenticators,
  exporter headers, `extraEnvs`, a `Secret` in `extraManifests`). Write
  `${env:NAME}` (`$${env:NAME}` in HCL), with `NAME` set from a Secret by
  `extraEnvs` `valueFrom`.
- **On GKE Autopilot each agent is billed** by its requests, 50m CPU,
  128Mi and 64Mi of disk, on every node. It runs there under the
  `socle-node-agent` PriorityClass, so on a full node it preempts an
  ordinary pod rather than stay `Pending`, and mounts `/var/log/pods` alone,
  read-only: the only `hostPath` Autopilot admits.
- **Its health is watched** by otel-gateway's collector rules, once
  monitoring's alerting is on ([every rule](../reference/alert-rules.md)).
- **Upgrades**: write the current component names (`otlp_http`,
  `k8s_attributes`) in `values`; a later chart stops rewriting the old ones.

<details>
<summary>Under the hood</summary>

**Installed**: chart `opentelemetry-collector` 0.173.1 (collector 0.160.0,
`otelcol-k8s`) from `oci://ghcr.io/open-telemetry/opentelemetry-helm-charts`,
in `daemonset` mode, in the `otel-agent` namespace. It receives nothing: no
port, no `hostPort`.

**What the socle sets**: `file_log` on `/var/log/pods` and `k8s_attributes`,
exported to `vlsingle-monitoring.monitoring.svc:9428`; no metrics pipeline;
its own telemetry on port 8888, annotated `prometheus.io/scrape` for
monitoring's vmagent. Requests 50m CPU, 128Mi and 64Mi of ephemeral
storage, a 512Mi memory limit. On gcp, from
`oci/clusters/gcp/otel-agent/patch.yaml`: `PriorityClass/socle-node-agent`
(1000000, not the default) and the chart's `logsCollection` preset replaced
by its own `file_log` receiver and one read-only mount
([OTEL-AGENT-07](../decisions/otel-agent.md#otel-agent-07-on-gcp-the-logs-without-the-charts-preset-and-a-priority-for-the-agent)).

**Cloud access**: none.

**Measured** on floci k3s, 2026-09-30: one agent collecting metrics and
logs at 10–12m CPU and 52Mi; a container's line in VictoriaLogs 6 s after
its pod was created.

</details>
