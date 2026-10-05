---
title: Upgrade the socle
description: Bump socle_version, verify the new modules, apply, and know what moves with the version; test a branch or an alpha first.
sidebar:
  order: 2
---

An upgrade is one line in the tfvars and one apply. The same line moves the
OpenTofu modules, the Flux artifact and every version they pin.

## 1. Read what changes

A socle version is SemVer. Before 1.0.0 a breaking change bumps the minor,
not the major, so `0.3.x` to `0.4.0` may need a change on your side. What
moves with a version:

- the foundations and bootstrap modules, sourced with
  `?tag=${var.socle_version}`;
- the Flux artifact the cluster pulls, tagged the same;
- every version they pin: flux-operator, Cilium and CoreDNS charts, the EKS
  add-ons, each catalog module's chart
  ([Compatibility](../reference/compatibility.md)).

Each release has a GitHub release and an entry in `CHANGELOG.md`, both
written by release-please from the conventional commits: read the entries
between your version and the target. A breaking change is marked as such.
No version has been released yet.

## 2. Verify the modules

OpenTofu does not verify signatures. In CI, before `tofu init`:

```sh
cosign verify ghcr.io/do-now-io/socle/opentofu-modules:<version> \
  --certificate-identity-regexp '^https://github\.com/do-now-io/socle/\.github/workflows/publish-artifact\.yaml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Flux verifies the artifact itself, on every reconciliation.

## 3. Bump and apply

```hcl
socle_version = "0.0.0" # x-release-please-version
```

```sh
tofu init
tofu apply -var-file=clusters/prod.tfvars
```

`tofu init` fetches the modules at the new tag; the apply upgrades what the
bootstrap installs and the envelope's inputs, and the cluster pulls the new
artifact. The `socle` Kustomization has `prune: true`: an object the new
artifact no longer carries leaves the cluster.

Check convergence as after any apply:

```sh
kubectl -n flux-system get ocirepository socle     # the new tag, SourceVerified
kubectl -n flux-system get resourceset socle-root  # Ready
```

Move one ring at a time: dev, then staging, then prod.

### When the upgrade replaces the cluster

A change that forces the cluster's replacement (the foundations README lists
the ForceNew attributes) makes the endpoint unknown at plan, and the helm
provider cannot refresh its releases. Apply the foundations first, then
everything:

```sh
tofu apply -var-file=clusters/prod.tfvars -target=module.foundations
tofu apply -var-file=clusters/prod.tfvars
```

## Test a build before it is released

`socle_version` accepts any SemVer tag the registry holds
([Artifacts](../reference/artifacts.md#tags)). `latest` and `main` are
refused.

- **An alpha from `main`** (`X.Y.Z-alpha.N`): set `socle_version` only. The
  default `cosign_identity` already trusts `main`.
- **A branch build** (`0.0.0-<branch-slug>.<short-sha>`): set `socle_version`
  and `cosign_identity` to the branch's identity, on a dev cluster only.
  Without the identity, Flux refuses the artifact's signature:

  ```hcl
  socle_version = "0.0.0-feat-x.abc1234"
  cosign_identity = {
    issuer  = "^https://token\\.actions\\.githubusercontent\\.com$"
    subject = "^https://github\\.com/do-now-io/socle/\\.github/workflows/publish-artifact\\.yaml@refs/heads/feat/x$"
  }
  ```

Branch tags are deleted when the branch goes and after seven days, alphas
after thirty: move the cluster back to a release before then.
