---
title: reloader decisions
description: The decisions behind the reloader module, one per section, each with its status.
sidebar:
  order: 10
---

The decisions behind the reloader module. The one to know first: a workload
is rolled only when it carries one of Reloader's annotations, and
`autoReloadAll` is refused
([RELOADER-01](#reloader-01-opt-in-per-workload-off-by-default)). The module
page is [reloader](../catalog/reloader.md).

## RELOADER-01: Opt-in per workload, off by default

**accepted** · 2026-10-02 · [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf), [`oci/catalog/reloader/resourceset.yaml`](../../oci/catalog/reloader/resourceset.yaml)

**Context.** With `autoReloadAll`, Reloader restarts every Deployment,
StatefulSet and DaemonSet of the cluster when anything it reads changes, the
client's tenants included. Whether a restart is safe is a property of the
workload. Reloader's ClusterRole lists, gets and watches every ConfigMap and
Secret of the cluster, which is inherent to what it does.

**Decision.** Reloader rolls only the workloads annotated
`reloader.stakater.com/auto`, `secret.reloader.stakater.com/reload` or
`configmap.reloader.stakater.com/reload`. The socle sets
`autoReloadAll: false`, and the plan refuses
`kube.reloader.values.reloader.autoReloadAll = true`. The module is off by
default.

**Consequences.** A workload says itself that a restart is safe. Reading
every Secret of the cluster is a grant the client chooses by turning the
module on, not one the socle makes for him; the chart's scoped mode
(`reloader.namespaces`) narrows it through `values`. `values_secret` is never
read by OpenTofu, so a Secret could still set `autoReloadAll`: that Secret is
the client's, reviewed outside the socle.

**Sources.** Stakater Reloader's documentation (annotations,
`autoReloadAll`, `reloader.namespaces`).

## RELOADER-02: The annotations strategy

**accepted** · 2026-10-02 · [`oci/catalog/reloader/resourceset.yaml`](../../oci/catalog/reloader/resourceset.yaml)

**Context.** The chart's default strategy writes a `STAKATER_*` environment
variable into the pod template; `annotations` writes
`reloader.stakater.com/last-reloaded-from` instead. Both change the template,
so both show as a diff to a GitOps tool.

**Decision.** `reloadStrategy: annotations`.

**Consequences.** A GitOps diff can be told to ignore one annotation (Argo
CD's `ignoreDifferences`, a Flux drift exclusion); an injected entry in a
container's `env` list cannot be ignored as cleanly. The annotation also names
what changed: a JSON with the kind, namespace and name of the object.

**Sources.** Stakater Reloader's documentation (reload strategies).
