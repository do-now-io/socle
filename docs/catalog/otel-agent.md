---
title: otel-agent
description: "Node-level OpenTelemetry collector: kubelet metrics and container logs for every node, pod and container."
category: observability
---

The OpenTelemetry Collector as a DaemonSet, one pod per node, for what only a
node can see: the kubelet's metrics for every node, pod and container, and
every container's log, written to [victoria-metrics](victoria-metrics.md) and
[victoria-logs](victoria-logs.md). **On by default**, on every cloud.

## Getting started

It is already on. Tolerate your nodes' taints so an agent runs on each:

```hcl kube-start="otel_agent"
kube = {
  otel_agent = {
    logs = true
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
| `enabled` | `true` | Turns the module on or off, its dashboard with it. |
| `logs` | `true` | Container logs to victoria-logs while it is on. `false`: metrics only, no `hostPath`, no root. |
| `values` | `{}` | Any [`opentelemetry-collector` chart](https://artifacthub.io/packages/helm/opentelemetry-helm/opentelemetry-collector) value; yours win. |
| `values_secret` | `""` | A Secret in `otel-agent` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl kube-full="otel_agent"
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

## Good to know

- **Reading logs runs the agent as root**, every capability dropped, with a
  read-only `hostPath` on `/var/log/pods`. With AKS Deployment Safeguards,
  which forbid that, set `logs = false`.
- **Lines written while an agent restarts are lost**: it keeps no
  checkpoints and starts again from the end of each file.
- **Lists in `values` are replaced, not merged**: to add an exporter, write
  the pipeline's whole `exporters` list, `otlp_http/victoria-metrics`
  included.
- **`tofu plan` refuses** literal credentials in `values` (authenticators,
  exporter headers, `extraEnvs`, a `Secret` in `extraManifests`). Write
  `${env:NAME}` (`$${env:NAME}` in HCL), with `NAME` set from a Secret by
  `extraEnvs` `valueFrom`.
- **On GKE Autopilot each agent is billed** by its requests, 50m CPU and
  128Mi, on every node.
- **Its alert rules ship with it**: a node out of memory, CPU or disk, a
  PersistentVolumeClaim nearly full or filling, and the agent's own health
  ([every rule](../reference/alert-rules.md)). They fire once
  [alerting](alerting.md) is on. The CPU and claim rules also read
  [kube_state_metrics](kube-state-metrics.md): without it they return
  nothing.
- **Upgrades**: write the current component names (`otlp_http`,
  `k8s_attributes`) in `values`; a later chart stops rewriting the old ones.

<details>
<summary>Under the hood</summary>

**Installed**: chart `opentelemetry-collector` 0.173.1 (collector 0.160.0,
`otelcol-k8s`) from `oci://ghcr.io/open-telemetry/opentelemetry-helm-charts`,
in `daemonset` mode, in the `otel-agent` namespace, with the
*Kubernetes / Nodes and pods* dashboard for Grafana. It receives nothing: no
port, no `hostPort`.

**What the socle sets**: `kubeletstats` every 20 s over the node IP
(`insecure_skip_verify`: kubelet certificates are self-signed), with the
`volume` group but neither the ServiceAccount token volumes nor the used
inodes, which no rule reads; `file_log` on
`/var/log/pods` while logs are on, `k8s_attributes` on both; each exporter
follows its backend's `enabled`. Host metrics are off. Requests 50m CPU and
128Mi, a 512Mi memory limit.

**Cloud access**: none.

**Measured** on floci k3s, 2026-09-30: one agent collecting metrics and
logs at 10–12m CPU and 52Mi.

</details>
