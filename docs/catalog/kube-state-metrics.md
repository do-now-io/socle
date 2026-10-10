---
title: kube-state-metrics
description: Every Kubernetes object's state as metrics, which the socle's Kubernetes and Flux alerts read.
category: observability
---

kube-state-metrics turns the state of every Kubernetes object into metrics:
a Deployment's available replicas, a pod's phase, a node's conditions, a
Job's failures, a Flux object's readiness. [otel_gateway](otel-gateway.md)
scrapes it, so nothing but the collectors sends to
[victoria-metrics](victoria-metrics.md). The module also ships the socle's
Kubernetes and Flux alert rules, which fire once [alerting](alerting.md) is
on. **On by default**, on every cloud.

## Getting started

It is already on, with nothing to name. What you may set first is more
labels on the pod series, for alerts or dashboards that group by them:

```hcl kube-start="kube_state_metrics"
kube = {
  kube_state_metrics = {
    values = {
      metricLabelsAllowlist = ["pods=[app.kubernetes.io/name]"]
    }
  }
}
```

Then `kubectl -n kube-state-metrics get deployment kube-state-metrics` shows
it ready.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on or off, its alert rules with it. |
| `values` | `{}` | Any [`kube-state-metrics` chart](https://artifacthub.io/packages/helm/prometheus-community/kube-state-metrics) value; yours win. |
| `values_secret` | `""` | A Secret in `kube-state-metrics` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl kube-full="kube_state_metrics"
kube = {
  kube_state_metrics = {
    enabled = true # on by default; off removes the release and its alert rules

    # Any value of the kube-state-metrics chart 8.6.0; yours win over the socle's.
    values = {
      metricLabelsAllowlist = ["pods=[app.kubernetes.io/name]"]
      resources             = { requests = { memory = "128Mi" } }
    }

    # A Secret you create in kube-state-metrics, whose values.yaml key holds
    # chart values that must not reach the OpenTofu state; merged last.
    values_secret = "kube-state-metrics-values"
  }
}
```

## Good to know

- **Its alert rules are [the socle's Kubernetes and Flux rules](../reference/alert-rules.md)**:
  nodes not ready or under pressure, pods crash-looping or unhealthy,
  workloads short of replicas or stuck in a rollout, Jobs failing, claims
  `Pending`, HPAs unable to scale, and any Flux object or catalog module not
  `Ready` for 15 minutes. They are awesome-prometheus-alerts' rules, as
  written.
- **Off, the Kubernetes and Flux alerts go with it**, and so do five of
  otel_agent's rules, which read it: the CPU rule (the nodes' capacity) and
  the four PersistentVolumeClaim rules (which volume is a claim), the two
  critical ones included. Nothing fails: the rules have no series to read.
- **Without otel_gateway nothing is scraped**, and the rules have nothing to
  read either.
- **Secrets are not collected**: kube-state-metrics never reads one. Every
  other object of the cluster it may list and watch.
- **It adds series**: about 1 700 on floci's one node and 25 pods, a fifth of
  what VictoriaMetrics held; on a large cluster, tens of thousands, against
  the 100 000 new series an hour [victoria_metrics](victoria-metrics.md)
  accepts. `VictoriaMetricsSeriesLimitNear` warns first; `metricAllowlist` in
  `values` narrows what kube-state-metrics exposes.
- **Lists in `values` are replaced, not merged**: `collectorsExclude` or
  `rbac.extraRules` that you set replace the socle's, which exclude Secrets
  and grant the Flux kinds.
- **`tofu plan` refuses** a kubeconfig in clear (`kubeconfig.secret`) and a
  `Secret` in `extraManifests`.

<details>
<summary>Under the hood</summary>

**Installed**: chart `kube-state-metrics` 8.6.0 (kube-state-metrics 2.20.0)
from `oci://ghcr.io/prometheus-community/charts`, one replica, in the
`kube-state-metrics` namespace (Pod Security `restricted`), with a
`ClusterIP` Service on 8080 (the objects) and 8081 (its own list and watch
counters), and a Flux `Kustomization` applying its rules.

**What the socle sets**: the chart's collectors but Secrets; a custom
resource state producing `gotk_resource_info` for Kustomization,
HelmRelease, GitRepository, OCIRepository, HelmRepository, HelmChart and
Bucket, as Flux publishes it, and for the Flux Operator's ResourceSet;
`list` and `watch` on those kinds. No `prometheus.io/scrape` annotation:
otel_gateway scrapes both ports with a job of its own, every 30 s, keeping
the labels kube-state-metrics gives (`namespace`, `pod`, `node`…). Requests
10m CPU and 64Mi, no limit.

**Cloud access**: none.

**Measured** on floci k3s, 2026-10-10: 7m CPU and 34Mi; every metric the
rules name stored under kube-state-metrics' own names and labels; a
crash-looping pod, a failed Job, a `Pending` claim, an OOM-killed container
and a broken Flux Kustomization each raised its alert, delivered by
Alertmanager, the last after its 15 minutes.

</details>
