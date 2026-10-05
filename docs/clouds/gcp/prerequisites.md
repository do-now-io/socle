---
title: Prerequisites
description: The GCP project, roles, credentials, state and tooling the socle expects.
sidebar:
  order: 1
---

What must exist before `tofu apply` can run the GCP foundations. The module
creates none of it. Each item can be done in the Cloud Console or with the
commands below; set these once:

```sh
PROJECT_ID=my-project-dev
BILLING_ACCOUNT=000000-000000-000000
REGION=europe-west1
STATE_BUCKET=my-project-dev-tofu-state
PRINCIPAL=user:you@example.com   # or serviceAccount:…, principalSet://… for CI
```

## Account

- **One project per environment.** Workload Identity Federation builds a
  workload's principal from the project, the namespace and the service
  account name, so two clusters in one project share principals
  ([GCP-06](../../decisions/gcp.md#gcp-06-workload-identity-federation-a-google-service-account-per-kubernetes-service-account)).
  A separate project also bounds the blast radius of an IAM mistake.
- The project ID matches `^[a-z][a-z0-9-]{4,28}[a-z0-9]$`.
- A billing account linked to the project, and a budget with alert
  thresholds on it: Autopilot bills Pod requests, and a runaway workload is
  otherwise silent.
- Under an organisation or folder, whose org policies permit private GKE
  nodes, Cloud NAT and external NAT addresses.
- Never delete a project that held a cluster before its state is archived:
  a deleted project ID cannot be reused.

```sh
gcloud projects create "$PROJECT_ID"                  # when it does not exist
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
gcloud billing projects describe "$PROJECT_ID"        # billingEnabled: true
```

The APIs the module calls:

| API | Needed for |
| --- | --- |
| `cloudresourcemanager.googleapis.com` | project IAM bindings |
| `serviceusage.googleapis.com` | enabling the others |
| `compute.googleapis.com` | VPC, subnetworks, router, Cloud NAT |
| `container.googleapis.com` | the Autopilot cluster |
| `pubsub.googleapis.com` | the upgrade notification topic (on by default) |
| `bigquery.googleapis.com` | only when `billing_export_dataset_id` is set |

```sh
gcloud services enable \
  cloudresourcemanager.googleapis.com serviceusage.googleapis.com \
  compute.googleapis.com container.googleapis.com \
  pubsub.googleapis.com bigquery.googleapis.com \
  --project="$PROJECT_ID"
```

Drop `pubsub` when `enable_upgrade_notifications = false` and `bigquery`
when no dataset is requested. Never disable an API a resource still depends
on: the next plan cannot read it.

## Permissions for the apply

Two sets. The first prepares the project, once, and is held by whoever does
that; the second is what the principal running `tofu apply` needs on every
run.

Preparing the project:

| Role | For |
| --- | --- |
| `roles/serviceusage.serviceUsageAdmin` | enabling the APIs above |
| `roles/storage.admin` | creating the state bucket |

Running the apply, granted on the project except where stated:

| Role | For |
| --- | --- |
| `roles/container.admin` | the cluster, and the Helm releases the bootstrap installs in it |
| `roles/compute.networkAdmin` | VPC, subnetworks, router and NAT |
| `roles/resourcemanager.projectIamAdmin` | the `observability_reader_members` bindings |
| `roles/pubsub.admin` | the upgrade notification topic |
| `roles/bigquery.admin` | only when `billing_export_dataset_id` is set |
| `roles/storage.objectAdmin` | reading and writing state — on the state bucket, not the project |

The same table is in the
[minimal example](../../../opentofu/gcp/examples/minimal/README.md).

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

- Use a dedicated service account for OpenTofu, impersonated by humans and
  federated from CI, bound at project level, never at organisation level.
- Never `roles/owner` or `roles/editor`: both grant service account key
  creation and IAM changes far beyond what the module needs.
- No service account key, ever. The module accepts no credential as input.
  Enforce it with the `constraints/iam.disableServiceAccountKeyCreation` org
  policy.

Credentials come from the environment: Workload Identity Federation in CI, a
user login locally. The google provider reads Application Default
Credentials; `gke-gcloud-auth-plugin`, which the Helm releases authenticate
through, reads the active `gcloud` account. Locally, log in to both and set
the quota project, or API calls bill and rate-limit against whatever project
the login defaulted to:

```sh
gcloud auth login
gcloud auth application-default login
gcloud auth application-default set-quota-project "$PROJECT_ID"
gcloud config set project "$PROJECT_ID"
```

## State

A GCS bucket for remote state, created before the first `tofu init`. The
module ships no backend block; state lives in your project. State holds
every attribute of every resource, and losing it leaves a cluster that
exists but can no longer be managed.

- Versioning on before the first write; soft delete raised from the 7-day
  default.
- Uniform bucket-level access, public access prevention enforced.
- A lifecycle rule that deletes only noncurrent versions. A rule without
  `isLive: false` eventually deletes the current state.
- Object access granted on the bucket: anyone who can read it reads every
  value the state holds.
- Same region as the cluster, one prefix per environment, never shared with
  application data. The GCS backend locks natively.

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

In the root configuration:

```hcl
terraform {
  backend "gcs" {
    bucket = "my-project-dev-tofu-state"
    prefix = "socle/gcp/dev"
  }
}
```

## Tooling

- OpenTofu 1.10 or later.
- The `gcloud` CLI, authenticated as above.
- `gke-gcloud-auth-plugin`: the foundations' `helm_kubernetes` output runs
  it to get a short-lived token, so the bootstrap cannot reach the cluster
  without it. `gcloud components install gke-gcloud-auth-plugin`, or your
  package manager's `google-cloud-cli-gke-gcloud-auth-plugin`.
- `kubectl`, to read the result.
- `cosign`, to verify the modules package before `tofu init`: OpenTofu does
  not verify OCI signatures ([distribution](../../architecture/distribution.md)).
- While the socle registry is private, a registry login for OpenTofu and a
  pull secret for Flux ([private registry](../../guides/private-registry.md)).

## Quotas

Autopilot nodes are Compute Engine VMs in your project and draw on its
regional quotas. Check before the first apply, and before growing a cluster:

- CPUs, and persistent disk SSD, in the region.
- In-use external IP addresses in the region: Cloud NAT allocates its
  addresses automatically.
- One proxy-only subnetwork per region and VPC: a second cluster in the same
  region and VPC sets `create_proxy_only_subnet = false`.

```sh
gcloud compute regions describe "$REGION" --project="$PROJECT_ID" \
  --flatten=quotas --format="table(quotas.metric,quotas.usage,quotas.limit)"
```
