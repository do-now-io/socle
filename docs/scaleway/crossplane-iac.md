# Scaleway, Crossplane and the IaC bet

Socle provisions a client's application infrastructure in-cluster, with
Crossplane, from claims. That is a bet, and it is an elimination criterion
for tooling. This document tests it against Scaleway.

| Question | Position |
| --- | --- |
| Crossplane on Scaleway | **The bet holds** — kept, with conditions |
| Provider | `scaleway/crossplane-provider-scaleway`, official, upjet-generated |
| Version | Pinned. Never a floating tag |
| Regeneration | **Ours.** The factory owns a fork it can regenerate |
| Fallback for a missing resource | `provider-terraform`, inside the same Composition |
| tofu-controller | Refused — a second reconciler and a second state model |
| OpenTofu provider, for the foundations | No gaps. Nothing to work around |

## The provider, measured

`scaleway/crossplane-provider-scaleway` is maintained by Scaleway, generated
with [Upjet][upjet] from their own Terraform provider, and supports
Crossplane v2 with namespaced managed resources.

| | |
| --- | --- |
| Managed resources | **144**, against 157 resources in the Terraform provider |
| Latest release | **v0.6.0, 6 February 2026 — seven months ago** |
| Last functional commit | **27 April 2026.** Everything since is Dependabot |
| Open issues | 14, two at `priority:highest` **since August 2024** |
| Community | 30 stars, 13 forks |
| Distribution | `xpkg.upbound.io/scaleway/provider-scaleway` |

**Coverage is excellent. Cadence is not.** Those are two separate findings
and they point different ways, so they are argued separately below.

## Coverage: everything a claim needs is there

The resources clients will actually ask for, as managed resources today:

| Claim | Managed resources |
| --- | --- |
| PostgreSQL / MySQL | `rdb`: instances, databases, users, privileges, acls, readreplicas, snapshots, databasebackups |
| Redis | `redis`: clusters |
| MongoDB | `mongodb`: instances, users, snapshots |
| Buckets | `object`: buckets, acls, policies, objects, lockconfigurations, websiteconfigurations |
| Queues and topics | `mnq`: sqs, sqsqueues, sns, snstopics, snstopicsubscriptions, natsaccounts, plus credentials for each |
| Secrets | `secrets`: secrets, versions · `keymanager`: keys, materials |
| Volumes | `block`: volumes, snapshots |
| Identity | `iam`: applications, apikeys, policies, groups, users, tokens, sshkeys |

Also generated: `k8s`, `vpc` (22 CRDs, public gateways included), `lb`,
`registry`, `domain`, `cockpit`, `container`, `function`, `jobs`, `sdb`,
`kafka`, `opensearch`, `datawarehouse`, `inference`, `edgeservices`,
`interlink`, `s2svpn`, `ipam`, `billing`.

**Nothing in the catalog's plausible claim set is missing.** The gaps that do
exist are narrow — `lb` has no ACL resource, and serverless triggers and job
definitions are absent — and none of them sit on a claim path.

**Note the IAM coverage in particular.** `iam.applications`, `iam.apikeys`
and `iam.policies` all exist, which means the credential problem of
[managed scope](managed-scope.md#iam) is at least *expressible* in
Crossplane: an application, a policy with its IP condition, and an API key
whose connection secret the provider writes. Rotation becomes a Composition
concern rather than a script.

## Cadence: the provider is in maintenance by bot

This is the finding that matters, and it is not visible from the resource
count.

- **Seven months without a release.** v0.6.0 shipped 6 February 2026.
- **Four and a half months without a functional commit.** The last one is a
  Redis LateInitializer fix on 27 April 2026 — **and it is not in any
  release**. Anyone hitting that bug runs from `main` or waits.
- **Two `priority:highest` bugs have been open since August 2024**:
  `PublicGatewayIP` not created on the target cluster, and `RDB Instance
  matchLabels` not working. Two years.
- `examples/install.yaml` still pins `v0.1.0`, five releases behind.
- Meanwhile **the Terraform provider it is generated from ships roughly
  monthly** — v2.82.0 on 1 September 2026. The generated provider drifts
  behind its own source, and the gap widens by default.

Against that, the repository is not abandoned: dependencies are current,
actions are pinned, commits are signed, and a nightly e2e workflow landed in
January 2026. Scaleway also publishes a Crossplane tutorial. This is a
maintained project that has stopped advancing, not a dead one.

One stale signal worth not over-reading: issue #201, "provider fails to start
in CNCF Crossplane 2.0", `priority:highest`, still open. The February 2026
README documents installing against upstream Crossplane v2 and the provider
advertises v2 support, so the issue is almost certainly obsolete. **Nobody
closed it.** That is the maintenance posture in one example.

## Decision

**The bet holds. Crossplane stays, this provider stays, and the factory
takes ownership of the thing Scaleway has stopped doing.**

The argument turns on one property: **the provider is generated, not
written.** A hand-written provider that stalls is a dead end — you wait, or
you write Go. An upjet-generated provider that stalls is a build you can run
yourself. The repository carries its generator config, so regenerating
against a newer Terraform provider is mechanical.

So:

1. **Pin `v0.6.0`.** Never a floating tag, on a component that reconciles
   client infrastructure.
2. **The factory maintains a fork it can regenerate**, and regenerates when
   a needed resource or fix is only in the Terraform provider. This is a
   standing capability, not a contingency.
3. **Verify before promising.** Two of the three `priority:highest` bugs
   touch resources the catalog will use — RDB and public gateway IPs. They
   are old enough that they may already be fixed and unclosed. The first
   cluster tests them; nothing is sold on them until it does.

## Fallbacks, and what switching costs

| Option | State | Position |
| --- | --- | --- |
| **Regenerate the provider** | upjet, config in repo | **First resort** |
| **`crossplane-contrib/provider-terraform`** | v1.2.0, August 2026, active | **Per-resource fallback** |
| `flux-iac/tofu-controller` | v0.16.5, August 2026, 158 open issues, still 0.x | **Refused** |

**`provider-terraform` is the fallback because it does not change the
architecture.** It exposes a Terraform workspace as a managed resource, so a
missing Scaleway resource is patched *inside* the Composition that needed
it. Claims, XRs and the GitOps path are untouched, and the patch is removed
when the generated provider catches up.

**tofu-controller is refused for the reason AWS Backup and the Scaleway
alert manager are refused**: it would add a second reconciler, a second
state model and a second failure mode beside Flux, to solve a problem the
first resort already solves.

Order of magnitude for each move, once the capability exists:

| | Cost |
| --- | --- |
| Patch one missing resource via `provider-terraform` | ~0.5 day |
| Stand up the fork-and-regenerate pipeline | **~3–5 days, once** |
| Regenerate against a newer Terraform provider | ~0.5 day per refresh |
| Rewrite the Compositions onto tofu-controller | weeks — the reason it is refused |

The three-to-five days is the real number in this document. It buys
independence from Scaleway's release cadence on the one component that would
otherwise block the catalog.

## The OpenTofu provider, for the foundations

Separate question, and a much shorter answer.

`scaleway/terraform-provider-scaleway` — 157 resources, 144 data sources,
v2.82.0 on 1 September 2026, pushed the day this was written. **Every
resource the foundations module needs exists**, including the ones the
sprint's decisions rely on:

`k8s_cluster`, `k8s_pool`, **`k8s_acl`** (the allowed-IP list), `vpc`,
`vpc_private_network`, `vpc_public_gateway`, `vpc_gateway_network`,
`ipam_ip`, `instance_placement_group`, `instance_security_group`,
`iam_application`, `iam_policy`, `iam_api_key`, `object_bucket`,
`object_bucket_policy`, **`object_bucket_lock_configuration`**,
`cockpit_token`, `cockpit_source`, `lb`, `lb_ip`, `secret`.

**No gaps, and nothing to work around.** The 219 open issues are worth
knowing about, but they are the issue count of a large, actively released
provider, not a warning.

## Cost impact

| | |
| --- | --- |
| Provider licence, support, hosting | €0 — open source, pulled from a public registry |
| Fork-and-regenerate pipeline | ~3–5 days, one-off, amortised across every client |
| Ongoing | folded into the ~1.5 days/month of [managed scope](managed-scope.md#what-it-costs-per-client) |

No recurring cloud cost. The bet is paid in engineering, once.

## Module specification

Crossplane runs in the cluster, so most of this belongs to the catalog. What
the foundations module owes it:

| Variable | Default | Constraint |
| --- | --- | --- |
| `crossplane_application_id` | module-created | the IAM application the provider authenticates as |
| `crossplane_policy_permission_sets` | **none — required** | scoped to the Project, never Organization-wide |
| `crossplane_allowed_cidrs` | inherits the gateway egress | the IP condition on that policy |

Absent by decision: the provider install itself, `ProviderConfig`,
Compositions — all catalog objects, shipped in the OCI artifact.

## Sources

Read 14 September 2026. Repository metadata, release dates, commit history
and issue state read from the GitHub API on that date; resource counts from
`package/crds` and the Terraform provider's `docs/resources`.

[Crossplane provider for Scaleway][xp-scw] · [its README][xp-readme] ·
[issue #201][xp-201] · [Upjet][upjet] · [Scaleway's Crossplane
tutorial][scw-tuto] · [provider-terraform][pt] · [tofu-controller][tofu] ·
[Terraform provider for Scaleway][tf-scw] · [Crossplane
documentation][xp-docs].

[xp-scw]: https://github.com/scaleway/crossplane-provider-scaleway
[xp-readme]: https://github.com/scaleway/crossplane-provider-scaleway/blob/main/README.md
[xp-201]: https://github.com/scaleway/crossplane-provider-scaleway/issues/201
[upjet]: https://github.com/crossplane/upjet
[scw-tuto]: https://www.scaleway.com/en/docs/tutorials/get-started-crossplane-kubernetes/
[pt]: https://github.com/crossplane-contrib/provider-terraform
[tofu]: https://github.com/flux-iac/tofu-controller
[tf-scw]: https://github.com/scaleway/terraform-provider-scaleway
[xp-docs]: https://docs.crossplane.io/
