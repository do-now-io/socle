---
title: external-dns decisions
description: The decisions behind the external-dns module, one per section, each with its status.
sidebar:
  order: 10
---

external-dns was the first module to declare its own cloud role
([SOCLE-04](socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)):
how that role is scoped on Route 53, and where the cloud is chosen.

## EXTERNAL-DNS-01: Route 53 writes scoped by record name

**accepted** · 2026-09-24 · [`oci/catalog/external-dns/resourceset.yaml`](../../oci/catalog/external-dns/resourceset.yaml)

**Decision.** `ChangeResourceRecordSets` is allowed on every zone only when
every name in the batch (`ForAllValues:StringLike`) is a `domain_filters`
entry or under one, lowercased and without the trailing dot. Reads stay on
every zone: Route 53 has no condition key for them.

**Context.** Scoping by zone needs hosted zone ids the client would copy by
hand, since Crossplane cannot look them up; the boundary alone
([CROSSPLANE-01](crossplane.md#crossplane-01-the-boundary-is-an-allowlist-of-services))
would let the role rewrite every zone of the account.

**Consequences.** IAM enforces `domain_filters` with no zone id to copy. A
zone delegated under two clusters' filters is writable by both; the TXT
registry keeps them apart. floci enforces no IAM, so the refusal is proven
only on a real account.

**Sources.** AWS Route 53 condition key `route53:ChangeResourceRecordSetsNormalizedRecordNames`.

## EXTERNAL-DNS-02: The cloud is chosen in the template, not by overlay patches

**accepted** · 2026-09-24 · [`oci/catalog/external-dns/resourceset.yaml`](../../oci/catalog/external-dns/resourceset.yaml), [`oci/clusters/aws/kustomization.yaml`](../../oci/clusters/aws/kustomization.yaml)

**Decision.** Each cloud is one `<< if eq inputs.cloud … >>` block inside the
socle-values document; the overlays list the module and patch nothing.

**Context.** The socle's values live in a ConfigMap listed first in
`valuesFrom` so the client's win
([SOCLE-06](socle.md#socle-06-the-clients-values-win)); an overlay patch
cannot reach a value inside a ConfigMap's YAML string.

**Consequences.** A shared default changes in one place. Every module whose
values live in a ConfigMap puts per-cloud values in the template the same way.

**Sources.** helm-controller `valuesFrom` merge order; `chartutil.ChartValuesFromReferences` in `fluxcd/pkg`.
