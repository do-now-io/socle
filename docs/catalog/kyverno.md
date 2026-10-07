# Catalog module `kyverno` — the admission engine

Issue #57. Today nothing in a socle cluster refuses a privileged pod, an image
from any registry, or a workload without requests. [Kyverno](https://kyverno.io)
is the admission layer that does, in YAML and CEL. It ships as **two modules**:

- `kyverno`, this one: the engine, and no policy;
- [`kyverno_policies`](kyverno-policies.md): the socle's policy set on it.

A client can therefore run the engine with his own policies only. Both modules
are **off by default**. An admission webhook on every cluster is something a
client opts into, not something the socle ships unasked.

| Question | Position |
| --- | --- |
| What | The official `kyverno` chart, `oci://ghcr.io/kyverno/charts/kyverno:3.9.1` (Kyverno v1.19.1), one `HelmRelease` in namespace `kyverno` |
| Default | **Off** |
| Shape | Admission controller ×3 with a PodDisruptionBudget (`minAvailable: 1`); background and reports controllers ×1; **no cleanup controller** |
| Webhooks | Never see `kube-system`, `flux-system`, `kyverno`, nor any namespace the socle renders: Kyverno judges the client's applications only |
| Metrics | `prometheus.io/*` annotations on `:8000` for every controller, scraped by [`otel_gateway`](otel-gateway.md) |
| Dashboard | The chart's own, a `ConfigMap` labelled `grafana_dashboard`, loaded by [`grafana`](grafana.md) |
| Cloud access | None: no role, no Crossplane |
| Client surface | `enabled`, `values`, `values_secret` |

## Failure policy: what happens when Kyverno is down

The issue's first question. An admission webhook that is down can block every
apply in the cluster, Flux included. The answer has three layers, each
measured:

1. **The webhooks never see the control plane, Flux or the socle.**
   Kyverno's `config.webhooks.namespaceSelector` excludes `kube-system` and
   `flux-system` by name, and every namespace the socle renders by label:
   flux-operator labels each namespace a ResourceSet renders with
   `resourceset.fluxcd.controlplane.io/namespace`, the ResourceSet's own
   namespace, `flux-system` for the socle's. The chart excludes its own
   namespace on top. Every webhook Kyverno registers carries these selectors
   (measured on the live `ValidatingWebhookConfiguration`). Whatever policy a
   client writes, neither Flux nor a socle component ever waits on Kyverno.
   A client whose own ResourceSets live in `flux-system` would see their
   namespaces excluded too: his belong elsewhere, or in his ArgoCD.
   On GCP the selector also names GKE's own namespaces, which a client cannot
   deploy to on Autopilot: `kube-node-lease`, `gke-managed-system`,
   `gke-managed-cim`, `gke-gmp-system`, `gmp-system`, `gmp-public`. GKE keeps
   mutating webhooks out of its managed namespaces by rewriting their
   configuration;
   excluding them ourselves leaves it nothing to rewrite and Kyverno nothing
   to rewrite back. The list is the one known on 2026-10-07 — to check with
   `kubectl get ns` on the sandbox.
2. **Audit goes through Kyverno, and fails open.** The policies' webhooks are
   registered with `failurePolicy: Ignore`. Kyverno down admits. Nothing to
   refuse is lost, since an Audit policy refuses nothing.
3. **Enforce does not go through Kyverno at all.** A policy the client
   enforces is compiled by Kyverno into a native `ValidatingAdmissionPolicy`.
   The API server evaluates it in process, Kyverno up or down
   ([kyverno-policies.md](kyverno-policies.md#enforce)).

So Kyverno down blocks nothing, and an Enforce policy still holds. Measured on
a local k3s 1.34 through the real Flux path, with Kyverno's admission scaled to
zero:

| Request | Outcome |
| --- | --- |
| Flux scaling `podinfo` from 1 to 2 replicas | Applied, 2/2 Ready in 6 s |
| A pod without requests, `require-requests` in Audit | Admitted |
| A privileged pod, `disallow-privileged-containers` in Enforce | Refused by `ValidatingAdmissionPolicy 'vpol-disallow-privileged-containers'` |
| A pod in `flux-system`, privileged | Admitted: excluded |

The same proof runs in CI, in `kyverno_policies`' Chainsaw test.

**Replicas.** The admission controller is the one in the API server's path:
three replicas, spread by the chart's preferred anti-affinity, behind a
PodDisruptionBudget, so a node drain never takes the last one. The background
and reports controllers are leader-elected. A second replica would be a
standby, not capacity, so they run one each. The cleanup controller is off:
see the next section. A client lowers the admission
replicas through `values` for a dev cluster.

## Uninstall: nothing left behind

A webhook configuration that outlives its server is the outage this module is
careful to avoid. Kyverno registers its webhooks itself, with no owner
reference, so Kubernetes' garbage collector never removes them. Deleting the
`kyverno` namespace outright leaves all ten configurations behind (measured).
The chart removes them in a Helm `pre-delete` hook, which helm-controller runs
when the operator garbage-collects the `HelmRelease`.

The hook races the controllers it cleans up after. Every Kyverno controller
re-registers its webhook configuration when it disappears. The chart's first
hook scales the admission controller to zero, the second deletes the
configurations. The cleanup controller is still running at that moment.
Measured on floci, in this module's first CI run: off at 13:56:26, the release
uninstalled at 13:56:42, and `kyverno-cleanup-validating-webhook-cfg`
recreated at 13:56:28. It was still there five minutes later, with no server
behind it and `failurePolicy: Fail`. A local run on k3s had left nothing: the
outcome depends on timing.

**So the socle runs no cleanup controller.** It ships no cleanup or deleting
policy, which is all that controller serves: `CleanupPolicy`,
`DeletingPolicy` and the `cleanup.kyverno.io/ttl` label. Without it, the off
path leaves nothing, and the Chainsaw test asserts that every run: no
`ValidatingWebhookConfiguration`, no `MutatingWebhookConfiguration` labelled
`webhook.kyverno.io/managed-by: kyverno`, and no Kyverno CRD. A client who
wants TTL cleanup sets `cleanupController.enabled: true` in `values`. He then
accepts that an off may leave that one configuration behind. Its rules match
only Kyverno's cleanup kinds, whose CRDs go with the release, so no request
ever reaches it, and a later install of Kyverno takes it back.

**The policies go first.** Turning `kyverno` off while `kyverno_policies` is
on is refused at plan. Forced through the input provider, it was measured: the
engine's `HelmRelease` did not terminate within five minutes, and the
operator's garbage collection gave up on it. A client turns
`kyverno_policies` off, then `kyverno`.

The CRDs go with the release. That removes every Kyverno policy in the cluster,
the client's included. A client who keeps policies of his own across an
off/on sets `crds.annotations` in `values`.

## What is installed

When enabled, the hello-module shape under the `kyverno` names: `Namespace`,
`OCIRepository` pinned at 3.9.1, `kyverno-socle-values` and
`kyverno-client-values` (labelled `reconcile.fluxcd.io/watch`), and a
`HelmRelease` with no `spec.values`. The socle's values:

- the replica counts and the PodDisruptionBudget above, and
  `cleanupController.enabled: false`;
- requests of 100m / 128Mi for the admission container, 50m / 64Mi for the
  other two;
- the webhooks' `namespaceSelector`;
- the `prometheus.io/*` annotations on every controller;
- `grafana.enabled`, the chart's dashboard.

The chart's defaults stand for the rest: CRDs installed, policy and admission
reports on, background scans hourly, `policyExceptions` off.

## What the client may set — `kube.kyverno`

| Attribute | Default | Type | Meaning |
| --- | --- | --- | --- |
| `enabled` | `false` | bool | On installs the engine; off uninstalls it, its webhooks and its CRDs |
| `values` | `{}` | object | Any `kyverno` chart value, the client's winning. `imagePullSecrets` with credentials and an `extraEnvVars` entry named like a credential with a literal value are refused at plan |
| `values_secret` | `""` | string | A Secret in `kyverno` with a `values.yaml` key, merged last |

A client who sets `config.webhooks.namespaceSelector` in `values` replaces the
socle's whole: he must keep `kube-system` and `flux-system` in it.

```hcl
kube = {
  kyverno          = { enabled = true }
  kyverno_policies = { enabled = true }   # docs/catalog/kyverno-policies.md
}
```

## Reports and the dashboard

Kyverno writes a `PolicyReport` per resource it evaluates, in the resource's
namespace. On a busy cluster that volume is the known cost of Kyverno. The
socle keeps the chart's defaults: admission reports aggregated by the reports
controller, back-pressure at 1000 pending, background scans hourly. A Pod's
report arrived 21 s after its admission on the local k3s.

The Kyverno dashboard comes with the chart, as a `ConfigMap` labelled
`grafana_dashboard: "1"` that [`grafana`](grafana.md)'s sidecar loads. Its
variable is a Prometheus datasource, so it resolves to VictoriaMetrics. CEL
policies count under `kyverno_validating_policy_results_total`, not under the
legacy `kyverno_policy_results_total`. The chart's dashboard reads both.
Measured on floci: the CEL series of a reported pod reached VictoriaMetrics.
The e2e does not query it: that would take a script, and the scrape is
`otel_gateway`'s proof; it asserts the annotations and the dashboard's
ConfigMap instead.

## Why Kyverno and not OPA Gatekeeper

Gatekeeper's policies are Rego, a language of its own. Its mutation is a
separate, younger API. Image signature verification needs an external
provider. Kyverno's are YAML and CEL, the same CEL as Kubernetes' own
`ValidatingAdmissionPolicy`, which is what lets an Enforce policy run natively.
Kyverno mutates, generates and verifies cosign signatures with no other
component. Chainsaw, the socle's e2e runner, comes from the same project.

## Measured

Locally on k3s 1.34.1 with flux-operator 0.60.0, through the real Flux path:

- install of both modules from the input provider to `Ready`: 96 s;
- the controllers' footprint at rest: admission 26–109m CPU and 48–59Mi per
  replica, background and reports 16–24m and 51–56Mi;
- off: the release uninstalled in 38 s.

On floci, in the CI run of the first commit (run 36870726028), the
`kyverno (aws)` job:

| Step | Measured |
| --- | --- |
| On, to three admission replicas Ready | 52 s |
| Values order, two rollouts of the reports controller | 51 s |
| Off, the release uninstalled | 16 s; the cleanup controller's webhook left behind, which is why it is off |

The `kyverno-policies (aws)` job turns the engine on and off too, and was
green in the same run.

## Left out

- **Image verification.** No `verifyImages` policy for the socle's own images
  in v1. Verifying a cosign signature at admission needs Sigstore's
  transparency log and TUF root: an air-gapped cluster would refuse every pod
  or need a mirror. The socle already verifies its artifact in Flux
  (`SourceVerified`). A follow-up issue holds the policy for the socle's
  images, Audit first, and the offline story.
- **Policy exceptions.** `features.policyExceptions` stays off. The socle's own
  exemptions are by namespace, in the policies' values. A client who wants
  `PolicyException` objects turns the feature on through `values`.
- **`reports-server`.** Reports stay in etcd. A cluster whose reports outgrow
  it moves them to the chart's `reports-server` through `values`.
