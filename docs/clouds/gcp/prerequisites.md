---
title: Prerequisites
description: The GCP project, roles, credentials, state and tooling the socle expects.
sidebar:
  order: 1
---

Tick these before `tofu apply` runs the GCP foundations, alone or through
the whole root [`opentofu/clusters/gcp`](../../../opentofu/clusters/gcp/README.md).
Neither creates any of it. The commands use these variables:

```sh
PROJECT_ID=my-project-dev
BILLING_ACCOUNT=000000-000000-000000
REGION=europe-west1
STATE_BUCKET=my-project-dev-tofu-state
PRINCIPAL=user:you@example.com   # or serviceAccount:…, principalSet://… for CI
```

## Account

- [ ] **One project per environment**, its ID matching
  `^[a-z][a-z0-9-]{4,28}[a-z0-9]$`, and **one socle cluster per project**: a
  workload's principal names the project, its namespace and its
  ServiceAccount, never the cluster, so two socle clusters in one project
  would be the same principal for every module, and what Crossplane grants
  one would serve the other.
- [ ] A billing account linked, and a budget with alert thresholds.
- [ ] Org policies that permit private GKE nodes, Cloud NAT and external NAT
  addresses. No service account is created: every workload, Crossplane
  included, is a Workload Identity Federation principal of its own
  ([GCP-14](../../decisions/gcp.md#gcp-14-workload-identity-federation-direct-principals-no-google-service-account)).
- [ ] The APIs enabled:

| API | Needed for |
| --- | --- |
| `cloudresourcemanager` | project IAM bindings: the apply's, and those Crossplane makes for modules |
| `serviceusage` | enabling the others |
| `compute` | VPC, subnetworks, router, Cloud NAT, the Gateways' load balancers |
| `container` | the Autopilot cluster |
| `iam` | Crossplane's bucket role and the DNS records role |
| `sts` | every workload's federated token: a pod's Kubernetes token exchanged for a Google one |
| `iamcredentials` | a CI identity impersonating the service account that runs OpenTofu |
| `logging` | GKE's system and workload logs (`logging_components`) |
| `monitoring` | GKE's system metrics; what KEDA's `pubsub` scaler reads |
| `dns` | the certificate's DNS authorizations, external-dns |
| `certificatemanager` | the shared Gateways' Google-managed certificates (`gateway_certificate`) |
| `storage` | the state bucket, and the buckets modules own (Velero's) |
| `secretmanager` | the external-secrets module |
| `artifactregistry` | Argo CD Image Updater reading `kube.argocd_image_updater.repositories` |
| `pubsub` | only with `enable_upgrade_notifications` (on by default) |
| `bigquery` | only with `billing_export_dataset_id` |

```sh
gcloud projects create "$PROJECT_ID"                  # when it does not exist
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
gcloud services enable \
  cloudresourcemanager.googleapis.com serviceusage.googleapis.com \
  compute.googleapis.com container.googleapis.com \
  iam.googleapis.com sts.googleapis.com iamcredentials.googleapis.com \
  logging.googleapis.com monitoring.googleapis.com \
  dns.googleapis.com certificatemanager.googleapis.com \
  storage.googleapis.com secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  pubsub.googleapis.com bigquery.googleapis.com \
  --project="$PROJECT_ID"
```

<details>
<summary>Under the hood</summary>

- Workload Identity builds a principal from project, namespace and service
  account: two clusters in one project share principals.
- Enable only what the configuration uses: drop `pubsub` without upgrade
  notifications, `bigquery` without an export dataset, `secretmanager`
  without external-secrets, `certificatemanager` without
  `gateway_certificate`, `artifactregistry` without Image Updater's
  repositories.
- Autopilot bills Pod requests; without a budget a runaway workload is
  silent.
- A deleted project ID cannot be reused: archive the state first.
- Never disable an API a resource still depends on: the next plan cannot
  read it.

</details>

## Permissions for the apply

- [ ] To prepare the project, once: `roles/serviceusage.serviceUsageAdmin`
  (APIs) and `roles/storage.admin` (state bucket).
- [ ] On the principal that applies, on the project:

| Role | For |
| --- | --- |
| `roles/container.admin` | the cluster, and the Helm releases in it |
| `roles/compute.networkAdmin` | VPC, subnetworks, router, NAT |
| `roles/resourcemanager.projectIamAdmin` | the `observability_reader_members` bindings, and Crossplane's conditional grants when `crossplane` is set |
| `roles/iam.roleAdmin` | Crossplane's bucket role and the DNS records role; only with `crossplane` |
| `roles/dns.admin` | the certificate's authorization records; only with `gateway_certificate` |
| `roles/certificatemanager.editor` | only with `gateway_certificate` |
| `roles/pubsub.admin` | the upgrade notification topic |
| `roles/bigquery.admin` | only with `billing_export_dataset_id` |
| `roles/storage.objectAdmin` | state, **on the state bucket**, not the project |

```sh
for ROLE in \
  roles/container.admin \
  roles/compute.networkAdmin \
  roles/resourcemanager.projectIamAdmin \
  roles/iam.roleAdmin \
  roles/dns.admin \
  roles/certificatemanager.editor \
  roles/pubsub.admin \
  roles/bigquery.admin
do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="$PRINCIPAL" --role="$ROLE" --condition=None
done
```

- [ ] Logged in locally, for both the provider (ADC) and
  `gke-gcloud-auth-plugin` (the active `gcloud` account):

```sh
gcloud auth login
gcloud auth application-default login
gcloud auth application-default set-quota-project "$PROJECT_ID"
gcloud config set project "$PROJECT_ID"
```

<details>
<summary>Under the hood</summary>

- A dedicated service account for OpenTofu, impersonated by humans and
  federated from CI, bound at project level.
- Never `roles/owner` or `roles/editor`; never a service account key
  (enforce `constraints/iam.disableServiceAccountKeyCreation`).
- Without the quota project, API calls bill and rate-limit against whatever
  project the login defaulted to.
- The same table is in the
  [minimal example](../../../opentofu/gcp/examples/minimal/README.md).

</details>

## State

- [ ] A GCS bucket in the cluster's region: uniform access, public access
  prevention, versioning, soft delete raised to 30 days, a lifecycle rule on
  noncurrent versions only. The GCS backend locks natively.

```sh
gcloud storage buckets create "gs://$STATE_BUCKET" \
  --project="$PROJECT_ID" --location="$REGION" \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update "gs://$STATE_BUCKET" \
  --versioning --soft-delete-duration=30d

cat > lifecycle.json <<'JSON'
{
  "rule": [
    {
      "action": { "type": "Delete" },
      "condition": { "isLive": false, "daysSinceNoncurrentTime": 365, "numNewerVersions": 20 }
    }
  ]
}
JSON
gcloud storage buckets update "gs://$STATE_BUCKET" --lifecycle-file=lifecycle.json

gcloud storage buckets add-iam-policy-binding "gs://$STATE_BUCKET" \
  --member="$PRINCIPAL" --role=roles/storage.objectAdmin
```

One prefix per environment:

```hcl
terraform {
  backend "gcs" {
    bucket = "my-project-dev-tofu-state"
    prefix = "socle/gcp/dev"
  }
}
```

<details>
<summary>Under the hood</summary>

- State holds every attribute of every resource; anyone who reads the bucket
  reads it all. Losing it leaves a cluster nobody can manage.
- A lifecycle rule without `isLive: false` eventually deletes the current
  state.
- Never share the bucket with application data.

</details>

## Tooling

- [ ] OpenTofu 1.10 or later.
- [ ] `gcloud`, authenticated as above.
- [ ] `gke-gcloud-auth-plugin` (`gcloud components install
  gke-gcloud-auth-plugin`, or the package
  `google-cloud-cli-gke-gcloud-auth-plugin`): the bootstrap cannot reach the
  cluster without it.
- [ ] `kubectl`.
- [ ] `cosign`, to verify the modules package: OpenTofu does not verify OCI
  signatures ([distribution](../../architecture/distribution.md)).

## Crossplane's allowed roles

- [ ] With `gcp.crossplane` set, `allowed_roles` names every role a catalog
  module's principal may be granted, at most nine (the DNS records role is
  the tenth). Crossplane grants nothing else, and a module whose role is
  missing never gets its binding Ready:

| Module | Role in `allowed_roles` |
| --- | --- |
| `external_dns` | none: the socle's own `socleDnsRecords_<cluster>` role, always granted |
| `external_secrets` | `roles/secretmanager.secretAccessor` |
| `keda` (`services = ["pubsub"]`) | `roles/monitoring.viewer` |
| `velero` | `roles/storage.objectAdmin` |
| `argocd_image_updater` (`repositories`) | `roles/artifactregistry.reader` |

<details>
<summary>Under the hood</summary>

- `owner`, `editor`, `viewer`, `iam.*`, `resourcemanager.*` and every
  predefined admin or owner role are refused at plan: each carries a
  `setIamPolicy` permission Crossplane could grant to itself. The one
  exception is `roles/storage.objectAdmin`, harmless on a bucket with
  uniform bucket-level access.
- The bound is a `modifiedGrantsByRole` condition on Crossplane's own grant
  of Project IAM Admin
  ([Google](https://cloud.google.com/iam/docs/setting-limits-on-granting-roles)).

</details>

## Quotas

- [ ] Regional CPUs and persistent disk SSD: Autopilot nodes draw on them.
  A fresh project is not enough for the whole catalog. Measured on the
  sandbox, a project created in October 2026 on a new billing account: 12
  `CPUS_ALL_REGIONS` (ask for about 32) and 250 GB of `SSD_TOTAL_GB` in the
  region (ask for about 1000). The SSD quota is the one that binds: 250 GB
  is two nodes, too few for every module on (2026-10-16,
  [sizing](sizing.md#what-fits-a-fresh-project)); without the increase, turn
  on only the modules you need. Ask before the first apply: on a fresh
  billing account Google refused automatic increases ("cannot grant at this
  moment") and sent the CPU request to review; the Console (IAM & Admin →
  Quotas & System Limits) or a paid billing account then does it.
- [ ] In-use external IP addresses: Cloud NAT allocates its own.
- [ ] One proxy-only subnetwork per region and VPC: a second cluster there
  sets `create_proxy_only_subnet = false`.

```sh
gcloud compute project-info describe --project="$PROJECT_ID" \
  --flatten=quotas --format="table(quotas.metric,quotas.usage,quotas.limit)" | grep CPUS_ALL_REGIONS
gcloud compute regions describe "$REGION" --project="$PROJECT_ID" \
  --flatten=quotas --format="table(quotas.metric,quotas.usage,quotas.limit)"
```

<details>
<summary>Under the hood</summary>

- Every Autopilot node boots on a 100 GB `pd-balanced` disk, the only boot
  disk type Autopilot accepts, and `pd-balanced` counts against
  `SSD_TOTAL_GB`. So do the claims on the default StorageClass,
  `standard-rwo`: 250 GB is two nodes and a few claims.
- Autopilot caps a node at 32 pods, and GKE's own DaemonSets and system
  pods take 13 of them on an `e2-standard-2` node and 25 on the
  `ek-standard-8` system node. Two nodes leave about 26 places for Flux and
  the catalog, which runs about 41 pods with every module on. The 12 vCPUs
  were not the limit (sandbox, 2026-10-16).
- What the catalog itself requests, every module on:
  [sizing](sizing.md).

</details>
