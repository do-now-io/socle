---
title: Uninstall
description: Turn one module off, remove the socle from a cluster, or destroy everything, and what is left behind by design.
sidebar:
  order: 4
---

Three scopes, from the smallest.

## One module

Set `kube.<module>.enabled = false` and apply
([Enable a module](enable-a-module.md#5-turn-it-off)). Turn `crossplane` off
last: the roles it created for other modules stay otherwise.

## The socle, keeping the cluster

1. Wait for every module's `ResourceSet` to be Ready, if you just turned one
   on.
2. Destroy the bootstrap module:

   ```sh
   tofu destroy -var-file=clusters/prod.tfvars -target=module.socle
   ```

`flux-system` is then left with no `ResourceSet`, `FluxInstance` or
Deployment, and no module namespace remains (28 s on floci, 2026-09-30).

:::caution
Destroying right after turning a module on can leave that module's objects,
namespace included, in the cluster. Step 1 prevents it.
:::

<details>
<summary>Under the hood</summary>

The releases go in reverse: the envelope, the Flux instance, the operator,
then on aws and azure CoreDNS and Cilium, and on aws the EKS add-ons. The
`socle` Kustomization's `deletionPolicy: WaitForTermination` holds the
envelope until every catalog `ResourceSet` is finalized, so the operator is
never removed with work left
([Uninstall order](../architecture/flux-catalog.md#uninstall-order)). The
operator uninstalls from the inventory of its last completed reconcile,
hence step 1. CI asserts the empty result on every run (the `destroyed`
suite).

</details>

## Everything

```sh
tofu destroy -var-file=clusters/prod.tfvars
```

The releases go before the cluster, which needs the API. If the runner can no
longer reach it (it left `cluster_endpoint_public_access_cidrs`, say), drop
the releases from the state first:

```sh
tofu state rm module.socle
tofu destroy -var-file=clusters/prod.tfvars
```

## What is left behind, by design

| What | Why | How to remove it |
| --- | --- | --- |
| The Gateway API CRDs | deleting a CRD deletes every Gateway and route | by hand once unused, or with the cluster |
| The CRDs of `external_secrets`, `keda`, `velero`, `crossplane` | they hold your objects | as above |
| Module roles, when `crossplane` went first | nothing is left to delete them | delete the roles under `/socle/<cluster>/` in IAM |
| Velero's bucket | Crossplane may not delete a bucket of data | in the cloud, once its backups are not needed |
| A pending Velero `Restore` | its finalizer holds the namespace | delete the `Restore` ([Restore a backup](restore-a-backup.md)) |
| A mirror's pull secret | `flux-system` outlives the operator's release | with the cluster |
