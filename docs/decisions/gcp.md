---
title: GCP decisions
description: The decisions behind the GCP foundations, one per section, each with its status.
sidebar:
  order: 3
---

The GCP foundations build one GKE Autopilot cluster per environment, in its
own project, with private nodes, a DNS-based control plane endpoint and
Cloud NAT. Two decisions shape everything else: the cluster is Autopilot and
nothing else ([GCP-01](#gcp-01-autopilot-only-no-cluster-mode-option)), and
Google moves the Kubernetes version while the maintenance window orders the
rings ([GCP-02](#gcp-02-regular-release-channel-rings-ordered-by-the-maintenance-window)).
The estate-wide version policy is
[SOCLE-05](socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n).

Prices are us-central1 list prices, in USD, read on 8 September 2026.
Autopilot rates are not published per region. The reference estate is three
clusters: prod with 20 vCPU / 40 GiB of Pod requests, staging 8 / 16, dev
4 / 8, over a 730-hour month.

## GCP-01: Autopilot only, no cluster mode option

**accepted** · 2026-09-08 · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf)

**Context.** GKE offers two modes. In Autopilot, Google provisions and
operates the nodes and bills Pod resource requests; in Standard, the client
owns the nodes and pays for their capacity, used or idle. Autopilot enforces
Workload Identity Federation, Shielded nodes, Dataplane V2 and network
policy; Standard leaves them off unless enabled. The mode is fixed at
creation: changing it means a second cluster and a migration.

On the reference estate:

| Estate of three clusters | Per month |
| --- | --- |
| Autopilot | $1,488 |
| Standard, packed to the allocatable ceiling | $1,346 |
| Standard, with the headroom rollouts and autoscaling need | $1,668 |
| Standard, production surviving a zone loss | $2,151 |

The cluster fee applies to both modes and cancels out. Node auto-upgrade is
on in both; Standard adds attending the node rollout, 5 to 14 hours per
minor version, 15 to 42 hours a year.

**Decision.** Every cluster is Autopilot. `enable_autopilot = true` is a
literal, not a variable.

**Consequences.**

- One shape of cluster: the module covers and tests one surface, not two.
- The client gives up what Autopilot forbids: privileged Pods outside
  Google's partner allowlists, SSH and host namespaces, writable `hostPath`,
  any node OS but Container-Optimized OS, any CNI but Dataplane V2, and the
  choice of whether to upgrade. Every Pod is billed at least 250 mCPU /
  512 MiB. The full list is in [GCP limits](../clouds/gcp/limits.md).
- A workload that needs Standard does not belong on a socle GKE cluster.
- Three scanner findings answer themselves on Autopilot and are ignored in
  `cluster.tf`: authorized networks (no IP endpoint), network policy
  (enforced, and the block is rejected), node service account (no
  `node_config` exists).

**Sources.** [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing) ·
[Autopilot and Standard comparison](https://cloud.google.com/kubernetes-engine/docs/resources/autopilot-standard-feature-comparison) ·
[cluster upgrades](https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-upgrades) ·
[Autopilot resource requests](https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests) ·
[partner workloads](https://cloud.google.com/kubernetes-engine/docs/resources/autopilot-partners).

## GCP-02: Regular release channel, rings ordered by the maintenance window

**accepted** · 2026-09-08 · [`opentofu/gcp/variables.tf`](../../opentofu/gcp/variables.tf) (`release_channel`, `maintenance_window`, `maintenance_exclusions`) · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) (`release_channel`, `maintenance_policy`)

**Context.** Kubernetes ships three minors a year with about 14 months of
support each, so a cluster upgrades at least twice a year. GKE's channels:

| Channel | A minor arrives | Note |
| --- | --- | --- |
| Rapid | 1 to 2 weeks after upstream | Outside the GKE SLA |
| Regular | about 2 months after Rapid | Google's recommendation |
| Stable | 3 to 4 months after Regular | |
| Extended | — | Forbidden on Autopilot |

The alternative to letting the channel move the version is to pin every
cluster with a `NO_MINOR_UPGRADES` exclusion and drive the version from the
pipeline. That inherits the full support clock, including shipping a bump
before Google overrides the exclusion at end of support.

**Decision.** One channel estate-wide, `REGULAR` by default; `RAPID` and
`STABLE` are accepted, `EXTENDED` is refused at plan. The maintenance window
is required and has no default. Its day of the week orders the rings inside
the channel: dev on Tuesday, staging on Wednesday, prod on Saturday.
Exclusions are the brake, empty by default.

**Consequences.**

- Google owns the Kubernetes version clock; the socle release owns the
  artifact clock.
- A silent default would mean nobody decided when production upgrades; the
  plan fails until the client writes a window.
- The module validates a window of at least 4 hours, a `DAILY` or `WEEKLY`
  RRULE, at most 3 `NO_UPGRADES` exclusions of at most 90 days, and at most
  20 exclusions. GKE's own rule — 48 hours of availability in any 92-day
  window, counting only blocks of 4 hours or more — is checked by GKE at
  apply, not by the module.
- `kubernetes_min_version` is a raise-only floor for promoting a minor
  deliberately; null in steady state.
- Upgrade notifications go to a Pub/Sub topic the module creates, so
  automation can react instead of polling release notes.

**Sources.** [Release channels](https://cloud.google.com/kubernetes-engine/docs/concepts/release-channels) ·
[versioning and support](https://cloud.google.com/kubernetes-engine/versioning) ·
[maintenance windows and exclusions](https://cloud.google.com/kubernetes-engine/docs/concepts/maintenance-windows-and-exclusions).

## GCP-03: Only the free system metrics, Auto-Monitoring refused

**accepted** · 2026-09-08 · [`opentofu/gcp/variables.tf`](../../opentofu/gcp/variables.tf) (`logging_components`, `monitoring_components`) · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) (`logging_config`, `monitoring_config`)

**Context.** GKE's system metrics are free and cannot be disabled. Every
other metric component — control plane, kube-state, kubelet, cAdvisor — is
billed per sample, at $0.158 per month per sample per second. GKE
Auto-Monitoring is a free feature that starts ingesting billed samples
without a decision on the client's side.

**Decision.** `monitoring_components` defaults to `SYSTEM_COMPONENTS` alone
and must include it; the billed components are accepted, never defaulted.
`logging_components` defaults to system components and workloads, and must
include system components. Auto-Monitoring is not configured and has no
variable.

**Consequences.**

- No per-sample charge appears unless the client adds a component.
- Workload logs go to Cloud Logging by default; drop `WORKLOADS` once
  application logs are collected in-cluster. On the reference estate, 30 GiB
  per cluster costs about $20 a month.

**Sources.** [Observability pricing](https://cloud.google.com/stackdriver/pricing) ·
[GKE metrics](https://cloud.google.com/stackdriver/docs/solutions/gke/managing-metrics).

## GCP-04: Workload metrics on Managed Service for Prometheus

**superseded by [SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud)** · 2026-09-08, superseded 2026-09-28 · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) (`managed_prometheus`)

**Context.** Managed Service for Prometheus bills ingestion per sample;
self-hosting costs Pod requests and a disk. Per cluster:

| | Samples/s | Per month |
| --- | --- | --- |
| Unfiltered `kube-prometheus` (Google's figure) | about 900 | $142 |
| Filtered as Google recommends | about 300 | $47 |
| Self-hosted Prometheus, Grafana and disk | — | $134 |

The crossover was about 850 samples/s per cluster. Monarch keeps 24 months,
a self-hosted Prometheus fifteen days.

**Decision.** Workload metrics were to go to Managed Service for Prometheus,
with a samples-per-second budget on the catalog's monitoring module.

**Consequences.** SOCLE-03 replaced this with one in-cluster stack on every
cloud, GKE included. The free system metrics of GCP-03 are unaffected. The
module still sets `managed_prometheus { enabled = true }` in
`monitoring_config`: managed collection is on, and nothing in the catalog
sends it samples.

**Sources.** [Prometheus cost controls](https://cloud.google.com/stackdriver/docs/managed-prometheus/cost-controls) ·
[Observability pricing](https://cloud.google.com/stackdriver/pricing) ·
[#43](https://github.com/do-now-io/socle/issues/43).

## GCP-05: Velero by default, Backup for GKE as a priced option

**proposed** · 2026-09-08 · [`opentofu/gcp/variables.tf`](../../opentofu/gcp/variables.tf) (`backup_agent_enabled`) · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) (`addons_config`) · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf) (`catalog_clouds`)

**Context.** On the reference estate:

| | Per month | Covers |
| --- | --- | --- |
| Velero | about $90 | Configuration and CSI volume snapshots |
| Backup for GKE | $297 ($9 per protected namespace) | The same, plus managed cross-project restore |

Autopilot blocks Velero's node-agent, which needs privileged mode and a
writable `hostPath`, so neither tool gives a portable file-level copy of
volume data.

**Decision.** Velero is the backup, with one restore procedure on four
clouds; Backup for GKE is an opt-in.

**Consequences.**

- Built: the Backup for GKE agent, off by default
  (`backup_agent_enabled = false`).
- Not built: the catalog offers `velero` on aws only, so a GCP cluster has
  no backup by default until the module gains its GCP branch.

**Sources.** [Backup for GKE](https://cloud.google.com/kubernetes-engine/docs/add-on/backup-for-gke/concepts/backup-for-gke) ·
[Velero file system backup](https://velero.io/docs/main/file-system-backup/).

## GCP-06: Workload Identity Federation, a Google service account per Kubernetes service account

**accepted** · 2026-09-08 · [`opentofu/gcp/main.tf`](../../opentofu/gcp/main.tf) (`workload_identity_pool`) · [`opentofu/gcp/iam.tf`](../../opentofu/gcp/iam.tf) · [`opentofu/gcp/outputs.tf`](../../opentofu/gcp/outputs.tf) · [`oci/catalog/external-dns/resourceset.yaml`](../../oci/catalog/external-dns/resourceset.yaml)

**Context.** Autopilot pre-configures Workload Identity Federation and it
cannot be disabled. The pool is `PROJECT_ID.svc.id.goog`. A workload's
principal is built from the project, the namespace and the service account
name — not the cluster.

**Decision.** A workload that needs Google Cloud access gets a Google
service account bound to its Kubernetes service account, or IAM roles
granted to its federated principal directly. The module has no Workload
Identity variable; it outputs `workload_identity_pool` and
`workload_identity_principal_prefix`, and the layer that owns the Kubernetes
objects makes the binding.

**Consequences.**

- No key is ever issued or accepted.
- Two clusters in one project produce identical principals for the same
  namespace and service account. Isolation is one project per environment
  ([prerequisites](../clouds/gcp/prerequisites.md#account)).
- external-dns on GCP uses the metadata server's credentials: its own
  principal, or a Google service account the client binds through values.
  How a module gets its cloud access is
  [SOCLE-04](socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change).

**Sources.** [Workload Identity Federation for GKE](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity).

## GCP-07: Dataplane V2 and plain NetworkPolicy

**accepted** · 2026-09-08 · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) · [`opentofu/bootstrap/cilium.tf`](../../opentofu/bootstrap/cilium.tf)

**Context.** Autopilot enables Dataplane V2, Google's eBPF dataplane built
on Cilium, and blocks what a self-managed Cilium needs: privileged
DaemonSets and custom eBPF. Against the socle's own Cilium on the other
clouds, it lacks L7 policy at scale, cluster mesh, egress gateway, BGP,
Tetragon and inter-node transparent encryption; FQDN policies exist only as
a GKE-specific alpha CRD.

**Decision.** Dataplane V2 as Autopilot configures it. Catalog modules
express network policy as plain Kubernetes NetworkPolicy, the one policy
surface identical on four clouds. FQDN and L7 policies are not a default.

**Consequences.**

- Nothing to install: the bootstrap refuses its `cilium` variable on gcp
  (see [SOCLE-02](socle.md#socle-02-cilium-and-coredns-before-flux-from-the-bootstrap)).
- The module has no CNI or datapath variable.
- Dataplane V2 observability (Hubble relay and UI) is not offered: no
  variable turns it on.

**Sources.** [Dataplane V2](https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2) ·
[FQDN network policies](https://cloud.google.com/kubernetes-engine/docs/how-to/fqdn-network-policies) ·
[inter-node transparent encryption](https://cloud.google.com/kubernetes-engine/docs/how-to/enable-inter-node-transparent-encryption).

## GCP-08: Exposure through GKE's Gateway controller

**accepted** · 2026-09-08 · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) (`gateway_api_config`) · [`opentofu/gcp/variables.tf`](../../opentofu/gcp/variables.tf) (`gateway_api_enabled`) · [`opentofu/bootstrap/main.tf`](../../opentofu/bootstrap/main.tf) (`gateway_class_name`) · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf) (`catalog_clouds`)

**Context.** GKE runs a managed Gateway API controller and installs and
upgrades the standard-channel CRDs with the cluster. There is no data plane
to run, scale or patch. An in-cluster Envoy would behave identically on
every cloud, at about $98 a month per cluster against $18 for a managed load
balancer. Routing objects are portable; health checks, WAF and session
affinity go through Google-specific policy resources.

**Decision.** GKE's controller, with the standard channel stated on the
cluster (`gateway_api_enabled = true`). The bootstrap hands the catalog the
class `gke-l7-global-external-managed`, the global external Application Load
Balancer. Ingress is not used for new exposure.

**Consequences.**

- The socle installs nothing for Gateway API on GKE: the catalog's
  `gateway_api` module is not offered on gcp, and with it the shared
  `public` and `private` Gateways of
  [GATEWAY-API-02](gateway-api.md#gateway-api-02-shared-public-and-private-gateways-on-cilium)
  are not created here.
- GKE serves only its own GatewayClasses, so the class name is the cloud's.
- The module also creates the proxy-only subnetwork that GKE's regional
  classes draw on (GCP-09). The global class the bootstrap selects does not
  use it.

**Sources.** [Gateway API on GKE](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api) ·
[proxy-only subnets](https://cloud.google.com/load-balancing/docs/proxy-only-subnets).

## GCP-09: Private nodes, a DNS endpoint, and a sized reference network

**accepted** · 2026-09-08 · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) · [`opentofu/gcp/network.tf`](../../opentofu/gcp/network.tf) · [`opentofu/gcp/variables.tf`](../../opentofu/gcp/variables.tf)

**Context.** Autopilot nodes are public by default. GKE recommends the
DNS-based control plane endpoint: a stable FQDN, authorised by IAM. Master
authorized networks only apply to IP endpoints and must be rewritten every
time a subnet or CI runner address changes. A cluster's Pod range cannot be
changed after creation; the primary range can be expanded in place.
Autopilot gives each node a /26 of Pod addresses (32 Pods). On Autopilot
1.27 and later GKE assigns Service addresses from its own range. Auto IPAM
was in Preview.

**Decision.**

- Private nodes (`enable_private_nodes = true`), flipping Autopilot's
  default; Cloud NAT for egress, scoped to the cluster subnetwork, logging
  errors only; Private Google Access on.
- The DNS endpoint is the access path; IP endpoints off; no authorized
  networks; no client certificate.
- One custom-mode VPC, one subnetwork per cluster: nodes `10.0.0.0/22`
  (1,020 nodes), Pods `10.4.0.0/16` (1,024 nodes, `/17` or larger
  enforced), a proxy-only subnetwork `10.8.0.0/23` (`/26` or larger
  enforced), no Services range.
- Auto IPAM refused.

**Consequences.**

- The control plane is reachable wherever Google Cloud APIs are, with IAM
  as the only gate (`control_plane_dns_allow_external_traffic = true`). A
  network boundary is VPC Service Controls, set at organisation level.
- Private nodes without NAT cannot pull an image from outside Google Cloud;
  the plan refuses that combination on a subnetwork the module owns.
- The Pod range is sized for the estate the cluster might grow into, the
  primary range only to match it.
- A Shared VPC is supported: `create_subnetwork = false` with
  `subnetwork_name` and `pod_range_name`.
- On the reference estate the network costs about $96 a month: three load
  balancers $55, three Cloud NAT gateways $23, data processing $19. The
  Gateway controller, Dataplane V2 and the DNS endpoint carry no charge.

**Sources.** [Network isolation](https://cloud.google.com/kubernetes-engine/docs/concepts/network-isolation) ·
[VPC-native clusters](https://cloud.google.com/kubernetes-engine/docs/concepts/alias-ips) ·
[networking best practices](https://cloud.google.com/kubernetes-engine/docs/best-practices/networking) ·
[auto IPAM](https://cloud.google.com/kubernetes-engine/docs/how-to/enable-auto-ipam) ·
[VPC network pricing](https://cloud.google.com/vpc/network-pricing) ·
[Cloud NAT pricing](https://cloud.google.com/nat/pricing).

## GCP-10: Subnet flow logs on, at half sampling over ten minutes

**accepted** · 2026-09-15 · [`opentofu/gcp/network.tf`](../../opentofu/gcp/network.tf) (`log_config`) · [`opentofu/gcp/variables.tf`](../../opentofu/gcp/variables.tf) (`subnet_flow_logs_enabled`)

**Context.** VPC flow logs are the only record of which address talked to
which. Vended network logs are billed at $0.25/GiB.

**Decision.** Flow logs on the cluster subnetwork by default, sampling 0.5,
aggregated over 10 minutes, all metadata. The proxy-only subnetwork has
none: it carries Google's proxies, not the cluster's flows.

**Consequences.** A socle cluster is estimated at single-digit GiB a month
at that sampling, about a dollar. `subnet_flow_logs_enabled = false` turns
them off.

**Sources.** [VPC flow logs](https://cloud.google.com/vpc/docs/flow-logs) ·
[VPC network pricing](https://cloud.google.com/vpc/network-pricing).

## GCP-11: Service metrics read every 300 s, Cloud Monitoring alert policies refused

**proposed** · 2026-09-08 · [`opentofu/gcp/iam.tf`](../../opentofu/gcp/iam.tf) (`observability_reader`)

**Context.** Google Cloud service metrics land in Cloud Monitoring free;
reading them out is billed per time series returned (since October 2025).
For about 800 service series — two Cloud SQL instances, a Memorystore,
buckets, topics, load balancers, NAT, quotas:

| Read interval | Per month |
| --- | --- |
| 60 s | $17.02 |
| 300 s | $3.00 |
| 900 s | $0.67 |

Reading 20,000 cluster series the same way at 60 s would be $438 a month.
Cloud Monitoring alert policies are free until 1 September 2027, then
billed, and would split alerting across clouds.

**Decision.** A `stackdriver_exporter` reads service metrics every 300 s for
the socle's monitoring stack; cluster metrics stay on the in-cluster path.
Alerting is the socle's, one definition for four clouds; no Cloud Monitoring
alert policy, dashboard, uptime check or metrics scope. Quota metrics are in
the perimeter; Recommender is a monthly report, not a signal.

**Consequences.**

- Built: `observability_reader_members` grants `roles/monitoring.viewer`
  on the project to federated principals, never a key.
- Not built: the exporter itself.

**Sources.** [Observability pricing](https://cloud.google.com/stackdriver/pricing) ·
[quota metrics](https://cloud.google.com/monitoring/alerts/using-quota-metrics) ·
[Recommender pricing](https://cloud.google.com/recommender/pricing).

## GCP-12: Cost attribution through the detailed billing export

**accepted** · 2026-09-08 · [`opentofu/gcp/cluster.tf`](../../opentofu/gcp/cluster.tf) (`cost_management_config`) · [`opentofu/gcp/observability.tf`](../../opentofu/gcp/observability.tf) (`billing_export`) · [`opentofu/gcp/variables.tf`](../../opentofu/gcp/variables.tf)

**Context.** The detailed usage cost export to BigQuery is resource-level
and is the only export carrying the cluster, namespace and workload labels
of GKE cost allocation. Cost allocation takes three days to appear and does
not backfill. The export cannot be configured by API: no Terraform resource,
no `gcloud` command. The FOCUS export would give one schema across clouds
but was in Preview.

**Decision.** GKE cost allocation on from creation
(`cost_allocation_enabled = true`). With `billing_export_dataset_id` set, the
module creates the BigQuery dataset in the client's project; a human links
the billing account to it in the Cloud Console. FOCUS refused.

**Consequences.**

- The export is free and a small estate is megabytes; data arrives hours to
  five days late — a monthly view, not a live one.
- The client queries their own dataset; Google publishes the query that
  reproduces an invoice total but guarantees no match.
- Linking the billing account is the one step on GCP that no apply
  finishes ([limits](../clouds/gcp/limits.md#what-no-apply-can-finish)).
- `delete_contents_on_destroy = false`: a destroy does not delete cost data.

**Sources.** [Billing export](https://cloud.google.com/billing/docs/how-to/export-data-bigquery) ·
[its tables](https://cloud.google.com/billing/docs/how-to/export-data-bigquery-tables) ·
[FOCUS export](https://cloud.google.com/billing/docs/how-to/export-data-bigquery-tables/focus-export) ·
[GKE cost allocation](https://cloud.google.com/kubernetes-engine/docs/how-to/cost-allocations) ·
[no Terraform resource for the export](https://github.com/hashicorp/terraform-provider-google/issues/4848).

## GCP-13: Crossplane, not Config Connector

**proposed** · 2026-09-15 · [`oci/catalog/crossplane/resourceset.yaml`](../../oci/catalog/crossplane/resourceset.yaml)

**Context.** Config Connector manages Google Cloud resources from
Kubernetes. Its add-on is Standard-only and Google discourages it in
production. The socle uses Crossplane on every cloud.

**Decision.** No Config Connector toggle; application infrastructure on GCP
arrives through Crossplane.

**Consequences.** The crossplane module renders providers for AWS only. On
GCP it installs the core and no provider, so nothing provisions Google Cloud
resources from the cluster yet, and catalog modules that need a cloud role
(`kube.keda.services`, for one) are aws-only.

**Sources.** [Config Connector](https://cloud.google.com/config-connector/docs/overview).
