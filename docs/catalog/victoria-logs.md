# Catalog module `victoria_logs` — the logs storage

The fifth module of the monitoring stack (#43, design in
[`docs/monitoring.md`](../monitoring.md)): VictoriaLogs single-node, the second
signal. It arrives after the metrics path, so it brings its wiring into the
modules that already exist, each under a test on
`inputs.modules.victoria_logs.enabled`:

- container logs from [`otel_agent`](otel-agent.md);
- Kubernetes events and the applications' OTLP logs from
  [`otel_gateway`](otel-gateway.md);
- a datasource and its plugin in [`grafana`](grafana.md).

Turning the module off removes all of that in the same reconciliation. The
module itself follows [`victoria_metrics`](victoria-metrics.md) line for line.

| Question | Position |
| --- | --- |
| What | The official `victoria-logs-single` chart, `oci://ghcr.io/victoriametrics/helm-charts/victoria-logs-single:0.13.9` (VictoriaLogs v1.52.0), one `HelmRelease` in namespace `victoria-logs` |
| Where | Every cloud, the same template, no cloud patch |
| Default | **On** |
| Shape | One pod, `server.mode: deployment`, strategy `Recreate`, a standalone PVC — victoria_metrics' reason: a `volumeClaimTemplate` cannot be resized by Helm |
| Storage | 20Gi on the default StorageClass; `storage_size = ""` for an `emptyDir`. **A socle EKS has no StorageClass today**, as for victoria_metrics |
| Retention | 7 days. The chart defaults to one month, over the binary's own 7 |
| Ingest | OTLP over HTTP at `/insert/opentelemetry/v1/logs` |
| Exposure | Headless `ClusterIP`, `victoria-logs.victoria-logs.svc:9428`, no auth, in-cluster only |
| Cloud access | None |
| Client surface | `retention`, `storage_size`, `values`, `values_secret`; `otel_agent` gains `logs` |

## What is installed

The victoria_metrics shape, names changed: `Namespace/victoria-logs`,
`OCIRepository/victoria-logs-chart`, `ConfigMap/victoria-logs-socle-values`
and `ConfigMap/victoria-logs-client-values` (both labelled
`reconcile.fluxcd.io/watch`), and `HelmRelease/victoria-logs` with no
`spec.values`. The socle's values are:

- `server.fullnameOverride: victoria-logs` and `server.mode: deployment`;
- `server.retentionPeriod` from `retention`;
- persistence from `storage_size`;
- the `prometheus.io/*` pod annotations, so the gateway scrapes it;
- requests of 50m / 128Mi.

The chart's optional Vector subchart stays off: OpenTelemetry is the
collection layer.

## What it brings to the other modules

**`otel_agent`**, under `victoria_logs.enabled` **and** `otel_agent.logs`:

- the `logsCollection` preset: `file_log` on `/var/log/pods/*/*/*.log`,
  from the end of each existing file and from the first line of each new
  one, the agent's own logs excluded, **no checkpoints**;
- the chart's read-only `hostPath` mounts of `/var/log/pods` and
  `/var/lib/docker/containers` — on GCP, `/var/log/pods` alone, since GKE
  Autopilot admits no `hostPath` outside `/var/log`: the preset is off there
  and the template carries its receiver and its one mount
  ([otel-agent.md](otel-agent.md#per-cloud));
- an exporter `otlp_http/victoria-logs` and a `logs` pipeline, `file_log` →
  `k8s_attributes` → `memory_limiter` → `batch` → VictoriaLogs;
- **`runAsUser: 0`, with every capability dropped**, no privilege
  escalation and a read-only root filesystem. containerd writes each
  container's log as root with mode 0640. Kubernetes gives a non-root
  container no effective capability, so only root can read those files. As
  their owner it reads them without bypassing any permission. Without logs
  the agent keeps the image's non-root user and has no `hostPath`: the e2e
  checks both ways.

**`otel_gateway`**, under `victoria_logs.enabled`:

- the `kubernetesEvents` preset: `k8sobjects` watching `events.k8s.io`,
  deleted events excluded, with its RBAC. There is one replica, so each event
  is reported once;
- a `logs` pipeline taking the applications' OTLP logs on `:4317/:4318` and
  the events, → VictoriaLogs.

**`grafana`**, under `victoria_logs.enabled`:

- a read-only datasource `VictoriaLogs`, uid `victoria-logs`, type
  `victoriametrics-logs-datasource`;
- the plugin, **pinned at 0.32.0**, signed by Grafana (commercial signature),
  downloaded from grafana.com when the pod starts
  (`GF_PLUGINS_PREINSTALL_SYNC`). A cluster with no egress to grafana.com gets
  Grafana without its logs datasource — `docs/monitoring.md` §10, question 4,
  unchanged.

## What the client may set

`kube.victoria_logs`:

| Attribute | Default | Type | Meaning |
| --- | --- | --- | --- |
| `enabled` | `true` | bool | Off garbage-collects the release and the namespace, **logs included**, and takes the logs path out of both collectors and Grafana |
| `retention` | `"7d"` | string | Whole hours, days, weeks or years, at least a day |
| `storage_size` | `"20Gi"` | string | The claim, in `Gi` or `Ti`; `""` for an `emptyDir` |
| `values` | `{}` | object | Any `victoria-logs-single` chart value, the client's winning. Secrets refused as for victoria_metrics: auth flags, credential-named env literals, a Secret among `extraObjects` |
| `values_secret` | `""` | string | A Secret in `victoria-logs` with a `values.yaml` key, merged last |

`kube.otel_agent.logs` (`true`, bool): `false` keeps the agent to metrics.
That is for a cluster whose container logs go elsewhere, or one where the
`hostPath` is refused: **Azure's Baseline Pod Security, once Deployment
Safeguards applies it** (`docs/monitoring.md` §10, question 1, still open).
The gateway's events and OTLP logs need no `hostPath` and are unaffected.

## Reading logs

In Grafana, Explore → VictoriaLogs, in LogsQL. The OpenTelemetry resource
attributes are fields: `k8s.namespace.name:=argocd`,
`k8s.pod.name:~"flux"`. Kubernetes events carry
`k8s.resource.name:=events`, their message is `object.note`, and they have no
`_msg` (measured, below). A dashboard for logs is out of scope for v1.

## Measured

**Render and merge, locally** (`flux-operator build rset`, `helm template` of
each pinned chart, `victoria_logs` on and off). With it on:

- the agent has a `logs` pipeline `file_log` → `otlp_http/victoria-logs`,
  the two read-only `hostPath` mounts, and `runAsUser: 0` with `drop: [ALL]`;
- the gateway has a `logs` pipeline `otlp` + `k8sobjects` →
  `otlp_http/victoria-logs`, and RBAC `watch/list` on `events.k8s.io`;
- Grafana has two datasources and the pinned plugin;
- the chart renders a `Deployment` with `--retentionPeriod=7d`, a 20Gi claim,
  and the sample's client 160Mi over the socle's 128Mi.

With it off, the agent has no `logs` pipeline, no `hostPath` and no
`securityContext`. The gateway has no `logs` pipeline, Grafana has only
VictoriaMetrics and no plugin.

`tofu test`: 138 runs, 7 of them for this module and `otel_agent.logs`.

**e2e** (floci k3s, `ubuntu-latest` runner) — run
<https://github.com/do-now-io/socle/actions/runs/36691276340>, tag
`0.0.0-feat-catalog-victoria-logs.698cf75`, both jobs green on the first run:

| Job | Step | Measured |
| --- | --- | --- |
| both | `resourceset/victoria-logs` Ready on a `Bound` claim | **1–2 s** after the collectors |
| both | a container's line, echoed by a short-lived pod | found by its token **6 s** after the pod was created. Its fields: `_msg`, `_time`, `_stream`, `k8s.cluster.uid`, `k8s.namespace.name`, `k8s.pod.name`, `k8s.pod.uid`, `k8s.pod.start_time`, `k8s.container.name`, `k8s.container.restart_count`, `k8s.node.name`. **The agent reads `/var/log/pods` as root with every capability dropped** |
| both | Kubernetes events | present (`k8s.resource.name:=events`), fields `event.domain`, `event.name`, `object.*` |
| both | an OTLP log posted by podinfo to the gateway | found by its token |
| `e2e-aws-root` | live resources, `tests/floci.tfvars` setting 160Mi | `cpu: 50m, memory: 160Mi` |
| both | `kubectl top` | VictoriaLogs **2m CPU, 32–47Mi**; the agent collecting logs 10–12m, **52Mi** (33Mi without) |
| both | Grafana | two datasources, VictoriaLogs not default; plugin `victoriametrics-logs-datasource` 0.32.0, **signature valid**; VictoriaLogs datasource health **OK** |
| `e2e-aws-catalog` | `victoria_logs` disabled | no logs exporter in either collector, no datasource in Grafana, the agent back to **non-root with no `hostPath`** (`runAsUser` and `hostPath` both empty on the live DaemonSet) |
| `e2e-aws-catalog` | re-enabled | a new claim `Bound`, both collectors exporting to it, the datasource provisioned, **28 s** |

**e2e, through Chainsaw** (`tests/e2e/chainsaw-test.yaml`, since the e2e moved
into the modules — `docs/flux-catalog.md` §8). The table above is the bash phase
this module shipped with; the same proof now runs on every push in the `root`
job (`health`) and the module's own job (`health`, then `module`): `victoria-logs-health` asserts the Bound claim and the three write paths by token (`vl.sh`): a probe pod's line through the agent, the Kubernetes events through the gateway, an OTLP log posted by podinfo; `victoria-logs-module` patches the memory request (160Mi over 128Mi), turns the module off — no logs exporter in either collector, no datasource in Grafana, the agent back to non-root with no hostPath — and on again on a new claim.

Jobs: `e2e-aws-root` 3m50s, `e2e-aws-catalog` 14m36s.

**What the run found about events.** `k8sobjects` sends each event as a
structured body, the whole watch object. VictoriaLogs flattens it into
`object.*` fields and stores **no `_msg`**: a phrase search on the probe pod's
name found none of its events, and Grafana shows such a record as "missing
_msg field". The event is all there, as `object.note` (the message),
`object.reason`, `object.regarding.name` and the rest. The e2e asserts what
holds, that the events are stored, and prints what does not. Giving events a
`_msg` is follow-up 3 below.

## Open questions for the coordinator

1. **Root in the agent.** It is the one module running as root, and only
   while it collects logs. The alternative would be log files readable by a
   group the agent runs in, which is a kubelet and runtime setting on every
   cloud, not the socle's.
2. **Restarts lose lines.** With no checkpoints, a restarted agent re-reads
   from the end of each file, and what was written while it was down is lost.
   Checkpoints need a writable `hostPath`, which is a larger ask than a
   read-only one.
3. **Events without `_msg`.** A `transform` processor in the gateway's logs
   pipeline could lift `object.note` into the body for events only, or
   VictoriaLogs could be told which field is the message (`_msg_field`). The
   first touches the gateway's pipeline for one kind of record, the second
   applies to every record the exporter sends. Neither was measured, so both
   stay a choice for review.
