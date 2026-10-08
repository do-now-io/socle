---
title: alerting
description: vmalert evaluates the socle's alert rules, and Alertmanager sends what fires to your Slack, PagerDuty or webhook.
category: observability
requires:
  - module: victoria_metrics
    why: every rule is evaluated against it
---

Without alerting, the monitoring stack stores and shows everything and tells
no one when something breaks. This module evaluates the socle's rules (a pod
crash-looping, a node not ready, a disk filling, the stack's own health) and
sends what fires to your receivers. **Off by default**: only you know where
alerts go. Every cloud.

## Getting started

Create the Secret that holds your keys, then turn the module on with one
receiver:

```sh
kubectl create namespace alerting
kubectl -n alerting create secret generic alerting-keys \
  --from-literal=slack-url=https://hooks.slack.com/services/… \
  --from-literal=watchdog-url=https://hc-ping.com/…
```

```hcl kube-start="alerting"
kube = {
  alerting = {
    enabled          = true
    receivers_secret = "alerting-keys"
    receivers = [
      { name = "team", slack_configs = [{ api_url_file = "/etc/alertmanager/secrets/slack-url", channel = "#alerts" }] },
    ]
    route = { receiver = "team" }
  }
}
```

Then `kubectl -n alerting get helmrelease alerting` shows it `Ready`, and your
dead man's switch receives a ping every 6 minutes.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on. Needs `victoria_metrics`. |
| `receivers` | `[]` | Alertmanager receivers, as Alertmanager writes them; keys only through `*_file` fields. At least one when on. |
| `route` | `{}` | Alertmanager's routing tree; `route.receiver` names one of `receivers`. |
| `receivers_secret` | `""` | A Secret in `alerting` with your keys, mounted as files under `/etc/alertmanager/secrets/`. |
| `watchdog` | `true` | Sends an always-firing alert to the URL in the Secret's `watchdog-url` key, so a dead stack is noticed from outside. |
| `values` | `{}` | Any [`victoria-metrics-alert` chart](https://artifacthub.io/packages/helm/victoriametrics/victoria-metrics-alert) value; yours win. No rules, no Alertmanager config. |
| `values_secret` | `""` | A Secret in `alerting` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl kube-full="alerting"
kube = {
  alerting = {
    enabled          = true            # off by default; needs victoria_metrics
    watchdog         = true            # pings the watchdog-url key every 6 minutes
    receivers_secret = "alerting-keys" # keys: slack-url, pagerduty-key, watchdog-url

    # As Alertmanager writes them; every key through a *_file field.
    receivers = [
      { name = "team", slack_configs = [{ api_url_file = "/etc/alertmanager/secrets/slack-url", channel = "#alerts" }] },
      { name = "on-call", pagerduty_configs = [{ routing_key_file = "/etc/alertmanager/secrets/pagerduty-key" }] },
    ]

    # Alertmanager's routing tree: critical alerts to the on-call.
    route = {
      receiver = "team"
      routes   = [{ receiver = "on-call", matchers = ["severity=\"critical\""] }]
    }

    # Any value of the victoria-metrics-alert chart 0.50.0; yours win.
    values = {
      alertmanager = { retention = "240h" }
    }

    # A Secret you create in alerting, whose values.yaml key holds chart
    # values that must not reach the OpenTofu state.
    values_secret = "alerting-values"
  }
}
```

## Good to know

- **The rules are the socle's.** Each module ships the rules for what it
  measures: [otel_gateway](otel-gateway.md) (pods crash-looping or `Pending`,
  nodes not ready, Deployments missing replicas), [otel_agent](otel-agent.md)
  (a node filesystem nearly full), [victoria_metrics](victoria-metrics.md)
  (its disk, its series guard), and this module (the Watchdog, rules failing,
  notifications failing). You add none in this version.
- **Two severities**: `critical` for a node or data lost, `warning` for the
  rest. Route `severity="critical"` to your on-call, as above.
- **Point the watchdog at a dead man's switch** (Healthchecks.io, your
  on-call platform's heartbeat) that tolerates about 10 minutes between
  pings. If the stack or its node dies, the pings stop and the service
  outside raises the alarm. **Never silence the Watchdog**: that stops the
  pings too. `watchdog = false` turns it off, visibly in review.
- **Alerts and silences are in Grafana**, Alerting pages. A rule made in
  Grafana's UI notifies no one and is lost when its pod restarts.
- **`tofu plan` refuses** a literal key in `receivers` (`api_url`,
  `routing_key`, `url`, `token`… use the `*_file` twin), a route to an
  unknown receiver, a receiver named `watchdog`, the watchdog without
  `receivers_secret`, and rules or `alertmanager.config` in `values`.
- **Silences are lost when Alertmanager restarts**, unless you set
  `alertmanager.persistentVolume` in `values`.
- **Upgrades**: the chart moves with `socle_version`.

<details>
<summary>Under the hood</summary>

**Installed**: chart `victoria-metrics-alert` 0.50.0 (vmalert v1.153.0,
Alertmanager v0.34.1) from
`oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-alert`, in the
`alerting` namespace: one vmalert, one Alertmanager. A `ClusterRole` reading
ConfigMaps only, and a Flux `Kustomization` applying the module's own rules.

**What the socle sets**: vmalert reads from and writes its state back to
VictoriaMetrics, so a restart keeps every `for:` timer; a sidecar gathers the
ConfigMaps labelled `vmalert_rules: "1"` from the socle's namespaces only, and
vmalert re-reads them every 30 s. Alertmanager's configuration is rendered
from `receivers`, `route` and the watchdog's route, prepended. Requests:
vmalert 20m / 64Mi, the sidecar 10m / 96Mi, Alertmanager 10m / 48Mi, no
limits. Your `values` are merged over these.

**Why the rules are checked in CI**: vmalert reads its rule files all or
nothing. One bad file freezes every change, and stops it from starting. Every
rule file passes `vmalert -dryRun` before it is published.

**Cloud access**: none.

**Measured** on floci k3s, 2026-10-07: a pod exiting every 5 seconds raised
`PodCrashLooping` on the receiver after 8 min; the Watchdog arrived every
6 minutes, and stopped within 2 minutes of vmalert scaled to 0. Measured
use: vmalert 3m / 31Mi, the sidecar 1m / 72Mi, Alertmanager 2m / 30Mi.

</details>
