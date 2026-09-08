# Google Cloud — decisions

Index of what is decided for a GKE socle, and where each decision is argued.
Everything here assumes Autopilot.

| Document | Covers |
| --- | --- |
| [cluster-mode.md](cluster-mode.md) | Autopilot or Standard |
| [managed-scope.md](managed-scope.md) | Upgrades, add-ons, identity |
| [network-security.md](network-security.md) | Dataplane, exposure, control plane access, reference network |
| [cloud-observability.md](cloud-observability.md) | Google Cloud resources outside the cluster, and cost data |

## Every decision

**Delegated to Google** — it operates it reliably and the surcharge is
reasonable:

| Decision | Where |
| --- | --- |
| Autopilot clusters only, no cluster mode option | [cluster mode](cluster-mode.md) |
| The Kubernetes minor version follows the release channel | [managed scope](managed-scope.md) |
| Regular channel for the whole estate | [managed scope](managed-scope.md) |
| System metrics and logs — free, and not disableable | [managed scope](managed-scope.md) |
| Workload metrics go to Managed Service for Prometheus | [managed scope](managed-scope.md) |
| Workload Identity Federation, pre-configured | [managed scope](managed-scope.md) |
| Dataplane V2 as the CNI | [network & security](network-security.md) |
| Gateway API with Google's controller | [network & security](network-security.md) |
| DNS-based control plane endpoint | [network & security](network-security.md) |
| Detailed billing export as the cost attribution source | [cloud observability](cloud-observability.md) |
| GKE cost allocation, on from day one | [cloud observability](cloud-observability.md) |

**Ours** — it industrialises once and then costs nothing per cluster:

| Decision | Where |
| --- | --- |
| Which cluster upgrades first, through the maintenance window | [managed scope](managed-scope.md) |
| Backup with Velero, the same on four clouds | [managed scope](managed-scope.md) |
| Alerting, one Alertmanager for four clouds | [cloud observability](cloud-observability.md) |
| Private nodes, Cloud NAT, one subnet per cluster | [network & security](network-security.md) |
| Reading service metrics every 300 s from a central cluster | [cloud observability](cloud-observability.md) |
| Quota metrics in the standard perimeter | [cloud observability](cloud-observability.md) |

**Catalog options** — supported, priced through, not defaults:

| Decision | Where |
| --- | --- |
| Control plane and kube-state metrics, billed per sample | [managed scope](managed-scope.md) |
| Backup for GKE, for managed cross-project restore | [managed scope](managed-scope.md) |
| Hubble relay and UI | [network & security](network-security.md) |
| Database engine exporters, for query-level signal | [cloud observability](cloud-observability.md) |
| Staged release channels, for weeks of soak instead of days | [managed scope](managed-scope.md) |

**Refused** — absent from the module, not a variable set to false:

| Decision | Why | Where |
| --- | --- | --- |
| Standard clusters | One shape of cluster, tested one way | [cluster mode](cluster-mode.md) |
| Extended channel | Google forbids it on Autopilot | [managed scope](managed-scope.md) |
| GKE Auto-Monitoring | Free feature, billed samples | [managed scope](managed-scope.md) |
| Self-managed Cilium | Impossible on Autopilot | [network & security](network-security.md) |
| In-cluster gateway | Five times the cost, and ours to operate | [network & security](network-security.md) |
| Authorized networks | The DNS endpoint replaces them | [network & security](network-security.md) |
| Auto IPAM | Still Preview | [network & security](network-security.md) |
| FQDN and L7 policies as a default | GKE-specific and still alpha | [network & security](network-security.md) |
| Cloud Monitoring alert policies | Becomes billable, and splits alerting per cloud | [cloud observability](cloud-observability.md) |
| Reading cluster metrics through the Monitoring API | Two orders of magnitude more expensive | [cloud observability](cloud-observability.md) |

## What the estate costs

Reference estate of three Autopilot clusters — prod 20 vCPU / 40 GiB of Pod
requests, staging 8 / 16, dev 4 / 8 — at the recommended position:

| | Per month |
| --- | --- |
| Clusters and Pod requests | $1,488 |
| Observability and backup | +$252 |
| Network | +$96 |
| **Total** | **~$1,836** |

us-central1 list price, read September 2026. Re-price before quoting.

## Two things no module can do

- **Linking the billing account to the BigQuery cost export** has no API. It
  is a Console step — see [cloud observability](cloud-observability.md).
- **VPC Service Controls**, the network boundary in front of the control
  plane, is an organisation-level perimeter — see
  [network & security](network-security.md).
