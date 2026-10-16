---
title: external-secrets
description: Kubernetes Secrets read from your cloud's secret manager, kept in step when they rotate.
category: secrets
requires: []
---

External Secrets Operator (ESO) turns an `ExternalSecret` into a Kubernetes
`Secret` read from your cloud's secret manager, kept in step when it rotates;
pair it with [reloader](reloader.md) so the pods roll. **Off by default**. On
aws and gcp with crossplane on, the socle also gives it read-only access and
one store.

## Getting started

On aws, add `secretsmanager` to `aws.crossplane.allowed_services`; on gcp,
`roles/secretmanager.secretAccessor` to `gcp.crossplane.allowed_roles`. Then
turn it on with crossplane and reloader; it reads the secrets under
`acme-prod/` on aws, the secrets named `acme-prod_…` on gcp:

```hcl kube-start="external_secrets"
kube = {
  crossplane = { enabled = true } # aws: the module's own role; gcp: its own IAM bindings
  external_secrets = {
    enabled  = true
    prefixes = ["acme-prod"]
  }
  reloader = { enabled = true }
}
```

Then `kubectl get clustersecretstore secret-manager` is `Valid`.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on or off. |
| `prefixes` | `[<cluster name>]` | On aws, the Secrets Manager name paths the role reads; on gcp, the Secret Manager name prefixes it reads, letters, digits and `-`. `[]`: no access, no store. |
| `values` | `{}` | Any [`external-secrets` chart](https://artifacthub.io/packages/helm/external-secrets-operator/external-secrets) value; yours win. |
| `values_secret` | `""` | A Secret in `external-secrets` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl kube-full="external_secrets"
kube = {
  external_secrets = {
    enabled  = false         # off by default
    prefixes = ["acme-prod"] # default: the cluster's name; [] = no access, no store

    # Any value of the external-secrets chart 2.11.0; yours win over the socle's.
    values = {
      concurrent = 2
      log        = { level = "debug" }
    }

    # A Secret you create in external-secrets, whose values.yaml key holds
    # chart values that must not reach the OpenTofu state, such as an extraEnv
    # proxy URL with a password in it.
    values_secret = "external-secrets-values"
  }
}
```

## Good to know

- **Point your `ExternalSecret`s at the store**: `secretStoreRef: { kind:
  ClusterSecretStore, name: secret-manager }`, `remoteRef.key` under a
  prefix: `acme-prod/shop/db` on aws; on gcp the secret's name, `_` after
  the prefix, `acme-prod_shop-db` (Secret Manager names have no `/`). Add
  `reloader.stakater.com/auto: "true"` to the Deployment that reads the
  Secret.
- **Anyone who may create an `ExternalSecret` reads every secret under the
  prefixes.** Keep one prefix per cluster, the default, and other teams'
  secrets out of it; for per-team isolation, set `prefixes = []` and give
  each team a `SecretStore` on its own credentials.
- **Read-only, by name.** No listing (`dataFrom.find` fails), no writing
  (`PushSecret` is off), no `kms:Decrypt`: a customer-managed key's policy
  must name the role. On gcp, no `metadataPolicy: Fetch` and no
  `secretVersionSelectionPolicy: LatestOrFetch` either: both read more than
  a version's value.
- **On gcp, one socle cluster per project**: two clusters in one project
  share the controller's principal, so each reads what either's prefixes
  allow. Global secrets only: the store sets no `location`.
- **On azure, scaleway, or with crossplane off**, it is the operator
  alone: you write the stores, with credentials in a Secret.
- **Upgrades**: the chart moves with `socle_version`. The CRDs are kept when
  the module is off, so your `ExternalSecret`s and their `Secret`s survive.

<details>
<summary>Under the hood</summary>

**Installed**: chart `external-secrets` 2.11.0 (ESO v2.11.0) from
`oci://ghcr.io/external-secrets/charts/external-secrets`, in `external-secrets`
(Pod Security `restricted`). On aws with crossplane on and a prefix,
`Role/external-secrets`, `PodIdentityAssociation/external-secrets` and
`ClusterSecretStore/secret-manager`. On gcp with crossplane on and a prefix,
one `ProjectIAMMember/external-secrets-<name>` per prefix and
`ClusterSecretStore/secret-manager` (`gcpsm`, the cluster's project).
`<name>` is derived from the prefix: lowercased, every character an object
name refuses turned into `-`, and, when the prefix holds capitals, such a
character, a trailing `-` or more than 40 characters, cut to 37 characters
and followed by 8 of the prefix's SHA-1, so that two prefixes never share a
name. The default prefix, the cluster's name, is used as it stands.

**What the socle sets**: CRDs kept on removal, `PushSecret` processing off,
small requests (cpu, memory and ephemeral storage, which GKE Autopilot needs)
with memory limits, and, while [monitoring](monitoring.md)
is on, the metrics Services it scrapes. Your `values` are merged over these.

**Cloud access**: on aws, the role `<cluster>-external-secrets` may only
`GetSecretValue` and `DescribeSecret` on `secret:<prefix>/*` in the cluster's
region. On gcp, `roles/secretmanager.secretAccessor` for the principal of
`external-secrets/external-secrets` — Workload Identity, no Google service
account — one project-level binding per prefix under the IAM condition
`resource.name.startsWith('projects/<number>/secrets/<prefix>_')`: the
value of the secrets named `<prefix>_<name>`, nothing else. A binding is
named `external-secrets-<prefix>`; a prefix with capitals, a trailing `-` or
over 40 characters gets eight characters of its SHA-1 instead.
Elsewhere, none.

**Ordering**: the module's `ResourceSet` applies its steps in order,
each once the one before is healthy: the namespace, then the chart. On aws,
[`oci/clusters/aws/external-secrets/patch.yaml`](../../oci/clusters/aws/external-secrets/patch.yaml)
adds what only aws has: the module waits for the `crossplane` ResourceSet, a
`cloud` step before the chart holds the role and its association and is
healthy only once both are Ready, and a `store` step after the chart holds
the `ClusterSecretStore`. On gcp,
[`oci/clusters/gcp/external-secrets/patch.yaml`](../../oci/clusters/gcp/external-secrets/patch.yaml)
does the same with the bindings: the chart waits until each is Ready, as a
controller started before them would fail its first reads. Turn the module
off before crossplane, never in the same apply.

**Measured** on floci, 2026-10-02: a rotation reached the `Secret` and
Reloader rolled the Deployment in 25 s (`refreshInterval: 10s`). On gcp,
`external-secrets-module-gke` (`platform: gke`), run by hand on the
sandbox's GKE Autopilot, reads the binding, a secret under the prefix
turned into a `Secret`, and one outside it refused with `PermissionDenied`:
passed on 2026-10-16 (artifact `0.0.0-feat-gcp-parity.d896756`, 48 s), and turning the module off
removed its binding from the project.

</details>
