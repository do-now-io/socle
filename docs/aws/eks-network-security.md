# EKS network & security baseline

Socle is a multi-cloud Kubernetes factory. [Analysis 1](eks-cluster-mode.md) and [managed scope](eks-managed-scope.md) settled compute and managed-component ownership on AWS. This document covers the base network and security posture: IPv6, exposure (Gateway API), pod-level security groups, GuardDuty / KMS / private endpoint, and the reference VPC/subnet/NAT architecture.

## 1. IPv6 in greenfield

**Decision.** Refused. Not a priority call — a feasibility one: Socle's exact stack (Cilium as a full VPC CNI replacement) is untested and unsupported for it today.

- EKS's IPv6 mode is IPv6-only pods (not dual-stack pods/services), irreversible at cluster creation, and AWS ties it specifically to VPC CNI in prefix-delegation mode — not documented as CNI-agnostic.
- Cilium's ENI IPv6 IPAM mode is still beta (open since January 2022, cilium#18405), with an unresolved bug where Cilium cannot intercept IPv4 traffic over the `v4if0` interface EKS creates for IPv4 egress on IPv6 clusters (cilium#28409).

## 2. Exposure: Gateway API

**Decision.** AWS Load Balancer Controller implements Gateway API — already in Socle's stack, no VPC Lattice dependency.

- GA since v3.0.0 (January 2026), several point releases since — not experimental.
- Two documented gaps, neither blocking default use: no `certificateRefs` for ACM (hostname-based discovery only — a risk only if several ACM certs match one hostname); a shared-Gateway health-check bug sends the target's IP as the Host header, breaking host-based health checks once multiple `HTTPRoute`s share one Gateway (aws-load-balancer-controller#4400) — fires only if/when the catalog builds a shared-LB pattern, which doesn't exist yet; re-check both before it does.

**Decision.** ALB by default; NLB as a catalog option, not refused.

- Socle's catalog exposes Kubernetes services — HTTP/HTTPS is the dominant case, and ALB's host/path routing plus WAF integration (NLB has none) covers it directly.
- NLB stays available through the same already-installed controller — Gateway API covers both ALB and NLB, so keeping it as a catalog option costs nothing extra.
- Refusing NLB outright would be the one choice that actually narrows Socle's AWS offering below what GCP's single Gateway controller (handling both L4 and L7 GatewayClasses) already allows.

A client is billed for whichever one they actually provision, not both — so the ALB-vs-NLB choice isn't a cost trade-off to quantify, it's feature fit (above). The one real cost to flag: **WAF** (ALB-only) is priced separately from the load balancer — $5/month per Web ACL + $1/rule + $0.60/million requests — and at real traffic volume this can outweigh the load balancer's own cost, so it belongs in a client's estimate as its own line.

## 3. Security groups for pods

**Decision.** Not applicable — refused by construction, not by choice: it's a VPC CNI feature (ENI trunking), and Socle doesn't run VPC CNI.

- Cilium already covers the same ground and more: identity-based L3/L4 NetworkPolicy plus L7 (HTTP/gRPC/Kafka) enforcement in eBPF, cluster-wide and identical on all four clouds. Nothing lost.

## 4. GuardDuty, secrets encryption, endpoint access

**Decision.** GuardDuty EKS Protection — catalog option, not default.

- Two independently-priced sub-features: Audit Log Monitoring (~$1.60/million events) and Runtime Monitoring, a separate in-cluster agent (~$1.50/vCPU-hour). Either can be enabled alone.
- Real cost even on a small cluster — roughly $20–25/month for a modest 3-node estate, scaling with cluster size and event volume. Not the kind of "free, not disableable" delegation the arbitration rule assumes; priced through as an option, not bundled into the standard offer.

**Decision.** Secrets encryption via KMS — on by default.

- Essentially free (~$1/month per key, negligible per-request cost); standard on Kubernetes 1.28+ already, and addable post-creation on older versions without recreating the cluster.

**Decision.** API endpoint — public access restricted by CIDR, private access on. Not full private-only — AWS's own recommended pattern for this exact case.

- Free: this is the standard `endpointPublicAccess`/`endpointPrivateAccess` toggle, not the separate billed PrivateLink endpoint for the EKS control-plane AWS API (that one's ~$0.01/hr/AZ + per-GB, and only matters for calling the AWS API itself from a no-egress VPC — different thing, easy to conflate).

## 5. Reference network: VPC, subnets, NAT

**Decision.** Gateway endpoints (S3, DynamoDB) always on; Interface endpoints (ECR, STS, EC2, CloudWatch Logs) standard; NAT Gateway per AZ for what's left.

- Gateway endpoints are strictly free — no hourly charge, no data processing fee. No reason not to have them.
- Interface endpoints (ECR, STS, EC2, CloudWatch Logs) aren't chosen for savings — at the traffic volumes a cluster's own AWS-API calls realistically produce, the cost is low either way and the gap between routing that traffic via NAT or via an endpoint is a few dollars a month (table below). The reason to standardize on them is isolation: STS and EC2 calls (Pod Identity, Karpenter) are load-bearing for the cluster to function, and an endpoint keeps that traffic off the shared NAT path and off the public internet entirely, rather than competing with whatever else is using NAT.
- NAT Gateway per AZ (not a single shared one) avoids cross-AZ data transfer charges on top of NAT's own fee, and matches standard AWS well-architected guidance — the remaining traffic (general internet egress) is what NAT is for.

Cost of routing that traffic one way or the other, per AZ per month, at volumes realistic for a cluster's own AWS-API traffic:

| Traffic/month | Via NAT only | Via Interface endpoint | Difference |
| --- | --- | --- | --- |
| 50 GB | $2.25 | $7.30 + $0.50 = $7.80 | $5.55 |
| 100 GB | $4.50 | $7.30 + $1.00 = $8.30 | $3.80 |

Either way, the monthly cost is small — this isn't a decision worth making on price.

## Sources

Read 8 September 2026.

- [EKS IPv6 clusters](https://docs.aws.amazon.com/eks/latest/userguide/cni-ipv6.html) · [EKS Best Practices — IPv6](https://aws.github.io/aws-eks-best-practices/networking/ipv6/)
- [aws-load-balancer-controller v3.0.0 release notes](https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/tag/v3.0.0) · [AWS blog — Gateway API GA](https://aws.amazon.com/blogs/networking-and-content-delivery/aws-load-balancer-controller-adds-general-availability-support-for-kubernetes-gateway-api/) · [Gateway API guide](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/gateway/) · [aws-load-balancer-controller#4400](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/4400)
- [WAF pricing](https://aws.amazon.com/waf/pricing/)
- [Security groups for pods](https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html)
- [GuardDuty pricing](https://aws.amazon.com/guardduty/pricing/) · [GuardDuty EKS Runtime Monitoring](https://docs.aws.amazon.com/guardduty/latest/ug/eks-runtime-monitoring-guardduty.html)
- [Enabling KMS secrets encryption](https://docs.aws.amazon.com/eks/latest/userguide/enable-kms.html) · [Adding KMS encryption to existing clusters](https://aws.amazon.com/about-aws/whats-new/2021/03/amazon-eks-supports-adding-kms-envelope-encryption-to-existing-clusters/)
- [Cluster endpoint access control](https://docs.aws.amazon.com/eks/latest/userguide/config-cluster-endpoint.html) · [EKS VPC interface endpoints (PrivateLink)](https://docs.aws.amazon.com/eks/latest/userguide/vpc-interface-endpoints.html)
- [VPC pricing](https://aws.amazon.com/vpc/pricing/) · [PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/)

