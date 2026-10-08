---
title: 'Quickstart: GCP'
description: From zero to a converged GKE cluster with the socle.
sidebar:
  order: 2
---

One `tofu apply` of a root you write: a GKE Autopilot cluster in your
project, Flux on it, and the catalog reconciled from the signed artifact.

## Before you start

From [GCP prerequisites](../clouds/gcp/prerequisites.md):

- a billed project for this environment, its APIs enabled, a state bucket;
- on the principal that applies: `roles/container.admin`,
  `roles/compute.networkAdmin`, `roles/resourcemanager.projectIamAdmin`,
  `roles/pubsub.admin`, `roles/bigquery.admin`, and
  `roles/storage.objectAdmin` on the state bucket;
- OpenTofu 1.10 or later, `gcloud`, `gke-gcloud-auth-plugin`, `kubectl`.

## Write your tfvars

There is no GCP root in the repository: yours calls the foundations, then
the bootstrap. `main.tf`:

```hcl
terraform {
  required_version = ">= 1.10"

  required_providers {
    google = { source = "hashicorp/google", version = ">= 8.0, < 9.0" }
    helm   = { source = "hashicorp/helm", version = ">= 3.0, < 4.0" }
  }

  backend "gcs" {
    bucket = "my-project-dev-tofu-state"
    prefix = "socle/gcp/dev"
  }
}

variable "socle_version" { type = string }
variable "project_id" { type = string }
variable "region" { type = string }
variable "cluster_name" { type = string }
variable "environment" { type = string }
variable "owner" { type = string }
variable "maintenance_window" {
  type = object({ start_time = string, end_time = string, recurrence = string })
}
variable "kube" {
  type    = any
  default = {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "foundations" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/gcp?tag=${var.socle_version}"

  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name
  owner        = var.owner
  environment  = var.environment

  create_network     = true
  maintenance_window = var.maintenance_window

  # The dataset the detailed billing export lands in. Linking the billing
  # account to it is a Console step, after the apply.
  billing_export_dataset_id = "billing_export"
}

# No credential: gke-gcloud-auth-plugin gets a short-lived token from the
# active gcloud account at call time.
provider "helm" {
  kubernetes = module.foundations.helm_kubernetes
}

# The bootstrap requires the aws provider for its EKS add-ons, and OpenTofu
# configures it even when cloud = "gcp" plans no AWS resource. This block
# satisfies it without calling AWS.
provider "aws" {
  region                      = "eu-west-1"
  access_key                  = "unused"
  secret_key                  = "unused"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "socle" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/bootstrap?tag=${var.socle_version}"

  cloud        = "gcp"
  cluster_name = var.cluster_name
  environment  = var.environment
  owner        = var.owner
  region       = var.region

  kube = var.kube
}
```

No `cilium`, `cluster_network` or `schedulable_nodes`: GKE runs Dataplane V2
and Autopilot provisions nodes. `terraform.tfvars`:

```hcl
socle_version = "0.0.0" # x-release-please-version

project_id   = "my-project-dev"
region       = "europe-west1"
cluster_name = "socle-dev"
environment  = "dev"
owner        = "platform"

# Required, no default. The day of the week orders the rings: dev on
# Tuesday, staging on Wednesday, prod on Saturday.
maintenance_window = {
  start_time = "2026-01-06T02:00:00Z"
  end_time   = "2026-01-06T14:00:00Z"
  recurrence = "FREQ=WEEKLY;BYDAY=TU"
}

# Catalog modules that differ from their defaults.
kube = {}
```

Every input: [GCP foundations](../clouds/gcp/foundations.md#reference) and
[Configure](../guides/configure.md).

## Apply

```sh
gcloud auth login
gcloud auth application-default login
gcloud auth application-default set-quota-project my-project-dev

tofu init
tofu apply
```

Then, in the Cloud Console, **Billing › Billing export › BigQuery export**:
set the detailed usage cost export to the project and the `billing_export`
dataset. No apply can do it; without it, no cost data arrives.

## Check it converged

```sh
gcloud container clusters get-credentials socle-dev \
  --region europe-west1 --project my-project-dev --dns-endpoint

kubectl -n flux-system get ocirepository socle   # pulled digest, SourceVerified
kubectl -n flux-system get resourceset           # socle-root and one per module, Ready
```

`socle-root` Ready means the catalog converged; if not, see
[Troubleshooting](../guides/troubleshooting.md).

## Next steps

- [Enable a module](../guides/enable-a-module.md) through `kube`.
- [Upgrade](../guides/upgrade.md) by moving `socle_version`.
- What Autopilot forbids and what GCP lacks: [GCP limits](../clouds/gcp/limits.md).
- Staging and prod: their own projects, Wednesday and Saturday windows.
