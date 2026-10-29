---
title: monitoring
description: "The monitoring stack in one release: metrics, logs and traces storage, the cluster scraped, Grafana, and kube-prometheus-stack's alert rules."
category: observability
---

The [victoria-metrics-k8s-stack](https://docs.victoriametrics.com/helm/victoria-metrics-k8s-stack/)
chart as one release, the way kube-prometheus-stack is installed elsewhere:
VictoriaMetrics, VictoriaLogs and VictoriaTraces to store, vmagent to scrape
the cluster, Grafana to read, and vmalert and Alertmanager to alert, with the
rules and dashboards kube-prometheus-stack ships. **On by default** with
metrics, logs and Grafana; traces and alerting off. Every cloud. How it fits
with the collectors: [Observability](../architecture/observability.md).

## Getting started

It is already on. To alert, create the Secret that holds your keys, then turn
alerting on with one receiver:

```sh
kubectl -n monitoring create secret generic alerting-keys \
  --from-literal=slack-url=https://hooks.slack.com/services/… \
  --from-literal=watchdog-url=https://hc-ping.com/…
```

```hcl kube-start="monitoring"
kube = {
  monitoring = {
    alerting = {
      enabled          = true
      receivers_secret = "alerting-keys"
      receivers = [
        { name = "team", slack_configs = [{ api_url_file = "/etc/alertmanager/secrets/slack-url", channel = "#alerts" }] },
      ]
      route = { receiver = "team" }
    }
  }
}
```

Then `kubectl -n monitoring get vmalert,vmalertmanager` shows both
`operational`, and your dead man's switch receives a ping every 6 minutes.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `true` | Turns the whole stack on or off. Off deletes every claim and its data. |
| `metrics` | `{ retention = "15d", storage_size = "20Gi" }` | VictoriaMetrics, always there while the module is. `retention` in hours, days, weeks or years (`48h`, `4w`), at least a day; `storage_size` in `Gi` or `Ti`, `""` for an `emptyDir`, lost when the pod moves. |
| `logs` | `{ enabled = true, retention = "7d", storage_size = "20Gi" }` | VictoriaLogs, the same shape. Off takes [otel-agent](otel-agent.md) with it: it has nothing else to do. |
| `traces` | `{ enabled = false, retention = "7d", storage_size = "10Gi" }` | VictoriaTraces, the same shape. Off by default: not yet GA, an upgrade may drop stored traces. |
| `grafana` | `{ enabled = true, domain = "", gateway = "private" }` | Grafana. `domain` is the host it is served at, empty for none; `gateway` the shared Gateway its route uses: `private`, `public` or `""`. |
| `alerting` | `{ enabled = false, watchdog = true, receivers = [], route = {}, receivers_secret = "" }` | vmalert and Alertmanager. `receivers` and `route` as Alertmanager writes them, keys only through `*_file` fields; at least one receiver when on. `receivers_secret` is a Secret in `monitoring`, mounted under `/etc/alertmanager/secrets/`. `watchdog` sends an always-firing alert to the Secret's `watchdog-url` key. |
| `values` | `{}` | Any [`victoria-metrics-k8s-stack` chart](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-metrics-k8s-stack) value; yours win. |
| `values_secret` | `""` | A Secret in `monitoring` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

A block written alone keeps its siblings: `logs = { retention = "30d" }`
leaves logs on, on their 20Gi claim.

### Every setting

```hcl kube-full="monitoring"
kube = {
  monitoring = {
    enabled = true # on by default; off deletes every claim and its data

    metrics = { retention = "15d", storage_size = "20Gi" }                 # "" keeps the data in an emptyDir
    logs    = { enabled = true, retention = "7d", storage_size = "20Gi" }  # off also stops otel-agent
    traces  = { enabled = false, retention = "7d", storage_size = "10Gi" } # pre-GA: an upgrade may drop traces
    grafana = { enabled = true, domain = "", gateway = "private" }         # "" = no root_url and no route

    alerting = {
      enabled          = false           # off by default; on needs a receiver
      watchdog         = true            # pings the watchdog-url key every 6 minutes
      receivers_secret = "alerting-keys" # keys: slack-url, pagerduty-key, watchdog-url

      # As Alertmanager writes them; every key through a *_file field.
      receivers = [
        { name = "team", slack_configs = [{ api_url_file = "/etc/alertmanager/secrets/slack-url", channel = "#alerts" }] },
        { name = "on-call", pagerduty_configs = [{ routing_key_file = "/etc/alertmanager/secrets/pagerduty-key" }] },
      ]

      # Alertmanager's routing tree: critical alerts to the on-call, one noisy
      # alert to the socle's null receiver.
      route = {
        receiver = "team"
        routes = [
          { receiver = "on-call", matchers = ["severity=\"critical\""] },
          { receiver = "null", matchers = ["alertname=\"CPUThrottlingHigh\""] },
        ]
      }
    }

    # Any value of the victoria-metrics-k8s-stack chart 0.96.0; yours win.
    # Numeric flags as strings: Helm renders a million as 1e+06.
    values = {
      vmsingle = { spec = { extraArgs = { "storage.maxHourlySeries" = "1000000" } } }
      grafana  = { persistence = { enabled = true, size = "5Gi" } }
    }

    # A Secret you create in monitoring, whose values.yaml key holds chart
    # values that must not reach the OpenTofu state, such as
    # grafana."grafana.ini"."auth.generic_oauth".client_secret; merged last.
    values_secret = "monitoring-values"
  }
}
```

## Good to know

- **The alert rules are kube-prometheus-stack's**, from
  [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus),
  and VictoriaMetrics' for the stack itself, plus the socle's for Flux and
  the collectors: [every group, and what is off](../reference/alert-rules.md).
  Turning alerting on is all it takes. Severities are upstream's; `info` goes
  to the socle's `null` receiver, and a `critical` alert holds back the
  `warning` of the same name and namespace. Route `severity="critical"` to
  your on-call, as above.
- **Write your own rules as `VMRule`s**, in any namespace: vmalert reads them
  all. One that does not parse is refused when you apply it, and the others
  keep firing.
- **Create `receivers_secret` before turning alerting on.** Alertmanager
  does not start without it, and until it exists the VictoriaMetrics
  operator retries every minute and a half: `ReconcileErrors` and
  `LogErrors` fire, delivered once Alertmanager is up.
- **Point the watchdog at a dead man's switch** (Healthchecks.io, your
  on-call platform's heartbeat) that tolerates about 10 minutes between
  pings. If the stack or its node dies, the pings stop and the service
  outside raises the alarm. **Never silence the Watchdog**: that stops the
  pings too. `watchdog = false` turns it off, visibly in review.
- **The rules and dashboards are downloaded** from `raw.githubusercontent.com`
  by the chart's sync job, at the tags the socle pins. A cluster without
  egress there gets the stack with neither. The VictoriaLogs Grafana plugin
  comes from grafana.com the same way.
- **Every pod annotated** `prometheus.io/scrape: "true"` is scraped, with
  `prometheus.io/port`, `path` and `scheme` saying where; its `job` is the
  pod's `app.kubernetes.io/name`, else its `app` label, else `kubernetes-pods`. A pod that declares container ports must
  declare the annotated one: it is scraped once, on that port, and not at
  all if the port is missing. Init containers are never scraped.
- **The pods the cloud manages are not scraped**, annotated or not: GKE's,
  which carry `components.gke.io/component-name` (kube-dns, anetd,
  node-local-dns), are Google's to watch, and on Autopilot some refuse
  vmagent or leave with every node it replaces. Scrape one yourself with a
  `VMPodScrape` if you need it.
- **A target on a node going away is not down.** Autopilot and Karpenter
  replace nodes all day; the socle's `TargetDown` leaves out the targets of
  a node that is cordoned, not `Ready` or already deleted, and upstream's
  `TooManyScrapeErrors`, which cannot tell them apart, is off
  ([alert rules](../reference/alert-rules.md)). A failed scrape is not
  logged either: it is `up == 0`, and its last error is on vmagent's
  `/targets` page.
- **`storage_size` grows, never shrinks**, and only where the StorageClass
  allows expansion. To or from `""` replaces the volume: the data is lost.
  With `""` the data lives in an `emptyDir`, and VictoriaMetrics, VictoriaLogs
  and VictoriaTraces each ask 2Gi of ephemeral storage for it instead of
  64Mi. On GKE Autopilot that request is also the limit: a pod past it is
  evicted, its data lost. Keep data on a claim, or raise
  `<part>.spec.resources.requests.ephemeral-storage` in `values`.
- **On gcp there is no node-exporter**: GKE Autopilot refuses its host
  network, host PID and `hostPath`, so its rules and its dashboard are off
  too. Autopilot collects the nodes' metrics itself, into Cloud Monitoring.
- **Past 300,000 new series in an hour, new series are dropped** with a log
  line, and `RowsRejectedOnIngestion` fires. A fresh GKE Autopilot install
  writes about 57,000 series a scrape on seven nodes, and some 4,000 new ones
  with each node it adds, which it does every few minutes while it settles. Raise `storage.maxHourlySeries` under `vmsingle.spec.extraArgs` in
  `values` if you need to.
- **Log in to Grafana as `admin`** with the chart's random password:
  `kubectl -n monitoring get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d`.
  Without the shared Gateways (gcp, scaleway):
  `kubectl -n monitoring port-forward svc/grafana 3000:80`. Nothing is
  persisted: a restart loses dashboards made by hand. Ship yours as a
  ConfigMap labelled `grafana_dashboard: "1"`, in any namespace.
- **Alerts and silences are in Grafana**, Alerting pages. A rule made in
  Grafana's UI notifies no one and is lost when its pod restarts. Silences
  are lost when Alertmanager restarts, unless you give it a volume through
  `alertmanager.spec.storage` in `values`.
- **Kubernetes events have no `_msg`**: their message is `object.note`; find
  them with `k8s.resource.name:=events`.
- **`tofu plan` refuses** a literal key in `receivers` (`api_url`,
  `routing_key`, `url`, `token`… use the `*_file` twin), a route to an
  unknown receiver, a receiver named `watchdog` or `null`, the watchdog
  without `receivers_secret`; in `values`, Alertmanager's configuration, the
  rules' sources, the `enabled` switch of a part the attributes drive, and
  credentials (auth flags, literal credential env values, Grafana's
  passwords and client secrets, a `Secret` in `extraObjects`); a
  `retention` under a day, a `storage_size` not in `Gi` or `Ti`, and a key a
  block does not have.

<details>
<summary>Under the hood</summary>

**Installed**: chart `victoria-metrics-k8s-stack` 0.96.0 from
`oci://ghcr.io/victoriametrics/helm-charts`, release `monitoring` in the
`monitoring` namespace: the VictoriaMetrics operator v0.75.0, and through its
objects VictoriaMetrics v1.154.0, VictoriaLogs v1.53.0, VictoriaTraces
v0.10.0, vmagent, vmalert, Alertmanager v0.34.0, kube-state-metrics 2.20.0,
node-exporter 1.12.1 and Grafana 13.2.3. Services, in-cluster only, no
authentication: `vmsingle-monitoring:8428`, `vlsingle-monitoring:9428`,
`vtsingle-monitoring:10428`, `vmagent-monitoring:8429`,
`vmalert-monitoring:8080`, `vmalertmanager-monitoring:9093`, `grafana:80`.
A `ClusterRole/monitoring-grafana` reading ConfigMaps only, which Grafana's
sidecars use in place of the chart's (which also reads every Secret), and a
Flux `Kustomization` applying the socle's own `VMRule`s. With a domain, a
gateway and the shared Gateways, `HTTPRoute/grafana`, waiting for its
Gateway to be `Accepted`; on gcp also `HealthCheckPolicy/grafana`, so GKE's
load balancer checks `/api/health` rather than `/`, which Grafana redirects
to `/login`.

**What vmagent scrapes**, every 30 s: the kubelets and their cAdvisor,
kube-state-metrics, node-exporter (not on gcp), the stack itself, and every annotated pod
(the collectors, Flux, Cilium) but those the cloud manages. Not the control plane: the cloud's, its
rule groups off. The kubelet's API server and etcd families are dropped at
the scrape (on k3s they ride the kubelet's endpoint). Not the kubelet's
`/metrics/resource`: cAdvisor's figures again, which nothing reads. Of
cAdvisor, what kube-prometheus-stack drops by default: per-container
figures nothing reads, the CNI's interfaces, cgroups that are no pod. The
kubelet's and cAdvisor's series carry `node`, not the node's labels: GKE
puts more than 40 on a node, past what VictoriaMetrics stores. Nothing
is collected twice: the OpenTelemetry collectors push no metric of the
cluster's, and their own telemetry is scraped once, here.

**What the socle sets**: `-opentelemetry.usePrometheusNaming`, so what
applications push over OTLP reads as upstream dashboards expect;
`-storage.maxHourlySeries=300000` with `-sortLabels`, without which the
guard counts one series once per label order (measured, 2026-10-07);
vmagent's `-promscrape.suppressDuplicateScrapeTargetErrors` and
`-promscrape.suppressScrapeErrors`;
the socle's `TargetDown` in place of upstream's, and `TooManyScrapeErrors`
off;
`-vmalert.proxyURL` with alerting on, so Grafana lists the rules; the
`cluster` label on every series; the rules' sources pinned to
kube-prometheus v0.19.0, VictoriaMetrics v1.154.0, operator v0.75.0,
VictoriaLogs v1.53.0 and VictoriaTraces v0.10.0; Alertmanager's
configuration from `receivers` and `route`, with the Watchdog's route and
the `null` route for `info` prepended; the operator's CRDs kept on
uninstall, so turning the module off never deletes a client's `VMRule`;
cpu, memory and ephemeral-storage requests on every container, the
operator's config-reloaders and the chart's hooks included, no limits
([MONITORING-13](../decisions/monitoring.md#monitoring-13-requests-on-every-container-disk-included-on-every-cloud)).
Your `values` are merged over these. On gcp, from
`oci/clusters/gcp/monitoring/patch.yaml`: node-exporter off and the
`HealthCheckPolicy` above
([MONITORING-14](../decisions/monitoring.md#monitoring-14-on-gcp-no-node-exporter-and-grafana-health-checked-on-apihealth)).

**Cloud access**: none; the data is on the claims; egress to
raw.githubusercontent.com and grafana.com.

**Measured** on k3s, 2026-10-12, with the cluster scraped and every part
on: 211 rules loaded and healthy (209 since the chart 0.96.0), 158 of them alerting; 38,000 series on an
empty two-node cluster (55,000 before the kubelet's API server and etcd
families were dropped); VictoriaMetrics 53m / 355Mi, vmagent 20m / 141Mi,
vmalert 11m / 59Mi, Grafana 22m / 517Mi with the stack's 40 dashboards.
On GKE Autopilot, 2026-10-29, a fresh install on seven nodes: 91,000
samples a scrape, about 57,000 once GKE's pods, the node labels and
cAdvisor's unread figures are left out; 13 nodes created and removed in its
first 40 minutes.

</details>
