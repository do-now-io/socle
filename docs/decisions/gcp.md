---
title: GCP decisions
description: The decisions behind the GCP foundations, one per section, each with its status.
sidebar:
  order: 3
---

One GKE Autopilot cluster per environment, in its own project, private nodes,
DNS endpoint, Cloud NAT. Prices are us-central1 list prices in USD, read on
8 September 2026, for a reference estate of three clusters (Pod requests: prod
20 vCPU / 40 GiB, staging 8 / 16, dev 4 / 8). Version policy:
[SOCLE-05](socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n).

## GCP-01: Autopilot only, no cluster mode option

**accepted** · 2026-09-08 · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf)

**Decision.** Every cluster is Autopilot; `enable_autopilot = true` is a
literal, not a variable.

**Context.** The mode is fixed at creation. Autopilot bills Pod requests and
enforces Workload Identity, Shielded nodes, Dataplane V2 and network policy.
The estate costs $1,488 a month on Autopilot against $1,668 on Standard with
the headroom rollouts need, plus 15 to 42 hours a year attending node upgrades.

**Consequences.** One cluster shape to cover and test. The client gives up
privileged Pods outside Google's allowlists, writable `hostPath`, node SSH,
any CNI but Dataplane V2 and the choice to upgrade; every Pod is billed at
least 250 mCPU / 512 MiB ([GCP limits](../clouds/gcp/limits.md)). Three
scanner findings that cannot apply on Autopilot are ignored in `cluster.tf`.

**Sources.** [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing) · [Autopilot and Standard comparison](https://cloud.google.com/kubernetes-engine/docs/resources/autopilot-standard-feature-comparison) · [Autopilot resource requests](https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests).

## GCP-02: Regular release channel, rings ordered by the maintenance window

**accepted** · 2026-09-08 · [`opentofu/gcp/variables.tf`](../../opentofu/gcp/variables.tf) (`release_channel`, `maintenance_window`, `maintenance_exclusions`) · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) (`release_channel`, `maintenance_policy`)

**Decision.** One channel estate-wide, `REGULAR` by default (`EXTENDED` refused
at plan). The maintenance window is required, no default; its weekday orders
the rings: dev Tuesday, staging Wednesday, prod Saturday. Exclusions are the
brake, empty by default.

**Context.** A cluster upgrades at least twice a year. Pinning with
`NO_MINOR_UPGRADES` would make the pipeline own the full support clock;
Extended is forbidden on Autopilot.

**Consequences.** Google owns the version clock, the socle release the
artifact clock. The module validates the window and exclusion limits; GKE's
48-hours-per-92-days rule is checked by GKE at apply. Upgrade notifications go
to a Pub/Sub topic the module creates.

**Sources.** [Release channels](https://cloud.google.com/kubernetes-engine/docs/concepts/release-channels) · [maintenance windows and exclusions](https://cloud.google.com/kubernetes-engine/docs/concepts/maintenance-windows-and-exclusions).

## GCP-03: Only the free system metrics, Auto-Monitoring refused

**accepted** · 2026-09-08 · [`opentofu/gcp/variables.tf`](../../opentofu/gcp/variables.tf) (`logging_components`, `monitoring_components`) · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) (`logging_config`, `monitoring_config`)

**Decision.** `monitoring_components` defaults to `SYSTEM_COMPONENTS` alone;
billed components are accepted, never defaulted. `logging_components`
defaults to system and workloads. Auto-Monitoring has no variable.

**Context.** System metrics are free; every other component is billed at
$0.158 per month per sample per second, and Auto-Monitoring starts billed
ingestion without the client deciding.

**Consequences.** No per-sample charge unless the client adds a component.
Workload logs cost about $20 a month per cluster at 30 GiB; drop `WORKLOADS`
once logs are collected in-cluster.

**Sources.** [Observability pricing](https://cloud.google.com/stackdriver/pricing) · [GKE metrics](https://cloud.google.com/stackdriver/docs/solutions/gke/managing-metrics).

## GCP-04: Workload metrics on Managed Service for Prometheus

**superseded by [SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud)** · 2026-09-08, superseded 2026-09-28 · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) (`managed_prometheus`)

**Decision.** Workload metrics were to go to Managed Service for Prometheus,
with a samples-per-second budget on the monitoring module.

**Context.** Filtered as Google recommends, about 300 samples/s cost $47 a
month per cluster, against $134 self-hosted; the crossover was about 850
samples/s.

**Consequences.** SOCLE-03 replaced this with one in-cluster stack on every
cloud. `managed_prometheus` is still enabled, and nothing sends it samples.

**Sources.** [Prometheus cost controls](https://cloud.google.com/stackdriver/docs/managed-prometheus/cost-controls) · [#43](https://github.com/do-now-io/socle/issues/43).

## GCP-05: Velero by default, Backup for GKE as a priced option

**proposed** · 2026-09-08 · [`opentofu/gcp/variables.tf`](../../opentofu/gcp/variables.tf) (`backup_agent_enabled`) · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) (`addons_config`) · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf) (`catalog_clouds`)

**Decision.** Velero is the backup, one restore procedure on four clouds;
Backup for GKE is an opt-in.

**Context.** On the reference estate Velero costs about $90 a month, Backup
for GKE $297. Autopilot blocks Velero's node-agent, so neither gives a
file-level copy of volume data.

**Consequences.** Built: the Backup for GKE agent, off by default. Not built:
`velero` is offered on aws only, so a GCP cluster has no backup by default.

**Sources.** [Backup for GKE](https://cloud.google.com/kubernetes-engine/docs/add-on/backup-for-gke/concepts/backup-for-gke) · [Velero file system backup](https://velero.io/docs/main/file-system-backup/).

## GCP-06: Workload Identity Federation, a Google service account per Kubernetes service account

**accepted** · 2026-09-08 · [`opentofu/gcp/main.tf`](../../opentofu/gcp/main.tf) (`workload_identity_pool`) · [`opentofu/gcp/iam.tf`](../../opentofu/gcp/iam.tf) · [`opentofu/gcp/outputs.tf`](../../opentofu/gcp/outputs.tf) · [`oci/catalog/external-dns/resourceset.yaml`](../../oci/catalog/external-dns/resourceset.yaml)

**Decision.** A workload gets a Google service account bound to its
Kubernetes service account, or roles on its federated principal. The module
outputs the pool and principal prefix; the layer owning the Kubernetes
objects makes the binding.

**Context.** Autopilot enforces Workload Identity; the principal is built
from project, namespace and service account, not the cluster.

**Consequences.** No key is ever issued. Two clusters in one project share
principals, so isolation is one project per environment
([prerequisites](../clouds/gcp/prerequisites.md#account)). Module cloud
access: [SOCLE-04](socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change).

**Sources.** [Workload Identity Federation for GKE](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity).

## GCP-07: Dataplane V2 and plain NetworkPolicy

**accepted** · 2026-09-08 · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) · [`opentofu/bootstrap/cilium.tf`](../../opentofu/bootstrap/cilium.tf)

**Decision.** Dataplane V2 as Autopilot configures it; catalog modules write
plain Kubernetes NetworkPolicy. FQDN and L7 policies are not a default.

**Context.** Autopilot blocks what a self-managed Cilium needs (privileged
DaemonSets, custom eBPF). Dataplane V2 lacks L7 policy at scale, cluster
mesh and egress gateway; FQDN policy is a GKE alpha CRD.

**Consequences.** The bootstrap refuses its `cilium` variable on gcp
([SOCLE-02](socle.md#socle-02-cilium-and-coredns-before-flux-from-the-bootstrap)).
No CNI variable; Hubble is not offered.

**Sources.** [Dataplane V2](https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2) · [FQDN network policies](https://cloud.google.com/kubernetes-engine/docs/how-to/fqdn-network-policies).

## GCP-08: Exposure through GKE's Gateway controller

**accepted** · 2026-09-08 · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) (`gateway_api_config`) · [`opentofu/gcp/variables.tf`](../../opentofu/gcp/variables.tf) (`gateway_api_enabled`) · [`opentofu/bootstrap/main.tf`](../../opentofu/bootstrap/main.tf) (`gateway_class_name`) · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf) (`catalog_clouds`)

**Decision.** GKE's managed controller, standard channel
(`gateway_api_enabled = true`); the bootstrap hands the catalog the class
`gke-l7-global-external-managed`. Ingress is not used for new exposure.

**Context.** GKE runs the data plane and upgrades the CRDs itself. An
in-cluster Envoy would cost about $98 a month per cluster against $18 for a
managed load balancer.

**Consequences.** `gateway_api` is not offered on gcp, so the shared Gateways
of [GATEWAY-API-02](gateway-api.md#gateway-api-02-shared-public-and-private-gateways-on-cilium)
are not created here. The module also creates the proxy-only subnetwork
regional classes need (GCP-09).

**Sources.** [Gateway API on GKE](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api) · [proxy-only subnets](https://cloud.google.com/load-balancing/docs/proxy-only-subnets).

## GCP-09: Private nodes, a DNS endpoint, and a sized reference network

**accepted** · 2026-09-08 · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) · [`opentofu/gcp/network.tf`](../../opentofu/gcp/network.tf) · [`opentofu/gcp/variables.tf`](../../opentofu/gcp/variables.tf)

**Decision.** Private nodes, Cloud NAT and Private Google Access; the DNS
endpoint is the only access path, authorised by IAM. One subnetwork per
cluster: nodes `10.0.0.0/22`, Pods `10.4.0.0/16` (`/17` or larger enforced),
proxy-only `10.8.0.0/23`, no Services range. Auto IPAM refused.

**Context.** Autopilot nodes are public by default. Authorized networks apply
only to IP endpoints and need rewriting on every address change. The Pod range
cannot change after creation; Auto IPAM was in Preview.

**Consequences.** IAM is the only gate to the control plane; a network
boundary is VPC Service Controls. The plan refuses private nodes without NAT.
A Shared VPC works with `create_subnetwork = false`. The network costs about
$96 a month on the reference estate.

**Sources.** [Network isolation](https://cloud.google.com/kubernetes-engine/docs/concepts/network-isolation) · [VPC-native clusters](https://cloud.google.com/kubernetes-engine/docs/concepts/alias-ips) · [Cloud NAT pricing](https://cloud.google.com/nat/pricing).

## GCP-10: Subnet flow logs on, at half sampling over ten minutes

**accepted** · 2026-09-15 · [`opentofu/gcp/network.tf`](../../opentofu/gcp/network.tf) (`log_config`) · [`opentofu/gcp/variables.tf`](../../opentofu/gcp/variables.tf) (`subnet_flow_logs_enabled`)

**Decision.** Flow logs on the cluster subnetwork by default: sampling 0.5,
10-minute aggregation, all metadata. None on the proxy-only subnetwork.

**Context.** Flow logs are the only record of which address talked to which;
they are billed at $0.25/GiB.

**Consequences.** About a dollar a month per cluster;
`subnet_flow_logs_enabled = false` turns them off.

**Sources.** [VPC flow logs](https://cloud.google.com/vpc/docs/flow-logs) · [VPC network pricing](https://cloud.google.com/vpc/network-pricing).

## GCP-11: Service metrics read every 300 s, Cloud Monitoring alert policies refused

**proposed** · 2026-09-08 · [`opentofu/gcp/iam.tf`](../../opentofu/gcp/iam.tf) (`observability_reader`)

**Decision.** A `stackdriver_exporter` reads service metrics every 300 s for
the socle's monitoring stack. Alerting is the socle's; no Cloud Monitoring
alert policy, dashboard or uptime check.

**Context.** Reading metrics out is billed per series since October 2025:
about 800 service series cost $3.00 a month at 300 s, $17.02 at 60 s. Alert
policies become billed on 1 September 2027 and would split alerting across
clouds.

**Consequences.** Built: `observability_reader_members` grants
`roles/monitoring.viewer` to federated principals. Not built: the exporter.

**Sources.** [Observability pricing](https://cloud.google.com/stackdriver/pricing) · [quota metrics](https://cloud.google.com/monitoring/alerts/using-quota-metrics).

## GCP-12: Cost attribution through the detailed billing export

**accepted** · 2026-09-08 · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) (`cost_management_config`) · [`opentofu/gcp/observability.tf`](../../opentofu/gcp/observability.tf) (`billing_export`) · [`opentofu/gcp/variables.tf`](../../opentofu/gcp/variables.tf)

**Decision.** GKE cost allocation on from creation. With
`billing_export_dataset_id` set, the module creates the BigQuery dataset; a
human links the billing account to it. FOCUS refused.

**Context.** Only the detailed export carries GKE's namespace and workload
labels; allocation does not backfill. The export has no API, Terraform
resource or `gcloud` command. FOCUS was in Preview.

**Consequences.** The export is free; data is hours to five days late. The
link is the one GCP step no apply finishes
([limits](../clouds/gcp/limits.md#what-no-apply-can-finish)). A destroy keeps
the cost data.

**Sources.** [Billing export](https://cloud.google.com/billing/docs/how-to/export-data-bigquery) · [GKE cost allocation](https://cloud.google.com/kubernetes-engine/docs/how-to/cost-allocations) · [no Terraform resource](https://github.com/hashicorp/terraform-provider-google/issues/4848).

## GCP-13: Crossplane, not Config Connector

**proposed** · 2026-09-15 · [`oci/catalog/crossplane/resourceset.yaml`](../../oci/catalog/crossplane/resourceset.yaml)

**Decision.** No Config Connector toggle; application infrastructure on GCP
arrives through Crossplane.

**Context.** Config Connector's add-on is Standard-only and Google
discourages it in production; the socle uses Crossplane on every cloud.

**Consequences.** crossplane renders AWS providers only, so on GCP nothing
provisions cloud resources from the cluster yet, and modules needing a cloud
role (`kube.keda.services`) are aws-only.

**Sources.** [Config Connector](https://cloud.google.com/config-connector/docs/overview).
