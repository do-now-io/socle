---
title: The Flux catalog
description: How the catalog is rendered from the client's inputs and reconciled by the Flux Operator, and why it is built that way.
sidebar:
  order: 1
---

The catalog is the part of the socle that runs inside the cluster: one Flux
Operator `ResourceSet` per module, shipped in the signed OCI artifact,
rendered from the inputs OpenTofu validated. This page explains how the
pieces meet. What a client writes is in [Configure a cluster](../guides/configure.md);
the schema is in [Inputs](../reference/inputs.md); the rules a new module
follows are in the [Catalog module standard](../reference/catalog-module-standard.md).

## Three roles

| Role | Owner | Holds |
| --- | --- | --- |
| Inputs | OpenTofu, in the client's root | cloud, cluster identity, socle version, `kube` |
| Templates | The socle OCI artifact, `ghcr.io/do-now-io/socle/flux-modules` | one `ResourceSet` per catalog module, one overlay per cloud |
| Rendering | The Flux Operator, in the cluster | reads the inputs, renders, reconciles, garbage-collects |

The OpenTofu module knows the catalog only as a schema. The artifact knows
nothing about any client. The operator joins the two with its own API, so no
client repository and no templating step in OpenTofu exist
([SOCLE-01](../decisions/socle.md#socle-01-opentofu-ships-the-inputs-the-flux-operator-renders-them)).

## What OpenTofu deposits

The bootstrap module, [`opentofu/bootstrap`](../../opentofu/bootstrap/main.tf),
applies everything that runs in the cluster with the `helm` provider, plus
the EKS add-ons with the `aws` provider on aws. In order:

| # | Release or resource | Where | Why it is here |
| --- | --- | --- | --- |
| 1 | `cilium` | aws, azure | the cluster is created with no CNI ([Cilium before Flux](cilium-before-flux.md)) |
| 2 | `coredns` | aws | the flag that removed the VPC CNI removed CoreDNS too |
| 3 | EKS add-ons: Pod Identity Agent, snapshot controller, EBS CSI, EFS CSI (off by default) | aws | they need nodes and a network; the agent must run before any module asks for an identity |
| 4 | `flux-operator` | every cloud | the official chart, pinned exactly (`operator_version`, 0.60.0) |
| 5 | `flux-instance` | every cloud | which controllers run, health check on, **no `sync` block** |
| 6 | `socle` | every cloud | the envelope: two literal objects, below |

The envelope is a local chart, [`manifests/`](../../opentofu/bootstrap/manifests/),
whose only Helm expression is `toYaml .Values.inputs`:

- **`ResourceSetInputProvider` `flux-system/socle`**, type `Static`. Its
  `defaultValues` are the client's configuration as OpenTofu validated and
  normalised it. Every catalog `ResourceSet` reads this one provider by name
  ([SOCLE-12](../decisions/socle.md#socle-12-one-input-provider-per-cluster)).
- **`ResourceSet` `flux-system/socle-root`**, which renders what the cluster
  pulls: an `OCIRepository` `socle` (the artifact URL and tag from the
  inputs, an optional `secretRef`, and a cosign `verify` block) and a
  `Kustomization` `socle` on `./clusters/<cloud>`, with `prune: true`,
  `wait: true` and `deletionPolicy: WaitForTermination`.

The `<< >>` delimiters belong to the operator, not to Helm: Helm deposits the
file as it is. `socle-root` uses `resourcesTemplate`, a raw multi-document
string, rather than the structured `resources` list, because the optional
`secretRef` is a block `<< if >>`/`<< end >>` that adds or drops a whole key,
which only text templating can do.

Why the root source is a `ResourceSet` rather than the `FluxInstance`'s
`sync` block, and why Helm is the applier at all, are
[SOCLE-07](../decisions/socle.md#socle-07-the-root-source-is-a-resourceset-not-the-fluxinstance-sync)
and [SOCLE-08](../decisions/socle.md#socle-08-helm_release-is-the-applier-never-the-templater).
The envelope's chart version equals `VERSION`: the helm provider re-applies a
local chart only when its version or its values change.

### What the inputs hold

The `inputs` output of the bootstrap module is exactly what lands in
`defaultValues`, and the paths the templates read:

| Path | What it is |
| --- | --- |
| `cloud` | `aws`, `gcp`, `azure` or `scaleway`; picks the overlay `./clusters/<cloud>` |
| `cluster.name`, `.environment`, `.owner`, `.region`, `.accountId` | the cluster's identity; `accountId` on aws only (S3 bucket names are global) |
| `socle.url`, `.version`, `.pullSecret` | where the artifact is pulled from |
| `cosign.issuer`, `.subject` | the identity the signature must match |
| `modules.<module>.<attribute>` | every catalog module, every attribute, the client's values over the defaults |
| `cilium.installed`, `.gatewayApi`, `.hubble` | what the bootstrap decided about the network; all false where the cloud operates Cilium |
| `gateway.className`, `.shared`, `.namespace`, `.certificateArn` | the GatewayClass a template targets (`cilium`, GKE's `gke-l7-global-external-managed`, or empty), whether the shared Gateways exist, and on aws their certificate |
| `storage.snapshots` | the CSI snapshot controller and its CRDs are installed (aws) |

## The catalog schema

[`catalog.tf`](../../opentofu/bootstrap/catalog.tf) holds one entry per
module, and its defaults are its schema: the attribute names a client may
set, and what each is when he does not. `kube` is typed `any` and validated
against it at plan: unknown module, unknown attribute, wrong kind, a module
not offered on this cloud, and each module's own rules
([SOCLE-11](../decisions/socle.md#socle-11-kube-is-typed-any-and-validated-against-the-catalog)).
`local.modules` then merges the client's values over the defaults, so every
module and every attribute exists in the inputs. Templates rely on that: they
test values, never presence.

The catalog is declared twice, on purpose. `catalog.tf` says what a client
may configure, and `catalog_clouds` on which clouds (absent means every
cloud). Each `oci/clusters/<cloud>/kustomization.yaml` says what Flux deploys
there. [`check-catalog-clouds.sh`](../../.github/scripts/check-catalog-clouds.sh)
fails CI when the two disagree in either direction. They travel together
because the module and the artifact share `socle_version`.

Cilium, CoreDNS and the EKS add-ons are not catalog modules: they precede
Flux. See [Cilium before Flux](cilium-before-flux.md).

## How a module template is written

Each rule below was measured on a live cluster; the checklist form is in the
[Catalog module standard](../reference/catalog-module-standard.md).

- **One provider.** `inputsFrom: [{ kind: ResourceSetInputProvider, name: socle }]`
  on every module; never inline inputs.
- **The toggle is on each resource.** `fluxcd.controlplane.io/reconcile:
  << if inputs.modules.<m>.enabled >>enabled<< else >>disabled<< end >>`
  goes on every rendered object's own `metadata.annotations`. In
  `commonMetadata` the operator does not template it: the literal string
  lands on the objects. Per resource, turning the module off removes its
  objects through garbage collection (10 s, measured), and turning it on
  recreates them.
- **Cloud-specific values come from `inputs.cloud`** in the template, or from
  a Kustomize patch in the `clusters/<cloud>/` overlay, never from OpenTofu.
  `hello` shows both: its message names the cloud through `inputs.cloud`, and
  each `clusters/<cloud>/hello-color.patch.yaml` paints podinfo in that
  cloud's colour.
- **A module carries its own cloud access** as Crossplane managed resources
  in its own `ResourceSet` ([Module IAM](module-iam.md)).
- **Deleting a `ResourceSet` uninstalls everything it rendered** (measured).

## How values merge

Every module with a chart takes `values`, free-form chart values in the
tfvars, and `values_secret`, the name of a Secret the client creates in the
module's namespace with a `values.yaml` key. The `HelmRelease` has no inline
`values:` block. Its `valuesFrom` lists three entries, in this order:

1. `<module>-socle-values`, a ConfigMap the template renders with the socle's
   defaults;
2. `<module>-client-values`, a ConfigMap rendered the same way from
   `inputs.modules.<m>.values`;
3. the client's Secret, when he named one, `optional: true`.

helm-controller merges `valuesFrom` in order and then merges `spec.values`
over the result. A socle default written inline would therefore beat the
client on every key both set; moved into the first reference, it loses to
him. Where a named attribute and `values` set the same key, `values` wins.
Both ConfigMaps carry the module's reconcile toggle and the
`reconcile.fluxcd.io/watch: Enabled` label, which makes helm-controller
reconcile the release as soon as they change. Secrets never go in `values`:
it reaches the OpenTofu state and a plain ConfigMap, so each module refuses
its chart's secret-bearing paths at plan. The decision is
[SOCLE-06](../decisions/socle.md#socle-06-the-clients-values-win).

A consequence: an overlay can no longer JSON-patch one value by path, because
the values are a YAML document inside a ConfigMap. Per-cloud values go in the
socle-values document, under `<< if eq inputs.cloud "aws" >>`.

## CRDs when a module is off

Turning a module off garbage-collects what its `ResourceSet` rendered. What
happens to the CRDs depends on who installed them:

| Module | CRDs when off | Mechanism |
| --- | --- | --- |
| `gateway_api` | kept | the `gateway-api-crds` Kustomization has `deletionPolicy: Orphan`: deleting a CRD would delete every Gateway and route with it |
| `external_secrets` | kept | `crds.annotations: helm.sh/resource-policy: keep`: the client's `ExternalSecret`s and stores outlive the module |
| `keda` | kept | `crds.additionalAnnotations: helm.sh/resource-policy: keep`: the client's `ScaledObject`s outlive the module |
| `velero` | kept | `cleanUpCRDs: false`: a re-enable re-syncs the `Backup` objects from the bucket |
| `crossplane` | kept | the core applies its CRDs itself at start, outside Helm; module roles still declared are orphaned in the cloud |
| `kyverno` | **deleted** | the chart's default: the CRDs go with the release, and every Kyverno policy in the cluster with them |

The same holds for a full uninstall: see [Uninstall](../guides/uninstall.md).

## Convergence

Helm's `wait` does not wait for a custom resource to be Ready, so a green
`tofu apply` proves the objects were deposited, not that they converged.
`socle-root` has `wait: true`: it is Ready when everything it applied is,
and the `socle` Kustomization it renders has `wait: true` over every catalog
`ResourceSet`. CI reads it; a client can:

```sh
kubectl -n flux-system get resourceset socle-root
```

## Uninstall order

`tofu destroy` removes the releases in reverse: the envelope, then the
instance, then the operator. Helm's uninstall `wait` only holds the envelope
until `socle-root` is gone, which happens as soon as the `socle`
Kustomization is finalized. Without more, that is as soon as
kustomize-controller has issued the deletes of the catalog `ResourceSet`s,
and the instance and the operator would go while the operator is still
finalizing them: five `ResourceSet`s survived with their finalizer the first
time CI ran a destroy. `deletionPolicy: WaitForTermination` on the `socle`
Kustomization holds it until every `ResourceSet` it pruned is gone. The
procedure is in [Uninstall](../guides/uninstall.md).

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-09-21 | floci 1.5.34, k3s v1.34.1, flux-operator 0.60.0, Flux 2.9.5, OpenTofu 1.12.6, helm provider 3.3.0 | plan with the cluster unknown: 5 to add; apply 62 s; a value change rendered in 5 s; a module off garbage-collected in 10 s; a version bump re-verified and upgraded in 10 s; second plan empty; a typo in an `object`-typed `kube` silently accepted, refused as `any` with validations |
| 2026-09-30 | `e2e.yaml`, floci 2.1.0 | fixture root applied in 47 s (cluster 18 s, operator 17 s, instance 15 s), real root in about 70 s; `socle-root` Ready 46 to 56 s after Chainsaw starts; a value patched into the input provider reaches podinfo in 13 s; `tofu destroy -target=module.socle` with `WaitForTermination`: the envelope's uninstall waits 12 s, the socle is gone in 28 s, nothing left; a second plan after the off/on mutation empty |
| 2026-09-30 | `e2e.yaml`, floci 2.1.0, first fully green run | jobs: `root` 4m21s, `hello` 5m12s, `gateway-api` 5m04s, `argocd` 6m06s, `crossplane` 7m50s, `external-dns` 10m12s; each spends about 1m40s before Chainsaw starts |
