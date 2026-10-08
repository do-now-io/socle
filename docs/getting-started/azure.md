---
title: 'Quickstart: Azure'
description: From an Azure subscription to a private AKS cluster with Cilium, Flux and the catalog, in two applies.
sidebar:
  order: 3
---

Two modules in one root of your own, applied in two steps:
[`opentofu/azure`](../../opentofu/azure/README.md) builds the cluster, then the
[bootstrap](../../opentofu/bootstrap/README.md) installs Cilium, Flux and the
catalog.

:::caution
No Azure apply has run, in CI or on a real subscription: both modules are
planned with mocked providers only ([limits](../clouds/azure/limits.md)).
:::

## Before you start

From [prerequisites](../clouds/azure/prerequisites.md):

- the resource providers registered: `Microsoft.ContainerService`,
  `Microsoft.Network`, `Microsoft.Compute`, `Microsoft.ManagedIdentity`,
  `Microsoft.OperationalInsights`, `Microsoft.Monitor`;
- **Contributor and User Access Administrator** on the subscription for the
  principal that applies (the module creates the resource group);
- a versioned state storage account and container
  ([prerequisites](../clouds/azure/prerequisites.md#state));
- vCPU quota for 2 × Standard_D2s_v5 in zones 1, 2 and 3, and the families
  NAP picks; a region without three zones needs `zones` set;
- for step 2, a runner that reaches the private VNet and resolves its
  private DNS zone;
- OpenTofu 1.10 or later, the Azure CLI, `kubectl`.

```sh
az login
export ARM_SUBSCRIPTION_ID=<subscription-id>   # azurerm 4.x needs it
```

## Write your tfvars

The root, `main.tf`. Step 1 is the foundations alone:

```hcl
terraform {
  required_version = ">= 1.10"

  backend "azurerm" {
    resource_group_name  = "socle-tfstate-rg"
    storage_account_name = "socletfstate<suffix>"
    container_name       = "tfstate"
    key                  = "socle/azure/acme-dev.tfstate"
  }
}

variable "socle_version" { type = string }
variable "kubernetes_version" { type = string }
variable "maintenance_window_auto_upgrade" { type = any }
variable "maintenance_window_node_os" { type = any }
variable "kube" {
  type    = any
  default = {}
}

provider "azurerm" {
  features {}
}

module "foundations" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/azure?tag=${var.socle_version}"

  location            = "francecentral"
  cluster_name        = "acme-dev"
  resource_group_name = "acme-dev"
  owner               = "platform"
  environment         = "dev"

  # Required, no default: pin the minor per cluster, dev before prod;
  # AKS's stable channel then moves the cluster inside the window below.
  kubernetes_version = var.kubernetes_version

  # Required, no default, 4 to 24 hours each. Stagger them per cluster:
  # dev first, prod last.
  maintenance_window_auto_upgrade = var.maintenance_window_auto_upgrade
  maintenance_window_node_os      = var.maintenance_window_node_os
}

output "cluster_name" { value = module.foundations.cluster_name }
output "resource_group_name" { value = module.foundations.resource_group_name }
output "cluster_endpoint" { value = module.foundations.cluster_endpoint }
```

`cluster_name` must suit the bootstrap too: 1 to 40 lowercase letters, digits
and dashes, starting with a letter. `dev.tfvars`:

```hcl
# The only line an upgrade touches.
socle_version = "0.0.0" # x-release-please-version

kubernetes_version = "1.36"

maintenance_window_auto_upgrade = {
  frequency   = "Weekly"
  interval    = 1
  duration    = 4
  day_of_week = "Sunday"
  start_time  = "02:00"
  utc_offset  = "+00:00"
}

maintenance_window_node_os = {
  frequency   = "Weekly"
  interval    = 1
  duration    = 4
  day_of_week = "Saturday"
  start_time  = "03:00"
  utc_offset  = "+00:00"
}

# Only what differs from the catalog's defaults.
kube = {}
```

The [minimal example](../../opentofu/azure/examples/minimal/README.md) is the
same foundations call, with a relative source.

## Apply

**Step 1, the cluster**, from anywhere:

```sh
tofu init
tofu apply -var-file=dev.tfvars
```

The two `system` nodes stay `NotReady`: no CNI until step 2.

**Step 2, Cilium, Flux and the catalog**, from the runner that reaches the
VNet. Helm reads the admin kubeconfig
([why](../clouds/azure/limits.md#what-no-apply-can-finish)):

```sh
az aks get-credentials --resource-group acme-dev --name acme-dev --admin --file kubeconfig
```

Keep that file out of version control: it holds the admin's client
certificate. Add to `main.tf`:

```hcl
provider "helm" {
  kubernetes = {
    config_path = "${path.root}/kubeconfig"
  }
}

# The bootstrap requires the aws provider for its EKS add-ons, and OpenTofu
# configures it even when cloud = "azure" plans no AWS resource. This block
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

  cloud        = "azure"
  cluster_name = module.foundations.cluster_name
  environment  = "dev"
  owner        = "platform"
  region       = module.foundations.location

  socle_version = var.socle_version
  kube          = var.kube

  # Cilium before Flux: AKS is created with no CNI. What it needs comes from
  # the foundations' outputs: the private API server for kube-proxy
  # replacement, and the pod pool, which is not set on the cluster.
  cluster_network = {
    api_endpoint = module.foundations.cluster_endpoint
    pod_cidr     = module.foundations.pod_cidr
  }
}
```

```sh
tofu init
tofu apply -var-file=dev.tfvars
```

While the registry is private, create the pull secret in `flux-system` first
and set `artifact_pull_secret` ([private registry](../guides/private-registry.md)).
The Flux Operator stays `Pending` until NAP brings a node it can run on,
within `helm_timeout_seconds` (600).

## Check it converged

```sh
export KUBECONFIG=$PWD/kubeconfig
kubectl get nodes                                    # every node Ready
kubectl -n kube-system rollout status daemonset/cilium
kubectl -n flux-system get ocirepository socle       # the pulled digest, and SourceVerified
kubectl -n flux-system get resourceset               # socle-root and one per module, Ready
```

`socle-root` Ready means the catalog converged; a green apply alone does
not.

## Next steps

- [Configure](../guides/configure.md) the catalog and
  [enable a module](../guides/enable-a-module.md). On Azure `velero` and
  `kube.keda.services` are refused; external-dns needs the
  `external-dns-azure` Secret ([external-dns](../catalog/external-dns.md)).
- [Upgrade](../guides/upgrade.md) with `socle_version`; keep
  `kubernetes_version` at the cluster's minor once AKS has moved it
  ([limits](../clouds/azure/limits.md#what-no-apply-can-finish)).
- [Foundations](../clouds/azure/foundations.md): what is decided for you.
