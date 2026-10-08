---
title: reloader
description: Rolls a workload when a ConfigMap or Secret it reads changes, opt-in per workload.
category: secrets
---

Stakater Reloader rolls the workloads that ask for it when a ConfigMap or
Secret they read changes. Turn it on with
[external-secrets](external-secrets.md), whose rotated Secrets a running pod
never re-reads, or alone for ConfigMaps. **Off by default**, on every cloud.

## Getting started

Turn it on; it then rolls only the workloads you annotate (see Good to know).

```hcl title="terraform.tfvars" kube-start="reloader"
kube = {
  reloader = {
    enabled = true
  }
}
```

Then `kubectl -n reloader get deployment reloader` shows it ready.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on or off. |
| `values` | `{}` | Any [`reloader` chart](https://artifacthub.io/packages/helm/stakater/reloader) value; yours win. |
| `values_secret` | `""` | A Secret in `reloader` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl title="terraform.tfvars" kube-full="reloader"
kube = {
  reloader = {
    enabled = false # off by default; it reads every ConfigMap and Secret of the cluster

    # Any value of the reloader chart 2.2.18; yours win over the socle's.
    values = {
      reloader = {
        logFormat      = "json"
        ignoreCronJobs = true
      }
    }

    # A Secret you create in reloader, whose values.yaml key holds chart values
    # that must not reach the OpenTofu state, reloader.deployment.env.secret's
    # ALERT_WEBHOOK_URL say; merged last.
    values_secret = "reloader-values"
  }
}
```

## Good to know

- **A workload is rolled only when it asks**, with
  `reloader.stakater.com/auto: "true"` (every ConfigMap and Secret it
  references), or `secret.reloader.stakater.com/reload` /
  `configmap.reloader.stakater.com/reload` naming them. A workload with none
  is never touched.
- **Tell your GitOps tool to ignore `reloader.stakater.com/last-reloaded-from`**,
  which a reload writes on the pod template (Argo CD's `ignoreDifferences`),
  or it sees the workload as drifted.
- **`tofu plan` refuses** `autoReloadAll = true`, which would roll every
  workload of the cluster, and credentials in `reloader.deployment.env`: name
  your own Secret in `reloader.deployment.env.existing`, or use
  `values_secret`.
- **A change made while Reloader restarts is missed**: one replica, and it
  reacts to update events. `reloader.enableHA` or `syncAfterRestart` through
  `values` close that window.
- **Upgrades**: the chart moves with `socle_version`. The socle stays on the
  2.x chart until Reloader 3.x is stable.

<details>
<summary>Under the hood</summary>

**Installed**: chart `reloader` 2.2.18 (Reloader v1.4.22) from
`oci://ghcr.io/stakater/charts`, in the `reloader` namespace (Pod Security
`restricted`): one Deployment `reloader`, one replica. Its ClusterRole lists
and watches every ConfigMap and Secret; the chart's scoped mode
(`reloader.namespaces`) is available through `values`.

**What the socle sets**: `autoReloadAll: false` and
`reloadStrategy: annotations`, a hardened container (read-only root
filesystem, every capability dropped), requests 10m CPU and 64Mi with a 256Mi
memory limit, and `prometheus.io/scrape` for [otel-gateway](otel-gateway.md).

**Cloud access**: none.

**Measured** on floci k3s, 2026-10-02: Available in 16 s; a ConfigMap change
rolled the annotated workload in under 1 s, a Secret change in 10 s.

</details>
