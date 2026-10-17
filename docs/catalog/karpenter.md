---
title: karpenter
description: Nodes for your workloads on aws — launched for what is Pending, Spot and Graviton first, removed when empty or under-used.
category: autoscaling
requires:
  - module: crossplane
    clouds: [aws]
    why: "the controller's IAM role and its interruption queue are Crossplane managed resources"
---

Karpenter launches the EC2 nodes your pods need and removes those they no
longer use, in two pools: **private**, where a pod goes by default, its
egress through the NAT Gateway; **public**, for workloads costly in network
traffic that ask for it, their egress straight through the Internet Gateway,
with no NAT Gateway to pay. Without the module, a socle cluster on aws has
only its two bootstrap nodes, sized for the socle, not for your workloads.
**Off by default**; **aws only**: on gcp, GKE Autopilot already provisions a
node for every pod.

## Getting started

Allow its services in the foundations, then turn it on with Crossplane:

```hcl
aws = {
  crossplane = { allowed_services = ["ec2", "ssm", "pricing", "sqs", "eks"] }
}
```

```hcl kube-start="karpenter"
kube = {
  crossplane = { enabled = true }
  karpenter = {
    enabled      = true
    private_pool = { cpu = 64, memory = "256Gi" }
  }
}
```

Then `kubectl get nodepools` shows `private` and `public` `Ready`, and a pod
that fits on no node gets one within a minute: `kubectl get nodeclaims`
shows it. A workload asks for the public pool with both of these in its pod
template:

```yaml
nodeSelector:
  socle.do-now.io/node-pool: public
tolerations:
  - key: socle.do-now.io/node-pool
    value: public
    effect: NoSchedule
```

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on or off. |
| `private_pool` | see below | The private NodePool, where a pod goes by default. |
| `public_pool` | see below | The public NodePool, for the pods that tolerate it. |
| `<pool>.capacity_types` | `["spot", "on-demand"]` | What the pool may launch. Karpenter takes the cheapest that fits: Spot first. |
| `<pool>.architectures` | `["arm64", "amd64"]` | Graviton and x86; Graviton is cheaper, so it comes first. |
| `<pool>.cpu` | `32` | vCPU of all its nodes together: the ceiling. |
| `<pool>.memory` | `"128Gi"` | Memory of all its nodes together. |
| `<pool>.consolidate_after` | `"1m"` | How long a node stays empty or under-used before it goes. |
| `<pool>.ami` | `"al2023@latest"` | The AL2023 AMI: `latest` follows each release, `al2023@v<YYYYMMDD>` pins one. |
| `values` | `{}` | Any [`karpenter` chart](https://gallery.ecr.aws/karpenter/karpenter) value; yours win. |
| `values_secret` | `""` | A Secret in `karpenter` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

`tofu plan` refuses the module without Crossplane or a region, a capacity
type or architecture Karpenter does not know, a limit that is not a
quantity, an AMI outside AL2023, and a `controller.env` entry named like a
credential.

### Every setting

```hcl kube-full="karpenter"
kube = {
  karpenter = {
    enabled = false # off by default; needs crossplane

    # The private NodePool, where a pod goes by default: private subnets,
    # egress through the NAT Gateway.
    private_pool = {
      capacity_types    = ["spot", "on-demand"] # "spot", "on-demand"
      architectures     = ["arm64", "amd64"]    # kubernetes.io/arch values
      cpu               = 32                    # vCPU, all nodes together
      memory            = "128Gi"               # all nodes together
      consolidate_after = "1m"                  # empty or under-used this long, the node goes
      ami               = "al2023@latest"       # or al2023@v20261001
    }

    # The public NodePool, tainted: public subnets, a public IP per node,
    # egress through the Internet Gateway. The same keys.
    public_pool = {
      capacity_types    = ["spot", "on-demand"]
      architectures     = ["arm64", "amd64"]
      cpu               = 32
      memory            = "128Gi"
      consolidate_after = "1m"
      ami               = "al2023@latest"
    }

    # Any value of the karpenter chart 1.15.0; yours win over the socle's.
    values = {
      logLevel = "debug"
      settings = { featureGates = { spotToSpotConsolidation = true } }
    }

    # A Secret you create in karpenter, whose values.yaml key holds chart
    # values that must not reach the OpenTofu state, such as a
    # controller.env proxy URL with a password in it.
    values_secret = "karpenter-values"
  }
}
```

## Good to know

- **Five services in `aws.crossplane.allowed_services`**: `ec2`, `ssm`,
  `pricing`, `sqs`, `eks`. The plan cannot see them from the bootstrap; the
  aws root warns when one is missing, and the controller is otherwise refused
  by IAM, the reason in its logs.
- **An x86-only image needs a `nodeSelector`**: `kubernetes.io/arch: amd64`.
  Without one, Karpenter may place the pod on Graviton, cheaper, where it
  fails with `exec format error`. The socle's own images run on both.
- **Your nodes are the bootstrap nodes' peers**: same role, AL2023, IMDSv2
  on one hop, an encrypted gp3 root volume of 40 GiB. Cilium's agent starts
  first: no pod lands before the node has a network. Private nodes share the
  bootstrap nodes' security group and subnets.
- **The public pool is opt-in, and takes nothing from the internet.** Its
  nodes have a public IP for their egress only: their own security group
  admits the VPC and nothing else, and no load balancer targets them —
  a Gateway's traffic reaches your pods there through the private nodes.
  Put on it what moves a lot of data out (crawlers, media, exports) or in;
  keep the rest private. A pod there leaves with its node's public IP:
  allow-list the addresses of the public nodes, not the NAT Gateway's, at
  any third party that filters by source.
- **Nodes live 30 days at most** (`expireAfter`), then are replaced, on the
  latest AMI with `al2023@latest`; Karpenter replaces a node whose AMI is
  superseded the same way (drift). At most one node in ten is disrupted at a
  time. Guard a pod that must not move with `karpenter.sh/do-not-disrupt:
  "true"`, and give your Deployments a PodDisruptionBudget.
- **Spot reclaims are drained ahead**: EC2's two-minute warning, rebalance
  recommendations and AWS Health maintenance reach Karpenter through its
  queue, and it moves the pods before the node goes.
- **More NodePools are yours to write**: a GPU pool, a tainted pool for one
  team. They reference the socle's `EC2NodeClass` `private` or `public`, or
  one of yours. The socle's pools' limits are yours to raise through
  `private_pool` and `public_pool`.
- **Turning it off removes its nodes first**: the NodePool goes, Karpenter
  drains and terminates its nodes, then the controller goes. Your pods on
  those nodes go Pending. The CRDs, and the NodePools you wrote, stay.
- **Before `tofu destroy`**, turn the module off and wait for
  `kubectl get nodeclaims` to be empty: a destroy that removes the socle
  while Karpenter is draining can leave instances behind, whose network
  interfaces then stop the VPC's deletion. If it did, terminate the
  instances tagged `karpenter.sh/nodepool` and `kubernetes.io/cluster/<cluster>`
  in EC2, then destroy again.
- **Upgrades**: the chart moves with `socle_version`, and Karpenter's CRDs
  with it (created and replaced at install and upgrade).

<details>
<summary>Under the hood</summary>

**Installed**: chart `karpenter` 1.15.0 from `oci://public.ecr.aws/karpenter`,
in `karpenter` (Pod Security `restricted`): the controller, two replicas,
never on a node Karpenter manages, preferably one per bootstrap node and zone;
its CRDs (`NodePool`, `NodeClaim`, `EC2NodeClass`, `NodeOverlay`,
`CapacityBuffer`). Then `EC2NodeClass` and `NodePool` `private` and `public`,
from the `karpenter-nodes` Kustomization. On aws, `Role/karpenter`,
`PodIdentityAssociation/karpenter`, `Queue/karpenter` and five `Rule`s with their
`Target`s.

**What the socle sets**: the cluster's name, its endpoint and service range
from `DescribeCluster` (AL2023 nodes need the range), the interruption queue,
`AWS_REGION` (a pod cannot reach instance metadata on these nodes), requests
with no limit, the scrape annotations. Your `values` are merged over these;
a `controller.env` of yours replaces the socle's, so keep `AWS_REGION` in it.

**The nodes**: both EC2NodeClasses name the instance profile
`<cluster>-bootstrap-node`, which the foundations create for the bootstrap
nodes' role, so Karpenter creates no profile and the node joins through the
access entry EKS made for that role. `private` selects the subnets tagged
`kubernetes.io/cluster/<cluster>: owned` and `kubernetes.io/role/internal-elb`
and the security groups tagged for the cluster — the cluster security group.
`public` selects the subnets tagged `kubernetes.io/role/elb`, the security
group `<cluster>-public-nodes` the foundations create, asks for a public IP,
and has its kubelet register the node labelled
`node.kubernetes.io/exclude-from-external-load-balancers` (an AL2023
`NodeConfig` beside Karpenter's): EKS's load balancer controller opens a
Service's NodePort to `0.0.0.0/0` in the security group of every node it
targets, and does so in the seconds before Karpenter could label the node —
measured on the sandbox. Both NodePools allow families `c`, `m`, `r` of
generation 6 and later, the startup taint `node.cilium.io/agent-not-ready`,
consolidation `WhenEmptyOrUnderutilized`; `public` is tainted
`socle.do-now.io/node-pool=public:NoSchedule`, and each carries the label
`socle.do-now.io/node-pool`. A pod's address is an ENI's secondary one,
which the Internet Gateway never translates: Cilium masquerades what leaves
the VPC to the node's primary address
([AWS-23](../decisions/aws.md#aws-23-public-nodes-their-own-security-group-and-cilium-masquerading-out-of-the-vpc)).
Flux applies a kind named `*Class` before the rest and waits for it: a
change to a pool reaches its NodePool only while its EC2NodeClass is Ready.

**Cloud access**: the role `<cluster>-karpenter`, under `/socle/<cluster>/`
with the foundations' boundary, holds AWS's own controller policy for
Karpenter 1.15.0, minus the instance-profile writes and the zonal-shift read:
EC2 launches, tags and terminations only on what carries this cluster's tag
and a NodePool's; `iam:PassRole` on `<cluster>-bootstrap-node`, to EC2 only;
reads of instance profiles, AMIs, prices, subnets; its own queue. The
boundary allows that one IAM action only when `ec2` is in
`allowed_services`, and only on that role
([AWS-21](../decisions/aws.md#aws-21-the-boundarys-one-iam-exception-the-node-role-passed-to-ec2)).
The queue `<cluster>-karpenter` keeps a message five minutes, encrypted,
HTTPS only, written by EventBridge only; the rules `<cluster>-karpenter-*`
send it Spot interruption warnings, rebalance recommendations, instance state
changes, capacity-reservation interruptions and AWS Health events.

**Ordering**: the role, association and queue are a step of their own,
`cloud`, which aws adds to the module
([`oci/clusters/aws/karpenter/patch.yaml`](../../oci/clusters/aws/karpenter/patch.yaml),
[SOCLE-32](../decisions/socle.md#socle-32-what-only-one-cloud-has-that-cloud-adds-to-the-module-as-steps)):
the module waits for the `crossplane` ResourceSet, the controller starts once
they are Ready (`karpenter-access`), and the NodePool once the controller is.
Removal runs the other way: the NodePool and the EC2NodeClass sit in a Flux
Kustomization, which flux-operator deletes first and waits for, the controller
in the child ResourceSet `karpenter-controller`, deleted after
([KARPENTER-04](../decisions/karpenter.md#karpenter-04-the-nodes-go-before-the-controller)).
flux-operator waits one minute for the first stage: a drain longer than that
is why the module goes off before a destroy.

**Measured** on floci 2.1.0, 2026-10-16: the controller Ready with static
keys, the EC2NodeClasses reconciled against floci's EC2 (no subnet found,
floci's VPC carries no cluster tag). On the aws sandbox (eu-west-3,
2026-10-17, `karpenter-module-eks`): a private node launched in 46 s, Ready
with Cilium 8 s later, consolidated 2 min after its pods went; a pod on a
public node reached the internet with its node's IP, another on a private
node with the NAT Gateway's; a public node never became a load balancer
target, and its NodePort stayed closed from the internet. With the module
on: the controller's access Ready and its Pod Identity check Complete in
14 s; a private node Ready with Cilium in 55 s, a public node and its pod's
egress in 54 s, both consolidated 2 min 21 s after their pods went. Turned
off with a node running: the NodePools went first, the instance was
terminated within a minute, then the controller went; nothing left.

</details>

## Per cloud

| Cloud | |
| --- | --- |
| aws | the module, as above |
| gcp | not offered: GKE Autopilot provisions, sizes and removes a node for every pod itself — the socle's GKE has no node pool to scale ([KARPENTER-05](../decisions/karpenter.md#karpenter-05-aws-only-gke-autopilot-is-its-own-node-autoscaler)) |
| azure, scaleway | not offered: AKS has Node Auto Provisioning, Scaleway its cluster autoscaler, both decided with their foundations |
