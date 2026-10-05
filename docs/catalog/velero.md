---
title: velero
description: Backup and restore of your applications' volumes and objects, chosen by two labels.
category: backup
requires:
  - module: crossplane
    clouds: [aws]
    why: its bucket and IAM role are Crossplane managed resources; refused at plan otherwise
---

Velero backs up what GitOps cannot restore, the data in your applications'
EBS and EFS volumes, with the applications' own objects, into the module's
own S3 bucket. Nothing is backed up unless an application asks with two
labels. **Off by default**, aws only. To restore:
[Restore a backup](../guides/restore-a-backup.md).

## Getting started

Turn it on with the crossplane it needs, on foundations that list `s3` in
`aws.crossplane.allowed_services`:

```hcl title="terraform.tfvars" kube-start="velero"
kube = {
  crossplane = { enabled = true }
  velero = {
    enabled = true
  }
}
```

Then `kubectl -n velero get backupstoragelocations` shows `default`
`Available`.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on or off. The bucket is kept either way. |
| `policies` | seven pairs, below | A list of `{ frequency, retention, schedule }`, one `Schedule` each. Setting it replaces the whole list. |
| `node_agent` | `eks_addons.efs_csi` | The node-agent, needed for EFS volumes: a privileged DaemonSet. |
| `values` | `{}` | Any [`velero` chart](https://artifacthub.io/packages/helm/vmware-tanzu/velero) value; yours win. |
| `values_secret` | `""` | A Secret in `velero` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl title="terraform.tfvars" kube-full="velero"
kube = {
  velero = {
    enabled = false # off by default; aws only, needs kube.crossplane.enabled = true

    # One Schedule per { frequency, retention } label pair; setting it replaces the whole list.
    policies = [
      { frequency = "hourly", retention = "24h", schedule = "0 * * * *" },
      { frequency = "hourly", retention = "48h", schedule = "0 * * * *" },
      { frequency = "daily", retention = "7d", schedule = "0 2 * * *" },
      { frequency = "daily", retention = "30d", schedule = "0 2 * * *" },
      { frequency = "weekly", retention = "30d", schedule = "30 2 * * 0" },
      { frequency = "weekly", retention = "90d", schedule = "30 2 * * 0" },
      { frequency = "monthly", retention = "90d", schedule = "0 3 1 * *" },
    ]

    node_agent = false # default: eks_addons.efs_csi; the node-agent for EFS volumes, a privileged DaemonSet

    # Any value of the velero chart 12.2.0; yours win over the socle's.
    values = {
      resources     = { limits = { memory = "1Gi" } }
      configuration = { logFormat = "json" }
    }

    # A Secret you create in velero, whose values.yaml key holds chart values
    # that must not reach the OpenTofu state; merged last.
    values_secret = "velero-values"
  }
}
```

## Good to know

- **An application opts in with two labels on every object its chart
  renders**, not only its claims: `socle.do-now.io/backup-frequency: daily`
  and `socle.do-now.io/backup-retention: 30d`. Each pair of `policies` is one
  `Schedule`, `velero-<frequency>-<retention>`. A pair that is not a policy
  is admitted with a warning, and never backed up.
- **What it needs**: `kube.crossplane.enabled`, `s3` in the foundations'
  `aws.crossplane.allowed_services`, and `eks_addons.snapshot_controller`
  (on by default) for EBS snapshots. `tofu plan` refuses it off aws, without
  crossplane, and with credentials in `values`.
- **EBS volumes are snapshotted, EFS volumes copied** by the node-agent into
  the bucket; any other volume is skipped.
- **Turn it off before crossplane**, so the role can be released, and leave
  no `Restore` behind: its finalizer holds the `velero` namespace in
  `Terminating` ([Restore a backup](../guides/restore-a-backup.md#7-delete-the-restore)).
- **Keep the `velero` namespace to your platform team**: Velero runs with
  cluster-admin rights, so a `Schedule` or `Restore` there reads or rewrites
  any namespace.

<details>
<summary>Under the hood</summary>

**Installed**: chart `velero` 12.2.0 (Velero 1.18.2) from
`https://vmware-tanzu.github.io/helm-charts`, with
`velero-plugin-for-aws:v1.14.4`, in the `velero` namespace (Pod Security
`restricted`, `privileged` with the node-agent). A child ResourceSet
`velero-workload` holds the chart, one `Schedule` per policy, the
`VolumeSnapshotClass` `velero-ebs` and the warning admission policy. The
bucket `<cluster>-velero-<account id>` is versioned, SSE-S3 encrypted and
private, and never deleted by the socle.

**What the socle sets**: a non-root, read-only server; `upgradeCRDs: true`
and `cleanUpCRDs: false`, so a re-enabled module re-reads its backups from
the bucket.

**Cloud access**: an IAM role `<cluster>-velero`, declared through
Crossplane under the permissions boundary, bound to `velero/velero-server`
by Pod Identity, with object access to its own bucket only
([Module IAM](../architecture/module-iam.md)).

**Ordering**: the module `dependsOn` crossplane; the server starts once the
bucket, role and Pod Identity association are `Ready`.

**Measured** on floci k3s, 2026-10-02: a labelled claim backed up, its
namespace deleted and restored in 10 s, the file read back unchanged; off,
the role deleted and the bucket kept. EBS snapshots and Pod Identity on EKS
are not measured yet.

**Decisions**: [velero decisions](../decisions/velero.md).

</details>
