---
title: Pull from a private registry
description: Credentials for the private OpenTofu modules package, and a pull secret for Flux when the artifact comes from a private mirror.
sidebar:
  order: 3
---

The Flux artifact is public: a default install needs nothing from this page.
Two cases do:

| Case | Who needs a credential | How |
| --- | --- | --- |
| `tofu init` against `opentofu-modules`, private until v1 | the runner that applies | a docker login, or an OCI credential in the OpenTofu CLI configuration |
| The Flux artifact from your own private mirror | the cluster | a pull secret named in `artifact_pull_secret` |

## The OpenTofu modules package

Until v1, `tofu init` and `cosign verify` need a GitHub token with
`read:packages`. Log in before `init`:

```sh
printf '%s' "$GITHUB_TOKEN" | docker login ghcr.io -u <github user> --password-stdin
tofu init
```

At v1 the package goes public and this step goes away
([SOCLE-26](../decisions/socle.md#socle-26-opentofu-modules-goes-public-at-v1)).

## A private mirror of the Flux artifact

1. Copy the artifact with its signature, keeping the socle version as tag:

   ```sh
   cosign copy ghcr.io/do-now-io/socle/flux-modules:<version> \
     registry.acme.example/socle/flux-modules:<version>
   ```

2. Once the bootstrap has installed `flux-operator`, create the pull secret
   in `flux-system`, outside OpenTofu:

   ```sh
   kubectl -n flux-system create secret docker-registry socle-mirror \
     --docker-server=registry.acme.example \
     --docker-username=<user> --docker-password=<token>
   ```

3. Point the root at the mirror and name the Secret:

   ```hcl
   artifact_url         = "oci://registry.acme.example/socle/flux-modules"
   artifact_pull_secret = "socle-mirror"
   ```

## Good to know

- **Never re-sign the copy.** Flux checks the signature against the release
  workflow's identity.
- **Until the Secret exists**, the `OCIRepository` reports the pull as
  unauthorised and retries every minute.
- **The credential never enters OpenTofu**: only the Secret's name reaches
  the `OCIRepository`. A public mirror needs `artifact_url` alone.
