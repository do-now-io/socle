# Scaleway managed scope: what the provider operates, what we do

What Kapsule is and is not: [capabilities and limits](kapsule-capabilities.md).
This document splits the operating work between Scaleway and the factory, and
prices the half that lands on us.

Arbitration rule: reliable provider ops at a reasonable surcharge →
delegated. Cheap to industrialise → factory.

| Question | Position |
| --- | --- |
| Data-plane add-ons | Delegated — and not negotiable |
| CNI | Delegated, Scaleway's Cilium |
| Load balancers | Delegated — the CCM is the most complete thing Scaleway ships |
| DNS | Factory — External-DNS against Scaleway DNS |
| Certificates | Factory — cert-manager with Scaleway's DNS-01 webhook |
| Certificates on the Load Balancer | Refused — a second certificate store to operate |
| IAM boundary | One Project per environment |
| Factory runner credentials | IP-bound policy condition, always |
| OpenTofu state | Object Storage, native locking, versioned |
| Backups | Velero into Object Storage, same on four clouds |

## The gap against AWS

The interesting part is where it is not.

| AWS operates | On Scaleway | Lands on |
| --- | --- | --- |
| EKS add-ons, pinned, we trigger upgrades | CoreDNS, kube-proxy, CNI, CSI — all Scaleway's, no version exposed | **Nobody.** Less work, less control |
| Pod Identity / IRSA | nothing | **Factory** — every component holds a static key |
| Karpenter | cluster-autoscaler over homogeneous pools | **Factory** — capacity is a design act |
| Release channels | patches only; minors are manual | **Factory** — two scheduled upgrades a year |
| Private control plane | impossible | **Factory** — an allow-list to keep current |
| CUR, resource level, with tags | consumption API, no tags | **Factory** — Project-per-environment layout |
| AWS Backup | nothing | **Nobody** — Velero was already the standard |
| Managed Gateway API | nothing | **Nobody** — an in-cluster controller was already the standard |
| Spot | savings plans, ~10% at three years | **Nobody** — a commercial choice, not an ops one |

**Scaleway operates more of the data plane than EKS does, and gives less
control over it.** The add-on line, which is where an EKS estate spends its
version-management effort, costs nothing here — there is nothing to pin and
nothing to trigger. The gap is concentrated almost entirely on credentials.

### What it costs per client

One client, three clusters, steady state, after the factory has
industrialised what can be industrialised. Order of magnitude, not a quote.

| Driver | Days/month |
| --- | --- |
| API keys for in-cluster components — provisioning, rotation, incidents | 0.5 |
| Two minor upgrades a year, scheduled and run | 0.5 |
| Node pool shaping, with no Karpenter to absorb it | 0.25 |
| Allowed-IP list upkeep | 0.1 |
| Quota raises | 0.15 |
| **Total** | **~1.5 days/month** |

The one-off is larger than the recurring: key rotation has to be built once,
in the factory, and it is the single largest piece of Scaleway-specific
engineering in the whole sprint.

## Add-ons and CNI

Nothing to decide. CoreDNS, kube-proxy, the CNI and the CSI are Scaleway's,
installed on every node, with no version field and no opt-out. Refusing one
the way the AWS module refuses VPC CNI and kube-proxy is not possible: there
is no `bootstrap_self_managed_addons` equivalent, and `cni = "none"` is not
supported.

**Is "Cilium everywhere" simpler here?** On the box, yes — it is the
default. In practice it is a different Cilium, argued in
[capabilities](kapsule-capabilities.md#cni-cilium-but-not-ours): Scaleway's
version, beside kube-proxy rather than replacing it, without Hubble. The
catalog treats Scaleway as the cloud where Cilium's own features are not
available, not as the cloud where Cilium is free.

## Load balancers, DNS, certificates

| | Component | Maintained by | State |
| --- | --- | --- | --- |
| Load balancers | `scaleway-cloud-controller-manager` | Scaleway | ~50 Service annotations, released within the last two months |
| DNS | External-DNS Scaleway provider | upstream | Supported since External-DNS 0.7.4 |
| Certificates | `cert-manager-webhook-scaleway` | Scaleway | DNS-01 solver, released within the last two months |
| Volumes | `scaleway-csi` | Scaleway | Block Storage, released within the last two months |

**Delegated: the Load Balancer, through the CCM.** It is the most complete
integration Scaleway ships — PROXY protocol, HTTP/3, access logs, private
load balancers, per-zone placement, target node labels, timeouts, health
checks per protocol. A Service of type `LoadBalancer` is enough; nothing in
the module has to reach for the Load Balancer API.

**Factory: DNS and certificates**, with the components the socle already
runs on three other clouds. Both exist, both are current, and using them
keeps one External-DNS and one cert-manager across the estate.

- The External-DNS tutorial still carries a "Scaleway DNS is in Public Beta"
  warning that Scaleway's own DNS documentation no longer repeats. Treat the
  warning as stale, and the integration as the thing to verify on the first
  cluster.

**Refused: certificates on the Load Balancer.** The CCM accepts
`scw-loadbalancer-certificate-ids`, so TLS could terminate at the Scaleway
Load Balancer against certificates held in the Scaleway API. That would mean
a second certificate store, a second renewal path and a second failure mode,
on one cloud out of four. TLS terminates in the cluster, where cert-manager
already owns it.

## IAM

Scaleway IAM has principals — users, groups, applications — permission sets,
and a scope. What it does not have is per-resource authorisation.

**Resource-level conditions exist for three products only: IAM, Key Manager
and Secret Manager.** Not Kubernetes, not Instances, not VPC, not Object
Storage. A policy cannot say "this application may manage cluster A but not
cluster B".

**So the Project is the boundary, and the module puts one environment in
one Project.** The same conclusion arrives independently from cost
attribution, which is also Project-scoped — see
[observability](cloud-observability.md#cost-attribution). Two unrelated
constraints pointing at the same layout is the strongest argument in this
document.

**Request-level conditions do work everywhere**, in CEL, on the request's IP,
user agent and time. That is the one real mitigation available for static
keys:

- **The factory runner's key carries an IP condition** pinned to the
  runner's egress. A leaked key is then useless off that address.
- In-cluster components cannot use the same trick under controlled
  isolation, where node egress IPs are dynamic. Under **full isolation the
  egress is the Public Gateway's**, which is stable — a second reason for
  the isolation decision taken in
  [capabilities](kapsule-capabilities.md#networking).
- Read-only supervision is a plain `BillingReadOnly` plus per-product read
  permission sets, scoped to the Project, IP-bound to the observability
  cluster.

## Object Storage for state and backups

**OpenTofu state goes to Scaleway Object Storage with native locking.**

- Object Storage implements S3 conditional writes, `If-Match` and
  `If-None-Match`, documented July 2026. That is exactly what OpenTofu's
  `use_lockfile` needs, so **there is no second service to provision** — the
  same conclusion the AWS work reached when it dropped DynamoDB.
- Bucket versioning covers the state file's own history.
- Object Lock is available in Governance and Compliance modes, WORM, with
  per-object or bucket-default retention. It belongs on the Velero bucket,
  not the state bucket, where it would make a legitimate state rewrite
  impossible.
- Server-side encryption with Key Manager (SSE-KMS) is available and is the
  default for both buckets.
- Bucket policies accept IP conditions, which the state bucket uses to admit
  the factory runner only.

**Backups are Velero into Object Storage.** Unlike Autopilot, Kapsule places
no restriction on privileged Pods or writable `hostPath`, so Velero's
node-agent runs and the file-level copy exists — the portable volume backup
that GKE Autopilot denies the estate. Scaleway has no managed Kubernetes
backup product, so there is nothing to compare against and nothing to refuse.

## Module specification

| Variable | Default | Constraint |
| --- | --- | --- |
| `project_id` | **none — required** | one Project per environment |
| `crossplane_application_id` | module-created | IAM application, key exposed as a sensitive output |
| `runner_allowed_cidrs` | **none — required** | becomes the IP condition on the runner policy |
| `state_bucket_name` | **none — required** | versioning on, SSE-KMS on, `use_lockfile` |
| `velero_bucket_object_lock` | `false` | Governance mode when true |
| `lb_certificate_ids` | absent | refused by decision |

Absent by decision: any add-on toggle, any CNI choice, any Load Balancer
resource, any certificate resource.

## Sources

Read 14 September 2026.

[IAM policy conditions][cond] · [products supporting resource-level
conditions][res-level] · [IAM concepts][iam] · [billing
permission sets][bill-perms] · [CCM Load Balancer annotations][ccm] ·
[External-DNS Scaleway provider][edns] · [cert-manager webhook for
Scaleway][cmw] · [Scaleway CSI][csi] · [Object Storage conditional
writes][cond-writes] · [Object Storage concepts — Object Lock and retention
modes][os-concepts] · [shared responsibility model][srm] ·
[savings plans][savings].

[cond]: https://www.scaleway.com/en/docs/iam/reference-content/understanding-policy-conditions/
[res-level]: https://www.scaleway.com/en/docs/iam/reference-content/supported-products-resource-level/
[iam]: https://www.scaleway.com/en/docs/iam/concepts/
[bill-perms]: https://www.scaleway.com/en/docs/billing/concepts/
[ccm]: https://github.com/scaleway/scaleway-cloud-controller-manager/blob/master/docs/loadbalancer-annotations.md
[edns]: https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/scaleway.md
[cmw]: https://github.com/scaleway/cert-manager-webhook-scaleway
[csi]: https://github.com/scaleway/scaleway-csi
[cond-writes]: https://www.scaleway.com/en/docs/object-storage/api-cli/using-conditional-writes/
[os-concepts]: https://www.scaleway.com/en/docs/object-storage/concepts/
[srm]: https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-shared-responsibility-model/
[savings]: https://www.scaleway.com/en/docs/billing/additional-content/understanding-savings-plans/
