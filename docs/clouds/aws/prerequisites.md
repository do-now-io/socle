---
title: Prerequisites
description: The AWS account, the permissions for the apply, the state bucket and the tooling the socle expects.
sidebar:
  order: 1
---

Tick these before `tofu apply` runs
[`opentofu/clusters/aws`](../../../opentofu/clusters/aws). The socle creates
none of it.

## Account

- [ ] An AWS account and a region (the root's `aws.region`).
- [ ] A `cluster_name` unique in the account: IAM names are per account, even
  across regions.
- [ ] `iam:CreateServiceLinkedRole`, if the account has never run EKS, EC2
  Spot or Auto Scaling.
- [ ] With `gateway_certificate`: a **public** Route 53 hosted zone in the same
  account, for the domain or a parent of it.
- [ ] GuardDuty, if wanted, turned on by the account owner.

## Permissions for the apply

- [ ] A principal with a policy scoped to the services below, not
  `AdministratorAccess`. Credentials come from the ambient chain: a profile
  locally, an OIDC role in CI; no IAM access key.
- [ ] The same principal creates the cluster: it becomes its first admin.
  Another principal later needs its own EKS access entry.
- [ ] The runner's public IP in `cluster_endpoint_public_access_cidrs`: Helm
  talks to the public endpoint during the apply.

| Service | What the apply needs |
| --- | --- |
| EC2 | VPC, subnets, routes, internet gateway, Elastic IPs, NAT Gateways, VPC endpoints and their security group, flow logs, the launch template |
| EKS | cluster, node group, add-ons (`CreateAddon`, `DescribeAddon`, `UpdateAddon`, `DeleteAddon`), Pod Identity associations, tags |
| IAM | roles, inline policies, attachments; `iam:CreatePolicy` for the Crossplane boundary; `iam:PassRole` (see below) |
| KMS | two keys with rotation and key policy; `kms:DescribeKey` on the logs key |
| CloudWatch Logs | the control-plane and flow-log groups, retention, KMS key |
| ACM, Route 53 | with `gateway_certificate` only (see below) |
| STS | `GetCallerIdentity` |

<details>
<summary>Under the hood</summary>

- `iam:PassRole`: the cluster and node roles to EKS, the flow logs role to
  VPC flow logs, the Crossplane and CSI drivers' roles to
  `pods.eks.amazonaws.com`.
- Without `kms:DescribeKey` on the logs key, `CreateLogGroup` with a
  `kmsKeyId` fails with `AccessDeniedException`.
- ACM: `RequestCertificate`, `DescribeCertificate`, `ListTagsForCertificate`.
  Route 53: `ListHostedZones`, `GetHostedZone`, `ChangeResourceRecordSets`,
  `GetChange`, `ListResourceRecordSets`.
- The first admin comes from
  `bootstrap_cluster_creator_admin_permissions = true`, through an EKS access
  entry.

</details>

## State

- [ ] An S3 bucket, versioned, Block Public Access on, encrypted (SSE-S3 is
  the default), apart from application data. No DynamoDB table:
  `use_lockfile = true` locks.

```sh
aws s3api create-bucket --bucket acme-tofu-state --region eu-west-3 \
  --create-bucket-configuration LocationConstraint=eu-west-3
aws s3api put-bucket-versioning --bucket acme-tofu-state \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket acme-tofu-state \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

One key per cluster; expire only noncurrent versions:

```hcl
terraform {
  backend "s3" {
    bucket       = "acme-tofu-state"
    key          = "socle/aws/acme-prod.tfstate"
    region       = "eu-west-3"
    use_lockfile = true
  }
}
```

## Tooling

- [ ] OpenTofu 1.10 or later (OCI module sources).
- [ ] The AWS CLI: the helm provider gets its token from `aws eks get-token`.
- [ ] `kubectl`.
- [ ] `cosign`, to verify the modules package: OpenTofu does not verify OCI
  signatures.

## Quotas

- [ ] Elastic IPs: one per AZ per cluster, against a default of 5 per region.
  A third cluster on two AZs, or a second on three, needs an increase.
- [ ] VPCs: one per cluster, 5 per region by default.
- [ ] Also per cluster: one NAT Gateway per AZ, five interface endpoints, two
  Spot instances.
