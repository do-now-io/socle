---
title: Prerequisites
description: The AWS account, the permissions for the apply, the state bucket and the tooling the socle expects.
sidebar:
  order: 1
---

What must exist before `tofu apply` runs
[`opentofu/clusters/aws`](../../../opentofu/clusters/aws). The socle creates
none of it.

## Account

- An AWS account and a region. The region is the root's `aws.region`; the
  foundations module reads it from the provider.
- The account may hold several clusters. Every name the module creates
  carries `cluster_name`, and IAM names are unique per account, so two
  clusters in one account need two names, even in different regions.
- If the account has never run EKS, EC2 Spot or Auto Scaling, the first
  apply creates their service-linked roles; the principal needs
  `iam:CreateServiceLinkedRole` for that.
- With `gateway_certificate`: a **public** Route 53 hosted zone in the same
  account, named after the domain or a parent of it. ACM validates the
  certificate through it.
- GuardDuty, if wanted, is turned on by the account owner. The socle creates
  no detector ([AWS-14](../../decisions/aws.md#aws-14-guardduty-is-the-account-owners)).

## Permissions for the apply

The principal that applies creates the resources below. Scope its policy to
these services rather than attaching `AdministratorAccess`.

| Service | What the apply creates |
| --- | --- |
| EC2 | VPC, subnets, route tables, internet gateway, Elastic IPs, NAT Gateways, VPC endpoints, the endpoints' security group, flow logs, the bootstrap nodes' launch template |
| EKS | the cluster, the bootstrap node group, the add-ons (`CreateAddon`, `DescribeAddon`, `UpdateAddon`, `DeleteAddon`), Pod Identity associations, tags |
| IAM | roles, inline role policies, managed policy attachments; `iam:CreatePolicy` for the Crossplane permissions boundary; `iam:PassRole` for the cluster role (to EKS), the node role (to EKS), the flow logs role (to VPC flow logs), and the Crossplane and CSI drivers' roles (to `pods.eks.amazonaws.com`) |
| KMS | two keys (Secrets, logs) with rotation and a key policy; `kms:DescribeKey` on the logs key, without which `CreateLogGroup` with a `kmsKeyId` fails with `AccessDeniedException` |
| CloudWatch Logs | the control-plane and flow-log groups, their retention and their KMS key |
| ACM, Route 53 | with `gateway_certificate` only: the certificate (`RequestCertificate`, `DescribeCertificate`, `ListTagsForCertificate`), the zone lookup (`ListHostedZones`, `GetHostedZone`) and the validation records (`ChangeResourceRecordSets`, `GetChange`, `ListResourceRecordSets`) |
| STS | `GetCallerIdentity`, the providers' own check and the account ID the module reads |

Two more conditions, both about reaching the cluster in the same apply:

- **The principal is the cluster's first admin.** The cluster is created with
  `bootstrap_cluster_creator_admin_permissions = true`, so the principal that
  creates it gets cluster-admin through an EKS access entry. A later apply by
  another principal needs its own access entry.
- **The runner's public IP is in `cluster_endpoint_public_access_cidrs`.**
  The helm provider talks to the API server's public endpoint during the
  apply.

Credentials come from the provider's ambient chain: a profile or
environment variables on a workstation, a role assumed through OIDC
federation in CI. The module takes no credential as input and needs no IAM
access key.

## State

An S3 bucket in the client's account, created before the first `tofu init`,
with versioning on, Block Public Access on and default encryption. OpenTofu
locks state in S3 with conditional writes (`use_lockfile = true`); no
DynamoDB table is needed. One key per cluster:

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

The state holds every attribute of every resource. Keep the bucket apart
from application data, and expire only noncurrent versions.

```sh
aws s3api create-bucket --bucket acme-tofu-state --region eu-west-3 \
  --create-bucket-configuration LocationConstraint=eu-west-3
aws s3api put-bucket-versioning --bucket acme-tofu-state \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket acme-tofu-state \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

New S3 buckets are encrypted with SSE-S3 by default.

## Tooling

- OpenTofu 1.10 or later: the modules are pulled as OCI artifacts
  (`oci://`), which needs 1.10.
- The AWS CLI on the machine that applies: the helm provider gets its token
  from `aws eks get-token`, with the same credentials as the aws provider.
- `kubectl`, to read the result.
- While `ghcr.io/do-now-io/socle/opentofu-modules` is private, `tofu init`
  needs a GHCR login with `read:packages` (for example `docker login
  ghcr.io`, whose credentials OpenTofu reads). The Flux package the cluster
  pulls is public ([distribution](../../architecture/distribution.md)).
- `cosign`, to verify the modules package before `tofu init`: OpenTofu does
  not verify OCI signatures.

## Quotas

Per cluster, with the defaults: one VPC, one Elastic IP and one NAT Gateway
per AZ, five interface endpoints, two EC2 instances on Spot. Elastic IPs are
the first default quota to run out: 5 per region, so a third cluster on two
AZs, or a second on three, needs an increase. VPCs are 5 per region by
default.
