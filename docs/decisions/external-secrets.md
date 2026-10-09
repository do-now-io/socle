---
title: external-secrets decisions
description: The decisions behind the external-secrets module, one per section, each with its status.
sidebar:
  order: 10
---

The external-secrets module reads the client's secrets from the cloud into
the cluster. IAM bounds it, through a name prefix, not the store; the rest
follows: one socle store on aws only, read-only access, CRDs that outlive it.

## EXTERNAL-SECRETS-01: The name prefix is the boundary

**accepted** · 2026-10-02 · [`oci/catalog/external-secrets/resourceset.yaml`](../../oci/catalog/external-secrets/resourceset.yaml), [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf)

**Decision.** The role reads `secret:<prefix>/*` for each entry of
`kube.external_secrets.prefixes`, nothing else; the default is the cluster
name. Each entry is validated at plan: no wildcard, no leading or trailing `/`.

**Context.** A namespaced `SecretStore` with no `auth` block falls back to the
controller's own role, and the chart aggregates ESO's kinds into `edit` and
`admin`: anyone who can create a `SecretStore` reads what the role reads,
whatever fence the socle's store carries.

**Consequences.** Every namespace that may create an `ExternalSecret` or a
`SecretStore` reads every secret under the prefixes. Two clusters in one
account never read each other's secrets unless listed. Per-team isolation is
the client's.

**Sources.** ESO v2.11.0 provider resolution for a store without `auth`; the chart's `rbac.aggregateToEdit`.

## EXTERNAL-SECRETS-02: The socle's store, on aws only

**accepted** · 2026-10-02 · [`oci/catalog/external-secrets/resourceset.yaml`](../../oci/catalog/external-secrets/resourceset.yaml)

**Decision.** On aws with crossplane on and at least one prefix, the module
renders one `ClusterSecretStore`, `secret-manager`, on Secrets Manager in the
cluster's region, with no `auth` block. Elsewhere it installs the operator alone.

**Context.** Only aws has a Crossplane provider, so only there does the module
have an identity to bind a store to.

**Consequences.** Every namespace may reference `secret-manager`. Elsewhere
the client creates the store and its credential Secret; each cloud gains its
store with its Crossplane provider.

**Sources.** ESO `ClusterSecretStore` AWS provider.

## EXTERNAL-SECRETS-03: Read-only, two calls

**accepted** · 2026-10-02 · [`oci/catalog/external-secrets/resourceset.yaml`](../../oci/catalog/external-secrets/resourceset.yaml)

**Decision.** The role holds `secretsmanager:GetSecretValue` and
`secretsmanager:DescribeSecret` on the prefixes, nothing else. The
`PushSecret` and `ClusterPushSecret` reconcilers are off.

**Context.** `ListSecrets` and `BatchGetSecretValue` take no resource scope and
would list every secret name of the account; `PushSecret` writes to the cloud.

**Consequences.** `dataFrom.find` does not work with the socle's store. No
`kms:Decrypt`: a secret on a customer key needs that key's policy to name the
role. Parameter Store is not covered.

**Sources.** AWS Secrets Manager actions, resources and condition keys.

## EXTERNAL-SECRETS-04: The CRDs are kept when the module is off

**accepted** · 2026-10-02 · [`oci/catalog/external-secrets/resourceset.yaml`](../../oci/catalog/external-secrets/resourceset.yaml)

**Decision.** The chart installs the CRDs annotated
`helm.sh/resource-policy: keep`; the general rule is in
[CRDs when a module is off](../architecture/flux-catalog.md#crds-when-a-module-is-off).

**Context.** Deleting the CRDs would delete every `ExternalSecret`, and every
`Secret` it owns.

**Consequences.** Turning the module off removes the operator only; the
client's objects stay, inert, and Helm adopts the CRDs when it comes back.
They carry no conversion webhook, so they keep serving with the operator gone.

**Sources.** Helm `helm.sh/resource-policy`; the external-secrets chart 2.11.0.
