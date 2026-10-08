---
title: crossplane
description: "The tooling each module uses to declare its own cloud access: Crossplane and its providers (aws today)."
category: platform
requires: []
---

Crossplane is the tooling a module that needs a cloud service uses to declare
its own role, beside its workload. It grants nothing by itself. **Off by
default**; turn it on when a module you want needs cloud access (external-dns,
external-secrets, keda with `services`, velero). Providers exist on aws only.

## Getting started

Set the foundations' `aws.crossplane` with the services your modules use
(`crossplane = { allowed_services = ["route53", "secretsmanager"] }`), then
turn the module on; the aws root wires `permissions_boundary` for you:

```hcl title="terraform.tfvars" kube-start="crossplane"
kube = {
  crossplane = {
    enabled = true
  }
}
```

Then `kubectl get providers.pkg.crossplane.io` shows the four providers `Healthy`.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on or off. |
| `permissions_boundary` | `""` | The IAM policy every module role carries. The aws root fills it from the foundations; a value you write wins. |
| `values` | `{}` | Any [`crossplane` chart](https://artifacthub.io/packages/helm/crossplane/crossplane) value; yours win. |
| `values_secret` | `""` | A Secret in `crossplane-system` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl title="terraform.tfvars" kube-full="crossplane"
kube = {
  crossplane = {
    enabled = false # off by default; true installs the tooling

    # Any value of the crossplane chart 2.4.2; yours win over the socle's.
    values = {
      metrics = { enabled = true } # scrape annotations, read by otel_gateway
    }

    # A Secret you create in crossplane-system, whose values.yaml key holds
    # chart values that must not reach the OpenTofu state, such as an
    # extraEnvVarsCrossplane proxy URL with a password in it.
    values_secret = "crossplane-values"

    # On aws the root sets it to the foundations' boundary; written here, it
    # wins over the root's. Leave it out unless you mean to.
    # permissions_boundary = ""
  }
}
```

## Good to know

- **It needs `aws.crossplane` in the foundations.** Without it the aws root
  warns: Crossplane converges, and every role a module declares fails at the
  AWS API.
- **On gcp, azure and scaleway it installs the core alone.** No module
  declares a role there; each takes a credential you bring.
- **Turning it off deletes nothing it provisioned.** The CRDs, the webhook
  configuration and every module role stay, orphaned. Turn the modules that
  use it off first, wait for their roles to go, then turn Crossplane off.
- **`tofu plan` refuses secrets in `values`**: a `Secret` in `extraObjects`,
  or an `extraEnvVars*` entry named like a password, token or key. Use
  `values_secret`.
- **Upgrades**: the chart moves with `socle_version`, and its CRDs with it
  (Crossplane applies them at start). The four providers move together, on
  one tag.

<details>
<summary>Under the hood</summary>

**Installed**: chart `crossplane` 2.4.2 from `https://charts.crossplane.io/stable`,
in `crossplane-system`. On aws, the providers `provider-family-aws`,
`provider-aws-iam`, `provider-aws-eks` and `provider-aws-s3` (v2.8.1), then
`ClusterProviderConfig/default` on EKS Pod Identity, once they are `Healthy`.

**What the socle sets**: requests with no limits (about 1440Mi in all on aws),
and every provider pod on the fixed ServiceAccount
`crossplane-system/provider-aws`, so the foundations can bind it before the
cluster has a node. Your `values` are merged over these.

**Cloud access**: the foundations' role for `crossplane-system/provider-aws`
creates roles only under `/socle/<cluster>/` and only with the boundary, which
allows `allowed_services` and always denies `iam`, `sts` and the account
services.
The whole chain: [Module-owned cloud access](../architecture/module-iam.md).

**Ordering**: every module that declares a role waits for the `crossplane`
ResourceSet, Ready trivially when the module is off.

**Measured** on floci 2.1.0, GitHub runner, 2026-09-30: on, providers and
ProviderConfig converged, a module role in IAM, and off again in under 4 min.

</details>
