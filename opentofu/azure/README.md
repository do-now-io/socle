# Socle foundations — Azure

One flat root module: VNet, AKS Standard + Node Auto-Provisioning cluster,
identities. It provisions an empty-shell control plane and the identities
the Flux-pulled socle needs, then steps away.

```hcl
module "socle" {
  source = "oci://<registry>/<repo>//opentofu/azure?tag=<version>"

  location             = "francecentral"
  cluster_name         = "socle-prod"
  owner                = "platform"
  environment          = "prod"
  resource_group_name = "socle-prod"

  create_resource_group = true
  create_vnet             = true

  kubernetes_version = "<version>"

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

The region is not a variable, it's `location` — Azure resources take a
region per-resource rather than from provider config, unlike AWS/GCP.
`kubernetes_version` and both maintenance windows have no default and none
is suggested here — the socle pipeline owns the version choice, and there
is no globally correct maintenance window to pick on a client's behalf.

A deployable version of that is in [`examples/minimal`](examples/minimal),
which also lists the roles the apply needs and where remote state belongs.

> **OpenTofu does not verify OCI signatures.** It will pull an unsigned or
> tampered artifact without complaint. Run `cosign verify` in CI before
> `tofu init`, or enforce it through registry policy, and pin by digest.

## What is decided for you

Every default traces back to a research document. The short version:

| Decision | Position | Traces to |
| --- | --- | --- |
| AKS Standard + Node Auto-Provisioning, never Automatic | enforced | [cluster mode](../../docs/azure/cluster-mode.md) |
| Cilium, the CSI drivers and the Gateway API controller are factory components, not provisioned here | enforced | [cluster mode](../../docs/azure/cluster-mode.md) |
| Self-managed Cilium via BYO CNI (`network_plugin = "none"`), not the managed "Azure CNI powered by Cilium" | enforced | [network & security](../../docs/azure/network-security.md) |
| Node subnet sized for nodes only — Cilium owns pod IPAM entirely | enforced | [network & security](../../docs/azure/network-security.md) |
| One NAT Gateway for the node subnet | default | [network & security](../../docs/azure/network-security.md) |
| Private cluster, public FQDN disabled | enforced | [network & security](../../docs/azure/network-security.md) |
| `stable` auto-upgrade channel, `KubernetesOfficial` support plan (LTS refused) | enforced | [managed scope](../../docs/azure/managed-scope.md) |
| Managed Prometheus and Container Insights, on by default | default | [managed scope](../../docs/azure/managed-scope.md) |
| Entra Workload ID and the OIDC issuer, on by default | default | [managed scope](../../docs/azure/managed-scope.md) |
| Storage CSI stays AKS-managed | enforced | [managed scope](../../docs/azure/managed-scope.md) |

## Also decided, not from research

A few defaults are plain engineering, not a research decision — flagged as
such in the code rather than dressed up with a citation that doesn't exist:

- **`vnet_cidr` default (`10.0.0.0/16`)** — arbitrary, just large enough for
  any socle estate. The single node subnet covers the whole range: there's
  nothing else in this VNet to carve address space out for.
- **The mandatory system node pool** — AKS, unlike EKS, cannot exist with
  zero node pools. Kept small (`Standard_D2s_v5`, 2 nodes by default) and
  tainted system-only (`only_critical_addons_enabled`), since NAP owns
  every workload-shaped node.
- **`outbound_type = "userAssignedNATGateway"`** — this module attaches its
  own NAT Gateway directly to the node subnet rather than letting AKS
  manage one; this setting just tells AKS not to fall back to its default
  load-balancer-based egress path on top of it.
- **`log_retention_days` default (90)** — arbitrary, for the Container
  Insights Log Analytics workspace this module creates.

## What is deliberately absent

Not oversights. An option in the interface is an option that is supported
and tested, so these are refusals:

- **Deployment Safeguards** — decided in
  [managed scope](../../docs/azure/managed-scope.md), but azurerm (4.x
  series) has no attribute for it, and the underlying ARM property has no
  open-source GitOps equivalent the way Cilium or Karpenter do. Getting it
  in would mean either the `azapi` provider against a schema this session
  couldn't fully verify against the raw ARM Swagger, or a manual CLI step
  that breaks the "single apply" rule. Left out rather than guessed at.
- **`pod_cidr`** — azurerm only allows setting it when `network_plugin` is
  `kubenet` or `network_plugin_mode` is `overlay`, not `none`. A real gap
  between the ARM API's documented BYO CNI surface and this provider
  version's schema, not a decision.
- **Microsoft Defender for Containers** — a subscription-level singleton
  (`azurerm_security_center_subscription_pricing`), not a per-cluster
  setting. Same shape as AWS's GuardDuty detector, which was pulled out of
  `opentofu/aws/` entirely and dropped from Socle's documentation
  altogether — it's the client's own call on their own subscription, not
  Socle's to toggle or document.
- **Any Log Analytics ingestion for account-level PaaS metrics** — decided
  in [cloud observability](../../docs/azure/cloud-observability.md), but
  that decision creates no resources in this module at all (like AWS): it
  concerns a central observability cluster reading this account from the
  outside, out of this module's scope per the sprint deliverable.
- **Every workload identity, Crossplane's included** — a federated
  credential here would be half an identity. The other half is a
  Kubernetes service account that does not exist until the plugins are
  deployed, so both halves are built there. The OIDC issuer URL is still
  exposed as an output (checklist requirement).
- **Any credential as an input** — the module authenticates through the
  provider's ambient credentials, and issues no key.
- **Windows node pools, IPv6** — Node Auto-Provisioning supports neither,
  on any tier.

## Tests

```bash
tofu test          # 12 runs: every validation, and the defaults
```

Mocked, not credential-skipped: unlike `aws`/`google`, `azurerm` builds a
real authorizer and contacts Azure AD during configure regardless of
`skip_*_validation`-style flags — there is no offline stub mode to opt
into, so the provider itself is mocked (`mock_provider "azurerm" {}`), with
every cross-resource ID reference overridden to a realistic ARM ID: the
provider's own SDK parses those into their expected segment shape during
plan, even against a mock.

CI plans [`tests/emulator`](tests/emulator) against the floci-az emulator —
no cloud account, no secret. Unlike `aws`/`google`, `azurerm` has no
environment-only configuration path, so a fixture with its own `provider`
block is required rather than optional — the bare module cannot be planned
against an emulator directly.

**Currently known-red, not blocking.** floci-az's self-signed TLS
certificate fails Go's x509 validation, and `azurerm`'s cloud-metadata
discovery is HTTPS-only with no way to skip verification — the plan fails
at provider configuration, before a single resource. A floci-az bug,
outside this repo's control; `continue-on-error` keeps it off the required
checks in the meantime. What a working plan would additionally cover past
that point — real VNet/AKS/Monitor resource acceptance by floci-az — is
untested and unknown.

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
| <a name="input_service_cidr"></a> [service\_cidr](#input\_service\_cidr) | CIDR for Kubernetes service IPs. Must not overlap the VNet or any connected network, and be smaller than /12 — an AKS constraint independent of the BYO CNI choice below. | `string` | `"10.1.0.0/16"` | no |
| <a name="input_system_node_pool_node_count"></a> [system\_node\_pool\_node\_count](#input\_system\_node\_pool\_node\_count) | Node count for the mandatory system node pool. Small and fixed rather than autoscaled: this pool exists to satisfy AKS's structural minimum, not to run workloads. | `number` | `2` | no |
| <a name="input_system_node_pool_vm_size"></a> [system\_node\_pool\_vm\_size](#input\_system\_node\_pool\_vm\_size) | VM size for the mandatory system node pool. This is a structural AKS requirement, not a Karpenter/NAP-managed pool — kept small and tainted for-system-only by default (only\_critical\_addons\_enabled), since NAP provisions everything workload-shaped. | `string` | `"Standard_D2s_v5"` | no |
| <a name="input_vnet_cidr"></a> [vnet\_cidr](#input\_vnet\_cidr) | CIDR for the VNet — and its single node subnet, which covers the whole range — when this module creates it. Arbitrary default (not a research decision), sized generously since it only ever needs to fit nodes: Cilium's own IPAM owns pod addressing entirely, decoupled from the VNet. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_vnet_name"></a> [vnet\_name](#input\_vnet\_name) | Existing VNet name to attach to. Required when create\_vnet is false, and incoherent to set when create\_vnet is true — this module cannot both create a VNet and attach to a different one. | `string` | `null` | no |
| <a name="input_zones"></a> [zones](#input\_zones) | Availability zones the default system node pool spreads across. Unlike AWS's per-AZ subnets, Azure subnets aren't zone-scoped — zone placement happens on the node pool itself. | `list(string)` | <pre>[<br/>  "1",<br/>  "2",<br/>  "3"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Base64-encoded cluster CA certificate, for building a kubeconfig. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | The control plane's private FQDN — the only reachable endpoint, since this module always disables the public one. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the AKS cluster. |
| <a name="output_location"></a> [location](#output\_location) | Region the cluster and its resources were created in. |
| <a name="output_node_subnet_id"></a> [node\_subnet\_id](#output\_node\_subnet\_id) | ID of the node subnet. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | The cluster's OIDC issuer — what a workload identity federation binding built by the layer above (Crossplane's provider, or anything else) will need. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Name of the resource group the cluster and its resources live in, whether this module created it or not. |
| <a name="output_tags"></a> [tags](#output\_tags) | The standard tag set applied to every billable resource this module creates. |
| <a name="output_vnet_name"></a> [vnet\_name](#output\_vnet\_name) | Name of the VNet the cluster is attached to, whether this module created it or not. |
<!-- END_TF_DOCS -->
