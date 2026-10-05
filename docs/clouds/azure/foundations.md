---
title: Foundations
description: 'The Azure foundations module: what is decided for you, what is deliberately absent, and its full reference.'
sidebar:
  order: 2
---

[`opentofu/azure`](../../../opentofu/azure/main.tf) builds a resource group, a
VNet, an AKS cluster with no CNI and no workload, and its identity, and
outputs what the [bootstrap](../../reference/opentofu-modules.md) needs to
install Cilium and Flux.

## What is decided for you

*Enforced*: no variable. *Default*: a variable changes it.

| Position | | Decision |
| --- | --- | --- |
| AKS Standard, Node Auto-Provisioning, never Automatic | enforced | [AZURE-01](../../decisions/azure.md#azure-01-aks-standard-with-node-auto-provisioning-not-automatic) |
| A `system` pool of 2 × Standard_D2s_v5 over zones 1–3, tainted `CriticalAddonsOnly`; NAP provisions the rest | default | [AZURE-01](../../decisions/azure.md#azure-01-aks-standard-with-node-auto-provisioning-not-automatic) |
| `stable` upgrade channel | enforced | [AZURE-02](../../decisions/azure.md#azure-02-the-stable-upgrade-channel-and-one-maintenance-window-per-cluster) |
| Two maintenance windows of 4 to 24 hours, no default | required | [AZURE-02](../../decisions/azure.md#azure-02-the-stable-upgrade-channel-and-one-maintenance-window-per-cluster) |
| `KubernetesOfficial` support, no LTS | enforced | [AZURE-03](../../decisions/azure.md#azure-03-no-long-term-support) |
| Disk and File CSI drivers, AKS-managed | enforced | [AZURE-04](../../decisions/azure.md#azure-04-the-storage-csi-drivers-stay-aks-managed) |
| Container Insights (90 days) and Managed Prometheus | enforced, superseded | [AZURE-05](../../decisions/azure.md#azure-05-managed-prometheus-and-container-insights) |
| Entra Workload ID and the OIDC issuer | enforced | [AZURE-08](../../decisions/azure.md#azure-08-entra-workload-id-for-every-workload-that-calls-azure) |
| Microsoft-managed keys for etcd, disks and logs | enforced | [AZURE-09](../../decisions/azure.md#azure-09-no-customer-managed-keys) |
| `network_plugin = "none"`: Cilium comes with the bootstrap | enforced | [AZURE-10](../../decisions/azure.md#azure-10-self-managed-cilium-through-byo-cni) |
| `pod_cidr` `10.244.0.0/16`, passed to Cilium as an output | default | [AZURE-10](../../decisions/azure.md#azure-10-self-managed-cilium-through-byo-cni) |
| Private cluster, no public FQDN | enforced | [AZURE-12](../../decisions/azure.md#azure-12-a-private-cluster-with-no-public-fqdn) |
| One VNet `10.0.0.0/16`, one node subnet, one NAT gateway | default | [AZURE-13](../../decisions/azure.md#azure-13-one-vnet-one-node-subnet-one-nat-gateway) |
| Egress through the NAT gateway (`userAssignedNATGateway`) | enforced | [AZURE-13](../../decisions/azure.md#azure-13-one-vnet-one-node-subnet-one-nat-gateway) |
| `owner`, `environment`, `socle-version` tags on every resource | enforced | — |

<details>
<summary>Under the hood</summary>

- The private DNS zone is system-managed.
- Service range `10.1.0.0/16`, DNS service `10.1.0.10`: defaults AKS needs.
- Kubernetes RBAC on, system-assigned cluster identity: AKS's defaults,
  declared.
- `upgrade_settings.max_surge = "10%"` repeats AKS's server-side default so
  the plan converges.
- `kubernetes_version` has no default and accepts any `major.minor`; the
  policy is
  [SOCLE-05](../../decisions/socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n).

</details>

## What is deliberately absent

- **Deployment Safeguards**: proposed ([AZURE-06](../../decisions/azure.md#azure-06-deployment-safeguards-at-baseline-in-enforce-mode)), no `azurerm` 4.x attribute. `azure_policy_enabled = true` installs the add-on and assigns nothing.
- **`pod_cidr` on the cluster, a `network_policy`**: neither exists under BYO CNI; Cilium holds both.
- **Defender for Containers**: the client's subscription setting ([AZURE-15](../../decisions/azure.md#azure-15-defender-for-containers-is-the-clients-subscription-decision)).
- **Any workload identity, Crossplane's included**: bind one to the `oidc_issuer_url` output.
- **Entra ID authentication on the API server**: local accounts stay on ([limits](limits.md#what-no-apply-can-finish)).
- **Any credential as input, any key as output**: `cluster_ca_certificate` is the only certificate, sensitive.
- **Windows pools, IPv6**: NAP supports neither.
- **Azure service metrics readers**: proposed ([AZURE-16](../../decisions/azure.md#azure-16-azure-service-metrics-read-from-outside-the-cluster)).

## Measured

- **2026-10-05, OpenTofu 1.12.6, plan only**: the bootstrap with
  `cloud = "azure"` and no `aws` provider block fails with `Provider
  "registry.opentofu.org/hashicorp/aws" requires explicit configuration`.
  With a placeholder `aws` provider, the plan is 4 to add (Cilium, the
  operator, the instance, the socle release). The
  [quickstart](../../getting-started/azure.md#apply) carries that block.

## Reference

::include{file="opentofu/azure/README.md" section="tf-docs"}
