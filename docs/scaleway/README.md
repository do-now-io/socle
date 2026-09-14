# Scaleway — decisions

Kapsule throughout. Each decision is argued in the linked document.

| Decision | Position | Argued in |
| --- | --- | --- |
| Managed Kubernetes product | Kapsule | [kapsule-capabilities](kapsule-capabilities.md) |
| Kosmos | Refused — Kilo CNI, no Private Network, no migration path | [kapsule-capabilities](kapsule-capabilities.md) |
| Control plane, production | Dedicated 4 — the SLA and the audit log | [kapsule-capabilities](kapsule-capabilities.md) |
| Control plane, dev and staging | Mutualized, free | [kapsule-capabilities](kapsule-capabilities.md) |
| CNI | Cilium, Scaleway's own, not ours | [kapsule-capabilities](kapsule-capabilities.md) |
| Self-managed Cilium | Unavailable — `none` is not a supported CNI | [kapsule-capabilities](kapsule-capabilities.md) |
| Hubble, kube-proxy replacement | Absent — the catalog must not assume them | [kapsule-capabilities](kapsule-capabilities.md) |
| Kubernetes minor version | Ours — auto-upgrade covers patches only | [kapsule-capabilities](kapsule-capabilities.md) |
| Release channels | None exist; ring order is the pipeline's | [kapsule-capabilities](kapsule-capabilities.md) |
| Workload identity | None on Scaleway — IAM application and API key | [kapsule-capabilities](kapsule-capabilities.md) |
| Private control plane | Impossible — allowed-IP list is the boundary | [kapsule-capabilities](kapsule-capabilities.md) |
| Allowed-IP list | Required, no default — `0.0.0.0/0` is refused | [kapsule-capabilities](kapsule-capabilities.md) |
| Node isolation | Full isolation, every environment | [kapsule-capabilities](kapsule-capabilities.md) |
| Controlled isolation | Refused — dev would not exercise prod's egress path | [kapsule-capabilities](kapsule-capabilities.md) |
| Public Gateways | One per AZ — the gateway is zoned and has no HA | [kapsule-capabilities](kapsule-capabilities.md) |
| Security group | One per cluster — the default one is shared | [kapsule-capabilities](kapsule-capabilities.md) |
| Network layout | One VPC per environment, one /22 per cluster | [kapsule-capabilities](kapsule-capabilities.md) |
| Node spread | One pool per AZ, each in a placement group | [kapsule-capabilities](kapsule-capabilities.md) |
| Workload metrics | The socle's Prometheus — Cockpit is 2.5× GKE per sample | [kapsule-capabilities](kapsule-capabilities.md) |
| Scaleway's own metrics and logs | Cockpit, free | [kapsule-capabilities](kapsule-capabilities.md) |
| Backup | Velero, same on four clouds — Scaleway manages none | [kapsule-capabilities](kapsule-capabilities.md) |
| Discounted capacity | None exists — no spot market, no Karpenter | [kapsule-capabilities](kapsule-capabilities.md) |

## Reference estate

Three clusters — prod 20 vCPU / 40 GiB of Pod requests, staging 8 / 16, dev
4 / 8 — at the recommended position:

| | Per month |
| --- | --- |
| Nodes | €1,010 |
| Dedicated 4 control plane, prod only | +€80 |
| One Load Balancer per cluster | +€50 |
| Public Gateways — 3 in prod, 1 each elsewhere | +€95 |
| **Total** | **~€1,235** |
| *Production sized to survive a zone loss* | *+€311* |

fr-par list price excluding VAT, read 14 September 2026.

## The limits nothing downstream can fix

- No workload identity federation — a Pod calling the Scaleway API carries a
  long-lived API key.
- The control plane always has a public IP.
- etcd is capped at 55 MB mutualized, 200 MB dedicated.
