---
title: kyverno decisions
description: The decisions behind the kyverno module, one per section, each with its status.
sidebar:
  order: 10
---

The kyverno module is the socle's admission engine. The decision to know
first: an admission webhook that is down must never block the cluster, so
the engine fails open and Enforce runs without it. The policies themselves
are the kyverno-policies module's.

## KYVERNO-01: Engine and policies, two modules, failing open

**accepted** · 2026-10-01 · [`oci/catalog/kyverno/resourceset.yaml`](../../oci/catalog/kyverno/resourceset.yaml), [`oci/catalog/kyverno-policies/resourceset.yaml`](../../oci/catalog/kyverno-policies/resourceset.yaml)

**Context.** An admission webhook that is down can block every apply in the
cluster, Flux's included. A client may want the engine with his own
policies, without the socle's. Kyverno compiles a CEL policy into a native
`ValidatingAdmissionPolicy`, which the API server evaluates in process.

**Decision.** Two modules: `kyverno`, the engine with no policy, and
`kyverno_policies`, the socle's set, refused at plan without the engine.
Kyverno's webhooks never see `kube-system`, `flux-system` or any namespace
the socle renders. Policies in Audit go through Kyverno's webhook with
`failurePolicy: Ignore`; a policy the client enforces is compiled into a
native `ValidatingAdmissionPolicy`.

**Consequences.** Kyverno down admits everything in Audit and still refuses
what is in Enforce; neither Flux nor a socle component waits on Kyverno.
Measured on k3s 1.34 with the admission controller scaled to zero: Flux
scaled podinfo in 6 s, a privileged pod was refused under Enforce. The
policies must be turned off before the engine.

**Sources.** Kyverno 1.19 CEL policies and ValidatingAdmissionPolicy
generation; Kubernetes ValidatingAdmissionPolicy.

## KYVERNO-02: No cleanup controller

**accepted** · 2026-10-01 · [`oci/catalog/kyverno/resourceset.yaml`](../../oci/catalog/kyverno/resourceset.yaml)

**Context.** Kyverno registers its webhook configurations itself, with no
owner reference, so Kubernetes' garbage collector never removes them. The
chart removes them in a `pre-delete` hook, which races the controllers it
cleans up after: every Kyverno controller re-registers its configuration
when it disappears. Measured on floci on 2026-10-01: the module turned off at 13:56:26,
`kyverno-cleanup-validating-webhook-cfg` recreated at 13:56:28, the release
uninstalled at 13:56:42, and the configuration still there five minutes
later, with no server behind it and `failurePolicy: Fail`.
The cleanup controller serves only `CleanupPolicy`, `DeletingPolicy` and the
`cleanup.kyverno.io/ttl` label; the socle ships none.

**Decision.** `cleanupController.enabled: false`.

**Consequences.** The off path leaves no webhook configuration and no
Kyverno CRD; the module's test asserts it every run. A client who wants TTL
cleanup turns it on in `values` and accepts that an off may leave that one
configuration, whose rules match only kinds whose CRDs are gone.

**Sources.** The kyverno chart 3.9.1 `pre-delete` hooks; the floci
measurement above.

## KYVERNO-03: Kyverno, not OPA Gatekeeper

**accepted** · 2026-10-01 · [`oci/catalog/kyverno/resourceset.yaml`](../../oci/catalog/kyverno/resourceset.yaml)

**Context.** Gatekeeper's policies are Rego, a language of its own; its
mutation is a separate, younger API; image signature verification needs an
external provider. Kyverno's policies are YAML and CEL, the same CEL as
Kubernetes' own `ValidatingAdmissionPolicy`.

**Decision.** Kyverno is the socle's admission engine.

**Consequences.** An Enforce policy can run natively in the API server
(KYVERNO-01). Kyverno mutates, generates and verifies cosign signatures with
no other component. Chainsaw, the socle's e2e runner, comes from the same
project. The cost is a `PolicyReport` per evaluated resource in etcd.

**Sources.** Kyverno and OPA Gatekeeper documentation.
