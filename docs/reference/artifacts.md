---
title: Artifacts
description: The two OCI artifacts, their tags, which ones get deleted and when, what they contain, and how to verify their signatures.
sidebar:
  order: 2
---

Why there are two and how a release is cut is in
[Distribution](../architecture/distribution.md).

## The packages

| Package | Media type | Contents | Visibility |
| --- | --- | --- | --- |
| `ghcr.io/do-now-io/socle/flux-modules` | Flux artifact (`tar+gzip`) | `oci/`, without any `tests/` folder | public |
| `ghcr.io/do-now-io/socle/opentofu-modules` | `application/vnd.opentofu.modulepkg`, one `archive/zip` layer | `git archive` of the whole commit | private until v1 |

Both carry the annotations `org.opencontainers.image.source`
(`https://github.com/do-now-io/socle`) and `org.opencontainers.image.revision`
(`<branch>@sha1:<commit>`), which is how a release finds the alpha built from
its commit.

How each is consumed:

```hcl
# a client's root: the modules package, by tag
source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/aws?tag=${var.socle_version}"

# the bootstrap module's default: the Flux artifact, tag = socle_version
artifact_url = "oci://ghcr.io/do-now-io/socle/flux-modules"
```

## Tags

The same tag names both packages.

| Tag | Published by | Example | Deleted |
| --- | --- | --- | --- |
| `X.Y.Z` | merge of the release PR: a second tag on the alpha of that commit | `0.1.0` | never |
| `X.Y.Z-alpha.N` | every push to `main` | `0.1.0-alpha.3` | after 30 days, unless the same version also carries a release tag |
| `0.0.0-<branch-slug>.<short-sha>` | every push to any other branch | `0.0.0-docs-71-m2-migration.285a8d5` | when the branch is deleted, on manual dispatch with the branch name, and after 7 days |

The slug is the branch name lowercased, every run of characters outside
`a-z0-9` turned into one dash, with no leading or trailing dash. Two branch
names with the same slug (`feat-x` and `feat/x`) share their tags, and
deleting one branch deletes the other's.

Deletion is [`cleanup-artifacts.yaml`](../../.github/workflows/cleanup-artifacts.yaml):
on a branch's deletion, on `workflow_dispatch`, and nightly at 03:17 UTC for
the age rules, on both packages. A version is deleted only when every one of
its tags matches a rule, so a promoted alpha, which also carries its release
tag, is kept. A cluster pinned to a deleted tag can no longer pull it
([Troubleshooting](../guides/troubleshooting.md#manifest_unknown-on-the-ocirepository)).

`socle_version` accepts the three forms: a SemVer tag, with an optional
pre-release. `latest`, `main` and any moving head are refused at plan.

## What the Flux artifact contains

```text
oci/
├── clusters/
│   ├── aws/kustomization.yaml       # the catalog ResourceSets this cloud offers, and its patches
│   ├── gcp/  azure/  scaleway/
└── catalog/
    ├── hello/resourceset.yaml       # one ResourceSet per module
    ├── gateway-api/
    │   ├── resourceset.yaml
    │   └── cilium/                  # a Kustomization applied by the module, from this artifact
    ├── otel-agent/
    │   ├── resourceset.yaml
    │   └── dashboards/              # the module's Grafana dashboards
    └── <module>/resourceset.yaml
```

The cluster applies `./clusters/<cloud>`. In the repository, beside each
module, `oci/catalog/<module>/tests/e2e/` holds its Chainsaw suite,
`oci/tests/e2e/` the socle's own suites (`root`, `disabled`, `destroyed`),
and `oci/.ci/` the fixtures CI renders the catalog with; none of them is
pushed.

## Signatures

Both packages are signed keyless with cosign, through GitHub's OIDC token.

| Built from | Certificate identity |
| --- | --- |
| `main` (alphas and releases) | `https://github.com/do-now-io/socle/.github/workflows/publish-artifact.yaml@refs/heads/main` |
| another branch | `https://github.com/do-now-io/socle/.github/workflows/publish-artifact.yaml@refs/heads/<branch>` |

Issuer: `https://token.actions.githubusercontent.com`.

A release tag points at the alpha's digest, so it carries main's signature.
Flux checks the Flux artifact on every reconciliation against
`cosign_identity`, two anchored regexes whose default is the `main` identity
above.

### Verify a signature

OpenTofu does not verify OCI signatures. Run this in CI before `tofu init`,
for the version the tfvars pins:

```sh
cosign verify ghcr.io/do-now-io/socle/opentofu-modules:<version> \
  --certificate-identity-regexp '^https://github\.com/do-now-io/socle/\.github/workflows/publish-artifact\.yaml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The same command with `flux-modules` checks the Flux artifact. While
`opentofu-modules` is private, `cosign` needs registry credentials
(`cosign login ghcr.io`, or a docker login, with a token that has
`read:packages`).
