---
title: 'Quickstart: GCP'
description: From an empty GCP project to a GKE Autopilot cluster where the socle has converged, in one apply.
sidebar:
  order: 2
---

One `tofu apply` of the GCP root builds the VPC, its Cloud NAT and the GKE
Autopilot cluster, installs Flux; Flux then converges the catalog. GKE runs
the network (Dataplane V2), the cluster DNS and the nodes: there is nothing
to size.

## Before you start

From [Prerequisites](../clouds/gcp/prerequisites.md):

- a billed project with its APIs enabled, and **one socle cluster per
  project**: every Workload Identity principal names the project, never the
  cluster;
- a GCS state bucket;
- a principal with the
  [apply roles](../clouds/gcp/prerequisites.md#permissions-for-the-apply),
  logged in for both the provider (Application Default Credentials) and
  `gke-gcloud-auth-plugin`;
- [quotas](../clouds/gcp/prerequisites.md#quotas) raised: a fresh project's
  CPU and SSD quotas are not enough;
- OpenTofu 1.13 or later, `gcloud`, `gke-gcloud-auth-plugin`, `kubectl`.

## Write your main.tf

One file in an empty directory: the state backend, then the socle's GCP root
called as a module. Change the names, the region and the window, keep the
rest:

```hcl title="main.tf"
terraform {
  backend "gcs" {
    bucket = "acme-prod-tofu-state"
    prefix = "socle/gcp/acme-prod"
  }
}

locals {
  socle_version = "0.2.1" # x-release-please-version
}

module "socle" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/clusters/gcp?tag=${local.socle_version}"

  socle_version = local.socle_version

  gcp = {
    project_id   = "acme-prod"
    region       = "europe-west1"
    cluster_name = "acme-prod"
    owner        = "platform"
    environment  = "prod"

    # When GKE may upgrade the cluster, at least four hours: here Saturday
    # 02:00-14:00 UTC.
    maintenance_window = {
      start_time = "2026-01-03T02:00:00Z"
      end_time   = "2026-01-03T14:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }

    # Create the VPC, its subnetwork, NAT and proxy-only subnet. Without it,
    # network_name names a VPC you already own.
    create_network = true
  }
}

output "cluster_name" {
  value = module.socle.cluster_name
}
```

- `socle_version` is the only line an [upgrade](../guides/upgrade.md) touches:
  it moves the module source and the Flux artifact together.
- `maintenance_window` has no default: GKE upgrades the cluster on its own,
  you choose when. The day orders the rings, for example dev on Tuesday,
  staging on Wednesday, prod on Saturday.
- No Kubernetes version: the `REGULAR` release channel decides
  (`release_channel`, `kubernetes_min_version` to raise the floor).

To serve routes on your domain and let modules have their own Google Cloud
access, add under `gcp`:

```hcl
    # The Google-managed certificates of the two shared Gateways, authorised
    # by DNS in the managed zone acme-example of this project. Without it no
    # Gateway is created.
    gateway_certificate = { dns_zone = "acme-example", domains = ["acme.example", "*.acme.example"] }

    # Crossplane's grants; allowed_roles is the ceiling of every role a
    # catalog module gets. Empty still grants external-dns its DNS records role.
    crossplane = { allowed_roles = [] }
```

With both and `crossplane = { enabled = true }` under `kube`, external-dns
turns on for those domains. The role each module needs in `allowed_roles`:
[Crossplane's allowed roles](../clouds/gcp/prerequisites.md#crossplanes-allowed-roles).
Every other key: [Foundations](../clouds/gcp/foundations.md) and
[Configure](../guides/configure.md).

## Apply

```sh
tofu init
tofu apply
```

The apply ends once Flux's objects are in the cluster; Flux converges the
catalog after that.

## Check it converged

```sh
gcloud container clusters get-credentials acme-prod \
  --region europe-west1 --project acme-prod --dns-endpoint
kubectl -n flux-system get resourceset
kubectl -n flux-system get ocirepository socle
```

`socle-root` at `READY True` means every module's `ResourceSet` is applied
and healthy; the `OCIRepository` shows the pulled digest and
`SourceVerified`. If `socle-root` stays not Ready, the module's `ResourceSet`
names what is waiting: see [Troubleshooting](../guides/troubleshooting.md).

## Next steps

- [Enable a module](../guides/enable-a-module.md) and
  [Configure](../guides/configure.md) it.
- [Upgrade](../guides/upgrade.md): one line, `socle_version`.
- [Foundations](../clouds/gcp/foundations.md) and
  [Limits](../clouds/gcp/limits.md) on GCP.
- [Uninstall](../guides/uninstall.md).
