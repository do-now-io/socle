# Minimal Scaleway socle foundation

The smallest deployable foundation: a Project, a name, an owner, a Kubernetes
version, and the two decisions the module refuses to make for you — who may
reach the API server, and when patches may land.

```bash
export SCW_ACCESS_KEY="..."
export SCW_SECRET_KEY="..."

tofu init
tofu apply \
  -var project_id=22222222-2222-2222-2222-222222222222 \
  -var 'cluster_endpoint_public_access_cidrs=["203.0.113.0/24"]'
```

## Before the first apply

- **Raise the instance quota.** The default pool is two
  `COMPUTE3-X8C-16G` nodes per zone across two zones. Scaleway's per-type
  quotas sit below that on a new Organization, and only a support ticket moves
  them. An apply that hits the ceiling fails while building a pool.
- **Validate the Organization's identity.** Without it, most production
  instance types have no quota at all.

## Remote state

There is no `backend` block here on purpose: remote state belongs in the
consumer's own account, and the module neither creates nor assumes one.
Scaleway Object Storage works without a second service for locking — it
implements S3 conditional writes, which is what `use_lockfile` needs.

```hcl
terraform {
  backend "s3" {
    bucket                      = "my-tofu-state"
    key                         = "socle/scaleway/terraform.tfstate"
    region                      = "fr-par"
    endpoints                   = { s3 = "https://s3.fr-par.scw.cloud" }
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}
```

Turn on bucket versioning and server-side encryption. Object Lock belongs on a
Velero bucket, not on this one — it would make a legitimate state rewrite
impossible.

## What the apply needs

An IAM application with an API key, and a policy scoped to the target Project
carrying:

| Permission set | For |
| --- | --- |
| `KubernetesFullAccess` | the cluster, its pools and its ACL |
| `VPCFullAccess` | the VPC and the Private Network |
| `PublicGatewaysFullAccess` | the gateways and their flexible IPs |
| `IPAMFullAccess` | the gateways' private address reservations |
| `InstancesFullAccess` | the placement groups and the security group |
| `IAMManager` | the Crossplane application, policy and key |
| `ObservabilityFullAccess` | the query-only Cockpit token |

`IAMManager` is Organization-scoped by nature, which is the one permission
here that cannot be confined to a Project. Give it to the automation's
application and to nothing else, and bind that application's key to the
runner's egress address with a policy condition.

## Outputs

`oidc_issuer_url` and `workload_identity_pool` are **null on this cloud, and
only on this cloud**. Kapsule exposes no OIDC issuer and Scaleway has no
workload identity federation, so the in-cluster provider authenticates with
`crossplane_access_key` and `crossplane_secret_key` instead. They are returned
rather than omitted so that one output surface holds across four clouds.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_scaleway"></a> [scaleway](#requirement\_scaleway) | >= 2.82, < 3.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_socle"></a> [socle](#module\_socle) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_endpoint_public_access_cidrs"></a> [cluster\_endpoint\_public\_access\_cidrs](#input\_cluster\_endpoint\_public\_access\_cidrs) | CIDRs allowed to reach the Kubernetes API server. No default: whoever deploys this has to say who gets in. | `list(string)` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Scaleway Project to deploy into. One Project per environment — it is the only boundary Scaleway offers for both IAM and cost. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the cluster. | `string` | `"socle-minimal"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment this cluster serves. | `string` | `"dev"` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes minor to deploy. Explicit by design: Scaleway has no release channel. | `string` | `"1.35"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Team accountable for the cluster. | `string` | `"platform"` | no |
| <a name="input_region"></a> [region](#input\_region) | Region for the cluster and its network. | `string` | `"fr-par"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Base64-encoded cluster CA certificate. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | URL of the Kubernetes API server. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the cluster. |
| <a name="output_crossplane_access_key"></a> [crossplane\_access\_key](#output\_crossplane\_access\_key) | Access key of the in-cluster Crossplane identity. |
| <a name="output_crossplane_secret_key"></a> [crossplane\_secret\_key](#output\_crossplane\_secret\_key) | Secret key of the in-cluster Crossplane identity. |
| <a name="output_gateway_egress_cidrs"></a> [gateway\_egress\_cidrs](#output\_gateway\_egress\_cidrs) | The addresses this cluster's nodes egress from. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | Null on Scaleway: Kapsule exposes no OIDC issuer for workload identity. |
| <a name="output_workload_identity_pool"></a> [workload\_identity\_pool](#output\_workload\_identity\_pool) | Null on Scaleway: there is no workload identity federation. |
<!-- END_TF_DOCS -->
