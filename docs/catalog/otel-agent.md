# Catalog module `otel_agent` — the node-level collector

The second module of the monitoring stack (#43, design in
[`docs/monitoring.md`](../monitoring.md)): the OpenTelemetry Collector as a
DaemonSet, one pod per node, for what lives on a node. In this PR that is the
kubelet's metrics for every node, pod and container, with Kubernetes metadata
on every point, written to [`victoria_metrics`](victoria-metrics.md). Container
logs join it with `victoria_logs`. The module contract is
`docs/flux-catalog.md` §3 and §6; argocd is the template.

| Question | Position |
| --- | --- |
| What | The official `opentelemetry-collector` chart, `oci://ghcr.io/open-telemetry/opentelemetry-helm-charts/opentelemetry-collector:0.173.1` (collector 0.160.0), `mode: daemonset`, one `HelmRelease` in namespace `otel-agent` |
| Distribution | `otelcol-k8s` — upstream's Kubernetes build, 74 components against contrib's 251. It has `otlp_http`, `kubeletstats`, `k8s_attributes`, `nop`; it has no Prometheus remote-write, which is why every signal crosses as OTLP |
| Where | Every cloud, the same template, no cloud patch |
| Default | **On**, like every monitoring module but traces |
| Collects | `kubeletstats` every 20 s: node, pod and container CPU, memory, filesystem, network. The collector's own telemetry, scraped from itself |
| Enriches | `k8s_attributes`, watching this node's pods only: workload, namespace, labels on every point |
| Exports | OTLP/HTTP to `victoria-metrics.victoria-metrics.svc:8428/opentelemetry/v1/metrics` when `victoria_metrics` is on; to `nop` when it is off |
| Receives | **Nothing.** No receiver port, no hostPort: applications send OTLP to `otel_gateway` |
| Host access | None in this PR: no `hostPath`, no `hostNetwork`. The kubelet is reached over the node IP with the ServiceAccount token |
| Dashboard | **Kubernetes / Nodes and pods**, shipped by this module (below) |
| Cloud access | None |
| Client surface | `values` and `values_secret`, as every module; no named attribute until `victoria_logs` brings `logs` |

## What is installed

One `ResourceSet` (`oci/catalog/otel-agent/resourceset.yaml`),
`resourcesTemplate`, six objects, each carrying the per-resource reconcile
toggle on `inputs.modules.otel_agent.enabled`:

1. `Namespace/otel-agent`.
2. `OCIRepository/opentelemetry-collector-chart` — the chart pinned exactly.
3. `ConfigMap/otel-agent-socle-values` — the socle's own chart values.
4. `ConfigMap/otel-agent-client-values` — `kube.otel_agent.values`.
5. `HelmRelease/otel-agent` — no `spec.values`; `valuesFrom` = socle, client,
   the client's Secret when named (`optional: true`).
6. `Kustomization/otel-agent-dashboards` in `flux-system` — applies
   `oci/catalog/otel-agent/dashboards/` from the socle artifact itself into
   `otel-agent`, pruned with the module. The same shape as gateway-api's
   `cilium/` folder: the dashboard stays a file of its own, not a string inside
   the template.

Both values ConfigMaps carry `reconcile.fluxcd.io/watch: Enabled`, which Flux
recommends for every `valuesFrom` reference: helm-controller then upgrades the
release the moment one changes, rather than at its next `interval` (10m). That
matters here more than anywhere, because the agent's exporter follows another
module's `enabled`. The client labels his own Secret the same way if he wants
the same.

The chart names what it renders from `fullnameOverride: otel-agent`, with its
own suffix: the DaemonSet and its ConfigMap are `otel-agent-agent`.

The socle's values, and why:

| Value | Setting | Why |
| --- | --- | --- |
| `mode` | `daemonset` | One pod per node, for what only a node can see |
| `image.repository`, `command.name` | `…/opentelemetry-collector-k8s`, `otelcol-k8s` | The chart refuses to render without an image (and without a `mode`); this is the Kubernetes distribution (above) |
| `presets.kubeletMetrics` | on | The `kubeletstats` receiver, its RBAC (`nodes/stats`) and `K8S_NODE_IP` |
| `presets.kubernetesAttributes` | on | The `k8s_attributes` processor, filtered to this node, and its RBAC |
| `config.receivers.kubeletstats.insecure_skip_verify` | `true` | Kubelet serving certificates are self-signed on EKS, and on most managed clusters not signed by the CA a pod is given. The call still carries the ServiceAccount token, which the kubelet authorizes |
| `ports.*` | all off | The chart opens six receiver ports **as hostPorts on every node** by default. The agent receives nothing |
| `config.receivers.otlp`, `jaeger`, `zipkin` | `null` | Same reason; `null` removes the chart's default |
| `config.exporters` | `otlp_http/victoria-metrics`, or `nop` | `<< if inputs.modules.victoria_metrics.enabled >>` in the socle's document. The chart's `debug` exporter is removed |
| `config.service.pipelines` | `metrics` only | `logs` and `traces` are `null` until their backends exist |
| `resources` | requests 50m / 128Mi, **limit 512Mi memory** | The one module with a limit, on purpose: the chart derives `GOMEMLIMIT` from it and the `memory_limiter` processor its 80 %. Without one, both would read the node's whole memory, and the agent would be killed instead of refusing data first |

The component names are the new ones (`otlp_http`, `k8s_attributes`): the chart
rewrites the deprecated ones for this release and warns, and will stop.

## What the client may set — `kube.otel_agent`

| Attribute | Default | Type | Meaning |
| --- | --- | --- | --- |
| `enabled` | `true` | bool | Off garbage-collects the release, the namespace and the dashboard |
| `values` | `{}` | object | Any value of the `opentelemetry-collector` chart. Merged over the socle's values, the client's winning: an extra receiver, a filter processor, a second exporter to his own backend |
| `values_secret` | `""` | string | Name of a Secret in `otel-agent`, created by the client, with a `values.yaml` key. Merged last |

**A second exporter needs the whole list.** Helm replaces lists, it does not
merge them. A client adding his own exporter writes
`config.service.pipelines.metrics.exporters` in full, the socle's
`otlp_http/victoria-metrics` included, or the socle's is dropped.

### Secrets refused in `values`

The collector takes credentials in its own configuration and from its
environment. Plan refuses a **literal** in:

- an authenticator extension's `token`, `client_auth.password`,
  `htpasswd.inline` or `client_secret` (bearer token, basic auth, OAuth2);
- an exporter's `Authorization`, `Proxy-Authorization`, `X-API-Key`, `API-Key`
  or `X-Auth-Token` header;
- an `extraEnvs` entry named like a credential with a literal `value`;
- and a `Secret` among `extraManifests`.

A value written as an environment reference is accepted: `${env:SAAS_TOKEN}`,
with `extraEnvs` setting `SAAS_TOKEN` `valueFrom` a Secret the client owns, is
the collector's own way to read a secret, and nothing reaches the state. That
is a refinement of `docs/monitoring.md` §4, which listed the paths but not the
exemption.

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

(`$${…}` is how HCL writes a literal `${…}`.)

## The nodes and pods dashboard

`oci/catalog/otel-agent/dashboards/nodes-pods.yaml`: a ConfigMap labelled
`grafana_dashboard: "1"`, which the grafana module's sidecar picks up in any
namespace. Until that module lands, it is inert.

It is written on the names VictoriaMetrics stores under
`-opentelemetry.usePrometheusNaming` — dots to underscores, units in braces
dropped, byte units as `_bytes`, monotonic sums as `_total`:

| Panel | Expression reads |
| --- | --- |
| CPU used, by node | `k8s_node_cpu_usage` |
| Memory working set, by node | `k8s_node_memory_working_set_bytes` |
| Filesystem used, by node | `k8s_node_filesystem_usage_bytes` / `k8s_node_filesystem_capacity_bytes` |
| Network, by node | `rate(k8s_node_network_io_bytes_total)` by `direction` |
| CPU and memory, by namespace; top 10 pods by each | `k8s_pod_cpu_usage`, `k8s_pod_memory_working_set_bytes` |
| Network, by namespace | `rate(k8s_pod_network_io_bytes_total)` |

Variables: the data source (any Prometheus-type one, so the name Grafana
provisions is not hard-coded), `node` and `namespace`. Labels are the promoted
resource attributes, `k8s_node_name`, `k8s_namespace_name`, `k8s_pod_name`.

**The e2e keeps it honest**: it reads the dashboard back from the cluster,
extracts every metric an expression or a variable names, and fails when one of
them has no series in VictoriaMetrics. A renamed metric upstream breaks the
build, not a client's screen.

## Per cloud

Nothing in the template. Around it:

| Cloud | Note |
| --- | --- |
| AWS | Kubelet serving certificates self-signed — hence `insecure_skip_verify` |
| GCP | On Autopilot, a DaemonSet is billed per Pod request on every node: the 50m / 128Mi requests are the per-node price |
| Azure | Nothing until logs: the metrics path needs no `hostPath`, so Baseline Pod Security does not apply to this PR (`docs/monitoring.md` §10, question 1, is about logs) |
| Scaleway | Nothing |

## Templating notes

- The exporter block and the pipeline's exporter list are two `<< if >>` on
  the same test, inside the socle's document. The operator merges the whole
  catalog into the inputs, so `inputs.modules.victoria_metrics.enabled` always
  exists: templates test values, never presence.
- `null` in the socle's document deletes a chart default: helm-controller
  merges the `valuesFrom` documents, and Helm drops a key whose user value is
  `null` when it coalesces them with the chart's defaults. Checked with
  `helm template`.

## Measured

**Render** (`flux-operator build rset` 0.60.0, `oci/.ci/inputs-sample.yaml`):
six objects; the HelmRelease has no `spec.values`, `valuesFrom` = socle,
client, Secret.

**Merge, locally** — `helm template` of the pinned chart with the rendered
documents:

- the collector configuration is exactly: receivers `kubeletstats` (20 s,
  `serviceAccount`, `${env:K8S_NODE_IP}:10250`, `insecure_skip_verify`) and
  the self-scrape `prometheus`; processors `k8s_attributes` (filtered on
  `K8S_NODE_NAME`), `memory_limiter`, `batch`; exporter
  `otlp_http/victoria-metrics`; one `metrics` pipeline. No `debug`, no `otlp`,
  `jaeger` or `zipkin`, no `logs` or `traces` pipeline;
- the DaemonSet has **no container port**, no `hostPath`, no `hostNetwork`;
- with the sample's client `resources.requests.memory: 160Mi`: requests
  `cpu: 50m, memory: 160Mi`, limit `memory: 512Mi` — the client's value, the
  socle's siblings kept;
- with `victoria_metrics.enabled: false`: exporters `{nop: {}}`, the pipeline
  ending in `nop`.

`tofu test`: 114 runs, 9 of them for this module — `enabled` refusing a
string, `values` refusing a string, a literal bearer token, a literal basic
auth password, a literal `Authorization` header, a literal credential env, a
Secret among `extraManifests`, an invalid `values_secret`; and `${env:…}` in a
token and a header, with the env `valueFrom` a Secret, flowing through as
written. Defaults asserted.

**e2e** (floci k3s, `ubuntu-latest` runner) — run
<https://github.com/do-now-io/socle/actions/runs/36579573809>, tag
`0.0.0-feat-catalog-otel-agent.6615022`, both jobs green on the first run:

| Job | Step | Measured |
| --- | --- | --- |
| both | `resourceset/otel-agent` Ready, DaemonSet `otel-agent-agent` rolled out | **1 s** after victoria-metrics — the image pulled meanwhile |
| `e2e-aws-root` | `k8s_pod_cpu_usage` in VictoriaMetrics | 10 series, **2 s** after the rollout |
| `e2e-aws-root` | every metric of the dashboard | all eight with series (1 node, 16 pods; network 2 and 32, one per direction) |
| `e2e-aws-root` | live resources, `tests/floci.tfvars` setting 160Mi | `requests: cpu 50m, memory 160Mi; limits: memory 512Mi` — the client's value, the socle's siblings kept. 128Mi in `e2e-aws-catalog`, with no client value |
| both | the agent, `kubectl top` | **3–5m CPU, 33Mi** on one node |
| `e2e-aws-root` | VictoriaMetrics under the agent's ingest | 5m CPU, **90Mi** (59Mi before the agent started, 12Mi empty) |
| `e2e-aws-catalog` | `victoria_metrics` disabled, the agent kept on | the agent's configuration ends in `nop` **2 s** later and the DaemonSet rolls out — `reconcile.fluxcd.io/watch` at work, where the 10-minute interval would otherwise have applied |
| `e2e-aws-catalog` | `victoria_metrics` re-enabled | exporter back and `k8s_pod_cpu_usage` in the new, empty storage **2 s** after VictoriaMetrics was Ready |
| `e2e-aws-catalog` | `otel_agent` disabled alone, then re-enabled | HelmRelease and `otel-agent-dashboards` Kustomization NotFound; Ready again with the dashboard ConfigMap back after **77 s** |

What VictoriaMetrics stores from kubeletstats, as printed by the run — the
dashboard's names are among them: `container_cpu_time_seconds_total`,
`container_cpu_usage`, `container_filesystem_{available,capacity,usage}_bytes`,
`container_memory_{available,rss,usage,working_set}_bytes`,
`container_memory_{major_,}page_faults_ratio`, and the same families under
`k8s_node_` and `k8s_pod_`, plus `k8s_{node,pod}_network_io_bytes_total` and
`k8s_{node,pod}_network_errors_total`. The conversion is the one
`docs/monitoring.md` §3 assumed: braces units dropped, `By` → `_bytes`,
cumulative seconds → `_seconds_total`, `1` → `_ratio`.

**Helm 4** (`docs/monitoring.md` §10, question 6): the chart lists Helm 4.0+
as a prerequisite; Flux v2.9.5's helm-controller installs it, upgrades it
(the exporter's flip to `nop` and back) and uninstalls it. Closed.

**What floci cannot prove:** one node, so not the per-node cost at scale;
k3s's kubelet, not EKS's self-signed one.

## Open questions for the coordinator

1. **`reconcile.fluxcd.io/watch` on every module.** The monitoring modules
   carry it; argocd, external-dns and crossplane do not, so a change of
   `kube.<module>.values` there reaches the release only at its next
   interval, up to ten minutes. One label per ConfigMap in three templates; a
   PR of its own.
2. **`insecure_skip_verify`.** The alternative is kubelet serving certificates
   signed by the cluster CA (`serverTLSBootstrap` and a CSR approver), a
   foundations change on every cloud. Not worth it for a read-only stats call
   that already carries a token — to confirm.
