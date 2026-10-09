---
title: velero decisions
description: The decisions behind the velero module, one per section, each with its status.
sidebar:
  order: 10
---

An application chooses its backup policy by two labels, and nothing else is
backed up; the bucket is the module's own, made by Crossplane, and never
deleted. The restore procedure is [Restore a backup](../guides/restore-a-backup.md).

## VELERO-01: Backup policies chosen by two labels, warned never refused

**accepted** · 2026-10-01 · [`oci/catalog/velero/resourceset.yaml`](../../oci/catalog/velero/resourceset.yaml)

**Decision.** `kube.velero.policies` is a menu of (frequency, retention)
pairs, seven by default, each one `Schedule` selecting the labels
`socle.do-now.io/backup-frequency` and `socle.do-now.io/backup-retention`
cluster-wide. A volume policy picks the method from the CSI driver. A
`ValidatingAdmissionPolicy` warns on a pair not on the menu, never refuses.

**Context.** GitOps restores objects, not volume data. An application must not
write into `velero`, where a `Schedule` reads any namespace; a typo in a
policy name would otherwise mean no backup, in silence.

**Consequences.** Nothing is backed up unless it opts in, socle namespaces
included; a label never blocks a deployment. Argo CD does not show admission
warnings; the audit annotation is what a dashboard counts.

**Sources.** Velero 1.18 `Schedule` and resource policies; Kubernetes `ValidatingAdmissionPolicy` (GA in 1.30); measured on a local k3s, 2026-10-01.

## VELERO-02: The bucket comes from Crossplane and is never deleted

**accepted** · 2026-10-01 · [`oci/catalog/velero/resourceset.yaml`](../../oci/catalog/velero/resourceset.yaml), [`opentofu/aws/iam.tf`](../../opentofu/aws/iam.tf)

**Decision.** The bucket `<cluster>-velero-<account id>` (versioning, SSE-S3,
public access block, noncurrent versions expire after 30 days) is a Crossplane
managed resource with `managementPolicies` lacking `Delete`. Velero's role,
under the boundary, reaches that bucket only. Crossplane's foundations role
gains one statement: create and configure buckets under `<cluster>-*`, no
`s3:Delete*`, no object action.

**Context.** Backups must outlive the cluster, the module and a mistake.
Modules own their cloud access
([SOCLE-04](socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)),
but Crossplane v2 namespaced resources have no `deletionPolicy`.

**Consequences.** Uninstalling leaves the bucket and every backup; a rebuilt
cluster of the same name adopts it. Removing it is a manual act. This is the
one foundations change for the catalog: a capability, not a module's name.

**Sources.** Crossplane v2 management policies; provider-upjet-aws 2.8.1 reads bucket tags through S3 Control (measured on floci, 2026-10-01).

## VELERO-03: EBS by CSI snapshot, EFS by file-system backup

**accepted** · 2026-10-01 · [`oci/catalog/velero/resourceset.yaml`](../../oci/catalog/velero/resourceset.yaml), [`opentofu/bootstrap/eks_addons.tf`](../../opentofu/bootstrap/eks_addons.tf)

**Decision.** EBS volumes are CSI snapshots through `VolumeSnapshotClass`
`velero-ebs` (`deletionPolicy: Retain`); EFS volumes are file-system backups by
the node-agent (Kopia); others are skipped. The bootstrap installs the
`snapshot-controller` add-on by default; the node-agent comes with the EFS
driver.

**Context.** The EFS CSI driver has no snapshots. Velero's CSI mode needs the
snapshot CRDs: without them every backup ended `PartiallyFailed` on k3s.

**Consequences.** Velero needs no EC2 permission. EBS snapshots stay in the
account and region. `velero` is `privileged` only with the node-agent, a
privileged DaemonSet.

**Sources.** Velero 1.18 CSI and file-system backup documentation; AWS's add-on order for `snapshot-controller`; measured on a local k3s, 2026-10-01.

## VELERO-04: Restore is an operator action

**accepted** · 2026-10-01 · [`oci/catalog/velero/resourceset.yaml`](../../oci/catalog/velero/resourceset.yaml)

**Decision.** Restoring is the platform team's task, with the `velero` CLI and
cluster-admin rights, following [Restore a backup](../guides/restore-a-backup.md).
No self-service restore.

**Context.** A `Restore` in `velero` can recreate or rewrite any namespace.

**Consequences.** An application team asks for a restore. The procedure ends
by deleting the `Restore`, whose finalizer otherwise holds the namespace when
the module goes.

**Sources.** Measured on floci, 2026-10-02: a `Restore` left in place held `velero` in `Terminating` once the module was off.

## VELERO-05: S3 Object Lock on the bucket

**proposed** · 2026-10-01

**Decision.** Not decided. The bucket is created without Object Lock today.

**Context.** Versioning and a one-bucket role protect against a mistake, not
an attacker holding the role or the account. Object Lock makes versions
undeletable for a period, and cannot be turned off once enabled.

**Consequences.** To decide before the first production install: a lock
longer than a policy's retention keeps what Velero deletes, and its cost.

**Sources.** AWS S3 Object Lock documentation.
