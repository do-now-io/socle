# Catalog module `kyverno_policies` — the socle's baseline policy set

Issue #57, the second half of the admission layer. The engine is
[`kyverno`](kyverno.md). This module is the policy set the socle owns and keeps
working. It is a module of its own so that a client can take the engine
without the socle's policies, and so that the policies get their own `values`
under the module contract. **Off by default**, and refused at plan without
`kyverno`.

| Question | Position |
| --- | --- |
| What | The official `kyverno-policies` chart, `oci://ghcr.io/kyverno/charts/kyverno-policies:3.9.1`, one `HelmRelease` in namespace `kyverno-policies`, installed after the engine (`dependsOn`) |
| Kind | CEL `ValidatingPolicy` (`policies.kyverno.io`), the chart's default and Kyverno's direction; the legacy `ClusterPolicy` is deprecated upstream |
| Default | **Off**; when on, the Pod Security Standards *baseline* profile plus the socle's two policies, every one in **Audit** |
| Enforce | Per policy, the client's switch: `enforce`. An enforced policy becomes a native `ValidatingAdmissionPolicy` |
| Excluded | `kube-system`, `flux-system`, `kyverno`, from every policy, in admission, natively and in background scans |
| Cloud access | None |
| Client surface | `enabled`, `profile`, `enforce`, `allowed_registries`, `values`, `values_secret` |

## What ships

**The Pod Security Standards**, from the chart, by `profile`:

| Profile | Policies |
| --- | --- |
| `baseline` (default) | `disallow-capabilities`, `disallow-host-namespaces`, `disallow-host-path`, `disallow-host-ports`, `disallow-host-process`, `disallow-privileged-containers`, `disallow-proc-mount`, `disallow-selinux`, `restrict-apparmor-profiles`, `restrict-seccomp`, `restrict-sysctls` |
| `restricted` | baseline, plus `disallow-capabilities-strict`, `disallow-privilege-escalation`, `require-run-as-non-root-user`, `require-run-as-nonroot`, `restrict-seccomp-strict`, `restrict-volume-types` |

**The socle's own**, written in the module as Helm templates inside its values
document. The chart passes `customPolicies` through `tpl`, so they read the
same `failurePolicy`, the same per-policy action and the same exclusions as
the chart's own:

| Policy | Rule |
| --- | --- |
| `require-requests` | Every container requests CPU and memory |
| `disallow-latest-tag` | Every image is pinned by a tag other than `latest`, or by a digest |
| `restrict-image-registries` | Rendered only when `allowed_registries` is not empty: images from those registries only |

`restrict-image-registries` names an image as the runtime pulls it. A first
path segment without a dot, a port or `localhost` is a Docker Hub path, so
`busybox:1.37` is `docker.io/busybox:1.37`. It matches a registry plus a
slash, so `ghcr.io` never admits `ghcr.io.evil.example`.

Every policy matches **Pods only**: the pod-controller autogen, which would
also match each Deployment, StatefulSet or Job, is off (see [Enforce](#enforce)
for why). A violation is reported on the Pod and, in Enforce, refused at the
Pod. A Deployment whose template violates an enforced policy is admitted, and
its ReplicaSet reports `FailedCreate` in its events.

## Audit

Every policy reports and refuses nothing. Its webhook is registered by Kyverno
with `failurePolicy: Ignore`, so Kyverno down admits. Measured on a local
k3s 1.34: a privileged pod is admitted, and its `PolicyReport` lists
`disallow-privileged-containers: fail` 21 s later.

## Enforce

`kube.kyverno_policies.enforce` names the policies the client switches to a
refusal. For each one, the module:

1. sets the chart's `validationFailureActionByPolicy` to `Enforce`, so the
   policy's `validationActions` become `[Deny]`;
2. patches the policy, through the `HelmRelease`'s Kustomize post-renderer,
   with `spec.autogen.validatingAdmissionPolicy.enabled: true`.

Kyverno then generates a `ValidatingAdmissionPolicy`
`vpol-<name>` and its binding, owned by the policy, and drops the policy from
its own webhook. **The API server evaluates it itself.** An enforced policy
holds with Kyverno down. Nothing else depends on Kyverno being up, which
answers the issue's failure-policy question
([kyverno.md](kyverno.md#failure-policy-what-happens-when-kyverno-is-down)).
The native policy carries the policy's `matchConditions`, so the excluded
namespaces stay excluded.

Two facts of Kyverno 1.19.1 shaped this, both measured:

- Kyverno generates no `ValidatingAdmissionPolicy` while the pod-controller
  autogen is on. Its status reads `skip generating ValidatingAdmissionPolicy:
  pod controllers autogen is enabled`. Hence Pods only.
- It decides once, on the status it reads at that moment. A policy created
  with the autogen on and switched off later keeps that message until its spec
  changes again. Measured: the switch applied by a Helm upgrade never took.
  So the autogen is off on every policy from its first install, and the
  Enforce switch then always takes, in 6 s.

A client who writes `validationFailureActionByPolicy` in `values` himself gets
a `Deny` policy through Kyverno's webhook, with `failurePolicy: Ignore`. That
policy fails open with Kyverno down. `enforce` is the supported switch.

`enforce` may only name a policy this configuration renders: a restricted one
with `profile = "restricted"`, `restrict-image-registries` with an allow-list.
Any other name is refused at plan, since it would be a switch that silently
does nothing.

## Exclusions, and the socle's own components

Every policy excludes `kube-system`, `flux-system` and `kyverno` by a CEL
`matchCondition` on the request's namespace. It applies at admission, in the
native policy and in background scans alike. Measured: no report in any of the
three.

The socle's own components are exempted by name, where a policy and their job
disagree. A per-policy exclusion replaces the global list, so it repeats it.

| Namespace | Policies | Why |
| --- | --- | --- |
| `otel-agent` | `disallow-host-path`, and with `restricted` `restrict-volume-types`, `require-run-as-nonroot`, `require-run-as-non-root-user` | It reads every container's log from `/var/log/pods`: a read-only hostPath, as root, every capability dropped ([otel-agent.md](otel-agent.md)) |

Under `restricted`, the socle's components that do not pass are listed by the
e2e, which prints every failing policy per namespace after a background scan.
On the local k3s, with `hello` only, `podinfo` fails
`disallow-privilege-escalation`, `require-run-as-nonroot` and
`restrict-seccomp-strict`. The CI run, with every default module, gives the
full table below. Each line is either a fix in that module's values or an
exemption here, decided module by module.

## What the client may set — `kube.kyverno_policies`

| Attribute | Default | Type | Meaning |
| --- | --- | --- | --- |
| `enabled` | `false` | bool | On installs the set; refused without `kube.kyverno.enabled` |
| `profile` | `"baseline"` | string | `baseline` or `restricted` |
| `enforce` | `[]` | list | Policies switched to Enforce, each made native; only names this configuration renders |
| `allowed_registries` | `[]` | list | Registry hosts, optionally with a port and a path: `ghcr.io`, `registry.k8s.io`, `ghcr.io/acme`, `localhost:5000`. No scheme, no trailing slash |
| `values` | `{}` | object | Any `kyverno-policies` chart value, the client's winning. A list he sets replaces the socle's whole: `customPolicies` drops the socle's two, `vpolExclude.excludeNamespaces` drops the three namespaces |
| `values_secret` | `""` | string | A Secret in `kyverno-policies` with a `values.yaml` key, merged last |

The chart carries no credential, so `values` has no path to refuse.

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

A client's own policies belong with his applications, in his GitOps, not in
`values.customPolicies`.

## Measured

On a local k3s 1.34.1 with flux-operator 0.60.0, through the real Flux path,
every step of the module's Chainsaw test passed. That run's cleanup then timed
out deleting the `busybox` pod, whose `sleep` ignores SIGTERM: the test now
gives it no grace period. A rerun on the same machine lost its node to another
cluster sharing the Docker host, so the green end-to-end run is CI's.

| Step | Measured |
| --- | --- |
| Both modules on, from the input provider | `Ready` in 96 s; 13 policies, all `WebhookConfigured` |
| A privileged pod, Audit | Admitted; `PolicyReport` fail in 21 s |
| `enforce = ["disallow-privileged-containers"]` | Native policy and binding in 6 s; the pod refused by the API server |
| Kyverno's admission at 0 replicas | Flux scales `podinfo` to 2 in 15 s; the privileged pod still refused; a pod without requests admitted |
| `allowed_registries = ["registry.k8s.io"]` | `busybox:1.37` admitted and reported `restrict-image-registries: fail` |
| `profile = "restricted"` | The six restricted policies rendered, `otel-agent` exempted where listed |
| Values order | Severity annotation: socle `medium`, `values` `high`, Secret `low` on the live policy; cleared, `medium` |
| Off | Policies, native policies and namespace gone in 11 s |

`tofu test`: 14 refusal cases and 1 positive for the two modules, defaults
asserted. The CI run on floci adds its figures here once it lands.

## Left out

- **Mutation and generation.** The set validates only. Defaults that mutate
  (a `seccompProfile`, a default request) would change what the client wrote,
  which the socle does not do unasked.
- **`verifyImages`.** See [kyverno.md](kyverno.md#left-out).
- **Namespaced policies.** The set is cluster-wide. A client who wants
  per-namespace rules writes them himself.
