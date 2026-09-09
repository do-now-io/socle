# Architecture Decisions

## EKS Standard over Auto Mode

We use EKS Standard with self-hosted Karpenter instead of EKS Auto Mode. Auto Mode locks the CNI to AWS VPC CNI, incompatible with Cilium, our standard CNI across providers. It also limits control — no Karpenter logs, no version pinning, no node access — and adds a ~12% management fee on top of EC2 pricing, hitting Spot instances disproportionately hard. Self-hosted Karpenter gives the same autoscaling without the lock-in or the cost. Full rationale, cost model, and sources: [eks-cluster-mode.md](eks-cluster-mode.md).

## EKS managed scope: add-ons, upgrades, identity

AWS-only add-ons (CoreDNS, EBS/EFS CSI, Pod Identity Agent) stay EKS-managed; VPC CNI and kube-proxy are refused, replaced by Cilium. Workload identity is Pod Identity exclusively — IRSA is absent from the module. Control plane version policy caps clients at n-1 while the socle supports down to n-2, driven by two decoupled Kargo pipelines (socle release, Kubernetes version) so extended support is never paid. EKS Upgrade Insights is a mandatory pre-check, never the only one. Full rationale, cost model, and sources: [eks-managed-scope.md](eks-managed-scope.md).