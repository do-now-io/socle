---
title: Pull from a private registry
description: Pull the socle from your own private mirror — a registry credential for OpenTofu, a pull secret for Flux.
sidebar:
  order: 3
---

Both socle packages are public: a default install needs nothing from this
page. It is for a socle served from your own private registry.

| Case | Who needs a credential | How |
| --- | --- | --- |
| `tofu init` against your mirror of `opentofu-modules` | the runner that applies | a docker login, or an OCI credential in the OpenTofu CLI configuration |
| The Flux artifact from your mirror | the cluster | a pull secret named in `artifact_pull_secret` |

## The OpenTofu modules package

Copy it with its signature, then log in to your registry before `init` and
point both module sources at it:

```sh
cosign copy ghcr.io/do-now-io/socle/opentofu-modules:<version> \
  registry.acme.example/socle/opentofu-modules:<version>
docker login registry.acme.example
tofu init
```

## The Flux artifact

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
