# Socle foundations — Azure

One flat module: a resource group, a VNet with one node subnet and a NAT
gateway, and a private AKS Standard cluster with Node Auto-Provisioning, no
CNI, Entra Workload ID and the OIDC issuer. It builds no workload; the
[bootstrap module](../bootstrap/README.md) installs Cilium and Flux on the
cluster from its outputs.

What it decides for you, what it leaves out and why:
[docs/clouds/azure/foundations.md](../../docs/clouds/azure/foundations.md).
The decisions: [docs/decisions/azure.md](../../docs/decisions/azure.md).

## Usage

```hcl
module "foundations" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/azure?tag=${var.socle_version}"

  location            = "francecentral"
  cluster_name        = "acme-prod"
  resource_group_name = "acme-prod"
  owner               = "platform"
  environment         = "prod"

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
}
```

`kubernetes_version` and both maintenance windows have no default. The
region is `location`: Azure takes it per resource, not from the provider.
There is no one-apply root for Azure: the
[quickstart](../../docs/getting-started/azure.md) applies the foundations,
then the bootstrap. [`examples/minimal`](examples/minimal) is the smallest
deployable call; the roles and the state it needs are in
[prerequisites](../../docs/clouds/azure/prerequisites.md).

> **OpenTofu does not verify OCI signatures.** Run `cosign verify` in CI
> before `tofu init`, or enforce it through registry policy:
> [distribution](../../docs/architecture/distribution.md).

## Testing

```bash
tofu test          # 14 runs: every validation, and the defaults
```

The `azurerm` provider is mocked (`mock_provider "azurerm" {}`): it contacts
Entra ID while it configures, whatever the `skip_*` flags. CI also plans
[`tests/emulator`](tests/emulator) against floci-az, a fixture with its own
`provider` block; that plan does not pass yet and is not a required check.
How CI runs: [CONTRIBUTING.md](../../CONTRIBUTING.md).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0, < 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_kubernetes_cluster.socle](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster) | resource |
| [azurerm_log_analytics_workspace.container_insights](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) | resource |
| [azurerm_monitor_data_collection_rule.prometheus](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule) | resource |
| [azurerm_monitor_data_collection_rule_association.prometheus](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule_association) | resource |
| [azurerm_monitor_workspace.socle](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_workspace) | resource |
| [azurerm_nat_gateway.socle](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway) | resource |
| [azurerm_nat_gateway_public_ip_association.socle](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway_public_ip_association) | resource |
| [azurerm_public_ip.nat](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_resource_group.socle](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_subnet.node](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_nat_gateway_association.node](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_nat_gateway_association) | resource |
| [azurerm_virtual_network.socle](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name shared by the resource group (when created), the VNet, the AKS cluster and every resource this module creates around them. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Stamped on every billable resource. Also what the factory's upgrade rings (dev/staging/prod) key off. | `string` | n/a | yes |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | AKS control plane version. Required, no default: the module accepts whatever version it is given rather than enforcing a version policy itself — that policy is decided and bumped by the socle Kargo pipelines, not by this module. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region for every resource this module creates. Required, no default — there is no globally correct region to pick on a client's behalf. | `string` | n/a | yes |
| <a name="input_maintenance_window_auto_upgrade"></a> [maintenance\_window\_auto\_upgrade](#input\_maintenance\_window\_auto\_upgrade) | Window Kubernetes version auto-upgrades (stable channel) are allowed to run in. At least 4 hours, per AKS's own constraint. | <pre>object({<br/>    frequency   = string<br/>    interval    = number<br/>    duration    = number<br/>    day_of_week = optional(string)<br/>    start_time  = optional(string)<br/>    utc_offset  = optional(string)<br/>  })</pre> | n/a | yes |
| <a name="input_maintenance_window_node_os"></a> [maintenance\_window\_node\_os](#input\_maintenance\_window\_node\_os) | Window node OS security patches are allowed to run in. Separate schedule from maintenance\_window\_auto\_upgrade, so node patching and Kubernetes upgrades never have to share a window. | <pre>object({<br/>    frequency   = string<br/>    interval    = number<br/>    duration    = number<br/>    day_of_week = optional(string)<br/>    start_time  = optional(string)<br/>    utc_offset  = optional(string)<br/>  })</pre> | n/a | yes |
| <a name="input_owner"></a> [owner](#input\_owner) | Stamped on every billable resource so cost can be attributed and orphans can be found. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group. Used as the name to create when create\_resource\_group is true, or the name of an existing one to attach to when false. | `string` | n/a | yes |
| <a name="input_additional_tags"></a> [additional\_tags](#input\_additional\_tags) | Extra tags merged onto every resource this module creates, on top of owner/environment/socle-version. | `map(string)` | `{}` | no |
| <a name="input_create_nat_gateway"></a> [create\_nat\_gateway](#input\_create\_nat\_gateway) | Create one NAT Gateway for the VNet's node subnet. Not a toggle for<br/>disabling egress outright — the node subnet has no public IP of its<br/>own, so without this its nodes reach nothing. Exists only for the<br/>create\_vnet = false case, where the consumer's existing VNet already<br/>manages its own NAT or an alternate egress path. | `bool` | `true` | no |
| <a name="input_create_resource_group"></a> [create\_resource\_group](#input\_create\_resource\_group) | Create the resource group, or attach to one the consumer already manages. | `bool` | `true` | no |
| <a name="input_create_vnet"></a> [create\_vnet](#input\_create\_vnet) | Create the VNet and its node subnet, or attach to a subnet the consumer already manages. | `bool` | `true` | no |
| <a name="input_dns_service_ip"></a> [dns\_service\_ip](#input\_dns\_service\_ip) | IP address within service\_cidr used for cluster service discovery (kube-dns). | `string` | `"10.1.0.10"` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention for the Container Insights Log Analytics workspace this module creates. | `number` | `90` | no |
| <a name="input_node_subnet_id"></a> [node\_subnet\_id](#input\_node\_subnet\_id) | Existing node subnet ID to attach to. Required when create\_vnet is false — this module carves its own subnet out of vnet\_cidr only when it also creates the VNet. | `string` | `null` | no |
| <a name="input_pod_cidr"></a> [pod\_cidr](#input\_pod\_cidr) | Range Cilium allocates pod addresses from, as the cluster pool of the<br/>Cilium the bootstrap module installs (docs/architecture/cilium-before-flux.md). Not set on<br/>the cluster: azurerm refuses pod\_cidr under network\_plugin = "none" (see<br/>cluster.tf), so this module only carries the value to the bootstrap<br/>through its output. Must not overlap the VNet, service\_cidr or any<br/>connected network. The default is AKS's own pod range, which the chart's<br/>default (10.0.0.0/8) would not be: that one contains the VNet. | `string` | `"10.244.0.0/16"` | no |
| <a name="input_service_cidr"></a> [service\_cidr](#input\_service\_cidr) | CIDR for Kubernetes service IPs. Must not overlap the VNet or any connected network, and be smaller than /12 — an AKS constraint independent of the BYO CNI choice below. | `string` | `"10.1.0.0/16"` | no |
| <a name="input_system_node_pool_node_count"></a> [system\_node\_pool\_node\_count](#input\_system\_node\_pool\_node\_count) | Node count for the mandatory system node pool. Small and fixed rather than autoscaled: this pool exists to satisfy AKS's structural minimum, not to run workloads. | `number` | `2` | no |
| <a name="input_system_node_pool_vm_size"></a> [system\_node\_pool\_vm\_size](#input\_system\_node\_pool\_vm\_size) | VM size for the mandatory system node pool. This is a structural AKS requirement, not a Karpenter/NAP-managed pool — kept small and tainted for-system-only by default (only\_critical\_addons\_enabled), since NAP provisions everything workload-shaped. | `string` | `"Standard_D2s_v5"` | no |
| <a name="input_vnet_cidr"></a> [vnet\_cidr](#input\_vnet\_cidr) | CIDR for the VNet — and its single node subnet, which covers the whole range — when this module creates it. Arbitrary default (not a research decision), sized generously since it only ever needs to fit nodes: Cilium's own IPAM owns pod addressing entirely, decoupled from the VNet. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_vnet_name"></a> [vnet\_name](#input\_vnet\_name) | Existing VNet name to attach to. Required when create\_vnet is false, and incoherent to set when create\_vnet is true — this module cannot both create a VNet and attach to a different one. | `string` | `null` | no |
| <a name="input_zones"></a> [zones](#input\_zones) | Availability zones the default system node pool spreads across. Azure subnets aren't zone-scoped — zone placement happens on the node pool itself. | `list(string)` | <pre>[<br/>  "1",<br/>  "2",<br/>  "3"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Base64-encoded cluster CA certificate, for building a kubeconfig. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | The control plane's private FQDN — the only reachable endpoint, since this module always disables the public one. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the AKS cluster. |
| <a name="output_helm_kubernetes"></a> [helm\_kubernetes](#output\_helm\_kubernetes) | Drop-in value for the helm provider's kubernetes attribute, so a root configures it in one line. Carries no credential: kubelogin obtains a short-lived Entra token from the caller's Azure CLI login at call time; the server ID is AKS's well-known Entra application. PRECONDITION NOT YET MET BY THIS MODULE: the exec only authenticates against a cluster with Entra ID authentication enabled (azure\_active\_directory\_role\_based\_access\_control), which this module does not configure yet — local accounts remain its auth path. Until it is enabled, this output is the shape a root will consume, not a working login (docs/clouds/azure/limits.md). |
| <a name="output_location"></a> [location](#output\_location) | Region the cluster and its resources were created in. |
| <a name="output_node_subnet_id"></a> [node\_subnet\_id](#output\_node\_subnet\_id) | ID of the node subnet. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | The cluster's OIDC issuer — what a workload identity federation binding built by the layer above (Crossplane's provider, or anything else) will need. |
| <a name="output_pod_cidr"></a> [pod\_cidr](#output\_pod\_cidr) | Range the bootstrap module hands Cilium as its cluster pool. Passed through, never set on the cluster: azurerm refuses pod\_cidr under BYO CNI. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Name of the resource group the cluster and its resources live in, whether this module created it or not. |
| <a name="output_tags"></a> [tags](#output\_tags) | The standard tag set applied to every billable resource this module creates. |
| <a name="output_vnet_name"></a> [vnet\_name](#output\_vnet\_name) | Name of the VNet the cluster is attached to, whether this module created it or not. |
<!-- END_TF_DOCS -->
