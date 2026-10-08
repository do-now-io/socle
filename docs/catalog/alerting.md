# Catalog module `alerting` — vmalert and Alertmanager

The alerting layer of the monitoring stack (#43, design in
[`docs/monitoring.md`](../monitoring.md)), left out of the stack's v1 on
purpose and taken up by #59. Without it the stack stores and shows everything
and tells no one when something breaks. **vmalert** evaluates rules against
[`victoria_metrics`](victoria-metrics.md) and writes their state back;
**Alertmanager** groups, silences and routes what fires to the client's
receivers.

*Design note, written before the module. **Measured** is what was measured on
floci by hand; the rest comes from the charts and from the vmalert,
Alertmanager and Grafana documentation and source, at the pinned versions.*

## v1 in one paragraph

**The socle's rules only.** Infrastructure alerts — a pod crash-looping, a
node not ready, a disk filling, the stack's own health — are written by the
socle, live in this repository, are checked in CI before they are published,
and are evaluated by vmalert. **A client ships no rule file in v1.** Alerts
and silences are seen in Grafana, where a client *can* make a rule in the UI —
**unsupported: in v1 it notifies no one, and it is lost whenever Grafana's pod
is recreated** ([below](#grafana)).
The client's part is to say **where** alerts go — receivers and routes in
OpenTofu, keys in a Secret — and to give the watchdog a destination outside
the cluster. Application alerts are the v2: #82.

| Question | Position |
| --- | --- |
| What | The official `victoria-metrics-alert` chart, from the project's OCI registry (`oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-alert`), pinned exactly. It installs vmalert and, with `alertmanager.enabled`, Alertmanager: one `HelmRelease` in namespace `alerting` |
| One module, not two | The chart ships both, and neither is useful alone: vmalert without Alertmanager tells no one, Alertmanager without vmalert receives nothing |
| Scope | **Per cluster**, meant for production clusters. No central Alertmanager: each cluster is self-contained, the scope `docs/monitoring.md` sets |
| Where | Every cloud, the same template, no cloud patch. No cloud access: no role, no Crossplane |
| Default | **Off.** On, it requires a receiver and the watchdog's destination, which only the client knows; on by default, every cluster's plan would be refused |
| Needs | **`victoria_metrics`**, refused at plan without it: without a datasource no rule can ever fire, and silence would read as "all is well" |
| Who writes rules | **The socle only, in v1.** Each module ships the rules for what it measures, as it ships its dashboard |
| How rules reach vmalert | Plain vmalert rule files in **ConfigMaps labelled `vmalert_rules: "1"`**, gathered by a sidecar into vmalert's rule directory — **from the socle's own namespaces only**. A labelled ConfigMap anywhere else is ignored. No VictoriaMetrics operator, no `VMRule` |
| Rules checked | **In CI**, every rule file under `oci/catalog/*/rules/` through `vmalert -dryRun`: one bad file takes vmalert down (measured, below) |
| Receivers | The **routing plan** (`receivers`, `route`) in the client's OpenTofu, checked at plan; the **keys** in a Secret, mounted as files, read through Alertmanager's `*_file` fields. A literal key in the plan is refused |
| Watchdog | An always-firing rule, shipped by the socle, routed to a **dead man's switch** outside the cluster. Its destination is required, unless the client writes `watchdog = false` |
| Grafana | **The one interface**: an Alertmanager datasource, alerts and silences in Grafana's Alerting pages. A rule made in its UI is possible — **not supported: it notifies no one in v1, and is lost with the pod** (below) |
| Replicas | One vmalert, one Alertmanager |
| Client surface | `watchdog`, `receivers`, `route`, `receivers_secret`, plus `values` and `values_secret` as every module |

## What is installed

One `ResourceSet` (`oci/catalog/alerting/resourceset.yaml`),
`resourcesTemplate`, each object carrying the reconcile toggle on
`inputs.modules.alerting.enabled`:

1. `Namespace/alerting`.
2. **`ClusterRole/alerting-rules`**: `get`, `watch` and `list` on
   `configmaps`, nothing else, and its `ClusterRoleBinding` to vmalert's
   ServiceAccount. The chart has no RBAC of its own. Same grant as grafana's
   `ClusterRole/grafana-dashboards`: ConfigMaps, never Secrets. The grant is
   cluster-wide; which namespaces are read is the sidecar's list (below).
3. `OCIRepository/victoria-metrics-alert-chart`, pinned exactly.
4. `ConfigMap/alerting-socle-values`: the socle's chart values, labelled
   `reconcile.fluxcd.io/watch: Enabled`.
5. `ConfigMap/alerting-client-values`: `kube.alerting.values`, labelled the
   same.
6. `HelmRelease/alerting`: no `spec.values`; `valuesFrom` = socle, client,
   then the client's Secret when named (`optional: true`).
7. `Kustomization/alerting-rules` in `flux-system`: applies
   `oci/catalog/alerting/rules/` from the socle artifact into `alerting` — the
   watchdog and the stack's own health (below). The shape of otel_agent's
   dashboards Kustomization.

### How rules reach vmalert

- The chart reads rules from one ConfigMap, its own. The socle adds, through
  `server.extraContainers`, the **same sidecar Grafana runs** (`k8s-sidecar`):
  `LABEL=vmalert_rules`, `LABEL_VALUE=1`, `RESOURCE=configmap`,
  `UNIQUE_FILENAMES=true` (two modules may both name their key `rules.yaml`),
  writing every matching ConfigMap's keys into an `emptyDir` shared with
  vmalert.
- **`NAMESPACE` is a list, not `ALL`**: the namespaces of the modules that
  ship rules — `alerting`, `otel-agent`, `otel-gateway`, `victoria-metrics`
  today; a module that starts shipping rules adds its namespace. A client's
  labelled ConfigMap is never read.
- vmalert reads that directory through a wildcard (`-rule=/rules/*.yaml`) and
  re-reads it on `-configCheckInterval`, its own hot reload.

### Why a bad file must never reach vmalert

vmalert reads its rule files **all or nothing** (its source,
`app/vmalert/config`): one bad file freezes every change while it runs, and
stops it from starting at all ([measured](#measured)). No flag changes that
for a file that is not valid YAML. Hence the two guards: **the CI check**, and
**the namespace list**. Should a file slip through, the socle alerts on
`vmalert_config_last_reload_successful == 0`, and the watchdog catches a
crash.

### Who ships which rule

A rule lives in the module whose metrics it reads, so turning a module off
removes its rules with its dashboard. The baseline, on the names VictoriaMetrics
stores from OpenTelemetry (no kube-state-metrics, no node-exporter: #45). The
[awesome-prometheus-alerts](https://samber.github.io/awesome-prometheus-alerts/rules/)
catalogue is a source for what to watch and which thresholds; its expressions
read kube-state-metrics and node-exporter, so each is rewritten, not copied.

| Rule | Reads | Ships in |
| --- | --- | --- |
| Watchdog, always firing | `vector(1)` | `alerting` |
| A rule file did not load | `vmalert_config_last_reload_successful` | `alerting` |
| A rule fails at evaluation, without a break for 10 minutes | `vmalert_alerting_rules_errors_total` (labels `alertname`, `group`, `file`) | `alerting` |
| Notifications failing, without a break for 10 minutes | `alertmanager_notifications_failed_total` | `alerting` |
| Pod crash-looping | `k8s_container_restarts` | `otel_gateway` (`k8s_cluster`) |
| Pod pending too long | `k8s_pod_phase` (1 = pending) | `otel_gateway` |
| Node not ready | `k8s_node_condition_ready` | `otel_gateway` |
| Deployment missing replicas | `k8s_deployment_desired`, `k8s_deployment_available` | `otel_gateway` |
| Node filesystem nearly full | `k8s_node_filesystem_usage_bytes`, `k8s_node_filesystem_capacity_bytes` | `otel_agent` (`kubeletstats`) |
| VictoriaMetrics down, disk nearly full, series dropped by its guard | its own scraped metrics (`vm_hourly_series_limit_rows_dropped_total`) | `victoria_metrics` |

Each module's rules are a ConfigMap under `oci/catalog/<module>/rules/`,
applied by a Kustomization under that module's toggle. With `alerting` off they
are inert, as a dashboard is with `grafana` off.

**Shipped in two steps.** The module's PR ships the `alerting` rows above —
the watchdog and the alerting path's own health. The other modules' rows
(`otel_gateway`, `otel_agent`, `victoria_metrics`) follow in a PR of their
own, each module gaining a `rules/` folder and its Kustomization; the
sidecar already reads their namespaces.

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
| `server.extraArgs.configCheckInterval` | `30s` | How often vmalert re-reads the directory, so a rule shipped or removed is live without a restart |
| `server.extraContainers`, `extraVolumes`, `extraVolumeMounts` | the sidecar and the shared `emptyDir` | Above |
| `alertmanager.enabled` | `true` | The chart then points vmalert at its own Alertmanager by itself |
| `alertmanager.config` | rendered from `receivers`, `route` and the watchdog | Below |
| `alertmanager.extraVolumes`, `extraVolumeMounts` | `receivers_secret`, read-only, at `/etc/alertmanager/secrets/` | Where the `*_file` fields point |
| pod annotations | `prometheus.io/scrape` on both | So `otel_gateway` scrapes their own metrics, which the stack's health rules read |
| `resources.requests` | vmalert 20m / 64Mi, the sidecar 10m / 96Mi, Alertmanager 10m / 48Mi | Measured on floci with the socle's rules: vmalert 3m / 31Mi, the sidecar 1m / 72Mi, Alertmanager 2m / 30Mi. Headroom for the other modules' rules and for alerts held. No limits, as the other modules |

## What the client may set — `kube.alerting`

| Attribute | Default | Type | Meaning |
| --- | --- | --- | --- |
| `enabled` | `false` | bool | On requires `victoria_metrics`, a receiver and, unless `watchdog = false`, `receivers_secret` |
| `watchdog` | `true` | bool | Route the always-firing Watchdog to the dead man's switch whose URL is the `watchdog-url` key of `receivers_secret`. `false` is a choice made in the open, visible in review |
| `receivers` | `[]` | list | Alertmanager receivers, as Alertmanager writes them (`slack_configs`, `pagerduty_configs`, `webhook_configs`, …), keys as `*_file` only |
| `route` | `{}` | object | Alertmanager's routing tree. `route.receiver`, the default, must name one of `receivers` |
| `receivers_secret` | `""` | string | Name of a Secret in `alerting`, created by the client, holding the keys. Mounted as files under `/etc/alertmanager/secrets/` |
| `values` | `{}` | object | Any value of the chart: vmalert's flags, resources, Alertmanager's retention or storage. Merged over the socle's, the client's winning. Not rules: see below |
| `values_secret` | `""` | string | Name of a Secret in `alerting` with a `values.yaml` key. Merged last |

**No rules from the client in v1**: a labelled ConfigMap in their namespace
is not read, rules in `values` are refused at plan, and the `alerting`
namespace is the socle's. Grafana's UI is the one unsupported exception
([below](#grafana)).

**Why the routing plan is a named attribute, not `values`.** The socle adds
the watchdog's receiver and route to the client's. Helm replaces lists: a
client writing `alertmanager.config.receivers` in `values` would drop the
watchdog's. So OpenTofu renders `alertmanager.config` from `receivers`,
`route` and the watchdog, and `values` may not set `alertmanager.config`.

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
  `client_secret`; each `*_file` twin is accepted. The plan lands in the
  OpenTofu state and the cluster's input ConfigMap, and a Slack webhook URL is
  a key: whoever holds it posts in the on-call channel.
- `alertmanager.config` in `values` (above).
- **Rules in `values`**: `server.config.alerts.groups` non-empty, or a
  `server.extraArgs.rule` other than the socle's (above).

What `values_secret` holds, OpenTofu never reads: a client who rewrites
Alertmanager's configuration or vmalert's rules there takes these checks off
themselves.

### The watchdog

- The rule `Watchdog`, `expr: vector(1)`, ships in `oci/catalog/alerting/rules/`.
- The socle prepends a route `alertname="Watchdog"` → receiver `watchdog`, a
  `webhook_configs` with `url_file: /etc/alertmanager/secrets/watchdog-url`.
  It arrives **every 6 minutes**, not 5: Alertmanager checks the 5-minute
  `repeat_interval` only at its 1-minute `group_interval` (measured). The
  client sets their dead man's switch (Healthchecks.io, or their on-call
  platform's heartbeat) to tolerate **about 10 minutes** between pings.
- If vmalert, Alertmanager, VictoriaMetrics or the node under them dies, the
  pings stop, and the service outside the cluster raises the alarm. Nothing
  inside the cluster can: the stack shares the fate of what it watches.
- **Never silence the Watchdog.** A silence on `alertname="Watchdog"` stops
  the pings as surely as an outage, and the dead man's switch raises a false
  alarm. Anyone with access to Grafana can set it: the client's runbook says
  so.
- The Secret is mounted without `optional`, so a missing `receivers_secret`
  keeps Alertmanager from starting and the release from becoming Ready, rather
  than silently dropping the watchdog. What a missing **key** does is to
  measure.

## Grafana

**Grafana stays the one interface**, alerting included — the place the stack
chose for metrics, logs and traces. The `grafana` module adds an
**Alertmanager datasource** under `<< if inputs.modules.alerting.enabled >>`:
alerts firing and silences are seen and set in Grafana's Alerting pages.
Grafana's own alerting therefore stays on: switching it off is the only way to
refuse rules made in its UI, and it removes those pages with them
([measured](#measured)).

**In v1, Grafana is where alerts are seen, not where rules are made.** A rule
made in its UI is possible, not supported, a risk accepted and written here:

- **it notifies no one.** It fires in Grafana and goes to Grafana's own
  Alertmanager, which has no contact point; the socle's Alertmanager, the
  client's route and receivers never see it (measured);
- **it is lost whenever Grafana's pod is recreated** (a node lost, a drain, an
  upgrade of the socle), with no mistake and **no warning**: the grafana
  module has no persistence, `/var/lib/grafana` is an `emptyDir`
  ([grafana.md](grafana.md)). Measured: a socle upgrade recreated the pod and
  the rule was gone;
- not in Git.

**Why not route it through the socle's Alertmanager in v1.** Two settings are
needed, and only one is configuration (measured):

| Setting | Where it lives | v1 |
| --- | --- | --- |
| `handleGrafanaManagedAlerts: true` on the Alertmanager datasource | the grafana module's provisioning | **set**: harmless alone, ready for the v2 |
| `alertmanagersChoice` ("send to: internal, external, all") | **Grafana's database**, through its admin API only: a provisioned datasource gets no *Enable* button in Alerting → Settings | **not set**: lost with the pod like the rules, so it would need a job re-applying it at every start |

Set by hand through the API, a rule made in the UI reached the client's
receiver through the socle's route. Doing it for every client, durably, is
the v2's subject: #82.

## Per cloud

Nothing. No volume (`emptyDir` for the rules, Alertmanager's state on its own
volume only if the client sets `alertmanager.persistentVolume`), no cloud
identity.

## Measured

**A broken rule file, vmalert** (floci k3s, by hand, 6 October 2026). The
chart at the version the module pins, a ConfigMap mounted as `/rules`,
`-rule=/rules/*.yaml`, `-configCheckInterval=10s`, `-notifier.blackhole`, a
disk-less VictoriaMetrics as datasource. A valid file with the Watchdog, then a second file whose
expression misses a parenthesis (`rate(x[5m] > 1`):

| Case | Result |
| --- | --- |
| Valid file only | 1 file read, group `essai` scheduled |
| Broken file added, vmalert running | Pod `Running`; the parse error logged; `vmalert_config_last_reload_successful 0`; `/api/v1/rules` still lists `essai` alone |
| A **new valid** group added beside the broken file | Not loaded: `/api/v1/rules` still `essai` alone — every change is frozen |
| Pod deleted, broken file in place | `level=fatal` *cannot parse configuration file … invalid group "client" in file "/rules/cassee.yaml" … bad MetricsQL expr*, `CrashLoopBackOff` — no rule evaluated |

**Grafana's alerting off, and why it stays on** (same cluster and day; vmalert
with its Alertmanager and an always-firing Watchdog; the grafana chart at the
version the grafana module pins, with VictoriaMetrics and an Alertmanager
datasource, `implementation: prometheus`):

| `unified_alerting.enabled` | Result |
| --- | --- |
| default (on) | Alerting menu present. *Active notifications*, the Alertmanager datasource chosen: the Watchdog listed. *Silences*: the page shows, *Create silence* offered |
| `false` | **No Alerting menu.** `/alerting/groups` opened directly redirects to the home page: the datasource's views are gone with it |

The vmalert run lives on in the module's e2e: a labelled ConfigMap in a
client namespace, broken on purpose, leaves vmalert running and its rules
unchanged. The same run on Grafana's rule files is in #82.

**The module, end to end** (floci k3s, 7 October 2026). The branch's artifact
applied through `.github/e2e/aws` with `argocd` and `metrics_server` off, the
module turned on through `kube.alerting` — a `team` webhook receiver, the
route's `group_wait` 10s and `group_interval` 30s, `receivers_secret` — and
both webhooks pointing at an echo server in the cluster that logs every
request it receives:

| Case | Result |
| --- | --- |
| On | `HelmRelease` Ready; `alerting-server` 2/2 (vmalert and the sidecar), `alerting-alertmanager` 1/1; `socle-alerting` loaded with its four rules |
| The Watchdog | On `/watchdog` only, never on the client's receiver; the URL read from the Secret's file; **every 6 minutes** |
| **The proof of #59** | A test rule (`increase(k8s_container_restarts[5m]) > 2`, in a labelled ConfigMap of `alerting`) and a pod exiting every 5 seconds: `firing` on `/team`, naming namespace, pod and container; the namespace deleted, `resolved` on `/team`. Delays not timed, by choice: the chain is the proof |
| vmalert scaled to 0 at 12:20:27 UTC | One more ping at 12:22:08 (the alert still held by Alertmanager), then **none**; back within 2 minutes of scaling up |
| VictoriaMetrics restarted | Before the health rules waited 10 minutes: **five** "fails at evaluation" alerts on `/team` some 8 minutes after each restart, one per rule. After: none in 15 minutes |
| A rule made in Grafana's UI | `Firing` in Grafana, never in the socle's Alertmanager. With `handleGrafanaManagedAlerts`: Alerting → Settings still shows *Not receiving Grafana managed alerts*, Grafana's log *Sending alerts to local notifier*. With `alertmanagersChoice: all` posted to the admin API: on `/team`. The pod recreated by a socle upgrade: the rule gone |
| `kubectl top`, the socle's rules | vmalert 3m / 31Mi, the sidecar 1m / 72Mi, Alertmanager 2m / 30Mi: the requests above |

Found on the way, fixed in the same PR: **VictoriaMetrics dropped fresh data**
12 minutes after it started — its series guard counted one series many
times. The crash-looping pod's metrics never reached the storage until
`sortLabels` was set ([victoria-metrics.md](victoria-metrics.md)). For the
rules PR: `k8s_container_restarts` carries `container_id`, which changes at
every restart, so a crash-loop rule aggregates it away; and the kubelet's
back-off reaches 5 minutes, so a 5-minute window stops seeing a pod that has
crash-looped for long.

Not measured: a missing `watchdog-url` key in `receivers_secret`, and the
rules of a module turned off (the other modules' rules come in their own PR).

## Left out of v1

- **Application alerts**, generated or written by the client: #82.
- **A client's own Alertmanager** in place of the module's.
- **Log-based rules.** vmalert evaluates `vlogs` rules against VictoriaLogs,
  but one vmalert reads one datasource: log rules need a second vmalert, a
  follow-up once `victoria_logs` users ask.
- **High availability**: two Alertmanagers in a cluster, two vmalerts.
- **Silences surviving a restart**: they live in Alertmanager's state, lost
  with the pod unless the client sets `alertmanager.persistentVolume`.
- **Recording rules** shipped by the socle: none needed by the baseline.
- **A central Alertmanager** across clusters.
- **Probing endpoints from outside** (a blackbox exporter, or OpenTelemetry's
  `httpcheck` receiver in `otel_gateway`): asked for by the coordinator, a
  subject of its own after this one.
