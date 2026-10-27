---
title: Upgrade the socle
description: Bump socle_version, verify the new modules, apply, and know what moves with the version; test a branch or an alpha first.
sidebar:
  order: 2
---

An upgrade is one line in the cluster's `main.tf` and one apply. That line moves the
OpenTofu modules, the Flux artifact and every version they pin
([Compatibility](../reference/compatibility.md)).

## 1. Read what changes

Read the `CHANGELOG.md` entries, or the GitHub releases, between your version
and the target; a breaking change is marked. Before 1.0.0 a breaking change
bumps the minor: `0.3.x` to `0.4.0` may need a change on your side.

## 2. Verify the modules

OpenTofu does not verify signatures; Flux verifies the artifact itself. In
CI, before `tofu init`:

```sh
cosign verify ghcr.io/do-now-io/socle/opentofu-modules:<version> \
  --certificate-identity-regexp '^https://github\.com/do-now-io/socle/\.github/workflows/publish-artifact\.yaml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## 3. Bump and apply

```hcl
locals {
  socle_version = "0.2.1" # x-release-please-version
}
```

`tofu init` fetches the modules at the new tag:

```sh
tofu init
tofu apply
kubectl -n flux-system get ocirepository socle     # the new tag, SourceVerified
kubectl -n flux-system get resourceset socle-root  # Ready
```

An object the new artifact no longer carries leaves the cluster. Move one
ring at a time: dev, then staging, then prod.

`socle_version` does not move Kubernetes. On AWS the version is yours,
`aws.kubernetes_version`, a foundations change of its own. On GCP the release
channel upgrades the cluster in your `gcp.maintenance_window`; the day of the
window orders the rings.

### When the upgrade replaces the cluster

A change that replaces the cluster (listed in the root's README:
[AWS](../../opentofu/clusters/aws/README.md),
[GCP](../../opentofu/clusters/gcp/README.md)) leaves the helm provider unable
to refresh. Apply the foundations first; the target is the same on both
roots:

```sh
tofu apply -target=module.socle.module.foundations
tofu apply
```

## Test a build before it is released

`socle_version` takes any SemVer tag the registry holds
([Artifacts](../reference/artifacts.md#tags)); `latest` and `main` are
refused.

- **An alpha from `main`** (`X.Y.Z-alpha.N`): set `socle_version` only.
- **A branch build** (`0.0.0-<branch-slug>.<short-sha>`), on a dev cluster
  only: also set `cosign_identity` to the branch, or Flux refuses the
  signature:

  ```hcl
  # local.socle_version = "0.0.0-feat-x.abc1234", and in the module block:
  cosign_identity = {
    issuer  = "^https://token\\.actions\\.githubusercontent\\.com$"
    subject = "^https://github\\.com/do-now-io/socle/\\.github/workflows/publish-artifact\\.yaml@refs/heads/feat/x$"
  }
  ```

Branch tags are deleted with the branch and after seven days, alphas after
thirty: move back to a release before then.
