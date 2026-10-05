---
title: kyverno-policies decisions
description: The decisions behind the kyverno-policies module, one per section, each with its status.
sidebar:
  order: 10
---

The decisions behind the socle's policy set on the Kyverno engine. The two to
know first: an enforced policy is a native `ValidatingAdmissionPolicy`, so
nothing depends on Kyverno being up
([KYVERNO-POLICIES-01](#kyverno-policies-01-enforce-is-a-native-validatingadmissionpolicy-audit-goes-through-an-ignore-webhook)),
and the policies judge the client's namespaces only, never the socle's
([KYVERNO-POLICIES-03](#kyverno-policies-03-the-clients-namespaces-only)). The
module page is [kyverno-policies](../catalog/kyverno-policies.md); the engine's
decisions are in [kyverno decisions](kyverno.md).

## KYVERNO-POLICIES-01: Enforce is a native ValidatingAdmissionPolicy, Audit goes through an Ignore webhook

**accepted** · 2026-10-01 · [`oci/catalog/kyverno-policies/resourceset.yaml`](../../oci/catalog/kyverno-policies/resourceset.yaml)

**Context.** An admission webhook that refuses while its controller is down
blocks every pod of the cluster, the socle's own included. One that admits
while it is down turns an Enforce policy into a policy that holds only when
Kyverno is healthy. Kyverno 1.19 can compile a `ValidatingPolicy` into a
native `ValidatingAdmissionPolicy` and its binding, which the API server
evaluates itself, with no webhook in the path.

**Decision.** Every policy is in Audit, through Kyverno's webhook with
`failurePolicy: Ignore`. A policy the client names in
`kube.kyverno_policies.enforce` is switched to `Deny` and compiled into a
native `ValidatingAdmissionPolicy` (`spec.autogen.validatingAdmissionPolicy.enabled`,
patched by the `HelmRelease`'s post-renderer).

**Consequences.** Kyverno down admits what is in Audit, which refuses nothing
anyway, and changes nothing for what is enforced. Nothing else in the cluster
depends on Kyverno being up. The refusal starts a few seconds after the
binding appears, while the API server's admission plugin loads it. A client
who writes `validationFailureActionByPolicy` in `values` gets a webhook `Deny`
that fails open; `enforce` is the supported switch.

**Sources.** Kyverno 1.19 `ValidatingPolicy` autogen; Kubernetes
`ValidatingAdmissionPolicy` (GA in 1.30); measured on floci and a local k3s,
2026-10-01 ([Measured](../catalog/kyverno-policies.md#measured)).

## KYVERNO-POLICIES-02: Pods only, the autogen off from the first install

**accepted** · 2026-10-01 · [`oci/catalog/kyverno-policies/resourceset.yaml`](../../oci/catalog/kyverno-policies/resourceset.yaml)

**Context.** Kyverno's pod-controller autogen makes each Pod policy also
match Deployments, StatefulSets, Jobs and the other pod controllers. Two facts
of Kyverno 1.19.1, measured: it generates no `ValidatingAdmissionPolicy`
while that autogen is on (its status reads `skip generating
ValidatingAdmissionPolicy: pod controllers autogen is enabled`), and it
decides once, on the status it reads at that moment. A policy created with
the autogen on and switched off later kept that message until its spec
changed again; the switch applied by a Helm upgrade never took.

**Decision.** Every policy matches Pods only: the post-renderer sets
`spec.autogen.podControllers.controllers: [none]` on every `ValidatingPolicy`,
from its first install.

**Consequences.** The Enforce switch always takes, in seconds. A violation is
reported on the Pod, and an enforced one refused at the Pod: a Deployment
whose template violates it is admitted, and its ReplicaSet reports
`FailedCreate`. A client sees the refusal in the ReplicaSet's events, not in
the answer to his `kubectl apply`.

**Sources.** Measured on a local k3s 1.34.1 and on floci, 2026-10-01.

## KYVERNO-POLICIES-03: The client's namespaces only

**accepted** · 2026-10-02 · [`oci/catalog/kyverno-policies/resourceset.yaml`](../../oci/catalog/kyverno-policies/resourceset.yaml)

**Context.** The policies exist to judge what the client deploys. The socle's
own charts are not his to change: under `restricted`, the first floci run
reported `hello`, `otel-gateway`, `victoria-metrics`, `otel-agent` and
`victoria-logs`, and enforcing a policy could have refused their pods.
flux-operator labels every namespace a ResourceSet renders with
`resourceset.fluxcd.controlplane.io/namespace`, the ResourceSet's own
namespace: `flux-system` for every socle module.

**Decision.** Two exclusions on every policy: a `namespaceSelector` refusing
that label's value `flux-system`, added by the post-renderer, which Kyverno
copies into the native policy; and `kube-system`, `flux-system` and `kyverno`
by name, through the chart's `vpolExclude`, since nothing labels them.

**Consequences.** A new socle module is out of scope with nothing to add
here. The exclusion holds in admission, in the native policy and in the
background scans alike. The client's third-party charts live in his
namespaces and are judged like his applications; he exempts them through
`values.vpolExclude`. The socle's own modules still deserve to pass
`restricted`, as hygiene.

**Sources.** Measured on a local k3s 1.34: in a namespace labelled as the
socle's, a privileged pod admitted and not reported, in Audit and in Enforce,
Kyverno up or down; in an application namespace, reported in Audit and
refused in Enforce.

## KYVERNO-POLICIES-04: A module of its own, validate only

**accepted** · 2026-10-01 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf)

**Context.** The engine and the policies could ship as one module. A client
may want the engine without the socle's policies, and the module contract
gives one `values` per chart release. Kyverno can also mutate and generate
resources.

**Decision.** `kyverno_policies` is a module of its own, on the `kyverno`
module's engine, refused at plan without it. It validates only: no mutation,
no generation, no `verifyImages`, no namespaced policy.

**Consequences.** The policies have their own `values` and their own switch.
Nothing the client wrote is changed by the socle: a default that mutates (a
`seccompProfile`, a default request) would be. A client who wants mutation,
image verification or per-namespace rules writes his own policies, in his
GitOps.

**Sources.** The catalog module contract
([architecture/flux-catalog.md](../architecture/flux-catalog.md)).
