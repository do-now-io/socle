---
title: gitops decisions
description: The decisions behind the gitops module, one per section, each with its status.
sidebar:
  order: 10
---

The gitops module is the client's entry point: Flux applies one path of
their repository, ArgoCD ships what it declares. Why the socle reads a
client repository at all, and why its key may go through the state, is
[SOCLE-36](socle.md#socle-36-flux-applies-the-clients-entry-point-argocd-ships-the-applications).

## GITOPS-01: One Secret in flux-system, copied into argocd

**accepted** · 2026-10-29 · [`opentofu/bootstrap/manifests/templates/gitops.yaml`](../../opentofu/bootstrap/manifests/templates/gitops.yaml), [`oci/catalog/gitops/resourceset.yaml`](../../oci/catalog/gitops/resourceset.yaml)

**Context.** Flux and ArgoCD read the same repository with the same key,
under different names: Flux's `GitRepository` wants `identity` and
`known_hosts`, ArgoCD's repository Secret `type`, `url` and
`sshPrivateKey`, labelled `argocd.argoproj.io/secret-type: repository` in
`argocd`. The bootstrap cannot write into `argocd`: the argocd module
renders that namespace, after the bootstrap. Rendering the key from the
inputs would put it in a custom resource in clear. The Flux Operator's
`fluxcd.controlplane.io/copyFrom` fills a Secret of a ResourceSet from
another, and re-copies when the source changes if the source is labelled
`reconcile.fluxcd.io/watch: Enabled`; it replaces the copy's whole data
(`internal/copier/resources.go`, v0.61.0).

**Decision.** The envelope renders `flux-system/socle-gitops` with every key
both readers need — `identity`, `known_hosts`, `type`, `url`,
`sshPrivateKey` — and the module renders
`argocd/socle-gitops-repository` with `copyFrom` on it. The key reaches the
release through `set_sensitive`, base64-encoded so Helm's `--set` parser
never splits it.

**Consequences.** One key to rotate: a new `gitops_ssh_key` and an apply
update both Secrets. Each holds the other reader's keys too, which neither
reads. A client who already declares a repository Secret for the same url
has two, and ArgoCD picks one of them: they remove theirs. A `repo-creds`
template for the same organisation stays theirs and keeps serving their
other repositories; an exact `repository` match wins over it.

**Sources.** flux-operator v0.61.0 `docs/api/v1/resourceset.md` (Copying data from existing ConfigMaps and Secrets) · Flux `GitRepository` v1, SSH authentication · ArgoCD declarative setup, repositories and repository credentials.

## GITOPS-02: Off orphans what the path applied

**accepted** · 2026-10-29 · [`oci/catalog/gitops/resourceset.yaml`](../../oci/catalog/gitops/resourceset.yaml) (`deletionPolicy: Orphan`)

**Context.** With `prune: true`, a deleted `Kustomization` deletes what it
applied (`deletionPolicy` defaults to `MirrorPrune`). Here that is every
`Application` of the client; with ArgoCD's
`resources-finalizer.argocd.argoproj.io`, every workload they deployed.
Turning the module off, or a ResourceSet re-render that drops it, would be
a cluster-wide delete.

**Decision.** `prune: true`, `deletionPolicy: Orphan`. An object removed
from the path is deleted; the `Kustomization` deleted deletes nothing.

**Consequences.** Removing an `Application` from the path deletes it, and
its finalizer, when the client set one, its workloads: the GitOps contract.
Off, the Applications stay and ArgoCD keeps syncing them, but nothing
applies the path any more, and the repository Secret goes. Turning it back
on adopts them again by server-side apply.

**Sources.** Flux `Kustomization` v1, `spec.deletionPolicy` · ArgoCD, app deletion and finalizers.

## GITOPS-03: The ResourceSet does not wait on the client's repository

**accepted** · 2026-10-29 · [`oci/catalog/gitops/resourceset.yaml`](../../oci/catalog/gitops/resourceset.yaml) (`wait: false`)

**Context.** Every ResourceSet with `wait: true` is Ready only once all it
applied is; `socle-root`'s `Kustomization` waits on every module's
ResourceSet. Waiting here would tie the socle's own Ready to the client's
repository: a wrong key, a deploy key not yet added on GitHub or a bad
manifest in the path would turn `socle-root` red.

**Decision.** `wait: false`. The ResourceSet is Ready once its three
objects are applied; whether the path is fetched and applied is the
`Kustomization` `gitops`'s status.

**Consequences.** The client watches `kubectl -n flux-system get
gitrepository,kustomization gitops`; the monitoring module's Flux rules
alert on it like on any other Flux object. A missing source Secret still
fails the ResourceSet: that one is the socle's.

**Sources.** flux-operator v0.61.0 `docs/api/v1/resourceset.md` (`wait`).

## GITOPS-04: GitHub's host keys pinned, any other host's given

**accepted** · 2026-10-29 · [`opentofu/bootstrap/main.tf`](../../opentofu/bootstrap/main.tf) (`local.github_known_hosts`), [`oci/catalog/argocd/resourceset.yaml`](../../oci/catalog/argocd/resourceset.yaml) (`configs.ssh.extraHosts`)

**Context.** Flux refuses an SSH host whose key is not in `known_hosts`.
Fetching it at reconcile time (`ssh-keyscan`) trusts whoever answers. GitHub
publishes its keys (`api.github.com/meta`) and rotated one once, in 2023.
ArgoCD's chart already trusts GitHub, GitLab, Bitbucket and Azure DevOps.

**Decision.** `known_hosts` empty means GitHub's three published keys, read
2026-10-29 and pinned in the bootstrap. Another SSH host is refused at plan
without `known_hosts`, which the client takes from their host; the argocd
module then adds the same lines to ArgoCD's `configs.ssh.extraHosts`.

**Consequences.** A GitHub key rotation is a socle release, or a
`known_hosts` the client sets meanwhile. A self-hosted GitLab works with no
step beyond the input.

**Sources.** GitHub, "GitHub's SSH key fingerprints" · `https://api.github.com/meta` · argo-cd chart 10.10.5 `values.yaml` (`configs.ssh`).

## GITOPS-05: Flux keeps the helm parameters ArgoCD Image Updater writes

**accepted** · 2026-10-29 · [`oci/catalog/gitops/resourceset.yaml`](../../oci/catalog/gitops/resourceset.yaml) (`spec.ignore`), [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf) (`gitops.ignore`)

**Context.** Image Updater's `write-back argocd`, which the
argocd-image-updater module runs, writes the new tag or digest to
`spec.source.helm.parameters`, or `spec.sources[N].helm.parameters`, of an
Application, by an Update through the Kubernetes API. Under this module
those Applications are applied by Flux, with server-side apply, as
`kustomize-controller`. The Application CRD of argo-cd v3.5.5 has no
`x-kubernetes-list-type` and no `x-kubernetes-map-type` anywhere.
`spec.source` is an object, merged field by field: Flux owns `repoURL`,
`path`, `helm.valueFiles`, Image Updater owns `helm.parameters`, and neither
undoes the other — Flux with Image Updater on single-source Applications is
an established setup. `spec.sources` is an array with no list keys, so
atomic: Flux owns it whole. And a client who deploys the socle's charts with
values kept in Git needs `sources`: the chart, then a `ref: values` source
for its `$values/...` value files.

Measured on a GKE Autopilot cluster with `0.0.0-gitops-entry-point.3201a6b`,
on a multi-source Application: a merge patch of
`spec.sources[0].helm.parameters` under the field manager
`argocd-image-updater` took the whole `spec.sources`; the next
reconciliation, without force, re-applied it from Git and the parameters
were gone, `kustomize-controller` owning `spec.sources` again.

Options weighed: Flux's own `spec.ignore` (below); Flux applying one root
Application per path, ArgoCD syncing the children with `ignoreDifferences`
on `helm.parameters` and `RespectIgnoreDifferences` (Image Updater's
app-of-apps pattern — ArgoCD would manage the child Applications again);
`kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` per Application (Git changes
to them never reach the cluster); `ssa: Merge` (no help: `spec.sources` is
declared, as one value); Image Updater's `write-back git` (a write
credential and a commit per image); single-source Applications only (no
`$values`).

Flux's `Kustomization` has `spec.ignore` (kustomize-controller v1.9.6, in
the Flux 2.9.6 flux-operator 0.61.0 ships). An ignored JSON pointer is left
out of drift detection; when it differs on a reconciliation, Flux strips it
from the payload if another Apply manager owns it, otherwise it copies the
cluster's value into the payload ("Adopt"). Image Updater writes by Update,
so its parameters are adopted, and the rest of `spec.sources` keeps
following Git. A pointer absent on both sides is not drift, so listing
indexes that do not exist costs nothing (`fluxcd/pkg/ssa` v0.76.2,
`computeDriftedPaths`, `lookupJSONPointer`). Pointers take no wildcard.
Measured on the same cluster: with `ignore: [{paths:
[/spec/sources/0/helm/parameters, /spec/source/helm/parameters], target:
{group: argoproj.io, kind: Application}}]` patched on the `Kustomization`,
the same write survived two forced reconciliations, the `Kustomization`
Ready.

**Decision.** The module's `Kustomization` ignores `helm.parameters` on
every `argoproj.io` `Application` of the path, by default: `/spec/source/…`
and `/spec/sources/0` to `4/…`. `kube.gitops.ignore` appends the client's
own rules, in Flux's shape, validated at plan. Flux keeps applying the
children; ArgoCD manages no Application.

**Consequences.** `write-back argocd` works on single- and multi-source
Applications up to five sources; a sixth needs a client rule. The cluster's
`helm.parameters` win over Git on every Application of the path: a client
who sets them in Git sees them applied on creation only. Owed on a real
cluster: a `valueFiles` change in Git still applies while the parameters
stay. The e2e proves the rule on floci: a merge patch of the parameters by
another manager survives a forced reconciliation.

**Sources.** #131, #132 · argo-cd v3.5.5 `manifests/crds/application-crd.yaml` · Flux `Kustomization` v1, Ignore Rules · `fluxcd/pkg/ssa` v0.76.2 `manager_apply.go` · Argo CD Image Updater, write-back methods.
