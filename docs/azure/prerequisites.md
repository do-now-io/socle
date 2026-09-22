# Azure — prerequisites

What must exist on your Azure subscription before `tofu apply` can run the
socle foundations module. The module creates none of it.

Each item can be done by hand in the Azure Portal — nothing is provided for
that path — or from the command line. The commands for every item are
gathered in [By command line](#by-command-line) at the end.

## Subscription

- An Azure subscription. It is very likely to hold **several clusters** —
  dev/staging/prod rings, or more than one environment for the same
  client. This module does not assume exclusive ownership of the
  subscription.
- Regional vCPU quota for the VM SKU families used — the system node pool
  (`system_node_pool_vm_size`) and whatever NAP later provisions. Default
  quotas usually clear a handful of clusters; worth checking ahead of the
  third or fourth.
- Resource providers registered: `Microsoft.ContainerService`,
  `Microsoft.OperationalInsights`, `Microsoft.Monitor`, `Microsoft.Network`,
  `Microsoft.Compute`, `Microsoft.ManagedIdentity`. Not automatic on a
  subscription that has never used one of these services — `tofu apply`
  fails with `MissingSubscriptionRegistration` until registered.

## Roles on the principal running OpenTofu

| Scope | Role | Grants |
| --- | --- | --- |
| Target resource group (or the subscription, if `create_resource_group = true` needs a new one) | Contributor | The VNet, subnet, NAT Gateway, public IP, AKS cluster, Log Analytics workspace, Monitor workspace, data collection rule |
| Same scope | User Access Administrator (or a custom role with `Microsoft.Authorization/roleAssignments/write`) | AKS's `SystemAssigned` identity needs Network Contributor on the VNet/subnet it ends up using — Contributor alone can't create that role assignment, whether the module creates the VNet or attaches to an existing one |

Contributor alone is a common trap here: the deployment fails on the
cluster resource, not on the role assignment itself, since AKS attempts
the grant on your behalf during `PUT`.

## Credentials

The module accepts no credential as input. The provider reads Azure's own
ambient credential chain — `az login` for local runs, Workload Identity
Federation (OIDC) from CI via an app registration's federated credential,
no client secret either way.

```sh
export ARM_USE_OIDC=true
export ARM_CLIENT_ID=<app-id>
export ARM_TENANT_ID=<tenant-id>
export ARM_SUBSCRIPTION_ID=<subscription-id>
```

## State

A Storage Account and blob container for remote state. The `azurerm`
backend locks natively through blob leases — no separate lock resource
needed. The module ships no backend block; state lives in your own
subscription, so declare it in your root configuration:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "socle-tfstate-rg"
    storage_account_name = "sockletfstatexxxx"
    container_name       = "tfstate"
    key                  = "socle/azure/<cluster-name>.tfstate"
  }
}
```

## Tooling

- OpenTofu, at or above the floor the module's `required_version` sets.
- Azure CLI, authenticated (`az login`).

## Good practices

Per resource, what to do beyond simply creating it.

### Subscription

- Separate environments by resource group and state key prefix, not by
  subscription boundary alone.
- A budget with alert thresholds (`az consumption budget create`).
  Several clusters sharing one subscription make a runaway workload's
  cost easy to miss inside the aggregate bill.

### Roles

- A dedicated app registration for OpenTofu, federated via OIDC from CI
  and via interactive `az login` (never a client secret) for humans.
- Scoped to the target resource group, not the subscription, and not
  `Owner`.
- No client secret ever created on the app registration — enforce it with
  an Azure Policy if the tenant has one.

### Credentials

- Federated credential (OIDC) in CI, interactive `az login` for humans.
- No app registration client secrets, ever.

### State storage account

State holds every attribute of every resource, secrets included, and
losing it means the cluster exists but is no longer manageable.

- Blob versioning and soft delete on before the first write.
- Storage account firewall restricted, or a private endpoint, if the
  network reaching it is controlled.
- One container prefix per cluster/environment: one subscription, and
  therefore one storage account, commonly serves several clusters.
- Never shared with application data.

## By command line

Set the variables once:

```sh
LOCATION=francecentral
SUBSCRIPTION_ID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
TARGET_RG=my-cluster-rg
STATE_RG=socle-tfstate-rg
STATE_STORAGE_ACCOUNT=sockletfstatexxxx
STATE_CONTAINER=tfstate
APP_NAME=socle-tofu
```

Register resource providers (once per subscription):

```sh
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Monitor
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.ManagedIdentity
```

Credentials — an app registration CI federates via OIDC, trusting one
specific repository and branch:

```sh
APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
az ad sp create --id "$APP_ID"
az ad app federated-credential create --id "$APP_ID" --parameters '{
  "name": "github-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:do-now-io/socle:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

Scope the role assignments to the target resource group (create it first
if the module isn't the one creating it):

```sh
az group create --name "$TARGET_RG" --location "$LOCATION"
az role assignment create --assignee "$APP_ID" --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$TARGET_RG"
az role assignment create --assignee "$APP_ID" --role "User Access Administrator" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$TARGET_RG"
```

State storage:

```sh
az group create --name "$STATE_RG" --location "$LOCATION"
az storage account create --name "$STATE_STORAGE_ACCOUNT" --resource-group "$STATE_RG" \
  --location "$LOCATION" --sku Standard_LRS --encryption-services blob
az storage container create --name "$STATE_CONTAINER" --account-name "$STATE_STORAGE_ACCOUNT" --auth-mode login
az storage account blob-service-properties update --account-name "$STATE_STORAGE_ACCOUNT" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 30
```

Then point the backend at the state storage and initialise:

```sh
tofu init -backend-config="resource_group_name=$STATE_RG" \
  -backend-config="storage_account_name=$STATE_STORAGE_ACCOUNT" \
  -backend-config="container_name=$STATE_CONTAINER" \
  -backend-config="key=socle/azure/<cluster-name>.tfstate"
```
