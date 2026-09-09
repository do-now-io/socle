# EKS network & security baseline

Socle is a multi-cloud Kubernetes factory. [Analysis 1](eks-cluster-mode.md) and [managed scope](eks-managed-scope.md) settled compute and managed-component ownership on AWS. This document covers the base network and security posture: IPv6, exposure (Gateway API), pod-level security groups, GuardDuty / KMS / private endpoint, and the reference VPC/subnet/NAT architecture.

## 1. IPv6 in greenfield

**Decision.** Refused. Not a priority call — a feasibility one: Socle's exact stack (Cilium as a full VPC CNI replacement) is untested and unsupported for it today.

- EKS's IPv6 mode is IPv6-only pods (not dual-stack pods/services), irreversible at cluster creation, and AWS ties it specifically to VPC CNI in prefix-delegation mode — not documented as CNI-agnostic.
- Cilium's ENI IPv6 IPAM mode is still beta (open since January 2022, cilium#18405), with an unresolved bug where Cilium cannot intercept IPv4 traffic over the `v4if0` interface EKS creates for IPv4 egress on IPv6 clusters (cilium#28409).
- No documented case of Cilium as a full CNI replacement running with Karpenter in production on an EKS IPv6 cluster — existing write-ups use CNI chaining (Cilium alongside VPC CNI), a different topology than Socle's.
- Revisit once Cilium's ENI IPv6 mode leaves beta and the `v4if0` issue is resolved.



## Sources

Read 8 September 2026.

- [EKS IPv6 clusters](https://docs.aws.amazon.com/eks/latest/userguide/cni-ipv6.html) · [EKS Best Practices — IPv6](https://aws.github.io/aws-eks-best-practices/networking/ipv6/)

