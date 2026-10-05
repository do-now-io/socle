---
title: Azure · AKS
description: What the socle builds on Azure, the decisions behind it, what it costs and what is proven.
sidebar:
  label: Overview
  order: 0
---

## What the socle builds

Two applies, no one-apply root yet.
[`opentofu/azure`](../../../opentofu/azure/main.tf) builds a resource group, a
VNet with a NAT gateway, and a private AKS Standard cluster with Node
Auto-Provisioning, no CNI, Entra Workload ID and a two-node `system` pool.
[`opentofu/bootstrap`](../../../opentofu/bootstrap/main.tf) with
`cloud = "azure"` then installs Cilium (BYO CNI) and Flux, and Flux renders
the catalog. The shared Gateways run on Cilium.

Start with [Prerequisites](prerequisites.md), then the
[Azure quickstart](../../getting-started/azure.md). What is decided for you is
in [Foundations](foundations.md).

## The decisions

All in [Azure decisions](../../decisions/azure.md). The Kubernetes version
policy is the socle's:
[SOCLE-05](../../decisions/socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n).

- [AZURE-01](../../decisions/azure.md#azure-01-aks-standard-with-node-auto-provisioning-not-automatic) · accepted · AKS Standard with Node Auto-Provisioning, not Automatic
- [AZURE-02](../../decisions/azure.md#azure-02-the-stable-upgrade-channel-and-one-maintenance-window-per-cluster) · accepted · `stable` channel, one maintenance window per cluster
- [AZURE-03](../../decisions/azure.md#azure-03-no-long-term-support) · accepted · no Long-Term Support
- [AZURE-04](../../decisions/azure.md#azure-04-the-storage-csi-drivers-stay-aks-managed) · accepted · storage CSI drivers stay AKS-managed
- [AZURE-05](../../decisions/azure.md#azure-05-managed-prometheus-and-container-insights) · superseded by SOCLE-03, still in the code · Managed Prometheus and Container Insights
- [AZURE-06](../../decisions/azure.md#azure-06-deployment-safeguards-at-baseline-in-enforce-mode) · proposed · Deployment Safeguards at Baseline, Enforce
- [AZURE-07](../../decisions/azure.md#azure-07-backup-with-velero) · proposed · backup with Velero
- [AZURE-08](../../decisions/azure.md#azure-08-entra-workload-id-for-every-workload-that-calls-azure) · accepted · Entra Workload ID for every workload
- [AZURE-09](../../decisions/azure.md#azure-09-no-customer-managed-keys) · accepted · no customer-managed keys
- [AZURE-10](../../decisions/azure.md#azure-10-self-managed-cilium-through-byo-cni) · accepted · self-managed Cilium through BYO CNI
- [AZURE-11](../../decisions/azure.md#azure-11-gateway-api-through-the-application-routing-add-on) · superseded by GATEWAY-API-02 · Gateway API through application routing
- [AZURE-12](../../decisions/azure.md#azure-12-a-private-cluster-with-no-public-fqdn) · accepted · private cluster, no public FQDN
- [AZURE-13](../../decisions/azure.md#azure-13-one-vnet-one-node-subnet-one-nat-gateway) · accepted · one VNet, one node subnet, one NAT gateway
- [AZURE-14](../../decisions/azure.md#azure-14-microsoft-defender-for-containers-as-a-catalog-option) · superseded by AZURE-15 · Defender as a catalog option
- [AZURE-15](../../decisions/azure.md#azure-15-defender-for-containers-is-the-clients-subscription-decision) · accepted · Defender is the client's subscription decision
- [AZURE-16](../../decisions/azure.md#azure-16-azure-service-metrics-read-from-outside-the-cluster) · proposed · Azure service metrics read from outside the cluster

## Cost

Per cluster. US dollars, France Central list prices, September 2026, before
tax.

| Line | Per month |
| --- | --- |
| Control plane, Standard tier ($0.10/hour) | $73.00 |
| NAT gateway ($0.045/hour, plus $0.045/GB) | $32.85 |
| API server private endpoint ($0.01/hour, plus $0.01/GB) | $7.30 |
| Nodes | the VM price; NAP adds no meter |

<details>
<summary>Under the hood</summary>

- Reference estate (one prod 24/7, two UAT 12 hours per working day, one
  Standard_D4s_v5 and one Standard_D8s_v5 each): control plane and nodes
  $1,060.34 a month, against $1,338.99 on AKS Automatic.
- Not counted: the two `system` nodes (2 × Standard_D2s_v5), and the
  Container Insights and Managed Prometheus ingestion the module still turns
  on ([AZURE-05](../../decisions/azure.md#azure-05-managed-prometheus-and-container-insights)),
  billed per GB.

</details>

## Status

- **Built**: the foundations and the bootstrap's `azure` branch, both
  `tofu test`ed with mocked providers. The plan against floci-az fails on its
  self-signed certificate; not a required check.
- **Never applied** on a real subscription: BYO CNI with NAP, the private
  cluster and Cilium on AKS are unproven. Convergence is proven on AWS
  (floci) only.
- **Not offered yet**: Velero, a Crossplane Azure provider,
  `kube.keda.services` ([limits](limits.md)).
