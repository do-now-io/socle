---
title: Pull from a private registry
description: Credentials for the private OpenTofu modules package, and a pull secret for Flux when the artifact comes from a private mirror.
sidebar:
  order: 3
---

The Flux artifact, `ghcr.io/do-now-io/socle/flux-modules`, is public: a
cluster pulls it with no credential, and a default install needs nothing
from this page. Two cases do:

| Case | Who needs a credential | How |
| --- | --- | --- |
| `tofu init` against `ghcr.io/do-now-io/socle/opentofu-modules`, private until v1 | the runner that applies | an OCI credential in the OpenTofu CLI configuration, or a docker login |
| The Flux artifact served from your own private mirror | the cluster | a pull secret named in `artifact_pull_secret` |

## The OpenTofu modules package

Until v1, `tofu init` and `cosign verify` need a GitHub token with
`read:packages` for `ghcr.io/do-now-io/socle/opentofu-modules`. OpenTofu reads
OCI registry credentials from the docker credentials store, so the simplest
form on a runner is a login before `init`:

```sh
printf '%s' "$GITHUB_TOKEN" | docker login ghcr.io -u <github user> --password-stdin
tofu init
```

Once the package is public, at v1, this step goes away
([SOCLE-26](../decisions/socle.md#socle-26-opentofu-modules-goes-public-at-v1)).

## A private mirror of the Flux artifact

1. Copy the artifact, with its signature, to your registry: for instance
   `cosign copy ghcr.io/do-now-io/socle/flux-modules:<version>
   registry.acme.example/socle/flux-modules:<version>`. The tag must stay the
   socle version, and the signature must still match the release workflow's
   identity: Flux checks it.
2. Create the pull secret once, in `flux-system`, outside OpenTofu:

   ```sh
   kubectl -n flux-system create secret docker-registry socle-mirror \
     --docker-server=registry.acme.example \
     --docker-username=<user> --docker-password=<token>
   ```

   The namespace exists once the bootstrap has installed `flux-operator`.
   Until the Secret exists, the `OCIRepository` reports the pull as
   unauthorised and retries every minute.
3. Point the root at the mirror and name the Secret:

   ```hcl
   artifact_url         = "oci://registry.acme.example/socle/flux-modules"
   artifact_pull_secret = "socle-mirror"
   ```

The credential never enters OpenTofu or its state: OpenTofu only writes the
Secret's name into the `OCIRepository`'s `secretRef`. A public mirror needs
`artifact_url` alone.
