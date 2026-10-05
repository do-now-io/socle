---
title: Prerequisites
description: The Azure subscription, roles, state, network reach and tooling the socle expects before the first apply.
sidebar:
  order: 1
---

What must exist before `tofu apply` runs the [foundations](foundations.md).
The module creates none of it.

## Account

- An Azure subscription. It may hold several clusters (dev, staging, prod, or
  several clients' environments): the module assumes no exclusive ownership.
- These resource providers registered. A subscription that never used one
  fails the apply with `MissingSubscriptionRegistration`:

  ```sh
  az provider register --namespace Microsoft.ContainerService
  az provider register --namespace Microsoft.Network
  az provider register --namespace Microsoft.Compute
  az provider register --namespace Microsoft.ManagedIdentity
  # Only while the module still creates Container Insights and Managed Prometheus:
  az provider register --namespace Microsoft.OperationalInsights
  az provider register --namespace Microsoft.Monitor
  ```

  `Microsoft.OperationalInsights` and `Microsoft.Monitor` serve the Log
  Analytics workspace, the Azure Monitor workspace and the data collection
  rule of [AZURE-05](../../decisions/azure.md#azure-05-managed-prometheus-and-container-insights),
  which is superseded but still in the code.

## Permissions for the apply

The module takes no credential as input. `azurerm` reads the ambient chain:
`az login` on a workstation, Workload Identity Federation (OIDC) in CI, with
no client secret either way:

```sh
export ARM_USE_OIDC=true
export ARM_CLIENT_ID=<app-id>
export ARM_TENANT_ID=<tenant-id>
export ARM_SUBSCRIPTION_ID=<subscription-id>
```

The principal needs two roles, on the target resource group, or on the
subscription when the module creates the group (`create_resource_group = true`):

| Role | Why |
| --- | --- |
| Contributor | The resource group, VNet, subnet, NAT gateway, public IP, AKS cluster, Log Analytics workspace, Azure Monitor workspace and data collection rule |
| User Access Administrator, or any role with `Microsoft.Authorization/roleAssignments/write` | The cluster's system-assigned identity needs Network Contributor on the node subnet, whether the module creates it or attaches to yours. Contributor cannot write a role assignment |

The module declares no role assignment itself. The requirement is AKS's,
for a cluster on a VNet that AKS does not create.

To scope both roles to an existing resource group:

```sh
SUBSCRIPTION_ID=<subscription-id>
TARGET_RG=<resource-group>
APP_ID=<app-id>
az role assignment create --assignee "$APP_ID" --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$TARGET_RG"
az role assignment create --assignee "$APP_ID" --role "User Access Administrator" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$TARGET_RG"
```

For CI, an app registration with a federated credential trusting one
repository and branch, and no secret:

```sh
APP_ID=$(az ad app create --display-name socle-tofu --query appId -o tsv)
az ad sp create --id "$APP_ID"
az ad app federated-credential create --id "$APP_ID" --parameters '{
  "name": "github-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<org>/<repo>:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

### Reaching the cluster for the bootstrap

The cluster is private, with no public FQDN
([AZURE-12](../../decisions/azure.md#azure-12-a-private-cluster-with-no-public-fqdn)).
The foundations apply only calls Azure's API and runs from anywhere. The
bootstrap apply talks to the Kubernetes API through Helm, so its runner needs:

- a route to the API server's private endpoint: a runner in the VNet, or a
  network connected to it by peering, VPN or ExpressRoute;
- resolution of the cluster's private DNS zone (`privatelink.<region>.azmk8s.io`),
  which is linked to the cluster's VNet only;
- a kubeconfig. The module's `helm_kubernetes` output does not log in yet (see
  [limits](limits.md#what-no-apply-can-finish)); the
  [quickstart](../../getting-started/azure.md#apply) uses
  `az aks get-credentials --admin`.

## State

A storage account and a blob container in your subscription. The `azurerm`
backend locks through blob leases: no lock resource. The module ships no
backend block; declare it in your root:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "socle-tfstate-rg"
    storage_account_name = "socletfstate<suffix>"
    container_name       = "tfstate"
    key                  = "socle/azure/<cluster-name>.tfstate"
  }
}
```

State holds every attribute of every resource, the cluster's CA included.
Turn versioning and soft delete on before the first write, and keep one key
per cluster:

```sh
LOCATION=francecentral
STATE_RG=socle-tfstate-rg
STATE_ACCOUNT=socletfstate<suffix>   # 3 to 24 lowercase letters and digits, globally unique
az group create --name "$STATE_RG" --location "$LOCATION"
az storage account create --name "$STATE_ACCOUNT" --resource-group "$STATE_RG" \
  --location "$LOCATION" --sku Standard_LRS --encryption-services blob
az storage container create --name tfstate --account-name "$STATE_ACCOUNT" --auth-mode login
az storage account blob-service-properties update --account-name "$STATE_ACCOUNT" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 30
```

`--auth-mode login` needs a data-plane role on the account, such as Storage
Blob Data Contributor, for the principal that writes state.

## Tooling

- OpenTofu 1.10 or later, the floor in [`versions.tf`](../../../opentofu/azure/versions.tf).
- Azure CLI, logged in (`az login`), for the commands on this page and for
  `az aks get-credentials`.
- `kubectl`, to check convergence.
- `cosign`, to verify the module package before `tofu init`: OpenTofu does
  not verify OCI signatures ([distribution](../../architecture/distribution.md)).

## Quotas

- Regional vCPU quota per VM family: the `system` pool
  (`system_node_pool_vm_size`, 2 × Standard_D2s_v5 by default) and every
  family NAP provisions. Check with
  `az vm list-usage --location <region> -o table`.
- Zones: the `system` pool spreads over `zones` (`["1", "2", "3"]`). A
  subscription, region and VM size without all three fails with
  `AvailabilityZoneNotSupported`; pass the zones it has, or `[]`.
- Network: one Standard public IP and one NAT gateway per cluster, plus the
  public IPs of the load balancers the shared Gateways create.
