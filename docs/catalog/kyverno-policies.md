---
title: kyverno-policies
description: The socle's baseline Pod Security and image policies, in Audit, any of them enforceable natively.
category: security
requires:
  - module: kyverno
    why: its policies are the engine's resources; refused at plan without it
---

The socle's policy set on the [kyverno](kyverno.md) engine: the Pod Security
Standards, CPU and memory requests required, the `latest` tag refused, and
your allowed registries when you name them. Every policy reports and refuses
nothing until you switch it to Enforce. **Off by default**, on every cloud.

## Getting started

Turn it on with the kyverno engine it needs, and name your registries:

```hcl kube-start="kyverno_policies"
kube = {
  kyverno = { enabled = true }
  kyverno_policies = {
    enabled            = true
    profile            = "baseline"
    allowed_registries = ["ghcr.io/acme", "registry.k8s.io"]
  }
}
```

Then `kubectl get policyreports -A` shows what each of your namespaces
violates.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on or off. Needs `kube.kyverno.enabled = true`. |
| `profile` | `"baseline"` | The Pod Security profile: `baseline`, or `restricted` (baseline plus six). |
| `enforce` | `[]` | The policies switched to Enforce, each compiled into a native admission policy. |
| `allowed_registries` | `[]` | Registry hosts, with an optional port and path (`ghcr.io/acme`). Adds `restrict-image-registries`. |
| `values` | `{}` | Any [`kyverno-policies` chart](https://artifacthub.io/packages/helm/kyverno/kyverno-policies) value; yours win. |
| `values_secret` | `""` | A Secret in `kyverno-policies` with a `values.yaml` key, merged last. |

### Every setting

```hcl kube-full="kyverno_policies"
kube = {
  kyverno_policies = {
    enabled            = false      # off by default; needs kube.kyverno.enabled = true
    profile            = "baseline" # baseline, or restricted (baseline plus six)
    enforce            = []         # policies switched to Enforce, each made native
    allowed_registries = []         # registry hosts, optionally a path; adds restrict-image-registries

    # Any value of the kyverno-policies chart 3.9.1; yours win over the socle's.
    values = {
      podSecuritySeverity = "high"
      vpolExclude = {
        # Replaces the socle's list: keep its three names.
        excludeNamespaces = ["kube-system", "flux-system", "kyverno", "ingress-nginx"]
      }
    }

    # A Secret you create in kyverno-policies, whose values.yaml key holds chart
    # values kept out of the OpenTofu state; merged last.
    values_secret = "kyverno-policies-values"
  }
}
```

## Good to know

- **An enforced policy refuses with Kyverno up or down**: the API server
  evaluates it natively. In Audit, a violation is admitted and reported, and
  Kyverno down admits everything.
- **Pods only, your namespaces only**: a Deployment whose template violates
  an enforced policy is admitted and its ReplicaSet reports `FailedCreate`.
  The socle's namespaces, `kube-system`, `flux-system` and `kyverno` are out.
- **`tofu plan` refuses** the module without `kyverno`, an unknown
  `profile`, an `enforce` name this configuration does not render (a
  restricted policy under `baseline`, `restrict-image-registries` without
  registries), and a malformed registry.
- **Lists in `values` replace the socle's**: `vpolExclude.excludeNamespaces`
  drops its three names, so keep them. Do not set
  `validationFailureActionByPolicy`: it enforces through the webhook, which
  admits while Kyverno is down; use `enforce`.
- **Your third-party charts are judged like your applications**: exempt one
  through `values.vpolExclude`.
- **Upgrades**: the names `enforce` accepts are those of the chart version,
  listed in [`catalog.tf`](../../opentofu/bootstrap/catalog.tf); a chart
  upgrade may add or rename one.

<details>
<summary>Under the hood</summary>

**Installed**: chart `kyverno-policies` 3.9.1 (Kyverno 1.19.1) from
`oci://ghcr.io/kyverno/charts`, in the `kyverno-policies` namespace, as CEL
`ValidatingPolicy` objects. An enforced policy becomes a native
`ValidatingAdmissionPolicy` `vpol-<name>` with its binding.

**What the socle sets**: the profile's policies, plus its own
`require-requests` and `disallow-latest-tag`, and `restrict-image-registries`
when you name registries, which reads `busybox:1.37` as
`docker.io/busybox:1.37`. The pod-controller autogen is off from the first
install, which native compilation needs.

**Cloud access**: none.

**Ordering**: the policies' `HelmRelease` `dependsOn` the engine's, so they
install after it.

**Measured** on floci k3s, 2026-10-01: release Ready in 64 s; an enforced
policy refused a privileged pod with Kyverno's admission scaled to 0. A
refusal starts a few seconds after the native binding appears.

</details>
