# Monitoring — OpenTelemetry to collect, Victoria to store, Grafana to read

The socle's in-cluster monitoring stack: metrics, logs and traces from every
workload and from the cluster itself, collected by OpenTelemetry, stored in
the Victoria family, read in Grafana. Tracks #43. This is the design; each
module lands in its own stacked PR with its own note under `docs/catalog/`,
and every one of them follows `docs/flux-catalog.md` §6 mechanically — the
argocd module is the template, not an inspiration.

| Question | Position |
| --- | --- |
| Shape | **Six catalog modules**, one chart release each: `otel_agent`, `otel_gateway`, `victoria_metrics`, `victoria_logs`, `victoria_traces`, `grafana` |
| Collection | OpenTelemetry Collector, `otelcol-k8s` distribution: a DaemonSet for what lives on a node, a Deployment for what lives in the cluster and for the applications' OTLP |
| Metrics | VictoriaMetrics single-node, OTLP in, 15 days, on a PVC — or an `emptyDir` when the client empties `storage_size` |
| Logs | VictoriaLogs single-node, OTLP in, 7 days, on a PVC, same switch |
| Traces | VictoriaTraces single-node, OTLP in, 7 days — **off by default**: pre-GA, storage format not yet committed |
| Grafana | The `grafana-community` chart, datasources provisioned by the socle for whichever backends are on |
| Dashboards | **The socle's own, on OpenTelemetry names**, each shipped by the module whose metrics it shows — no kube-state-metrics, no node-exporter |
| Stack order | **Metrics first**: `victoria_metrics`, `otel_agent`, `otel_gateway`, `grafana`, then `victoria_logs` and `victoria_traces` (§8) |
| Where | Every cloud, the same templates. **This supersedes** the delegation to Managed Service for Prometheus on GCP and Managed Prometheus + Container Insights on Azure (below) |
| Scope | **Each cluster is self-contained.** No remote-write, no federation, no central Alertmanager: the central observability plane of `docs/*/cloud-observability.md` is a separate subject |
| Cloud access | **None.** Every backend stores on a PVC; no bucket, no key, no role, so no Crossplane dependency and no foundations change |
| Client surface | Per module: `enabled`, the knobs below, and `values` / `values_secret` as every module has them |

## 1. Why six modules and not one

`docs/flux-catalog.md` §6 makes a module cheap and a monolith expensive: one
`ResourceSet`, one namespace, one on/off toggle, one `values` surface per
chart release. A single `monitoring` module would have to answer "which
chart does `kube.monitoring.values` go to", and turning traces off would mean
a sub-switch the contract has no shape for. So the cut follows the releases:

| Module | Namespace | Chart (pin at time of writing) | Runs as |
| --- | --- | --- | --- |
| `otel_agent` | `otel-agent` | `opentelemetry-collector` **0.173.1** (collector 0.160.0) | DaemonSet |
| `otel_gateway` | `otel-gateway` | `opentelemetry-collector` **0.173.1** | Deployment, 1 replica |
| `victoria_metrics` | `victoria-metrics` | `victoria-metrics-single` **0.48.0** (v1.153.0) | 1 pod + PVC |
| `victoria_logs` | `victoria-logs` | `victoria-logs-single` **0.13.9** (v1.52.0) | 1 pod + PVC |
| `victoria_traces` | `victoria-traces` | `victoria-traces-single` **0.1.11** (v0.11.0) | 1 pod + PVC |
| `grafana` | `grafana` | `grafana` **13.2.6** (Grafana 13.2.2), `grafana-community` | Deployment, 1 replica |

Every chart is published as OCI and pulled through an `OCIRepository`, as
argocd does: `oci://ghcr.io/open-telemetry/opentelemetry-helm-charts/…`,
`oci://ghcr.io/victoriametrics/helm-charts/…`,
`oci://ghcr.io/grafana-community/helm-charts/grafana` (each tag resolved
against the registry on 2026-09-28).

**One namespace per module**, not a shared `monitoring`: a disabled module
garbage-collects its namespace, and two `ResourceSet`s owning one namespace
would delete it under each other.

**Two collector modules, not one.** The agent and the gateway are the same
chart in two modes, so one module would need two `values` — a shape the
contract does not have. Two modules keep `kube.<m>.values` meaning one chart's
values, and let a client run the gateway alone (applications' OTLP only, no
node agent) on a cluster where DaemonSets are unwelcome.

**Not chosen:**

- `victoria-metrics-k8s-stack`. It is the VictoriaMetrics operator plus
  VMSingle, vmagent, vmalert, Alertmanager, kube-state-metrics,
  node-exporter and Grafana in one release — the monolith again, with a
  second collection layer (vmagent) beside OpenTelemetry and a webhook plus
  CRDs to order in Flux. #43 settled OpenTelemetry as the collection layer.
- `opentelemetry-kube-stack`. It needs the OpenTelemetry operator, whose
  webhooks need cert-manager by default, and it pins kube-state-metrics 6.3
  and node-exporter 4.48 far behind upstream (8.6.0, 4.59.0). The plain
  collector chart in two releases does the same work with no operator.
- The cluster charts (`victoria-metrics-cluster`, `victoria-logs-cluster`).
  A small cluster does not need them; a client who outgrows single-node is a
  later module, not a switch here.

## 2. What talks to what

```
 applications ──OTLP 4317/4318──▶ otel_gateway ──┐
 annotated pods ◀──scrape──────── otel_gateway   │   OTLP/HTTP
 Kubernetes API ◀──k8s_cluster, events── gateway ├──▶ victoria_metrics :8428  /opentelemetry/v1/metrics
                                                  ├──▶ victoria_logs    :9428  /insert/opentelemetry/v1/logs
 kubelet, /var/log/pods ◀──── otel_agent ────────┤
                                                  └──▶ victoria_traces  :10428 /insert/opentelemetry/v1/traces
                                         grafana ──▶ Prometheus / VictoriaLogs / Jaeger datasources
```

- **Every signal crosses as OTLP over HTTP.** All three backends ingest it
  natively, which is what lets the collector run `otelcol-k8s` — 74
  components against contrib's 251, and it carries `otlphttp` but not
  `prometheusremotewrite`. One exporter, three signal endpoints
  (`metrics_endpoint`, `logs_endpoint`, `traces_endpoint`).
- **The agent exports straight to the backends**, not through the gateway:
  node data does not depend on one Deployment staying up, and the gateway
  does not have to be sized for every node's logs.
- **Pipelines are conditional on the other modules.** Each collector's
  socle-values document adds a signal's exporter only when that backend is on
  — `<< if inputs.modules.victoria_logs.enabled >>` — and Grafana adds a
  datasource under the same test. OpenTofu merges the whole catalog into the
  inputs, so every module's `enabled` is always present: templates test
  values, never presence. Turning `victoria_logs` off therefore removes the
  logs pipeline from both collectors and the datasource from Grafana in the
  same reconciliation, with no collector left retrying into a Service that is
  gone. Because the stack lands metrics first (§8), a backend that arrives
  after the collectors and Grafana brings those conditional blocks in its own
  PR: the module that needs a pipeline or a datasource carries it — the rule
  dashboards (§5) and cloud access follow too.
- **Service names are constants.** Each Victoria module sets
  `fullnameOverride` in its socle document so the endpoint is
  `http://victoria-metrics.victoria-metrics.svc:8428` and never a
  chart-derived name. A client who overrides `fullnameOverride` in `values`
  breaks the wiring; the module note says so, the plan does not refuse it (a
  named attribute is a convenience, not a lock — §6).
- **No `dependsOn` between the modules.** The collectors retry an absent
  backend, Grafana starts without its datasources answering. Ordering would
  only make a slow backend block the ones that are ready.

### Where each signal comes from

| Signal | Source | Module | Receiver / preset |
| --- | --- | --- | --- |
| Node, pod and container CPU, memory, filesystem, network | kubelet stats API | `otel_agent` | `kubeletMetrics` (kubeletstats) |
| Container logs | `/var/log/pods`, read-only | `otel_agent` | `logsCollection` (filelog), `storeCheckpoints` off |
| Kubernetes metadata on every record | API server | both | `kubernetesAttributes` (k8sattributes) |
| Object state (deployments, pods, nodes, HPA…) | API server | `otel_gateway` | `clusterMetrics` (k8s_cluster) |
| Kubernetes events, as logs | API server | `otel_gateway` | `kubernetesEvents` |
| Prometheus endpoints (Cilium, Flux, ArgoCD, Crossplane, the backends themselves) | pods annotated `prometheus.io/scrape` | `otel_gateway` | `prometheus` receiver, `kubernetes_sd` on pods, annotation relabelling |
| Application metrics, logs, traces | OTLP gRPC 4317 / HTTP 4318 | `otel_gateway` | `otlp` |

- **Host metrics are off** (`hostMetrics` preset). They need the node's root
  filesystem mounted into the pod, which GKE Autopilot refuses and the
  Baseline Pod Security Standard forbids; kubeletstats already gives the node
  CPU, memory and filesystem figures that matter. A client who wants them
  sets the preset in `kube.otel_agent.values` on the clouds that allow it.
- **Scraping is annotation-based in v1**, from the gateway, one replica: no
  target allocator, no `ServiceMonitor`. Cilium already falls back to
  `prometheus.io/*` annotations when its ServiceMonitors are off, which they
  are in the socle. `ServiceMonitor`/`PodMonitor` support is open question 2.
- **`storeCheckpoints` stays off**: it makes the collector run as root. The
  cost is that a restarted agent re-reads from the end of each file
  (`start_at: end`) and loses the lines written while it was down; measured
  in the module PR.

## 3. What each backend stores, and for how long

The reference estate (`docs/gcp/managed-scope.md`) scrapes ~300 samples/s
per cluster once filtered and writes ~30 GiB of logs a month. On nodes the
client already pays for, that is small:

| Module | Retention default | PVC default | Why that much |
| --- | --- | --- | --- |
| `victoria_metrics` | `15d` | `20Gi` | ~300 samples/s × 15 days ≈ 390 M samples; at the ~1 byte/sample VictoriaMetrics typically reaches, well under 1 GiB. The rest is headroom for a noisier cluster before the disk becomes the question |
| `victoria_logs` | `7d` | `20Gi` | ~7 GiB of raw logs a week before compression. Kubernetes events land here too |
| `victoria_traces` | `7d` | `10Gi` | No reference volume; the chart's default size |

The byte-per-sample and compression figures are the upstream orders of
magnitude, not measured here. The module PRs measure the real ingest on
floci and correct these.

- The charts default `retentionPeriod` to `1` (one month) for all three
  products, overriding the binaries' own 7-day default for logs and traces.
  The socle sets it explicitly in each socle document, from the `retention`
  attribute.
- **Cardinality is bounded on metrics**: the socle document sets
  `-storage.maxHourlySeries` (100 000 by default), so a label explosion
  drops new series with a log line rather than filling the disk or the
  memory. That is the "samples/second budget" `docs/gcp/managed-scope.md`
  said the monitoring module must carry, in the unit that matters when
  storage is local rather than billed per sample. The flag is open source: it is
  defined in `app/vmstorage/main.go` at v1.153.0, the single-node build's own
  storage.
- **Metric names keep their Prometheus form**:
  `-opentelemetry.usePrometheusNaming` on VictoriaMetrics, so a metric
  scraped from Cilium or Flux reads with the name its upstream dashboards
  use, even though it crossed the collector as OTLP.
- **What is enterprise-only, and therefore not used**: downsampling,
  per-series retention filters, scheduled backups (`vmbackupmanager`).
  `vmbackup` itself is open source and writes to S3, GCS or Azure Blob; it is
  a follow-up, and a bucket is exactly the case where the module creates its
  own access through Crossplane (§6) — never a foundations block.

### Storage class

Each backend asks for a PVC of the cluster's default `StorageClass`, with no
class named in the template: the cloud's CSI driver is the foundations'
choice (EBS, Persistent Disk, Azure Disk, Scaleway Block), and the socle
already relies on the default for the source-controller cache.

**Decided in review: a PVC by default, an `emptyDir` on request.**
`storage_size = ""` renders no claim at all — the backend keeps its data in
an `emptyDir`, lost when the pod is rescheduled. That is the escape for a
cluster with no default class, not a production setting.

**EKS has none today.** `opentofu/aws` installs no EBS CSI driver — it is an
EKS-managed add-on left to the factory (`opentofu/aws/cluster.tf`,
`docs/aws/eks-managed-scope.md`) — and EKS itself marks no class default
since 1.30. A claim on a socle EKS therefore stays `Pending` and the backend
never starts. That is a foundations/factory gap, tracked on its own, and the
catalog does not paper over it: an AWS client sets `storage_size = ""` until
the driver exists (`opentofu/clusters/aws/prod.tfvars.example` says so), and a
per-cloud default in the template would hide the gap rather than close it.
floci's k3s ships `local-path` as its default class, so the e2e exercises the
PVC path.

## 4. What the client may set

The same pattern on every module: the defaults are the schema
(`opentofu/bootstrap/catalog.tf`), kinds are enforced by the catalog-wide
check, named attributes are validated in `variables.tf`, and `values` is the
chart's whole surface, merged over the socle's document with the client
winning.

| Module | Attribute | Default | Validation |
| --- | --- | --- | --- |
| all | `enabled` | `true`, except `victoria_traces` = `false` | bool |
| all | `values` | `{}` | object; each module refuses its secret-bearing paths |
| all | `values_secret` | `""` | empty or a Secret name |
| `victoria_metrics` | `retention` | `"15d"` | a VictoriaMetrics duration: integer plus `h`, `d`, `w` or `y`, at least 1 day |
| `victoria_metrics` | `storage_size` | `"20Gi"` | empty (an `emptyDir`, no claim) or a Kubernetes quantity in `Gi` or `Ti` |
| `victoria_logs` | `retention` | `"7d"` | same as above |
| `victoria_logs` | `storage_size` | `"20Gi"` | same |
| `victoria_traces` | `retention` | `"7d"` | same |
| `victoria_traces` | `storage_size` | `"10Gi"` | same |
| `otel_agent` | `logs` | `true` | bool — `false` drops the filelog pipeline, for a cluster whose logs go elsewhere |
| `grafana` | `domain` | `""` | empty or a lowercase FQDN, the argocd validation reused. Feeds `grafana.ini.server.root_url` now, the HTTPRoute later |

`otel_gateway` has no named attribute beyond the common three: every useful
knob (extra receivers, a sampling processor, a second exporter to the
client's own backend) is chart configuration, which is what `values` is for.

**Secrets refused in `values`**, each module's list in its note, at least:

- `grafana`: `adminPassword`, `grafana.ini.security.secret_key`,
  `grafana.ini.database.password`, any `client_secret` under
  `grafana.ini."auth.*"`. The admin password goes in the client's Secret
  through `admin.existingSecret`, or stays the random one the chart
  generates.
- `otel_agent`, `otel_gateway`: `password` and `token` under any
  `config.extensions` authenticator, `headers.authorization` under any
  `config.exporters` entry — the day a client adds an exporter to his own
  SaaS backend, its credential goes in `values_secret`.
- `victoria_*`: `-httpAuth.password` and `-*.authKey` under `server.extraArgs`.

**Resizing a volume.** The Victoria single-node charts default to a
StatefulSet, whose `volumeClaimTemplates` Helm cannot change after install —
a new `storage_size` would fail every upgrade. The socle runs them in the
charts' `deployment` mode instead (`server.mode: deployment`, strategy
`Recreate`), which renders a standalone PVC: growing it works where the class
allows expansion, shrinking is refused by the API server, and `""` drops the
claim. Measured on `victoria-metrics-single` 0.48.0 with `helm template`;
each module note restates it for its own chart.

## 5. Grafana

- **Datasources are provisioned by the socle**, in the socle document's
  `datasources:` value, each under the `enabled` of its backend:

  | Backend | Datasource | Plugin |
  | --- | --- | --- |
  | `victoria_metrics` | built-in **Prometheus**, `http://victoria-metrics.victoria-metrics.svc:8428`, default | none |
  | `victoria_logs` | `victoriametrics-logs-datasource` **0.32.0** | signed by Grafana (commercial signature) |
  | `victoria_traces` | built-in **Jaeger**, `…:10428/select/jaeger` | none |

  The Prometheus datasource rather than VictoriaMetrics' own plugin: the
  built-in one needs no download and covers PromQL; MetricsQL extras are a
  client's `values` away. VictoriaLogs has no built-in equivalent, so its
  plugin is the one exception, and it is **downloaded from grafana.com at
  startup** — open question 4.
- **Dashboards are ConfigMaps**, picked up by the chart's sidecar
  (`sidecar.dashboards.enabled: true`, label `grafana_dashboard`, every
  namespace). A module that has something to show ships its own dashboard in
  its own `ResourceSet`, under its own toggle — the same rule as
  cloud access: the thing that needs it carries it. Grafana names no module.
- **Decided in review: the dashboards are the socle's own, written on
  OpenTelemetry names** — one source per signal. `otel_agent` ships the nodes
  and pods dashboard (kubeletstats), `otel_gateway` the workloads one
  (`k8s_cluster`); each reads the names VictoriaMetrics stores under
  `-opentelemetry.usePrometheusNaming`, checked against a live query in the
  module's PR before the JSON is written. kube-state-metrics and
  node-exporter are not added: they would be a second collection layer beside
  OpenTelemetry, which #43 rules out, for the sole benefit of the community
  dashboards.
- **ClusterIP, no ingress**, as argocd: exposure is the Gateway API
  follow-up, and `domain` is already the hostname it will read.
- **No persistence.** Everything Grafana shows is provisioned, so a
  restarted pod loses only what a user clicked together by hand. A client
  who wants that kept sets `persistence.enabled` in `values`.
- **Licence.** Grafana is AGPL-3.0. The socle runs it unmodified, from
  upstream's images; nothing here changes that position, and it is written
  down because clients ask.
- **Alerting is not configured** (below).

## 6. Per cloud

The templates carry no cloud patch in v1. What differs is around them:

| Cloud | What changes for the stack | What changes elsewhere |
| --- | --- | --- |
| AWS | Nothing | — |
| GCP | The agent DaemonSet is billed per Pod request on Autopilot, on every node. Read-only `/var/log` is allowed there; writable `hostPath` is not, which the agent does not need | `docs/gcp/managed-scope.md` delegated workload metrics to Managed Service for Prometheus. **Superseded**: the socle's VictoriaMetrics stores them, at no per-sample cost. GKE's free system metrics are unaffected |
| Azure | `/var/log/pods` is a `hostPath`, which the Baseline Pod Security Standard forbids — and Baseline/Enforce is what `docs/azure/managed-scope.md` decided (not yet applied, see `opentofu/azure/cluster.tf`). Open question 1 | `opentofu/azure` enables Managed Prometheus and Container Insights today. **Superseded**: a separate PR removes both from the foundations, so a cluster does not pay twice for the same signal |
| Scaleway | Nothing. "Workload metrics in the socle's own Prometheus" (`docs/scaleway/kapsule-capabilities.md`) is this stack | Cockpit keeps Scaleway's free data |

The Azure removal is a foundations change, and it is argued as one: it
follows from a socle decision — one monitoring stack on four clouds — and
leaves `opentofu/azure` describing the same cluster whatever the catalog
runs, which is the invariance §6 asks for. It is not in this stack.

## 7. What floci can prove

The e2e jobs run the real AWS root on floci's k3s, a single node on a 7 GB
runner that already carries argocd.

| Provable on floci | Not provable on floci |
| --- | --- |
| Every module converges; disable garbage-collects it, re-enable brings it back | Cloud StorageClasses, volume expansion |
| A metric from the agent (`k8s.pod.cpu.usage` from kubeletstats) and one from the gateway (a scraped Flux controller metric) are queryable on VictoriaMetrics' `/api/v1/query` | GKE Autopilot's restrictions on DaemonSets and `hostPath` |
| A log line from a known pod is found through VictoriaLogs' `/select/logsql/query` | Azure's Baseline Pod Security Standard |
| Grafana's `/api/health` answers and `/api/datasources` lists exactly the enabled backends | The per-node cost of the agent at scale |
| Precedence: a client value beats a socle default on the live object (e.g. `-storage.maxHourlySeries` on the VictoriaMetrics container's args, its sibling flags intact) | Retention actually expiring data (15 days) |
| Turning `victoria_logs` off removes the logs exporter from both collectors and the datasource from Grafana | |

**Memory is the budget to watch.** Crossplane alone costs ~1.1 GB idle and
moved a job from 3m35s to 6m24s. No idle figure is published upstream for any
of the six; the first module PR measures them and decides, per module,
whether it stays in `tests/floci.tfvars` or is covered by `e2e-aws-catalog`
only. A module that cannot converge on floci defaults to off, with the reason
written down — the catalog rule, not a new one.

## 8. The stack

One draft PR per module, stacked on the issue branch
`feat/catalog-monitoring`, one commit each, in this order:

| Order | Module | Why here |
| --- | --- | --- |
| 1 | `victoria_metrics` | The first backend: the collectors need somewhere to write before their e2e can assert anything. Measures the memory budget and settles the PVC questions for the other two |
| 2 | `otel_agent` | Node and pod metrics (kubeletstats) — proves an OpenTelemetry metric reaching storage, and ships the nodes and pods dashboard |
| 3 | `otel_gateway` | Cluster object metrics, scraping, OTLP in — proves a scraped Flux metric reaching storage, and ships the workloads dashboard |
| 4 | `grafana` | The consumer: the Prometheus datasource and the dashboards the modules above ship. Metrics are readable end to end from here |
| 5 | `victoria_logs` | Second signal. Brings its own exporters into both collectors (container logs in the agent, Kubernetes events in the gateway) and its datasource into Grafana |
| 6 | `victoria_traces` | Third signal, off by default. Brings its exporter into the gateway and its datasource into Grafana |

**Decided in review: metrics first.** The order in the first draft put the
three backends first and Grafana last, which kept each backend PR small but
left nothing readable until the sixth. Metrics end to end — storage,
collection, reading — is the path a client asks to see first, so it lands in
four PRs, and logs and traces follow as additions to modules that already
exist, each carrying its own pipeline and datasource (§2).

This document is the base of that stack, as `docs/flux-catalog.md` §6 was for
#32: it is merged last, with the stack.

## 9. Out of scope for v1

- **Alerting.** No vmalert, no Alertmanager, no rules, no Grafana alerting
  contact points. The cloud-observability notes assume "one Alertmanager for
  four clouds" in a central plane; whether per-cluster alerting exists at all,
  or is only ever central, is decided with that plane.
- **Anything central**: remote-write, federation, multi-cluster Grafana.
- **Backups** of the backends (`vmbackup` to a bucket, through Crossplane).
- **Exposure** through Gateway API, and SSO on Grafana.
- **Profiles** (the collector's eBPF profiling distribution).
- **High availability** of any backend: single-node is one pod and one disk.

## 10. Open questions, for review

**Decided in review** (29 September 2026), and written into the sections
above:

- **Stack order** — metrics first (§8).
- **Question 3, a default StorageClass** — a PVC by default, `storage_size =
  ""` for an `emptyDir`; EKS has no class today, a foundations/factory gap
  tracked on its own (§3).
- **Question 5, dashboards** — the socle's own, on OpenTelemetry names, each
  shipped by the module whose metrics it shows (§5).
- **Questions 1, 2, 4, 6 and 7 stand as written below**, and so do the
  defaults of §4: every module on except `victoria_traces`.

1. **Container logs on Azure.** The agent reads `/var/log/pods` through a
   read-only `hostPath`, which Baseline Pod Security forbids. Either the
   `otel-agent` namespace is exempted when Deployment Safeguards is applied
   (a foundations exclusion, named as such), or on Azure `otel_agent` runs
   with `logs = false` and container logs have no path. Not blocking until
   Safeguards is actually applied, which it is not yet.
2. **`ServiceMonitor` and `PodMonitor`.** Charts from the ecosystem ship
   them, clients write them. Supporting them means the
   `prometheus-operator-crds` chart (32.0.1) plus the standalone OpenTelemetry
   target allocator chart (0.159.0), which watches both kinds without the
   operator. Two more releases; worth it the day a client asks, not before.
3. **A default StorageClass on every cloud.** *Decided, §3.* EKS has none
   until the EBS CSI driver is installed; GKE, AKS and Kapsule ship one,
   confirmed when each cloud's e2e exists.
4. **The VictoriaLogs plugin is downloaded at Grafana's start**, from
   grafana.com. A cluster without egress to it gets Grafana without logs.
   The alternative is baking the plugin into an init container image the
   socle publishes, which makes the socle an image publisher.
5. **Kubernetes dashboards.** *Decided, §5:* the socle's own, on
   OpenTelemetry names. The alternative was kube-state-metrics (chart 8.6.0)
   and node-exporter for the community dashboards, which duplicates what the
   collectors already collect.
6. **Helm 4.** Every OpenTelemetry chart now lists Helm 4.0+ as a
   prerequisite. The socle pins Flux v2.9.5; that its helm-controller is
   built on the Helm 4 SDK is expected, and verified by PR 2's e2e (the first
   OpenTelemetry chart) rather than assumed here.
7. **VictoriaTraces maturity.** Upstream's roadmap still lists "finalize the
   data structure and commit to backward compatibility" before GA. Off by
   default until it reaches GA; turning it on means accepting that an upgrade
   may drop stored traces.

## Sources

Read 28 September 2026.

- VictoriaMetrics: [chart index](https://victoriametrics.github.io/helm-charts/index.yaml) ·
  [OpenTelemetry ingestion](https://docs.victoriametrics.com/victoriametrics/integrations/opentelemetry/) ·
  [single-node flags](https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/) ·
  [enterprise features](https://docs.victoriametrics.com/victoriametrics/enterprise/) ·
  [vmbackup](https://docs.victoriametrics.com/victoriametrics/vmbackup/) ·
  [Grafana integration](https://docs.victoriametrics.com/victoriametrics/integrations/grafana/)
- VictoriaLogs: [overview and retention](https://docs.victoriametrics.com/victorialogs/) ·
  [OpenTelemetry ingestion](https://docs.victoriametrics.com/victorialogs/data-ingestion/opentelemetry/)
- VictoriaTraces: [overview](https://docs.victoriametrics.com/victoriatraces/) ·
  [OpenTelemetry ingestion](https://docs.victoriametrics.com/victoriatraces/data-ingestion/opentelemetry/) ·
  [querying](https://docs.victoriametrics.com/victoriatraces/querying/) ·
  [roadmap](https://docs.victoriametrics.com/victoriatraces/roadmap/)
- OpenTelemetry: [chart index](https://open-telemetry.github.io/opentelemetry-helm-charts/index.yaml) ·
  [collector chart](https://github.com/open-telemetry/opentelemetry-helm-charts/blob/main/charts/opentelemetry-collector/README.md) ·
  [target allocator chart](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-target-allocator) ·
  [kube-stack chart](https://github.com/open-telemetry/opentelemetry-helm-charts/blob/main/charts/opentelemetry-kube-stack/README.md) ·
  [otelcol-k8s manifest](https://github.com/open-telemetry/opentelemetry-collector-releases/blob/main/distributions/otelcol-k8s/manifest.yaml)
- Grafana: [chart migration notice](https://github.com/grafana/helm-charts/blob/main/charts/grafana/README.md) ·
  [grafana-community chart index](https://grafana-community.github.io/helm-charts/index.yaml) ·
  [chart values](https://github.com/grafana-community/helm-charts/blob/main/charts/grafana/values.yaml) ·
  [VictoriaLogs plugin](https://grafana.com/api/plugins/victoriametrics-logs-datasource)
- Cilium: [metrics](https://github.com/cilium/cilium/blob/main/Documentation/observability/metrics.rst)
- [prometheus-community chart index](https://prometheus-community.github.io/helm-charts/index.yaml) (kube-state-metrics, prometheus-operator-crds)
