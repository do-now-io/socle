---
title: Distribution
description: Two OCI artifacts under one version, how each push names its tag, how a release is cut, and who verifies the signatures.
sidebar:
  order: 2
---

A socle version is two OCI artifacts with the same tag, signed by the same
workflow identity, both written by
[`publish-artifact.yaml`](../../.github/workflows/publish-artifact.yaml):

| Package | Carries | Pulled by | When |
| --- | --- | --- | --- |
| `ghcr.io/do-now-io/socle/opentofu-modules` | the whole commit, as an OpenTofu module package | `tofu init`, on the client's runner | before any cluster exists |
| `ghcr.io/do-now-io/socle/flux-modules` | `oci/`, minus every `tests/` folder | Flux, from inside the cluster | every minute, once the cluster exists |

Tags, names and the verification command are listed in
[Artifacts](../reference/artifacts.md).

## Why two, and not one

The first pull happens on a machine with no cluster, so Flux cannot make it:
`tofu init` fetches the module that creates the cluster Flux will then
reconcile from. And the two cannot share a name. An OCI tag carries one
manifest, with one `artifactType` and one set of layers: a module package is
`application/vnd.opentofu.modulepkg` over a single `archive/zip` layer
(pushed with `oras`, the only tool here that sets an `artifactType`), the
Flux artifact is Flux's `tar+gzip` content.

The bootstrap module travels in the OpenTofu package, not in the Flux
artifact: it is OpenTofu code, run by `tofu init`, even though what it
installs is Flux. The module package is `git archive` of the commit, so the
roots can call each other by relative path and a consumer picks one with
`//opentofu/<cloud>`.

## One version for both

`socle_version` in a client's tfvars pins the module sources and the
`OCIRepository` tag. That only holds if one calculation names both:
[`compute-tag.sh`](../../.github/scripts/compute-tag.sh) runs once, in the
`publish` job, and `publish-modules` pushes under the tag it hands over. Two
jobs counting their own alphas would drift apart on the first partial
re-run.

| Trigger | Tag | Signed as |
| --- | --- | --- |
| push to `main` | `<next>-alpha.N` | `publish-artifact.yaml@refs/heads/main` |
| push to any other branch | `0.0.0-<branch-slug>.<short-sha>` | `publish-artifact.yaml@refs/heads/<branch>` |
| merge of the release PR | `<next>`, a second tag on the digest of the alpha that same push produced | the alpha's signature: `main` |

- **`<next>`** is what release-please will propose for the commits since the
  last release, computed the same way. `VERSION` is the last release. A
  `Release-As: X.Y.Z` footer wins; otherwise a breaking change (`type!:` or a
  `BREAKING CHANGE:` footer) bumps the major, the minor before 1.0.0; `feat`
  bumps the minor; anything else the patch. One bump from the last release,
  not one per commit. Before the first release, `<next>` is the config's
  `initial-version`, `0.1.0`. On the release commit itself, whose `VERSION`
  is not in the registry yet, `<next>` is `VERSION`.
- **`N`** is one more than the highest alpha already published for `<next>`
  (`crane ls`, filtered, sorted). A registry that cannot answer fails the
  job: guessing "it does not exist" is how a tag gets overwritten.
- **A branch tag** is a SemVer pre-release: it sorts below any release, never
  matches a `>=1.0.0` range, and is collected by
  [`cleanup-artifacts.yaml`](../../.github/workflows/cleanup-artifacts.yaml).
  The slug is the branch name lowercased, every run of other characters
  turned into one dash.

## Releases

release-please keeps one release pull request open
([`release-please-config.json`](../../release-please-config.json): type
`simple`, tags without `v`). Its job runs after the e2e proofs, so the PR
only advances to a commit whose alpha converged on floci. The PR carries the
`CHANGELOG.md` entry and rewrites every version stamp: `VERSION`,
`.release-please-manifest.json`, and each line annotated
`# x-release-please-version` in the files listed under `extra-files`.

Merging that PR is the release. The push publishes the alpha of the merge
commit and runs the proofs; release-please then tags the commit and publishes
the GitHub release; `promote` runs
[`release.sh`](../../.github/scripts/release.sh) for each package, which
finds the alpha whose `org.opencontainers.image.revision` annotation is
`main@sha1:<that commit>` and gives it the version as a second tag with
`crane tag`. Same bytes, same signature: the release is exactly what the
proofs ran on.

`release.sh` refuses when the release tag is not that commit's `VERSION`,
when no alpha was built from the commit, and when the version already exists
as another digest. A version that already points at this commit's alpha is
accepted, so re-running `promote` after a failure between the two packages
finishes the release. A release tag is never overwritten.

Everything happens in one workflow rather than `on: release` because a
release created with the workflow's token triggers no other workflow; one run
also orders the jobs: alpha, proofs, release PR or release, promotion. The
decision is
[SOCLE-20](../decisions/socle.md#socle-20-a-release-re-tags-the-alpha-release-please-runs-in-the-same-workflow);
the contributor's side (merge method, repository settings) is in
[CONTRIBUTING, Releases](../contributing.md#releases).

## Signatures

Both packages are signed with cosign, keyless, through the GitHub OIDC token,
and each push verifies what it just signed. The subject is the workflow file
on the ref that ran it:

```text
https://github.com/do-now-io/socle/.github/workflows/publish-artifact.yaml@refs/heads/main
```

**Flux verifies** the Flux artifact on every reconciliation, through the
`OCIRepository`'s `verify` block, against `cosign_identity`. Its default
trusts `main` only, and verification cannot be turned off
([SOCLE-16](../decisions/socle.md#socle-16-cosign-verification-is-mandatory-mains-identity-trusted-by-default)).

**OpenTofu does not.** It pulls an unsigned or tampered module package
without complaint. The verification is the consumer's to run in CI, before
`init` ([the command](../reference/artifacts.md#verify-a-signature)). Nothing
forces that step: making it mandatory needs a registry policy or an admission
controller.

The workflow's file name is part of the signed subject: renaming
`publish-artifact.yaml` makes every deployed verification stop matching.

## Visibility

`flux-modules` is public: a cluster pulls it with no credential.
`opentofu-modules` is private until v1, so `tofu init` against the published
package, and `cosign verify` of it, need a token. See
[Pull from a private registry](../guides/private-registry.md).
