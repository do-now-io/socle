---
title: kyverno decisions
description: The decisions behind the kyverno module, one per section, each with its status.
sidebar:
  order: 10
---

The kyverno module is the socle's admission engine. An admission webhook that
is down must never block the cluster: the engine fails open and Enforce runs
without it. The policies are the kyverno-policies module's.

## KYVERNO-01: Engine and policies, two modules, failing open

**accepted** · 2026-10-01 · [`oci/catalog/kyverno/resourceset.yaml`](../../oci/catalog/kyverno/resourceset.yaml), [`oci/catalog/kyverno-policies/resourceset.yaml`](../../oci/catalog/kyverno-policies/resourceset.yaml)

**Decision.** Two modules: `kyverno`, the engine with no policy, and
`kyverno_policies`, refused at plan without it. The webhooks never see
`kube-system`, `flux-system` or a socle namespace; Audit goes through the
webhook with `failurePolicy: Ignore`, Enforce is a native `ValidatingAdmissionPolicy`.

**Context.** A webhook that is down can block every apply, Flux's included,
and a client may want the engine without the socle's policies.

**Consequences.** Kyverno down admits Audit and still refuses Enforce: on k3s
1.34 with the admission controller at zero, Flux scaled podinfo in 6 s and a
privileged pod was refused. The policies must be turned off before the engine.

**Sources.** Kyverno 1.19 CEL policies and ValidatingAdmissionPolicy generation; Kubernetes ValidatingAdmissionPolicy.

## KYVERNO-02: No cleanup controller

**accepted** · 2026-10-01 · [`oci/catalog/kyverno/resourceset.yaml`](../../oci/catalog/kyverno/resourceset.yaml)

**Decision.** `cleanupController.enabled: false`.

**Context.** Kyverno registers its webhook configurations with no owner
reference, and the chart's `pre-delete` hook races the controllers that
re-register them. Measured on floci on 2026-10-01: the cleanup controller's
configuration survived the uninstall, with no server and `failurePolicy: Fail`.
The socle ships no `CleanupPolicy`, `DeletingPolicy` or TTL label it would serve.

**Consequences.** The off path leaves no webhook configuration and no Kyverno
CRD; the module's test asserts it. A client who turns TTL cleanup on in
`values` accepts that an off may leave that one configuration.

**Sources.** The kyverno chart 3.9.1 `pre-delete` hooks; the floci measurement.

## KYVERNO-03: Kyverno, not OPA Gatekeeper

**accepted** · 2026-10-01 · [`oci/catalog/kyverno/resourceset.yaml`](../../oci/catalog/kyverno/resourceset.yaml)

**Decision.** Kyverno is the socle's admission engine.

**Context.** Gatekeeper's policies are Rego, its mutation a younger separate
API, and image verification needs an external provider. Kyverno's are YAML
and CEL, the CEL of Kubernetes' own `ValidatingAdmissionPolicy`.

**Consequences.** Enforce runs natively in the API server (KYVERNO-01), and
Kyverno mutates, generates and verifies cosign signatures alone. Chainsaw
comes from the same project. The cost is a `PolicyReport` per evaluated
resource in etcd.

**Sources.** Kyverno and OPA Gatekeeper documentation.
