---
title: crossplane decisions
description: The decisions behind the crossplane module, one per section, each with its status.
sidebar:
  order: 10
---

The crossplane module is the tooling behind each module owning its cloud
access ([SOCLE-04](socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)):
a boundary that names services, raw managed resources per module, off by default.

## CROSSPLANE-01: The boundary is an allowlist of services

**accepted** · 2026-09-24 · [`opentofu/aws/iam.tf`](../../opentofu/aws/iam.tf), [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf)

**Decision.** The boundary grants `<service>:*` for each entry of
`crossplane.allowed_services` (empty by default) and always denies `iam`,
`sts`, `organizations`, `account`, `sso` and `identitystore`
(`NeverIdentityNorAccount`), also refused at plan.

**Context.** The boundary is the foundations'
([AWS-18](aws.md#aws-18-crossplanes-identity-and-its-permissions-boundary-in-the-foundations)).
Naming resources would put each module's needs into the foundations, and
some, such as a hosted zone id, are unknown when they are applied.

**Consequences.** A new service is one word in the client's tfvars; an empty
list makes every module role grant nothing. Each module scopes its own policy
([EXTERNAL-DNS-01](external-dns.md#external-dns-01-route-53-writes-scoped-by-record-name),
[EXTERNAL-SECRETS-01](external-secrets.md#external-secrets-01-the-name-prefix-is-the-boundary),
[KEDA-01](keda.md#keda-01-the-operators-role-scoped-per-aws-service)).
With `sts` denied, no module role can assume another role.

**Sources.** AWS IAM permissions boundaries; `opentofu/aws/tests/defaults.tftest.hcl`.

## CROSSPLANE-02: Raw managed resources in each module, not a shared XRD

**accepted** · 2026-09-24 · [`oci/catalog/crossplane/resourceset.yaml`](../../oci/catalog/crossplane/resourceset.yaml), [`oci/catalog/external-dns/resourceset.yaml`](../../oci/catalog/external-dns/resourceset.yaml)

**Decision.** Each module declares its raw managed resources (`Role`,
`PodIdentityAssociation`) in its own ResourceSet, one branch per cloud. The
crossplane module installs Crossplane, the providers and the
`ClusterProviderConfig`; no XRD, Composition or function.

**Context.** The alternative was a Composition and XRD owned by the crossplane
module, instantiated by each module.

**Consequences.** A module's whole cloud surface is reviewed with it, and
adding a module never changes the crossplane module. The cost is about twenty
lines of YAML per module per cloud, kept uniform by
[Module-owned cloud access](../architecture/module-iam.md).

**Sources.** Crossplane v2 namespaced managed resources; `provider-upjet-aws` v2.8.1 CRDs.

## CROSSPLANE-03: Off by default

**accepted** · 2026-09-24 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf)

**Decision.** `kube.crossplane.enabled` defaults to `false`. A module that
needs Crossplane says so at plan, in its own validation.

**Context.** On aws, Crossplane with its providers measured about 1.1 GB of
memory idle, about 2 GB just after install. No module on by default needs
cloud access, and its identity `aws.crossplane` is itself opt-in.

**Consequences.** The client writes `aws.crossplane` and
`kube.crossplane.enabled`; the aws root warns when the second comes without
the first. Revisit when a module that needs cloud access is on by default.

**Sources.** The memory measured on the module page.

## CROSSPLANE-04: Upstream chart repositories and package tags, unverified

**proposed** · 2026-09-24 · [`oci/catalog/crossplane/resourceset.yaml`](../../oci/catalog/crossplane/resourceset.yaml), [`oci/catalog/external-dns/resourceset.yaml`](../../oci/catalog/external-dns/resourceset.yaml), [`oci/catalog/keda/resourceset.yaml`](../../oci/catalog/keda/resourceset.yaml)

**Decision.** Proposed: accept the crossplane, external-dns and KEDA
`HelmRepository` sources pinned to an exact chart version, and the provider
packages pinned by tag, rather than mirror them.

**Context.** These charts exist upstream only as HTTPS Helm repositories (no
anonymous OCI chart); providers come from `xpkg.crossplane.io` by tag. Flux
verifies none of them.

**Consequences.** No mirroring pipeline, but a compromised repository or a
moved tag reaches every cluster on its next reconcile. The alternative is a
signed mirror in the socle's registry, or packages pinned by digest.

**Sources.** The charts' upstream publication; Flux `HelmRepository` and `OCIRepository` verification.
