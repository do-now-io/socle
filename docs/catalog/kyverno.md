---
title: kyverno
description: The Kyverno admission engine, with no policy, failing open and never judging the socle's namespaces.
category: security
requires: []
---

Kyverno is the admission engine that refuses a privileged pod or an image from
any registry, with policies in YAML and CEL. This module is the engine alone:
the socle's policies are [kyverno-policies](kyverno-policies.md). **Off by
default**, on every cloud: an admission webhook is something you opt into.

## Getting started

Turn the engine on, with [kyverno-policies](kyverno-policies.md) for the
socle's policy set:

```hcl kube-start="kyverno"
kube = {
  kyverno = {
    enabled = true
  }
  kyverno_policies = { enabled = true } # the socle's policy set
}
```

Then `kubectl -n kyverno get deploy` shows three admission replicas Available.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on or off. Off removes the engine, its webhooks and its CRDs. |
| `values` | `{}` | Any [`kyverno` chart](https://artifacthub.io/packages/helm/kyverno/kyverno) value; yours win. |
| `values_secret` | `""` | A Secret in `kyverno` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl kube-full="kyverno"
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

## Good to know

- **Kyverno down blocks nothing of the socle's.** Its webhooks fail open,
  and a policy switched to Enforce in kyverno-policies runs as a native
  `ValidatingAdmissionPolicy`. A policy of your own follows the
  `failurePolicy` you give it.
- **It never judges the socle's namespaces**: `kube-system`, `flux-system`
  and every namespace a `flux-system` ResourceSet renders. A
  `config.webhooks.namespaceSelector` in `values` replaces that whole: keep
  them in it.
- **On GCP, nor GKE's own namespaces**: `kube-node-lease`,
  `gke-managed-system`, `gke-managed-cim`, `gke-managed-filestorecsi`,
  `gke-managed-networking-dra-driver`, `gke-managed-parallelstorecsi`,
  `gke-managed-volumepopulator`, `gke-gmp-system`, `gmp-system` and
  `gmp-public`. A selector of your own on GCP keeps these too.
- **Turning it off removes every Kyverno policy**, yours included, since the
  CRDs go with it. Set `crds.annotations` to keep them, as above.
- **Turn `kyverno_policies` off first**: `tofu plan` refuses it on with
  `kyverno` off. It also refuses credentials in `values`.
- **Three admission replicas** need room for three pods; lower
  `admissionController.replicas` in `values` on a dev cluster. Upgrades: the
  chart moves with `socle_version`.

<details>
<summary>Under the hood</summary>

**Installed**: chart `kyverno` 3.9.1 (Kyverno v1.19.1) from
`oci://ghcr.io/kyverno/charts/kyverno`, in the `kyverno` namespace.

**What the socle sets**: three admission replicas with a PodDisruptionBudget,
one background and one reports controller, no cleanup controller,
requests with no limits, scrape annotations and the chart's Grafana
dashboard. Your `values` are merged over these.

**Requests**: every container states CPU, memory and ephemeral storage, the
init container and the chart's three hooks (CRD migration, webhook removal,
scale to zero) included: 64Mi of disk for a controller, 32Mi for an init
container or a hook, for logs and a small sigstore cache. On GKE Autopilot a
container that states no disk gets 1Gi reserved and billed. The same on every
cloud; the chart's own limits on the init container and the hooks stay.

**On GCP**: the webhooks' `namespaceSelector` also names GKE's namespaces,
through the cloud's `kyverno-cloud-values` (from
[`oci/clusters/gcp/kyverno/patch.yaml`](../../oci/clusters/gcp/kyverno/patch.yaml)).
GKE rewrites a mutating webhook that reaches its managed namespaces, and
Kyverno would rewrite it back on every reconcile; leases in `kube-node-lease`
are the nodes' heartbeat. A selector matches no prefix, so each is named: the
list is what `kubectl get ns` showed on a 1.35 Autopilot cluster of the
sandbox (2026-10-07), plus `gke-managed-cim` and `gmp-system`, which GKE
documents. A namespace a later GKE version adds is not excluded until it
joins the list.

**Cloud access**: none.

**Ordering**: [kyverno-policies](kyverno-policies.md) requires this module.

**Measured** on floci, GitHub runner, 2026-10-01: three admission replicas
Ready in 52 s; off, uninstalled in 16 s.

</details>
