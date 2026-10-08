---
title: external-secrets
description: Kubernetes Secrets read from your cloud's secret manager, kept in step when they rotate.
category: secrets
requires: []
---

External Secrets Operator (ESO) turns an `ExternalSecret` into a Kubernetes
`Secret` read from your cloud's secret manager, kept in step when it rotates;
pair it with [reloader](reloader.md) so the pods roll. **Off by default**. On
aws with crossplane on, the socle also gives it a read-only role and one store.

## Getting started

On aws, add `secretsmanager` to `aws.crossplane.allowed_services`, then turn it
on with crossplane and reloader; the role reads the secrets under `acme-prod/`:

```hcl title="terraform.tfvars" kube-start="external_secrets"
kube = {
  crossplane = { enabled = true }
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
| `prefixes` | `[<cluster name>]` | On aws, the Secrets Manager name paths the role reads. `[]`: no role, no store. |
| `values` | `{}` | Any [`external-secrets` chart](https://artifacthub.io/packages/helm/external-secrets-operator/external-secrets) value; yours win. |
| `values_secret` | `""` | A Secret in `external-secrets` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl title="terraform.tfvars" kube-full="external_secrets"
kube = {
  external_secrets = {
    enabled  = false         # off by default
    prefixes = ["acme-prod"] # default: the cluster's name; [] = no role, no store

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
  prefix (`acme-prod/shop/db`). Add `reloader.stakater.com/auto: "true"` to
  the Deployment that reads the Secret.
- **Anyone who may create an `ExternalSecret` reads every secret under the
  prefixes.** Keep one prefix per cluster, the default, and other teams'
  secrets out of it; for per-team isolation, set `prefixes = []` and give
  each team a `SecretStore` on its own credentials.
- **Read-only, by name.** No listing (`dataFrom.find` fails), no writing
  (`PushSecret` is off), no `kms:Decrypt`: a customer-managed key's policy
  must name the role.
- **On gcp, azure, scaleway, or with crossplane off**, it is the operator
  alone: you write the stores, with credentials in a Secret.
- **Upgrades**: the chart moves with `socle_version`. The CRDs are kept when
  the module is off, so your `ExternalSecret`s and their `Secret`s survive.

<details>
<summary>Under the hood</summary>

**Installed**: chart `external-secrets` 2.11.0 (ESO v2.11.0) from
`oci://ghcr.io/external-secrets/charts/external-secrets`, in `external-secrets`
(Pod Security `restricted`). On aws with crossplane on and a prefix,
`Role/external-secrets`, `PodIdentityAssociation/external-secrets` and
`ClusterSecretStore/secret-manager`.

**What the socle sets**: CRDs kept on removal, `PushSecret` processing off,
small requests with memory limits, and scrape annotations for
[otel-gateway](otel-gateway.md). Your `values` are merged over these.

**Cloud access**: on aws, the role `<cluster>-external-secrets` may only
`GetSecretValue` and `DescribeSecret` on `secret:<prefix>/*` in the cluster's
region.
Elsewhere, none.

**Ordering**: waits for the `crossplane` ResourceSet; the chart waits for the
role and its association, the store for the chart. Turn the module off before
crossplane, never in the same apply.

**Measured** on floci, 2026-10-02: a rotation reached the `Secret` and
Reloader rolled the Deployment in 25 s (`refreshInterval: 10s`).

</details>
