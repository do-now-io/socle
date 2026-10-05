---
title: external-secrets decisions
description: The decisions behind the external-secrets module, one per section, each with its status.
sidebar:
  order: 10
---

The external-secrets module reads the client's secrets from the cloud and
writes them into the cluster. What bounds it is IAM, through a name prefix,
not the store: that is the decision to know first. The others follow from it:
one socle store on aws only, read-only access, and CRDs that outlive the
module.

## EXTERNAL-SECRETS-01: The name prefix is the boundary

**accepted** · 2026-10-02 · [`oci/catalog/external-secrets/resourceset.yaml`](../../oci/catalog/external-secrets/resourceset.yaml), [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf)

**Context.** A `ClusterSecretStore` can be fenced to some namespaces
(`spec.conditions`). But a namespaced `SecretStore` with no `auth` block falls
back to the controller's own credential chain, the module's Pod Identity
role, and the chart aggregates ESO's kinds into the `edit` and `admin`
ClusterRoles. Anyone allowed to create a `SecretStore` in any namespace
therefore reads whatever the role reads, whatever fence the socle's store
carries.

**Decision.** The role reads `secret:<prefix>/*` for each entry of
`kube.external_secrets.prefixes`, and nothing else. The default is the
cluster name; a list, because shared secrets (`shared/platform/*`) rarely
live under one cluster's name. Each entry is validated at plan as a Secrets
Manager name path with no wildcard and no leading or trailing `/`.

**Consequences.** Every namespace that may create an `ExternalSecret` or a
`SecretStore` can read every secret under the prefixes; the module page says
so. Two clusters in one account never read each other's secrets unless the
client lists the other's prefix. Per-team isolation is the client's: no
socle store, and a `SecretStore` per team on its own credentials, or
`processSecretStore: false` through `values`.

**Sources.** ESO v2.11.0 provider resolution for a store without `auth`; the
chart's `rbac.aggregateToEdit`.

## EXTERNAL-SECRETS-02: The socle's store, on aws only

**accepted** · 2026-10-02 · [`oci/catalog/external-secrets/resourceset.yaml`](../../oci/catalog/external-secrets/resourceset.yaml)

**Context.** A store bound to the module's role is the natural default: the
role exists for it, and a client who turns the module on with crossplane
expects to write an `ExternalSecret` and nothing else. Only aws has a
Crossplane provider, so only there does the module have an identity to bind
a store to.

**Decision.** On aws with crossplane on and at least one prefix, the module
renders one `ClusterSecretStore`, `secret-manager`, on Secrets Manager in the
cluster's region, with no `auth` block. Elsewhere it installs the operator
alone and the client writes his stores.

**Consequences.** Every namespace may reference `secret-manager`. On gcp,
azure and scaleway, and on aws with crossplane off, the client creates the
store and its credential Secret. Each of those clouds gains its role and its
store with its Crossplane provider.

**Sources.** ESO `ClusterSecretStore` AWS provider.

## EXTERNAL-SECRETS-03: Read-only, two calls

**accepted** · 2026-10-02 · [`oci/catalog/external-secrets/resourceset.yaml`](../../oci/catalog/external-secrets/resourceset.yaml)

**Context.** A `remoteRef` needs `GetSecretValue` for the value and
`DescribeSecret` for the version and metadata. `ListSecrets` and
`BatchGetSecretValue` take no resource scope: granting them lists every
secret name of the account. `PushSecret` writes from the cluster to the
cloud.

**Decision.** The role holds `secretsmanager:GetSecretValue` and
`secretsmanager:DescribeSecret` on the prefixes, nothing else. The chart's
`PushSecret` and `ClusterPushSecret` reconcilers are off.

**Consequences.** `dataFrom.find` does not work with the socle's store. No
`kms:Decrypt`: a secret on the account's `aws/secretsmanager` key needs
none; one on a customer key needs that key's policy to name the role, the
key owner's decision. Parameter Store is not covered.

**Sources.** AWS Secrets Manager actions, resources and condition keys.

## EXTERNAL-SECRETS-04: The CRDs are kept when the module is off

**accepted** · 2026-10-02 · [`oci/catalog/external-secrets/resourceset.yaml`](../../oci/catalog/external-secrets/resourceset.yaml)

**Context.** ESO's CRDs are cluster-wide and the client's objects live in
them. Deleting them with the module would delete every `ExternalSecret`,
and every `Secret` whose `ownerReference` is one.

**Decision.** The chart installs the CRDs annotated
`helm.sh/resource-policy: keep`. The general rule is in
[CRDs when a module is off](../architecture/flux-catalog.md#crds-when-a-module-is-off).

**Consequences.** Turning the module off removes the operator only; the
client's objects stay, inert. Turned back on, Helm adopts the CRDs, whose
release annotations still name this release. The CRDs carry no conversion
webhook (`crds.conversion.enabled: false`, the chart's default), so a kept
CRD keeps serving with the operator gone.

**Sources.** Helm `helm.sh/resource-policy`; the external-secrets chart
2.11.0.
