# Architecture Decisions

## EKS Standard over Auto Mode

We use EKS Standard with self-hosted Karpenter instead of EKS Auto Mode. Auto Mode locks the CNI to AWS VPC CNI, incompatible with Cilium, our standard CNI across providers. It also limits control — no Karpenter logs, no version pinning, no node access — and adds a ~12% management fee on top of EC2 pricing, hitting Spot instances disproportionately hard. Self-hosted Karpenter gives the same autoscaling without the lock-in or the cost. Full rationale, cost model, and sources: [eks-cluster-mode.md](eks-cluster-mode.md).

## EKS managed scope: add-ons, upgrades, identity

AWS-only add-ons (CoreDNS, EBS/EFS CSI, Pod Identity Agent) stay EKS-managed; VPC CNI and kube-proxy are refused, replaced by Cilium. Workload identity is Pod Identity exclusively — IRSA is absent from the module. Control plane version policy caps clients at n-1 while the socle supports down to n-2, driven by two decoupled Kargo pipelines (socle release, Kubernetes version) so extended support is never paid. EKS Upgrade Insights is a mandatory pre-check, never the only one. Full rationale, cost model, and sources: [eks-managed-scope.md](eks-managed-scope.md).

## EKS network & security baseline

IPv6 is refused — a feasibility call, not a priority one: Cilium's ENI IPv6 IPAM mode is still beta and unusable with the stack Socle runs. Exposure goes through Gateway API, implemented by the AWS Load Balancer Controller already in the stack — ALB by default, NLB a catalog option, and WAF priced as its own line rather than folded into the load balancer. Security groups for pods are refused by construction: a VPC CNI feature, and Cilium covers the same ground in eBPF. GuardDuty EKS Protection is a catalog option priced through rather than bundled, secrets encryption via KMS is on by default, and the API endpoint keeps public access restricted by CIDR with private access on. Full rationale, cost model, and sources: [eks-network-security.md](eks-network-security.md).

## Observing AWS resources outside the cluster

Service metrics are pulled by YACE from a central observability cluster every 300 seconds — one cadence across the whole supervision plane rather than a per-cloud tuning exercise. Cluster metrics never travel that path; pointing the same exporter at them is the mistake the document calls out explicitly. CloudWatch Metric Streams and the Cost Explorer API are both refused — the first only wins below a ~190-second interval, the second is paid and opaque. Cost attribution runs on CUR / Data Exports into the client's own S3 bucket, quota metrics sit in the standard perimeter, and unmanaged resources are found through the Resource Groups Tagging API, with AWS Config as a catalog option. Full rationale, cost model, and sources: [cloud-observability.md](cloud-observability.md).
