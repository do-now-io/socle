---
title: Foundations
description: 'The AWS foundations module: what is decided for you, what is deliberately absent, and its full reference.'
sidebar:
  order: 2
---

[`opentofu/aws`](../../../opentofu/aws) is one flat module: the VPC, the EKS
cluster, its bootstrap nodes, the log groups, and the identities nothing in
the cluster can create. It provisions nothing that needs a pod to run except
the bootstrap node group, and that group is `ACTIVE` only once Cilium runs on
its nodes, so the module does not converge alone: the root
[`opentofu/clusters/aws`](../../../opentofu/clusters/aws) applies it with the
bootstrap module, which installs Cilium beside the group.

## What is decided for you

Enforced means there is no variable; default means a variable can change it.

| Position | | Decision |
| --- | --- | --- |
| EKS Standard; no `compute_config`, no Auto Mode | enforced | [AWS-01](../../decisions/aws.md#aws-01-eks-standard-not-auto-mode) |
| Created with `bootstrap_self_managed_addons = false`: no VPC CNI, kube-proxy or CoreDNS; no EKS add-on in this module | enforced | [AWS-02](../../decisions/aws.md#aws-02-vpc-cni-and-kube-proxy-refused-aws-only-add-ons-stay-eks-add-ons) |
| Pod Identity only; no IAM OIDC provider | enforced | [AWS-03](../../decisions/aws.md#aws-03-pod-identity-not-irsa) |
| `force_update_version = false` | default | [AWS-04](../../decisions/aws.md#aws-04-upgrade-insights-as-a-pipeline-pre-check) |
| Secrets envelope-encrypted with a KMS key the module creates, with rotation | default (`secrets_encryption_enabled`, `secrets_encryption_kms_key_arn`) | [AWS-10](../../decisions/aws.md#aws-10-secrets-encrypted-with-kms-by-default) |
| Public endpoint restricted by CIDR, private endpoint on; `0.0.0.0/0` refused | enforced | [AWS-11](../../decisions/aws.md#aws-11-public-api-endpoint-restricted-by-cidr-private-access-on) |
| A public and a private subnet per AZ, at least two AZs, no all-public layout | enforced | [AWS-12](../../decisions/aws.md#aws-12-reference-network-public-and-private-per-az) |
| A NAT Gateway and a private route table per AZ | default (`create_nat_gateway`, only with `create_vpc = false`) | [AWS-12](../../decisions/aws.md#aws-12-reference-network-public-and-private-per-az) |
| S3 gateway endpoint; `ecr.api`, `ecr.dkr`, `sts`, `ec2`, `logs` interface endpoints | enforced on a VPC the module creates | [AWS-12](../../decisions/aws.md#aws-12-reference-network-public-and-private-per-az) |
| `upgrade_policy.support_type = "STANDARD"` | enforced | [AWS-15](../../decisions/aws.md#aws-15-no-extended-support) |
| Both log groups created by the module, 90-day retention, one customer-managed KMS key | default (`log_retention_days`) | [AWS-16](../../decisions/aws.md#aws-16-the-account-keeps-custody-of-the-logs) |
| All five control-plane log types | default (`cluster_log_types`) | [AWS-16](../../decisions/aws.md#aws-16-the-account-keeps-custody-of-the-logs) |
| VPC flow logs, all traffic, ten-minute aggregation | default (`vpc_flow_logs_enabled`) | [AWS-16](../../decisions/aws.md#aws-16-the-account-keeps-custody-of-the-logs) |
| Bootstrap node group: two nodes, Spot over six 4 vCPU Graviton families, untainted, not autoscaled | default (`bootstrap_node_*`) | [AWS-17](../../decisions/aws.md#aws-17-a-bootstrap-node-group-of-two-spot-nodes) |
| Bootstrap nodes: AL2023, IMDSv2 with a hop limit of 1, 20 GiB encrypted gp3, private subnets, one node unavailable at a time | enforced | [AWS-17](../../decisions/aws.md#aws-17-a-bootstrap-node-group-of-two-spot-nodes) |
| Crossplane's role, Pod Identity association and permissions boundary, only when `crossplane` is set | default (`crossplane = null`) | [AWS-18](../../decisions/aws.md#aws-18-crossplanes-identity-and-its-permissions-boundary-in-the-foundations) |

Plain engineering, with no decision behind it:

- `vpc_cidr` defaults to `10.0.0.0/16`, split into one equal block per subnet.
- `access_config.authentication_mode = "API"`: access entries, not the
  legacy `aws-auth` ConfigMap.
- `access_config.bootstrap_cluster_creator_admin_permissions = true`, set
  explicitly (see [Measured](#measured)). AWS accepts it only at creation:
  changing it replaces the cluster.
- The bootstrap nodes' role carries what the kubelet needs
  (`AmazonEKSWorkerNodePolicy`), ECR pull (the three actions of
  `AmazonEC2ContainerRegistryPullOnly`, inline), and the Cilium operator's
  ENI policy, because the operator runs `hostNetwork` on these nodes. No
  `AmazonEKS_CNI_Policy`: there is no VPC CNI.
- Subnet tags `kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb` and
  `kubernetes.io/cluster/<name> = owned`, which load balancer and node
  provisioners use to discover subnets.
- Every resource carries `owner`, `environment` and `socle-version`, plus
  `additional_tags`.

## What is deliberately absent

An option in the interface is an option the socle supports and tests, so
these are refusals, not gaps:

- **IPv6** ([AWS-06](../../decisions/aws.md#aws-06-ipv6-refused)) and
  **security groups for pods** ([AWS-07](../../decisions/aws.md#aws-07-security-groups-for-pods-refused)).
- **EKS add-ons.** The bootstrap module creates them once Cilium runs
  ([AWS-02](../../decisions/aws.md#aws-02-vpc-cni-and-kube-proxy-refused-aws-only-add-ons-stay-eks-add-ons)).
- **Load balancers.** The two shared Gateways get NLBs from EKS's in-tree
  service controller; this module creates only the ACM certificate they
  terminate TLS with, when `gateway_certificate` is set
  ([GATEWAY-API-02](../../decisions/gateway-api.md#gateway-api-02-shared-public-and-private-gateways-on-cilium)).
- **IRSA**, or a toggle for it. The OIDC issuer URL is an output, unused by
  the socle.
- **Workload identities other than Crossplane's.** Each catalog module
  declares its own, which Crossplane creates under `/socle/<cluster>/`
  ([SOCLE-04](../../decisions/socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)).
  The CSI drivers' roles are the bootstrap module's, beside their add-ons.
- **Fargate profiles and Karpenter.** Karpenter is to be a catalog module
  ([#53](https://github.com/do-now-io/socle/issues/53)).
- **GuardDuty** ([AWS-14](../../decisions/aws.md#aws-14-guardduty-is-the-account-owners)).
- **A DynamoDB gateway endpoint.** No socle component uses DynamoDB.
- **A region variable.** The region is the provider's.
- **Any credential as an input.** The providers use the ambient credentials;
  the module issues no key.

## Measured

- **2026-09-14, a real EKS cluster in the sandbox account, aws provider 6.x:** with
  `bootstrap_cluster_creator_admin_permissions` left unset, the apply created
  one access entry, for EKS's own service role, and none for the principal
  that applied; `kubectl` was refused credentials. Set to `true`, the principal gets cluster-admin, which is
  what lets the same apply install Cilium and Flux.
- **2026-09-14, a real EKS cluster:** a refresh after the first apply showed
  no drift.

## Reference

::include{file="opentofu/aws/README.md" section="tf-docs"}
