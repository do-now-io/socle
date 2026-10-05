---
title: reloader decisions
description: The decisions behind the reloader module, one per section, each with its status.
sidebar:
  order: 10
---

Reloader rolls a workload only when the workload asks for it by annotation;
`autoReloadAll` is refused and the module is off by default.

## RELOADER-01: Opt-in per workload, off by default

**accepted** · 2026-10-02 · [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf), [`oci/catalog/reloader/resourceset.yaml`](../../oci/catalog/reloader/resourceset.yaml)

**Decision.** Reloader rolls only workloads annotated
`reloader.stakater.com/auto`, `secret.reloader.stakater.com/reload` or
`configmap.reloader.stakater.com/reload`. The plan refuses
`autoReloadAll = true`, and the module is off by default.

**Context.** `autoReloadAll` restarts every workload of the cluster, tenants
included, and whether a restart is safe is the workload's property. Reloader
reads every ConfigMap and Secret of the cluster by design.

**Consequences.** Reading every Secret is a grant the client makes by turning
the module on; `reloader.namespaces` narrows it. `values_secret` is not read
by OpenTofu, so a Secret could still set `autoReloadAll`.

**Sources.** Stakater Reloader's documentation (annotations, `autoReloadAll`, `reloader.namespaces`).

## RELOADER-02: The annotations strategy

**accepted** · 2026-10-02 · [`oci/catalog/reloader/resourceset.yaml`](../../oci/catalog/reloader/resourceset.yaml)

**Decision.** `reloadStrategy: annotations`.

**Context.** The default strategy writes a `STAKATER_*` env variable into the
pod template; `annotations` writes `reloader.stakater.com/last-reloaded-from`.
Both show as a GitOps diff.

**Consequences.** One annotation is easy to ignore in a GitOps diff (Argo CD's
`ignoreDifferences`, a Flux drift exclusion); an injected `env` entry is not.
The annotation also names the object that changed.

**Sources.** Stakater Reloader's documentation (reload strategies).
