---
title: Azure decisions
description: The decisions behind the Azure foundations, one per section, each with its status.
sidebar:
  order: 4
---

The decisions behind [`opentofu/azure`](../../opentofu/azure/main.tf): an AKS
Standard cluster with Node Auto-Provisioning, private, with no CNI until the
bootstrap module installs Cilium. Read [AZURE-01](#azure-01-aks-standard-with-node-auto-provisioning-not-automatic)
and [AZURE-10](#azure-10-self-managed-cilium-through-byo-cni) first. The
Kubernetes version policy is the socle's, not this cloud's:
[SOCLE-05](socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n).

## AZURE-01: AKS Standard with Node Auto-Provisioning, not Automatic

**accepted** · 2026-09-15 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`sku_tier`, `node_provisioning_profile`)

**Context.** AKS Automatic and AKS Standard with Node Auto-Provisioning (NAP)
run the same node engine, Karpenter for Azure. Automatic adds a pod-readiness
SLA (99.9 % of qualifying operations in under 5 minutes), forces the `stable`
channel and a policy baseline, and charges a fixed surcharge per vCPU-hour on
top of the node price. Because the surcharge is fixed, it weighs most where
compute is cheapest: +17.5 % on On-Demand, +94.7 % on Spot (France Central
list prices, September 2026). Standard with NAP carries no NAP meter in the
retail price list. On the reference estate (one prod environment 24/7, two UAT
environments 12 h per working day, 12 vCPU / 48 GiB per environment), Standard
with NAP costs $1,060.34 a month and Automatic $1,338.99.

**Decision.** AKS Standard tier, NAP on (`mode = "Auto"`), never Automatic.

**Consequences.** No pod-readiness SLA. The upgrade channel and the support
plan are this module's own hardcoded values ([AZURE-02](#azure-02-the-stable-upgrade-channel-and-one-maintenance-window-per-cluster),
[AZURE-03](#azure-03-no-long-term-support)), not a guarantee Azure enforces.
AKS still needs one node pool: a `system` pool, tainted for critical add-ons
only (`only_critical_addons_enabled`), that NAP never manages. NAP refuses
Windows node pools and IPv6 clusters on any tier, and an outbound type change
after creation. NAP under BYO CNI ([AZURE-10](#azure-10-self-managed-cilium-through-byo-cni))
is allowed by Microsoft's support policy but has never been applied on a real
AKS cluster by the socle.

**Sources.** [AKS Automatic](https://learn.microsoft.com/en-us/azure/aks/intro-aks-automatic) ·
[node auto-provisioning](https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning) ·
[NAP networking, BYO CNI support policy](https://learn.microsoft.com/en-us/azure/aks/node-auto-provisioning-networking) ·
[Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices).

## AZURE-02: The `stable` upgrade channel, and one maintenance window per cluster

**accepted** · 2026-09-14 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`automatic_upgrade_channel`, `maintenance_window_*`), [`opentofu/azure/variables.tf`](../../opentofu/azure/variables.tf)

**Context.** AKS supports a rolling window of three minors. Its channels are
`none`, `patch` (latest patch of the same minor), `stable` (latest patch of
minor N-1) and `rapid` (latest patch of the newest minor). Upgrades run in
planned maintenance windows: `aksManagedAutoUpgradeSchedule` for the
Kubernetes version, `aksManagedNodeOSUpgradeSchedule` for node OS patches.
Windows are best effort: AKS may run an urgent patch outside them. One
maintenance configuration shared by several clusters of a subscription can
cause ARM throttling errors that fail the upgrade.

**Decision.** `automatic_upgrade_channel = "stable"`, hardcoded. Both
windows, `maintenance_window_auto_upgrade` and `maintenance_window_node_os`,
are required inputs with no default, 4 to 24 hours each. Rings come from
staggering the windows per cluster: dev first, staging next, prod last.

**Consequences.** Kubernetes upgrades happen on AKS's clock, inside windows
the client picks; the socle artifact moves on its own. The module sets
`kubernetes_version` with no `ignore_changes`: once AKS has moved a cluster
to a newer minor, the next plan may propose the version written in the
tfvars again.

**Sources.** [Automatic upgrades](https://learn.microsoft.com/en-us/azure/aks/auto-upgrade-cluster) ·
[planned maintenance](https://learn.microsoft.com/en-us/azure/aks/planned-maintenance).

## AZURE-03: No Long-Term Support

**accepted** · 2026-09-14 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`support_plan`)

**Context.** Long-Term Support needs the Premium tier and extends the support
of an aging minor. A cluster on the `stable` channel ([AZURE-02](#azure-02-the-stable-upgrade-channel-and-one-maintenance-window-per-cluster))
is always within one minor of the newest.

**Decision.** `support_plan = "KubernetesOfficial"`, hardcoded. Premium and
LTS are not reachable through the module.

**Consequences.** No Premium charge. A client who must hold a minor beyond
community support has no path through this module.

**Sources.** [Long-term support](https://learn.microsoft.com/en-us/azure/aks/long-term-support) ·
[pricing tiers](https://learn.microsoft.com/en-us/azure/aks/free-standard-pricing-tiers).

## AZURE-04: The storage CSI drivers stay AKS-managed

**accepted** · 2026-09-14 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (no `storage_profile` block)

**Context.** Azure Disk and Azure File CSI drivers are on by default since
Kubernetes 1.21, and in-tree drivers are gone since 1.26. There is no
cross-cloud replacement worth carrying.

**Decision.** The module sets nothing: AKS installs and upgrades both drivers.

**Consequences.** Storage classes are AKS's. The socle neither pins nor
patches the drivers.

**Sources.** [CSI storage drivers on AKS](https://learn.microsoft.com/en-us/azure/aks/csi-storage-drivers).

## AZURE-05: Managed Prometheus and Container Insights

**superseded by [SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud)** · 2026-09-14 · superseded 2026-09-28

**Context.** AKS Standard turns on no metrics or logs pipeline by itself.
Managed Prometheus needs an Azure Monitor workspace and a data collection rule;
Container Insights needs a Log Analytics workspace.

**Decision.** Both on, set by the module.

**Consequences.** The socle now runs one in-cluster monitoring stack on every
cloud. The code still creates both paths: `azurerm_log_analytics_workspace.container_insights`,
`azurerm_monitor_workspace.socle`, the data collection rule and its
association, `oms_agent` and `monitor_metrics` on the cluster. They are billed
until removed.

**Sources.** [Monitor AKS](https://learn.microsoft.com/en-us/azure/aks/monitor-aks) ·
[Azure Monitor pricing](https://azure.microsoft.com/en-us/pricing/details/monitor/).

## AZURE-06: Deployment Safeguards at Baseline, in Enforce mode

**proposed** · 2026-09-15 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (comment above the cluster)

**Context.** Deployment Safeguards is Microsoft's best-practice bundle:
requests and limits set where missing, anti-affinity and topology spread,
`:latest` tags and in-tree storage classes rejected, plus the baseline Pod
Security Standards. Automatic forces it; Standard leaves it off. The
`azurerm` 4.x provider has no attribute for it; the ARM property
(`safeguardsProfile`) is reachable through `azapi` or `az aks safeguards`.

**Decision.** Turn it on at Baseline, Enforce.

**Consequences.** Not built: the cluster sets only `azure_policy_enabled = true`,
which installs the Azure Policy add-on and assigns no policy. Nothing on an
Azure cluster enforces the baseline Pod Security Standards today. Once built,
Velero's node-agent needs its namespace excluded ([AZURE-07](#azure-07-backup-with-velero)).
The catalog's Kyverno modules cover the same ground on every cloud.

**Sources.** [Deployment Safeguards](https://learn.microsoft.com/en-us/azure/aks/deployment-safeguards) ·
[Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards).

## AZURE-07: Backup with Velero

**proposed** · 2026-09-14 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf) (`catalog_clouds`)

**Context.** Velero backs up cluster objects and, through CSI snapshots,
volumes, with no privileged pod. Its node-agent, which takes file-level
backups restorable outside the region, needs privileged containers and
`hostPath`.

**Decision.** Velero on AKS, CSI-snapshot mode by default.

**Consequences.** Not built: the catalog offers `velero` on `aws` only, and
`kube.velero` is refused at plan on `azure`.

**Sources.** [Velero node-agent](https://velero.io/docs/main/supported-configmaps/node-agent-configmap/) ·
[the velero catalog module](../catalog/velero.md).

## AZURE-08: Entra Workload ID for every workload that calls Azure

**accepted** · 2026-09-14 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`workload_identity_enabled`, `oidc_issuer_enabled`)

**Context.** Standard does not turn Workload ID on. `oidc_issuer_enabled`
defaults to false on the `azurerm` 4.x series.

**Decision.** Both attributes set to true. A workload that needs Azure gets a
federated Entra identity bound to its Kubernetes service account; no client
secret.

**Consequences.** The foundations create no identity for any workload: a
federated credential needs a service account that exists only once the
catalog runs. The issuer is the `oidc_issuer_url` output. The actively
developed Crossplane provider is the Upjet-generated `provider-family-azure`;
the socle does not install it yet.

**Sources.** [Workload ID on AKS](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview) ·
[provider-upjet-azure](https://github.com/crossplane-contrib/provider-upjet-azure).

## AZURE-09: No customer-managed keys

**accepted** · 2026-09-21 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`#trivy:ignore:AZU-0067`, no `disk_encryption_set_id`, no `key_management_service`)

**Context.** Azure encrypts etcd, OS disks and logs at rest with
Microsoft-managed keys. KMS etcd encryption needs a user-assigned identity
granted Key Vault access before the cluster exists; the module uses a
system-assigned one. A customer key on Log Analytics needs a dedicated cluster
on a commitment tier, 100 GB a day minimum. A disk encryption set needs the
client's own Key Vault.

**Decision.** Microsoft-managed keys everywhere. A customer-managed key is the
client's compliance decision on their own Key Vault.

**Consequences.** No Key Vault, no extra identity, no commitment tier. A client
who needs CMK changes the cluster's identity model, outside this module.

**Sources.** [KMS etcd encryption](https://learn.microsoft.com/en-us/azure/aks/use-kms-etcd-encryption) ·
[Log Analytics customer-managed keys](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/customer-managed-keys).

## AZURE-10: Self-managed Cilium through BYO CNI

**accepted** · 2026-09-15 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`network_plugin = "none"`), [`opentofu/bootstrap/cilium.tf`](../../opentofu/bootstrap/cilium.tf)

**Context.** The managed "Azure CNI powered by Cilium" locks Cilium's
configuration, and puts FQDN filtering, L7 policies, encryption and flow
observability behind Advanced Container Networking Services, billed per node.
BYO CNI (`network_plugin = "none"`) gives the full open-source Cilium. On a BYO
CNI cluster Microsoft support excludes CNI issues (pod-to-pod traffic, the
plugin itself); nodes and the control plane stay supported.

**Decision.** `network_plugin = "none"`. The bootstrap module installs Cilium
by Helm before Flux ([SOCLE-02](socle.md#socle-02-cilium-and-coredns-before-flux-from-the-bootstrap)),
with `aksbyocni.enabled`, kube-proxy replacement, and cluster-pool IPAM over
the foundations' `pod_cidr`.

**Consequences.** Nodes stay `NotReady` until Cilium runs. Pod addresses come
from Cilium, not from the VNet, so the node subnet is sized for nodes only.
`azurerm` refuses `pod_cidr` under `network_plugin = "none"`, so the range is
not set on the cluster: it reaches Cilium through the `pod_cidr` output. No
`network_policy` value exists under BYO CNI (`#trivy:ignore:AZU-0043`); Cilium
enforces policies. AKS still runs its own kube-proxy beside Cilium's
replacement.

**Sources.** [BYO CNI](https://learn.microsoft.com/en-us/azure/aks/use-byo-cni) ·
[Azure CNI powered by Cilium](https://learn.microsoft.com/en-us/azure/aks/azure-cni-powered-by-cilium) ·
[ACNS pricing](https://azure.microsoft.com/en-us/pricing/details/advanced-container-networking-services/) ·
[Cilium before Flux](../architecture/cilium-before-flux.md).

## AZURE-11: Gateway API through the application routing add-on

**superseded by [GATEWAY-API-02](gateway-api.md#gateway-api-02-shared-public-and-private-gateways-on-cilium)** · 2026-09-15

**Context.** The application routing add-on serves Gateway API from an
in-cluster Istio. Application Gateway for Containers costs about $134 a month
per Gateway before capacity units.

**Decision.** Gateway API through the application routing add-on;
Application Gateway for Containers as a catalog option.

**Consequences.** Never built. The shared Gateways run on the socle's Cilium,
on the `cilium` GatewayClass, as on AWS.

**Sources.** [Application routing Gateway API](https://learn.microsoft.com/en-us/azure/aks/app-routing-gateway-api) ·
[Application Gateway for Containers](https://learn.microsoft.com/en-us/azure/application-gateway/for-containers/overview).

## AZURE-12: A private cluster, with no public FQDN

**accepted** · 2026-09-15 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`private_cluster_enabled`, `private_dns_zone_id`, `private_cluster_public_fqdn_enabled`)

**Context.** Nodes sit in a private subnet behind NAT; a public API endpoint
would be the one public surface left. A private cluster puts the API server
behind a private endpoint (about $7.30 a month plus $0.01/GB, September 2026)
with an AKS-managed private DNS zone. Authorized IP ranges apply only to a
public endpoint.

**Decision.** Private cluster, public FQDN disabled, system-managed private
DNS zone, all hardcoded.

**Consequences.** The API server answers only from the VNet or a network
connected to it: VPN, ExpressRoute, peering, Bastion. The machine that runs
the bootstrap module's Helm releases needs that reach, and DNS resolution of
the private zone. `cluster_endpoint` is the private FQDN.

**Sources.** [Private AKS clusters](https://learn.microsoft.com/en-us/azure/aks/private-clusters).

## AZURE-13: One VNet, one node subnet, one NAT gateway

**accepted** · 2026-09-15 · [`opentofu/azure/network.tf`](../../opentofu/azure/network.tf)

**Context.** Azure subnets span every zone of a region, so one subnet and one
gateway can serve nodes in every zone. Pods take no VNet address
([AZURE-10](#azure-10-self-managed-cilium-through-byo-cni)). A Service of type
LoadBalancer puts its public IP on the Standard Load Balancer, not on a public
subnet.

**Decision.** One VNet (`vnet_cidr`, default `10.0.0.0/16`), one node subnet
covering it, one NAT gateway with one static public IP, `outbound_type =
"userAssignedNATGateway"`. A client who already has a network passes
`create_vnet = false` with `vnet_name` and `node_subnet_id`.

**Consequences.** The gateway is non-zonal: Azure places it in one zone, and
traffic from the other zones crosses a zone boundary to reach it, at no charge
only because Azure does not bill intra-region inter-zone transfer. A zone
outage there stops egress for every node. NAT gateway: $0.045/hour ($32.85 a
month) plus $0.045/GB, September 2026.

**Sources.** [NAT gateway reliability](https://learn.microsoft.com/en-us/azure/reliability/reliability-nat-gateway) ·
[availability zones](https://learn.microsoft.com/en-us/azure/reliability/availability-zones-overview).

## AZURE-14: Microsoft Defender for Containers as a catalog option

**superseded by [AZURE-15](#azure-15-defender-for-containers-is-the-clients-subscription-decision)** · 2026-09-15

**Context.** Defender for Containers is a Defender for Cloud plan billed per
vCore ($0.00941/vCore/hour, about $247 a month on a 36-vCPU estate, September
2026), separate from the AKS tier.

**Decision.** Off by default, exposed as a module variable per client.

**Consequences.** Never built: the plan is a subscription setting, not a
cluster one.

**Sources.** [Defender for Containers](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-deployment-overview).

## AZURE-15: Defender for Containers is the client's subscription decision

**accepted** · 2026-09-15 · [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (comment above the cluster)

**Context.** Defender for Containers is enabled with
`azurerm_security_center_subscription_pricing`, one per subscription. Several
clusters, and the client's other workloads, share it.

**Decision.** No resource and no variable: the client turns the plan on or off
on their subscription.

**Consequences.** The module cannot turn Defender on, and does not turn it off.

**Sources.** [Defender for Containers](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-deployment-overview).

## AZURE-16: Azure service metrics read from outside the cluster

**proposed** · 2026-09-15

**Context.** Managed services around a cluster (SQL Database, Storage, Service
Bus, Cache for Redis) publish platform metrics for free, kept 90 days. Reading
them costs $0.01 per 1,000 calls, and `metrics:getBatch` reads 50 resources
per call. Routing the same signal through Log Analytics costs $2.76/GB ingested
(Basic Logs $0.625/GB), September 2026. Cost Management Exports write the bill
to a storage account for free. The `Microsoft.Quota` usages API reports usage
against limits for free.

**Decision.** Read platform metrics through `metrics:getBatch` every 300 s,
and quotas through `Microsoft.Quota`; never through Log Analytics. Cost
attribution comes from Cost Management Exports to the client's storage
account.

**Consequences.** Nothing built: the foundations create no export, no reader
identity and no variable for it. The shared design is in
[observability](../architecture/observability.md).

**Sources.** [Metrics batch API](https://learn.microsoft.com/en-us/rest/api/monitor/metrics-batch/batch) ·
[Azure Monitor pricing](https://azure.microsoft.com/en-us/pricing/details/monitor/) ·
[Cost Management Exports](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-improved-exports) ·
[quota usages API](https://learn.microsoft.com/en-us/rest/api/quota/usages/list).
