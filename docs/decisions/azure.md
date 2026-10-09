---
title: Azure decisions
description: The decisions behind the Azure foundations, one per section, each with its status.
sidebar:
  order: 4
---

The decisions behind [`opentofu/azure`](../../opentofu/azure/main.tf): a private
AKS Standard cluster with Node Auto-Provisioning and no CNI until the bootstrap
installs Cilium. Read [AZURE-01](#azure-01-aks-standard-with-node-auto-provisioning-not-automatic)
and [AZURE-10](#azure-10-self-managed-cilium-through-byo-cni) first; the version
policy is [SOCLE-05](socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n).

## AZURE-01: AKS Standard with Node Auto-Provisioning, not Automatic

**accepted** · 2026-09-15 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`sku_tier`, `node_provisioning_profile`)

**Decision.** AKS Standard tier, NAP on (`mode = "Auto"`), never Automatic.

**Context.** Both run the same node engine, Karpenter for Azure. Automatic adds
a pod-readiness SLA and a fixed per-vCPU-hour surcharge: +17.5 % on On-Demand,
+94.7 % on Spot (France Central, September 2026); the reference estate costs
$1,060.34 a month on Standard with NAP against $1,338.99 on Automatic.

**Consequences.** No pod-readiness SLA; the channel and support plan are this
module's choices ([AZURE-02](#azure-02-the-stable-upgrade-channel-and-one-maintenance-window-per-cluster),
[AZURE-03](#azure-03-no-long-term-support)). A tainted `system` pool stays, which
NAP never manages. NAP refuses Windows and IPv6; NAP under BYO CNI is supported
but never applied on a real AKS cluster by the socle.

**Sources.** [AKS Automatic](https://learn.microsoft.com/en-us/azure/aks/intro-aks-automatic) · [node auto-provisioning](https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning) · [NAP networking](https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning-networking) · [Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices).

## AZURE-02: The `stable` upgrade channel, and one maintenance window per cluster

**accepted** · 2026-09-14 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`automatic_upgrade_channel`, `maintenance_window_*`), [`opentofu/azure/variables.tf`](../../opentofu/azure/variables.tf)

**Decision.** `automatic_upgrade_channel = "stable"`, hardcoded (latest patch of
minor N-1). `maintenance_window_auto_upgrade` and `maintenance_window_node_os`
are required, 4 to 24 hours each; rings come from staggering them per cluster.

**Context.** AKS upgrades inside planned windows, best effort. One maintenance
configuration shared by several clusters can cause ARM throttling that fails the
upgrade.

**Consequences.** Upgrades run on AKS's clock, inside the client's windows.
`kubernetes_version` has no `ignore_changes`: after AKS moves a minor, the next
plan may propose the tfvars version again.

**Sources.** [Automatic upgrades](https://learn.microsoft.com/en-us/azure/aks/auto-upgrade-cluster) · [planned maintenance](https://learn.microsoft.com/en-us/azure/aks/planned-maintenance).

## AZURE-03: No Long-Term Support

**accepted** · 2026-09-14 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`support_plan`)

**Decision.** `support_plan = "KubernetesOfficial"`, hardcoded; Premium and LTS
are not reachable through the module.

**Context.** LTS needs the Premium tier and extends an aging minor; a `stable`
cluster is always within one minor of the newest.

**Consequences.** No Premium charge. A client who must hold a minor beyond
community support has no path through this module.

**Sources.** [Long-term support](https://learn.microsoft.com/en-us/azure/aks/long-term-support) · [pricing tiers](https://learn.microsoft.com/en-us/azure/aks/free-standard-pricing-tiers).

## AZURE-04: The storage CSI drivers stay AKS-managed

**accepted** · 2026-09-14 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (no `storage_profile` block)

**Decision.** The module sets nothing: AKS installs and upgrades the Azure Disk
and Azure File CSI drivers.

**Context.** Both are on by default since 1.21 and in-tree drivers are gone since
1.26; no cross-cloud replacement is worth carrying.

**Consequences.** Storage classes are AKS's; the socle neither pins nor patches
the drivers.

**Sources.** [CSI storage drivers on AKS](https://learn.microsoft.com/en-us/azure/aks/csi-storage-drivers).

## AZURE-05: Managed Prometheus and Container Insights

**superseded by [SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud)** · 2026-09-14 · superseded 2026-09-28

**Decision.** Both on, set by the module.

**Context.** AKS Standard turns on no metrics or logs pipeline; Managed
Prometheus needs an Azure Monitor workspace and a data collection rule,
Container Insights a Log Analytics workspace.

**Consequences.** The code still creates both paths (the two workspaces, the
data collection rule and its association, `oms_agent`, `monitor_metrics`); they
are billed until removed.

**Sources.** [Monitor AKS](https://learn.microsoft.com/en-us/azure/aks/monitor-aks) · [Azure Monitor pricing](https://azure.microsoft.com/en-us/pricing/details/monitor/).

## AZURE-06: Deployment Safeguards at Baseline, in Enforce mode

**proposed** · 2026-09-15 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (comment above the cluster)

**Decision.** Turn on Deployment Safeguards at Baseline, Enforce.

**Context.** It is Microsoft's best-practice bundle plus the baseline Pod
Security Standards; Automatic forces it, Standard leaves it off. `azurerm` 4.x
has no attribute for it, only `azapi` or `az aks safeguards`.

**Consequences.** Not built: only `azure_policy_enabled = true` is set, which
assigns no policy, so nothing enforces the baseline PSS on Azure today. Velero's
node-agent namespace will need excluding ([AZURE-07](#azure-07-backup-with-velero)).

**Sources.** [Deployment Safeguards](https://learn.microsoft.com/en-us/azure/aks/deployment-safeguards) · [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards).

## AZURE-07: Backup with Velero

**proposed** · 2026-09-14 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf) (`catalog_clouds`)

**Decision.** Velero on AKS, CSI-snapshot mode by default.

**Context.** CSI snapshots need no privileged pod; the node-agent, for
file-level backups restorable outside the region, needs privileged containers
and `hostPath`.

**Consequences.** Not built: `velero` is offered on `aws` only, and
`kube.velero` is refused at plan on `azure`.

**Sources.** [Velero node-agent](https://velero.io/docs/main/supported-configmaps/node-agent-configmap/) · [the velero catalog module](../catalog/velero.md).

## AZURE-08: Entra Workload ID for every workload that calls Azure

**accepted** · 2026-09-14 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`workload_identity_enabled`, `oidc_issuer_enabled`)

**Decision.** `workload_identity_enabled` and `oidc_issuer_enabled` set to true.
A workload that needs Azure gets a federated Entra identity bound to its service
account; no client secret.

**Context.** Standard does not turn Workload ID on, and `oidc_issuer_enabled`
defaults to false on `azurerm` 4.x.

**Consequences.** The foundations create no workload identity: the service
account exists only once the catalog runs. The issuer is the `oidc_issuer_url`
output. `provider-family-azure` is not installed yet.

**Sources.** [Workload ID on AKS](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview) · [provider-upjet-azure](https://github.com/crossplane-contrib/provider-upjet-azure).

## AZURE-09: No customer-managed keys

**accepted** · 2026-09-21 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`#trivy:ignore:AZU-0067`, no `disk_encryption_set_id`, no `key_management_service`)

**Decision.** Microsoft-managed keys everywhere; a customer-managed key is the
client's compliance decision on their own Key Vault.

**Context.** KMS etcd encryption needs a user-assigned identity granted Key
Vault access before the cluster exists (the module uses a system-assigned one);
CMK on Log Analytics needs a dedicated cluster at 100 GB a day minimum.

**Consequences.** No Key Vault, no extra identity, no commitment tier. CMK means
changing the cluster's identity model, outside this module.

**Sources.** [KMS etcd encryption](https://learn.microsoft.com/en-us/azure/aks/use-kms-etcd-encryption) · [Log Analytics customer-managed keys](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/customer-managed-keys).

## AZURE-10: Self-managed Cilium through BYO CNI

**accepted** · 2026-09-15 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`network_plugin = "none"`), [`opentofu/bootstrap/cilium.tf`](../../opentofu/bootstrap/cilium.tf)

**Decision.** `network_plugin = "none"`; the bootstrap installs Cilium by Helm
before Flux ([SOCLE-02](socle.md#socle-02-cilium-and-coredns-before-flux-from-the-bootstrap)),
with `aksbyocni.enabled`, kube-proxy replacement and cluster-pool IPAM over `pod_cidr`.

**Context.** The managed Cilium locks its configuration and bills FQDN, L7,
encryption and flow features per node (ACNS). Under BYO CNI Microsoft support
excludes CNI issues only.

**Consequences.** Nodes stay `NotReady` until Cilium runs; the subnet is sized
for nodes only. `pod_cidr` reaches Cilium through an output, since `azurerm`
refuses it on the cluster; no `network_policy` (`#trivy:ignore:AZU-0043`). AKS
still runs its own kube-proxy.

**Sources.** [BYO CNI](https://learn.microsoft.com/en-us/azure/aks/use-byo-cni) · [Azure CNI powered by Cilium](https://learn.microsoft.com/en-us/azure/aks/azure-cni-powered-by-cilium) · [ACNS pricing](https://azure.microsoft.com/en-us/pricing/details/advanced-container-networking-services/) · [Cilium before Flux](../architecture/cilium-before-flux.md).

## AZURE-11: Gateway API through the application routing add-on

**superseded by [GATEWAY-API-02](gateway-api.md#gateway-api-02-shared-public-and-private-gateways-on-cilium)** · 2026-09-15

**Decision.** Gateway API through the application routing add-on (an
in-cluster Istio); Application Gateway for Containers as a catalog option.

**Context.** Application Gateway for Containers costs about $134 a month per
Gateway before capacity units.

**Consequences.** Never built. The shared Gateways run on the socle's Cilium,
`cilium` GatewayClass, as on AWS.

**Sources.** [Application routing Gateway API](https://learn.microsoft.com/en-us/azure/aks/app-routing-gateway-api) · [Application Gateway for Containers](https://learn.microsoft.com/en-us/azure/application-gateway/for-containers/overview).

## AZURE-12: A private cluster, with no public FQDN

**accepted** · 2026-09-15 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`private_cluster_enabled`, `private_dns_zone_id`, `private_cluster_public_fqdn_enabled`)

**Decision.** Private cluster, public FQDN disabled, system-managed private DNS
zone, all hardcoded.

**Context.** Nodes sit behind NAT; a public API endpoint would be the last
public surface. The private endpoint costs about $7.30 a month plus $0.01/GB
(September 2026); authorized IP ranges apply only to a public one.

**Consequences.** The API answers only from the VNet or a connected network
(VPN, ExpressRoute, peering, Bastion); the bootstrap's runner needs that reach
and the private DNS zone. `cluster_endpoint` is the private FQDN.

**Sources.** [Private AKS clusters](https://learn.microsoft.com/en-us/azure/aks/private-clusters).

## AZURE-13: One VNet, one node subnet, one NAT gateway

**accepted** · 2026-09-15 · [`opentofu/azure/network.tf`](../../opentofu/azure/network.tf)

**Decision.** One VNet (`vnet_cidr`, default `10.0.0.0/16`), one node subnet,
one NAT gateway with one static IP, `outbound_type = "userAssignedNATGateway"`.
An existing network: `create_vnet = false` with `vnet_name` and `node_subnet_id`.

**Context.** Azure subnets span every zone of a region, pods take no VNet
address ([AZURE-10](#azure-10-self-managed-cilium-through-byo-cni)), and
LoadBalancer IPs sit on the Standard Load Balancer.

**Consequences.** The gateway is non-zonal: a zone outage there stops egress
for every node. $0.045/hour ($32.85 a month) plus $0.045/GB, September 2026.

**Sources.** [NAT gateway reliability](https://learn.microsoft.com/en-us/azure/reliability/reliability-nat-gateway) · [availability zones](https://learn.microsoft.com/en-us/azure/reliability/availability-zones-overview).

## AZURE-14: Microsoft Defender for Containers as a catalog option

**superseded by [AZURE-15](#azure-15-defender-for-containers-is-the-clients-subscription-decision)** · 2026-09-15

**Decision.** Off by default, exposed as a module variable per client.

**Context.** Defender for Containers is billed per vCore, about $247 a month on
a 36-vCPU estate (September 2026), separate from the AKS tier.

**Consequences.** Never built: the plan is a subscription setting, not a
cluster one.

**Sources.** [Defender for Containers](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-deployment-overview).

## AZURE-15: Defender for Containers is the client's subscription decision

**accepted** · 2026-09-15 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (comment above the cluster)

**Decision.** No resource and no variable: the client turns the plan on or off
on their subscription.

**Context.** `azurerm_security_center_subscription_pricing` is one per
subscription, shared by several clusters and the client's other workloads.

**Consequences.** The module cannot turn Defender on, and does not turn it off.

**Sources.** [Defender for Containers](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-deployment-overview).

## AZURE-16: Azure service metrics read from outside the cluster

**proposed** · 2026-09-15

**Decision.** Platform metrics through `metrics:getBatch` every 300 s, quotas
through `Microsoft.Quota`, never through Log Analytics; cost from Cost
Management Exports to the client's storage account.

**Context.** Platform metrics are free and kept 90 days; reading costs $0.01 per
1,000 calls of 50 resources, against $2.76/GB ingested through Log Analytics
(September 2026). Exports and the quota API are free.

**Consequences.** Nothing built: no export, reader identity or variable. The
shared design is in [observability](../architecture/observability.md).

**Sources.** [Metrics batch API](https://learn.microsoft.com/en-us/rest/api/monitor/metrics-batch/batch) · [Azure Monitor pricing](https://azure.microsoft.com/en-us/pricing/details/monitor/) · [Cost Management Exports](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-improved-exports) · [quota usages API](https://learn.microsoft.com/en-us/rest/api/quota/usages/list).
