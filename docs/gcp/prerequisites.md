# Google Cloud — prerequisites

What must exist on your Google Cloud account before `tofu apply` can run the
socle — the foundations module alone, or the whole root
[`opentofu/clusters/gcp`](../../opentofu/clusters/gcp/README.md). Neither
creates any of it.

Each item can be done by hand in the Cloud Console — nothing is provided for
that path — or from the command line. The commands for every item are
gathered in [By command line](#by-command-line) at the end. The roles the
apply itself needs are listed in
[the minimal example](../../opentofu/gcp/examples/minimal/README.md).

## Account

- A Google Cloud project, ID matching `^[a-z][a-z0-9-]{4,28}[a-z0-9]$`.
- A billing account linked to that project.
- Org policies that permit private GKE nodes and Cloud NAT in the project.
  No service account is created: every workload, Crossplane included, is a
  Workload Identity Federation principal of its own
  ([managed-scope](managed-scope.md#identity)).
- One socle cluster per project. A workload's principal names the project and
  its Kubernetes namespace and ServiceAccount, never the cluster: two socle
  clusters in one project would be the same principal for every module, and
  what Crossplane grants one would serve the other.

## APIs enabled on the project

| API | Needed for |
| --- | --- |
| `cloudresourcemanager.googleapis.com` | project IAM bindings — the apply's, and those Crossplane makes for modules |
| `serviceusage.googleapis.com` | enabling the others |
| `compute.googleapis.com` | VPC, subnetworks, router, Cloud NAT, the Gateways' load balancers |
| `container.googleapis.com` | the Autopilot cluster |
| `iam.googleapis.com` | Crossplane's custom roles and the zone lister role |
| `sts.googleapis.com` | every workload's federated token: the exchange of a pod's Kubernetes token for a Google one |
| `iamcredentials.googleapis.com` | a CI identity impersonating the service account that runs OpenTofu |
| `logging.googleapis.com` | GKE's system and workload logs (`logging_components`) |
| `monitoring.googleapis.com` | GKE's system metrics; what KEDA's GCP scalers read |
| `dns.googleapis.com` | the certificate's DNS authorizations, Crossplane's zone bindings, external-dns |
| `certificatemanager.googleapis.com` | the shared Gateways' Google-managed certificates (`gateway_certificate`) |
| `storage.googleapis.com` | the state bucket, and the buckets modules own (Velero's) |
| `secretmanager.googleapis.com` | the external-secrets module |
| `pubsub.googleapis.com` | only when `enable_upgrade_notifications` is true (default) |
| `bigquery.googleapis.com` | only when `billing_export_dataset_id` is set |

## Roles on the principal running OpenTofu

| Role | Grants |
| --- | --- |
| `roles/serviceusage.serviceUsageAdmin` | enable the APIs above |
| `roles/compute.networkAdmin` | network, subnetworks, router, NAT |
| `roles/container.admin` | the cluster, and the bootstrap's Helm releases on it |
| `roles/resourcemanager.projectIamAdmin` | project-level role bindings, Crossplane's included: its own conditional grant of Project IAM Admin and of the bucket role |
| `roles/iam.roleAdmin` | Crossplane's custom roles and the zone lister role — only when `crossplane` is set |
| `roles/dns.admin` | Crossplane's binding on each zone in `crossplane.dns_zones` — a zone's IAM policy — and the certificate's authorization records |
| `roles/certificatemanager.editor` | only when `gateway_certificate` is set |
| `roles/storage.admin` | creating the state bucket — one-time; the apply principal itself needs only object access on that bucket |
| `roles/pubsub.admin` | only with upgrade notifications |
| `roles/bigquery.admin` | only with the billing export dataset |

## Quotas

What a fresh project is given is not enough for the socle. Measured on the
sandbox, a project created in October 2026 on a new billing account:

| Quota | Fresh project | Ask for |
| --- | --- | --- |
| `CPUS_ALL_REGIONS` (global) | 12 | ~32 |
| `SSD_TOTAL_GB` (the cluster's region) — Persistent Disk SSD | 250 GB | ~1000 GB |

Why the disk quota runs out first:

- Every Autopilot node boots on a 100 GB `pd-balanced` disk, and Autopilot
  accepts no other boot disk type. `pd-balanced` counts against
  `SSD_TOTAL_GB`, not against the standard disk quota.
- Persistent volumes on the default StorageClass, `standard-rwo`, are
  `pd-balanced` too: VictoriaMetrics' and VictoriaLogs' 20 GiB claims draw on
  the same 250 GB.
- 250 GB is two nodes and a few claims, and the full socle needs more than
  two nodes. The CPU quota was the next limit the sandbox hit: 12 of 12 in
  use.

Ask before the first apply, for the cluster's region. On a fresh project or
billing account Google may refuse an automatic increase — measured: requests
through the Cloud Quotas API for 500, 1000 and 2000 GB were refused ("cannot
grant at this moment"), and the request for 32 vCPU went to review. Then it
takes a request in the Console (IAM & Admin → Quotas & System Limits), or a
paid billing account. The values in force: [By command line](#by-command-line).

## Credentials

Application Default Credentials reachable by the provider — a user login for
local runs, Workload Identity Federation from CI. The module accepts no
credential as input and no service account key is ever needed.

## State

A GCS bucket for remote state, with versioning on, created before the first
`tofu init`. The module ships no backend block; state lives in your own
account, so declare it in your root configuration:

```hcl
terraform {
  backend "gcs" {
    bucket = "my-project-tofu-state"
    prefix = "socle/gcp"
  }
}
```

## Tooling

- OpenTofu 1.10 or later.
- `gcloud` CLI, authenticated.
- `gke-gcloud-auth-plugin`, for the whole root: the helm provider gets its
  token through it.

## Good practices

Per resource, what to do beyond simply creating it.

### Project

- One project per cluster and per environment. A shared project makes the
  blast radius of an IAM mistake the whole estate, and two socle clusters in
  one project share every module's principal ([Account](#account)).
- Under an organisation or folder, so org policies and audit sinks are
  inherited rather than reinvented.
- Never delete a project that has held a cluster before its state is
  archived; a deleted project ID cannot be reused.

### Billing

- A budget with alert thresholds on the project. An Autopilot cluster bills
  by pod request and a runaway workload is otherwise silent.
- Billing account administration held by different principals than project
  administration.

### APIs

- Enable only what the configuration uses: drop `pubsub` when
  `enable_upgrade_notifications` is false, `bigquery` when no export dataset
  is set, `secretmanager` without the external-secrets module,
  `certificatemanager` without `gateway_certificate`.
- Never disable an API a resource still depends on — the resource is deleted
  or orphaned, and the next plan cannot read it.

### Roles

- A dedicated service account for OpenTofu, impersonated by humans and
  federated from CI, rather than roles granted to individual users.
- Bound at project level, never at organisation level.
- Never `roles/owner` or `roles/editor`: both grant service account key
  creation and IAM changes far past what the module needs.

### Credentials

- Workload Identity Federation in CI, user ADC only for local runs.
- No service account keys, ever. Enforce it with the
  `constraints/iam.disableServiceAccountKeyCreation` org policy.
- Set the quota project, otherwise API calls bill and rate-limit against
  whatever project the login defaulted to.

### State bucket

State holds every attribute of every resource, secrets included, and losing
it means the cluster exists but is no longer manageable.

- Versioning on before the first write.
- A lifecycle rule that can never touch a live object: delete only noncurrent
  versions, and only ones both old and superseded. A rule without an
  `isLive: false` condition will eventually delete the current state.
- Soft delete raised from the 7-day default, so an accidental delete of the
  bucket contents is recoverable.
- Public access prevention enforced, uniform bucket-level access on.
- Object access granted on the bucket, not `roles/storage.admin` on the
  project — anyone who can read this bucket can read every secret the cluster
  holds.
- Same region as the cluster, one prefix per environment, and never shared
  with application data.
- Locking needs nothing: the GCS backend locks natively.

## By command line

Set the variables once:

```sh
PROJECT_ID=my-project
BILLING_ACCOUNT=000000-000000-000000
REGION=europe-west1
STATE_BUCKET=my-project-tofu-state
PRINCIPAL=user:you@example.com   # or serviceAccount:…, principalSet://… for CI
```

Project and billing, when neither exists yet:

```sh
gcloud projects create "$PROJECT_ID"
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
```

When the project and the billing link already exist, check them instead:

```sh
gcloud projects list                            # find the project ID
gcloud projects describe "$PROJECT_ID"
gcloud billing projects describe "$PROJECT_ID"  # billingEnabled must be true
gcloud config set project "$PROJECT_ID"
```

When the project exists but is not billed:

```sh
gcloud billing accounts list
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
```

APIs:

```sh
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  compute.googleapis.com \
  container.googleapis.com \
  iam.googleapis.com \
  sts.googleapis.com \
  iamcredentials.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  dns.googleapis.com \
  certificatemanager.googleapis.com \
  storage.googleapis.com \
  secretmanager.googleapis.com \
  pubsub.googleapis.com \
  bigquery.googleapis.com \
  --project="$PROJECT_ID"
```

Roles:

```sh
for ROLE in \
  roles/serviceusage.serviceUsageAdmin \
  roles/compute.networkAdmin \
  roles/container.admin \
  roles/resourcemanager.projectIamAdmin \
  roles/iam.roleAdmin \
  roles/dns.admin \
  roles/certificatemanager.editor \
  roles/storage.admin \
  roles/pubsub.admin \
  roles/bigquery.admin
do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="$PRINCIPAL" --role="$ROLE" --condition=None
done
```

Quotas in force — the global CPU count, then the region's SSD and CPU:

```sh
gcloud compute project-info describe --project="$PROJECT_ID" --format=json \
  | jq '.quotas[] | select(.metric == "CPUS_ALL_REGIONS")'
gcloud compute regions describe "$REGION" --project="$PROJECT_ID" --format=json \
  | jq '.quotas[] | select(.metric == "SSD_TOTAL_GB" or .metric == "CPUS")'
```

Credentials:

```sh
gcloud auth application-default login
gcloud auth application-default set-quota-project "$PROJECT_ID"
```

State bucket:

```sh
gcloud storage buckets create "gs://$STATE_BUCKET" \
  --project="$PROJECT_ID" --location="$REGION" \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update "gs://$STATE_BUCKET" \
  --versioning --soft-delete-duration=30d
```

A lifecycle that never deletes a live object — only noncurrent versions that
are both over a year old and superseded twenty times over:

```sh
cat > lifecycle.json <<'JSON'
{
  "rule": [
    {
      "action": { "type": "Delete" },
      "condition": {
        "isLive": false,
        "daysSinceNoncurrentTime": 365,
        "numNewerVersions": 20
      }
    }
  ]
}
JSON
gcloud storage buckets update "gs://$STATE_BUCKET" --lifecycle-file=lifecycle.json
```

Object access on the bucket for the principal that runs the apply, instead of
`roles/storage.admin` on the project:

```sh
gcloud storage buckets add-iam-policy-binding "gs://$STATE_BUCKET" \
  --member="$PRINCIPAL" --role=roles/storage.objectAdmin
```

Then point the backend at it and initialise:

```sh
tofu init -backend-config="bucket=$STATE_BUCKET" -backend-config="prefix=socle/gcp"
```
