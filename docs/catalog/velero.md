# Catalog module `velero`

Velero backs up the state GitOps cannot restore — the data in the
application's persistent volumes, EBS and EFS on AWS, Persistent Disk on GCP —
together with the application's own objects, and restores them. One catalog
module, on AWS and GCP. Issue #58; the catalog contract is [docs/flux-catalog.md](../flux-catalog.md)
§6, the cloud-access contract [crossplane.md](crossplane.md) §3.

> Status: **implemented, draft PR #74.** Designed and agreed on 2026-10-01.
> The chart, its values and a real backup and restore were measured on a
> local k3s and in CI on floci (§9, *Measured*). The sandbox proof is still
> to come.
>
> GCP: implemented with the GCP parity work (2026-10-07) — rendered,
> kubeconformed against provider-upjet-gcp v3.0.0's CRDs and `helm template`d;
> its sandbox proof (§9, *On the GCP sandbox*) is still to come.

| Question | Position |
| --- | --- |
| Chart | Official `velero` 12.2.0 (app 1.18.2), from the `HelmRepository` `https://vmware-tanzu.github.io/helm-charts` — no public OCI chart (GHCR refuses an anonymous pull, measured 2026-10-01). Plugin `velero/velero-plugin-for-aws:v1.14.4` |
| Clouds | aws and gcp: `catalog_clouds` lists `velero = ["aws", "gcp"]`. GCP's differences are in §2 *On GCP* |
| Default | Off: it needs Crossplane, which is off by default |
| What is backed up | Only what an application **opts into**, by two labels its chart sets on every object of its release (§3). Nothing else — the socle's own namespaces included |
| Policies | Seven (frequency, retention) pairs by default, each one `Schedule`; the client lists its own in `kube.velero.policies` |
| EBS volumes | CSI snapshots, native, kept in EBS; the bucket holds the metadata |
| EFS volumes | File-system backup (node-agent, Kopia) into the bucket — the EFS CSI driver has no snapshots |
| Persistent Disk volumes (gcp) | CSI snapshots by GKE's `pd.csi.storage.gke.io`, class `velero-pd`. No file-system backup: Autopilot refuses the node-agent |
| Bucket | The module's own, through Crossplane: versioned, SSE-S3, public access blocked, noncurrent versions expired after 30 days, never deleted (`managementPolicies` without `Delete`, and no `s3:Delete*` for Crossplane). On GCP the same on GCS, with uniform bucket-level access |
| Cloud access | The module's own IAM role through Crossplane: S3 object actions on its bucket only. No EC2: the EBS CSI driver takes the snapshots with its own role. On GCP `roles/storage.objectAdmin` on its bucket, bound to the pod's own principal — no Google service account |
| Restore | An ops runbook (§7), never self-service: an application may choose its policy, never restore |

## 1. What is installed

Two layers, after the `crossplane` ResourceSet is Ready, in the shape
external-dns set ([external-dns.md](external-dns.md), *Ordering*):

1. **The `velero` ResourceSet**:
   - the `Namespace` `velero` — Pod Security `restricted`, or `privileged`
     when `node_agent` is on (the node-agent DaemonSet mounts the kubelet's
     pod volumes from the host);
   - the bucket and its settings, Crossplane managed resources (§2);
   - the module's `Role` and `PodIdentityAssociation` (§2) — on GCP one
     `BucketIAMMember` instead;
   - the child ResourceSet `velero-workload`.
2. **The child `velero-workload`**, which `dependsOn` the bucket, the Role and
   the association being `Ready` (`readyExpr` on `Ready=True`) — on GCP the
   bucket and the `BucketIAMMember`:
   - `HelmRepository` `vmware-tanzu`, the two values ConfigMaps, the
     `HelmRelease` `velero`;
   - the volume policy ConfigMap (§3);
   - the `VolumeSnapshotClass` for `ebs.csi.aws.com`, labelled
     `velero.io/csi-volumesnapshot-class: "true"`, rendered only when the
     snapshot-controller add-on is on (§8) — on GCP `velero-pd`, for
     `pd.csi.storage.gke.io`, when `storage.snapshots` is on, which it always
     is on gcp (GKE ships the snapshot controller);
   - one `Schedule` per entry of `kube.velero.policies`;
   - the `ValidatingAdmissionPolicy` that warns on an unknown pair (§3).

Every object carries the reconcile toggle. The ServiceAccount is fixed,
`velero/velero-server`: it is the subject the association binds.

## 2. The bucket and the role, through Crossplane

### The bucket

| Object (`s3.aws.m.upbound.io/v1beta1`) | Setting |
| --- | --- |
| `Bucket` `velero` | external name `<cluster>-velero-<account_id>` (S3 names are global; two clusters may share a name across accounts), region `inputs.cluster.region`, tagged with the socle's cluster tags |
| `BucketVersioning` | `Enabled` |
| `BucketServerSideEncryptionConfiguration` | `AES256` (SSE-S3) |
| `BucketPublicAccessBlock` | all four switches on |
| `BucketLifecycleConfiguration` | noncurrent versions expire after 30 days; incomplete multipart uploads aborted after 7 |

**None of them can delete anything.** Namespaced managed resources have no
`deletionPolicy` in Crossplane v2. Each one carries
`managementPolicies: [Observe, Create, Update, LateInitialize]` instead, without
`Delete`. Turning the module off, or uninstalling the socle, deletes the
Kubernetes objects and leaves the bucket, its settings and every backup in
place. Crossplane's own identity has no `s3:Delete*` action either (§8), so
the guarantee holds even if a managed resource is edited by hand. A rebuilt cluster with the same name
in the same account adopts the bucket by its external name (§7, scenario 2).

Velero deleting a backup at its TTL deletes the objects; versioning keeps
them as noncurrent versions for 30 days, so a deletion — by mistake or by
whoever got the role — is recoverable for a month.

`BucketOwnershipControls` is not in provider-upjet-aws v2.8.1's namespaced
CRDs (checked 2026-10-01); S3's default since April 2023, owner enforced with
ACLs disabled, is what the socle wants anyway.

### The role

As [crossplane.md](crossplane.md) §3 has it: `Role` `velero/velero-server`,
IAM name `<cluster>-velero`, path `/socle/<cluster>/`, the boundary from
`inputs.modules.crossplane.permissions_boundary`, trust `pods.eks.amazonaws.com`
for `sts:AssumeRole` and `sts:TagSession`, and one inline policy `bucket`:

| Sid | Actions | Resource |
| --- | --- | --- |
| `ListTheBucket` | `s3:ListBucket`, `s3:GetBucketLocation` | the bucket's ARN |
| `ObjectsInTheBucket` | `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:PutObjectTagging`, `s3:AbortMultipartUpload`, `s3:ListMultipartUploadParts` | `<bucket ARN>/*` |

No `ec2:` action: in CSI mode Velero creates `VolumeSnapshot` objects and the
EBS CSI driver calls EC2 with its own role (`opentofu/bootstrap/eks_addons.tf`).
The client allows one service, `s3`:

```hcl
aws  = { crossplane = { allowed_services = ["s3"] } }   # the boundary, foundations
kube = {
  crossplane = { enabled = true }
  velero     = { enabled = true }
}
```

### On GCP

Same shape, GCP's objects. The access guard is
`and (eq inputs.cloud "gcp") inputs.modules.crossplane.enabled`.

| Object | Setting |
| --- | --- |
| `Bucket` `velero` (`storage.gcp.m.upbound.io/v1beta2`) | external name `<cluster>-velero-<project_number>` — GCS names are global; under the `<cluster>-` prefix, the only one Crossplane's bucket role may create (`opentofu/gcp/iam.tf`). `location` the cluster's region in capitals, **`uniformBucketLevelAccess: true`**, `publicAccessPrevention: enforced`, versioning on, one lifecycle rule deleting noncurrent versions 30 days old, labels `socle-cluster`, `socle-module`. `managementPolicies: [Observe, Create, Update, LateInitialize]` |
| `BucketIAMMember` `velero-server` (`storage.gcp.m.upbound.io/v1beta1`) | `roles/storage.objectAdmin` on that bucket, member `principal://iam.googleapis.com/projects/<project_number>/locations/global/workloadIdentityPools/<project_id>.svc.id.goog/subject/ns/velero/sa/velero-server` |

One object where AWS has five: GCS carries versioning, public access
prevention and the lifecycle on the bucket itself, and encrypts every object
at rest with Google-managed keys by default — SSE-S3's equivalent, nothing to
declare. No abort rule for incomplete uploads: the plugin writes through the
JSON API's resumable uploads, which GCS expires itself after a week.

**Never deleted, here too.** No `Delete` in the bucket's management policies,
and Crossplane's bucket role has no `storage.buckets.delete` (nor
`storage.buckets.list`, nor any object permission): turning the module off
releases the `Bucket` and leaves the bucket and its backups. Never deleted
is not never changed: `storage.buckets.update` still lets Crossplane rewrite
the bucket's lifecycle rules and uniform bucket-level access, as it rewrites
the lifecycle on AWS. The
`BucketIAMMember` keeps the default policies, so the binding **is** removed
with the module — nothing reaches the bucket once Velero is gone.

**Uniform bucket-level access is a requirement, not a preference.** The
foundations refuse every predefined admin role in `allowed_roles` but
`roles/storage.objectAdmin`, because its one IAM-granting permission,
`storage.objects.setIamPolicy`, writes object ACLs — and a bucket with
uniform access has none. On a bucket without it, Velero's principal could
make any backup readable by anyone.

**No Google service account.** velero-server's Kubernetes ServiceAccount is
the principal itself (Workload Identity Federation): no
`iam.gke.io/gcp-service-account` annotation, no key. The plugin,
`velero/velero-plugin-for-gcp:v1.14.4`, takes Application Default
Credentials from the GKE metadata server. One consequence, read in the
plugin's source (`velero-plugin-for-gcp/object_store.go` at v1.14.4):

- On metadata-server credentials, `Init` goes through
  `initFromComputeEngine`, which **refuses to start without
  `config.serviceAccount`** in the `BackupStorageLocation` ("serviceAccount
  is expected to be provided as an item in BackupStorageLocation's config") —
  although the plugin's `backupstoragelocation.md` calls it optional.
- That value is used for one thing: `CreateSignedURL` signs through IAM
  `signBlob` as `projects/-/serviceAccounts/<serviceAccount>`. Backups,
  restores, the bucket's validation and the sync never sign anything: they
  read and write objects with the pod's own token.

So the socle sets a placeholder, `serviceAccount: no-google-service-account`,
which names no account that can exist (not an e-mail). **What does not work
on GCP:** everything the `velero` CLI downloads through a signed URL — a
`DownloadRequest` — fails, the CLI timing out on the URL: `velero backup
logs`, `velero restore logs`, `velero backup download`, and what `describe`
reads from the bucket — its volumes section even without `--details`
(`pkg/cmd/util/output/backup_describer.go`, Velero 1.18.2), and with it the
resource list and the item operations. The objects are in the
bucket all the same; with read access to it, an operator reads them
directly:

```sh
gcloud storage cat gs://<cluster>-velero-<project_number>/backups/<backup>/<backup>-logs.gz | gunzip
gcloud storage cat gs://<cluster>-velero-<project_number>/restores/<restore>/restore-<restore>-logs.gz | gunzip
```

A client who wants signed URLs creates a Google service account, grants
velero-server's principal `roles/iam.serviceAccountTokenCreator` on it, and
replaces the whole `configuration.backupStorageLocation` list in `values`
with its e-mail as `serviceAccount` — the socle does not, since that is an
identity the module does not otherwise need. No `region` in the config
either: the plugin refuses any key it does not know.

**No compute role.** In CSI mode Velero creates `VolumeSnapshot` objects and
GKE's Persistent Disk CSI driver takes the snapshots with its own identity.

The client allows one role, in the foundations:

```hcl
gcp  = { crossplane = { allowed_roles = ["roles/storage.objectAdmin"] } }  # foundations
kube = {
  crossplane = { enabled = true }
  velero     = { enabled = true }
}
```

Without it, the `BucketIAMMember` stays not `Ready` on the IAM error, and
`velero-workload` — the server — waits for it.

## 3. Backup policies: two labels, chosen by the application

### The contract an application's chart implements

A chart opts its release in with two labels on **every object it renders** —
its common labels — from values such as `backup: { frequency: daily,
retention: 30d }`:

```yaml
socle.do-now.io/backup-frequency: daily
socle.do-now.io/backup-retention: 30d
```

Every object, not only the PersistentVolumeClaims: a file-system restore
reinjects the data through an init container Velero adds to the restored pod,
which must come back with its controller; and a restore of the whole release
is Velero's beaten path (§7). The objects weigh a few KB per backup; the
release's Secrets travel with them, into an encrypted bucket nobody but the
module's role reads.

An application never writes into the `velero` namespace. Velero runs with
cluster-admin rights, so creating a `Schedule` or a `Restore` there is reading
or rewriting any namespace: that right stays with the platform team (§7).

### The pairs

Each entry of `kube.velero.policies` renders one `Schedule` named
`<frequency>-<retention>`, whose template selects the two labels across every
namespace, sets the TTL and points at the socle's storage location and volume
policy. The defaults:

| frequency | retention | Cron (UTC) | TTL |
| --- | --- | --- | --- |
| `hourly` | `24h` | `0 * * * *` | `24h` |
| `hourly` | `48h` | `0 * * * *` | `48h` |
| `daily` | `7d` | `0 2 * * *` | `168h` |
| `daily` | `30d` | `0 2 * * *` | `720h` |
| `weekly` | `30d` | `30 2 * * 0` | `720h` |
| `weekly` | `90d` | `30 2 * * 0` | `2160h` |
| `monthly` | `90d` | `0 3 1 * *` | `2160h` |

The cost of a pair nobody uses is one empty backup per run — metadata only,
48 a day for the two hourly pairs. A client who wants fewer, or others, sets
the whole list.

### What happens to each volume — the volume policy

One resource-policy ConfigMap, referenced by every `Schedule`'s
`template.resourcePolicy`:

| Condition | Action |
| --- | --- |
| `csi.driver: ebs.csi.aws.com` | `snapshot` |
| `csi.driver: efs.csi.aws.com` | `fs-backup` |
| `csi.driver: pd.csi.storage.gke.io` (gcp, instead of the two above) | `snapshot` |
| anything else | Velero's fallback: no snapshot location and no fs-backup annotation, so skipped — Filestore included on GCP |

So a chart sets the two labels and nothing Velero-specific: no
`backup.velero.io/backup-volumes` annotation per volume.

### A pair that does not exist — warned, not refused

A typo (`retention: 31d`) would mean no backup, silently. A native
`ValidatingAdmissionPolicy` (GA since Kubernetes 1.30) matches Deployments,
StatefulSets, DaemonSets and PersistentVolumeClaims carrying the frequency
label, and **warns** (`validationActions: [Warn, Audit]`) when the pair is
not one of `kube.velero.policies`. It never refuses: a backup label must not
be able to block a deployment. Its limit: Argo CD does not surface admission
warnings in its UI; the audit annotation is what a dashboard can count.

## 4. What the client may set — `kube.velero`

| Attribute | Default | Rule at plan (`opentofu/bootstrap/variables.tf`) |
| --- | --- | --- |
| `enabled` | `false` | needs `kube.crossplane.enabled` on every cloud it runs on, aws and gcp; on aws also the cluster's region and its account id — refused otherwise, naming the missing piece |
| `policies` | the seven pairs of §3 | a list of `{ frequency, retention, schedule }`; `frequency` and `retention` RFC 1123 label values, `retention` matching `^[0-9]+(h\|d)$`, `schedule` five cron fields, no pair twice |
| `node_agent` | `eks_addons.efs_csi`; `false` on gcp | a bool; off, no privileged DaemonSet and the namespace stays `restricted`. On without EFS is allowed (a client's own NFS volumes, through `values`). Refused on gcp: Autopilot forbids the node-agent's hostPath — and the template renders nothing of it there regardless |
| `values` | `{}` | the chart's secret-bearing paths refused: `credentials.secretContents`, `credentials.extraEnvVars`, a Secret in `extraObjects`, a `configuration.extraEnvVars` entry with a literal value named like a credential. A Secret is named through `credentials.existingSecret`, never inlined |
| `values_secret` | `""` | an RFC 1123 Secret name, merged last |

Velero with Crossplane off is refused at plan in v1, on every cloud it runs
on: without Crossplane there is no bucket and no role or binding. The way out — a client's own bucket and identity —
is out of scope (§10).

## 5. Fixed by the socle, not by a named attribute

In `velero-socle-values`, each overridable through `values` as the contract
says:

- **`configuration.features: EnableCSI` only where the snapshot controller
  is** (`inputs.storage.snapshots`). Without its CRDs every backup ends
  `PartiallyFailed` on the missing `VolumeSnapshot` kinds, measured on k3s.
  `snapshotsEnabled: false`, since CSI snapshots need no
  `VolumeSnapshotLocation`. `deployNodeAgent` comes from `node_agent`;
- **one `BackupStorageLocation` `default`**: provider `aws`, the module's
  bucket, region `inputs.cluster.region`, no prefix; **no
  `VolumeSnapshotLocation`** — CSI snapshots need none. On gcp: provider
  `gcp`, the bucket, and the `serviceAccount` placeholder of §2 *On GCP*;
- **`credentials.useSecret: false`**: the AWS SDK's default chain picks the
  Pod Identity credentials up — on gcp, Application Default Credentials from
  the metadata server;
- **`upgradeCRDs: true`, `cleanUpCRDs: false`**: turning the module off keeps
  the CRDs, so the `Backup` objects a re-enable re-syncs from the bucket find
  their kind;
- **the restricted security context** on the server, the CRD upgrade job and
  the maintenance jobs: uid 65532, no privilege escalation, a read-only root
  filesystem. Kopia needs two `emptyDir`s for that, `/udmrepo` and `/.cache`
  (`$HOME` is `/` for the image's user). Without them the repository never
  initialises: `mkdir /udmrepo` then `mkdir /.cache: read-only file system`,
  measured. The node-agent is the one privileged pod;
- **requests sized from the e2e** (§9), the chart's limits kept;
- **the plugin as an init container**, pinned with the chart:
  `velero-plugin-for-aws` or `velero-plugin-for-gcp`, both `v1.14.4`;
- **requests on the CRD upgrade Job** (`upgradeJobResources`, 50m / 128Mi)
  and on the plugin's init container (10m / 32Mi), on every cloud: Autopilot
  gives a container without requests 500m / 2Gi, and bills what is
  requested. Every container states its ephemeral storage too: 512Mi for the
  server, whose `emptyDir`s hold the plugin and Kopia's cache
  ([docs/gcp/sizing.md](../gcp/sizing.md)).

The volume policy and the `VolumeSnapshotClass` are objects of the
ResourceSet, not chart values: they are part of the socle's contract with the
applications.

## 6. Ordering

- The `velero` ResourceSet `dependsOn` the `crossplane` ResourceSet.
- The child `velero-workload` `dependsOn` the `Bucket`, the `Role` and the
  `PodIdentityAssociation` — on GCP the `Bucket` and the `BucketIAMMember` —
  `readyExpr` on `Ready=True`
  ([external-dns.md](external-dns.md): steps alone do not order this).
- **Off: the module first, Crossplane after** — Crossplane's own warning.
  The bucket's resources have no `Delete` in their management policies, so
  turning the module off deletes nothing in S3 — on GCP, nothing in GCS; the
  `BucketIAMMember` is deleted. The role is still deleted, and the provider
  must be there to release the finalizers.
- **Off: no `Restore` left.** Its finalizer is the server's, and the server
  goes with the module: the namespace would stay Terminating (§7, step 6).

## 7. Restore — the deliverable

Restoring is a platform-team act, with the `velero` CLI (1.18) and an admin
kubeconfig. The runbook ships in this note and the sandbox proves it (§9).

### Scenario 1 — a namespace deleted, or its data corrupted

1. **Suspend the application's Argo CD sync**, in Git (drop `automated` from
   the Application) or `argocd app set <app> --sync-policy none`. Otherwise
   Argo CD recreates an empty PVC at once, and Velero never overwrites an
   existing PVC.
2. **Delete the namespace** if it still exists.
3. **Restore**, from the backup to go back to:

   ```sh
   velero backup get --selector socle.do-now.io/backup-frequency=daily
   velero restore create --from-backup <backup> --include-namespaces <ns> --wait
   ```

   EBS: a new volume from the snapshot. EFS: Velero's init container writes the
   files back before the application's container starts.
4. **The `Restore` is `Completed`**: `velero restore describe <restore>
   --details` shows no error, the PVCs are `Bound`.
5. **Resume the Argo CD sync.** The restored objects are those Git describes:
   Argo CD adopts them.
6. **Delete the `Restore`** once checked: `velero restore delete <restore>`.
   It carries a finalizer, `restores.velero.io/external-resources-finalizer`,
   that only the server releases. A `Restore` left in place holds the
   `velero` namespace Terminating when the module is turned off (measured,
   run 36977771047). If that already happened:
   `kubectl -n velero patch restore <restore> --type merge -p '{"metadata":{"finalizers":null}}'`.

### Scenario 2 — the cluster lost, rebuilt with the same name, account and region

The socle comes back as it was; the `Bucket`'s external name finds the
orphaned bucket and Crossplane adopts it; Velero re-syncs every backup from
it (`backupSyncPeriod`). Each namespace is then restored as in scenario 1 —
the EBS snapshots are still in the region.

A cluster **renamed** does not find its bucket: pointing a second, read-only
storage location at the old bucket is a manual step, written in this note
when the sandbox has run it, and not automated in v1.

## 8. What changes outside `oci/catalog/velero/`

Four changes the module needs, each generic. The first two are exceptions to
"a new module never changes `crossplane`" and "the foundations never change
because of the catalog" ([crossplane.md](crossplane.md)); that note gains a
section saying Crossplane may manage **buckets** under the cluster's prefix,
as it manages roles under its path — a capability of the socle, which
`vmbackup` (#46) will use for its own bucket.

1. **`oci/catalog/crossplane`**: `provider-aws-s3` (v2.8.1, the family's
   version) beside `iam` and `eks`, in the `config` child's `dependsOn`; the
   floci `ClusterProviderConfig` of the tests gains `s3` in its `services`.
2. **`opentofu/aws/iam.tf`**, Crossplane's own policy gains one statement,
   `ManageBucketsUnderTheClusterPrefix`, on `arn:aws:s3:::<cluster>-*`: create
   the bucket, read its configuration, and write its versioning, encryption,
   public access block, lifecycle and tags — the tags through S3 Control
   (`s3:ListTagsForResource`, `s3:TagResource`, `s3:UntagResource`), which
   is how provider-upjet-aws 2.8.1 reads them (measured on floci). **No `s3:DeleteBucket`, no
   `s3:Delete*`, no object action**: Crossplane can never delete a bucket of
   backups nor read what is in it, whatever a managed resource says. Each
   action is listed — no `s3:*` — and `tofu test` asserts the absences.
3. **`opentofu/bootstrap`**: `inputs.cluster.accountId`, from
   `data.aws_caller_identity` on aws (floci answers `000000000000`); empty
   elsewhere.
4. **`opentofu/bootstrap/eks_addons.tf`**: the `snapshot-controller` EKS
   add-on (its CRDs come with it), on by default, created **before**
   `aws-ebs-csi-driver` as AWS requires, pinned at `v8.5.0-eksbuild.3`. Its
   state reaches the inputs as `inputs.storage.snapshots`, so the
   `VolumeSnapshotClass` and `EnableCSI` render only when the CRDs exist.
   floci has no add-on API, so neither renders there, and both floci roots
   turn the add-on off.

## 9. Proof

### e2e on floci — `tests/e2e/chainsaw-test.yaml`

floci 2.1.0 serves S3 — bucket, versioning, encryption, public access block,
lifecycle, tagging, objects (measured locally on 2026-10-01) — and not
`ec2:CreateSnapshot` (`UnsupportedOperation`), Pod Identity nor add-ons. The
tests prove what that allows, the seams as steps of their own:

| Test (labels) | Step | What it proves |
| --- | --- | --- |
| `velero-health` (`health`, `any`) | | Off by default: the ResourceSet Ready, an empty inventory, no `velero` namespace |
| `velero-module-aws` (`module`, `aws`) | crossplane and velero on | The module renders the bucket's five objects, the Role and the association |
| | floci seam, DNS | Every name under `floci.e2e` resolves to floci in the cluster, through k3s's `coredns-custom`. The SDK prefixes S3 Control's host with the account, and an IP takes no prefix |
| | floci seam | floci's `ClusterProviderConfig` at `http://floci.e2e:4566`, with `s3` and `s3control`, the managed resources pointed at it |
| | the bucket in S3 | Bucket `socle-e2e-catalog-velero-000000000000` exists, versioned, `AES256`, public access blocked, its lifecycle rule — from `status.atProvider`, and the one `script` reading floci's S3 |
| | the role | IAM role under `/socle/socle-e2e-catalog/`, its `bucket` policy on that bucket only, no `ec2:` |
| | floci seam, second half | The association `Synced=False`; one minute later still no `HelmRelease` |
| | off, bucket kept | Module off, then Crossplane off: the namespace gone, **the bucket still in S3** |
| | on with static keys | Velero on with Crossplane off through the inputs (the plan refuses it; the test bypasses it — floci's missing Pod Identity is the seam), a Secret with test keys, `s3Url` at floci, `node_agent` on, a client `values` mapping local-path volumes to `fs-backup`: the `BackupStorageLocation` `Available` on the orphaned bucket |
| | values precedence | A key the socle sets, overridden by `values`, then by the Secret of `values_secret`, then both cleared |
| | the seven `Schedule`s | Their cron, TTL, selector and volume policy as §3 renders them |
| | backup | A labelled Deployment writes a file into a PVC; a `Backup` from the `daily-7d` template `Completed`, its `PodVolumeBackup` `Completed` |
| | restore | The namespace deleted; the `Restore` `Completed`; the file read back from the restored PVC |
| | re-sync | The `Backup` object deleted: it reappears, re-read from the bucket at the next sync — scenario 2 in small |
| | warning | A Deployment with `retention: 31d`: `kubectl apply` prints the policy's warning, and the Deployment is created |

There is no `destroyed` test. The root job runs every module's `destroyed`
tests and never turns Velero on, so a bucket assertion there would fail. The
bucket's survival is asserted in the `module` phase instead, after each off.

### Measured, on a local k3s against floci 2.1.0 (2026-10-01)

The second half of the e2e, run by hand with the values the template renders
(`flux-operator build rset`, then `helm install` of chart 12.2.0):

| What | Result |
| --- | --- |
| The server under Pod Security `restricted`, CRD upgrade job included | Running; the `BackupStorageLocation` `Available` on floci's S3, path-style, `checksumAlgorithm: ""` |
| The node-agent, namespace `privileged` | Rolled out on k3s's `/var/lib/kubelet/pods` |
| A `local-path` claim with `volumeType: local`, the pair `daily`/`7d` on every object | Backup `Completed` in 10 s, one `PodVolumeBackup` `Completed` (the 26-byte file) |
| The namespace deleted, then restored | `Restore` `Completed` in 10 s; a new claim `Bound`, Velero's `restore-wait` init container, the file read back unchanged |
| A `Backup` object deleted, the bucket kept | Re-read from the bucket within the sync period: scenario 2 in small |
| The admission policy | `daily-31d` warned with the policy's message and admitted; `daily-7d` silent |
| The bucket's five resources, through the Terraform AWS provider 6.67 (what provider-upjet-aws wraps) against floci, path-style | Created; the second plan empty |

Two defects that only a real backup showed, both fixed in the template: the
read-only root filesystem blocked Kopia (above), and `EnableCSI` without the
snapshot CRDs failed every backup (above).

### Measured, in CI (run 36980161442, 2026-10-02)

Every step of `velero-module-aws` is green on floci, in 18 minutes of the
job's 20. The run also showed what the local probe could not:

- provider-upjet-aws 2.8.1 reads a bucket's tags through S3 Control
  (`ListTagsForResource`). Crossplane's grant carries the three tag actions,
  and the floci seam serves `s3control`.
- The SDK calls S3 Control at `<account>.<endpoint host>`, which an IP cannot
  take. A DNS seam of its own resolves every name under `floci.e2e` to floci.
- A `Restore` left in place holds the namespace once the module goes (§7,
  step 6).

The time is close to the budget. A step added to this test is a step another
one has to give back.

### On the sandbox account — the proof floci cannot give

1. Velero gets the role's credentials through Pod Identity; IAM refuses it a
   bucket that is not its own, and the boundary refuses any service but `s3`.
2. A StatefulSet on EBS, labelled `daily-7d`: backup (a `VolumeSnapshot`
   `ReadyToUse`, an EBS snapshot tagged), namespace deleted with Argo CD
   managing it, scenario 1 of §7 step by step, the data back.
3. The same on EFS through the node-agent.
4. Scenario 2: the socle destroyed and re-applied, the backups listed again,
   one namespace restored.
5. Crossplane cannot delete the bucket: the `Bucket` given
   `managementPolicies: ["*"]` and deleted fails with AccessDenied, and the
   bucket stays.

### On the GCP sandbox — `velero-module-gcp` (`module`, `gcp`, `gke`)

Run by hand against the sandbox's GKE Autopilot, the module as the sandbox's
root turned it on, `--set cluster=<name>`; no script.

| Step | What it proves |
| --- | --- |
| the bucket | `Bucket` `Ready` and `Synced`, external name under `<cluster>-velero-`, no `Delete` nor `*` in its policies; uniform access, public access prevention and versioning as GCS reports them (`status.atProvider`), the 30-day noncurrent rule |
| the binding | `BucketIAMMember` `Ready`: `roles/storage.objectAdmin`, on that bucket, for `…/subject/ns/velero/sa/velero-server` |
| the server | `velero-workload` `Ready`, the namespace `restricted`, velero-server without a Google service account annotation, the server `Available`, the `BackupStorageLocation` `Available` with provider `gcp` and the placeholder; no node-agent; `velero-pd` on `pd.csi.storage.gke.io` |
| backup | A labelled Deployment on a `standard-rwo` claim writes a file; a `Backup` from the `daily-7d` template (TTL one hour, so Velero deletes it and its snapshot after the test) `Completed` with one CSI snapshot |
| restore | The namespace deleted; the `Restore` `Completed`; the pod's init container finds the file on the new disk and reports it in its termination message — read from the pod's status, no exec |

Still owed by the sandbox (Task 13 of the GCP work): the binding refused when
`allowed_roles` lacks `roles/storage.objectAdmin`; after a `destroy`, no
binding left for `ns/velero/sa/velero-server` and the bucket still there; and
`velero backup logs` failing as §2 *On GCP* says.

### Static

`flux-operator build rset` with `oci/.ci/inputs-sample.yaml` (velero on),
`kubeconform -strict` on the render and the raw template; `helm template` of
chart 12.2.0 with the socle's values and a client override (its
`values.schema.json` refuses unknown keys); `tofu test` with one failing case
per new validation, in the bootstrap and in `opentofu/aws`.

## 10. Out of scope in v1, on purpose

- **azure, scaleway.** The module's shape carries over (Blob, Object Storage
  through the aws plugin); each needs its Crossplane provider.
- **File-system backup on gcp.** Autopilot forbids the node-agent's
  hostPath, so a Filestore or other non-PD volume is not backed up there.
- **Signed URLs on gcp** — `velero backup logs` and the like (§2 *On GCP*).
- **Copy to another region or account.** Snapshots and bucket live in the
  cluster's account and region: an account compromised, or a region lost,
  takes them along. The data mover (snapshots moved into the bucket) and S3
  replication are the v2 route.
- **S3 Object Lock**, the real defence against ransomware — it needs a bucket
  created with it, so a decision before the first production install of v2.
- **A cluster renamed** finding its old backups automatically.
- **Velero with Crossplane off**, a client's own bucket and identity.
- **Self-service restore** for application teams.
- **A bucket shared with `vmbackup`**: each module has its own, so each role
  reaches one bucket.

## Open points for the implementation

- The `Schedule`s run as soon as they exist (`skipImmediately: false`): with
  seven pairs, the first install takes seven backups, empty unless an
  application is labelled. Kept, unless the e2e shows a cost.
- Velero's `kubectl` image for the CRD upgrade hook comes from
  `registry.k8s.io`; pinned with the chart, its tag to follow the cluster's
  minor version.
