---
title: crossplane decisions
description: The decisions behind the crossplane module, one per section, each with its status.
sidebar:
  order: 10
---

The crossplane module is the tooling of the socle's rule that each module
owns its cloud access ([SOCLE-04](socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)).
The decisions here are what bounds that tooling: a boundary that names
services, raw managed resources in each module rather than a shared
abstraction, and off by default for its cost.

## CROSSPLANE-01: The boundary is an allowlist of services

**accepted** · 2026-09-24 · [`opentofu/aws/iam.tf`](../../opentofu/aws/iam.tf), [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf)

**Context.** Crossplane's identity and the permissions boundary every role
it creates must carry are the foundations'
([AWS-18](aws.md#aws-18-crossplanes-identity-and-its-permissions-boundary-in-the-foundations)).
What the boundary names was the choice: resources (the zones, prefixes and
buckets each module needs) or services. Resources would put each module's
needs into the foundations, against the rule that a new module never
changes them; and some, such as a hosted zone id, are not known when the
foundations are applied.

**Decision.** The boundary names services: `<service>:*` for each entry of
the client's `crossplane.allowed_services`, empty by default, and always a
deny of `iam`, `sts`, `organizations`, `account`, `sso` and `identitystore`
(statement `NeverIdentityNorAccount`), which the list also refuses at plan.
Which resources of a service a module reaches is that module's own role
policy.

**Consequences.** A module that uses a service already allowed needs no
foundations change; one that uses a new service needs one word in the
client's tfvars, a reviewed change to what the cluster may ever touch. An
empty list makes every module role grant nothing. The boundary is a ceiling
for the cluster, not a scope for a module: each module scopes its own policy
to its record names ([EXTERNAL-DNS-01](external-dns.md#external-dns-01-route-53-writes-scoped-by-record-name)),
prefixes ([EXTERNAL-SECRETS-01](external-secrets.md#external-secrets-01-the-name-prefix-is-the-boundary))
or actions ([KEDA-01](keda.md#keda-01-the-operators-role-scoped-per-aws-service)).
Because `sts` is denied, no module role can assume another role: per-workload
roles assumed by an operator are impossible.

**Sources.** AWS IAM permissions boundaries;
`opentofu/aws/tests/defaults.tftest.hcl` asserts the boundary's properties on
the planned documents.

## CROSSPLANE-02: Raw managed resources in each module, not a shared XRD

**accepted** · 2026-09-24 · [`oci/catalog/crossplane/resourceset.yaml`](../../oci/catalog/crossplane/resourceset.yaml), [`oci/catalog/external-dns/resourceset.yaml`](../../oci/catalog/external-dns/resourceset.yaml)

**Context.** A module's cloud access could be a Composition and an XRD owned
by the crossplane module, which each module would instantiate, or the raw
managed resources (`iam.aws.m.upbound.io` `Role`,
`eks.aws.m.upbound.io` `PodIdentityAssociation`) in the module's own
template.

**Decision.** Each module declares its raw managed resources, in its own
ResourceSet, under one branch per cloud. The crossplane module installs
Crossplane, the providers and the `ClusterProviderConfig`, and no XRD, no
Composition, no function.

**Consequences.** A module's whole cloud surface sits in its own file and is
reviewed with it; adding a module never changes the crossplane module. The
cost is about twenty lines of YAML per module per cloud, kept uniform by the
contract in [Module-owned cloud access](../architecture/module-iam.md). A
cloud without a branch simply has no role.

**Sources.** Crossplane v2 namespaced managed resources; the
`provider-upjet-aws` v2.8.1 CRDs.

## CROSSPLANE-03: Off by default

**accepted** · 2026-09-24 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf)

**Context.** On aws, Crossplane with its providers measured about 1.1 GB of
memory idle and about 2 GB just after install. Its identity in the
foundations, `aws.crossplane`, is itself opt-in: without it the providers
run with no credential. No module on by default needs cloud access.

**Decision.** `kube.crossplane.enabled` defaults to `false`. A module that
needs Crossplane says so at plan, in its own validation, rather than turning
it on as a hidden default.

**Consequences.** A cluster pays for Crossplane only when the client asks
for a module that uses it. The client writes two lines, `aws.crossplane` and
`kube.crossplane.enabled`, and the aws root warns when the second comes
without the first. Revisit when a module that needs cloud access becomes on
by default.

**Sources.** The memory measured on the module page.

## CROSSPLANE-04: Upstream chart repositories and package tags, unverified

**proposed** · 2026-09-24 · [`oci/catalog/crossplane/resourceset.yaml`](../../oci/catalog/crossplane/resourceset.yaml), [`oci/catalog/external-dns/resourceset.yaml`](../../oci/catalog/external-dns/resourceset.yaml), [`oci/catalog/keda/resourceset.yaml`](../../oci/catalog/keda/resourceset.yaml)

**Context.** Crossplane, external-dns and KEDA publish their charts only to
HTTPS Helm repositories: no OCI chart exists upstream
(`registry.k8s.io` serves only the external-dns image; `ghcr.io/kedacore/charts/keda`
refuses an anonymous pull). Crossplane's providers are pulled from
`xpkg.crossplane.io` by tag. Flux verifies none of these, where the other
modules' OCI charts could be verified and the socle's own artifact is.

**Decision.** Proposed: accept the three `HelmRepository` sources, pinned to
an exact chart version, and the provider packages pinned by tag, rather than
mirror them into the socle's registry.

**Consequences.** No mirroring pipeline to run. A compromised upstream
repository or a moved tag would reach every cluster on its next reconcile.
The alternative is a mirror into the socle's registry, signed with the
artifact, or the packages pinned by digest.

**Sources.** The charts' upstream publication; Flux `HelmRepository` and
`OCIRepository` verification.
