---
title: Overview
description: How OpenTofu, the bootstrap, Flux and the ResourceSets fit together, from one OpenTofu file to a converged cluster.
sidebar:
  order: 0
---

The socle turns one OpenTofu file into a managed Kubernetes cluster running a
chosen set of platform modules, and keeps it converged. In one apply,
OpenTofu creates the cluster and hands it its inputs; Flux, through the Flux
Operator, then pulls a signed artifact and renders the catalog from them.

```text
main.tf ──▶ tofu apply ──▶ foundations: network, cluster, nodes, identities
                      └──▶ bootstrap: [Cilium, CoreDNS, EKS add-ons], flux-operator,
                                      flux-instance, envelope (inputs + socle-root)
                                                     │
ghcr.io/do-now-io/socle/flux-modules ───verified pull──▶ Flux ──▶ clusters/<cloud>
                                                                  └▶ one ResourceSet per module
```

## The layers

| Layer | What it is | Code | Owned by |
| --- | --- | --- | --- |
| Foundations | One module per cloud: network, cluster, the nodes the socle starts on, identities | [`opentofu/aws`](../../opentofu/aws/), `gcp`, `azure`, `scaleway` | OpenTofu |
| Bootstrap | Cilium and CoreDNS where the cloud has none, the EKS add-ons, the Flux Operator and instance, the envelope of inputs | [`opentofu/bootstrap`](../../opentofu/bootstrap/) | OpenTofu, same apply |
| Root | The one apply: calls both, configures the providers | [`opentofu/clusters/aws`](../../opentofu/clusters/aws/) (AWS only so far) | the socle; your `main.tf` calls it |
| Catalog | One `ResourceSet` per module, one overlay per cloud | [`oci/`](../../oci/) | Flux, from the signed artifact |

## The positions

- **Your configuration lives in your Git, as OpenTofu**: `socle_version`,
  `<cloud> = {…}`, `kube = {…}` (and `cilium`, `coredns`, `eks_addons` where
  they apply). Flux never syncs from your repository.
- **OpenTofu ships inputs only**, through `helm_release` as an applier; the
  Flux Operator templates
  ([The Flux catalog](flux-catalog.md)).
- **One apply**, foundations and bootstrap in the same root. Two cases need
  more: [When one apply is not enough](../guides/troubleshooting.md#when-one-apply-is-not-enough).
- **`socle_version` pins both** the module sources and the artifact tag
  ([Distribution](distribution.md)).
- **The signature is always checked** by Flux, on every reconciliation.
- **A module carries its own cloud access**, never the foundations
  ([Module IAM](module-iam.md)).

After the apply, the cluster pulls the artifact every minute, verifies it,
and each `ResourceSet` renders its module, or nothing when it is off. A change
of `kube` is re-rendered within seconds of its apply.

## How the root reaches the cluster

Each foundations module outputs `helm_kubernetes`, so the root's provider is
one line on every cloud:

```hcl
provider "helm" {
  kubernetes = module.foundations.helm_kubernetes
}
```

It holds no token: an exec plugin gets a short-lived one from the runner's
ambient credentials.

<details>
<summary>Under the hood</summary>

The object is `{ host, cluster_ca_certificate, exec = { api_version,
command, args } }`.

| Cloud | Exec | State |
| --- | --- | --- |
| AWS | `aws eks get-token --cluster-name …` | works; the root applies with it on floci |
| GCP | `gke-gcloud-auth-plugin`, host is the DNS endpoint | output exists; no GCP root yet |
| Azure | `kubelogin get-token --login azurecli --server-id 6dae42f8-4368-4678-94ff-3960e28e3630` | needs Entra ID authentication, which `opentofu/azure` does not configure yet |
| Scaleway | `sh -c` emitting an `ExecCredential` from `SCW_SECRET_KEY` | output exists; no Scaleway root yet |

No `kubernetes` provider exists in the chain. On aws
the bootstrap does not `depends_on` the whole foundations module: Cilium
follows the cluster alone (the nodes become Ready only once it runs), and
everything else follows the node group through `schedulable_nodes`
([Cilium before Flux](cilium-before-flux.md)).

</details>
