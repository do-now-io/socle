# Scaleway — decisions

Kapsule throughout. Each decision is argued in the linked document.

| Decision | Position | Argued in |
| --- | --- | --- |
| Managed Kubernetes product | Kapsule — Kosmos refused | [kapsule-capabilities](kapsule-capabilities.md) |
| Control plane | Dedicated 4 in production, mutualized elsewhere | [kapsule-capabilities](kapsule-capabilities.md) |
| CNI | Cilium, Scaleway's own — no Hubble, no kube-proxy replacement | [kapsule-capabilities](kapsule-capabilities.md) |
| Kubernetes minor version | Ours — auto-upgrade covers patches only | [kapsule-capabilities](kapsule-capabilities.md) |
| Workload identity | None exists — IAM application and API key | [kapsule-capabilities](kapsule-capabilities.md) |
| Control plane exposure | Allowed-IP list, required, no default | [kapsule-capabilities](kapsule-capabilities.md) |
| Node isolation | Full isolation, every environment | [kapsule-capabilities](kapsule-capabilities.md) |
| Public Gateways | One per AZ — the gateway is zoned and has no HA | [kapsule-capabilities](kapsule-capabilities.md) |
| Network layout | One VPC per environment, one /22 per cluster | [kapsule-capabilities](kapsule-capabilities.md) |
| Node autoscaling | cluster-autoscaler, `expander = least_waste` | [kapsule-capabilities](kapsule-capabilities.md) |
| Node range and zones | COMPUTE3-X in fr-par-1 and fr-par-2 — two, not three | [kapsule-capabilities](kapsule-capabilities.md) |
| Three availability zones | Catalog option — pl-waw on POP2-HC only | [kapsule-capabilities](kapsule-capabilities.md) |
| Workload metrics | The socle's Prometheus, not Cockpit | [kapsule-capabilities](kapsule-capabilities.md) |
| Discounted capacity | Savings plans — rate unpublished, a commercial call | [kapsule-capabilities](kapsule-capabilities.md) |
| Data-plane add-ons | Delegated — no version exposed, no opt-out | [managed-scope](managed-scope.md) |
| Load balancers | Delegated — the CCM covers it | [managed-scope](managed-scope.md) |
| DNS and certificates | Factory — External-DNS and the Scaleway webhook | [managed-scope](managed-scope.md) |
| Certificates on the Load Balancer | Refused — a second certificate store | [managed-scope](managed-scope.md) |
| IAM boundary | One Project per environment | [managed-scope](managed-scope.md) |
| Factory runner credentials | IP-bound policy condition, always | [managed-scope](managed-scope.md) |
| OpenTofu state | Object Storage — native locking | [managed-scope](managed-scope.md) |
| Backup | Velero into Object Storage | [managed-scope](managed-scope.md) |
| Scaleway service metrics | Cockpit `/federate`, every 300 s | [cloud-observability](cloud-observability.md) |
| Alerting | Ours — one Alertmanager for four clouds | [cloud-observability](cloud-observability.md) |
| Cost attribution | Consumption API, Project-scoped, monthly | [cloud-observability](cloud-observability.md) |
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

fr-par list price excluding VAT, read 14 September 2026. Supervision adds €0
today. Add ~1.5 days/month of operations per client, argued in
[managed-scope](managed-scope.md#what-it-costs-per-client).

## The limits nothing downstream can fix

- No workload identity federation — a Pod calling the Scaleway API carries a
  long-lived API key.
- The control plane always has a public IP.
- etcd is capped at 55 MB mutualized, 200 MB dedicated.
- The current and previous instance generations never share an Availability
  Zone, so only pl-waw can run a homogeneous three-zone cluster.
- No per-resource IAM outside IAM, Key Manager and Secret Manager, and no
  tags on consumption — the Project is the only boundary for both access and
  cost.

## No module can do these

- Raise the instance quotas the reference estate needs — production's node
  type is capped at 2 against the 4 it wants, so a support ticket comes
  before the first apply.
- Validate the Organization's identity, without which most useful instance
  types have no quota at all.
