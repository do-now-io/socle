---
title: Limits
description: What no apply can finish on Azure, the provider limits the socle runs into, and what it does not offer there yet.
sidebar:
  order: 3
---

## What no apply can finish

- **One apply for the whole socle**: no `opentofu/clusters/azure`; the foundations and the bootstrap are two applies ([quickstart](../../getting-started/azure.md)).
- **A login from `helm_kubernetes`**: it needs Entra ID authentication, which the module does not enable; use `az aks get-credentials --admin`.
- **The bootstrap from outside the VNet**: the API server is private ([AZURE-12](../../decisions/azure.md#azure-12-a-private-cluster-with-no-public-fqdn)); run it from the VNet or a connected network, with the private DNS zone resolvable.
- **The bootstrap without an `aws` provider block**: give it a placeholder ([measured](foundations.md#measured)).
- **A `kubernetes_version` that follows the cluster**: once AKS moves the minor, the next plan may propose a downgrade AKS refuses (read from the code, not seen). Set it to `az aks show --resource-group <rg> --name <cluster> --query currentKubernetesVersion -o tsv` first.

## Provider limits

- **Node Auto-Provisioning** refuses Windows pools, IPv6, a cluster stop, and an outbound type change after creation.
- **BYO CNI**: Microsoft support excludes CNI issues; nodes and control plane stay supported.
- **No `pod_cidr` and no `network_policy` on the cluster** under `network_plugin = "none"`; Cilium's pool and policies are the only ones.
- **AKS kube-proxy still runs** beside Cilium's replacement.
- **Deployment Safeguards**: no `azurerm` 4.x attribute.
- **Maintenance windows are best effort**, 4 to 24 hours; share none between clusters, or ARM may throttle.
- **One non-zonal NAT gateway**: other zones cross a zone boundary, and lose egress if its zone fails.
- **Managed Prometheus and Container Insights** are still created, superseded by [SOCLE-03](../../decisions/socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud), billed per GB.

## What the socle does not offer here yet

- **Velero**: refused at plan on `azure` ([AZURE-07](../../decisions/azure.md#azure-07-backup-with-velero)).
- **A Crossplane Azure provider**: providers render for AWS only.
- **`kube.keda.services`**: refused; use a `TriggerAuthentication` Secret or `podIdentity.azureWorkload` in `values`.
- **external-dns credentials**: create the `external-dns-azure` Secret ([external-dns](../../catalog/external-dns.md)).
- **Deployment Safeguards** ([AZURE-06](../../decisions/azure.md#azure-06-deployment-safeguards-at-baseline-in-enforce-mode)): Kyverno is the policy path.
- **Readers of Azure metrics, quotas and cost** ([AZURE-16](../../decisions/azure.md#azure-16-azure-service-metrics-read-from-outside-the-cluster)).
- **A real-cloud proof**: planned with mocked providers only.
