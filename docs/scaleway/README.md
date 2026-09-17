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
| Discounted capacity | Savings plans — 10–25%, rate unpublished, GPU excluded | [kapsule-capabilities](kapsule-capabilities.md) |
| Node autoscaling | cluster-autoscaler — no Karpenter exists for Scaleway | [kapsule-capabilities](kapsule-capabilities.md) |
| Autoscaler expander | `least_waste` — Scaleway ships `random` | [kapsule-capabilities](kapsule-capabilities.md) |
| Consolidation | Does not exist — pool shape is a design act | [kapsule-capabilities](kapsule-capabilities.md) |
| Node range | COMPUTE3-X — dedicated vCPU, current generation | [kapsule-capabilities](kapsule-capabilities.md) |
| BASIC3-X for nodes | Refused — shared vCPU, 99% SLO | [kapsule-capabilities](kapsule-capabilities.md) |
| Zones, production | fr-par-1 and fr-par-2 — two, not three | [kapsule-capabilities](kapsule-capabilities.md) |
| Three availability zones | Catalog option — pl-waw on POP2-HC only | [kapsule-capabilities](kapsule-capabilities.md) |
| GPU | Delegated — Scaleway installs the NVIDIA operator | [kapsule-capabilities](kapsule-capabilities.md) |
| Data-plane add-ons | Delegated — no version exposed, no opt-out | [managed-scope](managed-scope.md) |
| Load balancers | Delegated — the CCM covers it, ~50 annotations | [managed-scope](managed-scope.md) |
| DNS and certificates | Factory — External-DNS and cert-manager's Scaleway webhook | [managed-scope](managed-scope.md) |
| Certificates on the Load Balancer | Refused — a second certificate store | [managed-scope](managed-scope.md) |
| IAM boundary | One Project per environment | [managed-scope](managed-scope.md) |
| Per-resource IAM | Does not exist outside IAM, Key and Secret Manager | [managed-scope](managed-scope.md) |
| Factory runner credentials | IP-bound policy condition, always | [managed-scope](managed-scope.md) |
| OpenTofu state | Object Storage — native locking, no second service | [managed-scope](managed-scope.md) |
| Ops overhead vs AWS | ~1.5 days/month per client, nearly all credentials | [managed-scope](managed-scope.md) |
| Scaleway service metrics | Cockpit `/federate`, every 300 s | [cloud-observability](cloud-observability.md) |
| Scraping the Scaleway APIs | Refused — Cockpit holds the data already, free | [cloud-observability](cloud-observability.md) |
| Alerting | Ours — one Alertmanager for four clouds | [cloud-observability](cloud-observability.md) |
| Scaleway alert manager | Refused — regionalised, and blocks Grafana's own | [cloud-observability](cloud-observability.md) |
| Cost attribution | Consumption API, resource lines, Project-scoped | [cloud-observability](cloud-observability.md) |
| Per-namespace cost | Does not exist — OpenCost as a catalog option | [cloud-observability](cloud-observability.md) |
| Quotas | Raised at onboarding — the estate does not fit the defaults | [cloud-observability](cloud-observability.md) |
| The Crossplane bet | Holds — coverage is excellent, cadence is not | [crossplane-iac](crossplane-iac.md) |
| Crossplane provider | Scaleway's own, upjet-generated, version pinned | [crossplane-iac](crossplane-iac.md) |
| Provider regeneration | Factory-owned fork — ~3–5 days, once | [crossplane-iac](crossplane-iac.md) |
| Missing Crossplane resource | `provider-terraform` inside the Composition | [crossplane-iac](crossplane-iac.md) |
| tofu-controller | Refused — a second reconciler beside Flux | [crossplane-iac](crossplane-iac.md) |
| OpenTofu provider, foundations | No gaps — nothing to work around | [crossplane-iac](crossplane-iac.md) |

## Reference estate

Three clusters — prod 20 vCPU / 40 GiB of Pod requests, staging 8 / 16, dev
4 / 8 — at the recommended position:

| | Per month |
| --- | --- |
| Nodes — COMPUTE3-X | €1,111 |
| Dedicated 4 control plane, prod only | +€80 |
| One Load Balancer per cluster | +€50 |
| Public Gateways — 2 in prod, 1 each elsewhere | +€76 |
| **Total** | **~€1,317** |
| *Production surviving a zone loss, on two zones* | *+€684* |
| *The same, on pl-waw's three zones* | *+€311* |

fr-par list price excluding VAT, read 14 September 2026.

Add ~1.5 days/month of Do Now operations against an AWS baseline, argued in
[managed-scope](managed-scope.md#what-it-costs-per-client).

## The limits nothing downstream can fix

- No workload identity federation — a Pod calling the Scaleway API carries a
  long-lived API key.
- The control plane always has a public IP.
- etcd is capped at 55 MB mutualized, 200 MB dedicated.
- The current and previous instance generations never share an Availability
  Zone, so only pl-waw can run a homogeneous three-zone cluster.
- No per-resource IAM outside IAM, Key Manager and Secret Manager, and no
  tags on consumption — so the Project is the only boundary for both access
  and cost.

## Nothing in the module can do these

- Raise the instance quotas the reference estate needs. The quota table has
  no figure at all for the Zen 5 generation, and the shape COMPUTE3-X
  replaces is capped at 2 against an estate that wants 4 — a support ticket
  before the first apply.
- Validate the Organization's identity, without which most useful instance
  types have no quota at all.
