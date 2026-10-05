---
title: Restore a backup
description: Bring back an application's namespace, objects and volume data from a velero backup, then clean up after it.
sidebar:
  order: 7
---

This guide restores one namespace from a backup taken by the
[velero](../catalog/velero.md) module, on aws. A restore is an operator's
task: Velero runs with cluster-admin rights, so a `Restore` can rewrite any
namespace ([VELERO-04](../decisions/velero.md#velero-04-restore-is-an-operator-action)).

**What you need:**

- the `velero` CLI 1.18, the server's version (Velero 1.18.2);
- a kubeconfig with cluster-admin rights on the cluster;
- the module on (`kube.velero.enabled = true`) and its server running:
  `kubectl -n velero get deploy velero` shows it available.

The CLI works in the `velero` namespace by default, which is the module's.

**What a restore does.** It recreates the backup's objects in a namespace
that does not hold them. For an EBS volume it creates a new volume from the
CSI snapshot. For an EFS volume, Velero adds an init container,
`restore-wait`, to the restored pod and writes the files back before your
container starts. **Velero never overwrites an object that exists**: it skips
it. That is why the namespace has to be empty first, and why your GitOps
tool must not recreate it meanwhile.

## 1. Find the backup

Backups are named after their `Schedule`, `velero-<frequency>-<retention>`,
with a timestamp. List the schedules, then the backups of the one your
application uses:

```sh
velero schedule get
velero backup get --selector velero.io/schedule-name=velero-daily-7d
```

Check that the one you pick holds what you expect: `Phase: Completed`, your
namespace among its resources, and its volumes (`CSI Snapshots` for EBS, `Pod
Volume Backups` for EFS):

```sh
velero backup describe <backup> --details
```

## 2. Suspend your GitOps sync

If Argo CD (or another GitOps tool) manages the namespace, stop it from
syncing. Otherwise it recreates an empty claim at once, and Velero then skips
the claim it should have restored.

```sh
argocd app set <app> --sync-policy none
```

Or remove `automated` from the Application's `syncPolicy` in Git.

## 3. Delete the namespace

If the namespace still exists, delete it and wait until it is gone:

```sh
kubectl delete namespace <namespace> --wait
```

## 4. Restore

```sh
velero restore create <restore> --from-backup <backup> --include-namespaces <namespace> --wait
```

`--include-namespaces` keeps the restore to that namespace: a backup of a
policy selects every labelled object of the cluster.

## 5. Check the result

```sh
velero restore describe <restore> --details
kubectl -n <namespace> get pvc,pods
```

The restore is `Completed` with no error, every claim is `Bound`, and the
pods run. For an EFS volume, `kubectl -n velero get podvolumerestores` lists
one `Completed` entry per volume. Then check the data itself, from inside
your application.

A restore `PartiallyFailed` lists what failed under `Errors`; its log is
`velero restore logs <restore>`.

## 6. Resume your GitOps sync

The restored objects are the ones Git describes, so Argo CD adopts them:

```sh
argocd app set <app> --sync-policy automated
```

Or restore `automated` in Git.

## 7. Delete the Restore

Once you have checked the result, delete the `Restore`, **while the module is
still on**:

```sh
velero restore delete <restore> --confirm
```

A `Restore` carries the finalizer
`restores.velero.io/external-resources-finalizer`, which only the Velero
server releases. One left in place when the module is turned off holds the
`velero` namespace in `Terminating`, since the server is gone. If that has
already happened, remove the finalizer by hand:

```sh
kubectl -n velero patch restore <restore> --type merge -p '{"metadata":{"finalizers":null}}'
```

## After a lost cluster

Rebuild the cluster with the **same name, in the same account and region**,
and turn `crossplane` and `velero` on again. The bucket's name,
`<cluster>-velero-<account id>`, is the same: Crossplane adopts the bucket the
socle left behind, and Velero reads every backup back from it at its next
sync. The EBS snapshots are still in the region. Then restore each namespace
from step 1.

A cluster rebuilt under **another name** does not find its bucket, and the
module's role can reach only its own bucket: the module offers no way to
restore from the old one.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-10-01 | local k3s, floci 2.1.0 S3 | an application's namespace deleted and restored from a node-agent backup: `Restore` `Completed` in 10 s, the claim `Bound`, the file read back unchanged |
| 2026-10-02 | floci, k3s | the same restore, then the `Restore` deleted while the server ran; a deleted `Backup` read back from the bucket; with a `Restore` left in place, the `velero` namespace held in `Terminating` once the module was off |

The full rebuild on AWS and an EBS snapshot restore have not been measured
yet.
