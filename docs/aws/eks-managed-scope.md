# EKS managed scope: add-ons, upgrades, identity

Socle is a multi-cloud Kubernetes factory. [Analysis 1](eks-cluster-mode.md) settled how AWS clusters get their compute provisioned: EKS Standard, self-hosted Karpenter, Cilium, no Auto Mode. This document covers who owns each data-plane component, how workloads get AWS permissions, and how clusters get upgraded without ever paying Extended Support.

Arbitration rule: reliable provider ops at a reasonable surcharge → delegated. Cheap to industrialise → factory.

## 1. Add-ons: EKS-managed or GitOps?

| Component          | Position           | Who operates                     | Notes                                                                   |
| ------------------- | ------------------- | --------------------------------- | ------------------------------------------------------------------------ |
| VPC CNI            | **Refused**        | Factory (neutralisation)         | Replaced by Cilium; Cilium's documented pattern, not the bootstrap flag |
| kube-proxy         | **Refused**        | Factory (neutralisation)         | Replaced by Cilium `kubeProxyReplacement`                               |
| CoreDNS            | **Delegated**      | AWS packages / factory triggers  | NodeLocal DNSCache via `configuration_values` if needed                |
| EBS CSI            | **Delegated**      | AWS packages / factory triggers  | Identity via `aws_eks_addon`'s own `pod_identity_association`           |
| EFS CSI            | **Catalog option** | AWS packages / factory triggers  | RWX only; node component may need a separate association               |
| Pod Identity Agent | **Delegated**      | AWS packages / factory triggers  | Prerequisite for all workload identity                                 |

**Decision.** AWS-only components stay EKS add-ons; anything with a multi-cloud equivalent is the socle's.

- EBS CSI, EFS CSI, Pod Identity Agent: no cross-cloud equivalent to keep uniform.
- CoreDNS: the add-on already tracks the Kubernetes version AWS validated it against — redoing that buys nothing.
- AWS never auto-updates an add-on — the trigger is always ours, so versions are pinned in the module, never resolved via `most_recent`.

**Decision.** VPC CNI / kube-proxy excluded via Cilium's documented delete-and-taint pattern.

**Decision.** NodeLocal DNSCache, if ever needed, goes through the add-on's `configurationValues` — never a Flux patch, never a CoreDNS migration to the socle.

## 2. Identity: Pod Identity or IRSA?

**Decision.** Pod Identity, exclusively. IRSA absent from the module.

- AWS's own recommendation; its EC2-only restriction matches our EC2-only scope exactly.
- Verified per component: Crossplane, LB controller, both CSI drivers, Karpenter all support it.

Note: the OIDC issuer URL is still exposed as an output (checklist requirement) — not IRSA, provisions nothing.

## 3. Control plane version policy

**Decision.** Policy ceiling n-1, socle compatibility floor n-2, two decoupled Kargo pipelines (socle release / Kubernetes version), support-margin floor the client cannot lower.

- No release channel on EKS (unlike GKE) — the version bump is 100% ours to trigger.
- Standard support 14 months; extended +12 months at a $0.50/hr surcharge, 6x the $0.10 base rate.
- ~3.5 versions in standard support at once (3 releases/yr over 14mo support): n-1 leaves ~10 months margin, n-2 ~6, n-3 ~2. n-2 is the widest range still fully in standard support; n-1 is the tightest safe ceiling.
- Decoupled pipelines so a socle hotfix reaches a client frozen on Kubernetes version. Cost: we own the compatibility matrix — a bidirectional guard is mandatory, declared inside the socle artifact, read by both pipelines. Kubernetes' own skew policy forces control-plane-before-data-plane ordering on top.
- Kargo's native gates don't fit: `verification` runs after promotion (too late), `freightCreationCriteria` is global (compatibility is per-cluster).
- Client-declared maintenance windows/freezes are enforced by our own scheduler, not the AWS API — and not by Kargo either: `PromotionWindow` (cron rules, freeze) merged to `main` in July 2026 marked Enterprise-only, OSS excluded.
- A Kargo Warehouse only discovers git/image/chart Freight — the target Kubernetes version has to ride an artifact, not a bare string.

Cost, reference estate from Analysis 1 (1 prod + 2 UAT, list price, 8 September 2026):

|                                  | Per month | Δ               |
| -------------------------------- | --------- | --------------- |
| Three clusters, standard support | $219      | —               |
| One lapses into extended         | $584      | +$365 (+167%)   |
| All three lapse                  | $1,314    | +$1,095 (+500%) |

Against that analysis's EC2 estate (~$2,400 on-demand, ~$500 Spot): all three lapsing adds ~46% to an on-demand bill, more than triples a Spot one.

## 4. Upgrade Insights: reliable enough to automate?

**Decision.** Mandatory pre-check, never sufficient alone. Called explicitly via `list-insights`, not relied on as an apply-time gate.

- Only check that sees the client's own application behaviour (removed-API usage) — our compatibility guard doesn't know about that.
- 30-day audit-log window cuts both ways: misses APIs called less than monthly (false negative); keeps reporting fixed issues for up to 30 days (false positive, containers-roadmap#2569). This 30-day blind spot sets the floor for soak duration (open item, below).
- AWS's own blocking of `update-cluster-version` on `ERROR` findings is currently rolled back — an apply proceeds regardless, so this check must run as an explicit pipeline step, not be trusted to fail on its own.
- Override available as `force_update_version` on `aws_eks_cluster`, default `false`.

## Sources

Read 8 September 2026.

- [EKS add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html) · [Update an add-on](https://docs.aws.amazon.com/eks/latest/userguide/updating-an-add-on.html) · [Manage CoreDNS](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html)
- [CreateCluster](https://docs.aws.amazon.com/eks/latest/APIReference/API_CreateCluster.html) · [Alternate CNI plugins](https://docs.aws.amazon.com/eks/latest/userguide/alternate-cni-plugins.html) · [Cilium kube-proxy-free](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/) · [Cilium EKS requirements](https://docs.cilium.io/en/stable/installation/requirements-eks/)
- [Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) · [LB controller install](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/) · [Karpenter getting started](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/) · [Upbound AWS Pod Identity](https://docs.upbound.io/manuals/packages/providers/aws-auth/aws-pod-identity/)
- [EKS Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html) · [EKS pricing](https://aws.amazon.com/eks/pricing/) · [K8s release cadence](https://kubernetes.io/releases/release/)
- [list-insights](https://docs.aws.amazon.com/cli/latest/reference/eks/list-insights.html) · [describe-insight](https://docs.aws.amazon.com/cli/latest/reference/eks/describe-insight.html) · [Enforcement announcement](https://aws.amazon.com/about-aws/whats-new/2025/03/amazon-eks-enforces-upgrade-insights-check-cluster-upgrades) · [containers-roadmap#2570](https://github.com/aws/containers-roadmap/issues/2570) · [#2569](https://github.com/aws/containers-roadmap/issues/2569)
- [UpdateClusterVersion](https://docs.aws.amazon.com/eks/latest/APIReference/API_UpdateClusterVersion.html) · [provider PR#42134](https://github.com/hashicorp/terraform-provider-aws/pull/42134) · [aws_eks_addon](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) · [aws_eks_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster)
- [Kargo promotion steps](https://docs.kargo.io/user-guide/reference-docs/promotion-steps/) · [Working with stages](https://docs.kargo.io/user-guide/how-to-guides/working-with-stages) · [v1.2.0](https://docs.kargo.io/release-notes/v1.2.0) · [akuity/kargo#1328](https://github.com/akuity/kargo/issues/1328) · [PR#6710](https://github.com/akuity/kargo/pull/6710)

