---
title: external-secrets
description: Kubernetes Secrets read from your cloud's secret manager, kept in step when they rotate.
category: secrets
requires: []
---

External Secrets Operator (ESO) turns an `ExternalSecret` into a Kubernetes
`Secret` read from your cloud's secret manager, and updates it when the value
rotates there. Pair it with [reloader](reloader.md) so the pods reading that
Secret roll. It is **off by default**. On aws with crossplane on, the socle
also gives it a read-only role and one store; elsewhere you bring the stores.

## Getting started

On aws, let Crossplane's boundary allow Secrets Manager:

```hcl
# opentofu/clusters/aws, in your tfvars
aws = { crossplane = { allowed_services = ["secretsmanager"] } }
```

Then turn the module on with crossplane, and reloader for the pods to roll.
The role reads the secrets under your cluster's name, `acme-prod/` here:

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

After the apply, `kubectl -n flux-system get resourceset external-secrets` is
Ready and `kubectl get clustersecretstore secret-manager` is `Valid`. An
`ExternalSecret` of yours then reads a secret through it:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: { name: db, namespace: shop }
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: ClusterSecretStore, name: secret-manager }
  target: { name: db }
  data:
    - secretKey: password
      remoteRef: { key: acme-prod/shop/db, property: password }
# the Deployment reading Secret db carries reloader.stakater.com/auto: "true"
```

## What it installs

| | |
| --- | --- |
| Chart | `external-secrets` `2.11.0` (ESO v2.11.0) from `oci://ghcr.io/external-secrets/charts/external-secrets` |
| Namespace | `external-secrets`, Pod Security `restricted` enforced |
| Objects | `Namespace/external-secrets`; on aws with crossplane on and a prefix, `Role/external-secrets` and `PodIdentityAssociation/external-secrets`; the child `ResourceSet/external-secrets-workload` holding `OCIRepository/external-secrets-chart`, `ConfigMap/external-secrets-socle-values`, `ConfigMap/external-secrets-client-values` and `HelmRelease/external-secrets`; where the role exists, the child `ResourceSet/external-secrets-store` holding `ClusterSecretStore/secret-manager` |

The socle's values:

| Value | Setting |
| --- | --- |
| `fullnameOverride` | `external-secrets` |
| `installCRDs`, `crds.annotations` | `true`, `helm.sh/resource-policy: keep`: the CRDs outlive the module |
| `serviceAccount.name` | `external-secrets`, the role's subject. The webhook and the cert controller talk to no cloud |
| `processPushSecret`, `processClusterPushSecret` | `false`: nothing in the cluster writes to the cloud |
| Resources | controller 10m / 64Mi, limit 256Mi; webhook and cert controller 10m / 32Mi, limit 128Mi |
| `podAnnotations` | `prometheus.io/scrape` on port 8080, for [otel-gateway](otel-gateway.md) |

The chart's own security contexts run the three pods non-root, read-only,
every capability dropped, `RuntimeDefault` seccomp.

## What you can set

Under `kube.external_secrets` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on. |
| `prefixes` | `[<cluster name>]` | On aws, the Secrets Manager name paths the module's role reads: `secret:<prefix>/*` for each. `[]` means no role and no store. |
| `values` | `{}` | Any `external-secrets` chart value; yours win over the socle's ([SOCLE-06](../decisions/socle.md#socle-06-the-clients-values-win)). |
| `values_secret` | `""` | The name of a Secret you create in `external-secrets`, with a `values.yaml` key, merged last. Label it `reconcile.fluxcd.io/watch: Enabled` for a change to apply before the next interval. |

Refused at plan:

- A `prefixes` entry that is not a Secrets Manager name path: letters,
  digits and `_+=.@-`, segments separated by `/`, no leading or trailing
  `/`, no wildcard, at most 256 characters.
- On aws, with the module and crossplane on and `prefixes` not empty, an
  empty `region` in the bootstrap module: the role is scoped to the region's
  secrets and the association is regional. The aws root passes `aws.region`.
- In `values`: a `Secret` among `extraObjects`, and an `extraEnv`,
  `webhook.extraEnv` or `certController.extraEnv` entry with a literal value
  whose name looks like a credential (`valueFrom` passes;
  `AWS_SECRETSMANAGER_ENDPOINT` is an endpoint and passes).
- `values_secret` that is not a valid Secret name.

### Every setting

Every attribute, at its default, and how chart values and secrets go in:

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

## Per cloud

On aws with crossplane on and at least one prefix: the module's role and
the `secret-manager` store. On aws with crossplane off or `prefixes = []`,
and on gcp, azure and scaleway: the operator alone; you write your
`SecretStore`s or `ClusterSecretStore`s, with credentials in a Secret their
`auth` block names.

## Cloud access

On aws with crossplane on and a prefix, the module declares its own IAM role,
`<cluster>-external-secrets` under `/socle/<cluster>/`, carrying the
permissions boundary, bound by Pod Identity to
`external-secrets/external-secrets`. Its one inline policy is read-only. For
`prefixes = ["acme-prod", "shared/platform"]` in `eu-west-3`:

```json
{"Version": "2012-10-17", "Statement": [{
  "Sid": "ReadSecretsUnderThePrefixes", "Effect": "Allow",
  "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
  "Resource": ["arn:aws:secretsmanager:eu-west-3:*:secret:acme-prod/*",
               "arn:aws:secretsmanager:eu-west-3:*:secret:shared/platform/*"]}]}
```

No `ListSecrets` or `BatchGetSecretValue`, so no `dataFrom.find`; no
`kms:Decrypt`: a secret on a customer-managed key needs that key's policy to
name the role. The account is `*` because the account id is not among the
inputs; a role acts only in its own account. The boundary must allow
`secretsmanager`.

**Every namespace that may create an `ExternalSecret` or a `SecretStore` can
read every secret under the prefixes.** A `SecretStore` with no `auth` block
falls back to the controller's own role, and the chart aggregates ESO's kinds
into the `edit` and `admin` ClusterRoles
([EXTERNAL-SECRETS-01](../decisions/external-secrets.md#external-secrets-01-the-name-prefix-is-the-boundary)).
Keep one prefix per cluster, the default, and other teams' secrets out of
it. For per-team isolation, set `prefixes = []` and give each team a
`SecretStore` on its own credentials, or set `processSecretStore: false` and
`rbac.aggregateToEdit: false` through `values`.

## Ordering

The module requires nothing. It waits for crossplane: the
`external-secrets` ResourceSet `dependsOn` the `crossplane` ResourceSet,
Ready trivially when crossplane is off. Where the role exists,
`external-secrets-workload` waits for the Role and the association to be
`Ready` (Pod Identity hands credentials at admission only), and
`external-secrets-store` waits for the HelmRelease: the store's CRD comes
with the chart and ESO's webhook must answer
([Module-owned cloud access](../architecture/module-iam.md)). Turn the module
off before crossplane, never in the same apply.

## Upgrade notes

The CRDs are kept when the module is turned off: your `ExternalSecret`s,
`SecretStore`s and the `Secret`s they own survive. Turned back on, the
release adopts them. They carry no conversion webhook, so they keep serving
with the operator gone.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-10-02 | floci, GitHub `ubuntu-latest` runner, crossplane off, a store on static keys | Operator on, three Deployments Available in 33 s; a seeded secret became a `Secret` in 2 s; a rotation reached the `Secret` and Reloader rolled the Deployment in 25 s (`refreshInterval: 10s`); off in 13 s with the CRDs still Established |
| 2026-10-02 | floci, crossplane on | Providers Healthy and the Role declared in 68 s; the Role in floci's IAM under `/socle/<cluster>/`, reading `secret:<cluster>/*`, neither listing nor writing |

Its decisions: [external-secrets decisions](../decisions/external-secrets.md).
