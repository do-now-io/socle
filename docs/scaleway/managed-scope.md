# Scaleway managed scope: what Scaleway operates, what we do

Who operates what around a Kapsule cluster — see
[capabilities](kapsule-capabilities.md). Arbitration rule: reliable provider
ops at a reasonable surcharge → delegated; cheap to industrialise → factory.

| Question | Position |
| --- | --- |
| Data-plane add-ons | Delegated — and not negotiable |
| Load balancers | Delegated — the CCM is the most complete thing Scaleway ships |
| DNS and certificates | Factory — External-DNS and cert-manager's Scaleway webhook |
| Certificates on the Load Balancer | Refused — a second certificate store |
| IAM boundary | One Project per environment |
| Factory runner credentials | IP-bound policy condition, always |
| OpenTofu state | Object Storage, native locking, versioned |
| Backups | Velero into Object Storage, same on four clouds |

## What lands on the factory

| Scaleway operates | We operate |
| --- | --- |
| CoreDNS, kube-proxy, CNI, CSI — no version, no opt-out | Credentials: every in-cluster component holds a static API key |
| Load balancers, through the CCM | Capacity: pool shape, with no Karpenter to absorb it |
| Patch upgrades, in a maintenance window | Minor upgrades, twice a year |
| GPU drivers and the NVIDIA operator | The allowed-IP list, and quota raises |
| | DNS, certificates, backups — the same components as on every cloud |

**The data plane is entirely Scaleway's, so there is nothing to pin and
nothing to trigger.** What is left on us is concentrated almost entirely on
credentials.

### What it costs per client

One client, three clusters, steady state. Order of magnitude, not a quote.

| Driver | Days/month |
| --- | --- |
| API keys for in-cluster components — provisioning, rotation, incidents | 0.5 |
| Two minor upgrades a year | 0.5 |
| Node pool shaping, with no Karpenter to absorb it | 0.25 |
| Allowed-IP list and quota raises | 0.25 |
| **Total** | **~1.5 days/month** |

The one-off is larger than the recurring: **key rotation has to be built
once, in the factory** — the single largest piece of Scaleway-specific
engineering in the sprint.

## Add-ons, load balancers, DNS

Nothing to decide on add-ons: CoreDNS, kube-proxy, the CNI and the CSI are
Scaleway's, with no version field and no opt-out — there is no equivalent of
the add-on exclusions other clouds offer. Cilium is the default but it is
[a different Cilium](kapsule-capabilities.md#cni).

**Delegated: the Load Balancer, through `scaleway-cloud-controller-manager`.**
The most complete integration Scaleway ships — ~50 Service annotations
covering PROXY protocol, HTTP/3, access logs, private load balancers, health
checks. A Service of type `LoadBalancer` is enough; nothing in the module
reaches for the Load Balancer API.

**Factory: DNS and certificates**, with External-DNS's Scaleway provider and
Scaleway's `cert-manager-webhook-scaleway` DNS-01 solver. Both are current,
and using them keeps one External-DNS and one cert-manager across four
clouds. The External-DNS tutorial still warns that Scaleway DNS is in beta,
where Scaleway's own DNS documentation no longer does — treat the warning as
stale, and verify on the first cluster.

**Refused: certificates on the Load Balancer.** The CCM can terminate TLS
against certificates held in the Scaleway API, which would mean a second
certificate store, a second renewal path and a second failure mode, on one
cloud out of four.

## IAM

Scaleway IAM has principals, permission sets and a scope. What it does not
have is per-resource authorisation: **resource-level conditions exist for IAM,
Key Manager and Secret Manager only.** A policy cannot say "this application
may manage cluster A but not cluster B".

**Decision: the Project is the boundary, and one environment is one Project.**
Cost attribution arrives at the same layout independently, since consumption
carries no tags — see
[observability](cloud-observability.md#cost-attribution). Two unrelated
constraints pointing at the same layout is the strongest argument here.

**Request-level conditions do work everywhere**, on IP, user agent and time.
That is the one real mitigation for static keys: **the factory runner's key
carries an IP condition** pinned to its egress, and under full isolation
in-cluster components egress through the Public Gateway's stable IP — a
second reason for [that decision](kapsule-capabilities.md#networking).

## Object Storage for state and backups

**OpenTofu state goes to Object Storage with native locking.** Conditional
writes are supported, which is what `use_lockfile` needs, so **there is no
second service to provision for locking**. Versioning covers the state file's
history, SSE-KMS is the default, and a bucket policy admits the factory
runner only.

**Backups are Velero into Object Storage.** Kapsule places no restriction on
privileged Pods or writable `hostPath`, so Velero's node-agent runs and the
portable, file-level copy of volume data exists. Object Lock belongs on the
Velero bucket, not the state bucket, where WORM would make a legitimate state
rewrite impossible.

## Module specification

| Variable | Default | Constraint |
| --- | --- | --- |
| `project_id` | **none — required** | one Project per environment |
| `crossplane_application_id` | module-created | IAM application, key as a sensitive output |
| `runner_allowed_cidrs` | **none — required** | IP condition on the runner policy |
| `state_bucket_name` | **none — required** | versioning on, SSE-KMS on, `use_lockfile` |
| `velero_bucket_object_lock` | `false` | Governance mode when true |

Absent by decision: any add-on toggle, any CNI choice, any Load Balancer or
certificate resource.

## Sources

Read 14 September 2026. [IAM policy conditions][cond] · [products supporting
resource-level conditions][res-level] · [CCM Load Balancer annotations][ccm] ·
[External-DNS Scaleway provider][edns] · [cert-manager webhook][cmw] ·
[Scaleway CSI][csi] · [Object Storage conditional writes][cond-writes] ·
[Object Storage concepts][os-concepts] · [shared responsibility model][srm].

[cond]: https://www.scaleway.com/en/docs/iam/reference-content/understanding-policy-conditions/
[res-level]: https://www.scaleway.com/en/docs/iam/reference-content/supported-products-resource-level/
[ccm]: https://github.com/scaleway/scaleway-cloud-controller-manager/blob/master/docs/loadbalancer-annotations.md
[edns]: https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/scaleway.md
[cmw]: https://github.com/scaleway/cert-manager-webhook-scaleway
[csi]: https://github.com/scaleway/scaleway-csi
[cond-writes]: https://www.scaleway.com/en/docs/object-storage/api-cli/using-conditional-writes/
[os-concepts]: https://www.scaleway.com/en/docs/object-storage/concepts/
[srm]: https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-shared-responsibility-model/
