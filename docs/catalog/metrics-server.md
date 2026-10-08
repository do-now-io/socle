---
title: metrics-server
description: The resource metrics API behind kubectl top and every HorizontalPodAutoscaler on CPU or memory, on EKS.
category: observability
requires: []
---

metrics-server serves the CPU and memory of every node and pod under the
`metrics.k8s.io` API: what `kubectl top` reads and what every
HorizontalPodAutoscaler on CPU or memory scales from. **On by default**, on
aws only: GKE, AKS and Kapsule run their own.

## Getting started

It is already on. For a cluster that deletes namespaces often (preview
environments, a test runner), keep it answering through a node loss:

```hcl kube-start="metrics_server"
kube = {
  metrics_server = {
    ha = true
  }
}
```

Then `kubectl top nodes` answers.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on or off. aws only. |
| `ha` | `false` | Two replicas on two nodes, with a disruption budget. |
| `values` | `{}` | Any [`metrics-server` chart](https://artifacthub.io/packages/helm/metrics-server/metrics-server) value; yours win. |
| `values_secret` | `""` | A Secret in `metrics-server` with a `values.yaml` key, merged last. |

### Every setting

```hcl kube-full="metrics_server"
kube = {
  metrics_server = {
    enabled = true  # on by default, aws only
    ha      = false # true: two replicas spread across nodes, a disruption budget

    # Any value of the metrics-server chart 3.14.0; yours win over the socle's.
    values = {
      args = ["--metric-resolution=30s"]
    }

    # A Secret you create in metrics-server, whose values.yaml key holds chart
    # values. The chart takes no secret; every module with a chart has it.
    values_secret = "metrics-server-values"
  }
}
```

## Good to know

- **Not a monitoring system**: one value per node and pod, refreshed every
  15 s, no history. History is [victoria_metrics](victoria-metrics.md)'.
- **When it is down, HPAs hold** at their current replica count, and every
  namespace deletion in the cluster waits until it answers again (the
  namespace stays `Terminating`). With one replica that lasts about a minute
  on a drain, up to five on a node lost. `ha = true` avoids it.
- **Watch the `APIService`, not Flux**: with nothing behind
  `v1beta1.metrics.k8s.io`, the `HelmRelease` stays `Ready`.
  `kubectl get apiservice v1beta1.metrics.k8s.io` shows `Available`.
- **Kubelet certificates are always checked**: `tofu plan` refuses
  `--kubelet-insecure-tls` in `values`.
- **Custom and external metrics** (requests per second, a queue depth) are
  [keda](keda.md)'s, on another API; the two never collide.
- **Upgrades**: the chart moves with `socle_version`.

<details>
<summary>Under the hood</summary>

**Installed**: chart `metrics-server` 3.14.0 (metrics-server 0.9.0) from
`https://kubernetes-sigs.github.io/metrics-server/`, in its own
`metrics-server` namespace, never `kube-system`.

**What the socle sets**: one replica, or two with `ha`, a preferred
anti-affinity on the node and `maxUnavailable: 1`; a toleration of
`CriticalAddonsOnly`; the chart's `system-cluster-critical` priority, its
requests (100m CPU, 200Mi), no limits, and its self-signed certificate
between the API server and metrics-server. Your `values` are merged over
these.

**Why aws only**: two metrics-servers cannot share a cluster, and GKE, AKS
and Kapsule each operate one. `tofu plan` refuses the module elsewhere.

**Cloud access**: none.

**Measured** on floci k3s: `Ready` 35 s after the apply, `kubectl top nodes`
at 40 s. On EKS: an HPA on CPU at 50 % read `201%/50%` 15 s after it was
created, and scaled to 3 replicas at 30 s.

</details>
