---
title: velero decisions
description: The decisions behind the velero module, one per section, each with its status.
sidebar:
  order: 10
---

The decisions behind backup and restore. The two to know first: an
application chooses its backup policy by two labels, and nothing else is
backed up ([VELERO-01](#velero-01-backup-policies-chosen-by-two-labels-warned-never-refused));
the bucket is the module's own, made by Crossplane, and the socle never
deletes it ([VELERO-02](#velero-02-the-bucket-comes-from-crossplane-and-is-never-deleted)).
The module page is [velero](../catalog/velero.md); the restore procedure is
[Restore a backup](../guides/restore-a-backup.md).

## VELERO-01: Backup policies chosen by two labels, warned never refused

**accepted** · 2026-10-01 · [`oci/catalog/velero/resourceset.yaml`](../../oci/catalog/velero/resourceset.yaml)

**Context.** GitOps restores the objects of an application, not the data in
its volumes. What to back up, how often and for how long is the
application's to say, but an application must not write into the `velero`
namespace: Velero runs with cluster-admin rights, and a `Schedule` there reads
any namespace. A typo in a policy name would mean no backup, in silence.

**Decision.** The platform offers a menu of (frequency, retention) pairs,
`kube.velero.policies`, seven by default; each is one `Schedule` selecting the
labels `socle.do-now.io/backup-frequency` and `socle.do-now.io/backup-retention`
across every namespace. An application's chart sets both on every object of
its release. A volume policy, referenced by every `Schedule`, picks the
method from the volume's CSI driver, so a chart sets nothing Velero-specific.
A native `ValidatingAdmissionPolicy` warns (`Warn`, `Audit`) on a workload or
claim whose pair is not on the menu, and never refuses.

**Consequences.** Nothing is backed up unless an application opts in, the
socle's own namespaces included. A backup label can never block a deployment.
Argo CD does not show admission warnings in its UI; the audit annotation is
what a dashboard can count. A pair nobody uses costs one empty backup per
run.

**Sources.** Velero 1.18 `Schedule`, label selectors and resource policies;
Kubernetes `ValidatingAdmissionPolicy` (GA in 1.30). Measured on a local k3s,
2026-10-01: `daily-31d` warned with the policy's message and admitted.

## VELERO-02: The bucket comes from Crossplane and is never deleted

**accepted** · 2026-10-01 · [`oci/catalog/velero/resourceset.yaml`](../../oci/catalog/velero/resourceset.yaml), [`opentofu/aws/iam.tf`](../../opentofu/aws/iam.tf)

**Context.** Backups must outlive the cluster, the module and a mistake.
Every module declares its own cloud access
([SOCLE-04](socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)),
but a bucket is a new kind of resource for Crossplane, and namespaced managed
resources have no `deletionPolicy` in Crossplane v2. S3 bucket names are
global.

**Decision.** The module declares its bucket, `<cluster>-velero-<account id>`,
with versioning, SSE-S3, the public access block and a lifecycle expiring
noncurrent versions after 30 days, as Crossplane managed resources whose
`managementPolicies` are `[Observe, Create, Update, LateInitialize]`, without
`Delete`. Its own IAM role, under `/socle/<cluster>/` and the permissions
boundary, reaches that bucket's objects and nothing else: S3 only, no EC2.
Crossplane's own identity, in the foundations, gains one statement:
create and configure buckets under `<cluster>-*`, with no `s3:Delete*` and no
object action.

**Consequences.** Turning the module off, or uninstalling the socle, deletes
the Kubernetes objects and leaves the bucket and every backup; the guarantee
holds even if a managed resource is edited, since Crossplane is refused the
action. A cluster rebuilt with the same name in the same account adopts the
bucket by its external name. A backup deleted at its TTL, or by whoever holds
the role, stays recoverable as noncurrent versions for 30 days. Removing a
bucket is a manual act in the AWS account. This is the one place the
foundations changed for the catalog: a capability (buckets under the
cluster's prefix), not a module's name.

**Sources.** Crossplane v2 management policies; provider-upjet-aws 2.8.1,
which reads a bucket's tags through S3 Control (measured on floci,
2026-10-01).

## VELERO-03: EBS by CSI snapshot, EFS by file-system backup

**accepted** · 2026-10-01 · [`oci/catalog/velero/resourceset.yaml`](../../oci/catalog/velero/resourceset.yaml), [`opentofu/bootstrap/eks_addons.tf`](../../opentofu/bootstrap/eks_addons.tf)

**Context.** EBS volumes have native snapshots through the EBS CSI driver and
the CSI snapshot controller. The EFS CSI driver has no snapshots. Velero's
CSI mode needs the snapshot CRDs: without them every backup ended
`PartiallyFailed`, measured on k3s.

**Decision.** An EBS volume is a CSI snapshot through the `VolumeSnapshotClass`
`velero-ebs` (`deletionPolicy: Retain`, Velero deletes the snapshot when the
backup expires); an EFS volume is a file-system backup by the node-agent
(Kopia) into the bucket. Any other volume is skipped. The bootstrap installs
the `snapshot-controller` EKS add-on by default, before the EBS driver; Velero's
`EnableCSI` and the class are rendered only when it is there. The node-agent,
a privileged DaemonSet, is installed only when `node_agent` is on, by default
when the EFS driver is.

**Consequences.** Velero needs no EC2 permission: the EBS driver takes the
snapshots with its own role. EBS snapshots stay in the account and region, so
a lost account or region takes them along. The `velero` namespace is
`privileged` only with the node-agent. Kopia under a read-only root
filesystem needs two `emptyDir`s, `/udmrepo` and `/.cache`.

**Sources.** Velero 1.18 CSI snapshot and file-system backup documentation;
AWS's add-on order for `snapshot-controller`; measured on a local k3s,
2026-10-01.

## VELERO-04: Restore is an operator action

**accepted** · 2026-10-01 · [`oci/catalog/velero/resourceset.yaml`](../../oci/catalog/velero/resourceset.yaml)

**Context.** A `Restore` in the `velero` namespace can recreate or rewrite
any namespace. An application team could choose its policy without being
able to restore.

**Decision.** Restoring is the platform team's task, with the `velero` CLI
and cluster-admin rights, following [Restore a backup](../guides/restore-a-backup.md).
No self-service restore.

**Consequences.** An application team asks for a restore. The procedure
suspends the GitOps sync, empties the namespace, restores, checks, resumes the
sync and deletes the `Restore`, whose finalizer otherwise holds the namespace
when the module goes.

**Sources.** Measured on floci, 2026-10-02: a `Restore` left in place held
the `velero` namespace in `Terminating` once the module was off.

## VELERO-05: S3 Object Lock on the bucket

**proposed** · 2026-10-01

**Context.** Versioning and a role limited to one bucket protect against a
mistake, not against an attacker holding that role or the account: noncurrent
versions can be deleted. S3 Object Lock makes object versions undeletable
for a retention period. It needs versioning, which the bucket has, and once
enabled on a bucket it cannot be turned off.

**Decision.** Not decided. The bucket is created without Object Lock today.

**Consequences.** To decide before the first production install: a lock
longer than a policy's retention keeps what Velero deletes at its TTL, and
the bucket's cost with it.

**Sources.** AWS S3 Object Lock documentation.
