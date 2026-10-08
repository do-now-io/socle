# Socle foundations — AWS

One flat module: the VPC, the EKS Standard cluster, its bootstrap node group,
the log groups, and the identities nothing in the cluster can create
(Crossplane's, on request). It provisions nothing that needs a pod to run,
except the bootstrap node group.

It does not converge alone. The bootstrap nodes boot with no CNI and the
group turns `ACTIVE` only once Cilium runs on them, so a root applies this
module together with [`opentofu/bootstrap`](../bootstrap), which installs
Cilium beside the group. That root is [`opentofu/clusters/aws`](../clusters/aws);
start from the [AWS quickstart](../../docs/getting-started/aws.md).

```hcl
module "foundations" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/aws?tag=${var.socle_version}"

  cluster_name = "acme-prod"
  owner        = "platform"
  environment  = "prod"

  availability_zones                   = ["eu-west-3a", "eu-west-3b"]
  kubernetes_version                   = "1.34"
  cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"]
}
```

The region is the `aws` provider's, not a variable. `kubernetes_version` has
no default.

What is decided for you, what is deliberately absent, and why:
[AWS foundations](../../docs/clouds/aws/foundations.md).

> **OpenTofu does not verify OCI signatures.** It pulls an unsigned or
> tampered artifact without complaint; Flux verifies, OpenTofu does not. Run
> `cosign verify` before `tofu init`:
> [distribution](../../docs/architecture/distribution.md).

## Tests

```bash
tofu test
```

Plans only, offline: every validation fails once, and the defaults are
asserted, with the provider's credentials stubbed. CI also plans this module against the floci emulator
(`integration.yaml`), with the variables that have no default set through
`TF_VAR_*`. The module is applied, through the real root, by the
`root (aws)` job of `e2e.yaml` on floci's k3s.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0, < 7.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_acm_certificate.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate_validation.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_cloudwatch_log_group.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_eks_cluster.socle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster) | resource |
| [aws_eks_node_group.bootstrap](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group) | resource |
| [aws_eks_pod_identity_association.crossplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_flow_log.socle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_policy.crossplane_boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.crossplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.crossplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.node_cilium_operator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.node_ecr_pull](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_internet_gateway.socle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_kms_key.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key.secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_launch_template.bootstrap](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_nat_gateway.socle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route53_record.gateway_certificate_validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.vpc_endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.socle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.cilium_operator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.node_ecr_pull](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_route53_zone.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | AZs the VPC's public and private subnets are spread across. Every VPC<br/>gets at least one public and one private subnet per AZ — never a flat,<br/>all-public layout — to satisfy ISO 27001 A.8.22 and SOC 2 CC6 network<br/>segregation. There is no all-public escape hatch: the private tier is<br/>structural, whether or not a client's workloads use it. | `list(string)` | n/a | yes |
| <a name="input_cluster_endpoint_public_access_cidrs"></a> [cluster\_endpoint\_public\_access\_cidrs](#input\_cluster\_endpoint\_public\_access\_cidrs) | CIDRs allowed to reach the public EKS API endpoint. Required, no<br/>default: the endpoint is restricted by CIDR rather than left open or<br/>made fully private-only (AWS's own recommended pattern for this case),<br/>and there is no globally correct default to authorize on a client's<br/>behalf. | `list(string)` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name shared by the VPC, the EKS cluster and every resource this module creates around them. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Stamped on every billable resource. Also what the factory's upgrade rings (dev/staging/prod) key off. | `string` | n/a | yes |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | EKS control plane version. Required, no default: the module accepts<br/>whatever version it is given rather than enforcing the policy ceiling<br/>itself. The n-1 policy ceiling / n-2 compatibility floor is decided and<br/>bumped by the socle Kargo pipelines, not by this module — a `validation`<br/>block cannot call the AWS API to know what "current" is, and the<br/>decoupled socle-release/Kubernetes-version pipelines are the actual<br/>owners of that decision. | `string` | n/a | yes |
| <a name="input_owner"></a> [owner](#input\_owner) | Stamped on every billable resource so cost can be attributed and orphans can be found. | `string` | n/a | yes |
| <a name="input_additional_tags"></a> [additional\_tags](#input\_additional\_tags) | Extra tags merged onto every resource this module creates, on top of owner/environment/socle-version. | `map(string)` | `{}` | no |
| <a name="input_bootstrap_node_capacity_type"></a> [bootstrap\_node\_capacity\_type](#input\_bootstrap\_node\_capacity\_type) | SPOT by default: the several instance types spread the two nodes over<br/>independent pools, and EKS replaces a node at risk before draining it.<br/>ON\_DEMAND for a cluster that must not lose a bootstrap node to a<br/>reclaim, at about two and a half times the price. | `string` | `"SPOT"` | no |
| <a name="input_bootstrap_node_count"></a> [bootstrap\_node\_count](#input\_bootstrap\_node\_count) | How many bootstrap nodes, spread over the private subnets' AZs. Two by<br/>default: when one is reclaimed or lost the other carries the whole socle<br/>until it is replaced, CoreDNS keeps a replica, and Karpenter's chart<br/>places its two replicas on different nodes in different zones.<br/>One is accepted on a cluster that can live with neither. Nothing scales<br/>this group, so it is one number rather than min, max and desired. | `number` | `2` | no |
| <a name="input_bootstrap_node_instance_types"></a> [bootstrap\_node\_instance\_types](#input\_bootstrap\_node\_instance\_types) | Instance types of the bootstrap node group, which carries Cilium's<br/>operator, CoreDNS, Flux and later Karpenter — not the client's<br/>workloads, which Karpenter's nodes carry. Several on Spot, so the nodes<br/>come from independent capacity pools; on demand, the first is used. The<br/>default is six Graviton families of 4 vCPU and 8 to 32 GiB: each one<br/>alone carries the whole socle, Karpenter included, with half its CPU<br/>left, so losing a node to a reclaim is routine. All must share an<br/>architecture, which the AMI follows. | `list(string)` | <pre>[<br/>  "t4g.xlarge",<br/>  "m7g.xlarge",<br/>  "m6g.xlarge",<br/>  "c7g.xlarge",<br/>  "c6g.xlarge",<br/>  "r6g.xlarge"<br/>]</pre> | no |
| <a name="input_cluster_log_types"></a> [cluster\_log\_types](#input\_cluster\_log\_types) | Control plane log types shipped to CloudWatch Logs. None by default:<br/>ingestion is billed by the gigabyte, and the audit stream records every<br/>request to the API server — one controller writing in a loop made it<br/>about $40 a day on an idle cluster (#80). A client whose audit expects<br/>the API server's record of who did what (ISO 27001 A.8.15, SOC 2 CC7)<br/>turns on at least audit and authenticator; the log group, its retention<br/>and its key exist either way, so the first line is already covered. | `list(string)` | `[]` | no |
| <a name="input_create_nat_gateway"></a> [create\_nat\_gateway](#input\_create\_nat\_gateway) | Create one NAT Gateway per AZ. One per AZ, never a single shared one, to<br/>avoid cross-AZ data transfer charges — not a toggle for disabling NAT<br/>outright, which the private-subnet decision above rules out. Exists<br/>only for the create\_vpc = false case, where the consumer's existing VPC<br/>already manages its own NAT. | `bool` | `true` | no |
| <a name="input_create_vpc"></a> [create\_vpc](#input\_create\_vpc) | Create the VPC, or attach to one the consumer already manages. | `bool` | `true` | no |
| <a name="input_crossplane"></a> [crossplane](#input\_crossplane) | Give the catalog's crossplane module its AWS identity — the one the socle<br/>cannot make for itself: an IAM role, bound through EKS Pod Identity to<br/>crossplane-system/provider-aws, allowed to create roles under<br/>/socle/<cluster\_name>/ only, and only carrying the permissions boundary<br/>this module writes. allowed\_services is that boundary: the AWS services<br/>(IAM action prefixes, such as route53 or s3) any module's role may be<br/>granted. Empty grants nothing; iam, sts, organizations, account, sso and<br/>identitystore are refused. Which resources of those services a module<br/>reaches is its own role's policy. Null, the default, creates nothing. The<br/>client root passes the boundary's ARN into kube.crossplane. | <pre>object({<br/>    allowed_services = optional(list(string), [])<br/>  })</pre> | `null` | no |
| <a name="input_force_update_version"></a> [force\_update\_version](#input\_force\_update\_version) | Force the control plane version update even if Upgrade Insights reports<br/>blocking findings. Default false: Upgrade Insights is a mandatory<br/>pre-check, never sufficient alone (it only sees the client's own<br/>removed-API usage, over a rolling 30-day audit-log window that both<br/>misses infrequent calls and over-reports fixed ones) — but AWS's own<br/>blocking of `update-cluster-version` on ERROR findings is currently<br/>rolled back, so this module does not assume AWS enforces the check<br/>either. | `bool` | `false` | no |
| <a name="input_gateway_certificate"></a> [gateway\_certificate](#input\_gateway\_certificate) | The ACM certificate the socle's two Gateways terminate TLS with, at the<br/>load balancer: `domain` and `*.domain`, validated by DNS in the public<br/>Route 53 zone named `domain` — found by name, no zone ID to copy. `zone`<br/>names that zone instead when `domain` is a subdomain of it, such as<br/>domain = "sbx.acme.example" in zone = "acme.example". Every route<br/>published through a Gateway — ArgoCD's included — is then<br/>`<name>.<domain>`. Null, the default, creates nothing, and the bootstrap<br/>module creates no Gateway: the socle never serves a route in clear text. | <pre>object({<br/>    domain = string<br/>    zone   = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention for the log groups this module creates — the control plane's and the VPC flow logs'. Set explicitly because a log group left to AWS never expires. | `number` | `90` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Existing private subnet IDs, one per AZ in availability\_zones. Required when create\_vpc is false — this module carves its own subnets out of vpc\_cidr only when it also creates the VPC. | `list(string)` | `[]` | no |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | Existing public subnet IDs, one per AZ in availability\_zones. Required when create\_vpc is false — same reasoning as private\_subnet\_ids. | `list(string)` | `[]` | no |
| <a name="input_secrets_encryption_enabled"></a> [secrets\_encryption\_enabled](#input\_secrets\_encryption\_enabled) | Envelope-encrypt Kubernetes Secrets via KMS. On by default: essentially free (~$1/month per key, negligible per-request cost), and standard on Kubernetes 1.28+ already. | `bool` | `true` | no |
| <a name="input_secrets_encryption_kms_key_arn"></a> [secrets\_encryption\_kms\_key\_arn](#input\_secrets\_encryption\_kms\_key\_arn) | Existing KMS key for Secrets envelope encryption. Leave unset and the module creates its own key. Ignored when secrets\_encryption\_enabled is false. | `string` | `null` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR for the VPC when this module creates it. Arbitrary default (not a research decision) — a /16 large enough for any socle estate. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_vpc_flow_logs_enabled"></a> [vpc\_flow\_logs\_enabled](#input\_vpc\_flow\_logs\_enabled) | Record accepted and rejected traffic on the VPC this module creates. On by default, aggregated over ten-minute windows to keep the volume down: it is the only record of who talked to whom, and the segmentation this VPC is built around is unauditable without it. | `bool` | `true` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | Existing VPC to attach to. Required when create\_vpc is false, and incoherent to set when create\_vpc is true — this module cannot both create a VPC and attach to a different one. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bootstrap_node_group"></a> [bootstrap\_node\_group](#output\_bootstrap\_node\_group) | The bootstrap node group, once its nodes have joined. node\_count is what the bootstrap module checks before it installs anything that needs a node; referencing it is also what orders those releases after the group. |
| <a name="output_cilium_operator_policy_json"></a> [cilium\_operator\_policy\_json](#output\_cilium\_operator\_policy\_json) | IAM policy the Cilium operator needs in ENI mode — the bootstrap module installs Cilium on this cluster before Flux. The bootstrap nodes' role already carries it; any other node role the operator may be scheduled on needs it too. |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Base64-encoded cluster CA certificate, for building a kubeconfig. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | The control plane's API endpoint — the access path the socle and its automation use. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the EKS cluster. |
| <a name="output_crossplane_permissions_boundary_arn"></a> [crossplane\_permissions\_boundary\_arn](#output\_crossplane\_permissions\_boundary\_arn) | ARN of the permissions boundary every role Crossplane creates must carry — what kube.crossplane.permissions\_boundary takes, and what the client root passes for you. Null when crossplane is not set. |
| <a name="output_crossplane_role_arn"></a> [crossplane\_role\_arn](#output\_crossplane\_role\_arn) | ARN of the IAM role the catalog's crossplane module's AWS providers run as, through Pod Identity. Null when crossplane is not set. |
| <a name="output_gateway_certificate_arn"></a> [gateway\_certificate\_arn](#output\_gateway\_certificate\_arn) | ARN of the issued ACM certificate the socle's Gateways terminate TLS with — what the bootstrap module's gateway\_certificate\_arn takes, and what the client root passes for you. Null when gateway\_certificate is not set. |
| <a name="output_helm_kubernetes"></a> [helm\_kubernetes](#output\_helm\_kubernetes) | Drop-in value for the helm provider's kubernetes attribute, so a root configures it in one line. Carries no credential: the exec plugin obtains a short-lived token from the caller's ambient AWS credentials at call time, exactly as the aws provider itself authenticates. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | The cluster's OIDC issuer. Checklist requirement, not this module's identity mechanism — Pod Identity is, IRSA is absent, and nothing here provisions an OIDC trust relationship against it. Null on an emulated cluster that reports no identity (floci), so an apply there still converges. |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnet IDs, one per AZ. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | Public subnet IDs, one per AZ. |
| <a name="output_region"></a> [region](#output\_region) | Region the cluster and VPC were created in, as resolved from the provider. |
| <a name="output_service_cidr"></a> [service\_cidr](#output\_service\_cidr) | The Kubernetes service range EKS chose for this cluster (172.20.0.0/16 or 10.100.0.0/16, by VPC CIDR). The bootstrap module gives CoreDNS its .10 address, the one every node's kubelet is told to use. Null on an emulated cluster that reports none (floci). |
| <a name="output_tags"></a> [tags](#output\_tags) | The standard tag set applied to every billable resource this module creates. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC the cluster is attached to, whether this module created it or not. |
<!-- END_TF_DOCS -->
