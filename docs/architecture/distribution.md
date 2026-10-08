---
title: Distribution
description: Two OCI artifacts under one version, how each push names its tag, how a release is cut, and who verifies the signatures.
sidebar:
  order: 2
---

A socle version is two OCI artifacts with the same tag, signed by the same
workflow, [`publish-artifact.yaml`](../../.github/workflows/publish-artifact.yaml).
Tags and commands are in [Artifacts](../reference/artifacts.md).

| Package | Carries | Pulled by | When |
| --- | --- | --- | --- |
| `ghcr.io/do-now-io/socle/opentofu-modules` | the whole commit, as an OpenTofu module package | `tofu init`, on your runner | before any cluster exists |
| `ghcr.io/do-now-io/socle/flux-modules` | `oci/`, minus every `tests/` folder | Flux, in the cluster | every minute |

## Why two, and not one

The first pull happens where no cluster exists yet, so Flux cannot make it.
And one OCI tag carries one manifest type: an OpenTofu module package and a
Flux artifact cannot share a name.

<details>
<summary>Under the hood</summary>

The module package is `application/vnd.opentofu.modulepkg` over one
`archive/zip` layer, pushed with `oras`; the Flux artifact is Flux's
`tar+gzip`. The package is `git archive` of the commit, so the bootstrap
module travels in it and a consumer picks a module with `//opentofu/<cloud>`.

</details>

## One version for both

[`compute-tag.sh`](../../.github/scripts/compute-tag.sh) runs once per push
and both packages take its tag, so they never drift.

| Trigger | Tag | Signed as |
| --- | --- | --- |
| push to `main` | `<next>-alpha.N` | `publish-artifact.yaml@refs/heads/main` |
| push to another branch | `0.0.0-<branch-slug>.<short-sha>` | `publish-artifact.yaml@refs/heads/<branch>` |
| merge of the release PR | `<next>`, a second tag on that push's alpha | the alpha's signature: `main` |

<details>
<summary>Under the hood</summary>

- **`<next>`** is what release-please will propose since `VERSION`, the last
  release: a `Release-As:` footer wins; a breaking change bumps the major
  (the minor before 1.0.0), `feat` the minor, anything else the patch. Before
  the first release it is `0.1.0`; on the release commit, `VERSION`.
- **`N`** is one more than the highest published alpha of `<next>`. A
  registry that cannot answer fails the job rather than risk overwriting.
- **A branch tag** is a SemVer pre-release, collected by
  [`cleanup-artifacts.yaml`](../../.github/workflows/cleanup-artifacts.yaml).

</details>

## Releases

release-please keeps one release PR open, advanced only to a commit whose
alpha passed the e2e proofs. Merging it is the release: `promote` gives that
commit's alpha the version as a second tag, so the release is the exact bytes
and signature the proofs ran on. A release tag is never overwritten
(contributor side in [CONTRIBUTING](../contributing.md#releases)).

<details>
<summary>Under the hood</summary>

The PR carries the `CHANGELOG.md` entry and rewrites `VERSION`,
`.release-please-manifest.json` and every `# x-release-please-version` line
([`release-please-config.json`](../../release-please-config.json)).
[`release.sh`](../../.github/scripts/release.sh) finds the alpha whose
`org.opencontainers.image.revision` is `main@sha1:<commit>` and tags it with
`crane tag`. It refuses a tag that is not the commit's `VERSION`, a commit
with no alpha, and a version already on another digest; a re-run after a
partial failure finishes the release. All of it is one workflow because a
release made with the workflow's token triggers no other workflow.

</details>

## Signatures

Both packages are signed keyless with cosign; the subject is the workflow
file on its ref:

```text
https://github.com/do-now-io/socle/.github/workflows/publish-artifact.yaml@refs/heads/main
```

- **Flux verifies** the artifact on every reconciliation against
  `cosign_identity`, which trusts `main` by default and cannot be turned off.
- **OpenTofu does not.** Run [the command](../reference/artifacts.md#verify-a-signature)
  in CI before `init`; nothing forces it.
- **Renaming `publish-artifact.yaml`** breaks every deployed verification.

## Visibility

`flux-modules` is public. `opentofu-modules` is private until v1: `tofu init`
and `cosign verify` need a token
([Pull from a private registry](../guides/private-registry.md)).
