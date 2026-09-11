# Socle foundations — AWS

One flat root module: VPC, EKS Standard cluster, identities. It provisions an
empty-shell control plane and the identities the Flux-pulled socle needs,
then steps away.

```hcl
module "socle" {
  source = "oci://<registry>/<repo>//opentofu/aws?tag=<version>"

  cluster_name = "socle-prod"
  owner        = "platform"
  environment  = "prod"

  availability_zones = ["eu-west-3a", "eu-west-3b"]

  create_vpc = true

  kubernetes_version                   = "<version>"
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]

  coredns_addon_version            = "<version>"
  ebs_csi_addon_version            = "<version>"
  pod_identity_agent_addon_version = "<version>"
}
```

The region is not a variable: it comes from the `aws` provider you configure.
Add-on and Kubernetes versions have no default and none are suggested here —
read the current ones with `aws eks describe-addon-versions`.

A deployable version of that is in [`examples/minimal`](examples/minimal),
which also lists the roles the apply needs and where remote state belongs.

> **OpenTofu does not verify OCI signatures.** It will pull an unsigned or
> tampered artifact without complaint. Run `cosign verify` in CI before
> `tofu init`, or enforce it through registry policy, and pin by digest.

## What is decided for you

Every default traces back to a research document. The short version:

| Decision | Position | Traces to |
| --- | --- | --- |
| EKS Standard, no Auto Mode option | enforced | [cluster mode](../../docs/aws/eks-cluster-mode.md) |
| Karpenter, Cilium, CSI drivers, LB controller are factory components, not provisioned here | enforced | [cluster mode](../../docs/aws/eks-cluster-mode.md) |
| VPC gets at least one public and one private subnet per AZ, no all-public escape hatch | enforced | [network & security](../../docs/aws/eks-network-security.md) |
| NAT Gateway per AZ | default | [network & security](../../docs/aws/eks-network-security.md) |
| S3 Gateway endpoint always on; ECR/STS/EC2/CloudWatch Logs Interface endpoints standard | enforced | [network & security](../../docs/aws/eks-network-security.md) |
| Public EKS API access restricted by CIDR, private access always on | enforced | [network & security](../../docs/aws/eks-network-security.md) |
| Secrets encryption via KMS on by default | default | [network & security](../../docs/aws/eks-network-security.md) |
| Control plane logs (all five streams) and VPC flow logs on | default | [network & security](../../docs/aws/eks-network-security.md) |
| Pod Identity exclusively, IRSA absent | enforced | [managed scope](../../docs/aws/eks-managed-scope.md) |
| VPC CNI and kube-proxy refused — never installed at all (`bootstrap_self_managed_addons = false`) | enforced | [managed scope](../../docs/aws/eks-managed-scope.md) |
| End of standard support: cluster stays put, socle pipelines decide when to upgrade (`EXTENDED`) | default | [managed scope](../../docs/aws/eks-managed-scope.md) |
| Add-on versions pinned, never resolved via `most_recent` | required, no default | [managed scope](../../docs/aws/eks-managed-scope.md) |
| Crossplane's AWS provider identity created here | enforced | [managed scope](../../docs/aws/eks-managed-scope.md) |

## Also decided, not from research

A few defaults are plain engineering, not a research decision — flagged as
such in the code rather than dressed up with a citation that doesn't exist:

- **`vpc_cidr` default (`10.0.0.0/16`)** — arbitrary, just large enough for
  any socle estate.
- **`access_config.authentication_mode = "API"`** — the aws-auth ConfigMap
  is legacy; the apply-time principal keeps default cluster-admin access,
  enough to bootstrap Flux.
- **Setting `upgrade_policy.support_type` at all** — the value chosen is
  AWS's own default, so this changes no behaviour. Writing it down does:
  left unset, a cluster that falls out of standard support moves to the 6x
  control plane rate without anyone having decided that, and it cannot be
  moved back until it is upgraded.
- **A customer-managed KMS key on both log groups** — CloudWatch Logs already
  encrypts at rest with an AWS-owned key, so this buys custody rather than
  encryption. It is worth one key because the control plane audit stream is
  the record of who did what to the API server, and because the module already
  spends the same dollar on the Secrets key for the same reason.
- **`log_retention_days` default (90)** — arbitrary. What is not arbitrary is
  that the module creates both log groups itself: a group EKS or VPC flow
  logs create implicitly never expires, and nobody notices until the bill
  does.
- **`kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb` and
  `kubernetes.io/cluster/<name>` subnet tags** — Karpenter and the AWS Load
  Balancer Controller need them for subnet auto-discovery once the factory
  installs them later; a network-level artifact this module has to lay
  down now regardless.

## What is deliberately absent

Not oversights. An option in the interface is an option that is supported
and tested, so these are refusals:

- **IPv6** — Cilium's ENI IPv6 IPAM mode is still beta and has an
  unresolved bug on EKS IPv6 clusters.
- **Security groups for pods** — a VPC CNI (ENI trunking) feature; Socle
  doesn't run VPC CNI. Cilium already covers the same ground in eBPF.
- **Gateway API / ALB vs NLB configuration** — the AWS Load Balancer
  Controller is a factory component delivered through the socle OCI
  artifact, like Karpenter and Cilium, not provisioned by this module.
- **DynamoDB Gateway endpoint** — dropped: no cited Socle use case, here or
  in the observability service-coverage table. S3 keeps its own citation.
- **IRSA, or any toggle for it** — Pod Identity is the only mechanism this
  module wires up. The OIDC issuer URL is still exposed as an output
  (checklist requirement), not because IRSA needs it.
- **Any credential as an input** — the module authenticates through the
  provider's ambient credentials, and issues no key.
- **GuardDuty EKS Protection** — a single detector per account per region,
  not per cluster. A client with several clusters in one AWS account would
  have two applies of this module fight over the same detector. Out of
  scope: an account-level prerequisite, not a module toggle.

## Tests

```bash
tofu test          # 15 runs: every validation, and the defaults
```

`tests/emulator/` runs the module against the floci emulator in CI, no cloud
account and no secret. It exists because the module has nine variables with no
default: CI needs somewhere to put throwaway values that is not the module
itself.

That leg **plans, it does not apply** — floci emulates no EKS add-on API and
ships none of the service-role managed policies. Both limits are the
emulator's; the reasons are in `tests/emulator/main.tf` and in the workflow's
run summary rather than left to be rediscovered.

## What an apply does not give you

This module provisions no compute. There is no managed node group, no Fargate
profile and no Karpenter — those are factory components delivered through the
socle OCI artifact. A cluster created here therefore has zero schedulable
nodes, and the CoreDNS and EBS CSI add-ons it installs have nothing to run on
until compute arrives. **Where that compute comes from is an open decision**,
not a documented one; this note is here so the gap is recorded rather than
discovered.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0, < 7.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_eks_addon.coredns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_addon.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_addon.efs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_addon.pod_identity_agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_cluster.socle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster) | resource |
| [aws_eks_pod_identity_association.crossplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_flow_log.socle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.crossplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.crossplane](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_internet_gateway.socle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_kms_key.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key.secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_nat_gateway.socle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
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
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | AZs the VPC's public and private subnets are spread across. Every VPC<br/>gets at least one public and one private subnet per AZ — never a flat,<br/>all-public layout — to satisfy ISO 27001 A.8.22 and SOC 2 CC6 network<br/>segregation. There is no all-public escape hatch: the private tier is<br/>structural, whether or not a client's workloads use it. | `list(string)` | n/a | yes |
| <a name="input_cluster_endpoint_public_access_cidrs"></a> [cluster\_endpoint\_public\_access\_cidrs](#input\_cluster\_endpoint\_public\_access\_cidrs) | CIDRs allowed to reach the public EKS API endpoint. Required, no<br/>default: the endpoint is restricted by CIDR rather than left open or<br/>made fully private-only (AWS's own recommended pattern for this case),<br/>and there is no globally correct default to authorize on a client's<br/>behalf. | `list(string)` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name shared by the VPC, the EKS cluster and every resource this module creates around them. | `string` | n/a | yes |
| <a name="input_coredns_addon_version"></a> [coredns\_addon\_version](#input\_coredns\_addon\_version) | CoreDNS add-on version. Required, no default: add-on versions are pinned by whoever triggers the bump (the socle pipeline), never resolved via most\_recent — AWS never auto-updates an add-on on its own. | `string` | n/a | yes |
| <a name="input_ebs_csi_addon_version"></a> [ebs\_csi\_addon\_version](#input\_ebs\_csi\_addon\_version) | EBS CSI driver add-on version. Required, no default — same reasoning as coredns\_addon\_version. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Stamped on every billable resource. Also what the factory's upgrade rings (dev/staging/prod) key off. | `string` | n/a | yes |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | EKS control plane version. Required, no default: the module accepts<br/>whatever version it is given rather than enforcing the policy ceiling<br/>itself. The n-1 policy ceiling / n-2 compatibility floor is decided and<br/>bumped by the socle Kargo pipelines, not by this module — a `validation`<br/>block cannot call the AWS API to know what "current" is, and the<br/>decoupled socle-release/Kubernetes-version pipelines are the actual<br/>owners of that decision. | `string` | n/a | yes |
| <a name="input_owner"></a> [owner](#input\_owner) | Stamped on every billable resource so cost can be attributed and orphans can be found. | `string` | n/a | yes |
| <a name="input_pod_identity_agent_addon_version"></a> [pod\_identity\_agent\_addon\_version](#input\_pod\_identity\_agent\_addon\_version) | Pod Identity Agent add-on version. Required, no default — same reasoning as coredns\_addon\_version. Prerequisite for all workload identity in this module. | `string` | n/a | yes |
| <a name="input_additional_tags"></a> [additional\_tags](#input\_additional\_tags) | Extra tags merged onto every resource this module creates, on top of owner/environment/socle-version. | `map(string)` | `{}` | no |
| <a name="input_cluster_log_types"></a> [cluster\_log\_types](#input\_cluster\_log\_types) | Control plane log types shipped to CloudWatch Logs. All five by default:<br/>the audit and authenticator streams are the only record of who did what<br/>to the API server, which ISO 27001 A.8.15 and SOC 2 CC7 both expect, and<br/>the same argument that puts a private subnet tier in every VPC applies<br/>here. Trim the list to cut ingestion cost; an empty list turns control<br/>plane logging off entirely. | `list(string)` | <pre>[<br/>  "api",<br/>  "audit",<br/>  "authenticator",<br/>  "controllerManager",<br/>  "scheduler"<br/>]</pre> | no |
| <a name="input_cluster_support_type"></a> [cluster\_support\_type](#input\_cluster\_support\_type) | What happens when this cluster's Kubernetes version reaches the end of<br/>standard support, 14 months after its EKS release.<br/><br/>EXTENDED, the default here and AWS's own: nothing is upgraded. The cluster<br/>enters extended support and the control plane goes from $0.10 to $0.60 an<br/>hour — around +$365 a month — until it is moved back onto a supported<br/>version. The socle pipelines keep deciding when that happens, which is the<br/>whole point of owning the version ceiling.<br/><br/>STANDARD: AWS upgrades the cluster itself at the end of standard support,<br/>on its own schedule, and no extended-support charge is ever possible. It<br/>trades a silent bill for a control plane upgrade nobody here scheduled.<br/><br/>Not reversible under pressure: a cluster already in extended support cannot<br/>be moved to STANDARD until it is upgraded onto a version still in standard<br/>support. | `string` | `"EXTENDED"` | no |
| <a name="input_create_nat_gateway"></a> [create\_nat\_gateway](#input\_create\_nat\_gateway) | Create one NAT Gateway per AZ. One per AZ, never a single shared one, to<br/>avoid cross-AZ data transfer charges — not a toggle for disabling NAT<br/>outright, which the private-subnet decision above rules out. Exists<br/>only for the create\_vpc = false case, where the consumer's existing VPC<br/>already manages its own NAT. | `bool` | `true` | no |
| <a name="input_create_vpc"></a> [create\_vpc](#input\_create\_vpc) | Create the VPC, or attach to one the consumer already manages. | `bool` | `true` | no |
| <a name="input_crossplane_policy_arns"></a> [crossplane\_policy\_arns](#input\_crossplane\_policy\_arns) | IAM policy ARNs granted to the identity the in-cluster Crossplane AWS provider assumes. Empty by default: the catalog does not exist yet, and a list written today would be a guess. | `list(string)` | `[]` | no |
| <a name="input_crossplane_service_account_name"></a> [crossplane\_service\_account\_name](#input\_crossplane\_service\_account\_name) | Name of the in-cluster Crossplane AWS provider's Kubernetes service account. Must match the socle's DeploymentRuntimeConfig — the provider Pod's service account name is not stable across provider revisions unless it is pinned there. | `string` | `"provider-aws"` | no |
| <a name="input_crossplane_service_account_namespace"></a> [crossplane\_service\_account\_namespace](#input\_crossplane\_service\_account\_namespace) | Namespace of the in-cluster Crossplane AWS provider's Kubernetes service account. | `string` | `"crossplane-system"` | no |
| <a name="input_efs_csi_addon_enabled"></a> [efs\_csi\_addon\_enabled](#input\_efs\_csi\_addon\_enabled) | Install the EFS CSI driver add-on. Catalog option, not default: RWX-only, and the node component may need its own Pod Identity association. | `bool` | `false` | no |
| <a name="input_efs_csi_addon_version"></a> [efs\_csi\_addon\_version](#input\_efs\_csi\_addon\_version) | EFS CSI driver add-on version. Required when efs\_csi\_addon\_enabled is true — same reasoning as coredns\_addon\_version. | `string` | `null` | no |
| <a name="input_force_update_version"></a> [force\_update\_version](#input\_force\_update\_version) | Force the control plane version update even if Upgrade Insights reports<br/>blocking findings. Default false: Upgrade Insights is a mandatory<br/>pre-check, never sufficient alone (it only sees the client's own<br/>removed-API usage, over a rolling 30-day audit-log window that both<br/>misses infrequent calls and over-reports fixed ones) — but AWS's own<br/>blocking of `update-cluster-version` on ERROR findings is currently<br/>rolled back, so this module does not assume AWS enforces the check<br/>either. | `bool` | `false` | no |
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
| ---- | ----------- |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Base64-encoded cluster CA certificate, for building a kubeconfig. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | The control plane's API endpoint — the access path the socle and its automation use. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the EKS cluster. |
| <a name="output_crossplane_role_arn"></a> [crossplane\_role\_arn](#output\_crossplane\_role\_arn) | The identity the in-cluster Crossplane AWS provider assumes, via Pod Identity. |
| <a name="output_crossplane_service_account_kubernetes_binding"></a> [crossplane\_service\_account\_kubernetes\_binding](#output\_crossplane\_service\_account\_kubernetes\_binding) | The Kubernetes service account bound to that identity, as namespace/name. Must match the socle's DeploymentRuntimeConfig. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | The cluster's OIDC issuer. Checklist requirement, not this module's identity mechanism — Pod Identity is, IRSA is absent, and nothing here provisions an OIDC trust relationship against it. |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnet IDs, one per AZ. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | Public subnet IDs, one per AZ. |
| <a name="output_region"></a> [region](#output\_region) | Region the cluster and VPC were created in, as resolved from the provider. |
| <a name="output_tags"></a> [tags](#output\_tags) | The standard tag set applied to every billable resource this module creates. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC the cluster is attached to, whether this module created it or not. |
<!-- END_TF_DOCS -->
