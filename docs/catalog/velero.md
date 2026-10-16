---
title: velero
description: Backup and restore of your applications' volumes and objects, chosen by two labels.
category: backup
requires:
  - module: crossplane
    clouds: [aws, gcp]
    why: its bucket and its access (an IAM role on aws, an IAM binding on gcp) are Crossplane managed resources; refused at plan otherwise
---

Velero backs up what GitOps cannot restore, the data in your applications'
volumes (EBS and EFS on aws, Persistent Disk on gcp), with the applications'
own objects, into the module's own bucket (S3 on aws, GCS on gcp). Nothing is
backed up unless an application asks with two labels. **Off by default**, on
aws and gcp. To restore:
[Restore a backup](../guides/restore-a-backup.md).

## Getting started

Turn it on with the crossplane it needs, on foundations that list `s3` in
`aws.crossplane.allowed_services` on aws, or `roles/storage.objectAdmin` in
`gcp.crossplane.allowed_roles` on gcp:

```hcl kube-start="velero"
kube = {
  crossplane = { enabled = true } # aws: the bucket and the module's role; gcp: the bucket and its binding
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
| `node_agent` | `eks_addons.efs_csi` | The node-agent, needed for EFS volumes: a privileged DaemonSet. Refused on gcp. |
| `values` | `{}` | Any [`velero` chart](https://artifacthub.io/packages/helm/vmware-tanzu/velero) value; yours win. |
| `values_secret` | `""` | A Secret in `velero` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl kube-full="velero"
kube = {
  velero = {
    enabled = false # off by default; aws and gcp, needs kube.crossplane.enabled = true

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

    node_agent = false # default: eks_addons.efs_csi; the node-agent for EFS volumes, a privileged DaemonSet; refused on gcp

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
- **What it needs**: `kube.crossplane.enabled`; on aws, `s3` in the
  foundations' `aws.crossplane.allowed_services` and
  `eks_addons.snapshot_controller` (on by default) for EBS snapshots; on gcp,
  `roles/storage.objectAdmin` in `gcp.crossplane.allowed_roles` — without it
  the binding stays not `Ready` and the server waits for it. `tofu plan`
  refuses it on azure and scaleway, without crossplane, with `node_agent` on
  gcp, and with credentials in `values`.
- **EBS and Persistent Disk volumes are snapshotted, EFS volumes copied** by
  the node-agent into the bucket; any other volume is skipped — Filestore
  included on gcp, where Autopilot refuses the node-agent's `hostPath`.
- **On gcp, `velero backup logs`, `velero restore logs`, `velero backup
  download` and what `velero backup describe` reads from the bucket fail**:
  they go through a URL signed as a Google service account, and the module
  has none (below). Read the logs from the bucket instead, with read access
  to it:
  `gcloud storage cat gs://<cluster>-velero-<project number>/backups/<backup>/<backup>-logs.gz | gunzip`.
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
`velero-plugin-for-aws:v1.14.4` on aws, `velero-plugin-for-gcp:v1.14.4` on
gcp, in the `velero` namespace (Pod Security `restricted`, `privileged` with
the node-agent). The module
([`oci/catalog/velero`](../../oci/catalog/velero/resourceset.yaml)) is what
every cloud shares: the chart, one `Schedule` per policy and the warning
admission policy. What is aws's
([`oci/clusters/aws/velero/patch.yaml`](../../oci/clusters/aws/velero/patch.yaml),
[SOCLE-32](../decisions/socle.md#socle-32-what-only-one-cloud-has-that-cloud-adds-to-the-module-as-steps)) is a step of its own: the bucket, the role, the AWS
plugin, the backup storage location, the EBS and EFS volume policy and the
`VolumeSnapshotClass` `velero-ebs`. The bucket
`<cluster>-velero-<account id>` is versioned, SSE-S3 encrypted and private,
and never deleted by the socle. What is gcp's
([`oci/clusters/gcp/velero/patch.yaml`](../../oci/clusters/gcp/velero/patch.yaml))
is the same step on GCS: the bucket `<cluster>-velero-<project number>`
(uniform bucket-level access, public access prevention enforced, versioned,
noncurrent versions deleted after 30 days, Google-managed encryption), its
binding, the GCP plugin, the backup storage location, the Persistent Disk
volume policy, the `VolumeSnapshotClass` `velero-pd` on
`pd.csi.storage.gke.io`, and `deployNodeAgent: false`. No
`VolumeSnapshotLocation` on either cloud: CSI snapshots need none.

**What the socle sets**: a non-root, read-only server; `upgradeCRDs: true`
and `cleanUpCRDs: false`, so a re-enabled module re-reads its backups from
the bucket. Requests on every cloud, disk included, since GKE Autopilot
reserves 500m / 2Gi / 1Gi for a container that states none: the server
50m / 128Mi / 512Mi (its `emptyDir`s hold the plugin and Kopia's cache), the
CRD upgrade Job 50m / 128Mi / 32Mi, the node-agent 50m / 128Mi / 512Mi, the
Kopia repository maintenance Jobs the server starts at runtime the server's
own, through `configuration.repositoryMaintenanceJob`; the plugin's init
container 10m / 32Mi / 32Mi on gcp.

**Cloud access**: on aws, an IAM role `<cluster>-velero`, declared through
Crossplane under the permissions boundary, bound to `velero/velero-server`
by Pod Identity, with object access to its own bucket only
([Module IAM](../architecture/module-iam.md)). On gcp, one
`BucketIAMMember`: `roles/storage.objectAdmin` on the module's bucket only,
for `velero/velero-server`'s own Workload Identity principal
(`principal://iam.googleapis.com/projects/<project number>/locations/global/workloadIdentityPools/<project id>.svc.id.goog/subject/ns/velero/sa/velero-server`)
— no Google service account, no key. The plugin then needs a
`serviceAccount` in the storage location to start, used only to sign
download URLs: the socle sets the placeholder `no-google-service-account`
(`object_store.go`, velero-plugin-for-gcp v1.14.4). A client who wants
signed URLs creates a Google service account, grants velero-server's
principal `roles/iam.serviceAccountTokenCreator` on it, and replaces
`configuration.backupStorageLocation` in `values` with its e-mail. No
compute role on either cloud: the CSI driver takes the snapshots with its
own identity.

**Ordering**: the module waits for the `crossplane` ResourceSet; its steps
run in order — the namespace, the cloud's step, then the chart — and the
cloud's step is healthy only once the bucket and the module's access (the
role and the Pod Identity association on aws, the binding on gcp) are
`Ready`, so the server starts with its credentials. On aws it also waits for
the Job `velero-server-pod-identity` to receive them under the server's
ServiceAccount, which aws's step creates instead of the chart: a Ready
association reaches the admission webhook seconds later ([module IAM](../architecture/module-iam.md#the-ordering-chain)). On gcp tokens
are exchanged at call time, so nothing more is needed there. Turning it off, the
binding goes with the module on gcp; the bucket stays on both.

**Measured** on floci k3s, 2026-10-02: a labelled claim backed up, its
namespace deleted and restored in 10 s, the file read back unchanged; off,
the role deleted and the bucket kept. EBS snapshots and Pod Identity on EKS
are not measured yet. On gcp, `velero-module-gke` (labels `cloud: gcp`,
`platform: gke`) runs by hand against the sandbox's GKE Autopilot: the
bucket and its binding `Ready`, the server `Available` on its own principal,
a Persistent Disk snapshot backed up and restored with its data; first proven
with the earlier GCP work on 2026-10-07, passed again on this layout on
2026-10-16 (artifact `0.0.0-feat-gcp-parity.d896756`, 250 s), and turning the module off removed its
binding from the project.

</details>
