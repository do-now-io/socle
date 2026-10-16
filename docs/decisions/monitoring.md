---
title: monitoring decisions
description: The decisions behind the monitoring module, one per section, each with its status.
sidebar:
  order: 10
---

The monitoring stack is one chart, victoria-metrics-k8s-stack, as one module;
vmagent is the one place metrics are scraped, and the alert rules are
upstream's, fetched at pinned tags. It replaces the victoria-metrics,
victoria-logs, victoria-traces, grafana and alerting modules of 0.1, whose
decisions still holding are restated below (MONITORING-05 to -12). The
stack-wide decision is [SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud).

## MONITORING-01: One stack chart, one module

**accepted** · 2026-10-12 · [`oci/catalog/monitoring/resourceset.yaml`](../../oci/catalog/monitoring/resourceset.yaml), [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf)

**Context.** A managed cluster needs, from the day alerting is on, what
kube-prometheus-stack installs: the rules and dashboards of
kube-prometheus, on kube-state-metrics, node-exporter and cAdvisor. #91 first
translated awesome-prometheus-alerts by hand onto OpenTelemetry's names: about
50 rules, a dozen upstream rules with no source, and every rule the socle's to
maintain. victoria-metrics-k8s-stack is VictoriaMetrics' equivalent of
kube-prometheus-stack: the operator, the storage, vmagent, vmalert,
Alertmanager, Grafana, kube-state-metrics and node-exporter in one release,
with kube-prometheus' rules adapted to them. A catalog module is one key, one
folder, one ResourceSet and one e2e suite, which CI checks; five modules over
one release would break that.

**Decision.** One module, `monitoring`, renders one
`victoria-metrics-k8s-stack` release in the `monitoring` namespace. Its
parts are nested attributes (`metrics`, `logs`, `traces`, `grafana`,
`alerting`), each switching the chart's own `enabled`; `values` are the
chart's.

**Consequences.** Parts move
together with one chart version. Nested attributes are checked at plan like
modules (unknown key, wrong type) and merged one level deep.

**Sources.** #91; the victoria-metrics-k8s-stack chart 0.95.2; measured on
k3s, 2026-10-12.

## MONITORING-02: vmagent is the one place metrics are scraped

**accepted** · 2026-10-12 · [`oci/catalog/monitoring/resourceset.yaml`](../../oci/catalog/monitoring/resourceset.yaml), [`oci/catalog/otel-gateway/resourceset.yaml`](../../oci/catalog/otel-gateway/resourceset.yaml), [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml)

**Context.** The upstream rules select on `job` and `instance` as Prometheus
scrapes write them (`job="kube-state-metrics"`, `job="kubelet"`,
`metrics_path="/metrics/cadvisor"`). Through an OpenTelemetry collector and
OTLP, those become `service_name` and `service_instance_id` (measured on the
collectors' own metrics), and no rule matches. Keeping `k8s_cluster` and
`kubeletstats` beside the stack's sources would collect the same state
twice.

**Decision.** vmagent scrapes the kubelets, cAdvisor, kube-state-metrics,
node-exporter, the stack, and every pod annotated `prometheus.io/scrape`,
with `job` from its `app.kubernetes.io/name`. The collectors carry OTLP only:
otel-gateway the applications' and the Kubernetes events, otel-agent the
containers' logs; their own telemetry is scraped by annotation. The
kubelet's API server and etcd families are dropped at the scrape.

**Consequences.** One collection layer for metrics, one for OTLP, nothing
collected twice. Supersedes
[OTEL-GATEWAY-01](otel-gateway.md#otel-gateway-01-scraping-by-annotation-no-servicemonitor),
[OTEL-GATEWAY-04](otel-gateway.md#otel-gateway-04-what-the-alert-rules-read-from-k8s_cluster-and-both-collectors-health-in-one-place),
[OTEL-AGENT-02](otel-agent.md#otel-agent-02-the-kubelet-call-skips-certificate-verification)
and [OTEL-AGENT-05](otel-agent.md#otel-agent-05-volume-metrics-for-the-claims-only-their-name-from-the-kubelets-pod-list),
and the translation onto OpenTelemetry's names of #91's first commits. 38,000
series on an empty two-node k3s, 55,000 before the drop (measured).

**Sources.** The chart's `kubelet.vmScrape` and its rules' `labelRewrites`;
measured on k3s, 2026-10-12.

## MONITORING-03: The rules from upstream, at pinned tags

**accepted** · 2026-10-12 · [`oci/catalog/monitoring/resourceset.yaml`](../../oci/catalog/monitoring/resourceset.yaml)

**Context.** The chart does not carry its rules: a sync job downloads them at
install, from the `main` and `master` branches of kube-prometheus and the
VictoriaMetrics repositories, and writes them as `VMRule`s. Unpinned, two
installs of one socle version could load different rules.

**Decision.** Every source the chart reads is pinned to a tag: kube-prometheus
v0.19.0, VictoriaMetrics v1.154.0, operator v0.75.0, VictoriaLogs v1.53.0,
VictoriaTraces v0.10.0, the versions the chart runs. The groups that read the
control plane are off with its scrape. The socle's own rules, Flux and the
collectors, are `VMRule`s in their modules, checked with `vmalert -dryRun` in
CI. `defaultRules.sources` is refused in `values`.

**Consequences.** A cluster needs egress to raw.githubusercontent.com, or
loads no upstream rule and no dashboard. Renovate does not see tags in URLs:
they move with the chart, by hand, in the same change. vmalert selects every
`VMRule`; the operator's webhook refuses one that does not parse, so a
client's typo silences nothing else.

**Sources.** The chart's `defaultRules.sources` and sync job v0.0.17; the
operator's admission webhook.

## MONITORING-04: Upstream severities, info to null

**accepted** · 2026-10-12 · [`oci/catalog/monitoring/resourceset.yaml`](../../oci/catalog/monitoring/resourceset.yaml)

**Context.** ALERTING-05 recast every rule's severity by a socle rule
(`critical` only for a node or data lost). Recasting upstream's 158 alerts
would make them the socle's again. kube-prometheus marks with `info` what only
helps read a warning, and ships `InfoInhibitor` to mute it.

**Decision.** Upstream's severities as written. Alertmanager's
configuration, built from the client's `route`, puts first the Watchdog's
route, then `severity=~"info|none"` to a `null` receiver; a `critical` alert
inhibits the `warning` of the same `cluster`, `namespace` and `alertname`.

**Consequences.** `critical` pages where upstream judges it does. A client
mutes one alert with a route to `null`. Supersedes the severity rule of
ALERTING-05.

**Sources.** kube-prometheus v0.19.0 rules; Alertmanager v0.34.0
configuration reference.

## MONITORING-05: Numeric flags as strings

**accepted** · 2026-10-12 · [`oci/catalog/monitoring/resourceset.yaml`](../../oci/catalog/monitoring/resourceset.yaml)

**Decision.** The socle writes every numeric flag as a string
(`storage.maxHourlySeries: "100000"`) and tells the client to do the same; the
plan does not refuse a number. Restates VICTORIA-METRICS-02 of 0.1.

**Context.** Helm renders `1000000` as `1e+06`, which an integer flag refuses
at start; below a million a number renders as written.

**Consequences.** A large number gives a pod that does not start, with the
flag's error in its log.

**Sources.** `helm template` of the pinned chart; the flag's type in
VictoriaMetrics v1.153.0.

## MONITORING-06: A cardinality guard of 100 000 new series an hour, labels sorted

**accepted** · 2026-10-12 · [`oci/catalog/monitoring/resourceset.yaml`](../../oci/catalog/monitoring/resourceset.yaml)

**Decision.** `-storage.maxHourlySeries=100000` with `-sortLabels`,
overridable through `values`. Restates VICTORIA-METRICS-03 of 0.1.

**Context.** Storage is local: a label explosion means a full disk or
exhausted memory, not a bill. The guard counts a series by its labels in the
order they arrive; OTLP varies that order, and unsorted it counted one series
many times and dropped fresh data within minutes (measured, 2026-10-07).

**Consequences.** Past the limit, new series are dropped with a log line;
existing series keep being written. The stack's own rules alert as it
nears.

**Sources.** VictoriaMetrics single-node flags documentation.

## MONITORING-07: The routing plan in OpenTofu, the keys in a Secret

**accepted** · 2026-10-12 · [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf), [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf)

**Decision.** `alerting.receivers` and `alerting.route` are attributes,
checked at plan. Keys are files from `receivers_secret`, mounted at
`/etc/alertmanager/secrets/` and read through Alertmanager's `*_file`
fields; a literal key is refused, and so is Alertmanager's configuration in
`values`. Restates ALERTING-03 of 0.1.

**Context.** The socle prepends its receivers and routes, and Helm replaces
lists. The plan lands in the OpenTofu state; a Slack webhook URL is a key.

**Consequences.** What `values_secret` holds, OpenTofu never reads: a client
rewriting Alertmanager's configuration there takes these checks off
themselves.

**Sources.** Alertmanager configuration reference, v0.34.0.

## MONITORING-08: A watchdog to a dead man's switch, on by default

**accepted** · 2026-10-12 · [`oci/catalog/monitoring/resourceset.yaml`](../../oci/catalog/monitoring/resourceset.yaml)

**Decision.** kube-prometheus' always-firing `Watchdog`, routed first to the
URL in the `watchdog-url` key of `receivers_secret`. Required unless the
client writes `watchdog = false`. The Secret is mounted without `optional`.
Restates ALERTING-04 of 0.1.

**Context.** The stack shares the fate of what it watches: with
VictoriaMetrics down every rule fails and nothing fires. Only a service
outside the cluster can notice the pings stopping.

**Consequences.** A ping every 6 minutes: Alertmanager checks the 5-minute
`repeat_interval` at its 1-minute `group_interval` (measured). A missing
Secret keeps Alertmanager from starting rather than silently dropping the
watchdog.

**Sources.** #59, measured on floci 2026-10-07.

## MONITORING-09: Alerting off by default, traces too

**accepted** · 2026-10-12 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf)

**Decision.** `alerting.enabled` and `traces.enabled` default to `false`.
Restates ALERTING-01 and VICTORIA-TRACES-01 of 0.1.

**Context.** On by default, alerting would make every plan refused for want
of a receiver only the client knows. VictoriaTraces' roadmap still lists
committing to its storage format before GA.

**Consequences.** One vmalert and one Alertmanager when on, no high
availability; silences lost with the pod unless given a volume. Turning traces
on accepts that an upgrade may drop them.

**Sources.** #59; the VictoriaTraces roadmap, read 2026-09-28.

## MONITORING-10: Grafana reads ConfigMaps, never Secrets

**accepted** · 2026-10-12 · [`oci/catalog/monitoring/resourceset.yaml`](../../oci/catalog/monitoring/resourceset.yaml)

**Decision.** The module renders `ClusterRole/monitoring-grafana` (`get`,
`watch`, `list` on ConfigMaps only), Grafana binds to it
(`rbac.useExistingClusterRole`), and both sidecars, dashboards and
datasources, read `resource: configmap`. Restates GRAFANA-01 of 0.1.

**Context.** With a sidecar on, the grafana chart grants read on ConfigMaps
**and Secrets** cluster-wide, and no value narrows it. The stack's datasource
sidecar lists Secrets by default: measured, a 403 crash-loop under the
narrower role until told `configmap`.

**Consequences.** Grafana reads no Secret. A dashboard or datasource in a
Secret is not loaded.

**Sources.** The grafana chart 13.2.7 `templates/clusterrole.yaml`; measured
on k3s, 2026-10-12.

## MONITORING-11: The VictoriaLogs plugin downloaded at start

**accepted** · 2026-10-12 · [`oci/catalog/monitoring/resourceset.yaml`](../../oci/catalog/monitoring/resourceset.yaml)

**Decision.** While logs are on, Grafana's `plugins` list
`victoriametrics-logs-datasource@0.33.1`; Grafana downloads it at start, and
the chart provisions the VictoriaLogs datasource only when it is listed.
Restates GRAFANA-02 of 0.1.

**Context.** VictoriaLogs has no built-in datasource type, unlike metrics
(Prometheus) and traces (Jaeger). Baking the plugin in would mean a
socle-built image.

**Consequences.** Without egress to grafana.com, no logs datasource; metrics
and traces are unaffected.

**Sources.** The chart's `defaultDatasources` template; the VictoriaLogs
Grafana datasource 0.33.1.

## MONITORING-12: Each module brings its own monitoring, only while it is on

**accepted** · 2026-10-15 · [`.github/scripts/upstream-monitoring.sh`](../../.github/scripts/upstream-monitoring.sh), `oci/catalog/<module>/monitoring/`

**Decision.** A module with a workload exposes its metrics to vmagent (pod
annotations on a declared port, or a `VMServiceScrape` on the chart's
metrics Services where only HTTPS is served or where the dashboard filters
on the labels a Service scrape sets: Argo CD's `job="argocd-server-metrics"`,
External Secrets' `service`) and ships, under `monitoring/`, its alert rules and its dashboard,
applied by a `Kustomization` that is on only while the module and
`monitoring` both are. The rules come from awesome-prometheus-alerts when it
has a file for the module, copied as they are; the dashboard is the
project's own, or the most-used one on grafana.com when the project has
none. Both are pinned copies a script writes and CI checks against their
source, never edited. What awesome-prometheus-alerts lacks, the socle writes
in `rules.yaml`: the chart's own example alerts where it ships some (Kyverno,
Velero, KEDA), otherwise a few rules on metrics read on a live cluster.

**Context.** The stack's sync job could fetch the same files, but names each
`VMRule` after a rule group, and awesome-prometheus-alerts calls most of its
groups `EmbeddedExporter`: two sources would overwrite each other. A chart's
own `PrometheusRule` needs the prometheus-operator CRDs, which the socle does
not install, and the charts ship empty ones. Of the catalog,
awesome-prometheus-alerts covers Argo CD only (with Flux and the collector,
done earlier).

**Consequences.** A module turned off takes its rules and dashboard with
it; `monitoring` off leaves none. Bumping a source is a line in the script
and its `write`. Not covered: metrics-server has no dashboard or rule (only
its scrape); some of a dashboard's panels stay empty by nature (no sync
running, no ResourceQuota, a metric emitted on first use); podinfo (hello), kyverno-policies and gateway-api have no
workload of their own to watch. Cilium, installed by the bootstrap, is out
of this decision.

**Sources.** awesome-prometheus-alerts `dist/rules` at 822af1e; the
sync job's `ruleGroupVMRuleName` (VictoriaMetrics/helm-charts
`hack/sync-job/rules.go`); each chart's values at its pinned version; metric
names read on socle-dev, 2026-10-15, and every dashboard query evaluated
there: grafana.com 15038, external-dns' most-used dashboard, still reads the
`*_a_records` metrics 0.15 replaced, so the socle takes 23969.

## MONITORING-13: Requests on every container, disk included, on every cloud

**accepted** · 2026-10-16 · [`oci/catalog/monitoring/resourceset.yaml`](../../oci/catalog/monitoring/resourceset.yaml)

**Decision.** The socle's values state a cpu, a memory and an
ephemeral-storage request for every container the release runs: the
chart's (the operator, kube-state-metrics, node-exporter, Grafana and its
two sidecars, the sync job and the operator's cleanup hook) and those the
operator builds from its objects (`spec.resources` of VMSingle, VMAgent,
VLSingle, VTSingle, VMAlert, VMAlertmanager and the internal VMAuth, and
`spec.configReloaderResources` for the config-reloader and config-init
containers beside the last four: the operator's own 10m / 25Mi, stated with
64Mi of disk). Disk is 64Mi for a long-running container, 32Mi for a hook;
vmagent 256Mi, for the queue it keeps in an `emptyDir` while
VictoriaMetrics does not take its writes; Grafana 256Mi, for its SQLite
database, its search index and the VictoriaLogs plugin; VictoriaMetrics,
VictoriaLogs and VictoriaTraces 64Mi with a claim and **2Gi** with
`storage_size = ""`, their data then in an `emptyDir`. VictoriaMetrics asks
60m rather than 50m, and Grafana 80m, to stay within 6.5 GiB of memory a
vCPU.

**Context.** GKE Autopilot reserves, and bills, each pod from its requests;
a container that leaves one out gets 500m CPU, 2 GiB of memory and 1 GiB of
disk, and the disk request becomes the container's limit. Autopilot raises
the CPU of a pod above 6.5 GiB a vCPU. The operator adds its own defaults
only for a resource the object leaves out, and none for disk
(operator v0.75.0, `build.Resources`, `VM_CONFIG_RELOADER_REQUEST_*`).

**Consequences.** The same requests on every cloud; on EKS they only
schedule, and under DiskPressure the kubelet evicts first the pods furthest
over theirs. On Autopilot a pod past its disk request is evicted: a client
whose dashboards, queue or `emptyDir`-held data outgrow it raises it in
`values`. The disk figures are chosen, not measured; 2Gi promises no
retention, data to keep belongs on a claim.

**Sources.** [Resource requests in Autopilot](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests);
VictoriaMetrics operator v0.75.0 `internal/config/config.go` and
`internal/controller/operator/factory/build/container.go`; the
victoria-metrics-k8s-stack chart 0.95.2's values; GKE sandbox, 2026-10-07
(PR #84: every socle pod reserved 1 GiB of disk before).

## MONITORING-14: On gcp, no node-exporter, and Grafana health-checked on /api/health

**accepted** · 2026-10-16 · [`oci/clusters/gcp/monitoring/patch.yaml`](../../oci/clusters/gcp/monitoring/patch.yaml)

**Decision.** On gcp the module's cloud step sets
`prometheus-node-exporter.enabled: false` in `monitoring-cloud-values`; the
chart then leaves out node-exporter's rules and dashboard as well. A step
after `workload` adds `HealthCheckPolicy/grafana` while Grafana has a route:
GKE's load balancer checks `/api/health` on the serving port.

**Context.** node-exporter runs with `hostNetwork`, `hostPID` and the node's
root filesystem as a `hostPath`. Autopilot blocks host namespaces, except
for verified partners' containers, and admits a `hostPath` only under
`/var/log`, read-only: the DaemonSet would be refused and the release never
`Ready`. Google documents that Autopilot already collects node-exporter's
metrics for its nodes, for Managed Service for Prometheus — not for this
VictoriaMetrics. GKE's load balancer health-checks `/` and accepts only a
200; Grafana answers `/` with a 302 to `/login`, so without the policy the
backend is unhealthy and the route answers 502.

**Consequences.** On gcp the stack's node panels (node-exporter-full, the
nodes' CPU, memory, filesystem and network from `node_*`) are empty and no
node-exporter alert fires: node health is read in Cloud Monitoring. The
kubelets, cAdvisor and kube-state-metrics are still scraped.

**Sources.** [Autopilot security
measures](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-security)
(updated 2026-10-13); [Managed Service for Prometheus, Node
Exporter](https://docs.cloud.google.com/stackdriver/docs/managed-prometheus/exporters/node_exporter)
("These metrics are already enabled for nodes in GKE Autopilot clusters");
[Configure Gateway resources, health
check](https://cloud.google.com/kubernetes-engine/docs/how-to/configure-gateway-resources#configure_health_check);
the chart 0.95.2's `defaultRules` and `defaultDashboards`, keyed on
`prometheus-node-exporter.enabled`; Grafana's 502 behind the GKE Gateway,
sandbox, PR #84.
