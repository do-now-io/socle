---
title: Limits
description: What no apply can finish on Azure, the provider limits the socle runs into, and what it does not offer there yet.
sidebar:
  order: 3
---

## What no apply can finish

- **One apply for the whole socle.** There is no `opentofu/clusters/azure`
  root: the foundations and the bootstrap are two applies, the second one fed
  by the first one's outputs ([quickstart](../../getting-started/azure.md)).
- **A login from the module's `helm_kubernetes` output.** It runs `kubelogin
  get-token --login azurecli`, which needs Entra ID authentication on the
  cluster (`azure_active_directory_role_based_access_control`). The module
  does not enable it, and local accounts stay the cluster's only login. Until
  it does, a root reads a kubeconfig from `az aks get-credentials --admin`
  instead.
- **The bootstrap from outside the VNet.** The API server has a private
  endpoint and no public FQDN
  ([AZURE-12](../../decisions/azure.md#azure-12-a-private-cluster-with-no-public-fqdn)).
  Helm reaches it only from the VNet or a network connected to it (peering,
  VPN, ExpressRoute, Bastion), with the private DNS zone resolvable.
  `az aks command invoke` runs `kubectl` through Azure's API, not an OpenTofu
  apply.
- **The bootstrap without an `aws` provider block.** `opentofu/bootstrap`
  requires the `aws` provider for its EKS add-ons; OpenTofu configures it even
  when `cloud = "azure"` plans no AWS resource. The root gives it a placeholder
  ([measured](foundations.md#measured)).
- **A `kubernetes_version` that follows the cluster.** The module sets
  `kubernetes_version` from the tfvars with no `ignore_changes`, and the
  `stable` channel moves the cluster on its own. After AKS upgrades a minor,
  the next plan can propose the tfvars value again, a downgrade AKS refuses.
  This follows from the code; no Azure apply has shown it. Before an
  apply, set `kubernetes_version` to the cluster's `major.minor`, read from
  `az aks show --resource-group <rg> --name <cluster> --query currentKubernetesVersion -o tsv`.

## Provider limits

- **Node Auto-Provisioning** refuses Windows node pools and IPv6 clusters, a
  cluster stop, and an outbound type change after creation.
- **BYO CNI**: Microsoft support excludes CNI issues (pod-to-pod traffic, the
  CNI plugin, `kubectl proxy`); nodes and the control plane stay supported.
  NAP under BYO CNI follows the same policy.
- **`pod_cidr`** cannot be set on the cluster under `network_plugin = "none"`:
  `azurerm` accepts it only with `kubenet` or overlay mode. The control plane
  knows no pod range; Cilium's cluster pool is the only one.
- **No `network_policy`** under BYO CNI; Cilium enforces policies.
- **AKS kube-proxy** still runs beside Cilium's kube-proxy replacement: the
  module does not turn it off.
- **Deployment Safeguards** has no `azurerm` attribute in the 4.x series.
- **Maintenance windows** are best effort: AKS can run an urgent patch outside
  them. Each lasts 4 to 24 hours. One configuration shared by several clusters
  of a subscription can cause ARM throttling errors; give each cluster its
  own windows.
- **One non-zonal NAT gateway.** Azure places it in one zone; nodes in the
  other zones reach it across a zone boundary, and lose egress if that zone
  fails.
- **Managed Prometheus and Container Insights** are still created by the
  module, though superseded by
  [SOCLE-03](../../decisions/socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud),
  and billed per GB ingested until removed.

## What the socle does not offer here yet

- **Velero.** `velero` is offered on `aws` only; `kube.velero` is refused at
  plan on `azure` ([AZURE-07](../../decisions/azure.md#azure-07-backup-with-velero)).
- **A Crossplane Azure provider.** `crossplane` installs, but its template
  renders providers for AWS only, so no module gets its Azure identity from it.
- **`kube.keda.services`.** Refused on `azure`. KEDA scalers still work with a
  `TriggerAuthentication` Secret, or an identity bound through
  `podIdentity.azureWorkload` in `values`.
- **external-dns credentials.** On Azure the client creates the
  `external-dns-azure` Secret (`azure.json`); see
  [external-dns](../../catalog/external-dns.md).
- **Deployment Safeguards** ([AZURE-06](../../decisions/azure.md#azure-06-deployment-safeguards-at-baseline-in-enforce-mode)):
  the Kyverno modules are the policy path today.
- **Readers of Azure service metrics, quotas and cost**
  ([AZURE-16](../../decisions/azure.md#azure-16-azure-service-metrics-read-from-outside-the-cluster)).
- **A real-cloud proof.** The foundations and the bootstrap have been planned
  with mocked providers, never applied on a real AKS cluster.
