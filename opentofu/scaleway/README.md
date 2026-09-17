# Socle foundations — Scaleway

One flat root module: VPC, Private Network, Public Gateways, the Kapsule
cluster, its pools and the identities the Flux-pulled socle needs. It
provisions an empty shell, then steps away.

```hcl
module "socle" {
  source = "oci://<registry>/<repo>//opentofu/scaleway?tag=<version>"

  project_id   = "22222222-2222-2222-2222-222222222222"
  region       = "fr-par"
  cluster_name = "socle-prod"
  owner        = "platform"
  environment  = "prod"

  kubernetes_version                   = "1.35"
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/24"]

  maintenance_window = {
    day        = "saturday"
    start_hour = 3
  }

  crossplane_permission_sets = ["RelationalDatabasesFullAccess"]
}
```

A deployable version of that is in [`examples/minimal`](examples/minimal),
which also lists the permissions the apply needs and where remote state
belongs. What has to exist on the Scaleway account before any of it runs is in
[prerequisites](../../docs/scaleway/prerequisites.md).

> **OpenTofu does not verify OCI signatures.** It will pull an unsigned or
> tampered artifact without complaint. Run `cosign verify` in CI before
> `tofu init`, or enforce it through registry policy, and pin by digest.

## What is decided for you

Every default traces back to a research document. The short version:

| Decision | Position | Traces to |
| --- | --- | --- |
| Kapsule, Cilium, no CNI option | enforced | [capabilities](../../docs/scaleway/kapsule-capabilities.md) |
| Dedicated control plane in production, mutualized elsewhere | derived from `environment` | [capabilities](../../docs/scaleway/kapsule-capabilities.md) |
| Full isolation — no node carries a public address | enforced | [capabilities](../../docs/scaleway/kapsule-capabilities.md) |
| One Public Gateway per zone the pools span | enforced | [capabilities](../../docs/scaleway/kapsule-capabilities.md) |
| Allowed-IP list required, `0.0.0.0/0` refused | required | [capabilities](../../docs/scaleway/kapsule-capabilities.md) |
| Kubernetes version explicit, no floating tag | required | [capabilities](../../docs/scaleway/kapsule-capabilities.md) |
| Maintenance window required, no default | required | [capabilities](../../docs/scaleway/kapsule-capabilities.md) |
| `expander = least_waste`, not Scaleway's `random` | default | [capabilities](../../docs/scaleway/kapsule-capabilities.md) |
| COMPUTE3-X nodes across two zones of fr-par | default | [capabilities](../../docs/scaleway/kapsule-capabilities.md) |
| A security group per cluster, not the shared default | enforced | [capabilities](../../docs/scaleway/kapsule-capabilities.md) |
| One Project per environment | required | [managed scope](../../docs/scaleway/managed-scope.md) |
| Crossplane key bound to a source address | default | [managed scope](../../docs/scaleway/managed-scope.md) |
| Query-only Cockpit token; nothing pushed to Cockpit | default | [cloud observability](../../docs/scaleway/cloud-observability.md) |

## Two exceptions this module has to declare

**It issues a credential.** Every other foundations module refuses to, and the
conformance checklist says modules authenticate through ambient credentials or
workload identity federation. Scaleway has no workload identity federation at
all, so an in-cluster Crossplane provider can only hold a long-lived API key.
The module creates it, marks it sensitive, scopes its policy to one Project,
binds it to the gateways' egress addresses with an IAM condition, and lets a
consumer set an expiry. That is the whole mitigation available. See
[`iam.tf`](iam.tf).

**There is no TFLint ruleset for Scaleway.** `terraform-linters` publishes none
and neither does anyone else, so `.tflint.hcl` carries the recommended
`terraform` preset alone. The module leans on `tofu test` instead — 37 cases,
one per validation block plus the recommended-defaults assertions.

## What is deliberately absent

Not oversights. An option in the interface is an option that is supported and
tested, so these are refusals:

- **Kosmos** — a different CNI, no Private Network, and no migration path in
  either direction.
- **A CNI variable** — Kapsule supports `cilium` and `calico`; `none` is not
  supported, so a self-managed Cilium is impossible and Calico is worse on
  every count.
- **Controlled isolation** — it would have dev and staging exercising a
  different egress path from production.
- **`price` as an autoscaler expander** — upstream implements it for GCE and
  AWS only, so on Scaleway it is a silent no-op.
- **BASIC3-X and the development ranges as node types** — shared vCPU and a
  99% SLO.
- **`feature_gates`, `admission_plugins`, `apiserver_cert_sans`,
  `open_id_connect_config`** — Kapsule exposes them and the socle needs none.
- **Cockpit alerting, contacts, dashboards and data exports** — catalog
  concerns, so four clouds share one definition.
- **Load balancers, DNS records and certificates** — the cloud controller
  manager, External-DNS and cert-manager own those, in-cluster.

## What no apply can finish

- **Quota.** The reference estate wants four `COMPUTE3-X8C-16G` nodes in
  production; the shape it replaces is capped at two by default and the quota
  table has no figure for the Zen 5 generation at all. Raising a quota is a
  support ticket, before the first apply.
- **Identity validation.** Without it most useful instance types have no quota
  whatsoever.

## Integration testing

This module's leg is **plan-only**. Scaleway publishes no emulator, and there
is no third-party one — recorded in the conformance checklist as an exception,
not hidden.

Two offline checks stand in for an apply, and neither is one:

- **`tofu test`**, in `pr-static.yaml`, plans the module itself — 37 runs, 5
  asserting the recommended defaults and 32 tripping the 32 validation blocks
  one by one.
- **`tofu plan` on `examples/minimal`**, in `integration.yaml`, plans the
  module the way a consumer calls it, so the example's own wiring and outputs
  are exercised too.

Both use fixture credentials over empty state, so no API call leaves the
runner and forks can run them. **Convergence is not proven by either.** That
needs a real Project, a quota raise and an apply.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_scaleway"></a> [scaleway](#requirement\_scaleway) | >= 2.82, < 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [scaleway_cockpit_token.observability](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/cockpit_token) | resource |
| [scaleway_iam_api_key.crossplane](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/iam_api_key) | resource |
| [scaleway_iam_application.crossplane](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/iam_application) | resource |
| [scaleway_iam_policy.crossplane](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/iam_policy) | resource |
| [scaleway_instance_placement_group.socle](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/instance_placement_group) | resource |
| [scaleway_instance_security_group.socle](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/instance_security_group) | resource |
| [scaleway_ipam_ip.gateway](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/ipam_ip) | resource |
| [scaleway_k8s_acl.socle](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/k8s_acl) | resource |
| [scaleway_k8s_cluster.socle](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/k8s_cluster) | resource |
| [scaleway_k8s_pool.socle](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/k8s_pool) | resource |
| [scaleway_vpc.socle](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/vpc) | resource |
| [scaleway_vpc_gateway_network.socle](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/vpc_gateway_network) | resource |
| [scaleway_vpc_private_network.socle](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/vpc_private_network) | resource |
| [scaleway_vpc_public_gateway.socle](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/vpc_public_gateway) | resource |
| [scaleway_vpc_public_gateway_ip.socle](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/vpc_public_gateway_ip) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_endpoint_public_access_cidrs"></a> [cluster\_endpoint\_public\_access\_cidrs](#input\_cluster\_endpoint\_public\_access\_cidrs) | CIDRs allowed to reach the Kubernetes API server. Required with no default: the control plane cannot be made private on Kapsule, so this list is the only boundary there is, and Kapsule ships 0.0.0.0/0. | `list(string)` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the Kapsule cluster. Also names the network resources the module creates. | `string` | n/a | yes |
| <a name="input_crossplane_permission_sets"></a> [crossplane\_permission\_sets](#input\_crossplane\_permission\_sets) | Permission sets granted to the in-cluster Crossplane identity, scoped to this Project. Required with no default: what Crossplane may provision is a per-client decision, and a default would either be uselessly narrow or dangerously wide. | `list(string)` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment this cluster serves. Stamped as a tag, decides the default control plane offer, and is the axis the upgrade ring order follows. | `string` | n/a | yes |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes minor or patch version. Required with no default: Scaleway has no release channel, auto-upgrade covers patches only, and a floating version would let the pipeline lose track of which minor is deployed. | `string` | n/a | yes |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | When patch auto-upgrades may run. Required with no default: a silent default means nobody decided when production gets upgraded, and the window is what orders the upgrade rings across environments. | <pre>object({<br/>    day        = string<br/>    start_hour = number<br/>  })</pre> | n/a | yes |
| <a name="input_owner"></a> [owner](#input\_owner) | Team accountable for the cluster. Stamped as a tag on every resource that takes tags. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Scaleway Project that holds the cluster and its network. One Project per environment: it is the only boundary Scaleway offers for both IAM and cost attribution. | `string` | n/a | yes |
| <a name="input_additional_tags"></a> [additional\_tags](#input\_additional\_tags) | Extra tags merged onto the standard set, rendered as key=value. Cannot override owner, environment, cluster or socle-version. | `map(string)` | `{}` | no |
| <a name="input_autoscaler_expander"></a> [autoscaler\_expander](#input\_autoscaler\_expander) | How the cluster-autoscaler picks which pool to grow. least\_waste strands the least capacity; Scaleway's own default is random, which is a coin flip once there is more than one pool. | `string` | `"least_waste"` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Zones the node pools span, one pool per zone. Two is the default because the current instance generation exists in only two zones of fr-par and nl-ams; only pl-waw offers three. | `list(string)` | <pre>[<br/>  "fr-par-1",<br/>  "fr-par-2"<br/>]</pre> | no |
| <a name="input_cockpit_token_enabled"></a> [cockpit\_token\_enabled](#input\_cockpit\_token\_enabled) | Create a query-only Cockpit token so the central observability cluster can federate Scaleway's own metrics and logs. Reading is what the supervision plane does; pushing into Cockpit is billed per sample and is refused. | `bool` | `true` | no |
| <a name="input_control_plane_type"></a> [control\_plane\_type](#input\_control\_plane\_type) | Control plane offer. Null derives it from environment — dedicated 4 in production for the SLA and the audit log, mutualized elsewhere. Kosmos offers are absent by decision. | `string` | `null` | no |
| <a name="input_create_vpc"></a> [create\_vpc](#input\_create\_vpc) | Create the VPC instead of attaching to an existing one. Routing is VPC-wide, so one VPC per environment is the layout the research recommends. | `bool` | `true` | no |
| <a name="input_crossplane_allowed_cidrs"></a> [crossplane\_allowed\_cidrs](#input\_crossplane\_allowed\_cidrs) | Source addresses the Crossplane key may be used from, as an IAM policy condition. Empty derives it from the Public Gateways' egress addresses, which is the only stable source a fully isolated node presents. | `list(string)` | `[]` | no |
| <a name="input_crossplane_key_expires_at"></a> [crossplane\_key\_expires\_at](#input\_crossplane\_key\_expires\_at) | RFC 3339 expiry for the Crossplane API key. Null means no expiry. Scaleway has no workload identity federation, so this key is the credential — an expiry is what forces the rotation the factory owns. | `string` | `null` | no |
| <a name="input_delete_additional_resources"></a> [delete\_additional\_resources](#input\_delete\_additional\_resources) | On cluster deletion, also delete the Load Balancers and Block volumes Kubernetes created. False keeps client data when a cluster is torn down, at the price of orphaned billable resources someone has to clean up. | `bool` | `false` | no |
| <a name="input_node_type"></a> [node\_type](#input\_node\_type) | Commercial type of the pool nodes. COMPUTE3-X is the current generation: dedicated vCPU at 1 vCPU per 2 GiB. BASIC3-X is refused for nodes — shared vCPU and a 99% SLO. | `string` | `"COMPUTE3-X8C-16G"` | no |
| <a name="input_pool_max_size"></a> [pool\_max\_size](#input\_pool\_max\_size) | Maximum nodes per pool, and therefore per zone. | `number` | `5` | no |
| <a name="input_pool_min_size"></a> [pool\_min\_size](#input\_pool\_min\_size) | Minimum nodes per pool, and therefore per zone. Billed whether anything schedules on them or not, because the autoscaler never consolidates. | `number` | `2` | no |
| <a name="input_private_network_cidr"></a> [private\_network\_cidr](#input\_private\_network\_cidr) | IPv4 subnet of the cluster's Private Network. Kapsule consumes a /22 per cluster, so anything larger is wasted and anything smaller is refused. | `string` | `"10.10.0.0/22"` | no |
| <a name="input_public_gateway_type"></a> [public\_gateway\_type](#input\_public\_gateway\_type) | Offer of the Public Gateways that carry node egress. VPC-GW-S handles 100 Mbps, which is ample for image pulls and API calls. | `string` | `"VPC-GW-S"` | no |
| <a name="input_region"></a> [region](#input\_region) | Scaleway region for the cluster, its network and its pools. | `string` | `"fr-par"` | no |
| <a name="input_root_volume_size_in_gb"></a> [root\_volume\_size\_in\_gb](#input\_root\_volume\_size\_in\_gb) | System volume of each node. Scaleway's own guidance is 20 GB minimum and 100 GB to hold images and system logs comfortably. | `number` | `100` | no |
| <a name="input_scale_down_unneeded_time"></a> [scale\_down\_unneeded\_time](#input\_scale\_down\_unneeded\_time) | How long a node must sit below the utilisation threshold before the autoscaler removes it. | `string` | `"10m"` | no |
| <a name="input_scale_down_utilization_threshold"></a> [scale\_down\_utilization\_threshold](#input\_scale\_down\_utilization\_threshold) | Requested resources over allocatable capacity, below which a node becomes a scale-down candidate. | `number` | `0.5` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of an existing VPC to attach the cluster's Private Network to. Mutually exclusive with create\_vpc. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Base64-encoded cluster CA certificate, for building a kubeconfig. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | URL of the Kubernetes API server. Always public on Kapsule — a fully private control plane does not exist — and reachable only from cluster\_endpoint\_public\_access\_cidrs. |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | ID of the Kapsule cluster, in region/uuid form. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the Kapsule cluster. |
| <a name="output_cluster_region"></a> [cluster\_region](#output\_cluster\_region) | Region of the cluster. A Kapsule cluster lives in exactly one. |
| <a name="output_cluster_type"></a> [cluster\_type](#output\_cluster\_type) | The control plane offer in force. Derived from environment unless control\_plane\_type overrides it: production gets a dedicated offer for the SLA and the audit log. |
| <a name="output_cockpit_token_secret"></a> [cockpit\_token\_secret](#output\_cockpit\_token\_secret) | Query-only Cockpit token for the central observability cluster to federate Scaleway's metrics and logs. Null when cockpit\_token\_enabled is false. |
| <a name="output_crossplane_access_key"></a> [crossplane\_access\_key](#output\_crossplane\_access\_key) | Access key of the Crossplane API key. Not secret on its own, but pair it with crossplane\_secret\_key. |
| <a name="output_crossplane_application_id"></a> [crossplane\_application\_id](#output\_crossplane\_application\_id) | ID of the IAM application the in-cluster Crossplane provider authenticates as. |
| <a name="output_crossplane_secret_key"></a> [crossplane\_secret\_key](#output\_crossplane\_secret\_key) | Secret key for the in-cluster Crossplane provider. This is a long-lived credential because Scaleway offers no alternative; it is bound to the source addresses in crossplane\_allowed\_cidrs and expires at crossplane\_key\_expires\_at. |
| <a name="output_gateway_egress_cidrs"></a> [gateway\_egress\_cidrs](#output\_gateway\_egress\_cidrs) | Public addresses the cluster's nodes egress from, one per zone, as /32 CIDRs. This is the estate's stable source address: allow-list it wherever a client needs to admit the cluster. |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Raw kubeconfig for the cluster. Sensitive: it carries a bearer token. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | Always null. Kapsule exposes no OIDC issuer for workload identity, so nothing can federate against this cluster's ServiceAccount tokens. |
| <a name="output_private_network_id"></a> [private\_network\_id](#output\_private\_network\_id) | ID of the cluster's Private Network. |
| <a name="output_security_group_ids"></a> [security\_group\_ids](#output\_security\_group\_ids) | The cluster's own node security groups, keyed by zone. Not the shared Kapsule default, which is common to every cluster in the Project. One per zone because an Instance security group is a zoned resource. |
| <a name="output_tags"></a> [tags](#output\_tags) | The standard tag set applied to every resource this module creates that accepts tags. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC the cluster's Private Network sits in, whether the module created it or not. |
| <a name="output_wildcard_dns"></a> [wildcard\_dns](#output\_wildcard\_dns) | DNS wildcard resolving to every ready node. Useful for reaching a NodePort before an ingress path exists. |
| <a name="output_workload_identity_pool"></a> [workload\_identity\_pool](#output\_workload\_identity\_pool) | Always null. Scaleway has no workload identity federation — the in-cluster provider authenticates with the API key below instead. |
<!-- END_TF_DOCS -->

## License

[Apache-2.0](../../LICENSE)
