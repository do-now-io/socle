---
title: Foundations
description: 'The Azure foundations module: what is decided for you, what is deliberately absent, and its full reference.'
sidebar:
  order: 2
---

[`opentofu/azure`](../../../opentofu/azure/main.tf) is one flat module: a
resource group, a VNet, an AKS cluster and its identity. It builds a cluster
with no CNI and no workload, and outputs what the
[bootstrap module](../../reference/opentofu-modules.md) needs to install
Cilium and Flux on it.

## What is decided for you

*Hardcoded* means no variable changes it; *default* means a variable does.

| Position | Set by | Decision |
| --- | --- | --- |
| AKS Standard tier, Node Auto-Provisioning on, never Automatic | hardcoded | [AZURE-01](../../decisions/azure.md#azure-01-aks-standard-with-node-auto-provisioning-not-automatic) |
| A `system` pool of 2 × Standard_D2s_v5 over zones 1, 2, 3, tainted `CriticalAddonsOnly`; NAP provisions every other node | default | [AZURE-01](../../decisions/azure.md#azure-01-aks-standard-with-node-auto-provisioning-not-automatic) |
| `stable` upgrade channel | hardcoded | [AZURE-02](../../decisions/azure.md#azure-02-the-stable-upgrade-channel-and-one-maintenance-window-per-cluster) |
| Two maintenance windows, 4 to 24 hours, required, no default | required | [AZURE-02](../../decisions/azure.md#azure-02-the-stable-upgrade-channel-and-one-maintenance-window-per-cluster) |
| `KubernetesOfficial` support plan, no LTS | hardcoded | [AZURE-03](../../decisions/azure.md#azure-03-no-long-term-support) |
| Disk and File CSI drivers, AKS-managed | hardcoded | [AZURE-04](../../decisions/azure.md#azure-04-the-storage-csi-drivers-stay-aks-managed) |
| Container Insights (Log Analytics, 90 days) and Managed Prometheus | hardcoded, superseded | [AZURE-05](../../decisions/azure.md#azure-05-managed-prometheus-and-container-insights) |
| Entra Workload ID and the OIDC issuer | hardcoded | [AZURE-08](../../decisions/azure.md#azure-08-entra-workload-id-for-every-workload-that-calls-azure) |
| Microsoft-managed keys for etcd, disks and logs | hardcoded | [AZURE-09](../../decisions/azure.md#azure-09-no-customer-managed-keys) |
| `network_plugin = "none"`: no CNI until the bootstrap installs Cilium | hardcoded | [AZURE-10](../../decisions/azure.md#azure-10-self-managed-cilium-through-byo-cni) |
| `pod_cidr` (`10.244.0.0/16`) passed to Cilium through an output, not set on the cluster | default | [AZURE-10](../../decisions/azure.md#azure-10-self-managed-cilium-through-byo-cni) |
| Private cluster, no public FQDN, system-managed private DNS zone | hardcoded | [AZURE-12](../../decisions/azure.md#azure-12-a-private-cluster-with-no-public-fqdn) |
| One VNet (`10.0.0.0/16`), one node subnet covering it, one NAT gateway | default | [AZURE-13](../../decisions/azure.md#azure-13-one-vnet-one-node-subnet-one-nat-gateway) |
| `outbound_type = "userAssignedNATGateway"` | hardcoded | [AZURE-13](../../decisions/azure.md#azure-13-one-vnet-one-node-subnet-one-nat-gateway) |
| Service range `10.1.0.0/16`, DNS service at `10.1.0.10` | default | none: AKS needs both |
| Kubernetes RBAC on, system-assigned cluster identity | hardcoded | none: AKS's own default, declared |
| Tags `owner`, `environment`, `socle-version` on every resource | hardcoded | none |

Some defaults are engineering, not a decision: `vnet_cidr` is large enough for
any node count; `log_retention_days` (90) is for the Container Insights
workspace; `upgrade_settings.max_surge = "10%"` repeats AKS's server-side
default so the plan converges.

`kubernetes_version` has no default: the version policy is the socle's
([SOCLE-05](../../decisions/socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n)),
and the module accepts any `major.minor`.

## What is deliberately absent

An option in the interface is one that is supported and tested; these are not
options.

- **Deployment Safeguards.** Proposed in
  [AZURE-06](../../decisions/azure.md#azure-06-deployment-safeguards-at-baseline-in-enforce-mode),
  not built: `azurerm` 4.x has no attribute for it. `azure_policy_enabled =
  true` installs the Azure Policy add-on and assigns nothing. No Pod Security
  Standard is enforced by the foundations.
- **`pod_cidr` on the cluster.** `azurerm` accepts it only with `kubenet` or
  overlay mode, not with `network_plugin = "none"`.
- **A `network_policy`.** None exists under BYO CNI; Cilium enforces policies.
- **Microsoft Defender for Containers.** A subscription setting, the client's
  ([AZURE-15](../../decisions/azure.md#azure-15-defender-for-containers-is-the-clients-subscription-decision)).
- **Any workload identity, Crossplane's included.** A federated credential
  needs a Kubernetes service account that exists only once the catalog runs.
  The `oidc_issuer_url` output is what one binds to.
- **Entra ID authentication on the API server.** Local accounts stay on; see
  [limits](limits.md#what-no-apply-can-finish).
- **Any credential as input, any key as output.** `cluster_ca_certificate` is
  the only certificate output, and it is sensitive.
- **Windows node pools, IPv6.** NAP supports neither.
- **Readers of Azure service metrics.** Proposed in
  [AZURE-16](../../decisions/azure.md#azure-16-azure-service-metrics-read-from-outside-the-cluster);
  nothing in this module.

## Measured

2026-10-05, OpenTofu 1.12.6, on a workstation, plan only: a root calling
`opentofu/bootstrap` with `cloud = "azure"` and no `aws` provider block fails
with `Provider "registry.opentofu.org/hashicorp/aws" requires explicit
configuration`, though no AWS resource is planned. With a placeholder `aws`
provider (static dummy keys, every `skip_*` set), the plan is Cilium, the
operator, the instance and the socle release: 4 to add. The
[quickstart](../../getting-started/azure.md#apply) carries that block.

## Reference

::include{file="opentofu/azure/README.md" section="tf-docs"}
