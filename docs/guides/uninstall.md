---
title: Uninstall
description: Turn one module off, remove the socle from a cluster, or destroy everything, and what is left behind by design.
sidebar:
  order: 4
---

Three scopes, from the smallest.

## One module

Set `kube.<module>.enabled = false` and apply. The operator garbage-collects
everything the module rendered, its namespace included
([Enable a module](enable-a-module.md#5-turn-it-off)). Turn `crossplane` off
last: the roles it created for other modules are not deleted with it.

## The socle, keeping the cluster

```sh
tofu destroy -var-file=clusters/prod.tfvars -target=module.socle
```

This removes what the bootstrap module installed. The releases go in reverse
order: the envelope, then the Flux instance, then the operator, then, on aws
and azure, CoreDNS and Cilium, and on aws the EKS add-ons. The envelope's
uninstall waits until every catalog `ResourceSet` has been finalized: the
`socle` Kustomization has `deletionPolicy: WaitForTermination`, so the
operator is never removed while it still has objects to delete
([Uninstall order](../architecture/flux-catalog.md#uninstall-order)). Measured
on floci (2026-09-30): the whole socle gone in 28 s.

After it, `flux-system` holds no `ResourceSet`, no `FluxInstance` and no
Deployment, and no namespace rendered by a `ResourceSet` is left. CI asserts
exactly that on every run (the socle's `destroyed` suite).

:::caution
Do not destroy right after turning a module on, or back on. The operator
uninstalls a `ResourceSet` from the inventory of its last completed
reconcile: if that one rendered nothing, what the next reconcile had
already applied stays in the cluster, its namespace included. Wait for the
module's `ResourceSet` to be Ready first.
:::

## Everything

```sh
tofu destroy -var-file=clusters/prod.tfvars
```

The graph deletes the releases before the cluster, and every release but
Cilium before the bootstrap nodes, which is the order the cluster needs. That
order needs the API: if the runner can no longer reach it (it left
`cluster_endpoint_public_access_cidrs`, say), remove the releases from the
state first, then destroy:

```sh
tofu state rm module.socle
tofu destroy -var-file=clusters/prod.tfvars
```

The cluster goes with whatever ran on it; only cloud objects outside the
cluster can survive (below).

## What is left behind, by design

| What | Why | How to remove it |
| --- | --- | --- |
| The Gateway API CRDs | `deletionPolicy: Orphan`: deleting a CRD deletes every Gateway and route | delete the CRDs by hand once nothing uses them, or with the cluster |
| The CRDs of `external_secrets`, `keda`, `velero`, `crossplane` | they hold your objects | as above |
| Module roles Crossplane created, when `crossplane` went first | nothing is left to reconcile or delete them | turn the modules off before Crossplane; otherwise delete the roles under `/socle/<cluster>/` in IAM |
| Velero's bucket | Crossplane may not delete a bucket of data | delete it in the cloud once its backups are no longer needed |
| A pending Velero `Restore` | its finalizer holds the module's namespace | delete the `Restore` once checked ([Restore a backup](restore-a-backup.md)) |

A `values_secret` you created goes with its module's namespace. The
`flux-system` namespace itself was created by Helm with the operator's
release and is not deleted with it, so a mirror's pull secret stays there
until the cluster goes.
