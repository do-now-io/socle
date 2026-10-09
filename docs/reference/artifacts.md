---
title: Artifacts
description: The two OCI artifacts, their tags, which ones get deleted and when, what they contain, and how to verify their signatures.
sidebar:
  order: 2
---

Why two, and how a release is cut: [Distribution](../architecture/distribution.md).

## The packages

| Package | Media type | Contents | Visibility |
| --- | --- | --- | --- |
| `ghcr.io/do-now-io/socle/flux-modules` | Flux artifact (`tar+gzip`) | `oci/`, without any `tests/` folder | public |
| `ghcr.io/do-now-io/socle/opentofu-modules` | `application/vnd.opentofu.modulepkg`, one `archive/zip` layer | `git archive` of the whole commit | public |

Annotations on both: `org.opencontainers.image.source`
(`https://github.com/do-now-io/socle`), `org.opencontainers.image.revision`
(`<branch>@sha1:<commit>`).

```hcl
# a client's root: the modules package, by tag
source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/aws?tag=${var.socle_version}"

# the bootstrap module's default: the Flux artifact, tag = socle_version
artifact_url = "oci://ghcr.io/do-now-io/socle/flux-modules"
```

## Tags

One tag names both packages; `socle_version` takes any of them, never
`latest` or `main`.

| Tag | Published by | Example | Deleted |
| --- | --- | --- | --- |
| `X.Y.Z` | merge of the release PR: a second tag on the alpha of that commit | `0.1.0` | never |
| `X.Y.Z-alpha.N` | every push to `main` | `0.1.0-alpha.3` | after 30 days, unless the same version also carries a release tag |
| `0.0.0-<branch-slug>.<short-sha>` | every push to any other branch | `0.0.0-docs-71-m2-migration.285a8d5` | when the branch is deleted, on manual dispatch with the branch name, and after 7 days |

- **Slug**: the branch name lowercased, each run outside `a-z0-9` one dash,
  no leading or trailing dash. `feat-x` and `feat/x` share their tags:
  deleting one branch deletes the other's.
- **Deletion**: [`cleanup-artifacts.yaml`](../../.github/workflows/cleanup-artifacts.yaml),
  nightly at 03:17 UTC for the age rules. A version goes only when every tag
  matches a rule, so a promoted alpha stays. A cluster pinned to a deleted
  tag stops pulling
  ([Troubleshooting](../guides/troubleshooting.md#manifest_unknown-on-the-ocirepository)).

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

The cluster applies `./clusters/<cloud>`. Not pushed: every `tests/` folder
(`oci/catalog/<module>/tests/`, `oci/tests/`).

## Signatures

Keyless cosign, through GitHub's OIDC token.

| Built from | Certificate identity |
| --- | --- |
| `main` (alphas and releases) | `https://github.com/do-now-io/socle/.github/workflows/publish-artifact.yaml@refs/heads/main` |
| another branch | `https://github.com/do-now-io/socle/.github/workflows/publish-artifact.yaml@refs/heads/<branch>` |

Issuer: `https://token.actions.githubusercontent.com`.

A release carries its alpha's `main` signature. Flux checks it on every
reconciliation against `cosign_identity`, two anchored regexes, `main` by
default.

### Verify a signature

OpenTofu does not verify signatures: run this in CI before `tofu init`.

```sh
cosign verify ghcr.io/do-now-io/socle/opentofu-modules:<version> \
  --certificate-identity-regexp '^https://github\.com/do-now-io/socle/\.github/workflows/publish-artifact\.yaml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Swap in `flux-modules` for the Flux artifact. Both are public: no login.
