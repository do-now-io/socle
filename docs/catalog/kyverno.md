---
title: kyverno
description: The Kyverno admission engine, with no policy, failing open and never judging the socle's namespaces.
category: security
requires: []
---

Kyverno is the admission layer that refuses a privileged pod, an image from
any registry or a workload without requests, with policies in YAML and CEL.
This module is the engine alone, with no policy: the socle's set is
[kyverno-policies](kyverno-policies.md), and you may run your own instead. It
is **off by default**: an admission webhook on every cluster is something you
opt into.

## Getting started

Turn the engine on, and [kyverno-policies](kyverno-policies.md) with it for
the socle's policy set:

```hcl title="terraform.tfvars" kube-start="kyverno"
kube = {
  kyverno = {
    enabled = true
  }
  kyverno_policies = { enabled = true } # the socle's policy set
}
```

After the apply, `kubectl -n flux-system get resourceset kyverno` is Ready
and `kubectl -n kyverno get deploy` shows three admission replicas Available.

## What it installs

| | |
| --- | --- |
| Chart | `kyverno` `3.9.1` (Kyverno v1.19.1) from `oci://ghcr.io/kyverno/charts/kyverno` |
| Namespace | `kyverno` |
| Objects | `Namespace/kyverno`, `OCIRepository/kyverno-chart`, `ConfigMap/kyverno-socle-values`, `ConfigMap/kyverno-client-values`, `HelmRelease/kyverno` |

The socle's values:

| Value | Setting |
| --- | --- |
| `admissionController.replicas` | 3, spread by the chart's preferred anti-affinity, with a PodDisruptionBudget `minAvailable: 1` |
| `backgroundController.replicas`, `reportsController.replicas` | 1 each: they are leader-elected, a second replica is a standby |
| `cleanupController.enabled` | `false` ([KYVERNO-02](../decisions/kyverno.md#kyverno-02-no-cleanup-controller)) |
| Requests | admission container 100m / 128Mi, background and reports 50m / 64Mi. No limits |
| `config.webhooks.namespaceSelector` | excludes `kube-system`, `flux-system`, and every namespace labelled `resourceset.fluxcd.controlplane.io/namespace: flux-system` |
| `podAnnotations` | `prometheus.io/scrape` on port 8000, on every controller, for [otel-gateway](otel-gateway.md) |
| `grafana.enabled` | `true`: the chart's dashboard as a ConfigMap, loaded by [grafana](grafana.md) |

The chart's defaults stand for the rest: CRDs installed, policy and
admission reports on, background scans hourly, `policyExceptions` off.

**What Kyverno never sees.** flux-operator labels each namespace a
ResourceSet renders with `resourceset.fluxcd.controlplane.io/namespace`, the
ResourceSet's own namespace, `flux-system` for the socle's. Every webhook
Kyverno registers carries the selector above, and the chart excludes
`kyverno` on top. Whatever policy you write, neither Flux nor a socle
component waits on Kyverno. Namespaces rendered by a ResourceSet of yours in
`flux-system` are excluded too.

**When Kyverno is down.** The socle's policies in Audit go through
Kyverno's webhooks, registered with `failurePolicy: Ignore`: Kyverno down
admits, and an Audit policy refuses nothing anyway. A policy you switch to
Enforce in kyverno-policies is compiled into a native
`ValidatingAdmissionPolicy` that the API server evaluates itself, Kyverno up
or down
([KYVERNO-01](../decisions/kyverno.md#kyverno-01-engine-and-policies-two-modules-failing-open)).
With the socle's policies, Kyverno down blocks nothing. A policy of your own
follows the `failurePolicy` you give it.

## What you can set

Under `kube.kyverno` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on. `false` uninstalls the engine, its webhooks and its CRDs. |
| `values` | `{}` | Any `kyverno` chart value; yours win over the socle's ([SOCLE-06](../decisions/socle.md#socle-06-the-clients-values-win)). Lower `admissionController.replicas` here for a dev cluster. |
| `values_secret` | `""` | The name of a Secret you create in `kyverno`, with a `values.yaml` key, merged last. OpenTofu never reads it. |

A `config.webhooks.namespaceSelector` in `values` replaces the socle's
whole: keep `kube-system`, `flux-system` and the label expression in it.

Refused at plan:

- In `values`: `imagePullSecrets` with credentials (create the Secret
  yourself and name it in `existingImagePullSecrets`), and an
  `extraEnvVars` entry, on any controller or the admission init container,
  with a literal value whose name looks like a credential.
- `values_secret` that is not a valid Secret name.
- `kyverno_policies` on with `kyverno` off: turn `kyverno_policies` off
  first, then `kyverno`.

### Every setting

Every attribute, at its default, and how chart values and secrets go in:

```hcl title="terraform.tfvars" kube-full="kyverno"
kube = {
  kyverno = {
    enabled = false # off by default; false uninstalls the engine and its CRDs

    # Any value of the kyverno chart 3.9.1; yours win over the socle's.
    values = {
      crds = {
        annotations = { "helm.sh/resource-policy" = "keep" } # policies survive an off
      }
      features = {
        backgroundScan = { backgroundScanInterval = "30m" }
      }
    }

    # A Secret you create in kyverno, whose values.yaml key holds chart values
    # that must not reach the OpenTofu state, such as an extraEnvVars proxy
    # URL with a password in it.
    values_secret = "kyverno-values"
  }
}
```

## Per cloud

The same template on every cloud, with no overlay patch.

## Cloud access

None.

## Ordering

No requirement. [kyverno-policies](kyverno-policies.md) requires this module.

## Upgrade notes

The CRDs go with the release: turning the module off removes every Kyverno
policy in the cluster, yours included. To keep your policies across an
off/on, set `crds.annotations` in `values`. The off path leaves no webhook
configuration behind: the chart's `pre-delete` hook removes them, and with
no cleanup controller nothing re-registers one. If you turn
`cleanupController.enabled` on, an off may leave its one configuration,
whose rules match only Kyverno's cleanup kinds; a later install takes it
back.

Reports: Kyverno writes a `PolicyReport` per resource it evaluates, in the
resource's namespace, kept in etcd. A cluster whose reports outgrow it moves
them to the chart's `reports-server` through `values`.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-10-01 | local k3s 1.34.1, flux-operator 0.60.0, through Flux | kyverno and kyverno-policies installed to Ready in 96 s; at rest, admission 26–109m CPU and 48–59Mi per replica, background and reports 16–24m and 51–56Mi; off, the release uninstalled in 38 s; a Pod's report 21 s after admission |
| 2026-10-01 | local k3s, Kyverno's admission scaled to zero | Flux scaled podinfo from 1 to 2 replicas in 6 s; a pod without requests admitted (Audit); a privileged pod refused by `vpol-disallow-privileged-containers` (Enforce) |
| 2026-10-01 | floci, GitHub `ubuntu-latest` runner | On, three admission replicas Ready in 52 s; off, the release uninstalled in 16 s |

Its decisions: [kyverno decisions](../decisions/kyverno.md).
