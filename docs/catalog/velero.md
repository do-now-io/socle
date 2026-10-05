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
EBS and EFS volumes, together with the applications' own objects, into the
module's own S3 bucket. Nothing is backed up unless an application asks for
it with two labels. aws only, off by default. Restoring is an operator's
task: [Restore a backup](../guides/restore-a-backup.md).

## Getting started

Turn it on with the crossplane it needs, on a cluster whose foundations list
`s3` in `aws.crossplane.allowed_services`. The seven default policies are
there at once; label an application to use one.

```hcl title="terraform.tfvars" kube-start="velero"
kube = {
  crossplane = { enabled = true }
  velero = {
    enabled = true
  }
}
```

After apply, `kubectl -n velero get schedules` lists one `Schedule` per
policy, and `kubectl -n velero get backupstoragelocations` shows `default`
`Available`.

## What it installs

| | |
| --- | --- |
| Chart | `velero` `12.2.0` (Velero 1.18.2) from `https://vmware-tanzu.github.io/helm-charts`, plugin `velero/velero-plugin-for-aws:v1.14.4` |
| Namespace | `velero`: Pod Security `restricted`, or `privileged` when `node_agent` is on |
| Objects | the namespace; the bucket and its settings, the IAM role and its Pod Identity association (Crossplane managed resources); a child ResourceSet `velero-workload` with the chart, the volume policy, one `Schedule` per policy, the `VolumeSnapshotClass` `velero-ebs`, and a `ValidatingAdmissionPolicy` that warns on an unknown label pair |

**The bucket**, `<cluster>-velero-<account id>`, in the cluster's region:
versioned, encrypted with SSE-S3 (`AES256`), every public access switch on,
noncurrent versions expired after 30 days, incomplete multipart uploads
aborted after 7. The socle never deletes it: turning the module off, or
uninstalling the socle, leaves the bucket and every backup in it
([VELERO-02](../decisions/velero.md#velero-02-the-bucket-comes-from-crossplane-and-is-never-deleted)).
A backup Velero deletes at its TTL stays as noncurrent versions for 30 days.

**How each volume is backed up**, by its CSI driver
([VELERO-03](../decisions/velero.md#velero-03-ebs-by-csi-snapshot-efs-by-file-system-backup)):

| Volume | Method | Where the data goes |
| --- | --- | --- |
| EBS (`ebs.csi.aws.com`) | CSI snapshot, through the `VolumeSnapshotClass` `velero-ebs` (`deletionPolicy: Retain`) | EBS snapshots in the account and region; the bucket holds the metadata |
| EFS (`efs.csi.aws.com`) | file-system backup by the node-agent (Kopia) | the bucket |
| anything else | skipped | — |

**The server** runs as uid 65532, non-root, no privilege escalation, a
read-only root filesystem, every capability dropped. It gets its AWS
credentials from Pod Identity, through the ServiceAccount `velero/velero-server`:
no key anywhere. The node-agent, when on, is a privileged DaemonSet: it reads
the kubelet's pod volumes from the host.

### Choosing a backup: two labels

An application opts in with two labels on **every object its chart renders**
(its common labels), not only the PersistentVolumeClaims:

```yaml
socle.do-now.io/backup-frequency: daily
socle.do-now.io/backup-retention: 30d
```

Each pair is a policy: one `Schedule`, `velero-<frequency>-<retention>`,
which selects both labels across every namespace. The defaults:

| frequency | retention | Cron (UTC) |
| --- | --- | --- |
| `hourly` | `24h` | `0 * * * *` |
| `hourly` | `48h` | `0 * * * *` |
| `daily` | `7d` | `0 2 * * *` |
| `daily` | `30d` | `0 2 * * *` |
| `weekly` | `30d` | `30 2 * * 0` |
| `weekly` | `90d` | `30 2 * * 0` |
| `monthly` | `90d` | `0 3 1 * *` |

A pair no object uses costs one empty backup per run, metadata only. Each
`Schedule` also runs once when it is created.

**A pair that is not a policy is warned, not refused.** `retention: 31d`
would mean no backup, silently. A `ValidatingAdmissionPolicy` on
Deployments, StatefulSets, DaemonSets and PersistentVolumeClaims carrying the
frequency label prints a warning to whoever applies it, and records an audit
annotation; the object is admitted. Argo CD does not show admission warnings
in its UI.

The objects travel with the data, the release's Secrets included, into the
encrypted bucket only the module's role reads. An application never writes in
the `velero` namespace: Velero runs with cluster-admin rights, so a
`Schedule` or a `Restore` there reads or rewrites any namespace. Keep that
namespace to your platform team
([VELERO-04](../decisions/velero.md#velero-04-restore-is-an-operator-action)).

## What you can set

Under `kube.velero` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on. |
| `policies` | the seven pairs above | A list of `{ frequency, retention, schedule }`: one `Schedule` each. Setting it replaces the whole list. |
| `node_agent` | `eks_addons.efs_csi` (`false`) | Installs the node-agent, needed for EFS volumes; the namespace becomes `privileged`. |
| `values` | `{}` | Any `velero` chart value; yours win over the socle's. |
| `values_secret` | `""` | A Secret you create in `velero` with a `values.yaml` key, merged last. |

```hcl
aws = { crossplane = { allowed_services = ["s3"] } }   # the foundations
kube = {
  crossplane = { enabled = true }
  velero     = { enabled = true }
}
```

Refused at plan:

- `enabled = true` on aws without `kube.crossplane.enabled = true`: without
  Crossplane there is no bucket and no role.
- `enabled = true` on aws with no `region` passed to the bootstrap module (the
  aws root wires `var.aws.region`): the bucket and the Pod Identity association
  are regional.
- The module on any cloud but aws: it is not offered there.
- A `policies` entry whose `frequency` is not 1 to 24 lowercase letters,
  digits or dashes, whose `retention` is not a whole number of hours or days
  (`48h`, `30d`), whose `schedule` is not five cron fields, with any other
  key, or a pair listed twice.
- In `values`: `credentials.secretContents`, `credentials.extraEnvVars`, a
  `Secret` in `extraObjects`, a `configuration.extraEnvVars` entry with a
  literal value named like a credential. Name a Secret you created through
  `credentials.existingSecret` instead.

Two prerequisites outside `kube`:

- The foundations' `aws.crossplane.allowed_services` must include `s3`, or
  the permissions boundary refuses the module's role.
- `eks_addons.snapshot_controller` (`true` by default) installs the CSI
  snapshot controller and its CRDs. Without it the socle renders neither
  Velero's CSI feature (`EnableCSI`) nor the `VolumeSnapshotClass`, and EBS
  volumes are not snapshotted.

### Every setting

Every attribute, at its default, and how chart values and secrets go in:

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

## Per cloud

aws only. The module is not in the gcp, azure or scaleway overlays, and the
plan refuses it there.

## Cloud access

The module declares its own access through Crossplane
([Module IAM](../architecture/module-iam.md),
[SOCLE-04](../decisions/socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)):
an IAM role `<cluster>-velero` under `/socle/<cluster>/`, with the permissions
boundary from `kube.crossplane.permissions_boundary`, bound to
`velero/velero-server` by a Pod Identity association. Its one policy:

| Actions | Resource |
| --- | --- |
| `s3:ListBucket`, `s3:GetBucketLocation` | the bucket |
| `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:PutObjectTagging`, `s3:AbortMultipartUpload`, `s3:ListMultipartUploadParts` | the bucket's objects |

No EC2 action: Velero creates `VolumeSnapshot` objects and the EBS CSI driver
takes the snapshots with its own role. Crossplane's own identity may create
and configure buckets under `<cluster>-*`, and holds no `s3:Delete*` and no
object action.

## Ordering

- The `velero` ResourceSet `dependsOn` the `crossplane` ResourceSet being
  Ready.
- Its child `velero-workload` waits for the `Bucket`, the `Role` and the
  `PodIdentityAssociation` to be `Ready`: Pod Identity injects credentials
  when the pod is admitted, so the server must start after its association.
- **To turn it off: the module first, Crossplane after.** The role is
  deleted, and Crossplane's provider must still be there to release it. The
  bucket is kept.
- **Leave no `Restore` behind.** A `Restore` carries a finalizer that only
  the Velero server releases. One left in place when the module goes holds the
  `velero` namespace in `Terminating`
  ([Restore a backup](../guides/restore-a-backup.md#7-delete-the-restore)).

## Upgrade notes

- `upgradeCRDs: true`, `cleanUpCRDs: false`: Velero's CRDs are upgraded with
  the chart and kept when the module is turned off, so a re-enabled module
  re-reads its `Backup` objects from the bucket.
- The AWS plugin is pinned with the chart: the 1.14.x line goes with Velero
  1.18.
- The CRD upgrade job uses the chart's `kubectl` image from
  `registry.k8s.io`, pinned with the chart.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-10-01 | local k3s, floci 2.1.0 S3, chart 12.2.0 | server running under `restricted`; a labelled `daily`/`7d` claim backed up by the node-agent in 10 s; the namespace deleted and restored in 10 s, the file read back unchanged; a deleted `Backup` re-read from the bucket within the sync period; `daily-31d` warned and admitted |
| 2026-10-02 | floci, k3s | the module's bucket created versioned, encrypted, public access blocked, with its lifecycle; its role under `/socle/<cluster>/` reaching that bucket only; off, the role deleted and the bucket kept; backup, restore and re-sync as above |

Not measured yet: Pod Identity on EKS, EBS CSI snapshots and their restore,
an EFS restore on AWS, a rebuilt cluster finding its backups, and Crossplane
refused a bucket deletion by IAM.

Its decisions: [velero decisions](../decisions/velero.md).
