# Catalog module `metrics_server` — the resource metrics API

metrics-server reads the CPU and memory of every node and pod from each
kubelet, keeps the latest value in memory, and serves it under the
`metrics.k8s.io` API. That API is what `kubectl top` reads and what every
HorizontalPodAutoscaler on CPU or memory scales from. Part of #52; the module
contract is `docs/flux-catalog.md` §6.

- **Not a monitoring system.** One value per node and per pod, refreshed every
  15 s, no history. History is the observability stack's job.
- **The first link of the scaling chain.** An HPA adds pods from these
  numbers; Karpenter (#53) adds nodes for the pods that no longer fit.

| Question | Position |
| --- | --- |
| What | The official chart, from the project's own Helm repository — upstream publishes no OCI chart — pinned exactly in the template |
| Where | **aws only.** Refused at plan on gcp and azure, where the cloud operates metrics-server, and on scaleway, where Kapsule ships its own ([observed in Scaleway's documentation](https://github.com/scaleway/docs-content/blob/main/pages/gpu/how-to/use-mig-with-kubernetes.mdx), absent from its [shared responsibility model](https://www.scaleway.com/en/docs/kubernetes/reference-content/kubernetes-shared-responsibility-model/), not verified by us) |
| Why not the EKS add-on | The same project on every cloud, so it is the socle's (`docs/aws/eks-managed-scope.md` §1) |
| Default | **On.** Without it `kubectl top` fails — `error: Metrics API not available`, measured on k3s with its own removed — and every HPA on CPU or memory stays blind — which a client discovers under load, when it is too late. It needs no input from the client: the chart renders with no values at all |
| Namespace | `metrics-server`, its own, like every other module — never `kube-system` |
| Kubelet TLS | **metrics-server checks every kubelet's certificate; the check is never turned off.** `--kubelet-insecure-tls` is refused at plan, in the client's `values` too: the socle owns the nodes, so a certificate that does not validate is the socle's to fix, not a client's to bypass. Measured on EKS: the kubelets' certificates validate as they are — `kubectl top` answers and metrics-server logs no `x509` error, with no `--kubelet-insecure-tls` among its args |
| API server to metrics-server TLS | **The chart's default, kept: metrics-server's own self-signed certificate, and the `APIService` skips its verification.** The alternatives are worse today: the chart's Helm-generated certificate expires after a year with nothing to renew it, and cert-manager, the one tool that would, is not in the socle. Impersonating metrics-server already takes write access to its namespace. Revisited when cert-manager joins the catalog |
| Where it runs | **Wherever the scheduler puts it** — today the bootstrap node group, the only compute. Which socle components stay pinned there is decided with Karpenter (#53), for all of them at once. It tolerates `CriticalAddonsOnly`, like CoreDNS, so it can follow that decision. Its requests fit on one surviving bootstrap node |
| Priority | `system-cluster-critical`, the chart's own default, kept: without it, an eviction under pressure silences every HPA in the cluster |
| Replicas | **One.** An outage freezes HPAs, it does not stop workloads: about a minute when a Spot node is drained ahead of a reclaim, up to five minutes when a node is lost without warning. `ha = true` runs two, spread across nodes, with a disruption budget — one switch, like `argocd` |
| Client surface | `enabled` (true), `ha` (false), `values`, `values_secret` — the catalog contract: every module with a chart takes both |

## What is installed

One `ResourceSet` (`oci/catalog/metrics-server/resourceset.yaml`), five
objects, each carrying the per-resource reconcile toggle on
`inputs.modules.metrics_server.enabled`:

1. `Namespace/metrics-server`.
2. `HelmRepository/metrics-server` in it — the project's own HTTPS repository,
   refreshed hourly.
3. `ConfigMap/metrics-server-socle-values` — the socle's chart values, the
   table below, as a YAML document.
4. `ConfigMap/metrics-server-client-values` — `kube.metrics_server.values` as
   YAML, `{}` by default.
5. `HelmRelease/metrics-server` — the chart pinned exactly. **No
   `spec.values`**: `valuesFrom` lists `metrics-server-socle-values`,
   `metrics-server-client-values`, then the client's Secret when named
   (`optional: true`), in that order. Both ConfigMaps carry
   `reconcile.fluxcd.io/watch: Enabled`, so a values-only change applies at
   once instead of at the next interval.

No `dependsOn`: the module needs no cloud access, so no Crossplane, and no
other module. The foundations do not change.

The socle's values, all in `metrics-server-socle-values`, and why:

| Value | Setting | Why |
| --- | --- | --- |
| `replicas` | 1, or 2 when `ha` | The replica decision above |
| `podDisruptionBudget` | off, or `maxUnavailable: 1` when `ha` | A drain never takes both replicas at once. With one replica a budget would block every drain and add no availability |
| `affinity` | none, or a **preferred** anti-affinity on `kubernetes.io/hostname` when `ha` | Two replicas land on two nodes when two exist. Required, a cluster down to one node could never schedule the second one, and the release would wait on it. Accepted: after a reschedule both replicas may share a node until the next one |
| `tolerations` | `CriticalAddonsOnly`, `Exists` | Can follow CoreDNS if the bootstrap nodes are tainted with Karpenter (#53) |
| `priorityClassName` | `system-cluster-critical` — the chart's default, kept | The priority decision above |
| `resources.requests` | 100m CPU, 200Mi memory — the chart's default, kept | No limits, like Cilium and ArgoCD: a memory limit guessed too low kills the pod every HPA depends on |
| `defaultArgs` | the chart's default, kept | `--kubelet-preferred-address-types` tries `InternalIP` first, the address a kubelet's certificate is checked against. `--kubelet-insecure-tls` is not among them, and the plan refuses it in `values` |
| `tls.type`, `apiService.insecureSkipTLSVerify` | the chart's defaults, kept | The API server to metrics-server decision above |

**Sizing.** metrics-server requests 100m and 200Mi, twice that with `ha`. The
bootstrap node group is sized for one node left (`docs/catalog/cilium.md` §2).
Measured on a demo EKS, catalog as deployed, metrics-server included: two
bootstrap nodes of 3920m each, the two together requesting 2362m and about
4.8 GiB — an upper bound for one survivor, since every DaemonSet is counted
twice.

- **CPU fits:** about 60 % of one node.
- **Memory depends on the survivor's family.** On a 16 or 32 GiB node, as
  measured, it is a fifth or less. On `c6g` or `c7g.xlarge`, two of the six
  default families with 8 GiB (about 6.6 GiB allocatable), it is about 73 %,
  and close to 90 % once Karpenter (#53) adds its 1 GiB. That margin is the
  bootstrap node group's sizing, not this module's: metrics-server is 200Mi
  of it.

## What the client may set — `kube.metrics_server`

| Attribute | Default | Type | Meaning |
| --- | --- | --- | --- |
| `enabled` | `true` | bool | Off garbage-collects the release, its namespace and its `APIService`. Offered on aws only: refused at plan elsewhere (`catalog_clouds`) |
| `ha` | `false` | bool | Two replicas, a preferred anti-affinity on the node, and a disruption budget of `maxUnavailable: 1` |
| `values` | `{}` | object | Any value of the chart, as the chart documents it. Merged over the socle's values, the client's winning |
| `values_secret` | `""` | string | Name of a Secret in `metrics-server`, created by the client, with a `values.yaml` key. Merged last. The chart takes no secret material; the attribute is there because the catalog contract gives it to every module with a chart |

Kinds are enforced by the catalog-wide kind check.

**Refused at plan:**

- `--kubelet-insecure-tls`, in any form, in `values.defaultArgs` or
  `values.args` — the chart reads both lists, so both are checked. It is the
  one setting that lowers what the module checks.
- The module on gcp, azure or scaleway.

**Left free, on purpose:** `tls.*` and `apiService.*`. Setting them can only
raise the API server to metrics-server check — a client running cert-manager
sets `tls.type: cert-manager` and `apiService.insecureSkipTLSVerify: false`.
Done halfway, `insecureSkipTLSVerify: false` alone, the `APIService` turns
`Available=False` and `kubectl top` fails at once. Flux does not show it: with
nothing behind the `APIService`, the `HelmRelease` stays `Ready` (measured on
floci, below). The `APIService` is the object to watch.

## Per cloud

| Cloud | metrics-server today | The module |
| --- | --- | --- |
| aws | **absent** — EKS installs none, and the foundations create the cluster with no self-managed add-on | installed by the socle |
| gcp | operated by GKE, behind `kube-system/metrics-server` ([GKE's HPA troubleshooting](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/horizontal-pod-autoscaling)) | refused at plan |
| azure | an AKS managed add-on ([AKS support policies](https://learn.microsoft.com/en-us/azure/aks/support-policies)) | refused at plan |
| scaleway | shipped by Kapsule in `kube-system` (the sources in the table above) | refused at plan |

- **One installed by the cloud is never doubled.** Two metrics-servers cannot
  coexist: the `APIService` is named after the API group and version, so one
  cluster holds only one, and several of the chart's cluster-wide RBAC objects
  carry fixed names too (measured on k3s, below).
- **Scaleway adds a reason of its own:** it asks that `kube-system` be left
  unmodified, or its automatic upgrades may fail.
- **How it is enforced:** `catalog_clouds` offers `metrics_server` on aws
  only, `oci/clusters/aws/kustomization.yaml` is the one overlay listing it,
  and `.github/scripts/check-catalog-clouds.sh` fails CI if the two disagree.

## When the `metrics.k8s.io` API is unavailable

The `APIService` exists before anything answers behind it: from its creation
until the pod is Ready, and whenever the pod is down — with one replica, up to
five minutes after a node is lost. In that window the API server reports the
group unavailable and its discovery is partial, since only metrics-server can
say which types it serves.

- **HPAs hold.** No scale-up, no scale-down; workloads keep running at their
  current replica count.
- **Flux stays green.** The `HelmRelease` is `Ready` while the `APIService` is
  `Available=False`: an alert on Flux alone misses this outage (measured on
  floci).
- **Discovery stays quiet.** `kubectl api-resources` exits 0 with nothing on
  stderr while the `APIService` is unavailable (measured on floci).
- **A namespace deletion waits.** The namespace controller must list every
  namespaced type before it removes a namespace, `PodMetrics` included, so a
  module disabled during the window stays `Terminating` and finishes on its
  own once the API answers. Nothing is lost; the client sees a delay. *Not
  measured: the quiet discovery above suggests the delay may not happen at
  all on a recent API server.*
- **The first apply.** Nothing in the socle trips on it: on floci the
  module's `ResourceSet` and `socle-root` were `Ready` 35 s after the apply,
  the `APIService` `Available` one second later.
- **Disabling the module itself.** The `APIService` belongs to no namespace,
  and still goes with the release: on floci the `HelmRelease`, the namespace
  and the `APIService` were gone, no namespace left `Terminating`.

## Measured

**Render and plan.** `flux-operator build rset` with `oci/.ci/inputs-sample.yaml`,
`ha` off and on: five objects, `valuesFrom` = socle, client, Secret, no
`spec.values`. `helm template` of the pinned chart over the rendered values,
with `ha`: two replicas, the disruption budget, the preferred anti-affinity
matching the chart's pod labels, the toleration, `system-cluster-critical`, a
client arg appended to the chart's. `tofu test`: 9 runs for this module —
every refusal tripped once, the defaults, an honest `--kubelet-*` flag passing.

**floci.** k3s's own metrics-server is removed by `.github/actions/e2e-cluster`
while the apply runs, as soon as k3s has applied it and long before Flux
exists, so every e2e job on aws runs the socle's, as EKS would. `oci/catalog/metrics-server/tests/e2e/chainsaw-test.yaml` asserts on
every push what the table shows; the timings were measured once, on the run
that first proved it:

| Phase | Measured |
| --- | --- |
| k3s's own removed | A `.skip` beside each of its seven manifests, then a delete: its nine objects gone, the `APIService` `NotFound`. Proven by hand to survive a k3s restart, the moment k3s re-applies its manifests |
| On, a client value over the socle's replicas | `ResourceSet` and `socle-root` `Ready` **35 s** after the apply, the `APIService` `Available` at **36 s**, pointing at `metrics-server/metrics-server` with Helm's and Flux's labels; `kubectl top nodes` at **40 s**. The live Deployment: 2 replicas — the client's — `system-cluster-critical`, no `--kubelet-insecure-tls` |
| Nothing behind the `APIService` | Scaled to 0: `Available=False`, the `HelmRelease` still `Ready`, `kubectl api-resources` exit 0 with an empty stderr. Back to 2 replicas: `Available` again |
| Off | `HelmRelease`, namespace and `APIService` gone; no namespace `Terminating` |

The suite also proves what the run above did not: `values_secret` merged
last — 3 replicas from the Secret over 2 from `values` over the socle's 1,
both cleared and the 1 back — and `ha`'s two replicas, budget and
anti-affinity, then gone with `ha` off.

Without any metrics-server, `kubectl top` answers `error: Metrics API not
available` (measured on k3s, its own removed by hand).

**EKS** (a demo cluster, two Graviton bootstrap nodes, catalog as
deployed): the chart installed by Helm with the socle's rendered values — the
Flux path is floci's to prove, the cloud's is this.

| Check | Measured |
| --- | --- |
| The API | `APIService` `Available`; `kubectl top nodes` and `kubectl top pods -A` answer |
| Kubelet TLS | No `x509` error in metrics-server's logs; its args are the chart's, without `--kubelet-insecure-tls` |
| An HPA on CPU | A busy loop requesting 100m, capped at 200m, HPA at 50 % between 1 and 3: `201%/50%` **15 s** after the HPA was created, **3** replicas at **30 s**. The load stopped: CPU at 0 % within a minute, back to **1** replica once the five-minute stabilization window had passed |
| Requests on the nodes | 1151m and 1211m of 3920m each; 1870Mi of 30 GiB and 3078Mi of 15 GiB — the sizing above |

## Left out, on purpose

- **Pinning to the bootstrap node group.** Decided with Karpenter (#53), for
  every socle component at once; the toleration is already there.
- **Custom and external metrics.** An HPA on requests per second or on a queue
  depth reads `external.metrics.k8s.io`, which the `keda` module ([note](keda.md))
  registers — a different `APIService`, so the two never collide. KEDA's own
  CPU and memory triggers still read this module's `metrics.k8s.io`.
- **The VerticalPodAutoscaler.** It reads the same API, but it is a separate
  component with its own decision.
- **A verified API server to metrics-server connection.** Waits for
  cert-manager in the catalog; until then a client running one sets it
  through `values`.
- **History.** One value per pod and per node is all metrics-server keeps;
  anything over time is the observability stack's.
