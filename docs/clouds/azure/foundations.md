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

| Position | |
| --- | --- |
| AKS Standard, Node Auto-Provisioning, never Automatic | enforced |
| A `system` pool of 2 × Standard_D2s_v5 over zones 1–3, tainted `CriticalAddonsOnly`; NAP provisions the rest | default |
| `stable` upgrade channel | enforced |
| Two maintenance windows of 4 to 24 hours, no default | required |
| `KubernetesOfficial` support, no LTS | enforced |
| Disk and File CSI drivers, AKS-managed | enforced |
| Container Insights (90 days) and Managed Prometheus | enforced, superseded |
| Entra Workload ID and the OIDC issuer | enforced |
| Microsoft-managed keys for etcd, disks and logs | enforced |
| `network_plugin = "none"`: Cilium comes with the bootstrap | enforced |
| `pod_cidr` `10.244.0.0/16`, passed to Cilium as an output | default |
| Private cluster, no public FQDN | enforced |
| One VNet `10.0.0.0/16`, one node subnet, one NAT gateway | default |
| Egress through the NAT gateway (`userAssignedNATGateway`) | enforced |
| `owner`, `environment`, `socle-version` tags on every resource | enforced |

<details>
<summary>Under the hood</summary>

- The private DNS zone is system-managed.
- Service range `10.1.0.0/16`, DNS service `10.1.0.10`: defaults AKS needs.
- Kubernetes RBAC on, system-assigned cluster identity: AKS's defaults,
  declared.
- `upgrade_settings.max_surge = "10%"` repeats AKS's server-side default so
  the plan converges.
- `kubernetes_version` has no default and accepts any `major.minor`.

</details>

## What is deliberately absent

- **Deployment Safeguards**: proposed, no `azurerm` 4.x attribute. `azure_policy_enabled = true` installs the add-on and assigns nothing.
- **`pod_cidr` on the cluster, a `network_policy`**: neither exists under BYO CNI; Cilium holds both.
- **Defender for Containers**: the client's subscription setting.
- **Any workload identity, Crossplane's included**: bind one to the `oidc_issuer_url` output.
- **Entra ID authentication on the API server**: local accounts stay on ([limits](limits.md#what-no-apply-can-finish)).
- **Any credential as input, any key as output**: `cluster_ca_certificate` is the only certificate, sensitive.
- **Windows pools, IPv6**: NAP supports neither.
- **Azure service metrics readers**: proposed.

## Measured

- **2026-10-05, OpenTofu 1.12.6, plan only**: the bootstrap with
  `cloud = "azure"` and no `aws` provider block fails with `Provider
  "registry.opentofu.org/hashicorp/aws" requires explicit configuration`.
  With a placeholder `aws` provider, the plan is 4 to add (Cilium, the
  operator, the instance, the socle release). The
  [quickstart](../../getting-started/azure.md#apply) carries that block.

## Reference

::include{file="opentofu/azure/README.md" section="tf-docs"}
