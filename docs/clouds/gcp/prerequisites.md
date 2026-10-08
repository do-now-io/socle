---
title: Prerequisites
description: The GCP project, roles, credentials, state and tooling the socle expects.
sidebar:
  order: 1
---

Tick these before `tofu apply` runs the GCP foundations. The module creates
none of it. The commands use these variables:

```sh
PROJECT_ID=my-project-dev
BILLING_ACCOUNT=000000-000000-000000
REGION=europe-west1
STATE_BUCKET=my-project-dev-tofu-state
PRINCIPAL=user:you@example.com   # or serviceAccount:…, principalSet://… for CI
```

## Account

- [ ] **One project per environment**, its ID matching
  `^[a-z][a-z0-9-]{4,28}[a-z0-9]$`.
- [ ] A billing account linked, and a budget with alert thresholds.
- [ ] Org policies that permit private GKE nodes, Cloud NAT and external NAT
  addresses.
- [ ] The APIs enabled: `cloudresourcemanager`, `serviceusage`, `compute`,
  `container`, `pubsub` (upgrade notifications, on by default), `bigquery`
  (only with `billing_export_dataset_id`).

```sh
gcloud projects create "$PROJECT_ID"                  # when it does not exist
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
gcloud services enable \
  cloudresourcemanager.googleapis.com serviceusage.googleapis.com \
  compute.googleapis.com container.googleapis.com \
  pubsub.googleapis.com bigquery.googleapis.com \
  --project="$PROJECT_ID"
```

<details>
<summary>Under the hood</summary>

- Workload Identity builds a principal from project, namespace and service
  account: two clusters in one project share principals.
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
| `roles/resourcemanager.projectIamAdmin` | the `observability_reader_members` bindings |
| `roles/pubsub.admin` | the upgrade notification topic |
| `roles/bigquery.admin` | only with `billing_export_dataset_id` |
| `roles/storage.objectAdmin` | state, **on the state bucket**, not the project |

```sh
for ROLE in \
  roles/container.admin \
  roles/compute.networkAdmin \
  roles/resourcemanager.projectIamAdmin \
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
- [ ] While the registry is private, a registry login and a Flux pull secret
  ([private registry](../../guides/private-registry.md)).

## Quotas

- [ ] Regional CPUs and persistent disk SSD: Autopilot nodes draw on them.
- [ ] In-use external IP addresses: Cloud NAT allocates its own.
- [ ] One proxy-only subnetwork per region and VPC: a second cluster there
  sets `create_proxy_only_subnet = false`.

```sh
gcloud compute regions describe "$REGION" --project="$PROJECT_ID" \
  --flatten=quotas --format="table(quotas.metric,quotas.usage,quotas.limit)"
```
