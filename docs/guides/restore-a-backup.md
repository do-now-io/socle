---
title: Restore a backup
description: Bring back an application's namespace, objects and volume data from a velero backup, then clean up after it.
sidebar:
  order: 7
---

This guide restores one namespace from a backup taken by the
[velero](../catalog/velero.md) module, on AWS or GCP. It is an operator's
task: a `Restore` can rewrite any namespace.

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

On GCP, what `describe` reads from the bucket, and `velero backup logs`, fail:
they go through a URL signed as a Google service account, which the module
has none of ([velero](../catalog/velero.md#good-to-know)). Read the logs from
the bucket:

```sh
gcloud storage cat gs://<cluster>-velero-<project number>/backups/<backup>/<backup>-logs.gz | gunzip
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
`velero restore logs <restore>`, or on GCP
`gs://<cluster>-velero-<project number>/restores/<restore>/restore-<restore>-logs.gz`.

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

Rebuild the cluster with the **same name, in the same account and region
on AWS, in the same project on GCP**, and turn `crossplane` and `velero` on
again: Crossplane adopts the bucket
left behind, and Velero reads every backup back from it. Then restore from
step 1. A cluster rebuilt under another name cannot reach the old bucket.

Measured on floci k3s, 2026-10-02: a namespace restored from a node-agent
backup, `Completed` in 10 s, the file read back unchanged. Measured on the
sandbox's GKE Autopilot, 2026-10-16: a Persistent Disk snapshot backed up and
restored with its data. The full rebuild and an EBS snapshot restore on AWS
are not measured yet.
