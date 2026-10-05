---
title: Overview
description: How OpenTofu, the bootstrap, Flux and the ResourceSets fit together, from one tfvars file to a converged cluster.
sidebar:
  order: 0
---

The socle turns one tfvars file into a managed Kubernetes cluster running a
chosen set of platform modules, and keeps it converged. Two tools share the
work, in one apply: OpenTofu creates the cluster and hands it its inputs, and
Flux, through the Flux Operator, pulls a signed artifact and renders the
catalog from those inputs. After the apply, OpenTofu steps away until the
next change of the tfvars.

## The positions

| Question | Position |
| --- | --- |
| Where the client's configuration lives | In the client's Git, as OpenTofu: one root per cloud, one tfvars per cluster |
| What Flux syncs from | The socle's OCI artifact only, never a client repository |
| Who templates | The Flux Operator, through the `ResourceSet`s shipped in the artifact |
| What OpenTofu ships into the cluster | Inputs only: one `ResourceSetInputProvider`, one root `ResourceSet`, and before them what Flux needs to run |
| How OpenTofu ships them | `helm_release`, as an applier, never as a templater |
| Number of applies | One: foundations and bootstrap in the same root |
| The client's surface | `socle_version`, `<cloud> = {…}`, `kube = {…}` (and on aws/azure `cilium`, on aws `coredns` and `eks_addons`) |
| Validation of `kube` | `any` plus `validation` blocks against the catalog schema, at plan |
| Version pin | `socle_version` drives both module sources and the artifact tag |
| Signature | cosign keyless, verified by Flux on every reconciliation; cannot be turned off |

## The layers

| Layer | What it is | Code | Owned by |
| --- | --- | --- | --- |
| Foundations | One OpenTofu module per cloud: network, managed cluster, the nodes the socle starts on, identities | [`opentofu/aws`](../../opentofu/aws/), `gcp`, `azure`, `scaleway` | OpenTofu |
| Bootstrap | Cilium and CoreDNS where the cloud provides none, the EKS add-ons on aws, the Flux Operator and instance, and the envelope carrying the inputs | [`opentofu/bootstrap`](../../opentofu/bootstrap/) | OpenTofu, same apply |
| Root | The one apply: calls the two modules above, configures the providers | [`opentofu/clusters/aws`](../../opentofu/clusters/aws/) (AWS only so far) | the client, a copy he never edits |
| Catalog | One `ResourceSet` per module, one overlay per cloud | [`oci/`](../../oci/) | Flux, from the signed artifact |

```text
tfvars ──▶ tofu apply ──▶ foundations: network, cluster, nodes, identities
                     └──▶ bootstrap: [Cilium, CoreDNS, EKS add-ons], flux-operator,
                                     flux-instance, envelope (inputs + socle-root)
                                                    │
ghcr.io/do-now-io/socle/flux-modules ──verified pull──▶ Flux ──▶ clusters/<cloud>
                                                                 └▶ one ResourceSet per module
```

What the bootstrap deposits, and how the operator renders it, is in
[The Flux catalog](flux-catalog.md). Why Cilium comes first is in
[Cilium before Flux](cilium-before-flux.md). How a module gets cloud access
without changing the foundations is in [Module IAM](module-iam.md). How the
two artifacts are published, signed and released is in
[Distribution](distribution.md).

## How the root reaches the cluster

Each foundations module outputs `helm_kubernetes`, so the root's provider
block is one line, identical on every cloud:

```hcl
provider "helm" {
  kubernetes = module.foundations.helm_kubernetes
}
```

The object is `{ host, cluster_ca_certificate, exec = { api_version,
command, args } }`. It holds no token and no kubeconfig: the exec plugin gets
a short-lived token at call time from the runner's ambient credentials, the
same ones the cloud provider uses.

| Cloud | Exec | State |
| --- | --- | --- |
| AWS | `aws eks get-token --cluster-name …` | works; the root applies with it on floci |
| GCP | `gke-gcloud-auth-plugin`, host is the DNS endpoint | output exists; no GCP root yet |
| Azure | `kubelogin get-token --login azurecli --server-id 6dae42f8-4368-4678-94ff-3960e28e3630` | authenticates only a cluster with Entra ID authentication, which `opentofu/azure` does not configure yet |
| Scaleway | `sh -c` emitting an `ExecCredential` from `SCW_SECRET_KEY` | output exists; no Scaleway root yet |

The decision is
[SOCLE-13](../decisions/socle.md#socle-13-helm_kubernetes-is-an-exec-no-credential-in-the-state).
On aws the root's own `aws` provider serves both modules; elsewhere the
bootstrap's `aws` provider has no resource and is never configured.

## One root, one apply

The foundations and the bootstrap are called from one root, so a client
applies once: the plan passes with the cluster unknown, and a second plan is
empty. Each module still has its own providers. On aws the root does not make
the bootstrap `depends_on` the whole foundations module: that would hold
Cilium until the bootstrap nodes are Ready, and they become Ready only once
Cilium runs on them. Cilium follows the cluster alone; everything else
follows the node group through `schedulable_nodes`, which is also why it is
uninstalled before the nodes on a destroy.

Two cases need more than one apply, replacing the cluster and destroying it
with the API unreachable: see
[Troubleshooting](../guides/troubleshooting.md#when-one-apply-is-not-enough).
No `kubernetes` provider exists anywhere in the chain
([SOCLE-10](../decisions/socle.md#socle-10-no-kubernetes-provider)).

## After the apply

The cluster pulls `ghcr.io/do-now-io/socle/flux-modules:<socle_version>`
every minute, verifies its signature, and applies `clusters/<cloud>` from it:
the list of catalog `ResourceSet`s that cloud offers. Each `ResourceSet`
reads the inputs and renders its module, or nothing when the module is off.
A change of `kube` is a `tofu apply` that upgrades the envelope's inputs; the
operator re-renders within seconds. A change of `socle_version` moves the
module sources and the artifact tag together
([Upgrade the socle](../guides/upgrade.md)).
