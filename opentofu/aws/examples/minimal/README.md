# Minimal socle foundations — AWS

The smallest call of the [`opentofu/aws`](../../) module: a region, a name,
an owner, an environment, and the variables the module leaves without a
default. It shows the module's interface; it is not a cluster on its own.

**This example does not converge alone.** The bootstrap node group's nodes
boot with no CNI and the group turns `ACTIVE` only once Cilium runs on them,
so an apply of this example fails on the node group. A
cluster is [`opentofu/clusters/aws`](../../../clusters/aws), which applies
the foundations with the bootstrap module that installs Cilium beside the
group; start from the [AWS quickstart](../../../../docs/getting-started/aws.md).

## Roles the apply needs

The full list is on
[Prerequisites](../../../../docs/clouds/aws/prerequisites.md#permissions-for-the-apply).
For this example alone: EC2 (VPC, subnets, route tables, internet and NAT
gateways, Elastic IPs, VPC endpoints and their security group, flow logs,
the launch template), EKS (cluster, node group), IAM (the cluster, node and
flow-log roles, their inline policies and attachments, `iam:PassRole` on
each), KMS (two keys), and CloudWatch Logs (two log groups).

## Remote state

Not configured here: state belongs in the consumer's own account. Declare a
backend in the root that wraps this example, for instance:

```hcl
terraform {
  backend "s3" {
    bucket       = "my-account-tofu-state"
    key          = "socle/aws/minimal.tfstate"
    region       = "eu-west-3"
    use_lockfile = true
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0, < 7.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_socle"></a> [socle](#module\_socle) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | AZs the VPC's subnets are spread across. | `list(string)` | <pre>[<br/>  "eu-west-3a",<br/>  "eu-west-3b"<br/>]</pre> | no |
| <a name="input_cluster_endpoint_public_access_cidrs"></a> [cluster\_endpoint\_public\_access\_cidrs](#input\_cluster\_endpoint\_public\_access\_cidrs) | CIDRs allowed to reach the public EKS API endpoint. Replace with the consumer's own admin CIDR. | `list(string)` | <pre>[<br/>  "203.0.113.0/32"<br/>]</pre> | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the cluster. | `string` | `"socle-minimal"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment this cluster serves. | `string` | `"dev"` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | EKS control plane version. The default tracks the n-1 policy ceiling — not the newest EKS offers, and not one close to the end of its standard support. | `string` | `"1.36"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Team accountable for the cluster. | `string` | `"platform"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region for the cluster and its VPC. Configures the provider; the module reads it back from there. | `string` | `"eu-west-3"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Base64-encoded cluster CA certificate. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | The control plane's API endpoint. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the cluster. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | The cluster's OIDC issuer URL. |
<!-- END_TF_DOCS -->
