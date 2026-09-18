# Minimal socle foundations — Azure

The smallest deployable example of the [`opentofu/azure`](../../) module:
region, name, owner, environment, and the handful of variables the module
deliberately leaves with no default.

## Roles the apply needs

At minimum, a principal able to create resource groups, VNets, subnets, NAT
Gateways and public IPs, an AKS cluster, a Log Analytics workspace, and an
Azure Monitor workspace with its data collection rule.

## Remote state

Not configured here on purpose — state belongs in the consumer's own
account. Declare a backend in a root configuration that wraps this
example, for instance:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name = "my-tfstate-rg"
    storage_account_name = "mytfstateaccount"
    container_name        = "tfstate"
    key                    = "socle/azure/minimal.tfstate"
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0, < 5.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_socle"></a> [socle](#module\_socle) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the cluster. | `string` | `"socle-minimal"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment this cluster serves. | `string` | `"dev"` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | AKS control plane version. The default tracks the n-1 policy ceiling — not the newest AKS offers, and not one close to the end of its standard support. | `string` | `"1.36"` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the cluster and its resource group. | `string` | `"francecentral"` | no |
| <a name="input_maintenance_window_auto_upgrade"></a> [maintenance\_window\_auto\_upgrade](#input\_maintenance\_window\_auto\_upgrade) | Window Kubernetes version auto-upgrades are allowed to run in. | <pre>object({<br/>    frequency   = string<br/>    interval    = number<br/>    duration    = number<br/>    day_of_week = optional(string)<br/>    start_time  = optional(string)<br/>    utc_offset  = optional(string)<br/>  })</pre> | <pre>{<br/>  "day_of_week": "Sunday",<br/>  "duration": 4,<br/>  "frequency": "Weekly",<br/>  "interval": 1,<br/>  "start_time": "02:00",<br/>  "utc_offset": "+00:00"<br/>}</pre> | no |
| <a name="input_maintenance_window_node_os"></a> [maintenance\_window\_node\_os](#input\_maintenance\_window\_node\_os) | Window node OS security patches are allowed to run in. | <pre>object({<br/>    frequency   = string<br/>    interval    = number<br/>    duration    = number<br/>    day_of_week = optional(string)<br/>    start_time  = optional(string)<br/>    utc_offset  = optional(string)<br/>  })</pre> | <pre>{<br/>  "day_of_week": "Saturday",<br/>  "duration": 4,<br/>  "frequency": "Weekly",<br/>  "interval": 1,<br/>  "start_time": "03:00",<br/>  "utc_offset": "+00:00"<br/>}</pre> | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Team accountable for the cluster. | `string` | `"platform"` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group the cluster and its resources are created in. | `string` | `"socle-minimal"` | no |
| <a name="input_system_node_pool_vm_size"></a> [system\_node\_pool\_vm\_size](#input\_system\_node\_pool\_vm\_size) | VM size for the mandatory system node pool. Override if the module's default is unavailable in your subscription's quota for this region. | `string` | `"Standard_D2s_v5"` | no |
| <a name="input_zones"></a> [zones](#input\_zones) | Availability zones the default system node pool spreads across. Not every subscription/region/VM-size combination has all three available — override if the module's default fails with AvailabilityZoneNotSupported. | `list(string)` | <pre>[<br/>  "1",<br/>  "2",<br/>  "3"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | n/a |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | n/a |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | n/a |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | n/a |
<!-- END_TF_DOCS -->
