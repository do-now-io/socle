# Catalog module `otel_gateway` — the cluster-level collector

The third module of the monitoring stack (#43, design in
[`docs/monitoring.md`](../monitoring.md)): the OpenTelemetry Collector as a
one-replica Deployment, for what lives in the cluster rather than on a node.
It has three inputs: the state of Kubernetes objects from the API server, the
Prometheus endpoints of annotated pods, and the applications' own OTLP. It
writes to [`victoria_metrics`](victoria-metrics.md). Kubernetes events and
application logs and traces join it with `victoria_logs` and
`victoria_traces`. It is the same chart as [`otel_agent`](otel-agent.md) in
another mode, and the module follows the same contract.

| Question | Position |
| --- | --- |
| What | `opentelemetry-collector` **0.173.1** (collector 0.160.0, `otelcol-k8s`), `mode: deployment`, one replica, one `HelmRelease` in namespace `otel-gateway` |
| Where | Every cloud, the same template, no cloud patch |
| Default | **On** |
| Object state | `k8s_cluster` every 10 s: Deployments, DaemonSets, StatefulSets, ReplicaSets, Jobs, pods, containers, nodes, namespaces |
| Scraping | Every running pod annotated `prometheus.io/scrape: "true"`, on the port and path its annotations name, every 30 s; plus the collector's own telemetry |
| OTLP in | **`otel-gateway.otel-gateway.svc:4317`** (gRPC) and **`:4318`** (HTTP), metrics only in this PR |
| Enriches | `k8s_attributes`: an application's OTLP gets its workload, namespace and labels, matched by connection IP |
| Exports | OTLP/HTTP to VictoriaMetrics when `victoria_metrics` is on, `nop` otherwise — the agent's rule |
| Exposure | `ClusterIP` only; no hostPort (the chart sets those in daemonset mode only) |
| Dashboard | **Kubernetes / Workloads**, shipped by this module |
| Client surface | `values` and `values_secret`; no named attribute — every knob is chart configuration |

## What is installed

> **With `victoria_logs` on**, the gateway also watches Kubernetes events
> (`k8sobjects` on `events.k8s.io`) and takes the applications' OTLP logs,
> both exported to VictoriaLogs: [victoria-logs.md](victoria-logs.md).

The same six objects as `otel_agent`, each under the reconcile toggle on
`inputs.modules.otel_gateway.enabled`: `Namespace/otel-gateway`, the chart's
`OCIRepository`, `ConfigMap/otel-gateway-socle-values`,
`ConfigMap/otel-gateway-client-values` (both labelled
`reconcile.fluxcd.io/watch: Enabled`), `HelmRelease/otel-gateway` with no
`spec.values`, and `Kustomization/otel-gateway-dashboards` applying
`oci/catalog/otel-gateway/dashboards/` from the artifact. In deployment mode
the chart names its objects from `fullnameOverride` with no suffix: the
Deployment, the Service and the collector's ConfigMap are all `otel-gateway`.

The socle's values, where they differ from the agent's:

| Value | Setting | Why |
| --- | --- | --- |
| `mode`, `replicaCount` | `deployment`, `1` | One view of the cluster. Two replicas would report every object twice unless `k8s_cluster` ran under a leader election, which the chart turns on with more than one replica — a client who wants HA sets `replicaCount` and gets it |
| `presets.clusterMetrics` | on | `k8s_cluster` and its RBAC (read on every object kind it reports) |
| `presets.kubernetesAttributes` | on | For the applications' OTLP. Its RBAC (pods, list and watch) is also what the pod discovery reads |
| `ports` | `otlp`, `otlp-http` kept; Jaeger and Zipkin off | OTLP is the only protocol the socle takes in |
| `config.receivers.prometheus` | two jobs: the collector itself, and `kubernetes-pods` | Below |
| `resources` | requests 100m / 128Mi, **limit 1Gi memory** | Measured at 45–50Mi on one node; the request leaves room for a bigger cluster. A limit, as the agent, for `GOMEMLIMIT` and `memory_limiter`; larger, because this one replica carries the whole cluster's object state, every scrape and every application's OTLP |

### The pod discovery

The `kubernetes-pods` job keeps a pod when `prometheus.io/scrape` is `"true"`
and it is running. It takes the scheme from `prometheus.io/scheme`, the path
from `prometheus.io/path` and the port from `prometheus.io/port`. The job also
writes three labels on every series it scrapes: **`k8s_namespace_name`,
`k8s_pod_name`, `k8s_node_name`**. Those are the names the kubelet and cluster
metrics carry once stored, so a single dashboard variable filters all of them.

The dollar signs of the relabelling (`$$1:$$2`) are doubled, because the
collector expands `$` in its configuration itself.

It is annotation-based in v1, as decided (`docs/monitoring.md` §2): no
`ServiceMonitor`, no target allocator. What is annotated today: VictoriaMetrics
(by its module), and whatever the client annotates; which other socle pods
upstream annotates is what the e2e's printed target list says (below). Cilium falls back to annotations while its ServiceMonitors are off.

## What the client may set — `kube.otel_gateway`

`enabled` (`true`), `values` (`{}`), `values_secret` (`""`), with the agent's
rules word for word:

- The same secret refusals, on the same chart. A literal authenticator
  token, password or client secret is refused. So are a literal
  `Authorization` or API-key header, a credential-named env literal, and a
  Secret among `extraManifests`. `${env:NAME}` read from a Secret is accepted.
- Lists are replaced, not merged. A client adding a receiver or an exporter
  writes the pipeline's whole list, the socle's entries included.

Typical additions: a second scrape job, a `filter` processor to drop a noisy
metric, an exporter to the client's own backend.

## The workloads dashboard

`oci/catalog/otel-gateway/dashboards/workloads.yaml`, `grafana_dashboard: "1"`,
written on the names VictoriaMetrics stores (the conversion the agent's e2e
measured):

| Panel | Reads |
| --- | --- |
| Nodes ready, pods running, pods neither running nor done | `k8s_node_condition_ready`, `k8s_pod_phase` (1 pending, 2 running, 3 succeeded, 4 failed, 5 unknown) |
| Scrape targets up; the targets over time | `up`, by `k8s_namespace_name` / `k8s_pod_name` |
| Deployments missing replicas | `k8s_deployment_desired - k8s_deployment_available > 0` |
| DaemonSets missing nodes | `k8s_daemonset_desired_scheduled_nodes - k8s_daemonset_ready_nodes > 0` |
| StatefulSets missing pods | `k8s_statefulset_desired_pods - k8s_statefulset_ready_pods > 0` |
| Container restarts, top 10 | `k8s_container_restarts` |
| CPU and memory requested, by namespace | `k8s_container_cpu_request`, `k8s_container_memory_request_bytes` |

The "missing" panels are empty when everything is whole, which is the point.
The e2e checks every name against VictoriaMetrics, as for the agent's
dashboard.

## Per cloud

Nothing in the template. On GKE Autopilot the one replica is billed by its
requests; on every cloud, the Service is `ClusterIP` and exposure is not
this module's.

## Measured

**Render and merge, locally** (`flux-operator build rset` 0.60.0,
`helm template` of the pinned chart):

- receivers `k8s_cluster`, `otlp`, `prometheus`;
- processors `k8s_attributes`, `memory_limiter`, `batch`;
- exporter `otlp_http/victoria-metrics`, or `nop` with `victoria_metrics` off;
- one `metrics` pipeline, no leader-election extension at one replica;
- the relabelling reaching the collector as `$$1:$$2`;
- a Service on 4317 and 4318, and container ports with no `hostPort`;
- with the sample's client `resources.requests.memory: 320Mi`: requests
  `cpu: 100m, memory: 320Mi`, limit `1Gi`.

`tofu test`: 120 runs, 6 of them for this module (the validation block is the
agent's, so the cases cover the paths the agent's do not: an OAuth2 client
secret and an `X-API-Key` header).

**e2e** (floci k3s, `ubuntu-latest` runner) — run
<https://github.com/do-now-io/socle/actions/runs/36687646353> (attempt 2),
tag `0.0.0-feat-catalog-otel-gateway.ceedef3`, both jobs green:

| Job | Step | Measured |
| --- | --- | --- |
| both | `resourceset/otel-gateway` Ready, Deployment rolled out | **1–2 s** after the agent |
| both | `k8s_deployment_available` in VictoriaMetrics | 15 series, 1–2 s later |
| both | a scraped annotated pod, `vm_app_version{k8s_namespace_name="victoria-metrics"}` | 2–3 s later |
| both | scrape targets `up` | the five Flux controllers and the operator, both collectors, podinfo and VictoriaMetrics — **Flux annotates its pods**, podinfo too |
| both | an OTLP gauge posted by podinfo | read back as `socle_e2e_otlp_probe`, **enriched with `k8s_namespace_name=hello`, `k8s_deployment_name=podinfo`** by `k8s_attributes` |
| both | the workloads dashboard | all twelve metrics with series (16 Deployments, 21 pods, 26 containers, one DaemonSet, one StatefulSet — argocd's controller) |
| `e2e-aws-root` | live resources, `tests/floci.tfvars` setting 320Mi | `requests: cpu 100m, memory 320Mi; limits: memory 1Gi`, the socle's siblings kept |
| both | `kubectl top` | the gateway **5–6m CPU, 45–50Mi**; VictoriaMetrics under both collectors 10–14m, **~150Mi**. The socle's 256Mi request was lowered to 128Mi after this run |
| `e2e-aws-catalog` | `victoria_metrics` disabled | pipeline ends in `nop` **1 s** later |
| `e2e-aws-catalog` | `victoria_metrics` re-enabled | `k8s_deployment_available` back in the new storage 9 s later |
| `e2e-aws-catalog` | disabled with the agent, then re-enabled | HelmRelease and dashboards Kustomization NotFound; Ready again with the dashboard after **77 s** |

**e2e, through Chainsaw** (`tests/e2e/chainsaw-test.yaml`, since the e2e moved
into the modules — `docs/flux-catalog.md` §8). The table above is the bash phase
this module shipped with; the same proof now runs on every push in the `root`
job (`health`) and the module's own job (`health`, then `module`): `otel-gateway-health` asserts `k8s_deployment_available`, the scraped `vm_app_version` of the annotated victoria-metrics pod, an OTLP gauge posted by podinfo read back enriched with `k8s_namespace_name=hello`, `k8s_deployment_name=podinfo`, and every metric of the workloads dashboard; `otel-gateway-module` patches the memory request (320Mi over 128Mi, 100m and 1Gi kept), then off and on.

Jobs: `e2e-aws-root` 3m13s, `e2e-aws-catalog` 13m53s.

**Two probes that did not work, kept here so nobody tries them again.** The
API server's service proxy delivers `kubectl create --raw` with a content
type the OTLP receiver refuses (415). A `kubectl port-forward` dials the
pod's `localhost`, while the chart binds the receivers to the pod IP.
podinfo, which ships `curl`, sends from inside the cluster instead, and that
also proves the enrichment. The first attempt of this run failed on
`argocd-redis`, which pulls from `ecr-public.aws.com` and hit
`ErrImagePull`; a re-run of the failed jobs passed.

## Open questions for the coordinator

1. **One replica.** A restart loses the OTLP an application sends during it.
   Two replicas plus the chart's leader election for `k8s_cluster` is a
   client's `values` away; the default stays small.
2. **Scraping at scale.** One replica scrapes every annotated pod. The target
   allocator (`docs/monitoring.md` §10, question 2) is also what would shard
   that the day one replica is not enough.
