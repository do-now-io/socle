---
title: reloader
description: Rolls a workload when a ConfigMap or Secret it reads changes, opt-in per workload.
category: secrets
---

Stakater Reloader watches ConfigMaps and Secrets and rolls the workloads that
ask for it when one they read changes. Turn it on with
[external-secrets](external-secrets.md), whose rotated Secrets a running pod
never re-reads, or alone for ConfigMaps. Off by default.

## Getting started

Turn it on; it then rolls only the workloads you annotate (below).

```hcl title="terraform.tfvars" kube-start="reloader"
kube = {
  reloader = {
    enabled = true
  }
}
```

After apply, `kubectl -n reloader get deployment reloader` shows it ready;
change a ConfigMap an annotated workload reads and its pods roll.

## What it installs

| | |
| --- | --- |
| Chart | `reloader` `2.2.18` (Reloader v1.4.22) from `oci://ghcr.io/stakater/charts` |
| Namespace | `reloader`, labelled `pod-security.kubernetes.io/enforce: restricted` |
| Objects | the namespace, the chart source, the socle's and your values ConfigMaps, one `HelmRelease` (Deployment `reloader`, one replica) |

The socle's values: `autoReloadAll: false`, `reloadStrategy: annotations`, a
read-only root filesystem, no privilege escalation, every capability dropped
(the chart already runs as 65534 with the `RuntimeDefault` seccomp profile);
requests 10m CPU and 64Mi memory, a 256Mi memory limit from which the chart
derives `GOMEMLIMIT`; `prometheus.io/scrape` on port 9090, for
[otel-gateway](otel-gateway.md).

**A workload is rolled only when it asks**, with one of Reloader's
annotations:

```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"                     # every ConfigMap and Secret it references
    # secret.reloader.stakater.com/reload: "db-credentials" # or only those named
    # configmap.reloader.stakater.com/reload: "app-config"
```

A workload with none of them is never touched. A reload writes
`reloader.stakater.com/last-reloaded-from` on the pod template: a JSON naming
the kind, namespace and name of the object that changed. Tell your GitOps
tool to ignore that annotation (Argo CD's `ignoreDifferences`), or it will
see the workload as drifted.

## What you can set

Under `kube.reloader` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on. |
| `values` | `{}` | Any `reloader` chart value; yours win over the socle's. |
| `values_secret` | `""` | A Secret you create in `reloader` with a `values.yaml` key, merged last. |

Refused at plan:

- `values.reloader.autoReloadAll = true`: it would roll every Deployment,
  StatefulSet and DaemonSet of the cluster on any change to anything it reads
  ([RELOADER-01](../decisions/reloader.md#reloader-01-opt-in-per-workload-off-by-default)).
  Annotate the workloads instead.
- Any `values.reloader.deployment.env.secret` entry, and a
  `reloader.deployment.env.open` entry named like a credential
  (`ALERT_WEBHOOK_URL`, `*_TOKEN`): the chart would put them in the state and
  in a ConfigMap. Create a Secret in `reloader` and name it in
  `reloader.deployment.env.existing`, or use `values_secret`.

`values_secret` is never read by OpenTofu, so the plan cannot check it: what
you put there is yours to review.

Narrower than the whole cluster: Reloader's ClusterRole lists and watches
every ConfigMap and Secret. The chart's scoped mode (`reloader.namespaces`, a
Role per namespace) is available through `values`.

### Every setting

Every attribute, at its default, and how chart values and secrets go in:

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

## Per cloud

The same on aws, gcp, azure and scaleway.

## Cloud access

None.

## Ordering

None. A workload annotated before Reloader runs is rolled at the next change
after it starts.

One replica, no leader election: a change made while Reloader restarts is
not seen, since it reacts to update events. If you cannot afford that window,
set `reloader.enableHA` and `deployment.replicas`, or `syncAfterRestart`
(which rolls every annotated workload on each restart), through `values`.

## Upgrade notes

- Reloader 3.x was in beta (3.0.0-beta.2) on 2026-10-02. The socle stays on
  the 2.x chart until 3.x is stable.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-10-02 | floci, k3s | Available in 16 s after `enabled = true`; a ConfigMap change rolled the annotated workload in under 1 s, a Secret change in 10 s, the unannotated one left at generation 1; off, removed in 26 s |

Its decisions: [reloader decisions](../decisions/reloader.md).
