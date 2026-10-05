---
title: kyverno-policies
description: The socle's baseline Pod Security and image policies, in Audit, any of them enforceable natively.
category: security
requires:
  - module: kyverno
    why: its policies are the engine's resources; refused at plan without it
---

The socle's policy set on the [kyverno](kyverno.md) engine: the Pod Security
Standards, CPU and memory requests required, the `latest` tag refused, and,
when you name them, your allowed registries. Every policy reports and refuses
nothing until you switch it to Enforce, one by one. Off by default.

## Getting started

Turn it on with the kyverno engine it needs. Every policy starts in Audit:
name your registries now, and switch policies to Enforce once their reports
are clean.

```hcl title="terraform.tfvars" kube-start="kyverno_policies"
kube = {
  kyverno = { enabled = true }
  kyverno_policies = {
    enabled            = true
    profile            = "baseline"
    allowed_registries = ["ghcr.io/acme", "registry.k8s.io"]
  }
}
```

After apply, `kubectl get validatingpolicies` lists the policies, and
`kubectl get policyreports -A` shows what each of your namespaces violates.

## What it installs

| | |
| --- | --- |
| Chart | `kyverno-policies` `3.9.1` (Kyverno 1.19.1) from `oci://ghcr.io/kyverno/charts` |
| Namespace | `kyverno-policies` |
| Objects | the namespace, the chart source, the socle's and your values ConfigMaps, one `HelmRelease`; the chart renders the policies as CEL `ValidatingPolicy` objects (`policies.kyverno.io`) |

The policies, by what turns them on:

| Set | Policies |
| --- | --- |
| `profile = "baseline"` (default) | `disallow-capabilities`, `disallow-host-namespaces`, `disallow-host-path`, `disallow-host-ports`, `disallow-host-process`, `disallow-privileged-containers`, `disallow-proc-mount`, `disallow-selinux`, `restrict-apparmor-profiles`, `restrict-seccomp`, `restrict-sysctls` |
| `profile = "restricted"` | baseline, plus `disallow-capabilities-strict`, `disallow-privilege-escalation`, `require-run-as-non-root-user`, `require-run-as-nonroot`, `restrict-seccomp-strict`, `restrict-volume-types` |
| Always, the socle's | `require-requests`: every container requests CPU and memory. `disallow-latest-tag`: every image is pinned by a tag other than `latest`, or by a digest |
| `allowed_registries` not empty | `restrict-image-registries`: images from those registries only |

**What they judge.** Pods, and only Pods: a Deployment whose template
violates an enforced policy is admitted, and its ReplicaSet reports
`FailedCreate` in its events. Only your namespaces: every namespace the socle
renders is out of every policy, by the label flux-operator puts on it
(`resourceset.fluxcd.controlplane.io/namespace: flux-system`), and so are
`kube-system`, `flux-system` and `kyverno`, by name. The same exclusions hold
in admission, in an enforced policy and in the background scans.

**Audit.** A violation is admitted and reported in the namespace's
`PolicyReport`. Kyverno's webhook is registered with `failurePolicy: Ignore`:
Kyverno down admits.

**Enforce.** A policy you name in `enforce` is switched to `Deny` and Kyverno
compiles it into a native `ValidatingAdmissionPolicy`, `vpol-<name>`, with its
binding. The API server evaluates it itself, so it refuses with Kyverno up or
down. The refusal starts a few seconds after the binding appears, while the
API server loads it (see [Measured](#measured)).

**`restrict-image-registries`** reads an image as the runtime pulls it: a
first path segment without a dot, a port or `localhost` is a Docker Hub path,
so `busybox:1.37` is `docker.io/busybox:1.37`. It matches a registry followed
by a slash, so `ghcr.io` never admits `ghcr.io.evil.example`.

## What you can set

Under `kube.kyverno_policies` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on. Needs `kube.kyverno.enabled = true`. |
| `profile` | `"baseline"` | `baseline` or `restricted` (baseline plus six). |
| `enforce` | `[]` | The policies switched to Enforce, each made native. Only a name this configuration renders. |
| `allowed_registries` | `[]` | Registry hosts, optionally with a port and a path: `ghcr.io`, `registry.k8s.io`, `ghcr.io/acme`, `localhost:5000`. Adds `restrict-image-registries`. |
| `values` | `{}` | Any `kyverno-policies` chart value; yours win over the socle's. |
| `values_secret` | `""` | A Secret you create in `kyverno-policies` with a `values.yaml` key, merged last. |

```hcl
kube = {
  kyverno = { enabled = true }
  kyverno_policies = {
    enabled            = true
    enforce            = ["disallow-privileged-containers", "disallow-host-path"]
    allowed_registries = ["ghcr.io", "registry.k8s.io", "public.ecr.aws"]
  }
}
```

Refused at plan:

- `enabled = true` without `kube.kyverno.enabled = true`: the release would
  wait for the engine forever.
- A `profile` other than `baseline` or `restricted`.
- An `enforce` entry this configuration does not render: a restricted policy
  without `profile = "restricted"`, `restrict-image-registries` without an
  allow-list, any other name. It would be a switch that does nothing.
- An `allowed_registries` entry with a scheme, a trailing slash, a tag or
  uppercase letters.
- A `values_secret` that is not a Secret name. The chart carries no
  credential, so `values` itself has nothing refused.

Two things `values` can do that you may not want:

- **A list you set replaces the socle's whole list.** `customPolicies` drops
  the socle's two policies; `vpolExclude.excludeNamespaces` drops the three
  names above, so keep them in yours. The socle's namespaces stay out either
  way: their selector is not a chart value.
- **`validationFailureActionByPolicy` written in `values`** gives a `Deny`
  policy through Kyverno's webhook, which admits everything while Kyverno is
  down. Use `enforce`, which makes the policy native.

Your own third-party charts (an ingress controller, an operator) live in your
namespaces and are judged like your applications. Exempt one through
`values.vpolExclude`. Your own policies belong with your applications, in your
GitOps, not in `values.customPolicies`.

### Every setting

Every attribute, at its default, and how chart values and secrets go in:

```hcl title="terraform.tfvars" kube-full="kyverno_policies"
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

## Per cloud

The same on aws, gcp, azure and scaleway.

## Cloud access

None.

## Ordering

The plan refuses the module without `kyverno`. In the cluster, the policies'
`HelmRelease` `dependsOn` the engine's (`kyverno/kyverno`): the policies are
the engine's CRDs and the chart reads the engine's version off its
Deployment, so they install after it, never before. The ResourceSet itself has
no `dependsOn`: its namespace, source and values are applied at once, and the
release waits.

## Upgrade notes

- The policy names `enforce` may take are those of chart 3.9.1, listed in
  [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf). A
  chart upgrade that adds or renames a policy changes that list.
- The pod-controller autogen is off on every policy from its first install;
  Kyverno compiles a native policy only with it off, and decides once
  ([KYVERNO-POLICIES-02](../decisions/kyverno-policies.md#kyverno-policies-02-pods-only-the-autogen-off-from-the-first-install)).
  A policy you bring through `values.customPolicies` follows the same rule.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-10-01 | local k3s 1.34.1, flux-operator 0.60.0 | a privileged pod in Audit: admitted, `PolicyReport` fail 21 s later; `enforce` on it: native policy and binding in 6 s, the pod then refused |
| 2026-10-01 | floci, k3s, `kyverno` and `kyverno-policies` on | release Ready in 64 s; a privileged pod reported in 38 s; enforced, refused 2 s after the native policy compiled; Kyverno's admission scaled to 0, the enforced policy still refused the pod and a pod without requests (Audit) was admitted; the `restricted` background scan reported after 60 s |
| 2026-10-01 | floci, k3s | a pod created 3 s after the native binding appeared was admitted; on a later run, the first refusal came 4 s after the pod's creation |

Its decisions: [kyverno-policies decisions](../decisions/kyverno-policies.md).
