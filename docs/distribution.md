# Distribution — two artifacts, one version

A release publishes two OCI artifacts under the same version, signed by the
same workflow identity:

| | Carries | Pulled by | When |
| --- | --- | --- | --- |
| `ghcr.io/do-now-io/socle/opentofu-modules` | every root under `opentofu/` | `tofu init`, on the client's runner | **before any cluster exists** |
| `ghcr.io/do-now-io/socle/flux-modules` | `oci/` | Flux, from inside the cluster | continuously, once it does |

Both come out of [`publish-artifact.yaml`](../.github/workflows/publish-artifact.yaml).

## Why two, and not one

The first pull happens on a machine with no cluster, so Flux cannot make it —
`tofu init` is what fetches the module that creates the cluster Flux will then
reconcile from.

And they cannot share a name. An OCI tag carries **one** manifest, with one
`artifactType` and one set of layers: a module package is
`application/vnd.opentofu.modulepkg` over an `archive/zip` layer, the socle is
Flux's `…flux.content.v1.tar+gzip`. One tag cannot be both.

**The bootstrap module travels in the OpenTofu package**, not in the socle. It
is OpenTofu code — the client runs `tofu init` on it — even though what it
installs is Flux.

## One version for both

`socle_version` in a client's tfvars pins the module source *and* the
`OCIRepository` tag. That only holds if one calculation names both, so both
jobs run `.github/scripts/compute-tag.sh`, which differs only by `REPOSITORY`:

- **a push to `main`** publishes `<next>-alpha.N`, where `<next>` is what the
  conventional commits since the last release call for — computed exactly as
  release-please computes it;
- **a push anywhere else** publishes `0.0.0-<branch>.<sha>`, a pre-release that
  sorts below every release, never matches `>=1.0.0`, and is collected by
  `cleanup-artifacts.yaml`;
- **merging the release PR** promotes: `release.sh` gives the alpha built from
  that very commit a second tag, the version itself. **Nothing is rebuilt.**
  cosign signed the digest, so the release carries the same signature and the
  same identity.

Both artifacts are promoted in the same job, from the same commit. A release
where only one of them carried the version would leave `socle_version` pinning
half a socle.

A release tag is never overwritten, and when the registry answers neither yes
nor no the job **fails** instead of publishing on doubt — guessing "it does not
exist" is how a pinned digest gets silently replaced.

## Who verifies, and who does not

This is the asymmetry that shapes everything downstream:

**Flux verifies** the socle artifact on every reconciliation, through the
`OCIRepository`'s `verify` block. Nothing is asked of the consumer beyond
configuring the identity.

**OpenTofu does not.** It will pull an unsigned or tampered module package
without complaint. The verification is the consumer's to run, in CI, before
`init`:

```sh
cosign verify ghcr.io/do-now-io/socle/opentofu-modules:<version> \
  --certificate-identity-regexp '^https://github\.com/do-now-io/socle/\.github/workflows/publish-artifact\.yaml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Nothing *forces* that step. Making it mandatory needs registry policy or an
admission controller, and both are out of scope here.

**Renaming `publish-artifact.yaml` changes the signed subject**, and every
verification already deployed stops matching. It is part of the contract, not
a filename.

## Private until v1

Both packages stay private while the socle is under development, and go public
at v1 — a one-time change in the package settings, which no workflow can make
because a package does not exist before its first push.

Until then a consumer needs credentials, and so does anyone running the
`cosign verify` above. That is what going public buys, and it is why "`tofu
init` needs no credentials" is a v1 claim rather than a description of today.

## What is not proven yet

`tofu init` against the published package, from a clean cache — the conformance
checklist's own criterion for section 5. It needs the package readable, so it
waits for v1 or for OCI credentials configured in the OpenTofu CLI
configuration. The artifact's *shape* is verified: the manifest published from
a branch was read back and carries `application/vnd.opentofu.modulepkg` over a
single `archive/zip` layer, which is what OpenTofu requires.
