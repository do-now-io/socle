# Google Cloud — decisions

Autopilot throughout. Each decision is argued in the linked document.

| Decision | Position | Argued in |
| --- | --- | --- |
| Cluster mode | Autopilot only, no option | [cluster-mode](cluster-mode.md) |
| Standard clusters | Refused — one shape, tested one way | [cluster-mode](cluster-mode.md) |
| Kubernetes minor version | Google's release channel | [managed-scope](managed-scope.md) |
| Release channel | Regular, estate-wide | [managed-scope](managed-scope.md) |
| Extended channel | Refused — forbidden on Autopilot | [managed-scope](managed-scope.md) |
| Upgrade order dev → prod | Ours, by maintenance window | [managed-scope](managed-scope.md) |
| Staged channels for longer soak | Catalog option | [managed-scope](managed-scope.md) |
| System metrics and logs | Google's, free, not disableable | [managed-scope](managed-scope.md) |
| Workload metrics | Managed Service for Prometheus | [managed-scope](managed-scope.md) |
| Control plane / kube-state metrics | Catalog option — billed per sample | [managed-scope](managed-scope.md) |
| Auto-Monitoring | Refused — free feature, billed samples | [managed-scope](managed-scope.md) |
| Backup | Velero, same on four clouds | [managed-scope](managed-scope.md) |
| Backup for GKE | Catalog option — $9 per namespace-month | [managed-scope](managed-scope.md) |
| Workload Identity Federation | Google's, pre-configured | [managed-scope](managed-scope.md) |
| CNI | Dataplane V2, enforced | [network-security](network-security.md) |
| Self-managed Cilium | Refused — impossible on Autopilot | [network-security](network-security.md) |
| Network policy | Plain Kubernetes NetworkPolicy | [network-security](network-security.md) |
| FQDN and L7 policies | Refused as default — GKE-specific, alpha | [network-security](network-security.md) |
| Hubble relay and UI | Catalog option | [network-security](network-security.md) |
| Exposure | Gateway API, Google's controller | [network-security](network-security.md) |
| In-cluster gateway | Refused — 5× the cost, ours to run | [network-security](network-security.md) |
| Nodes | Private, Cloud NAT for egress | [network-security](network-security.md) |
| Control plane access | DNS-based endpoint | [network-security](network-security.md) |
| Authorized networks | Refused — the DNS endpoint replaces them | [network-security](network-security.md) |
| Network layout | One VPC, one subnet per cluster | [network-security](network-security.md) |
| Auto IPAM | Refused — still Preview | [network-security](network-security.md) |
| Service metrics outside the cluster | Monitoring API, every 300 s | [cloud-observability](cloud-observability.md) |
| Cluster metrics via that API | Refused — 100× the cost | [cloud-observability](cloud-observability.md) |
| Database engine exporters | Catalog option | [cloud-observability](cloud-observability.md) |
| Alerting | Ours, one Alertmanager for four clouds | [cloud-observability](cloud-observability.md) |
| Cloud Monitoring alert policies | Refused — becomes billable, splits alerting | [cloud-observability](cloud-observability.md) |
| Cost attribution | Detailed billing export to BigQuery | [cloud-observability](cloud-observability.md) |
| GKE cost allocation | On, from day one | [cloud-observability](cloud-observability.md) |
| Quota metrics | In the standard perimeter | [cloud-observability](cloud-observability.md) |
| Recommender | Monthly report, not a signal | [cloud-observability](cloud-observability.md) |

## Reference estate

Three clusters — prod 20 vCPU / 40 GiB of Pod requests, staging 8 / 16, dev
4 / 8 — at the recommended position:

| | Per month |
| --- | --- |
| Clusters and Pod requests | $1,488 |
| Observability and backup | +$252 |
| Network | +$96 |
| **Total** | **~$1,836** |

us-central1 list price, read September 2026.

## No module can do these

- Link the billing account to the BigQuery cost export — no API, Console only.
- VPC Service Controls, the boundary in front of the control plane —
  organisation-level.
