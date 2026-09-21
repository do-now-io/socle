# Installing Flux, on four clouds

How a cluster starts pulling the socle. One decision for EKS, GKE, AKS and
Kapsule — nothing here is cloud-specific, which is the point.

| Question | Position |
| --- | --- |
| Installer | `flux-operator`, by Helm |
| `flux bootstrap` CLI | Refused — an out-of-band step, and a Git model the socle does not have |
| `flux_bootstrap_git` provider | Refused — same Git model, and it couples Flux's lifecycle to the cluster's |
| Where it runs | A second root module, after foundations, with its own state |
| Inside the foundations module | Refused — three providers instead of one, and a provider configured from its own apply |
| What the cluster pulls | One `OCIRepository`, pinned to a tag |
| Signature | cosign, verified by Flux on every reconciliation |
| Operator version | Pinned exactly — it is pre-1.0 |
| Flux version | `2.x`, converged by the operator |
| Image automation controllers | Absent — the version moves through Git |
| Licence | **AGPL-3.0, accepted with conditions** |

## Why not the CLI

`flux bootstrap` is a command a human or a script runs with a kubeconfig and a
Git token. The product forbids that shape twice over: "100% GitOps, no
out-of-band scripts" in the README, and "a single apply, no out-of-band step"
in the [conformance checklist](standards/opentofu-module.md).

The deeper mismatch is the model. **`flux bootstrap` writes Flux's own
manifests into a Git repository and syncs the cluster from there.** The socle
is distributed as one signed OCI artifact, pinned by tag. Bootstrapping from
Git would add a distribution channel the product does not have, and a
write-scoped Git token per client to create, rotate and revoke — on four
clouds.

The `flux` Terraform provider's `flux_bootstrap_git` resource is declarative,
which fixes the first objection and not the second: it is the same Git model.

## Why not inside the foundations module

Each foundations module declares exactly one provider, its cloud's. Adding
`helm` — and, for a `kubernetes_manifest`, `kubernetes` — would make it three,
and would configure a provider from attributes the same apply produces. That
plans badly before the cluster exists and destroys worse afterwards.

**So: a second root module, applied against the cluster foundations created,
with its own state.** The modules keep their promise — "provisions an empty
shell, then steps away" — and the two lifecycles stay separable: Flux can be
reinstalled without touching the cluster, and the cluster destroyed without
unwinding Flux first.

## Why the operator

| | `flux-operator` | Flux manifests, applied directly |
| --- | --- | --- |
| Flux's own upgrades | A version field the operator converges | A new set of manifests to apply |
| Drift on the controllers | Reconciled | Whatever was applied last |
| Cluster-specific wiring | `cluster.type` — one enum for four clouds | Per-cloud patches |
| Reporting | `FluxInstance` status, one object to watch | Read the Deployments |

The operator makes Flux itself a reconciled resource rather than a one-time
install, which is what lets the same two Helm releases serve four clouds with
a single differing value.

### What it costs, and it is not nothing

**It is AGPL-3.0.** Flux is Apache-2.0; the operator is not. Running it
unmodified inside a client's cluster is mere aggregation and raises nothing.
**Forking it would.** Article 13 reaches any modified version offered over a
network, and `crossplane-iac.md` already contemplates a factory-owned fork of a
different dependency, so the reflex exists in this project. The position is:
**use it unmodified, and treat a fork as a decision that needs legal review,
not an engineering shortcut.** If a patch becomes necessary, upstreaming it is
the cheaper path.

**It is pre-1.0** — v0.60.0, September 2026. `crossplane-iac.md` refuses
`tofu-controller` partly for being "still 0.x", so retaining the operator is a
deliberate inconsistency, and it is recorded here rather than glossed: the
operator is maintained by the people who maintain Flux, publishes steadily,
and its blast radius is one namespace on a cluster that can be re-bootstrapped
in minutes. `tofu-controller` was refused for being a second reconciler over
infrastructure state — a far larger claim than installing controllers.

The mitigation is the pin: `operator_version` takes an exact `x.y.z` and the
module refuses a range. On a pre-1.0 dependency a minor is not a contract.

## What the cluster pulls

One `OCIRepository` and one `Kustomization`, both named `socle`, created by the
operator from the instance's `sync` block. The name is fixed rather than
derived: it is immutable in the CRD, so deriving it from the cluster name
would make renaming a cluster a destroy.

**The reference is required, and `latest`, `main`, `master` and `HEAD` are
refused by validation.** A cluster that follows a moving head cannot answer
"which version is deployed", which is the one question a versioned
distribution exists to answer.

## Cosign

The foundations READMEs carry a warning: *OpenTofu does not verify OCI
signatures.* Flux does — `OCIRepository` supports `verify.provider: cosign`,
and re-checks on every reconciliation rather than once at install. Moving the
pull from OpenTofu to Flux is therefore a security improvement, not only a
GitOps one.

**With one wrinkle, found while writing this: the `FluxInstance` sync spec has
no `verify` field.** Its fields are `name`, `interval`, `kind`, `url`, `ref`,
`path`, `pullSecret` and `provider` — signature verification is not among them.

So verification is expressed as a **kustomize patch** on the generated
`OCIRepository`, which the operator supports through `instance.kustomize.patches`.
That is why the sync name is fixed: the patch needs a target.

**This is the one part of the design that is unproven.** The mechanism is
sound on paper; whether the operator applies patches to the objects it
generates for the sync, and not only to the Flux components, has to be checked
on the first cluster:

```sh
kubectl -n flux-system get ocirepository socle -o jsonpath='{.spec.verify}'
```

An empty result means the artifact is pulled unverified. If the patch does not
reach it, the fallbacks in order of preference are: raise it upstream, or drop
`instance.sync` entirely and ship the root `OCIRepository` as a small chart of
our own.

## Configuration, and where it lives

**In the cluster's own root configuration — and as little of it as possible.**

The temptation is to give each cluster a folder holding everything about it.
The objection is not the folder, it is what goes in it: duplication across
four clouds times three environments times N clients, silent divergence
between dev and prod, and — most of all — configuration that OpenTofu applies
once where Flux would reconcile it continuously.

**The line: a cluster's folder holds bindings, not policy.** Which project,
which name, who may reach the API server, which tag is pinned. Four to six
values, each one without a safe default. Everything else — the Flux version,
the components, the catalog's composition — belongs to the module's defaults
or to the fleet repository, where Flux owns it.

## Module specification

[`opentofu/bootstrap`](../opentofu/bootstrap), one module for four clouds.

| Variable | Default | Constraint |
| --- | --- | --- |
| `cluster_name`, `environment`, `owner` | **none — required** | stamped as labels on every object |
| `cluster_type` | `kubernetes` | `aws`, `azure`, `gcp` wire workload identity; Scaleway has none |
| `sync_url`, `sync_ref` | **none — required** | `oci://` for an OCIRepository; moving heads refused |
| `operator_version` | `0.60.0` | exact `x.y.z`, no ranges |
| `flux_version` | `2.x` | converged by the operator |
| `cosign_verification_enabled` | `true` | OCIRepository only |
| `cosign_identity` | `null` | issuer and subject, both non-empty |
| `flux_components` | four controllers | source and kustomize cannot be dropped |

Absent by decision: any Git bootstrap variable, any Git token, the image
automation controllers, a `kubernetes` provider.

## Sources

Read 21 September 2026.
[flux-operator](https://github.com/controlplaneio-fluxcd/flux-operator) —
AGPL-3.0, v0.60.0 published 11 September 2026 ·
[`FluxInstance` API](https://github.com/controlplaneio-fluxcd/flux-operator/blob/v0.60.0/api/v1/fluxinstance_types.go),
where the `Sync` struct's fields are defined ·
[operator docs](https://fluxoperator.dev/docs/crd/fluxinstance/) ·
charts at `oci://ghcr.io/controlplaneio-fluxcd/charts`, versions read from the
registry · [Flux OCIRepository
verification](https://fluxcd.io/flux/components/source/ocirepositories/#verification)
· [terraform-provider-flux](https://github.com/fluxcd/terraform-provider-flux).
