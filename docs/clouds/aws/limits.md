---
title: Limits
description: What no apply can finish on AWS, the provider limits the socle runs into, and what it does not offer there yet.
sidebar:
  order: 3
---

## What no apply can finish

- **Replacing the cluster.** A change AWS accepts only at creation, such as
  `cluster_name` or `bootstrap_cluster_creator_admin_permissions`, replaces
  the cluster. The endpoint is then unknown
  at plan and the helm provider cannot refresh its releases: apply
  `-target=module.foundations` first, then the full apply
  ([`opentofu/clusters/aws`](../../../opentofu/clusters/aws/README.md)).
- **Destroying when the API is unreachable.** The destroy deletes the Helm
  releases before the cluster, which needs the API. If the runner is no
  longer in `cluster_endpoint_public_access_cidrs`, run
  `tofu state rm module.socle` first.
- **The GuardDuty detector.** It is per account and region; the account
  owner turns it on
  ([AWS-14](../../decisions/aws.md#aws-14-guardduty-is-the-account-owners)).
- **The Route 53 zone.** With `gateway_certificate`, the public hosted zone
  must already exist; the module looks it up by name and never creates it.

## Provider limits

- **No IPv6 cluster**: Cilium's ENI IPv6 mode is beta
  ([AWS-06](../../decisions/aws.md#aws-06-ipv6-refused)).
- **No Auto Mode, no Fargate**: Auto Mode refuses any CNI but the VPC CNI,
  and Fargate runs no DaemonSet, so no Cilium agent
  ([AWS-01](../../decisions/aws.md#aws-01-eks-standard-not-auto-mode)).
- **EKS picks the service CIDR**: `172.20.0.0/16` or `10.100.0.0/16`,
  depending on the VPC CIDR. The module reads it back for CoreDNS and has no
  variable for it.
- **The API endpoint is public**, restricted to
  `cluster_endpoint_public_access_cidrs`, which is required and refuses
  `0.0.0.0/0`. The runner that applies must be inside it
  ([AWS-11](../../decisions/aws.md#aws-11-public-api-endpoint-restricted-by-cidr-private-access-on)).
- **AWS upgrades the cluster at the end of standard support**
  (`support_type = "STANDARD"`), whatever the socle's pipeline did
  ([AWS-15](../../decisions/aws.md#aws-15-no-extended-support)).
- **An existing VPC** (`create_vpc = false`) gets no VPC endpoints and no
  flow logs from the module: it manages neither the VPC nor its route
  tables.
- **The NLBs' TLS policy is AWS's default**: the in-tree service controller
  sets none, and the socle has not chosen a stricter one.
- **Quotas**: one Elastic IP and one NAT Gateway per AZ per cluster, against
  a default of 5 Elastic IPs per region
  ([Prerequisites](prerequisites.md#quotas)).

## What the socle does not offer here yet

- **Capacity for workloads.** Karpenter is not built
  ([#53](https://github.com/do-now-io/socle/issues/53)). Every workload runs
  on the two bootstrap Spot nodes, which are sized for the socle, not for an
  application.
- **A default StorageClass.** The EBS CSI driver is installed, but no
  StorageClass is created and EKS marks none as default, so a claim with no
  class stays `Pending`. Either keep `storage_size = ""` on
  `victoria_metrics`, `victoria_logs` and `victoria_traces` (an `emptyDir`,
  lost when the pod moves, as `prod.tfvars.example` does), or create a
  StorageClass with provisioner `ebs.csi.aws.com` and the annotation
  `storageclass.kubernetes.io/is-default-class: "true"` before the catalog
  needs it.
- **Backups outside the cluster's account and region.** Velero snapshots EBS
  volumes through CSI (EFS through a file-level copy); the snapshots and the
  bucket stay in the cluster's account and region
  ([velero](../../catalog/velero.md)).
- **The Upgrade Insights pre-check**
  ([AWS-04](../../decisions/aws.md#aws-04-upgrade-insights-as-a-pipeline-pre-check))
  and **cloud-resource observability**
  ([AWS-13](../../decisions/aws.md#aws-13-cloud-resources-observed-from-a-central-cluster)):
  proposed, not built.
