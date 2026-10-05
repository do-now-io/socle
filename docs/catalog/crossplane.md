---
title: crossplane
description: "The tooling each module uses to declare its own cloud access: Crossplane and its providers (aws today)."
category: platform
requires: []
---

Crossplane is how a catalog module that needs a cloud service declares its
own role, beside its workload, instead of the foundations growing one IAM
block per module. This module is only the tooling: Crossplane, the AWS
providers and their `ClusterProviderConfig`. It names no module and grants
nothing by itself. It is **off by default**; turn it on when a module you
want needs cloud access (external-dns, external-secrets, keda with
`services`, velero). How the whole chain works:
[Module-owned cloud access](../architecture/module-iam.md).

## Getting started

It needs one input that is not a module: the foundations' `aws.crossplane`,
which gives Crossplane its own identity and the permissions boundary every
role it creates must carry. Name there the services your modules use:

```hcl
# opentofu/clusters/aws, in your tfvars
aws = {
  # ...
  crossplane = { allowed_services = ["route53", "secretsmanager"] }
}
```

Then turn the module on. The aws root wires `permissions_boundary` for you:

```hcl title="terraform.tfvars" kube-start="crossplane"
kube = {
  crossplane = {
    enabled = true
  }
}
```

After the apply, `kubectl -n flux-system get resourceset crossplane` is Ready
and, on aws, `kubectl get providers.pkg.crossplane.io` shows the four providers `Healthy`.

## What it installs

| | |
| --- | --- |
| Chart | `crossplane` `2.4.2` from `https://charts.crossplane.io/stable` (a `HelmRepository`: upstream publishes no OCI chart) |
| Namespace | `crossplane-system` |
| Objects | Three steps, each applied and health-checked before the next: `core` — `Namespace`, `HelmRepository/crossplane-stable`, `ConfigMap/crossplane-socle-values`, `ConfigMap/crossplane-client-values`, `HelmRelease/crossplane`; `providers` (aws) — `DeploymentRuntimeConfig/provider-aws` and the `Provider`s `crossplane-contrib-provider-family-aws`, `provider-aws-iam`, `provider-aws-eks`, `provider-aws-s3`, all `v2.8.1` from `xpkg.crossplane.io`; `config` (aws) — the child `ResourceSet/crossplane-provider-config`, which waits for the four providers to be `Healthy` and holds `ClusterProviderConfig/default` on EKS Pod Identity |

Every AWS provider pod runs as the ServiceAccount
`crossplane-system/provider-aws`, a fixed name, so the foundations can write
its Pod Identity association before the cluster has a node. No key exists
anywhere.

Requests, no limits: core 50m / 128Mi, RBAC manager 10m / 32Mi, each
provider 50m / 320Mi. On aws that is 1440Mi requested in all.

## What you can set

Under `kube.crossplane` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on. |
| `permissions_boundary` | `""` | The IAM policy every module role must carry. The aws root fills it from the foundations' `crossplane_permissions_boundary_arn` when `aws.crossplane` is set; a value you write wins. Empty means roles are created without one, which Crossplane's own identity refuses. |
| `values` | `{}` | Any `crossplane` chart value; yours win over the socle's ([SOCLE-06](../decisions/socle.md#socle-06-the-clients-values-win)). |
| `values_secret` | `""` | The name of a Secret you create in `crossplane-system`, with a `values.yaml` key, merged last. OpenTofu never reads it. |

Refused at plan:

- `permissions_boundary` that is not empty or an IAM policy ARN.
- In `values`: a `Secret` among `extraObjects`, and an entry of
  `extraEnvVarsCrossplane`, `extraEnvVarsCrossplaneInit` or
  `extraEnvVarsRBACManager` named like a password, token, secret, credential
  or key.
- `values_secret` that is not a valid Secret name.

The aws root warns, without failing, when `kube.crossplane.enabled` is set
without `aws.crossplane`: Crossplane then installs and converges, and every
role a module declares fails at the AWS API.

:::caution[Turning it off does not delete what it provisioned]
The namespace and the release go. The CRDs, the `crossplane-no-usages`
webhook configuration and every module role still declared stay, orphaned in
your account with nothing left to delete them. Turn the modules that use
Crossplane off first, wait for their roles to be gone, then set
`enabled = false`. Turning a module and Crossplane off in the same apply
leaves the module's managed resources without a provider: their finalizers
hold the module's namespace.
:::

### Every setting

Every attribute, at its default, and how chart values and secrets go in:

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

## Per cloud

Offered by all four overlays, but only aws has providers. On gcp, azure and
scaleway, `enabled = true` installs the core alone: the `providers` and
`config` steps render nothing, and no module declares a role there. Modules
on those clouds take a credential you bring; each module page says how.

## Cloud access

Crossplane's own identity is the one the foundations create when
`aws.crossplane` is set: an IAM role bound to
`crossplane-system/provider-aws`, allowed to create roles only under
`/socle/<cluster>/` and only carrying the boundary
([AWS-18](../decisions/aws.md#aws-18-crossplanes-identity-and-its-permissions-boundary-in-the-foundations)).
The boundary allows the
services in `allowed_services` and always denies `iam`, `sts`,
`organizations`, `account`, `sso` and `identitystore`
([CROSSPLANE-01](../decisions/crossplane.md#crossplane-01-the-boundary-is-an-allowlist-of-services)).
For buckets a module owns, it may create and configure buckets named
`<cluster>-*`, and never delete one or read their objects. The full grant,
and what IAM cannot bound, are in
[Module-owned cloud access](../architecture/module-iam.md).

## Ordering

No requirement. Every module that declares a role `dependsOn` the
`crossplane` ResourceSet, which exists on every cloud and is Ready trivially
when the module is off, so their roles are applied only once the providers'
CRDs exist ([SOCLE-04](../decisions/socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)).

## Upgrade notes

The chart ships no `crds/` folder: Crossplane's init container applies its
core CRDs at every start, so a chart upgrade is a CRD upgrade, outside
Helm's CRD policy. The four providers move together, pinned to one tag. A
module back on after an off takes longer than a cold install: the providers
re-adopt the CRDs they left behind.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-09-24 | local k3s, through Flux, aws providers | `crossplane` ResourceSet Ready 99 s after it was applied, cold; a module-shaped Role in floci's IAM 3–6 s later. Off: namespace gone in 18 s, 21 Crossplane CRDs, 71 provider CRDs and the `crossplane-no-usages` webhook configuration left behind. Back on: about 5 min, the providers 3.5 min to `Healthy` against 89 s cold |
| 2026-09-24 | local k3s, idle, three aws providers (before `provider-aws-s3`) | core 109–138Mi, RBAC manager 17–21Mi, `provider-family-aws` 306–401Mi, `provider-aws-iam` 323–441Mi, `provider-aws-eks` 327–374Mi: about 1.1 GB |
| 2026-09-24 | floci, GitHub `ubuntu-latest` runner | Ready 58 s after the apply returned; right after install, core 148Mi and each provider 550–662Mi, about 2 GB |
| 2026-09-30 | floci 2.1.0, GitHub `ubuntu-latest` runner | On, core, providers and ProviderConfig converged, a module-shaped Role in IAM, and off again: under 4 min cold |

Its decisions: [crossplane decisions](../decisions/crossplane.md).
