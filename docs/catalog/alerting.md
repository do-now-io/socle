# Catalog module `alerting` — vmalert and Alertmanager

The alerting layer of the monitoring stack (#43, design in
[`docs/monitoring.md`](../monitoring.md)), left out of the stack's v1 on
purpose and taken up by #59. Without it the stack stores and shows everything
and tells no one when something breaks. **vmalert** evaluates rules against
[`victoria_metrics`](victoria-metrics.md) and writes their state back;
**Alertmanager** groups, silences and routes what fires to the client's
receivers. A rule travels with the module whose metrics it reads, as a
dashboard does: a ConfigMap labelled `vmalert_rules`, which a sidecar beside
vmalert picks up in every namespace.

*Design note, written before the module. Everything under **Measured** is still
to measure; what is stated elsewhere comes from the chart's templates and
values and from the vmalert and Alertmanager documentation, read at the
versions the module pins.*

| Question | Position |
| --- | --- |
| What | The official `victoria-metrics-alert` chart, from the project's OCI registry (`oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-alert`), pinned exactly. It installs vmalert and, with `alertmanager.enabled`, Alertmanager: one `HelmRelease` in namespace `alerting` |
| One module, not two | The chart ships both, and in the socle neither is useful alone: vmalert without Alertmanager tells no one, Alertmanager without vmalert receives nothing. A client with an Alertmanager of their own turns the chart's off and points vmalert at it (below) |
| Scope | **Per cluster**, meant for production clusters. No central Alertmanager: each cluster is self-contained, the scope `docs/monitoring.md` sets |
| Where | Every cloud, the same template, no cloud patch. No cloud access: no role, no Crossplane |
| Default | **Off.** On, it requires a receiver and the watchdog's destination, which only the client knows; on by default, every cluster's plan would be refused |
| Needs | **`victoria_metrics`**, refused at plan without it: without a datasource no rule can ever fire, and silence would read as "all is well" |
| Rules | Plain vmalert rule files in **ConfigMaps labelled `vmalert_rules: "1"`**, from any namespace, gathered by a sidecar into vmalert's rule directory. No VictoriaMetrics operator, no `VMRule` |
| Who ships rules | **Each module, for what it measures**, as it ships its dashboard; the client the same way, from their own namespaces. `values` tune vmalert, they do not carry rules |
| Receivers | The **routing plan** (`receivers`, `route`) in the client's OpenTofu, checked at plan; the **keys** in a Secret, mounted as files, read through Alertmanager's `*_file` fields. A literal key in the plan is refused |
| Watchdog | An always-firing rule, shipped by the socle, routed to a **dead man's switch** outside the cluster. Its destination is required, unless the client writes `watchdog = false` |
| Grafana | Alertmanager added as a Grafana datasource when this module is on. Grafana-managed alert rules: to decide after measuring (below) |
| Replicas | One vmalert, one Alertmanager |
| Client surface | `watchdog`, `receivers`, `route`, `receivers_secret`, plus `values` and `values_secret` as every module |

## What is installed

One `ResourceSet` (`oci/catalog/alerting/resourceset.yaml`),
`resourcesTemplate`, each object carrying the reconcile toggle on
`inputs.modules.alerting.enabled`:

1. `Namespace/alerting`.
2. **`ClusterRole/alerting-rules`**: `get`, `watch` and `list` on
   `configmaps`, nothing else, and its `ClusterRoleBinding` to vmalert's
   ServiceAccount. The chart has no RBAC of its own, and the sidecar needs to
   read ConfigMaps across the cluster. Same reasoning as grafana's
   `ClusterRole/grafana-dashboards`: ConfigMaps, never Secrets.
3. `OCIRepository/victoria-metrics-alert-chart`, pinned exactly.
4. `ConfigMap/alerting-socle-values` and
5. `ConfigMap/alerting-client-values`, both labelled
   `reconcile.fluxcd.io/watch: Enabled`.
6. `HelmRelease/alerting`: no `spec.values`; `valuesFrom` = socle, client,
   then the client's Secret when named (`optional: true`).
7. `Kustomization/alerting-rules` in `flux-system`: applies
   `oci/catalog/alerting/rules/` from the socle artifact into `alerting` — the
   watchdog and the stack's own health (below). The shape of otel_agent's
   dashboards Kustomization.

### How rules reach vmalert

- The chart reads rules from **one ConfigMap**, its own, and has no sidecar.
  It does accept `server.extraContainers`, `extraVolumes` and
  `extraVolumeMounts`.
- The socle adds the **same sidecar Grafana runs** (`k8s-sidecar`):
  `LABEL=vmalert_rules`, `LABEL_VALUE=1`, `NAMESPACE=ALL`,
  `RESOURCE=configmap`, writing every matching ConfigMap's keys into an
  `emptyDir` shared with vmalert.
- vmalert reads that directory through a wildcard (`-rule=/rules/*.yaml`) and
  re-reads it on `-configCheckInterval`, its own hot reload.
- **A bad file.** vmalert's documentation states that a reload that fails to
  parse keeps the previous configuration, logs the error and sets
  `vmalert_config_last_reload_successful` to `0`. So one client's broken file
  would freeze every rule change, the socle's included, until it is fixed. What
  happens at **start**, with a broken file already in the directory, is not
  documented there, and is the first thing to measure. The socle's own rules
  alert on `vmalert_config_last_reload_successful == 0`.

### Who ships which rule

A rule lives in the module whose metrics it reads, so turning a module off
removes its rules with its dashboard. The baseline, on the names VictoriaMetrics
stores from OpenTelemetry (no kube-state-metrics, no node-exporter: #45):

| Rule | Reads | Ships in |
| --- | --- | --- |
| Watchdog, always firing | `vector(1)` | `alerting` |
| A rule file did not load | `vmalert_config_last_reload_successful` | `alerting` |
| Notifications failing | `alertmanager_notifications_failed_total` | `alerting` |
| Pod crash-looping | `k8s_container_restarts` | `otel_gateway` (`k8s_cluster`) |
| Pod pending too long | `k8s_pod_phase` (1 = pending) | `otel_gateway` |
| Node not ready | `k8s_node_condition_ready` | `otel_gateway` |
| Deployment missing replicas | `k8s_deployment_desired`, `k8s_deployment_available` | `otel_gateway` |
| Node filesystem nearly full | `k8s_node_filesystem_usage_bytes`, `k8s_node_filesystem_capacity_bytes` | `otel_agent` (`kubeletstats`) |
| VictoriaMetrics down, disk nearly full | its own scraped metrics | `victoria_metrics` |

Each module's rules are a ConfigMap under `oci/catalog/<module>/rules/`,
applied by a Kustomization under that module's toggle. With `alerting` off they
are inert, as a dashboard is with `grafana` off.

Not in the baseline yet, each for a reason the collectors give:

- **Memory and disk pressure.** `k8s_cluster` reports only the `Ready`
  condition unless `node_conditions_to_report` names more: a change to
  `otel_gateway`.
- **PersistentVolumeClaim nearly full.** The volume metrics are a
  `kubeletstats` group the agent does not collect today: a change to
  `otel_agent`.
- **A Flux Kustomization or HelmRelease not Ready.** The readiness metric
  Flux documents comes from kube-state-metrics, which #45 refuses. The source
  to use instead (the Flux Operator's own metrics, or the scraped controllers)
  is still to find.
- **The bootstrap components down** (Cilium, CoreDNS): they live outside the
  catalog, and whether they are scraped at all is still to check.

### The socle's values

| Value | Setting | Why |
| --- | --- | --- |
| `server.datasource.url` | `http://victoria-metrics.victoria-metrics.svc:8428` | Where every rule is evaluated |
| `server.remoteWrite.url`, `server.remoteRead.url` | the same | vmalert writes its alerts' state back and reads it at start, so a restart does not reset every `for:` timer |
| `server.extraArgs.rule` | `/rules/*.yaml` | The sidecar's directory, instead of the chart's single ConfigMap |
| `server.extraArgs.configCheckInterval` | to measure | How soon a new or changed rule is live |
| `server.extraContainers`, `extraVolumes`, `extraVolumeMounts` | the sidecar and the shared `emptyDir` | Above |
| `alertmanager.enabled` | `true` | The chart then points vmalert at its own Alertmanager by itself |
| `alertmanager.config` | rendered from `receivers`, `route` and the watchdog | Below |
| `alertmanager.extraVolumes`, `extraVolumeMounts` | `receivers_secret`, read-only, at `/etc/alertmanager/secrets/` | Where the `*_file` fields point |
| pod annotations | `prometheus.io/scrape` on both | So `otel_gateway` scrapes their own metrics, which the stack's health rules read |
| `resources` | to measure | |

## What the client may set — `kube.alerting`

| Attribute | Default | Type | Meaning |
| --- | --- | --- | --- |
| `enabled` | `false` | bool | On requires `victoria_metrics`, a receiver and, unless `watchdog = false`, `receivers_secret` |
| `watchdog` | `true` | bool | Route the always-firing Watchdog to the dead man's switch whose URL is the `watchdog-url` key of `receivers_secret`. `false` is a choice made in the open, visible in review |
| `receivers` | `[]` | list | Alertmanager receivers, as Alertmanager writes them (`slack_configs`, `pagerduty_configs`, `webhook_configs`, …), keys as `*_file` only |
| `route` | `{}` | object | Alertmanager's routing tree. `route.receiver`, the default, must name one of `receivers` |
| `receivers_secret` | `""` | string | Name of a Secret in `alerting`, created by the client, holding the keys. Mounted as files under `/etc/alertmanager/secrets/` |
| `values` | `{}` | object | Any value of the chart: vmalert's flags, resources, Alertmanager's retention or storage. Merged over the socle's, the client's winning |
| `values_secret` | `""` | string | Name of a Secret in `alerting` with a `values.yaml` key. Merged last |

**Why the routing plan is a named attribute, not `values`.** The socle adds
the watchdog's receiver and route to the client's. Helm replaces lists: a
client writing `alertmanager.config.receivers` in `values` would drop the
watchdog's. So OpenTofu renders `alertmanager.config` from `receivers`,
`route` and the watchdog, and `values` may not set `alertmanager.config`.

**A client with an Alertmanager of their own** sets `alertmanager.enabled: false`
and `server.notifier.url` in `values`. `receivers`, `route` and the watchdog
then do not apply, and their Alertmanager carries the watchdog's route.

```hcl
kube = {
  victoria_metrics = { enabled = true }
  alerting = {
    enabled          = true
    receivers_secret = "alerting-keys"   # keys: slack-url, pagerduty-key, watchdog-url
    receivers = [
      { name = "team", slack_configs = [{ api_url_file = "/etc/alertmanager/secrets/slack-url", channel = "#alerts" }] },
      { name = "on-call", pagerduty_configs = [{ routing_key_file = "/etc/alertmanager/secrets/pagerduty-key" }] },
    ]
    route = {
      receiver = "team"
      routes   = [{ receiver = "on-call", matchers = ["severity=\"critical\""] }]
    }
  }
}
```

### Refused at plan

- `enabled` without `victoria_metrics.enabled`.
- `enabled` with no receiver, or a `route.receiver` that names none of them,
  or names `devnull` (the chart's default receiver, which drops everything).
- A receiver named `watchdog`: the socle's.
- `watchdog` on with no `receivers_secret`.
- **A literal key in `receivers`**: `api_url`, `api_key`, `routing_key`,
  `service_key`, `auth_password`, `auth_secret`, `url`, `webhook_url`,
  `token`, `bot_token`, and an `http_config` `password`, `credentials` or
  `client_secret`. Each has its `*_file` twin, which is accepted. Everything in
  the plan lands in the OpenTofu state, often in Git through a `.tfvars`, and in
  the cluster's input ConfigMap; a Slack webhook URL is a key, and whoever holds
  it posts in the on-call channel as the cluster.
- `alertmanager.config` in `values` (above).

What `values_secret` holds, OpenTofu never reads: a client who rewrites
Alertmanager's configuration there takes these checks off themselves.

### The watchdog

- The rule `Watchdog`, `expr: vector(1)`, ships in `oci/catalog/alerting/rules/`.
- The socle prepends a route `alertname="Watchdog"` → receiver `watchdog`, a
  `webhook_configs` with `url_file: /etc/alertmanager/secrets/watchdog-url`,
  repeated every few minutes; the client sets their dead man's switch
  (Healthchecks.io, or their on-call platform's heartbeat) to expect it at that
  period.
- If vmalert, Alertmanager, VictoriaMetrics or the node under them dies, the
  pings stop, and the service outside the cluster raises the alarm. Nothing
  inside the cluster can: the stack shares the fate of what it watches.
- The Secret is mounted without `optional`, so a missing `receivers_secret`
  keeps Alertmanager from starting and the release from becoming Ready, rather
  than silently dropping the watchdog. What a missing **key** does is to
  measure.

## Grafana

- The `grafana` module adds an **Alertmanager datasource** under
  `<< if inputs.modules.alerting.enabled >>`, as it adds VictoriaMetrics today.
- **Grafana-managed rules are not where rules live**: they would live outside
  Git, in Grafana's SQLite on an `emptyDir` (lost at each restart,
  [grafana.md](grafana.md)), and could notify through Grafana's own contact
  points, around the receiver checks and the watchdog.
- **How to refuse them is open.** Grafana has no switch for "show
  Alertmanager, refuse local rules":
  - `unified_alerting.enabled: false` removes Grafana alerting entirely —
    probably the views of the Alertmanager datasource too, which would make
    that datasource pointless;
  - `unified_alerting.allowed_integrations: prometheus-alertmanager` keeps the
    views and limits Grafana's contact points to an Alertmanager, ours; a
    hand-made rule is still possible, still lost at restart.
  Decided after measuring what each shows.

## Per cloud

Nothing. No volume (`emptyDir` for the rules, Alertmanager's state on its own
volume only if the client sets `alertmanager.persistentVolume`), no cloud
identity.

## Measured

Nothing yet. To measure on floci, in this order:

1. **A broken rule file**, at reload and at start: does vmalert keep running,
   keep the previous rules, refuse to start?
2. **Grafana** with `unified_alerting.enabled: false`, then with
   `allowed_integrations`: what the Alertmanager datasource still shows.
3. **The proof of #59**: a crash-looping pod fires, reaches a webhook receiver
   inside the cluster, and resolves.
4. **The watchdog**: reaches its webhook every period; stops when vmalert is
   scaled to zero. A missing `receivers_secret`, a missing `watchdog-url` key.
5. **Hot reload**: time from a new labelled ConfigMap to its rule being live;
   a ConfigMap deleted, its rule gone.
6. **A module off**: `otel_gateway` disabled, its rules gone from vmalert.
7. Resources of vmalert, the sidecar and Alertmanager, for the requests.

## Left out of v1

- **Log-based rules.** vmalert evaluates `vlogs` rules against VictoriaLogs,
  but one vmalert reads one datasource: log rules need a second vmalert, a
  follow-up once `victoria_logs` users ask.
- **High availability**: two Alertmanagers in a cluster, two vmalerts.
- **Silences surviving a restart**: they live in Alertmanager's state, lost
  with the pod unless the client sets `alertmanager.persistentVolume`.
- **Recording rules** shipped by the socle: none needed by the baseline.
- **A central Alertmanager** across clusters: the client's own Alertmanager
  path above leaves the door open.
