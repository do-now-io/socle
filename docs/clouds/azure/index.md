---
title: Azure · AKS
description: What the socle builds on Azure, the decisions behind it, what it costs and what is proven.
sidebar:
  label: Overview
  order: 0
---

## What the socle builds

Two modules, applied one after the other: there is no one-apply root for
Azure yet.

- [`opentofu/azure`](../../../opentofu/azure/main.tf), the foundations: a
  resource group, a VNet with one node subnet and a NAT gateway, and a private
  AKS Standard cluster with Node Auto-Provisioning, no CNI, Entra Workload ID
  and the OIDC issuer. A two-node `system` pool, tainted for critical add-ons,
  is the only fixed compute; NAP provisions the rest. See
  [foundations](foundations.md).
- [`opentofu/bootstrap`](../../../opentofu/bootstrap/main.tf) with
  `cloud = "azure"`: Cilium by Helm in AKS BYO CNI mode, then the Flux
  Operator, a FluxInstance and the socle's inputs. Flux then renders the
  catalog from the signed OCI artifact.

The shared Gateways run on Cilium's `cilium` GatewayClass. `velero` is not
offered on Azure, and Crossplane installs with no Azure provider.

## The decisions

All in [Azure decisions](../../decisions/azure.md).

- [AZURE-01](../../decisions/azure.md#azure-01-aks-standard-with-node-auto-provisioning-not-automatic): AKS Standard with Node Auto-Provisioning, not Automatic. *accepted*
- [AZURE-02](../../decisions/azure.md#azure-02-the-stable-upgrade-channel-and-one-maintenance-window-per-cluster): the `stable` upgrade channel, and one maintenance window per cluster. *accepted*
- [AZURE-03](../../decisions/azure.md#azure-03-no-long-term-support): no Long-Term Support. *accepted*
- [AZURE-04](../../decisions/azure.md#azure-04-the-storage-csi-drivers-stay-aks-managed): the storage CSI drivers stay AKS-managed. *accepted*
- [AZURE-05](../../decisions/azure.md#azure-05-managed-prometheus-and-container-insights): Managed Prometheus and Container Insights. *superseded by SOCLE-03, still in the code*
- [AZURE-06](../../decisions/azure.md#azure-06-deployment-safeguards-at-baseline-in-enforce-mode): Deployment Safeguards at Baseline, Enforce. *proposed*
- [AZURE-07](../../decisions/azure.md#azure-07-backup-with-velero): backup with Velero. *proposed*
- [AZURE-08](../../decisions/azure.md#azure-08-entra-workload-id-for-every-workload-that-calls-azure): Entra Workload ID for every workload that calls Azure. *accepted*
- [AZURE-09](../../decisions/azure.md#azure-09-no-customer-managed-keys): no customer-managed keys. *accepted*
- [AZURE-10](../../decisions/azure.md#azure-10-self-managed-cilium-through-byo-cni): self-managed Cilium through BYO CNI. *accepted*
- [AZURE-11](../../decisions/azure.md#azure-11-gateway-api-through-the-application-routing-add-on): Gateway API through the application routing add-on. *superseded by GATEWAY-API-02*
- [AZURE-12](../../decisions/azure.md#azure-12-a-private-cluster-with-no-public-fqdn): a private cluster, with no public FQDN. *accepted*
- [AZURE-13](../../decisions/azure.md#azure-13-one-vnet-one-node-subnet-one-nat-gateway): one VNet, one node subnet, one NAT gateway. *accepted*
- [AZURE-14](../../decisions/azure.md#azure-14-microsoft-defender-for-containers-as-a-catalog-option): Defender for Containers as a catalog option. *superseded by AZURE-15*
- [AZURE-15](../../decisions/azure.md#azure-15-defender-for-containers-is-the-clients-subscription-decision): Defender for Containers is the client's subscription decision. *accepted*
- [AZURE-16](../../decisions/azure.md#azure-16-azure-service-metrics-read-from-outside-the-cluster): Azure service metrics read from outside the cluster. *proposed*

## Cost

US dollars, France Central list prices read in September 2026, before tax.

| Item | Per month |
| --- | --- |
| Control plane, Standard tier ($0.10/hour) | $73.00 per cluster |
| NAT gateway ($0.045/hour, plus $0.045/GB processed) | $32.85 per cluster |
| API server private endpoint ($0.01/hour, plus $0.01/GB) | $7.30 per cluster |
| Nodes | the VM price; NAP adds no meter on Standard |

On the reference estate (one prod environment 24/7, two UAT environments
12 hours per working day, one Standard_D4s_v5 and one Standard_D8s_v5 per
environment), control plane and nodes come to $1,060.34 a month, against
$1,338.99 on AKS Automatic.

Not counted: the two `system` nodes (2 × Standard_D2s_v5 by default), and the
Container Insights and Managed Prometheus ingestion the module still turns on
([AZURE-05](../../decisions/azure.md#azure-05-managed-prometheus-and-container-insights)),
billed per GB until removed.

## Status

| Part | State |
| --- | --- |
| Foundations, `tofu test` | 14 runs, mocked `azurerm`: every validation, and the defaults |
| Foundations, plan against floci-az in CI | fails at provider configuration on floci-az's self-signed TLS certificate; not a required check |
| Bootstrap with `cloud = "azure"`, `tofu test` | plan with mocked providers: Cilium in BYO CNI mode with the pod pool, no CoreDNS, the shared Gateways |
| Apply on a real Azure subscription | never run: BYO CNI with NAP, the private cluster and Cilium on AKS are unproven |
| Convergence end to end | proven on AWS (floci), not on Azure |

What no apply can finish, and what the socle does not offer here yet:
[limits](limits.md).
