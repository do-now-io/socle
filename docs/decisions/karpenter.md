---
title: karpenter decisions
description: The decisions behind the karpenter module, one per section, each with its status.
sidebar:
  order: 10
---

Karpenter is the socle's node autoscaler on AWS, implementing
[AWS-01](aws.md#aws-01-eks-standard-not-auto-mode): EKS Standard with a
self-hosted Karpenter. The decisions that shape the rest are the nodes'
identity ([KARPENTER-02](#karpenter-02-the-nodes-are-the-bootstrap-nodes-peers))
and the order in which it is removed
([KARPENTER-04](#karpenter-04-the-nodes-go-before-the-controller)).

## KARPENTER-01: AWS's controller policy, without instance-profile writes

**accepted** · 2026-10-16 · [`oci/clusters/aws/karpenter/patch.yaml`](../../oci/clusters/aws/karpenter/patch.yaml)

**Decision.** The controller's role, `<cluster>-karpenter`, is a Crossplane
`Role` under `/socle/<cluster>/` with the foundations' boundary, bound by Pod
Identity to `karpenter/karpenter`. Its inline policy is AWS's own controller
policy for Karpenter 1.15.0, statement for statement, minus
`iam:CreateInstanceProfile`, `TagInstanceProfile`, `AddRoleToInstanceProfile`,
`RemoveRoleFromInstanceProfile`, `DeleteInstanceProfile` and the zonal-shift
read; `iam:PassRole` names the bootstrap nodes' role only.

**Context.** The issue's blocking question: the boundary denies `iam:*`
([AWS-18](aws.md#aws-18-crossplanes-identity-and-its-permissions-boundary-in-the-foundations)),
and Karpenter needs `iam:PassRole` and, when it manages profiles, profile
writes. OpenTofu never creates a role for a module
([SOCLE-04](socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)).
Every EC2 write in AWS's policy is already conditioned on the cluster's tag
and a NodePool's.

**Consequences.** The boundary must allow `ec2`, `ssm`, `pricing`, `sqs` and
`eks`; the aws root warns when one is missing. Its one IAM exception is
[AWS-20](aws.md#aws-20-the-boundarys-one-iam-exception-the-node-role-passed-to-ec2).
`eks:DescribeCluster` stays: AL2023's nodeadm needs the service range, which
only it gives Karpenter. Zonal shift stays off.

**Sources.** [Karpenter 1.15.0 getting started, CloudFormation](https://github.com/aws/karpenter-provider-aws/blob/v1.15.0/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml) · `pkg/providers/instanceprofile` and `pkg/controllers/nodeclass` at v1.15.0 · #53.

## KARPENTER-02: The nodes are the bootstrap nodes' peers

**accepted** · 2026-10-16 · [`oci/catalog/karpenter/nodes/ec2nodeclass.yaml`](../../oci/catalog/karpenter/nodes/ec2nodeclass.yaml), [`opentofu/aws/nodes.tf`](../../opentofu/aws/nodes.tf)

**Decision.** `EC2NodeClass/default` names the instance profile
`<cluster>-bootstrap-node` (`spec.instanceProfile`), selects the subnets
tagged `kubernetes.io/cluster/<cluster>: owned` and
`kubernetes.io/role/internal-elb: "1"` and the security groups tagged
`kubernetes.io/cluster/<cluster>: owned`, runs AL2023 with IMDSv2 on one hop
and an encrypted gp3 root volume.

**Context.** The issue asked for no new foundations tag. The foundations tag
the private subnets for internal load balancers and the cluster; EKS tags the
cluster security group, the bootstrap nodes' one, for the cluster, and no
other security group in the VPC carries that tag. The bootstrap nodes' role
already holds what a node needs, Cilium's ENI calls included, and EKS made
its access entry.

**Consequences.** No second identity to keep in step: Cilium's operator may
run on any node. A client attaching an existing VPC tags its private subnets
the same way, as the Gateways' load balancers already require. Pods do not
reach instance metadata, so the controller is given `AWS_REGION`. Flux
applies a kind named `*Class` first and waits for it to be Ready, whatever
the Kustomization's `wait` (fluxcd/pkg `ssa`, `ApplyAllStaged`): a change to
the NodePool waits on a Ready EC2NodeClass, which floci's never is.

**Sources.** [Karpenter NodeClasses](https://karpenter.sh/docs/concepts/nodeclasses/) · [EKS cluster security group](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html) · [AWS-17](aws.md#aws-17-a-bootstrap-node-group-of-two-spot-nodes).

## KARPENTER-03: One default NodePool, its shape typed in `node_pool`

**accepted** · 2026-10-16 · [`oci/catalog/karpenter/nodes/nodepool.yaml`](../../oci/catalog/karpenter/nodes/nodepool.yaml), [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf), [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf)

**Decision.** The socle renders `NodePool/default`: Spot and on demand,
arm64 and amd64, families `c`, `m`, `r` of generation 6 and later, 32 vCPU and
128Gi in all, `WhenEmptyOrUnderutilized` after one minute, nodes expiring
after 30 days, Cilium's startup taint `node.cilium.io/agent-not-ready`.
`kube.karpenter.node_pool` types its capacity types, architectures, limits,
consolidation delay and AMI alias, each validated at plan; any other NodePool
is the client's to write.

**Context.** The issue asked for Spot and Graviton first, like the bootstrap
group, limits, a consolidation policy, and whether `values` or a typed
attribute carries it. The NodePool is not a chart value: `values` cannot
reach it. Karpenter launches the cheapest offering that fits, so allowing
both capacity types and both architectures is Spot and Graviton first.
Cilium's agent removes its startup taint once it runs, which keeps pods off a
node without a network.

**Consequences.** An x86-only image needs a `nodeSelector` on
`kubernetes.io/arch`. A limit reached leaves pods Pending, with an alert
(`KarpenterNodePoolNearLimit`). `al2023@latest` moves nodes onto each new
AMI by drift; a client pins one with `al2023@v<date>`.

**Sources.** [Karpenter NodePools](https://karpenter.sh/docs/concepts/nodepools/) · [Cilium, Karpenter's startup taint](https://docs.cilium.io/en/stable/installation/taints/) · #53.

## KARPENTER-04: The nodes go before the controller

**accepted** · 2026-10-16 · [`oci/catalog/karpenter/resourceset.yaml`](../../oci/catalog/karpenter/resourceset.yaml)

**Decision.** The NodePool and the EC2NodeClass are applied by a Flux
Kustomization, `karpenter-nodes`, with `deletionPolicy: WaitForTermination`;
the controller's HelmRelease is the one object of a child ResourceSet,
`karpenter-controller`.

**Context.** The nodes Karpenter launched are in no OpenTofu state, and only
Karpenter terminates them, when their NodePool goes, while it runs. A
`ResourceSet` deletes what it rendered in two stages: Flux objects first,
waiting up to a minute for them, then the rest (flux-operator 0.60.0,
`deleteAllStaged`). A NodePool beside the controller's HelmRelease would go
after it, and its nodes, and their network interfaces, would outlive the
cluster and stop the VPC's deletion.

**Consequences.** Turning the module off and destroying the socle remove the
nodes first. A drain that takes more than flux-operator's minute (a
PodDisruptionBudget holding) lets the controller go before the last node:
hence the rule to turn the module off and wait for `kubectl get nodeclaims` to
be empty before `tofu destroy`, and the EC2 clean-up in the module's page.

**Sources.** flux-operator v0.60.0 `internal/controller/resourceset_controller.go` · [Karpenter, uninstall](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/#delete-the-cluster) · #53.

## KARPENTER-05: aws only; GKE Autopilot is its own node autoscaler

**accepted** · 2026-10-16 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf) (`catalog_clouds`)

**Decision.** No karpenter module on gcp, and none in its place: the socle's
GKE is Autopilot, which provisions, sizes and removes nodes for the pods it
schedules.

**Context.** Karpenter has providers for AWS and Azure only. On Autopilot
there is no node pool to scale and no node auto-provisioning to turn on:
Google operates both
([GCP-01](gcp.md#gcp-01-autopilot-only-no-cluster-mode-option)). A pod's requests are what Autopilot bills and sizes, and
Spot is a `nodeSelector` (`cloud.google.com/gke-spot`) or a ComputeClass the
workload asks for.

**Consequences.** On gcp a client sizes requests and chooses Spot per
workload; nothing in the catalog sets a node shape. A ComputeClass catalog
module would be a decision of its own, not this one.

**Sources.** [GKE Autopilot overview](https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview) · [Autopilot Spot Pods](https://cloud.google.com/kubernetes-engine/docs/how-to/autopilot-spot-pods) · [Karpenter providers](https://karpenter.sh/docs/).
