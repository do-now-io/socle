---
title: Socle decisions
description: The decisions that are neither one cloud's nor one module's, one per section, each with its status.
sidebar:
  order: 1
---

How a cluster gets from tfvars to a converged catalog, how the artifact is
released and tested, and the rules every module follows. Read
[SOCLE-01](#socle-01-opentofu-ships-the-inputs-the-flux-operator-renders-them)
and [SOCLE-04](#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)
first; [the architecture overview](../architecture/overview.md) explains the parts.

## SOCLE-01: OpenTofu ships the inputs, the Flux Operator renders them

**accepted** · 2026-09-23 · [`opentofu/bootstrap/main.tf`](../../opentofu/bootstrap/main.tf), [`opentofu/bootstrap/manifests/templates/inputs.yaml`](../../opentofu/bootstrap/manifests/templates/inputs.yaml), [`oci/catalog/`](../../oci/catalog/)

**Decision.** OpenTofu holds the inputs (cloud, cluster, socle version,
`kube`); the signed OCI artifact holds the templates (one `ResourceSet` per
module, one overlay per cloud); the Flux Operator renders, reconciles and
garbage-collects. OpenTofu ships one `ResourceSetInputProvider` and one root
`ResourceSet`.

**Context.** Templating in OpenTofu puts every manifest in the client's state
and makes a module change an OpenTofu change; a client Git repository adds a
channel and a write-scoped token per client.

**Consequences.** A module change is an artifact change, delivered by a
version bump. A template reads only the inputs, so every cloud fact a module
needs is an input (`inputs.cloud`, `inputs.cluster.region`, `inputs.gateway`).

**Sources.** [The Flux catalog](../architecture/flux-catalog.md#three-roles) · Flux Operator `ResourceSet` API, v0.60.0.

## SOCLE-02: Cilium and CoreDNS before Flux, from the bootstrap

**accepted** · 2026-09-24 · [`opentofu/bootstrap/cilium.tf`](../../opentofu/bootstrap/cilium.tf)

**Decision.** On aws and azure only, the bootstrap installs Cilium (chart
1.20.2) as a `helm_release` before `flux-operator`, and on aws CoreDNS (chart
1.47.1) right after. Cilium is not a catalog module; it is refused at plan on
GKE and Kapsule, which operate Cilium themselves.

**Context.** EKS (no self-managed add-ons) and AKS (`network_plugin = "none"`)
start without a CNI, so every non-`hostNetwork` pod, Flux included, stays
`Pending`; Cilium's agent, operator and Envoy all run `hostNetwork`.

**Consequences.** One root, one apply. The socle tracks which Cilium runs on
which minor; versions move with socle releases. On EKS the foundations own one
node group for it. Not proven on a real EKS or AKS: the e2e roots set
`cilium = { enabled = false }` on floci's flannel.

**Sources.** [Cilium before Flux](../architecture/cilium-before-flux.md) · Cilium 1.20 AKS BYOCNI and ENI documentation.

## SOCLE-03: One in-cluster monitoring stack on every cloud

**accepted** · 2026-09-28 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf), [`oci/catalog/victoria-metrics/`](../../oci/catalog/victoria-metrics/), [`oci/catalog/otel-agent/`](../../oci/catalog/otel-agent/), [`oci/catalog/grafana/`](../../oci/catalog/grafana/)

**Decision.** The same templates on every cloud: OpenTelemetry collects,
VictoriaMetrics, VictoriaLogs and VictoriaTraces store on PVCs, Grafana reads.
No remote-write, no federation, no central Alertmanager, no cloud access. This
supersedes the cloud-managed Prometheus decisions of GCP and Azure.

**Context.** Delegating to each cloud's managed Prometheus
([GCP-04](gcp.md#gcp-04-workload-metrics-on-managed-service-for-prometheus))
meant four clouds read four ways, two billing per sample or per GB.

**Consequences.** No per-sample charge; the cost is Pod requests and disks.
Alerting is out of the stack. `opentofu/azure` still creates Managed
Prometheus and Container Insights, so an AKS cluster pays twice until they are
removed; `opentofu/gcp` still enables `managed_prometheus`, unused.

**Sources.** [Observability](../architecture/observability.md) · [#43](https://github.com/do-now-io/socle/issues/43).

## SOCLE-04: Each module owns its cloud access; the foundations never change

**accepted** · 2026-09-23 · [`oci/catalog/crossplane/resourceset.yaml`](../../oci/catalog/crossplane/resourceset.yaml), [`oci/catalog/external-dns/resourceset.yaml`](../../oci/catalog/external-dns/resourceset.yaml), [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf) (`crossplane`)

**Decision.** A module that needs a cloud service declares its role, policy
and binding in its own `ResourceSet`, as Crossplane managed resources.
OpenTofu never creates a module's role. The foundations grant one identity,
Crossplane's, bounded on AWS by a permissions boundary and a path prefix.

**Context.** Roles in the foundations would be twenty optional IAM blocks for
five modules on four clouds, and the cloud module would depend on the catalog.

**Consequences.** Crossplane's grant is the socle's most powerful object. What
runs before Crossplane cannot use it (Cilium's ENI permissions, the EKS
add-ons' roles, [SOCLE-23](#socle-23-eks-add-ons-from-the-bootstrap-the-pod-identity-agent-before-flux)).
Only AWS has Crossplane providers today; elsewhere the client brings a credential.

**Sources.** [Module IAM](../architecture/module-iam.md) · [crossplane decisions](crossplane.md).

## SOCLE-05: The Kubernetes version moves by rings, N-1 then N

**proposed** · 2026-09-11 · [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf) (`kubernetes_version`), [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`automatic_upgrade_channel`)

**Decision.** The minor is pinned per cluster and moves dev, staging, prod
(the `environment` axis), with a ceiling of N-1 that becomes the floor of the
next minor. Socle release and Kubernetes version move through two decoupled
pipelines, planned on Kargo.

**Context.** A cluster must never enter extended support; EKS and Kapsule have
no release channel for minors; a client frozen on a minor must still get fixes.

**Consequences.** No Kargo pipeline exists yet. Today: `kubernetes_version` is
required on AWS and Scaleway; GKE's release channel moves it
([GCP-02](gcp.md#gcp-02-regular-release-channel-rings-ordered-by-the-maintenance-window));
AKS uses `automatic_upgrade_channel = "stable"`. The matrix is in [Compatibility](../reference/compatibility.md).

**Sources.** AWS EKS version support policy · [AWS decisions](aws.md).

## SOCLE-06: The client's values win

**accepted** · 2026-09-23 · [`oci/catalog/argocd/resourceset.yaml`](../../oci/catalog/argocd/resourceset.yaml), [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf) (`kube` validations)

**Decision.** Every chart module takes `values` and `values_secret`. The
`HelmRelease` has no inline `spec.values`; its `valuesFrom` lists
`<module>-socle-values`, `<module>-client-values`, then the client's Secret
(`optional: true`), later winning. Secret-bearing paths in `values` are refused at plan.

**Context.** helm-controller merges `spec.values` over `valuesFrom`, so an
inline socle default would beat the client; secrets must stay out of the state.

**Consequences.** `values` beats a named attribute. Per-cloud values go in the
template, not a JSON patch. The client's Secret needs the
`reconcile.fluxcd.io/watch: Enabled` label to apply before the next interval.

**Sources.** [How values merge](../architecture/flux-catalog.md#how-values-merge) · Flux helm-controller `valuesFrom` documentation.

## SOCLE-07: The root source is a ResourceSet, not the FluxInstance sync

**accepted** · 2026-09-23 · [`opentofu/bootstrap/manifests/templates/root.yaml`](../../opentofu/bootstrap/manifests/templates/root.yaml), [`opentofu/bootstrap/main.tf`](../../opentofu/bootstrap/main.tf) (`helm_release.instance`)

**Decision.** The `FluxInstance` has no `sync` block; the `socle-root`
`ResourceSet` renders the `OCIRepository` (cosign-verified) and the `socle`
Kustomization.

**Context.** In flux-operator v0.60.0 `sync` has no `verify` field, and a
`kustomize.patches` that misses stalls the instance while the apply reports
green (measured in PR #28).

**Consequences.** The root source gets the operator's drift correction and
garbage collection like every module.

**Sources.** flux-operator v0.60.0 API · PR #28.

## SOCLE-08: helm_release is the applier, never the templater

**accepted** · 2026-09-23 · [`opentofu/bootstrap/main.tf`](../../opentofu/bootstrap/main.tf) (`helm_release.socle`), [`opentofu/bootstrap/manifests/`](../../opentofu/bootstrap/manifests/)

**Decision.** OpenTofu applies the envelope through `helm_release` over a
local chart of two literal manifests; the only Helm expression is
`toYaml .Values.inputs`. The chart version equals `VERSION`.

**Context.** `kubernetes_manifest` needs the cluster and CRDs at plan time,
which breaks a single-root first apply; `local-exec kubectl` is out of band.

**Consequences.** The plan passes with the cluster unknown. The helm provider
does not re-apply a changed local chart unless its version changes
(measured), hence the stamp checked by `check-version.sh`.

**Sources.** [What OpenTofu deposits](../architecture/flux-catalog.md#what-opentofu-deposits).

## SOCLE-09: One root, one apply

**accepted** · 2026-09-23 · [`opentofu/clusters/aws/main.tf`](../../opentofu/clusters/aws/main.tf)

**Decision.** The foundations and bootstrap modules are called from one root,
applied once, each with its own providers. This replaces PR #28's second root.

**Context.** Two roots meant two applies per change and an output handed
between states.

**Consequences.** Measured: plan with the cluster unknown, converging apply,
empty second plan. Replacing the cluster or destroying it with the API
unreachable needs more than one apply: see [Uninstall](../guides/uninstall.md)
and [Troubleshooting](../guides/troubleshooting.md#when-one-apply-is-not-enough).

**Sources.** PR #28 · [Overview](../architecture/overview.md).

## SOCLE-10: No kubernetes provider

**accepted** · 2026-09-23 · [`opentofu/bootstrap/versions.tf`](../../opentofu/bootstrap/versions.tf)

**Decision.** No `kubernetes` provider anywhere; the bootstrap needs `helm`,
and `aws` on aws.

**Context.** It needs a reachable cluster at plan, and what it reads or writes
lands in the state.

**Consequences.** Credentials the cluster needs are created outside OpenTofu
and named in the tfvars.

**Sources.** [Pull from a private registry](../guides/private-registry.md).

## SOCLE-11: kube is typed any and validated against the catalog

**accepted** · 2026-09-23 · [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf) (`kube`), [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf)

**Decision.** `kube` is `any`, validated against the schema in `catalog.tf`:
module and attribute names, value kinds, the module's cloud, per-attribute
rules. `local.modules` merges the client's values over the defaults.

**Context.** An `object({…})` silently drops unknown attributes (measured,
OpenTofu 1.12.6); a `map(any)` refuses modules whose attributes differ.

**Consequences.** A typo is an error at plan, with the allowed list. Every
attribute is present in the inputs. terraform-docs shows `any`; the schema is
in [Inputs](../reference/inputs.md).

**Sources.** OpenTofu type conversion rules · `opentofu/bootstrap/tests/validations.tftest.hcl`.

## SOCLE-12: One input provider per cluster

**accepted** · 2026-09-23 · [`opentofu/bootstrap/manifests/templates/inputs.yaml`](../../opentofu/bootstrap/manifests/templates/inputs.yaml)

**Decision.** One `Static` `ResourceSetInputProvider`, `flux-system/socle`,
read by every catalog `ResourceSet`.

**Context.** The operator could read one provider per module.

**Consequences.** One object whatever the catalog's size; shared values reach
every module; one `kubectl get` shows the whole configuration.

**Sources.** [The Flux catalog](../architecture/flux-catalog.md#what-opentofu-deposits).

## SOCLE-13: helm_kubernetes is an exec, no credential in the state

**accepted** on aws, gcp and scaleway · **proposed** on azure · 2026-09-23 · [`opentofu/aws/outputs.tf`](../../opentofu/aws/outputs.tf), [`opentofu/azure/outputs.tf`](../../opentofu/azure/outputs.tf) (`helm_kubernetes`)

**Decision.** Each foundations module outputs `helm_kubernetes = { host,
cluster_ca_certificate, exec }`; the exec plugin mints a short-lived token
from the runner's credentials (`aws eks get-token`, `gke-gcloud-auth-plugin`,
`SCW_SECRET_KEY`, `kubelogin`).

**Context.** A kubeconfig or token output would put a credential in the state.

**Consequences.** Nothing secret is stored. On Azure the exec needs Entra ID
authentication, which `opentofu/azure` does not configure yet.

**Sources.** [Overview](../architecture/overview.md#how-the-root-reaches-the-cluster).

## SOCLE-14: nullable = false on every defaulted variable

**accepted** for `opentofu/aws` and `opentofu/bootstrap` · **proposed** for gcp, azure and scaleway · 2026-09-23 · [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf)

**Decision.** Every defaulted variable declares `nullable = false`, except
where the default is null.

**Context.** A root passing an object leaves omitted keys as explicit `null`,
and the child's default is not applied (measured, 1.12.6).

**Consequences.** Roots stay bare pass-through. gcp, azure and scaleway get it
when their roots are written.

**Sources.** [OpenTofu module standard](../reference/opentofu-module-standard.md).

## SOCLE-15: The socle's composition comes from OCI only; third-party CRDs from a pinned upstream

**accepted** · 2026-09-24 · [`opentofu/bootstrap/manifests/templates/root.yaml`](../../opentofu/bootstrap/manifests/templates/root.yaml), [`oci/catalog/gateway-api/resourceset.yaml`](../../oci/catalog/gateway-api/resourceset.yaml)

**Decision.** The socle's composition comes from OCI only. A read-only
third-party dependency may come from a `GitRepository` pinned by commit: the
Gateway API CRDs, commit `8bb74df` (v1.6.1).

**Context.** Vendored, those CRDs were 20116 lines; an `http` data source cost
6.4 MB of state; republishing needed a package and a CI step.

**Consequences.** No Git or Bucket root source. A commit cannot change under
the socle; the cluster must reach `github.com`.

**Sources.** [gateway-api](../catalog/gateway-api.md).

## SOCLE-16: Cosign verification is mandatory, main's identity trusted by default

**accepted** · 2026-09-23 · [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf) (`cosign_identity`), [`opentofu/bootstrap/manifests/templates/root.yaml`](../../opentofu/bootstrap/manifests/templates/root.yaml) (`verify`)

**Decision.** The `OCIRepository` always carries `verify`; `cosign_identity`
defaults to the release workflow on `refs/heads/main`. It cannot be turned off.

**Context.** Flux verifies a keyless signature on every reconciliation; branch
builds are signed by their branch's identity.

**Consequences.** Running a branch build needs a reviewed override. Renaming
`publish-artifact.yaml` breaks every deployed verification.

**Sources.** [Distribution](../architecture/distribution.md#signatures).

## SOCLE-17: The version moves by a reviewed tfvars change

**accepted** · 2026-09-23 · [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf) (`flux_components`, `socle_version`)

**Decision.** No image automation controllers. `socle_version` is a SemVer
tag; `latest`, `main` and other moving heads are refused at plan.

**Context.** Flux's image automation can rewrite a tag in Git by itself.

**Consequences.** Every upgrade is a reviewed commit and a `tofu apply`.

**Sources.** [Upgrade the socle](../guides/upgrade.md).

## SOCLE-18: Two artifacts, one version

**accepted** · 2026-09-24 · [`.github/workflows/publish-artifact.yaml`](../../.github/workflows/publish-artifact.yaml) (`publish`, `publish-modules`, `promote`)

**Decision.** Each push publishes `ghcr.io/do-now-io/socle/opentofu-modules`
(for `tofu init`) and `ghcr.io/do-now-io/socle/flux-modules` (`oci/`, for
Flux) under one tag, computed once and promoted in the same job.

**Context.** `tofu init` runs where no cluster exists, and an OpenTofu module
package and a Flux artifact cannot share one OCI manifest.

**Consequences.** One `socle_version` pins both. Re-running a failed promotion
finishes the release.

**Sources.** [Distribution](../architecture/distribution.md).

## SOCLE-19: The consumer verifies the OpenTofu modules

**accepted**, not enforced · 2026-09-23 · [`.github/workflows/publish-artifact.yaml`](../../.github/workflows/publish-artifact.yaml) (`publish-modules`)

**Decision.** The module package is signed keyless; the consumer runs
`cosign verify` before `tofu init`, in his CI.

**Context.** OpenTofu does not verify OCI signatures.

**Consequences.** Nothing forces the step; enforcing it is out of scope.

**Sources.** [Artifacts](../reference/artifacts.md#verify-a-signature).

## SOCLE-20: A release re-tags the alpha; release-please runs in the same workflow

**accepted** · 2026-09-23 · [`.github/scripts/compute-tag.sh`](../../.github/scripts/compute-tag.sh), [`.github/scripts/release.sh`](../../.github/scripts/release.sh), [`.github/workflows/publish-artifact.yaml`](../../.github/workflows/publish-artifact.yaml)

**Decision.** Every push to `main` publishes `<next>-alpha.N`. release-please
runs after the e2e proofs in the same workflow; on release, `promote` adds the
version tag to the alpha with `crane tag`. Nothing is rebuilt.

**Context.** A release must be what the proofs ran on, and a release made with
the workflow token triggers no `on: release` workflow.

**Consequences.** Same digest, signature and identity. Merges are rebase-only.
`1.0.0` only comes from a `Release-As` footer.

**Sources.** [Distribution](../architecture/distribution.md#releases) · [CONTRIBUTING, Releases](../contributing.md#releases).

## SOCLE-21: Chainsaw e2e, one job per module and cloud, on floci

**accepted** · 2026-10-01 · [`.github/workflows/e2e.yaml`](../../.github/workflows/e2e.yaml), [`.github/scripts/check-catalog-clouds.sh`](../../.github/scripts/check-catalog-clouds.sh)

**Decision.** Each module ships `tests/e2e/chainsaw-test.yaml`; `e2e.yaml`
runs one job per module and cloud on its own floci, plus the real root once.
The `e2e` job aggregates them and is the one required context.

**Context.** Two shell-assertion jobs failed under no module's name when one
module flaked (argocd, five runs in a row).

**Consequences.** Adding a module never touches the workflow; a failure names
its module and step. Only what floci runs is proven: no Cilium, no Pod
Identity, no IAM enforcement, one node.

**Sources.** [Catalog module standard](../reference/catalog-module-standard.md#the-e2e-proof).

## SOCLE-22: tofu test, not Terratest

**accepted** · 2026-09-08 · [`opentofu/bootstrap/tests/`](../../opentofu/bootstrap/tests/), [`.github/workflows/pr-static.yaml`](../../.github/workflows/pr-static.yaml)

**Decision.** Unit tests are native `tofu test`, one failing case per
validation block; convergence is the e2e's.

**Context.** Terratest's richer assertions cost Go in every contributor's path.

**Consequences.** No Go toolchain; assertions are what HCL can express over a
mocked plan.

**Sources.** [OpenTofu module standard](../reference/opentofu-module-standard.md#4-tests).

## SOCLE-23: EKS add-ons from the bootstrap, the Pod Identity Agent before Flux

**accepted** · 2026-09-30 · [`opentofu/bootstrap/eks_addons.tf`](../../opentofu/bootstrap/eks_addons.tf)

**Decision.** The bootstrap creates the add-ons once nodes run: the Pod
Identity Agent after Cilium and before `flux-operator`, the snapshot
controller and storage drivers after CoreDNS. On every cloud, what hands out
identities runs before the first catalog module.

**Context.** The add-ons need nodes and network, which the foundations stop
short of; without the agent, Crossplane's AWS providers hang silently (#48).

**Consequences.** The bootstrap needs the `aws` provider on aws. floci 2.1.0
has no add-on API, so the e2e leaves them off.

**Sources.** [Cilium before Flux](../architecture/cilium-before-flux.md#the-order-of-the-releases) · #48.

## SOCLE-24: CoreDNS by Helm on aws, not the EKS add-on

**accepted** · 2026-09-24 · [`opentofu/bootstrap/cilium.tf`](../../opentofu/bootstrap/cilium.tf) (`helm_release.coredns`)

**Decision.** On aws the bootstrap installs CoreDNS (chart 1.47.1) by Helm
after Cilium, behind a `kube-dns` Service at the `.10` address, two replicas.
On azure, AKS's own CoreDNS runs once Cilium does.

**Context.** The EKS add-on cannot be created before a CNI: it sits
`DEGRADED` until the aws provider's 20-minute timeout. Flux must resolve `ghcr.io`.

**Consequences.** The socle tracks which CoreDNS runs on which minor. Not
measured on a real AKS.

**Sources.** [Cilium before Flux](../architecture/cilium-before-flux.md#coredns) · aws provider `waitAddonCreated`.

## SOCLE-25: flux-modules is public

**accepted** · 2026-10-01 · [`.github/actions/e2e-cluster/action.yaml`](../../.github/actions/e2e-cluster/action.yaml)

**Decision.** `ghcr.io/do-now-io/socle/flux-modules` is public (anonymous pull
measured 200 on 2026-10-01); the e2e pulls it with no secret.

**Context.** A private artifact needs a pull secret in every cluster.

**Consequences.** `artifact_pull_secret` is only for a mirror.

**Sources.** [Pull from a private registry](../guides/private-registry.md).

## SOCLE-26: opentofu-modules goes public at v1

**proposed** · 2026-10-01 · [`.github/workflows/publish-artifact.yaml`](../../.github/workflows/publish-artifact.yaml) (`publish-modules`)

**Decision.** `ghcr.io/do-now-io/socle/opentofu-modules` goes public at v1.

**Context.** It is private while the socle is under development (anonymous pull 403).

**Consequences.** Until then `tofu init` and `cosign verify` need a token with
`read:packages`.

**Sources.** [Pull from a private registry](../guides/private-registry.md#the-opentofu-modules-package).

## SOCLE-27: One module per chart release, two collector modules

**accepted** · 2026-09-28 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf)

**Decision.** Six modules, one chart release and namespace each: `otel_agent`,
`otel_gateway`, `victoria_metrics`, `victoria_logs`, `victoria_traces`, `grafana`.

**Context.** A module is one `ResourceSet`, toggle and `values` surface; a
single `monitoring` module could not say which chart `values` targets.

**Consequences.** `kube.<m>.values` is one chart's values. The gateway can run
alone; a disabled module removes only its own namespace.

**Sources.** [Observability](../architecture/observability.md).

## SOCLE-28: OTLP everywhere, the otelcol-k8s collector, no remote-write

**accepted** · 2026-09-28 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml), [`oci/catalog/otel-gateway/resourceset.yaml`](../../oci/catalog/otel-gateway/resourceset.yaml)

**Decision.** Every signal crosses as OTLP over HTTP, from the plain
`opentelemetry-collector` chart (`otelcol-k8s`) in two releases, to
single-node backends. Neither stack chart.

**Context.** All three Victoria backends ingest OTLP natively.
`victoria-metrics-k8s-stack` adds a second collection layer;
`opentelemetry-kube-stack` needs an operator and, by default, cert-manager.

**Consequences.** One exporter, no operator. Outgrowing single-node needs a
later module.

**Sources.** [Observability](../architecture/observability.md#what-talks-to-what).

## SOCLE-29: No dependsOn between the monitoring modules

**accepted** · 2026-09-28 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml), [`oci/catalog/grafana/resourceset.yaml`](../../oci/catalog/grafana/resourceset.yaml)

**Decision.** No `dependsOn` between the six; a collector exporter or Grafana
datasource exists only when its backend is `enabled`.

**Context.** Collectors retry an absent backend and Grafana starts without its
datasources; ordering would only let a slow backend block the rest.

**Consequences.** Turning a backend off removes its pipelines and datasource
in the same reconciliation.

**Sources.** [Observability](../architecture/observability.md#what-talks-to-what).

## SOCLE-30: A PVC by default, an emptyDir on request

**accepted** · 2026-09-29 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf) (`storage_size`)

**Decision.** Each backend claims a PVC of the default StorageClass;
`storage_size = ""` uses an `emptyDir`. No per-cloud class in the templates.

**Context.** EKS marks no StorageClass default since 1.30, so a classless
claim stays `Pending` there.

**Consequences.** On a socle EKS the client sets `storage_size = ""` until a
default class exists, and loses data when the pod moves.

**Sources.** [Observability](../architecture/observability.md#where-the-data-lives).

## SOCLE-31: The socle's dashboards, on OpenTelemetry names

**superseded by [SOCLE-32](#socle-32-kube-state-metrics-beside-the-collectors-for-alerting-no-node-exporter)** · 2026-09-29 · [`oci/catalog/otel-agent/dashboards/`](../../oci/catalog/otel-agent/dashboards/), [`oci/catalog/otel-gateway/dashboards/`](../../oci/catalog/otel-gateway/dashboards/)

**Decision.** The socle writes its dashboards on the OpenTelemetry names
VictoriaMetrics stores, each shipped by the module whose metrics it shows. No
kube-state-metrics, no node-exporter.

**Context.** Community dashboards need both, a second collection layer beside
the collectors.

**Consequences.** A dashboard is a ConfigMap labelled `grafana_dashboard`
under its module's toggle. Community dashboards do not work unmodified.

**Sources.** [Observability](../architecture/observability.md#reading).

## SOCLE-32: kube-state-metrics beside the collectors, for alerting; no node-exporter

**accepted** · 2026-10-10 · [`oci/catalog/kube-state-metrics/`](../../oci/catalog/kube-state-metrics/), [`oci/catalog/otel-gateway/resourceset.yaml`](../../oci/catalog/otel-gateway/resourceset.yaml)

**Decision.** The socle's alert rules are taken from awesome-prometheus-alerts.
For Kubernetes objects and Flux they read kube-state-metrics, which the
`kube_state_metrics` module runs and otel_gateway scrapes; for nodes they read
kubeletstats. No node-exporter. The dashboards stay on the OpenTelemetry names
VictoriaMetrics stores, each shipped by the module whose metrics it shows.

**Context.** #91: a default alerting comparable to kube-prometheus-stack's.
No published rule set reads OpenTelemetry's k8s names, the projects that
offer Kubernetes alerting on OpenTelemetry keep kube-state-metrics, and those
names are still in development
([KUBE-STATE-METRICS-01](kube-state-metrics.md#kube-state-metrics-01-kube-state-metrics-for-object-state-scraped-by-otel_gateway)).
node-exporter would need the node's root filesystem, which Autopilot and the
Baseline Pod Security Standard refuse.

**Consequences.** Still one collection layer: the collectors send everything,
kube-state-metrics is one more endpoint they scrape. Object state is
collected twice, for the dashboards and for the rules. The node rules
awesome-prometheus-alerts writes on node-exporter are translated where
kubeletstats has the figure, and listed as not covered where it does not
([Alert rules](../reference/alert-rules.md)).

**Sources.** #91; [Observability](../architecture/observability.md).
