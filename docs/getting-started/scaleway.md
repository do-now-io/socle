---
title: 'Quickstart: Scaleway'
description: From an empty Scaleway Project to a Kapsule cluster with Flux and the catalog converged.
sidebar:
  order: 4
---

Two modules in one root of your own, applied in two steps: [`opentofu/scaleway`](../../opentofu/scaleway/README.md) builds the cluster, then the [bootstrap](../../opentofu/bootstrap/README.md) installs Flux and the catalog. No Scaleway apply has run in the socle's CI.

## Before you start

From [prerequisites](../clouds/scaleway/prerequisites.md):

- **identity validated and the quota ticket answered**: 4 `COMPUTE3-X8C-16G` nodes per cluster, up to 10, and a dedicated control plane for `prod`;
- a Project for this environment, and its ID;
- an IAM application for the apply, with `KubernetesFullAccess`, `VPCFullAccess`, `PrivateNetworksFullAccess`, `VPCGatewayFullAccess`, `IPAMFullAccess`, `InstancesFullAccess` and `ObservabilityFullAccess` on the Project, `IAMManager` on the Organization, and its key exported:

  ```sh
  export SCW_ACCESS_KEY=SCWXXXXXXXXXXXXXXXXX
  export SCW_SECRET_KEY=...
  export SCW_DEFAULT_ORGANIZATION_ID=...
  export SCW_DEFAULT_PROJECT_ID=...
  ```

- a versioned Object Storage state bucket ([prerequisites](../clouds/scaleway/prerequisites.md#state));
- OpenTofu 1.10 or later, and `kubectl`.

## Write your tfvars

The root, `main.tf`. Step 1 is the foundations alone:

```hcl
terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket                      = "my-tofu-state"
    key                         = "socle/scaleway/prod/terraform.tfstate"
    region                      = "fr-par"
    endpoints                   = { s3 = "https://s3.fr-par.scw.cloud" }
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}

variable "socle_version" { type = string }
variable "project_id" { type = string }
variable "cluster_endpoint_public_access_cidrs" { type = list(string) }
variable "kube" {
  type    = any
  default = {}
}

provider "scaleway" {
  project_id = var.project_id
  region     = "fr-par"
  zone       = "fr-par-1"
}

module "foundations" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/scaleway?tag=${var.socle_version}"

  project_id   = var.project_id
  region       = "fr-par"
  cluster_name = "acme-prod"
  owner        = "platform"
  environment  = "prod"

  # Required, no default: Scaleway has no release channel.
  kubernetes_version = "1.35"

  # Required, no default, 0.0.0.0/0 refused: the control plane is always public.
  # List the runner's egress and the operators'.
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Required: when patch upgrades may land, in UTC. Production last.
  maintenance_window = { day = "saturday", start_hour = 3 }

  # Required: what the in-cluster Crossplane identity may manage in this Project.
  crossplane_permission_sets = ["ObjectStorageFullAccess"]
  crossplane_key_expires_at  = "2027-10-01T00:00:00Z"
}

output "cluster_id" { value = module.foundations.cluster_id }
output "gateway_egress_cidrs" { value = module.foundations.gateway_egress_cidrs }
```

And `prod.tfvars`:

```hcl
# The only line an upgrade touches.
socle_version = "0.0.0" # x-release-please-version

project_id                           = "22222222-2222-2222-2222-222222222222"
cluster_endpoint_public_access_cidrs = ["203.0.113.0/24"]

# Only what differs from the catalog's defaults.
kube = {}
```

The [minimal example](../../opentofu/scaleway/examples/minimal/README.md) is the same foundations call, with a relative source; CI plans it.

## Apply

**Step 1, the cluster.**

```sh
tofu init
tofu apply -var-file=prod.tfvars
```

The outputs include `crossplane_access_key` and the sensitive `crossplane_secret_key`. Nothing in the cluster uses them yet: leave the key in state, never copy it into a Secret. `oidc_issuer_url` and `workload_identity_pool` are null on Scaleway.

**Step 2, Flux and the catalog.** Add to `main.tf`:

```hcl
# Kapsule has no exec credential plugin: this exec hands the API server
# SCW_SECRET_KEY, the same variable the scaleway provider reads, at call time.
# No token is stored in state.
provider "helm" {
  kubernetes = module.foundations.helm_kubernetes
}

# The bootstrap requires the aws provider for its EKS add-ons, and OpenTofu
# configures it even when cloud = "scaleway" plans no AWS resource. This block
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

  cloud        = "scaleway"
  cluster_name = "acme-prod"
  environment  = "prod"
  owner        = "platform"
  region       = "fr-par"

  socle_version = var.socle_version
  kube          = var.kube
}
```

No Cilium and no CoreDNS here: Kapsule operates both, and the bootstrap refuses `cilium`. While the registry is private, create the pull secret in `flux-system` first and set `artifact_pull_secret` ([private registry](../guides/private-registry.md)).

For External-DNS, first create its Secret with a key that may write the zone:

```sh
kubectl create namespace external-dns
kubectl -n external-dns create secret generic external-dns-scaleway \
  --from-literal=SCW_ACCESS_KEY=SCWXXXXXXXXXXXXXXXXX \
  --from-literal=SCW_SECRET_KEY=...
```

```hcl
kube = {
  external_dns = { enabled = true, domain_filters = ["acme.example"] }
}
```

Then apply again:

```sh
tofu init
tofu apply -var-file=prod.tfvars
```

## Check it converged

Fetch a kubeconfig. `cluster_id` is `region/uuid`:

```sh
scw k8s kubeconfig install "$(tofu output -raw cluster_id | cut -d/ -f2)" region=fr-par
```

```sh
kubectl get nodes                                  # 4 nodes, 2 per zone, Ready
kubectl -n flux-system get ocirepository socle     # the pulled digest, SourceVerified
kubectl -n flux-system get resourceset             # socle-root and one per module, Ready
```

`socle-root` Ready means the catalog converged. Expect no Gateway: nothing implements Gateway API on Scaleway yet ([limits](../clouds/scaleway/limits.md#what-the-socle-does-not-offer-here-yet)).

## Next steps

- [Configure](../guides/configure.md) the catalog through `kube`, and [enable a module](../guides/enable-a-module.md).
- [Upgrade](../guides/upgrade.md): `socle_version` moves the modules and the artifact; `kubernetes_version` moves the cluster, environment by environment.
- [Limits](../clouds/scaleway/limits.md), [troubleshooting](../guides/troubleshooting.md), [uninstall](../guides/uninstall.md).
