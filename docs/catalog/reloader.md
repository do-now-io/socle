# Catalog module `reloader` — a workload rolled when what it reads changes

Half of #56, with [`external_secrets`](external-secrets.md). External Secrets
Operator rewrites a `Secret` when its value rotates in the cloud's secret
manager; a pod that read it at start never sees the change. Stakater Reloader
closes that gap: it watches ConfigMaps and Secrets and rolls the workloads
that ask for it. It ships as its own module so that it stays usable alone,
for ConfigMaps, with its own namespace and toggle.

| Question | Position |
| --- | --- |
| What | The official chart, `oci://ghcr.io/stakater/charts/reloader:2.2.18` (Reloader v1.4.22), one `HelmRelease` in namespace `reloader` |
| Default | **Off** |
| Mode | **Opt-in per workload**, never `autoReloadAll`: refused at plan in `values` |
| Strategy | `annotations`: a reload writes `reloader.stakater.com/last-reloaded-from` on the pod template |
| Pod security | `restricted`, enforced on the namespace |
| Cloud access | None |
| Client surface | `enabled`, `values`, `values_secret` |

## What is installed

When enabled: `Namespace` `reloader` labelled
`pod-security.kubernetes.io/enforce: restricted`, an `OCIRepository` pinned at
2.2.18, `reloader-socle-values` and `reloader-client-values` (both labelled
`reconcile.fluxcd.io/watch: Enabled`), and a `HelmRelease` with no
`spec.values`; `valuesFrom` lists the socle's document, the client's, then
his Secret when he names one (`docs/flux-catalog.md` §6).

The socle's values:

- `fullnameOverride: reloader`;
- `reloader.autoReloadAll: false`, stated rather than inherited;
- `reloader.reloadStrategy: annotations`;
- `readOnlyRootFileSystem: true`, `allowPrivilegeEscalation: false`, every
  capability dropped; the chart already runs as 65534 with the
  `RuntimeDefault` seccomp profile, so the namespace holds `restricted`;
- requests 10m / 64Mi, a 256Mi memory limit, from which the chart derives
  `GOMEMLIMIT`;
- `prometheus.io/scrape` on port 9090, for [`otel_gateway`](otel-gateway.md).

## How a client uses it

On the workload, one of Reloader's annotations:

```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"                    # every ConfigMap and Secret it references
    # secret.reloader.stakater.com/reload: "db-credentials"   # or only those named
    # configmap.reloader.stakater.com/reload: "app-config"
```

A workload with none of them is never touched.

## Decisions

**Opt-in, never `autoReloadAll`.** With `autoReloadAll` every Deployment,
StatefulSet and DaemonSet of the cluster restarts when anything it reads
changes, the client's tenants included. Whether a restart is safe is a
property of the workload, so the workload says it. `variables.tf` refuses
`kube.reloader.values.reloader.autoReloadAll = true` with the annotation to
use instead. `values_secret` is never read by OpenTofu, so a Secret could
still set it: that Secret is the client's own, reviewed outside the socle.

**The `annotations` strategy.** The chart's default writes a `STAKATER_*`
environment variable into the pod template. Both strategies change the
template, but an annotation is something a GitOps diff (ArgoCD's
`ignoreDifferences`, a Flux drift exclusion) can be told to ignore, and an
injected env entry in a container list is not. It also names what changed:
`last-reloaded-from` is a JSON with the kind, namespace and name of the
object, which the e2e reads.

**Off by default.** Reloader's ClusterRole lists, gets and watches every
ConfigMap and Secret of the cluster. That is inherent to what it does, and
the chart's scoped mode (`reloader.namespaces`, a Role per namespace) is
`values` away for a client who wants it narrower. It is a grant a client
chooses, not one the socle makes for him.

**Secrets refused in `values`.** The chart turns `reloader.deployment.env.secret`
into a Secret of its own (its alerting webhook URL is a credential) and
`env.open` into literal variables. Any `env.secret` entry, and an `env.open`
entry named like a credential, are refused at plan; `env.existing` names a
Secret the client made and passes.

## What the e2e proves

`oci/catalog/reloader/tests/e2e/chainsaw-test.yaml`, on floci's k3s:

- `health`: off, the ResourceSet Ready with an empty inventory, no namespace;
- `module`: on, the Deployment Available in a `restricted` namespace with
  `--reload-strategy=annotations` and no `--auto-reload-all`; two workloads
  reading one ConfigMap and one Secret, one annotated: a ConfigMap change,
  then a Secret change, roll the annotated one, each time naming the object
  that changed, and leave the other at generation 1; the whole `valuesFrom`
  order on the memory request (socle 64Mi, `values` 80Mi, Secret 96Mi, back
  to 64Mi); off, garbage-collected.

Nothing here needs floci to emulate a cloud service.

## What was measured

| | Result |
| --- | --- |
| Render (`flux-operator build rset`, `oci/.ci/inputs-sample.yaml`) | 5 objects; the Secret entry in `valuesFrom` only when `values_secret` is set; kubeconform strict: valid |
| Chart render with the socle's values (`helm template`) | args `--log-level=info --reload-strategy=annotations`; container `readOnlyRootFilesystem`, no privilege escalation, `ALL` dropped; pod `runAsNonRoot`, 65534, `RuntimeDefault` |
| `tofu test` | the default, a values pass-through, and six refusals |
| e2e, CI (`reloader (aws)`, [run 36865489015](https://github.com/do-now-io/socle/actions/runs/36865489015), green on its first run too) | on, Available in 16 s; ConfigMap change to roll: under 1 s; Secret change to roll: 10 s; the whole `valuesFrom` order 34 s; off 26 s; the module's suite 1m33s. **Job: 6m26s** |

## Left out

- **HA.** One replica, no leader election. A change made while Reloader is
  restarting is not seen: it reacts to update events, and `syncAfterRestart`
  stays off because it rolls every annotated workload on each restart. A
  client who cannot afford the window sets `reloader.enableHA` and
  `deployment.replicas`, or `syncAfterRestart`, through `values`.
- **Argo Rollouts, OpenShift, CSI driver integration.** Not in the socle.
- **Alerting on reload.** Its webhook is a credential: `env.existing` from a
  Secret the client made.
- **Reloader 3.x.** In beta at the time of writing (3.0.0-beta.2); the pin
  moves when it is stable.
