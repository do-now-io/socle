---
title: external-secrets decisions
description: The decisions behind the external-secrets module, one per section, each with its status.
sidebar:
  order: 10
---

The external-secrets module reads the client's secrets from the cloud into
the cluster. IAM bounds it, through a name prefix, not the store; the rest
follows: one socle store on aws and gcp, read-only access, CRDs that outlive
it.

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

**superseded by [EXTERNAL-SECRETS-05](#external-secrets-05-the-socles-store-on-aws-and-gcp)** · 2026-10-02, superseded 2026-10-16 · [`oci/catalog/external-secrets/resourceset.yaml`](../../oci/catalog/external-secrets/resourceset.yaml)

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

## EXTERNAL-SECRETS-05: The socle's store, on aws and gcp

**accepted** · 2026-10-16 · [`oci/clusters/aws/external-secrets/patch.yaml`](../../oci/clusters/aws/external-secrets/patch.yaml), [`oci/clusters/gcp/external-secrets/patch.yaml`](../../oci/clusters/gcp/external-secrets/patch.yaml)

**Context.** GCP now has a Crossplane provider, so the module has an identity
to bind a store to there too: the controller's own Workload Identity
principal ([EXTERNAL-SECRETS-06](#external-secrets-06-on-gcp-one-conditional-project-binding-per-prefix)).

**Decision.** With crossplane on and at least one prefix, the module renders
one `ClusterSecretStore`, `secret-manager`, with no `auth` block: on aws on
Secrets Manager in the cluster's region, on gcp on Secret Manager in the
cluster's project (`gcpsm.projectID`, no `location`). Elsewhere, or with
crossplane off, it installs the operator alone.

**Consequences.** Every namespace may reference `secret-manager` on both
clouds. On gcp the store reads global secrets only. Azure and Scaleway gain
their store with their Crossplane provider.

**Sources.** ESO v2.11.0 `ClusterSecretStore` AWS and GCP Secret Manager
providers; [SOCLE-32](socle.md#socle-32-what-only-one-cloud-has-that-cloud-adds-to-the-module-as-steps).

## EXTERNAL-SECRETS-06: On gcp, one conditional project binding per prefix

**accepted** · 2026-10-16 · [`oci/clusters/gcp/external-secrets/patch.yaml`](../../oci/clusters/gcp/external-secrets/patch.yaml)

**Context.** A `SecretIAMMember` binds one secret, never a prefix. Secret
Manager presents a secret as `projects/<number>/secrets/<name>` and a version
as `projects/<number>/secrets/<name>/versions/<version>`, with the project's
number whatever the caller sends. `roles/secretmanager.secretAccessor` holds
`secretmanager.versions.access`, plus `resourcemanager.projects.get` and
`list`, which reach no secret. A binding's condition is replaced, never
updated in place. The workload pool is the project's, so the subject
`ns/external-secrets/sa/external-secrets` is the same for every cluster of a
project.

**Decision.** With crossplane on, one `ProjectIAMMember` per prefix grants
`roles/secretmanager.secretAccessor` to the principal of
`external-secrets/external-secrets`, no Google service account, under the
condition `resource.name.startsWith('projects/<number>/secrets/<prefix>_')`.
The module's chart waits for every binding to be Ready.

**Consequences.** Read-only: no `secrets.list` or `secrets.get`, so neither
`dataFrom.find`, `metadataPolicy: Fetch` nor
`secretVersionSelectionPolicy: LatestOrFetch`. Crossplane grants the role only
when the client lists it in `gcp.crossplane.allowed_roles`; otherwise IAM
refuses the binding, it never turns Ready, and the operator is withheld,
visibly. Adding a prefix adds a binding and leaves the others alone. Two
socle clusters in one project read what either's bindings allow: one socle
cluster per GCP project is the supported topology.

**Sources.** [Secret Manager access control](https://cloud.google.com/secret-manager/docs/access-control);
[IAM Conditions](https://cloud.google.com/iam/docs/conditions-overview);
[Workload Identity Federation for GKE](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity);
`gcloud iam roles describe roles/secretmanager.secretAccessor`, 2026-10-07;
provider-upjet-gcp v3.0.0 `ProjectIAMMember`.

## EXTERNAL-SECRETS-07: On gcp, `_` ends the prefix

**accepted** · 2026-10-16 · [`oci/clusters/gcp/external-secrets/patch.yaml`](../../oci/clusters/gcp/external-secrets/patch.yaml), [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf)

**Context.** Secret Manager names are `[A-Za-z0-9_-]`, without the `/` that
ends an AWS prefix: a bare `startsWith` on `acme-prod` would also read
`acme-prod2-db` and `acme-production-…`.

**Decision.** The condition names `<prefix>_`; on gcp a prefix is
`[A-Za-z0-9-]`, refused at plan otherwise; a secret the module reads is named
`<prefix>_<name>`.

**Consequences.** `remoteRef.key` is the secret's whole name,
`acme-prod_shop-db`. `prod_` never matches `prod-eu_db`.

**Sources.** [Secret Manager secret naming](https://cloud.google.com/secret-manager/docs/creating-and-accessing-secrets).
