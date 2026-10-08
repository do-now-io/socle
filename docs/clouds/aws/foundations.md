---
title: Foundations
description: 'The AWS foundations module: what is decided for you, what is deliberately absent, and its full reference.'
sidebar:
  order: 2
---

[`opentofu/aws`](../../../opentofu/aws) builds the VPC, the EKS cluster, its
bootstrap nodes, the log groups and the identities nothing in the cluster can
create. The bootstrap nodes are `ACTIVE` only once Cilium runs on them, so the
root [`opentofu/clusters/aws`](../../../opentofu/clusters/aws) applies this
module together with the bootstrap.

## What is decided for you

*Enforced*: no variable. *Default*: a variable changes it.

| Position | |
| --- | --- |
| EKS Standard, no Auto Mode | enforced |
| No VPC CNI, kube-proxy or CoreDNS add-on | enforced |
| Pod Identity only, no IAM OIDC provider | enforced |
| `force_update_version = false` | default |
| Secrets encrypted with a module KMS key, rotated | default |
| Public endpoint restricted by CIDR (`0.0.0.0/0` refused), private on | enforced |
| A public and a private subnet per AZ, at least two AZs | enforced |
| A NAT Gateway and private route table per AZ | default |
| S3 gateway endpoint; `ecr.api`, `ecr.dkr`, `sts`, `ec2`, `logs` interface endpoints | enforced on a module VPC |
| Standard support only | enforced |
| Log groups owned by the module, 90 days, KMS; VPC flow logs | default |
| Control-plane logs off: CloudWatch bills them by the gigabyte. `cluster_log_types = ["audit", "authenticator"]` when your audit asks for the API server's record | default |
| Two Spot Graviton bootstrap nodes, untainted, not autoscaled | default |
| Bootstrap nodes on AL2023, IMDSv2 hop limit 1, encrypted gp3, private subnets | enforced |
| Crossplane's role and permissions boundary, only when `crossplane` is set | default |

<details>
<summary>Under the hood</summary>

**The variables behind the defaults**: `secrets_encryption_enabled`,
`secrets_encryption_kms_key_arn`, `create_nat_gateway` (only with
`create_vpc = false`), `log_retention_days`, `cluster_log_types`,
`vpc_flow_logs_enabled` (all traffic, ten-minute aggregation),
`bootstrap_node_*` (six 4 vCPU Graviton families, 20 GiB volumes, one node
unavailable at a time), `crossplane = null`.

**Plain engineering, no decision behind it:**

- `vpc_cidr` defaults to `10.0.0.0/16`, split into one equal block per subnet.
- `authentication_mode = "API"`: access entries, not the `aws-auth` ConfigMap.
- `bootstrap_cluster_creator_admin_permissions = true`, set explicitly (see
  [Measured](#measured)). AWS accepts it only at creation.
- The node role carries `AmazonEKSWorkerNodePolicy`, the three actions of
  `AmazonEC2ContainerRegistryPullOnly` inline, and the Cilium operator's ENI
  policy. No `AmazonEKS_CNI_Policy`.
- Subnet tags `kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`
  and `kubernetes.io/cluster/<name> = owned`.
- Every resource carries `owner`, `environment`, `socle-version`, plus
  `additional_tags`.

</details>

## What is deliberately absent

- **IPv6** and
  **security groups for pods**.
- **EKS add-ons**: the bootstrap module creates them once Cilium runs.
- **Load balancers**: EKS's in-tree controller gives the shared Gateways
  their NLBs; this module only creates their ACM certificate.
- **IRSA**: the OIDC issuer URL is an output, unused.
- **Workload identities other than Crossplane's**: each catalog module
  declares its own;
  the CSI drivers' roles are the bootstrap's.
- **Fargate and Karpenter**: Karpenter is to be a catalog module
  ([#53](https://github.com/do-now-io/socle/issues/53)).
- **GuardDuty**.
- **A DynamoDB endpoint, a region variable, any credential as input.**

## Measured

- **2026-09-14, real EKS, aws provider 6.x**: with
  `bootstrap_cluster_creator_admin_permissions` unset, the applying principal
  got no access entry and `kubectl` was refused; set to `true`, it gets
  cluster-admin, which lets the same apply install Cilium and Flux.
- **2026-09-14, real EKS**: a refresh after the first apply showed no drift.

## Reference

::include{file="opentofu/aws/README.md" section="tf-docs"}
