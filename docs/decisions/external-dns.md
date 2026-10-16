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

**superseded by [SOCLE-32](socle.md#socle-32-what-only-one-cloud-has-that-cloud-adds-to-the-module-as-steps)** · 2026-09-24 · [`oci/catalog/external-dns/resourceset.yaml`](../../oci/catalog/external-dns/resourceset.yaml), [`oci/clusters/aws/kustomization.yaml`](../../oci/clusters/aws/kustomization.yaml)

**Decision.** Each cloud is one `<< if eq inputs.cloud … >>` block inside the
socle-values document; the overlays list the module and patch nothing.

**Context.** The socle's values live in a ConfigMap listed first in
`valuesFrom` so the client's win
([SOCLE-06](socle.md#socle-06-the-clients-values-win)); an overlay patch
cannot reach a value inside a ConfigMap's YAML string.

**Consequences.** A shared default changes in one place. Every module whose
values live in a ConfigMap puts per-cloud values in the template the same way.

**Sources.** helm-controller `valuesFrom` merge order; `chartutil.ChartValuesFromReferences` in `fluxcd/pkg`.

## EXTERNAL-DNS-03: Cloud DNS through a project role, bounded by the domain filters

**accepted** · 2026-10-16 · [`oci/clusters/gcp/external-dns/patch.yaml`](../../oci/clusters/gcp/external-dns/patch.yaml)

**Context.** Route 53's answer
([EXTERNAL-DNS-01](#external-dns-01-route-53-writes-scoped-by-record-name))
has no Cloud DNS equivalent: a change carries no condition on its names, and
IAM conditions do not apply to Cloud DNS. A managed zone is a resource IAM
binds on, so the first design bound external-dns on each zone the client
listed, which needed Crossplane to set that zone's IAM policy. Measured on
the sandbox project (2026-10-07): `dns.managedZones.getIamPolicy` and
`setIamPolicy` granted at zone level, by a custom role and even by
`roles/dns.admin`, are never honoured (403 for over four minutes), while
record operations granted at the same level are. A zone's IAM needs a
project-level grant, which nothing bounds to one zone.

**Decision.** With Crossplane on, the module declares one
`ProjectIAMMember`: the foundations' custom role
(`inputs.modules.crossplane.dns_records_role`, `socleDnsRecords_<cluster>`:
`dns.managedZones.{get,list}`, `dns.changes.{create,get,list}`,
`dns.resourceRecordSets.{create,delete,get,list,update}`) on the cluster's
project, for the ServiceAccount's own Workload Identity principal, by project
number. No Google service account. Crossplane holds no Cloud DNS IAM; this
role is always among those it may grant. external-dns is pointed at the
project (`--google-project`) and at public zones only
(`--google-zone-visibility=public`).

**Consequences.** external-dns may write the records of every zone of the
project; what it does write is bounded by `--domain-filter` in software, not
by IAM. One socle cluster per project, and no other team's zones in it. A
split-horizon private zone of the same name is left alone unless the client
asks for it through `values`. The proof is a Chainsaw test run by hand on the
sandbox's GKE (`external-dns-module-gke`): no GKE in CI, and floci-gcp serves
neither Workload Identity nor Cloud DNS.

**Sources.** external-dns v0.22.0 `provider/google/google.go`
(`ManagedZones.List` on every loop, project from the metadata server when
`--google-project` is absent); Google Cloud, [Cloud DNS access control](https://cloud.google.com/dns/docs/access-control);
provider-upjet-gcp v3.0.0 `cloudplatform.gcp.m.upbound.io_projectiammembers.yaml`;
PR #84; `external-dns-module-gke` passed on the sandbox, 2026-10-16 (artifact
`0.0.0-feat-gcp-parity.d896756`).
