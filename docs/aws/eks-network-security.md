# EKS network & security baseline

Socle is a multi-cloud Kubernetes factory. [Analysis 1](eks-cluster-mode.md) and [managed scope](eks-managed-scope.md) settled compute and managed-component ownership on AWS. This document covers the base network and security posture: IPv6, exposure (Gateway API), pod-level security groups, GuardDuty / KMS / private endpoint, and the reference VPC/subnet/NAT architecture.

## 1. IPv6 in greenfield

**Decision.** Refused. Not a priority call — a feasibility one: Socle's exact stack (Cilium as a full VPC CNI replacement) is untested and unsupported for it today.

- EKS's IPv6 mode is IPv6-only pods (not dual-stack pods/services), irreversible at cluster creation, and AWS ties it specifically to VPC CNI in prefix-delegation mode — not documented as CNI-agnostic.
- Cilium's ENI IPv6 IPAM mode is still beta (open since January 2022, cilium#18405), with an unresolved bug where Cilium cannot intercept IPv4 traffic over the `v4if0` interface EKS creates for IPv4 egress on IPv6 clusters (cilium#28409).
- No documented case of Cilium as a full CNI replacement running with Karpenter in production on an EKS IPv6 cluster — existing write-ups use CNI chaining (Cilium alongside VPC CNI), a different topology than Socle's.
- Revisit once Cilium's ENI IPv6 mode leaves beta and the `v4if0` issue is resolved.

## 2. Exposure: Gateway API

**Decision.** AWS Load Balancer Controller implements Gateway API — already in Socle's stack, no VPC Lattice dependency.

- GA since v3.0.0 (January 2026), several point releases since — not experimental.
- Same reasoning as Cilium and Velero elsewhere: at comparable capability, keep what's already installed rather than add an AWS-only dependency. VPC Lattice / `aws-application-networking-k8s` has no multi-cloud equivalent and nothing here forces it.
- Two documented gaps, neither blocking default use: no `certificateRefs` for ACM (hostname-based discovery only — a risk only if several ACM certs match one hostname); a shared-Gateway health-check bug sends the target's IP as the Host header, breaking host-based health checks once multiple `HTTPRoute`s share one Gateway (aws-load-balancer-controller#4400) — fires only if/when the catalog builds a shared-LB pattern, which doesn't exist yet.

**Decision.** ALB by default; NLB as a catalog option, not refused.

- Socle's catalog exposes Kubernetes services — HTTP/HTTPS is the dominant case, and ALB's host/path routing plus WAF integration (NLB has none) covers it directly.
- NLB stays available through the same already-installed controller — Gateway API covers both ALB and NLB, so keeping it as a catalog option costs nothing extra.
- Refusing NLB outright would be the one choice that actually narrows Socle's AWS offering below what GCP's single Gateway controller (handling both L4 and L7 GatewayClasses) already allows.

Cost, one load balancer, 24/7, modest traffic (within 1 capacity unit), us-east-1 list price:

| | Base (730h) | Capacity (1 unit) | Per month |
| --- | --- | --- | --- |
| ALB | $16.43 | $5.84 (1 LCU, $0.008/hr) | ≈ $22.27 |
| NLB | $16.43 | $4.38 (1 NLCU, $0.006/hr) | ≈ $20.81 |

The base rate is identical ($0.0225/hr either way) — at this scale the gap is noise (~$1.46/mo). It only opens up at high capacity-unit counts, where NLB's cheaper per-unit rate compounds, or once **WAF** enters the picture (ALB-only): $5/month per Web ACL + $1/rule + $0.60/million requests — at real traffic volume this can outweigh the load balancer's own cost, so it belongs in the client's estimate as its own line, not folded into "ALB costs a bit more." Pricing itself isn't really what decides ALB vs NLB here — feature fit does.

## 3. Security groups for pods

**Decision.** Not applicable — refused by construction, not by choice.

- Security Groups for Pods is an extension of the VPC CNI plugin (ENI trunking via `amazon-vpc-resource-controller`), not a CNI-agnostic EKS API feature. There is no path to use it without VPC CNI installed, and Socle doesn't install it.
- Cilium already covers the same ground and more: identity-based L3/L4 NetworkPolicy plus L7 (HTTP/gRPC/Kafka) enforcement in eBPF, cluster-wide and identical on all four clouds. Nothing lost.

## 4. GuardDuty, secrets encryption, endpoint access

**Decision.** GuardDuty EKS Protection — catalog option, not default.

- Two independently-priced sub-features: Audit Log Monitoring (~$1.60/million events) and Runtime Monitoring, a separate in-cluster agent (~$1.50/vCPU-hour). Either can be enabled alone.
- Real cost even on a small cluster — roughly $20–25/month for a modest 3-node estate, scaling with cluster size and event volume. Not the kind of "free, not disableable" delegation the arbitration rule assumes; priced through as an option, not bundled into the standard offer.

**Decision.** Secrets encryption via KMS — on by default.

- Essentially free (~$1/month per key, negligible per-request cost); standard on Kubernetes 1.28+ already, and addable post-creation on older versions without recreating the cluster.
- One-way door: cannot be disabled once enabled. Accepted — same shape as other raise-only, no-real-downside defaults in this doc set.
- Real operational risk sits on the key, not the setting: disabling or deleting the KMS key makes existing secrets unreadable and the cluster unusable until it's restored. The module must protect against this (key deletion protection, no destroy-happy default) — a module-spec item, not a reason to refuse encryption itself.

**Decision.** API endpoint — public access restricted by CIDR, private access on. Not full private-only — AWS's own recommended pattern for this exact case.

- Free: this is the standard `endpointPublicAccess`/`endpointPrivateAccess` toggle, not the separate billed PrivateLink endpoint for the EKS control-plane AWS API (that one's ~$0.01/hr/AZ + per-GB, and only matters for calling the AWS API itself from a no-egress VPC — different thing, easy to conflate).
- Full private-only would require VPN, Direct Connect, or a bastion for every client VPC before the factory's own pipeline could reach a cluster — a real operational dependency to build and maintain across ~40 clients, with no equivalent already in place.

## 5. Reference network: VPC, subnets, NAT

**Decision.** Gateway endpoints (S3, DynamoDB) always on; Interface endpoints (ECR, STS, EC2, CloudWatch Logs) standard; NAT Gateway per AZ for what's left.

- Gateway endpoints are strictly free — no hourly charge, no data processing fee. No reason not to have them.
- Interface endpoints cost ~$7.30/month/AZ plus $0.01/GB, against NAT's $0.045/GB — the fixed cost breaks even at roughly 210 GB/month per AZ. A cluster pulling container images from ECR routinely clears that on image pulls alone, so ECR (api + dkr), STS (Pod Identity) and EC2 (Karpenter) endpoints pay for themselves almost immediately.
- NAT Gateway per AZ (not a single shared one) avoids cross-AZ data transfer charges on top of NAT's own fee, and matches standard AWS well-architected guidance — the remaining traffic (general internet egress) is what NAT is for once the AWS-service traffic is offloaded to endpoints.

## Sources

Read 8 September 2026.

- [EKS IPv6 clusters](https://docs.aws.amazon.com/eks/latest/userguide/cni-ipv6.html) · [EKS Best Practices — IPv6](https://aws.github.io/aws-eks-best-practices/networking/ipv6/)
- [aws-load-balancer-controller v3.0.0 release notes](https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/tag/v3.0.0) · [AWS blog — Gateway API GA](https://aws.amazon.com/blogs/networking-and-content-delivery/aws-load-balancer-controller-adds-general-availability-support-for-kubernetes-gateway-api/) · [Gateway API guide](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/gateway/) · [aws-load-balancer-controller#4400](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/4400)
- [Elastic Load Balancing pricing](https://aws.amazon.com/elasticloadbalancing/pricing/) · [WAF pricing](https://aws.amazon.com/waf/pricing/)
- [Security groups for pods](https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html)
- [GuardDuty pricing](https://aws.amazon.com/guardduty/pricing/) · [GuardDuty EKS Runtime Monitoring](https://docs.aws.amazon.com/guardduty/latest/ug/eks-runtime-monitoring-guardduty.html)
- [Enabling KMS secrets encryption](https://docs.aws.amazon.com/eks/latest/userguide/enable-kms.html) · [Adding KMS encryption to existing clusters](https://aws.amazon.com/about-aws/whats-new/2021/03/amazon-eks-supports-adding-kms-envelope-encryption-to-existing-clusters/)
- [Cluster endpoint access control](https://docs.aws.amazon.com/eks/latest/userguide/config-cluster-endpoint.html) · [EKS VPC interface endpoints (PrivateLink)](https://docs.aws.amazon.com/eks/latest/userguide/vpc-interface-endpoints.html)
- [VPC pricing](https://aws.amazon.com/vpc/pricing/) · [PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/)

## Unresolved

- ALB/NLB pricing is list price, us-east-1 (the pricing page doesn't break out eu-west-3) — re-price before quoting a client, and note actual LCU/NLCU consumption depends on real traffic, not the "1 unit" assumption used here.
- The `certificateRefs` gap and the #4400 health-check bug should be re-checked before the catalog ever implements a shared-Gateway (multi-`HTTPRoute`) pattern.
- KMS-key-deletion failure mode stated from established behaviour, not re-confirmed against a current AWS doc this session.
- GuardDuty pricing tiers and PrivateLink interface-endpoint rates pulled via automated fetch/search — worth a manual spot-check before quoting in a client-facing number.

