---
title: gitops
description: Your repository's entry point, applied by Flux from the first apply — your ArgoCD Applications with no step by hand.
category: gitops
requires:
  - module: argocd
    why: the path holds ArgoCD Applications, whose CRD the argo-cd chart installs, and ArgoCD's repository Secret lives in its namespace
---

Flux lays the base up to your entry point; ArgoCD ships your applications.
With this module on, Flux applies one path of your repository — your root
ArgoCD Applications, and any cluster-wide object you keep there — and ArgoCD
gets the credential to read that repository. `tofu apply` is then the whole
bootstrap, a recreated cluster included. **Off by default.**

## Getting started

Create a deploy key, **read-only**, on your repository
(*Settings → Deploy keys → Add deploy key*, "Allow write access" unchecked),
with its private half in your secret store:

```sh
ssh-keygen -t ed25519 -N '' -C acme-prod-socle -f gitops
# gitops.pub goes to GitHub; gitops is the private half
```

Then point the module at the path and give the root the private half:

```hcl kube-start="gitops"
kube = {
  gitops = {
    enabled = true
    url     = "ssh://git@github.com/acme/platform"
    path    = "apps/acme-prod"
  }
}
```

```hcl
gitops_ssh_key = var.gitops_ssh_key # sensitive; from your secret store
```

Then `kubectl -n flux-system get kustomization gitops` shows the revision
applied, and `kubectl -n argocd get applications` your Applications.

## What it installs

| | |
| --- | --- |
| Chart | none |
| Namespace | none of its own: Flux's objects in `flux-system`, ArgoCD's Secret in `argocd` |
| Objects | `GitRepository` and `Kustomization` `flux-system/gitops`, the `Secret` `flux-system/socle-gitops` (from the bootstrap), and its copy `argocd/socle-gitops-repository`, ArgoCD's repository Secret |

## What you can set

Under `kube.gitops`:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on. Refused while `argocd` is off. |
| `url` | `""` | The repository: `ssh://git@<host>/<path>`, read with `gitops_ssh_key`, or `https://<host>/<path>` for a public repository, with no key. |
| `ref` | `"main"` | A branch, or a full reference such as `refs/tags/v1.2.0`. |
| `path` | `""` | What Flux applies, relative to the repository root; `""` is the root. |
| `known_hosts` | `""` | The SSH host's keys, as `ssh-keyscan` prints them. Empty: GitHub's published keys. Required for any other SSH host. |
| `ignore` | `[]` | Your own [drift-ignore rules](https://fluxcd.io/flux/components/kustomize/kustomizations/#ignore-rules) for the path, as Flux writes them, after the socle's. |

And beside `kube`, the root's `gitops_ssh_key`: the private half of the
deploy key, `sensitive`, required with an `ssh://` url and refused with an
`https://` one.

Refused at plan: the scp-like `git@github.com:acme/platform` (Flux reads
`ssh://` only), a user or token in an `https://` url, `..` in `path`, a key
that is not an unencrypted OpenSSH or PEM private key, and an SSH host other
than github.com without `known_hosts`.

### Every setting

```hcl kube-full="gitops"
kube = {
  gitops = {
    enabled     = true
    url         = "ssh://git@gitlab.acme.example/platform/infra" # or https:// for a public repository
    ref         = "refs/tags/v1.4.0"                             # a branch, or a full reference
    path        = "apps/acme-prod"                               # "" is the repository root
    known_hosts = "gitlab.acme.example ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..." # ssh-keyscan gitlab.acme.example

    # Fields another controller owns, which Flux must neither revert nor
    # report as drift; JSON pointers, no wildcard.
    ignore = [
      { paths = ["/spec/replicas"], target = { group = "apps", kind = "Deployment", name = "web" } },
    ]
  }
}
```

## Good to know

- **The key goes through the OpenTofu state**, and Helm's release Secret in
  `flux-system`. That is why it must be **read-only, on this one
  repository**: whoever reads the state can read the repository, nothing
  more. Never a personal key, never a key with write access.
- **The path is applied with Flux's rights**, cluster-wide: whoever can
  merge into it administers the cluster. Protect the branch.
- **Removing an object from the path deletes it**: an Application removed
  goes, and with ArgoCD's `resources-finalizer.argocd.argoproj.io` on it,
  what it deployed.
- **Turning the module off deletes nothing of yours**: the Applications stay
  and ArgoCD keeps syncing them. Nothing applies the path any more, and
  ArgoCD's repository Secret goes.
- **Write your Applications' `repoURL` as `url`**, the same string: ArgoCD
  matches the credential by URL. Its other repositories keep their own
  Secrets, or a `repo-creds` template. Do not declare another `repository`
  Secret for this url: ArgoCD would pick one of the two.
- **ArgoCD Image Updater's `write-back argocd` works on the Applications of
  the path**, multi-source included: the socle tells Flux to keep the
  `helm.parameters` it finds on `spec.source` and on `spec.sources` 0 to 4,
  so the tags Image Updater writes survive every reconciliation while the
  rest of each source keeps following Git. Do not set `helm.parameters` in
  Git on those Applications: the cluster's value wins there. A sixth source
  and beyond is not covered: add its path to `ignore`.
- **Another SSH host than GitHub**: its keys in `known_hosts`, and the socle
  adds them to ArgoCD's known hosts too.

## Per cloud

The same on aws, gcp, azure and scaleway.

## Cloud access

None.

## Ordering

Waits for `argocd`'s `ResourceSet` to be Ready: the Application CRD exists
before Flux applies the path. The module's `ResourceSet` does not wait on
your repository: a wrong key or a broken manifest shows on the
`Kustomization` `gitops`, not on the socle.

## Upgrade notes

Nothing to migrate: a new module. An existing hand-applied root Application
and repository Secret: remove the repository Secret (the module brings its
own), keep the root Application in the path — Flux adopts it on the first
apply.

<details>
<summary>Under the hood</summary>

**The Secret.** The bootstrap renders `flux-system/socle-gitops` from
`gitops_ssh_key` (through `set_sensitive`, never the inputs), with what Flux
reads (`identity`, `known_hosts`) and what ArgoCD reads (`type`, `url`,
`sshPrivateKey`). The module renders `argocd/socle-gitops-repository`,
labelled `argocd.argoproj.io/secret-type: repository`, and the Flux
Operator fills it from the first (`fluxcd.controlplane.io/copyFrom`); a
rotated key reaches it at once.

**Flux.** `GitRepository` `gitops`: every minute, `ref.name`
`refs/heads/<ref>` for a branch. `Kustomization` `gitops`: every ten
minutes, `prune: true`, `deletionPolicy: Orphan`, no health checks on your
objects, and `spec.ignore` on `helm.parameters` of every `argoproj.io`
`Application` (`/spec/source/...` and `/spec/sources/0` to `4`), then
yours. An ignored path is left out of drift detection, and Flux, its only
Apply manager, copies the cluster's value into what it applies.

**Decisions**: SOCLE-36 and the gitops decisions, in `docs/decisions/`.

</details>
