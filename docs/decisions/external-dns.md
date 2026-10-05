---
title: external-dns decisions
description: The decisions behind the external-dns module, one per section, each with its status.
sidebar:
  order: 10
---

external-dns was the first module to declare its own cloud role
([SOCLE-04](socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)).
Its decisions are how that role is scoped on Route 53, and where the cloud is
chosen in its template.

## EXTERNAL-DNS-01: Route 53 writes scoped by record name

**accepted** · 2026-09-24 · [`oci/catalog/external-dns/resourceset.yaml`](../../oci/catalog/external-dns/resourceset.yaml)

**Context.** The module's role must write records into the client's zones
and nowhere else. Three scopes were possible:

- **By zone**: `ChangeResourceRecordSets` on `hostedzone/<id>` for each zone.
  The tightest resource scope, but a hosted zone id is random: nothing maps
  `acme.example` to `Z0123…`, and Crossplane has no data source to look it
  up. It would take a `zone_ids` attribute the client copies from the console
  and keeps in step with `domain_filters`.
- **By the boundary alone**: `route53:*` on `*`, capped by Crossplane's
  boundary. The boundary names services, not resources
  ([CROSSPLANE-01](crossplane.md#crossplane-01-the-boundary-is-an-allowlist-of-services)):
  the role could rewrite every zone of the account, another cluster's or the
  company's apex included.
- **By record name**: Route 53's condition key
  `route53:ChangeResourceRecordSetsNormalizedRecordNames` holds the names in a
  change batch.

**Decision.** `ChangeResourceRecordSets` is allowed on every hosted zone only
when every name in the batch (`ForAllValues:StringLike`) is a
`domain_filters` entry or under one: `acme.example` and `*.acme.example` for
each filter, lowercased and without the trailing dot, the normalised form the
key compares. Reads stay on every zone, since Route 53 has no condition key
for them.

**Consequences.** IAM enforces what `domain_filters` already says, with no
zone id for the client to copy; the `socle-` TXT records sit under the same
names and pass. The role can read every zone of the account. A zone of
another cluster delegated under one of this cluster's filters is writable by
both; the TXT registry keeps them apart, IAM does not. floci enforces no IAM
policy, so the refusal of a name outside the filters is proven only on a
real account.

**Sources.** AWS Route 53 condition keys,
`route53:ChangeResourceRecordSetsNormalizedRecordNames`.

## EXTERNAL-DNS-02: The cloud is chosen in the template, not by overlay patches

**accepted** · 2026-09-24 · [`oci/catalog/external-dns/resourceset.yaml`](../../oci/catalog/external-dns/resourceset.yaml), [`oci/clusters/aws/kustomization.yaml`](../../oci/clusters/aws/kustomization.yaml)

**Context.** The provider and its credential differ per cloud. They were
first JSON 6902 patches in `oci/clusters/<cloud>/`, on the HelmRelease's
`spec.values`. The socle's values then moved into a ConfigMap listed first
in `valuesFrom`, so that the client's win
([SOCLE-06](socle.md#socle-06-the-clients-values-win)); a patch cannot reach
a value inside a ConfigMap's YAML string. Replacing the whole document per
cloud would copy every shared default four times.

**Decision.** Each cloud is one `<< if eq inputs.cloud … >>` block inside the
socle-values document. The overlays list the module and patch nothing.

**Consequences.** One file holds every cloud's provider, and a shared default
changes in one place. Any module whose values live in a ConfigMap follows the
same rule: a per-cloud value goes in the template, under an `if` on
`inputs.cloud`.

**Sources.** helm-controller `valuesFrom` merge order;
`chartutil.ChartValuesFromReferences` in `fluxcd/pkg`.
