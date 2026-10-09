---
title: Restore a backup
description: Bring back an application's namespace, objects and volume data from a velero backup, then clean up after it.
sidebar:
  order: 7
---

This guide restores one namespace from a backup taken by the
[velero](../catalog/velero.md) module, on aws. It is an operator's task: a
`Restore` can rewrite any namespace.

**What you need:** the `velero` CLI 1.18, a kubeconfig with cluster-admin
rights, and the module's server running
(`kubectl -n velero get deploy velero` shows it available).

Velero never overwrites an object that exists: it skips it. The namespace
must be empty first, and stay empty until the restore.

## 1. Find the backup

Backups are named after their `Schedule`, `velero-<frequency>-<retention>`,
with a timestamp:

```sh
velero schedule get
velero backup get --selector velero.io/schedule-name=velero-daily-7d
```

Check the one you pick is `Completed` and holds your namespace and its
volumes:

```sh
velero backup describe <backup> --details
```

## 2. Suspend your GitOps sync

Otherwise Argo CD recreates an empty claim, and Velero skips the one it
should restore:

```sh
argocd app set <app> --sync-policy none
```

## 3. Delete the namespace

```sh
kubectl delete namespace <namespace> --wait
```

## 4. Restore

`--include-namespaces` keeps the restore to your namespace, since a policy's
backup holds every labelled object of the cluster:

```sh
velero restore create <restore> --from-backup <backup> --include-namespaces <namespace> --wait
```

## 5. Check the result

The restore is `Completed`, every claim `Bound`, the pods running; then check
the data from inside your application. On `PartiallyFailed`, read
`velero restore logs <restore>`.

```sh
velero restore describe <restore> --details
kubectl -n <namespace> get pvc,pods
```

## 6. Resume your GitOps sync

Argo CD adopts the restored objects:

```sh
argocd app set <app> --sync-policy automated
```

## 7. Delete the Restore

Delete it while the module is still on: its finalizer is released only by
the Velero server, and one left behind holds the `velero` namespace in
`Terminating` once the module is off.

```sh
velero restore delete <restore> --confirm
```

If the module is already off, remove the finalizer by hand:

```sh
kubectl -n velero patch restore <restore> --type merge -p '{"metadata":{"finalizers":null}}'
```

## After a lost cluster

Rebuild the cluster with the **same name, in the same account and region**,
and turn `crossplane` and `velero` on again: Crossplane adopts the bucket
left behind, and Velero reads every backup back from it. Then restore from
step 1. A cluster rebuilt under another name cannot reach the old bucket.

Measured on floci k3s, 2026-10-02: a namespace restored from a node-agent
backup, `Completed` in 10 s, the file read back unchanged. The full rebuild
on AWS and an EBS snapshot restore are not measured yet.
