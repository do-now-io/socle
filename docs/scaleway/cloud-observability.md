# Observing Scaleway resources outside the cluster

Managed services around a cluster and the cost data describing it, read from
a central observability cluster. In-cluster metrics stay on the in-cluster
path — see [capabilities](kapsule-capabilities.md#observability).

| Question | Position |
| --- | --- |
| Scaleway service metrics | Cockpit's `/federate` endpoint, every 300 s |
| Scraping the Scaleway APIs directly | Refused — Cockpit already holds the data, free |
| Pushing workload metrics into Cockpit | Refused — billed per sample |
| Alerting | Ours — one Alertmanager for four clouds |
| Scaleway alert manager | Refused — regionalised, and blocks Grafana's own |
| Cost attribution | Consumption API, one Project per environment |
| Per-namespace cost | Does not exist — OpenCost in the catalog if a client asks |
| Quotas | Raised at onboarding, then watched |

## Pulling metrics out

**Scaleway's own metrics and logs land in Cockpit for free**, with a
dashboard per product, retained 31 days for metrics and 7 for logs. Two ways
out of it — neither is the product APIs:

| | How | Cost |
| --- | --- | --- |
| **`/federate`** | Prometheus federation, `match[]` selectors, a `query` token | **Free during beta, billable after** |
| Data exports | push to Datadog or an OTLP endpoint, per data source | free during beta, then by volume |

**Decision: federate from the central observability cluster, every 300
seconds, with `match[]` narrowed to the products in the perimeter.**

- One cadence across the supervision plane rather than a per-cloud tuning
  exercise, and here it costs nothing to read today.
- **The cost to plan for is the end of the beta.** Scaleway states plainly
  that `/federate` will be billed afterwards and publishes no rate. This is
  the one figure here that has to be re-read before a client signs.
- Data exports are refused: configured per data source, so per region and per
  Project, and they only reach Datadog or an OTLP endpoint. A pull the
  central cluster controls beats a push Scaleway controls.
- **The mistake to avoid is pushing.** Workload metrics sent into Cockpit are
  billed per sample and stay in the socle's Prometheus instead.

### Coverage

Every managed database, both storage products, the whole serverless range,
load balancers and gateways are covered. The gaps:

| No metrics, no logs | Consequence |
| --- | --- |
| **Container Registry** | The socle pulls its own artifacts through it — registry health is observed from the consumer side, through Flux's reconciliation failures |
| Domains and DNS, IAM, Key Manager | No signal; nothing to alert on |
| Audit Trail | Not in Cockpit at all — out of the metrics path |

Database engine exporters stay a catalog option, for the signal the managed
metrics lack.

## Alerting

**Ours** — four clouds, one Alertmanager, one routing tree, one on-call.
Scaleway's own alert manager is refused for two reasons beyond that: it is
**regionalised and per data source**, so an estate in two regions configures
alerting twice, and Scaleway **does not support Grafana's own alert manager**
in its Grafana, so the Cockpit Grafana cannot be driven the way the socle's
is.

The one Scaleway-side alert kept is the **billing alert** — a budget in euros
with a threshold — because the signal only exists on Scaleway's side.

## Cost attribution

**Decision: the Billing API's consumption endpoint, read per Project, with
one Project per environment.**

| | |
| --- | --- |
| Cost | Free |
| Granularity | One line per resource — name, product, SKU, quantity, value |
| Scope filter | Organization or Project |
| Period | **Monthly. There is no daily breakdown** |
| Auditable | The client reads the same endpoint and gets the same lines |

- Resource-level lines make "% of the cloud bill" reproducible: the client
  can re-run the query against their own Organization and reconcile it with
  the invoice.
- **There are no tags on consumption.** The Project is the only attribution
  axis that exists — the same layout
  [IAM](managed-scope.md#iam) arrives at independently.
- **Per-namespace cost does not exist.** In-cluster showback means OpenCost
  in the catalog, priced as its own line.

## Quotas

Scaleway quotas are per instance type and low enough to block a first
deployment: **the reference estate does not fit a default account.**
Production's node type is capped at 2 against the 4 it needs, and the
dedicated-control-plane quota caps the offer at four production clusters per
Organization. Identity validation is itself a prerequisite — without it, most
useful instance types have no quota at all.

**Position: quota raises are an onboarding checklist item, not a metric.**
Scaleway exposes no quota metric in Cockpit, so there is nothing to alert on.
The control is the checklist; the symptom is a failed apply.

## Cost impact

| | Per month |
| --- | --- |
| Cockpit, Scaleway data and dashboards | €0 |
| `/federate`, ~800 series at 300 s | **€0 today, unpriced after beta** |
| Billing API, quota checks | €0 |
| **Total** | **€0, with one unpriced line** |
| *Workload metrics pushed to Cockpit instead* | +€355 |

fr-par list price excluding VAT, read 14 September 2026.

## Module specification

| Variable | Default | Constraint |
| --- | --- | --- |
| `cockpit_token_enabled` | `true` | creates a `query`-only token, sensitive output |
| `observability_allowed_cidrs` | **none — required** | IP condition on the read-only policy |
| `billing_reader_enabled` | `false` | Organization-scoped, so opt-in |

Absent by decision: alert manager configuration, contacts, preconfigured
alerts, data exports, dashboards — catalog objects, so four clouds share one
definition.

## Sources

Read 14 September 2026. [Cockpit pricing][price] · [product
integration][integration] · [federate Scaleway metrics][federate] · [data
exports][exports] · [Cockpit concepts][concepts] · [alert manager][alerts] ·
[Cockpit limits][limits] · [Billing API][billing-api] · [billing
concepts][billing-concepts] · [billing alerts][billing-alerts] ·
[Organization quotas][quotas].

[price]: https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-pricing/
[integration]: https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-product-integration/
[federate]: https://www.scaleway.com/en/docs/cockpit/how-to/federate-scaleway-metrics/
[exports]: https://www.scaleway.com/en/docs/cockpit/how-to/manage-data-exports/
[concepts]: https://www.scaleway.com/en/docs/cockpit/concepts/
[alerts]: https://www.scaleway.com/en/docs/cockpit/how-to/enable-alert-manager/
[limits]: https://www.scaleway.com/en/docs/cockpit/reference-content/cockpit-limitations/
[billing-api]: https://www.scaleway.com/en/developers/api/billing/
[billing-concepts]: https://www.scaleway.com/en/docs/billing/concepts/
[billing-alerts]: https://www.scaleway.com/en/docs/billing/how-to/use-billing-alerts/
[quotas]: https://www.scaleway.com/en/docs/organizations-and-projects/additional-content/organization-quotas/
