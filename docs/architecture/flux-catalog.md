---
title: The Flux catalog
description: How the catalog is rendered from the client's inputs and reconciled by the Flux Operator, and why it is built that way.
sidebar:
  order: 1
---

The catalog is the part of the socle that runs in the cluster: one Flux
Operator `ResourceSet` per module, shipped in the signed artifact, rendered
from the inputs OpenTofu validated. What you write is in
[Configure a cluster](../guides/configure.md); the rules a module follows are
in the [Catalog module standard](../reference/catalog-module-standard.md).

## Three roles

| Role | Owner | Holds |
| --- | --- | --- |
| Inputs | OpenTofu, in your root | cloud, cluster identity, socle version, `kube` |
| Templates | the artifact, `ghcr.io/do-now-io/socle/flux-modules` | one `ResourceSet` per module, one overlay per cloud |
| Rendering | the Flux Operator, in the cluster | reads the inputs, renders, reconciles, garbage-collects |

OpenTofu knows the catalog only as a schema, the artifact knows no client,
and the operator joins them: no client repository, no templating in OpenTofu.

## What OpenTofu deposits

[`opentofu/bootstrap`](../../opentofu/bootstrap/main.tf) applies, in order:

| # | Release or resource | Where | Why it is here |
| --- | --- | --- | --- |
| 1 | `cilium` | aws, azure | the cluster has no CNI ([Cilium before Flux](cilium-before-flux.md)) |
| 2 | `coredns` | aws | removing the VPC CNI removed CoreDNS too |
| 3 | EKS add-ons: Pod Identity Agent, snapshot controller, EBS CSI, EFS CSI (off by default) | aws | the agent must run before any module asks for an identity |
| 4 | `flux-operator` | every cloud | pinned exactly (`operator_version`, 0.60.0) |
| 5 | `flux-instance` | every cloud | the controllers, **no `sync` block** |
| 6 | `socle` | every cloud | the envelope, two objects below |

- **`ResourceSetInputProvider` `flux-system/socle`**: your configuration, as
  OpenTofu validated and normalised it. Every module reads this one provider.
- **`ResourceSet` `flux-system/socle-root`**: renders the `OCIRepository`
  `socle` (URL, tag, optional pull secret, cosign `verify`) and the
  `Kustomization` `socle` on `./clusters/<cloud>`. It is Ready only when
  every module is: that, not a green apply, is convergence.

<details>
<summary>Under the hood</summary>

The envelope is a local chart, [`manifests/`](../../opentofu/bootstrap/manifests/),
whose only Helm expression is `toYaml .Values.inputs`; the `<< >>` delimiters
are the operator's. `socle-root` uses `resourcesTemplate`, a raw string,
because the optional `secretRef` adds or drops a whole key. The `socle`
Kustomization has `prune: true`, `wait: true` and `deletionPolicy:
WaitForTermination`. The envelope's chart version equals `VERSION`: the helm
provider re-applies a local chart only when its version or values change.

What the inputs hold (`defaultValues`, the bootstrap's `inputs` output):

| Path | What it is |
| --- | --- |
| `cloud` | `aws`, `gcp`, `azure` or `scaleway`; picks `./clusters/<cloud>` |
| `cluster.name`, `.environment`, `.owner`, `.region`, `.accountId` | the cluster's identity; `accountId` on aws only |
| `socle.url`, `.version`, `.pullSecret` | where the artifact is pulled from |
| `cosign.issuer`, `.subject` | the identity the signature must match |
| `modules.<module>.<attribute>` | every module, every attribute, your values over the defaults |
| `cilium.installed`, `.gatewayApi`, `.hubble` | what the bootstrap decided about the network |
| `gateway.className`, `.shared`, `.namespace`, `.certificateArn` | the GatewayClass, whether the shared Gateways exist, their certificate on aws |
| `storage.snapshots` | the CSI snapshot controller is installed (aws) |

The schema is [`catalog.tf`](../../opentofu/bootstrap/catalog.tf): `kube` is
`any`, validated against it at plan,
then merged over the defaults, so every attribute exists and templates test
values, never presence. What Flux deploys per cloud is declared again in
`oci/clusters/<cloud>/kustomization.yaml`;
[`check-catalog-clouds.sh`](../../.github/scripts/check-catalog-clouds.sh)
fails CI when the two disagree.

</details>

## How a module template is written

Each rule was measured on a live cluster; the checklist is the
[Catalog module standard](../reference/catalog-module-standard.md).

- **One provider**: `inputsFrom` the `ResourceSetInputProvider` `socle`,
  never inline inputs.
- **The toggle is on each resource**:
  `fluxcd.controlplane.io/reconcile: << if inputs.modules.<m>.enabled >>enabled<< else >>disabled<< end >>`
  on every object's own annotations. In `commonMetadata` it is not templated.
- **Cloud-specific values come from `inputs.cloud`**, or a Kustomize patch in
  the overlay, never from OpenTofu (`hello` shows both).
- **A module carries its own cloud access** as Crossplane resources
  ([Module IAM](module-iam.md)).
- **Deleting a `ResourceSet` uninstalls everything it rendered.**

## How values merge

The `HelmRelease` has no inline `values:`; its `valuesFrom` reads, in order:

1. `<module>-socle-values`, a ConfigMap with the socle's defaults;
2. `<module>-client-values`, a ConfigMap from `kube.<module>.values`;
3. the Secret named in `values_secret`, `optional: true`.

Later entries win, so yours beat the socle's, and `values` beats a named
attribute on the same key. Secrets are refused in `values`, which reaches the
state and a ConfigMap.

<details>
<summary>Under the hood</summary>

helm-controller merges `spec.values` over `valuesFrom`, so a socle default
written inline would beat you; moved into the first reference, it loses.
Both ConfigMaps carry the module's toggle and `reconcile.fluxcd.io/watch:
Enabled`, so a change reconciles at once. An overlay cannot JSON-patch one
value by path any more: per-cloud values go in the socle-values document,
under `<< if eq inputs.cloud "aws" >>`.

</details>

## CRDs when a module is off

Turning a module off garbage-collects what it rendered. Its CRDs:

| Module | CRDs when off | Why |
| --- | --- | --- |
| `gateway_api` | kept | `deletionPolicy: Orphan`: deleting a CRD deletes every Gateway and route |
| `external_secrets` | kept | `helm.sh/resource-policy: keep`: your `ExternalSecret`s and stores outlive it |
| `keda` | kept | `helm.sh/resource-policy: keep`: your `ScaledObject`s outlive it |
| `velero` | kept | `cleanUpCRDs: false`: a re-enable re-syncs `Backup`s from the bucket |
| `crossplane` | kept | the core applies them outside Helm; module roles still declared are orphaned in the cloud |
| `kyverno` | **deleted** | the chart's default: every Kyverno policy goes with them |

The same holds for a full [Uninstall](../guides/uninstall.md).

## Uninstall order

`tofu destroy` removes the envelope, then the instance, then the operator.
`deletionPolicy: WaitForTermination` on the `socle` Kustomization holds the
envelope until every catalog `ResourceSet` is gone; without it, five survived
with their finalizer on CI's first destroy. The procedure is in
[Uninstall](../guides/uninstall.md).

## Measured

- 2026-09-21, floci 1.5.34, flux-operator 0.60.0, Flux 2.9.5: apply 62 s; a
  value change rendered in 5 s; a module off garbage-collected in 10 s;
  second plan empty.
- 2026-09-30, `e2e.yaml`, floci 2.1.0: `socle-root` Ready 46 to 56 s after
  Chainsaw starts; `tofu destroy -target=module.socle` leaves nothing, in 28 s.
