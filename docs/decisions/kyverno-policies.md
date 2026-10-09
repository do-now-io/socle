---
title: kyverno-policies decisions
description: The decisions behind the kyverno-policies module, one per section, each with its status.
sidebar:
  order: 10
---

The socle's policy set on the Kyverno engine: enforced policies are native,
so nothing depends on Kyverno being up, and they judge only the client's
namespaces. Module page: [kyverno-policies](../catalog/kyverno-policies.md); engine: [kyverno decisions](kyverno.md).

## KYVERNO-POLICIES-01: Enforce is a native ValidatingAdmissionPolicy, Audit goes through an Ignore webhook

**accepted** · 2026-10-01 · [`oci/catalog/kyverno-policies/resourceset.yaml`](../../oci/catalog/kyverno-policies/resourceset.yaml)

**Decision.** Every policy is in Audit, through the webhook with
`failurePolicy: Ignore`. A policy named in `kube.kyverno_policies.enforce` is
switched to `Deny` and compiled into a native `ValidatingAdmissionPolicy`,
patched by the `HelmRelease`'s post-renderer.

**Context.** A webhook that refuses while down blocks every pod; one that
admits while down makes Enforce hold only when Kyverno is healthy. A native
policy is evaluated by the API server itself.

**Consequences.** Nothing in the cluster depends on Kyverno being up. Refusal
starts a few seconds after the binding appears. `validationFailureActionByPolicy`
in `values` gives a webhook `Deny` that fails open; `enforce` is the switch.

**Sources.** Kyverno 1.19 `ValidatingPolicy` autogen; Kubernetes `ValidatingAdmissionPolicy` (GA in 1.30); [Measured](../catalog/kyverno-policies.md), 2026-10-01.

## KYVERNO-POLICIES-02: Pods only, the autogen off from the first install

**accepted** · 2026-10-01 · [`oci/catalog/kyverno-policies/resourceset.yaml`](../../oci/catalog/kyverno-policies/resourceset.yaml)

**Decision.** Every policy matches Pods only: the post-renderer sets
`spec.autogen.podControllers.controllers: [none]` on every `ValidatingPolicy`
from its first install.

**Context.** Measured on Kyverno 1.19.1: it generates no native policy while
pod-controller autogen is on, and decides once; a switch applied later by a
Helm upgrade never took.

**Consequences.** The Enforce switch always takes, in seconds. A Deployment
whose template violates an enforced policy is admitted; the client sees the
refusal as `FailedCreate` in the ReplicaSet's events.

**Sources.** Measured on a local k3s 1.34.1 and on floci, 2026-10-01.

## KYVERNO-POLICIES-03: The client's namespaces only

**accepted** · 2026-10-02 · [`oci/catalog/kyverno-policies/resourceset.yaml`](../../oci/catalog/kyverno-policies/resourceset.yaml)

**Decision.** Every policy excludes namespaces labelled
`resourceset.fluxcd.controlplane.io/namespace: flux-system` (a
`namespaceSelector` from the post-renderer), and `kube-system`, `flux-system`
and `kyverno` by name through `vpolExclude`.

**Context.** The socle's charts are not the client's to change: the first
floci run under `restricted` reported five socle modules. flux-operator labels
every namespace a socle ResourceSet renders with that value.

**Consequences.** A new socle module is out of scope with nothing to add, in
admission and background scans alike. The client's third-party charts are
judged like his applications; he exempts them through `values.vpolExclude`.

**Sources.** Measured on a local k3s 1.34, in Audit and Enforce, Kyverno up or down.

## KYVERNO-POLICIES-04: A module of its own, validate only

**accepted** · 2026-10-01 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf)

**Decision.** `kyverno_policies` is a module of its own, refused at plan
without `kyverno`. It validates only: no mutation, no generation, no
`verifyImages`, no namespaced policy.

**Context.** A client may want the engine without the socle's policies, and
the module contract gives one `values` per chart release.

**Consequences.** The policies have their own `values` and switch, and the
socle changes nothing the client wrote. Mutation, image verification or
per-namespace rules are the client's own policies, in his GitOps.

**Sources.** The catalog module contract ([architecture/flux-catalog.md](../architecture/flux-catalog.md)).
