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
  The socle's namespaces, `kube-system`, `flux-system` and `kyverno` are out;
  on GCP, GKE's own namespaces too, the [kyverno](kyverno.md) module's list.
- **`tofu plan` refuses** the module without `kyverno`, an unknown
  `profile`, an `enforce` name this configuration does not render (a
  restricted policy under `baseline`, `restrict-image-registries` without
  registries), and a malformed registry.
- **Lists in `values` replace the socle's**: `vpolExclude.excludeNamespaces`
  drops its three names, and on GCP GKE's, so keep them. Do not set
  `validationFailureActionByPolicy`: it enforces through the webhook, which
  admits while Kyverno is down; use `enforce`.
- **Your third-party charts are judged like your applications**: exempt one
  through `values.vpolExclude`.
- **On GKE Autopilot, GKE refuses privileged pods first**: its own admission
  (Warden) denies a privileged container before Kyverno sees it, so the
  privileged policies only ever report pods Autopilot already blocks. They
  stay in the set, the same on every cloud.
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

**On GCP**: `vpolExclude.excludeNamespaces` also names GKE's namespaces,
through the cloud's `kyverno-policies-cloud-values` (from
[`oci/clusters/gcp/kyverno-policies/patch.yaml`](../../oci/clusters/gcp/kyverno-policies/patch.yaml)).
GKE keeps mutating webhooks out of them, not a native
`ValidatingAdmissionPolicy`, so an enforced policy could otherwise refuse a
pod GKE runs there. Measured on the sandbox, Warden's refusal of a privileged
pod reads `admission webhook
"warden-validating.common-webhooks.networking.gke.io" denied the request ...
[denied by autogke-disallow-privilege] container pause is privileged; not
allowed in Autopilot`. The e2e on GKE (`kyverno-policies-module-gke`) runs
the floci test's steps on a violation Autopilot admits: a pod mounting the
node's `/var/log` read-only, the one `hostPath` Autopilot allows, which
`disallow-host-path` reports in Audit and refuses once enforced.

**Measured** on floci k3s, 2026-10-01: release Ready in 64 s; an enforced
policy refused a privileged pod with Kyverno's admission scaled to 0. A
refusal starts a few seconds after the native binding appears. On GKE
Autopilot (sandbox, 2026-10-07): the baseline set converged in Audit;
`enforce = ["disallow-host-path"]` compiled into a native policy that denied
the `hostPath` pod; a pod in an excluded namespace was admitted. On
2026-10-16 (artifact `0.0.0-feat-gcp-parity.d896756`), `kyverno-policies-module-gke` passed in full
(389 s), the `PolicyReport` of the Audit step included.

</details>
