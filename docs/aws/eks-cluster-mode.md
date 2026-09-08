# EKS cluster mode: Auto Mode vs Standard + self-hosted Karpenter

Socle is a multi-cloud Kubernetes factory. This document covers one decision: how AWS clusters get their compute provisioned.

## Decision: EKS Standard + self-hosted Karpenter. No Auto Mode option.

## Why

**Control.** No node access (Bottlerocket, no SSH). No Karpenter version pinning. No Karpenter controller logs — AWS confirms this in their own docs. Built-in NodePools (`system`, `general-purpose`) not editable, only on/off. Auto Mode NodePools use AWS-proprietary labels (`eks.amazonaws.com/`*), incompatible with open-source Karpenter labels — any existing NodePool needs a rewrite. CoreDNS, VPC CNI, and EBS CSI run as node-level systemd processes in Auto Mode, invisible to `kubectl`. Nodes force-replaced every 21 days — fine if stateless/replicated/PDB- correct, risky otherwise.

**CNI.** Socle standardizes on Cilium across all providers. Auto Mode locks the CNI to AWS VPC CNI, no alternative supported. Also locks the AMI to Bottlerocket, no custom AMI. Incompatible, full stop.

**Cost.** Auto Mode fee ≈ 12% of On-Demand price, billed regardless of actual purchase option. On Spot, same flat fee against a much lower base. Karpenter bin-packs the same way self-hosted or managed — the fee buys no different consumption model, just a surcharge on the same EC2 hours.

## What Auto Mode actually bundles

Included: Karpenter, VPC CNI, network policies, kube-proxy, CoreDNS, EBS CSI, AWS Load Balancer Controller, Pod Identity Agent, node monitoring agent, GPU/Neuron plugins.

Not included even in Auto Mode: cert-manager, ArgoCD, External Secrets, Istio, External DNS, Crossplane, KEDA, Prometheus/Grafana/Loki, Keycloak, non-AWS ingress controllers, Windows nodes, Fargate.

Once Cilium is in place it already covers CNI, network policies, kube-proxy replacement, partial LB via Gateway API, and Hubble observability (no Auto Mode equivalent at all). Net-new value Auto Mode would add, on top of Cilium: Karpenter management + AMI patch pipeline. That's it.

## Cost model

```
Reference estate  20 vCPU / 40 GiB, 24/7 in 1 prod env, 2 UAT envs for 12h per working day
                  2 nodes per env, 1 of each instance type
Priced            eu-west-3 list price, September 2026

```


| Instance     | vCPU | On-Demand $/hr | Spot $/hr | Auto Mode fee $/hr |
| ------------ | ---- | -------------- | --------- | ------------------ |
| i8ge.3xlarge | 12   | 1.6569         | 0.2774    | 0.19883            |
| t4g.2xlarge  | 8    | 0.3008         | 0.1277    | 0.0361             |



| Estate of three environments    | On-Demand  | Spot     |
| ------------------------------- | ---------- | -------- |
| **Auto Mode ON** — cloud total  | **$2,684** | **$784** |
| **Auto Mode OFF** — cloud total | **$2,396** | **$496** |


The control plane fee ($73/month per cluster) applies in both modes and cancels out. Auto mode fees are for standard support. (14 months lifetime Kubernetes version)

## What you give up

- Hands-off weekly AMI refresh. Patching and publishing is Socle's job.
- Zero-op Karpenter/CNI/CSI/LBC version management. Compatibility against each new EKS version is validated by the factory pipeline.
- GPU/Neuron drivers bundled in the node image. Device plugins installed and maintained separately.
- Node monitoring / auto-repair by default. Equivalent coverage is opt-in.
- AWS as single point of support for the data plane. Karpenter, CNI, and CSI issues are diagnosed by Socle — full log access, full responsibility.



## Position

**Handled in-house by the factory.** Karpenter, Cilium, CSI drivers, and the load balancer controller are standard components Socle.

## Sources

- [EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/best-practices/automode.html#_faq)
- [Alternate CNI plugins for Amazon EKS clusters](https://docs.aws.amazon.com/eks/latest/userguide/alternate-cni-plugins.html)
- [Enable EKS Auto Mode on existing clusters](https://docs.aws.amazon.com/eks/latest/userguide/migrate-auto.html)
- [Tarification d'Amazon EC2 à la demande](https://aws.amazon.com/fr/ec2/pricing/on-demand/)
- [Tarification des instances Spot Amazon EC2](https://aws.amazon.com/fr/ec2/spot/pricing/)
- [Tarification Amazon EKS](https://aws.amazon.com/fr/eks/pricing/)

