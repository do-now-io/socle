# Socle foundations — AWS

One flat root module: VPC, EKS Standard cluster, its bootstrap nodes,
identities. It provisions a control plane with just enough compute for the
socle to start, and the identities the Flux-pulled socle needs, then steps
away.

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
}
```

The region is not a variable: it comes from the `aws` provider you configure.
`kubernetes_version` has no default and none is suggested here — the socle
pipeline owns that choice.

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
| One bootstrap node group — 2 nodes of 4 vCPU on Spot over six Graviton families, untainted, not autoscaled — the only compute this module owns | default | [Cilium design note §2](../../docs/catalog/cilium.md) |
| VPC gets at least one public and one private subnet per AZ, no all-public escape hatch | enforced | [network & security](../../docs/aws/eks-network-security.md) |
| NAT Gateway per AZ | default | [network & security](../../docs/aws/eks-network-security.md) |
| S3 Gateway endpoint always on; ECR/STS/EC2/CloudWatch Logs Interface endpoints standard | enforced | [network & security](../../docs/aws/eks-network-security.md) |
| Public EKS API access restricted by CIDR, private access always on | enforced | [network & security](../../docs/aws/eks-network-security.md) |
| Secrets encryption via KMS on by default | default | [network & security](../../docs/aws/eks-network-security.md) |
| Control plane logs (all five streams) and VPC flow logs on | default | [network & security](../../docs/aws/eks-network-security.md) |
| Pod Identity exclusively, IRSA absent | enforced | [managed scope](../../docs/aws/eks-managed-scope.md) |
| VPC CNI and kube-proxy refused — never installed at all (`bootstrap_self_managed_addons = false`) | enforced | [managed scope](../../docs/aws/eks-managed-scope.md) |
| End of standard support: AWS upgrades the cluster rather than billing extended support (`STANDARD`) | enforced | [managed scope](../../docs/aws/eks-managed-scope.md) |
| EBS CSI, EFS CSI and the Pod Identity Agent stay EKS-managed add-ons — installed by the factory, not here; CoreDNS is installed by the bootstrap module after Cilium | absent | [managed scope](../../docs/aws/eks-managed-scope.md), [catalog/cilium](../../docs/catalog/cilium.md) |
| Workload identities (Crossplane, EBS CSI) belong to the layer that installs their pods | absent | [managed scope](../../docs/aws/eks-managed-scope.md) |

## Also decided, not from research

A few defaults are plain engineering, not a research decision — flagged as
such in the code rather than dressed up with a citation that doesn't exist:

- **`vpc_cidr` default (`10.0.0.0/16`)** — arbitrary, just large enough for
  any socle estate.
- **`access_config.authentication_mode = "API"`** — the aws-auth ConfigMap
  is legacy.
- **`access_config.bootstrap_cluster_creator_admin_permissions = true`** —
  set explicitly, not left to its documented default. Measured against a
  real cluster on provider 6.x: an apply with this unset grants cluster-admin
  to nobody human, only an access entry for EKS's own service role. Explicit
  is what actually lets the apply-time principal bootstrap Flux. ForceNew —
  changing it replaces the cluster, since AWS accepts it only at creation.
- **`upgrade_policy.support_type = "STANDARD"`, with no variable** — the
  policy is that a cluster never enters extended support, so an option to
  enter it is an option we would not recommend. AWS's own default is exactly
  that option, and a cluster that takes it cannot leave until it is upgraded.
  Hardcoding STANDARD makes the rule true rather than pious: if the socle
  pipeline does its job, it never fires.
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
- **Every EKS add-on, and every variable that pinned one** — they are still
  EKS-managed add-ons, they are simply not installed from here. See below.
- **Every workload identity, Crossplane's included** — a role here would be
  half an identity. The other half is a Pod Identity association naming a
  Kubernetes service account that does not exist until the plugins are
  deployed, so both halves are built there.
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

CI plans this module directly against the floci emulator — no fixture
directory, no cloud account, no secret. The `aws` provider already honors
`AWS_ENDPOINT_URL` on its own, and the six variables with no default get
throwaway values from `TF_VAR_*`, both set in `integration.yaml`'s shared
`env:` block rather than baked into the module itself.

That leg **plans, it does not apply** — no longer because the apply fails
outright. It does not: `oidc_issuer_url` reads through `try()`, so the empty
`identity` this image's `DescribeCluster` returns yields null and all 34
resources converge. It is the *second* apply that cannot work, because the
emulator does not read back what it stored — `DescribeCluster` returns
`logging`, `encryptionConfig` and `upgradePolicy` as null, `GetRole` returns
no tags, `DescribeLogGroups` no `kmsKeyId`, `DescribeFlowLogs` no
`DeliverLogsPermissionArn`. A refresh therefore sees six resources as drifted
however many times it runs, and the apply that follows dies on
`UnsupportedOperation: Operation AssociateKmsKey is not supported`. Confirmed
to be the emulator's gap, not the module's — the same sequence against a real
EKS cluster showed zero drift. The reason is in the workflow's run summary
rather than left to be rediscovered.

## What an apply does not give you

This module provisions **nothing that needs a pod to run**, with one
exception it cannot do without: the bootstrap node group. Its nodes boot with
no CNI and are Ready — and the group ACTIVE — only once Cilium's agent runs on
them, so a root must install Cilium beside the group rather than after it
(`opentofu/clusters/aws` does). Otherwise: no Fargate profile, no Karpenter,
and no EKS add-on. What comes out is a VPC, a control plane, two nodes, log
groups and identities.

The add-ons left for that reason. CoreDNS and the EBS CSI controller are
Deployments; while the nodes wait for a CNI their pods cannot schedule, the
add-on health goes `DEGRADED`, and the apply fails before Cilium exists.

So an apply gives you a cluster with the nodes the socle starts on, and no
workload identity waiting for it. The capacity for workloads (Karpenter), the
CNI, the add-ons and the workload identities all arrive with the layer above,
because each of those identities has to name a Kubernetes service account
that this module cannot see.

That leaves one conformance checklist item unsatisfiable: outputs are required
to cover "the in-cluster provider's identity", and there is no longer one to
output. The standard needs amending once the plugins own that identity. The
gap is recorded here rather than papered over.

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
| [aws_cloudwatch_log_group.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_eks_cluster.socle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster) | resource |
| [aws_eks_node_group.bootstrap](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group) | resource |
| [aws_flow_log.socle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
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
| <a name="input_cluster_log_types"></a> [cluster\_log\_types](#input\_cluster\_log\_types) | Control plane log types shipped to CloudWatch Logs. All five by default:<br/>the audit and authenticator streams are the only record of who did what<br/>to the API server, which ISO 27001 A.8.15 and SOC 2 CC7 both expect, and<br/>the same argument that puts a private subnet tier in every VPC applies<br/>here. Trim the list to cut ingestion cost; an empty list turns control<br/>plane logging off entirely. | `list(string)` | <pre>[<br/>  "api",<br/>  "audit",<br/>  "authenticator",<br/>  "controllerManager",<br/>  "scheduler"<br/>]</pre> | no |
| <a name="input_create_nat_gateway"></a> [create\_nat\_gateway](#input\_create\_nat\_gateway) | Create one NAT Gateway per AZ. One per AZ, never a single shared one, to<br/>avoid cross-AZ data transfer charges — not a toggle for disabling NAT<br/>outright, which the private-subnet decision above rules out. Exists<br/>only for the create\_vpc = false case, where the consumer's existing VPC<br/>already manages its own NAT. | `bool` | `true` | no |
| <a name="input_create_vpc"></a> [create\_vpc](#input\_create\_vpc) | Create the VPC, or attach to one the consumer already manages. | `bool` | `true` | no |
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
|------|-------------|
| <a name="output_bootstrap_node_group"></a> [bootstrap\_node\_group](#output\_bootstrap\_node\_group) | The bootstrap node group, once its nodes have joined. node\_count is what the bootstrap module checks before it installs anything that needs a node; referencing it is also what orders those releases after the group. |
| <a name="output_cilium_operator_policy_json"></a> [cilium\_operator\_policy\_json](#output\_cilium\_operator\_policy\_json) | IAM policy the Cilium operator needs in ENI mode — the bootstrap module installs Cilium on this cluster before Flux. The bootstrap nodes' role already carries it; any other node role the operator may be scheduled on needs it too. |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Base64-encoded cluster CA certificate, for building a kubeconfig. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | The control plane's API endpoint — the access path the socle and its automation use. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the EKS cluster. |
| <a name="output_helm_kubernetes"></a> [helm\_kubernetes](#output\_helm\_kubernetes) | Drop-in value for the helm provider's kubernetes attribute, so a root configures it in one line. Carries no credential: the exec plugin obtains a short-lived token from the caller's ambient AWS credentials at call time, exactly as the aws provider itself authenticates. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | The cluster's OIDC issuer. Checklist requirement, not this module's identity mechanism — Pod Identity is, IRSA is absent, and nothing here provisions an OIDC trust relationship against it. Null on an emulated cluster that reports no identity (floci), so an apply there still converges. |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnet IDs, one per AZ. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | Public subnet IDs, one per AZ. |
| <a name="output_region"></a> [region](#output\_region) | Region the cluster and VPC were created in, as resolved from the provider. |
| <a name="output_service_cidr"></a> [service\_cidr](#output\_service\_cidr) | The Kubernetes service range EKS chose for this cluster (172.20.0.0/16 or 10.100.0.0/16, by VPC CIDR). The bootstrap module gives CoreDNS its .10 address, the one every node's kubelet is told to use. Null on an emulated cluster that reports none (floci). |
| <a name="output_tags"></a> [tags](#output\_tags) | The standard tag set applied to every billable resource this module creates. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC the cluster is attached to, whether this module created it or not. |
<!-- END_TF_DOCS -->
