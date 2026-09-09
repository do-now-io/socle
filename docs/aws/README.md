# Architecture Decisions

## EKS Standard over Auto Mode

We use EKS Standard with self-hosted Karpenter instead of EKS Auto Mode. Auto Mode locks the CNI to AWS VPC CNI, incompatible with Cilium, our standard CNI across providers. It also limits control — no Karpenter logs, no version pinning, no node access — and adds a ~12% management fee on top of EC2 pricing, hitting Spot instances disproportionately hard. Self-hosted Karpenter gives the same autoscaling without the lock-in or the cost. Full rationale, cost model, and sources: [eks-cluster-mode.md](eks-cluster-mode.md).