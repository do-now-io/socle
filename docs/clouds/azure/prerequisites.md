---
title: Prerequisites
description: The Azure subscription, roles, state, network reach and tooling the socle expects before the first apply.
sidebar:
  order: 1
---

Tick these before `tofu apply` runs the [foundations](foundations.md). The
module creates none of it.

## Account

- [ ] An Azure subscription; it may hold several clusters.
- [ ] The resource providers registered, or the apply fails with
  `MissingSubscriptionRegistration`:

```sh
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.ManagedIdentity
# Only while the module still creates Container Insights and Managed Prometheus (AZURE-05):
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Monitor
```

## Permissions for the apply

- [ ] **Contributor** for the principal that applies, on the target resource
  group, or on the subscription with `create_resource_group = true`.
- [ ] **User Access Administrator**, or any role with
  `Microsoft.Authorization/roleAssignments/write`, on the same scope: AKS
  grants the cluster's identity Network Contributor on the node subnet, which
  Contributor cannot.
- [ ] Credentials from the ambient chain, no client secret: `az login`
  locally, OIDC in CI:

```sh
export ARM_USE_OIDC=true
export ARM_CLIENT_ID=<app-id>
export ARM_TENANT_ID=<tenant-id>
export ARM_SUBSCRIPTION_ID=<subscription-id>
```

Both roles, scoped to an existing resource group:

```sh
SUBSCRIPTION_ID=<subscription-id>
TARGET_RG=<resource-group>
APP_ID=<app-id>
az role assignment create --assignee "$APP_ID" --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$TARGET_RG"
az role assignment create --assignee "$APP_ID" --role "User Access Administrator" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$TARGET_RG"
```

For CI, an app registration trusting one repository and branch:

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
The foundations apply runs from anywhere; the bootstrap's runner needs:

- [ ] a route to the API server's private endpoint: in the VNet, or peered,
  VPN or ExpressRoute;
- [ ] resolution of the private DNS zone (`privatelink.<region>.azmk8s.io`),
  linked to the cluster's VNet only;
- [ ] a kubeconfig from `az aks get-credentials --admin`: the module's
  `helm_kubernetes` output does not log in yet
  ([limits](limits.md#what-no-apply-can-finish),
  [quickstart](../../getting-started/azure.md#apply)).

## State

- [ ] A storage account and blob container, versioning and soft delete on,
  one key per cluster. Blob leases lock.
- [ ] A data-plane role on the account, such as Storage Blob Data
  Contributor, for the principal that writes state (`--auth-mode login`).

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

## Tooling

- [ ] OpenTofu 1.10 or later ([`versions.tf`](../../../opentofu/azure/versions.tf)).
- [ ] The Azure CLI, logged in (`az login`).
- [ ] `kubectl`.
- [ ] `cosign`, to verify the modules package: OpenTofu does not verify OCI
  signatures ([distribution](../../architecture/distribution.md)).

## Quotas

- [ ] Regional vCPUs per VM family, for the `system` pool (2 ×
  Standard_D2s_v5) and every family NAP picks:
  `az vm list-usage --location <region> -o table`.
- [ ] Zones 1, 2 and 3 for the `system` VM size, or the apply fails with
  `AvailabilityZoneNotSupported`; set `zones` to what the region has, or
  `[]`.
- [ ] One Standard public IP and one NAT gateway per cluster, plus the shared
  Gateways' load balancer IPs.
