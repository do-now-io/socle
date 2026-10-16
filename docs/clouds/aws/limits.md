---
title: Limits
description: What no apply can finish on AWS, the provider limits the socle runs into, and what it does not offer there yet.
sidebar:
  order: 3
---

## What no apply can finish

- **Replacing the cluster** (`cluster_name`, `bootstrap_cluster_creator_admin_permissions`): apply `-target=module.socle.module.foundations` first, then the full apply ([root README](../../../opentofu/clusters/aws/README.md)).
- **Destroying with the API unreachable**: if the runner left `cluster_endpoint_public_access_cidrs`, run `tofu state rm module.socle.module.socle` first.
- **A late control-plane log delivery**: with `cluster_log_types` set, a destroy waits five minutes between the cluster and its log group; EKS's delivery is best effort, and a later one recreates the group ([Uninstall](../../guides/uninstall.md#what-is-left-behind-by-design)).
- **The GuardDuty detector**: the account owner's.
- **The Route 53 zone**: with `gateway_certificate`, the public zone must already exist; the module never creates it.

## Provider limits

- **No IPv6 cluster**: Cilium's ENI IPv6 mode is beta.
- **No Auto Mode, no Fargate**: neither runs Cilium.
- **EKS picks the service CIDR** (`172.20.0.0/16` or `10.100.0.0/16`); no variable for it.
- **The API endpoint is public**, restricted to `cluster_endpoint_public_access_cidrs`, which must include the runner.
- **AWS upgrades the cluster at the end of standard support**, whatever the pipeline did.
- **An existing VPC** (`create_vpc = false`) gets no VPC endpoints and no flow logs.
- **The NLBs' TLS policy is AWS's default**; the socle sets none.
- **Elastic IPs**: one per AZ per cluster, 5 per region by default ([Prerequisites](prerequisites.md#quotas)).

## What the socle does not offer here yet

- **Capacity for workloads**: no Karpenter ([#53](https://github.com/do-now-io/socle/issues/53)); everything runs on the two bootstrap Spot nodes.
- **Backups outside the cluster's account and region** ([velero](../../catalog/velero.md)).
- **The Upgrade Insights pre-check** and **cloud-resource observability**: proposed, not built.
