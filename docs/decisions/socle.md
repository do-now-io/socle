---
title: Socle decisions
description: The decisions that are neither one cloud's nor one module's, one per section, each with its status.
sidebar:
  order: 1
---

The socle's own decisions: how a cluster gets from a tfvars file to a
converged catalog, how the artifact is published and released, how it is
tested, and the rules every catalog module follows. Two shape everything
else: OpenTofu ships inputs and the Flux Operator renders them
([SOCLE-01](#socle-01-opentofu-ships-the-inputs-the-flux-operator-renders-them)),
and a module carries its own cloud access so the foundations never change
([SOCLE-04](#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)).
The explanation of how the parts fit is in
[the architecture overview](../architecture/overview.md).

## SOCLE-01: OpenTofu ships the inputs, the Flux Operator renders them

**accepted** · 2026-09-23 · [`opentofu/bootstrap/main.tf`](../../opentofu/bootstrap/main.tf), [`opentofu/bootstrap/manifests/templates/inputs.yaml`](../../opentofu/bootstrap/manifests/templates/inputs.yaml), [`oci/catalog/`](../../oci/catalog/)

**Context.** A client's cluster needs his choices (which modules, which
values), the socle's templates, and something that turns the two into
Kubernetes objects and keeps them converged. OpenTofu could template the
modules itself, Helm could, or the Flux Operator's `ResourceSet` API could.
Templating in OpenTofu puts every module's manifests in the client's state
and makes a module change an OpenTofu change; a client Git repository holding
the rendered composition adds a distribution channel and a write-scoped token
per client.

**Decision.** Three roles, never mixed. OpenTofu, in the client's root, holds
the inputs: cloud, cluster identity, socle version and `kube`. The signed OCI
artifact holds the templates: one `ResourceSet` per catalog module and one
overlay per cloud. The Flux Operator, in the cluster, reads the inputs,
renders, reconciles and garbage-collects. OpenTofu ships one
`ResourceSetInputProvider` and one root `ResourceSet`, nothing else.

**Consequences.** The OpenTofu module knows the catalog only as a schema
(`catalog.tf`); the artifact knows nothing about any client. A module change
is an artifact change, delivered by a version bump. A template cannot read
anything OpenTofu did not put in the inputs, so every cloud fact a module
needs is an input (`inputs.cloud`, `inputs.cluster.region`, `inputs.gateway`).

**Sources.** [The Flux catalog](../architecture/flux-catalog.md#three-roles) ·
Flux Operator `ResourceSet` API, v0.60.0.

## SOCLE-02: Cilium and CoreDNS before Flux, from the bootstrap

**accepted** · 2026-09-24 · [`opentofu/bootstrap/cilium.tf`](../../opentofu/bootstrap/cilium.tf)

**Context.** EKS is created with `bootstrap_self_managed_addons = false` (no
VPC CNI, no kube-proxy, no CoreDNS) and AKS with `network_plugin = "none"`.
On both, every pod without `hostNetwork` stays `Pending` until a CNI runs,
flux-operator and the Flux controllers included, so a catalog module cannot
deliver the CNI Flux itself needs. Cilium's agent, operator and Envoy all run
`hostNetwork` (the 1.20.2 chart renders it on all three). The options were:
Helm releases in the bootstrap module before the operator; a pre-Flux step in
the client root; a minimal CNI that lets Flux deliver Cilium; a thin `cilium`
catalog module beside the release.

**Decision.** On aws and azure, and only there, the bootstrap module installs
Cilium (chart 1.20.2, `kube-system`) as a `helm_release` before
`flux-operator`, and on aws CoreDNS (chart 1.47.1) right after it. Cilium is
not a catalog module. GKE (Dataplane V2) and Kapsule operate Cilium
themselves; `cilium` is refused at plan there.

**Consequences.** One root and one apply still hold. The socle, not the
cloud, tracks which Cilium runs on which Kubernetes minor; the chart versions
are pinned in `cilium.tf` and move with socle releases. Every Deployment the
bootstrap installs needs a node, so on EKS the foundations own one node group
([AWS decisions](aws.md) carries its cost). Hubble and the Gateway API toggle
are values of the one release, `var.cilium`, never a second owner of it. Not
proven on a real EKS or AKS: floci's k3s runs flannel, so every e2e root sets
`cilium = { enabled = false }`.

**Sources.** [Cilium before Flux](../architecture/cilium-before-flux.md) ·
Cilium 1.20 AKS BYOCNI and ENI documentation.

## SOCLE-03: One in-cluster monitoring stack on every cloud

**accepted** · 2026-09-28 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf), [`oci/catalog/victoria-metrics/`](../../oci/catalog/victoria-metrics/), [`oci/catalog/otel-agent/`](../../oci/catalog/otel-agent/), [`oci/catalog/grafana/`](../../oci/catalog/grafana/)

**Context.** The cloud research had delegated workload metrics per cloud:
Managed Service for Prometheus on GKE
([GCP-04](gcp.md#gcp-04-workload-metrics-on-managed-service-for-prometheus)),
Managed Prometheus and Container Insights on AKS ([Azure decisions](azure.md)),
the socle's own Prometheus on Kapsule. Four clouds would then read four ways,
and two of them bill per sample or per GB ingested.

**Decision.** One stack, the same templates on every cloud: OpenTelemetry
collects (`otel_agent`, `otel_gateway`), VictoriaMetrics, VictoriaLogs and
VictoriaTraces store, Grafana reads. Each cluster is self-contained: no
remote-write, no federation, no central Alertmanager. The stack needs no
cloud access: every backend stores on a PVC. This supersedes the
cloud-managed Prometheus decisions of GCP and Azure.

**Consequences.** No per-sample charge on any cloud; the cost is Pod requests
and disks on nodes the client already pays for. Alerting and anything central
are out of the stack. `opentofu/gcp` still enables `managed_prometheus` (no
sample sent to it), and `opentofu/azure` still creates the Managed Prometheus
data collection rule and the Container Insights workspace: removing both from
the Azure foundations is still to do, so an AKS cluster pays twice until it
is.

**Sources.** [Observability](../architecture/observability.md) ·
[#43](https://github.com/do-now-io/socle/issues/43).

## SOCLE-04: Each module owns its cloud access; the foundations never change

**accepted** · 2026-09-23 · [`oci/catalog/crossplane/resourceset.yaml`](../../oci/catalog/crossplane/resourceset.yaml), [`oci/catalog/external-dns/resourceset.yaml`](../../oci/catalog/external-dns/resourceset.yaml), [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf) (`crossplane`)

**Context.** Several modules need a cloud service: external-dns writes DNS
records, KEDA reads queues, Velero writes a bucket. Each needs a role, per
cloud. If the foundations created those roles, five modules on four clouds
would be twenty optional IAM blocks to carry and wire through every client's
tfvars, four more per new module, and the cloud module would become a
function of the catalog chosen on top of it.

**Decision.** A module that needs a cloud service declares its own access in
its own `ResourceSet`, as Crossplane managed resources: the role, its policy
and its binding to the ServiceAccount the module renders, before the workload
that runs under it. OpenTofu never creates a role for a module, not as a
default, an option or an escape hatch. The foundations grant exactly one
cloud identity, Crossplane's, once per cloud, bounded by shape: on AWS a
permissions boundary and a path prefix the socle owns.

**Consequences.** A foundations module describes the same cluster whatever
the catalog runs. Crossplane's grant is the socle's most powerful object, and
is written down as such: it can create roles, inside the boundary only.
Anything needed before Crossplane runs cannot use it: Cilium's ENI
permissions are on the bootstrap nodes' role, and the EKS add-ons' roles are
the bootstrap module's
([SOCLE-23](#socle-23-eks-add-ons-from-the-bootstrap-the-pod-identity-agent-before-flux)).
Only AWS has Crossplane providers today; on the other clouds a module that
needs access runs without it and the client brings a credential.

**Sources.** [Module IAM](../architecture/module-iam.md) ·
[crossplane decisions](crossplane.md).

## SOCLE-05: The Kubernetes version moves by rings, N-1 then N

**proposed** · 2026-09-11 · [`opentofu/aws/variables.tf`](../../opentofu/aws/variables.tf) (`kubernetes_version`), [`opentofu/azure/cluster.tf`](../../opentofu/azure/cluster.tf) (`automatic_upgrade_channel`)

**Context.** A cluster must never enter a cloud's extended support. EKS and
Kapsule have no release channel for minors, GKE and AKS do. A socle release
and a Kubernetes minor change for different reasons, and a client frozen on
one minor must still get a socle fix.

**Decision.** The Kubernetes minor is pinned per cluster and moves through
the environments as rings, dev, then staging, then prod (the `environment`
variable is that axis): a ceiling of one minor behind the newest the cloud
offers (N-1), reached by the dev ring first, then N-1 becomes the floor the
next minor replaces. The socle release and the Kubernetes version move
through two decoupled pipelines, planned on Kargo.

**Consequences.** No Kargo pipeline exists in the repository: the decision is
proposed. Each cloud applies it its own way today. On AWS and Scaleway
`kubernetes_version` is required, with no default, and the module accepts any
`1.x` it is given; the ceiling is left to the pipeline. On GKE the release
channel (`REGULAR` by default) moves the version and the maintenance window's
day orders the rings ([GCP-02](gcp.md#gcp-02-regular-release-channel-rings-ordered-by-the-maintenance-window)).
On AKS `automatic_upgrade_channel = "stable"` upgrades within the required
maintenance window. The compatibility matrix the pipelines would read is the
socle's to own ([Compatibility](../reference/compatibility.md)).

**Sources.** AWS EKS version support policy · [AWS decisions](aws.md).

## SOCLE-06: The client's values win

**accepted** · 2026-09-23 · [`oci/catalog/argocd/resourceset.yaml`](../../oci/catalog/argocd/resourceset.yaml), [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf) (`kube` validations)

**Context.** A module's named attributes are the surface the socle curates;
a chart can do far more. A client must be able to set any chart value
without waiting for a socle release, and must never put a secret in the
OpenTofu state. helm-controller merges a `HelmRelease`'s `valuesFrom`
entries in order and then merges `spec.values` over the result
(`chartutil.ChartValuesFromReferences` ends on `MergeMaps(result, values)`):
a socle default written inline beats the client on every key both set.

**Decision.** Every module with a chart takes `values` (free-form, `{}`) and
`values_secret` (the name of a Secret the client creates in the module's
namespace, with a `values.yaml` key). The `HelmRelease` has no inline
`spec.values`. Its `valuesFrom` lists, in order: `<module>-socle-values`, the
socle's defaults rendered by the template; `<module>-client-values`, the
client's `values`; the client's Secret when he named one, `optional: true`.
Later wins. The two ConfigMaps carry the `reconcile.fluxcd.io/watch:
Enabled` label, and so must the client's Secret, for a change to apply
before the next interval. Each module refuses its chart's secret-bearing
paths in `values` at plan.

**Consequences.** Where a named attribute and `values` set the same key,
`values` wins: an attribute is a convenience, not a lock. A `clusters/<cloud>/`
overlay can no longer JSON-patch one value by path, because the values are a
YAML document inside a ConfigMap; per-cloud values go in the template under
`<< if eq inputs.cloud "…" >>`. Each module's e2e overrides one socle
default and asserts the client's value on the live object. Cilium and CoreDNS
follow the same promise through the `helm_release` values list, without
`values_secret`.

**Sources.** [How values merge](../architecture/flux-catalog.md#how-values-merge) ·
Flux helm-controller `valuesFrom` documentation.

## SOCLE-07: The root source is a ResourceSet, not the FluxInstance sync

**accepted** · 2026-09-23 · [`opentofu/bootstrap/manifests/templates/root.yaml`](../../opentofu/bootstrap/manifests/templates/root.yaml), [`opentofu/bootstrap/main.tf`](../../opentofu/bootstrap/main.tf) (`helm_release.instance`)

**Context.** A `FluxInstance` can carry a `sync` block that creates the
root source and Kustomization. In flux-operator v0.60.0 it has no `verify`
field (`api/v1/fluxinstance_types.go`), and `kustomize.patches` never reach
the objects it generates: a patch that misses stalls the instance while the
apply reports green (measured in PR #28).

**Decision.** The `FluxInstance` has no `sync` block. The root source is the
`socle-root` `ResourceSet`, deposited by the bootstrap envelope, rendering
the `OCIRepository` (with cosign verification) and the `socle`
Kustomization.

**Consequences.** The root source is under the operator's inventory, drift
correction and garbage collection, like every module. It is written once, in
`resourcesTemplate` rather than `resources`, because the optional `secretRef`
is a block `<< if >>` that only text templating can add or drop.

**Sources.** flux-operator v0.60.0 API · PR #28.

## SOCLE-08: helm_release is the applier, never the templater

**accepted** · 2026-09-23 · [`opentofu/bootstrap/main.tf`](../../opentofu/bootstrap/main.tf) (`helm_release.socle`), [`opentofu/bootstrap/manifests/`](../../opentofu/bootstrap/manifests/)

**Context.** Flux reads the Kubernetes API and nothing else: the first
objects it acts on must come from outside. Of OpenTofu's ways to write a
Kubernetes object, `kubernetes_manifest` needs the cluster and the CRDs to
exist at plan time, which breaks a single-root first apply; `local-exec
kubectl` is an out-of-band step.

**Decision.** OpenTofu applies the envelope through `helm_release` over a
local chart of two literal manifests. The only Helm expression in it is
`toYaml .Values.inputs`; the `<< >>` expressions are the operator's. The
envelope's chart version equals `VERSION`.

**Consequences.** The plan passes with the cluster unknown. The helm provider
does not re-apply a local chart whose templates changed unless its version or
values changed (measured), hence the version stamp, checked by
`check-version.sh`. The official ControlPlane bootstrap module ships a chart
for the same reason.

**Sources.** [What OpenTofu deposits](../architecture/flux-catalog.md#what-opentofu-deposits).

## SOCLE-09: One root, one apply

**accepted** · 2026-09-23 · [`opentofu/clusters/aws/main.tf`](../../opentofu/clusters/aws/main.tf)

**Context.** PR #28 had the bootstrap in a second root with its own state,
applied after the foundations, so that each root used one provider set.
Two roots mean two applies per change and an output handed from one state to
the other.

**Decision.** The foundations module and the bootstrap module are called
from one root, applied once. Each module still has its own providers: the
foundations the cloud's, the bootstrap `helm` (and `aws` on aws). This
replaces the second root.

**Consequences.** Measured: the plan passes with the cluster unknown, the
apply converges, a second plan is empty. Two cases need more than one apply,
documented with the root: replacing the cluster (`-target=module.foundations`
first) and destroying it with the API unreachable (`tofu state rm
module.socle` first). See [Uninstall](../guides/uninstall.md) and
[Troubleshooting](../guides/troubleshooting.md#when-one-apply-is-not-enough).

**Sources.** PR #28 · [Overview](../architecture/overview.md).

## SOCLE-10: No kubernetes provider

**accepted** · 2026-09-23 · [`opentofu/bootstrap/versions.tf`](../../opentofu/bootstrap/versions.tf)

**Context.** A `kubernetes` provider would let OpenTofu create Secrets or
read cluster state. It needs a reachable cluster at plan time, and anything
it reads or writes lands in the state.

**Decision.** No `kubernetes` provider anywhere in the chain. The bootstrap
needs `helm`, and `aws` on aws for the EKS add-ons.

**Consequences.** A credential the cluster needs (a mirror's pull secret, a
module's `values_secret`) is created outside OpenTofu and named in the
tfvars. Cilium and CoreDNS cannot take a `values_secret`: their charts name
an existing Secret instead.

**Sources.** [Pull from a private registry](../guides/private-registry.md).

## SOCLE-11: kube is typed any and validated against the catalog

**accepted** · 2026-09-23 · [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf) (`kube`), [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf)

**Context.** OpenTofu silently drops unknown attributes when converting to an
`object({…})` type: a misspelt module and a misspelt attribute both planned
as "No changes" (measured, OpenTofu 1.12.6). A `map(any)` refuses two modules
whose attributes differ: "all map elements must have the same type".

**Decision.** `kube` is `any`, validated by `validation` blocks against the
schema in `catalog.tf`: module names, attribute names, each value's kind
against its default's (read off `jsonencode`'s first character), the
module's cloud (`catalog_clouds`), and per-attribute rules. `local.modules`
merges the client's values over the defaults.

**Consequences.** A typo or a wrong type is an error at plan, with the
allowed list in the message. Every module and every attribute is present in
the inputs, so templates test values, never presence. terraform-docs shows
`any`; the schema is documented in [Inputs](../reference/inputs.md).

**Sources.** OpenTofu type conversion rules · `opentofu/bootstrap/tests/validations.tftest.hcl`.

## SOCLE-12: One input provider per cluster

**accepted** · 2026-09-23 · [`opentofu/bootstrap/manifests/templates/inputs.yaml`](../../opentofu/bootstrap/manifests/templates/inputs.yaml)

**Context.** The operator can read inputs from several providers, one per
module.

**Decision.** One `ResourceSetInputProvider`, `flux-system/socle`, of type
`Static`, read by every catalog `ResourceSet`.

**Consequences.** One object for OpenTofu whatever the catalog's size; shared
values (cloud, cluster, gateway) reach every module; the client reads his
whole configuration with one `kubectl get`. Per-module providers come back
the day a module must be rendered several times with different values; the
operator supports that without changing this design.

**Sources.** [The Flux catalog](../architecture/flux-catalog.md#what-opentofu-deposits).

## SOCLE-13: helm_kubernetes is an exec, no credential in the state

**accepted** on aws, gcp and scaleway · **proposed** on azure · 2026-09-23 · [`opentofu/aws/outputs.tf`](../../opentofu/aws/outputs.tf), [`opentofu/azure/outputs.tf`](../../opentofu/azure/outputs.tf) (`helm_kubernetes`)

**Context.** The root's `helm` provider needs the cluster's endpoint and a
credential. A kubeconfig or a token output would put a credential in the
state, and the helm provider does not take a kubeconfig string anyway.

**Decision.** Each foundations module outputs `helm_kubernetes = { host,
cluster_ca_certificate, exec = { api_version, command, args } }`, so the
root's provider block is `provider "helm" { kubernetes =
module.foundations.helm_kubernetes }` on every cloud. The exec plugin gets a
short-lived token at call time from the runner's ambient credentials: `aws
eks get-token` on AWS, `gke-gcloud-auth-plugin` on GCP, a credential minted
from `SCW_SECRET_KEY` on Scaleway, `kubelogin` on Azure.

**Consequences.** Nothing secret is stored. On Azure the exec only
authenticates against a cluster with Entra ID authentication enabled, which
`opentofu/azure` does not configure yet: the output is the shape a root will
consume, not a working login.

**Sources.** [Overview](../architecture/overview.md#how-the-root-reaches-the-cluster).

## SOCLE-14: nullable = false on every defaulted variable

**accepted** for `opentofu/aws` and `opentofu/bootstrap` · **proposed** for gcp, azure and scaleway · 2026-09-23 · [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf)

**Context.** A root that groups its inputs in an object (`aws = {…}`) passes
an omitted key as an explicit `null`, and OpenTofu keeps that null, the child
module's default not applied, unless the variable declares `nullable = false`
(measured, 1.12.6).

**Decision.** Every defaulted variable declares `nullable = false`, except
where the default is itself null.

**Consequences.** A root stays bare pass-through, with no copy of the
modules' defaults. `opentofu/gcp`, `azure` and `scaleway` get the declaration
when their roots are written.

**Sources.** [OpenTofu module standard](../reference/opentofu-module-standard.md).

## SOCLE-15: The socle's composition comes from OCI only; third-party CRDs from a pinned upstream

**accepted** · 2026-09-24 · [`opentofu/bootstrap/manifests/templates/root.yaml`](../../opentofu/bootstrap/manifests/templates/root.yaml), [`oci/catalog/gateway-api/resourceset.yaml`](../../oci/catalog/gateway-api/resourceset.yaml)

**Context.** The rule set on 2026-09-23 was "source kind: OCI only": the
socle is one signed artifact, never a client repository, Git or Bucket. The
Gateway API CRDs then needed a home: vendored, they were 20116 lines in the
repository; an `http` data source cost 6.4 MB of state; republishing them
needed a package and a CI step.

**Decision.** Where the socle's composition comes from stays OCI only. A
third-party, read-only dependency that carries no composition may come from
an upstream `GitRepository` pinned by commit: the Gateway API standard CRDs,
commit `8bb74df` (v1.6.1).

**Consequences.** No Git or Bucket variable exists for the root source. A
commit is content-addressed, so nothing changes under the socle; the cluster
must reach `github.com`.

**Sources.** [gateway-api](../catalog/gateway-api.md).

## SOCLE-16: Cosign verification is mandatory, main's identity trusted by default

**accepted** · 2026-09-23 · [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf) (`cosign_identity`), [`opentofu/bootstrap/manifests/templates/root.yaml`](../../opentofu/bootstrap/manifests/templates/root.yaml) (`verify`)

**Context.** Flux can verify a keyless cosign signature on every
reconciliation of an `OCIRepository`. Branch builds are signed by their
branch's workflow identity.

**Decision.** The `OCIRepository` always carries `verify`. `cosign_identity`
defaults to the release workflow on `refs/heads/main`; null means that
default, and an empty issuer or subject is refused. Verification cannot be
turned off.

**Consequences.** An unsigned artifact is not a socle. Production cannot run
a branch build without an explicit override in its tfvars, reviewed like any
change. Renaming `publish-artifact.yaml` changes the signed subject and
breaks every deployed verification.

**Sources.** [Distribution](../architecture/distribution.md#signatures).

## SOCLE-17: The version moves by a reviewed tfvars change

**accepted** · 2026-09-23 · [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf) (`flux_components`, `socle_version`)

**Context.** Flux's image automation controllers can rewrite a tag in Git
when a new one appears.

**Decision.** `flux_components` leaves out the image automation pair. The
socle version is `socle_version` in the client's tfvars, a SemVer tag;
`latest`, `main` and other moving heads are refused at plan.

**Consequences.** Every upgrade is a reviewed commit and a `tofu apply`. A
client who wants automatic bumps automates the tfvars change, not the
cluster.

**Sources.** [Upgrade the socle](../guides/upgrade.md).

## SOCLE-18: Two artifacts, one version

**accepted** · 2026-09-24 · [`.github/workflows/publish-artifact.yaml`](../../.github/workflows/publish-artifact.yaml) (`publish`, `publish-modules`, `promote`)

**Context.** `tofu init` fetches the module that creates the cluster, on a
machine where no cluster exists: Flux cannot make that pull. An OCI tag
carries one manifest: an OpenTofu module package
(`application/vnd.opentofu.modulepkg` over an `archive/zip` layer) and a Flux
artifact (`tar+gzip`) cannot share one.

**Decision.** Each push publishes two packages under the same tag:
`ghcr.io/do-now-io/socle/opentofu-modules` (the whole commit, for `tofu
init`) and `ghcr.io/do-now-io/socle/flux-modules` (`oci/`, for Flux). The tag
is computed once, in `publish`, and handed to `publish-modules`; both are
promoted in the same job, from the same commit.

**Consequences.** One `socle_version` pins the module sources and the
`OCIRepository` tag. A re-run of the promotion after a failure between the
two packages finishes the release. The bootstrap module travels in the
OpenTofu package.

**Sources.** [Distribution](../architecture/distribution.md).

## SOCLE-19: The consumer verifies the OpenTofu modules

**accepted**, not enforced · 2026-09-23 · [`.github/workflows/publish-artifact.yaml`](../../.github/workflows/publish-artifact.yaml) (`publish-modules`)

**Context.** OpenTofu does not verify OCI signatures: it pulls an unsigned or
tampered module package without complaint.

**Decision.** The module package is signed keyless like the artifact, and the
consumer runs `cosign verify` before `tofu init`, in his own CI.

**Consequences.** Nothing forces that step. Making it mandatory needs a
registry policy or an admission controller, out of scope.

**Sources.** [Artifacts](../reference/artifacts.md#verify-a-signature).

## SOCLE-20: A release re-tags the alpha; release-please runs in the same workflow

**accepted** · 2026-09-23 · [`.github/scripts/compute-tag.sh`](../../.github/scripts/compute-tag.sh), [`.github/scripts/release.sh`](../../.github/scripts/release.sh), [`.github/workflows/publish-artifact.yaml`](../../.github/workflows/publish-artifact.yaml)

**Context.** A release must be exactly what the proofs ran on. A release
created with the workflow's own token does not trigger other workflows, so an
`on: release` workflow would need a PAT or a GitHub App.

**Decision.** Every push to `main` publishes `<next>-alpha.N`, `<next>` read
from the conventional commits since the last release as release-please reads
them. release-please runs after the e2e proofs in the same workflow; merging
its pull request makes it tag the commit, and `promote` gives the alpha built
from that commit the version as a second tag with `crane tag`. Nothing is
rebuilt.

**Consequences.** Same digest, same signature, same identity (main). The
jobs are ordered in one run: alpha, proofs, release PR or release,
promotion. Merges must be rebase-only, so that every commit reaches `main`
with its own conventional message. `1.0.0` only comes from a `Release-As`
footer.

**Sources.** [Distribution](../architecture/distribution.md#releases) ·
[CONTRIBUTING, Releases](../contributing.md#releases).

## SOCLE-21: Chainsaw e2e, one job per module and cloud, on floci

**accepted** · 2026-10-01 · [`.github/workflows/e2e.yaml`](../../.github/workflows/e2e.yaml), [`.github/scripts/check-catalog-clouds.sh`](../../.github/scripts/check-catalog-clouds.sh)

**Context.** The first e2e was two jobs in `publish-artifact.yaml`, with the
assertions in shell. One module's flake (argocd's install timing out on a
cold runner, five runs in a row) failed a job named after no module.

**Decision.** Each catalog module ships its proof in
`oci/catalog/<module>/tests/e2e/chainsaw-test.yaml`. `e2e.yaml` discovers the
modules from those folders and the clouds from `.github/e2e/<cloud>/`, and
runs one job per pair the cloud's overlay deploys, each on its own floci,
plus the real root applied once. `check-catalog-clouds.sh` fails a module
without the file. The `e2e` job aggregates them and is the one required
context.

**Consequences.** Adding a module never touches the workflow. A failure names
its module and step, with the `catch` output beside it. Only what floci runs
is proven: no Cilium, no Pod Identity, no IAM enforcement, one node.

**Sources.** [Catalog module standard](../reference/catalog-module-standard.md#the-e2e-proof).

## SOCLE-22: tofu test, not Terratest

**accepted** · 2026-09-08 · [`opentofu/bootstrap/tests/`](../../opentofu/bootstrap/tests/), [`.github/workflows/pr-static.yaml`](../../.github/workflows/pr-static.yaml)

**Context.** Terratest has more expressive assertions, at the cost of Go in
every contributor's path. An emulator apply already covers convergence.

**Decision.** Unit tests are `tofu test`, native, one failing case per
validation block. Convergence is the e2e's.

**Consequences.** No Go toolchain to contribute. Assertions are limited to
what HCL can express over a plan with mocked providers.

**Sources.** [OpenTofu module standard](../reference/opentofu-module-standard.md#4-tests).

## SOCLE-23: EKS add-ons from the bootstrap, the Pod Identity Agent before Flux

**accepted** · 2026-09-30 · [`opentofu/bootstrap/eks_addons.tf`](../../opentofu/bootstrap/eks_addons.tf)

**Context.** The Pod Identity Agent, EBS CSI and EFS CSI stay EKS-managed
add-ons, but none can run before the nodes and the network do, and the
foundations stop at "nothing that needs a pod". Without the agent,
Crossplane's AWS providers hang on `169.254.170.23` without logging a line
(#48).

**Decision.** The bootstrap module creates the add-ons once the nodes run:
the Pod Identity Agent after Cilium and before `flux-operator`, the snapshot
controller and the two storage drivers after CoreDNS. The ordering point
holds on every cloud: whatever hands out cloud identities runs before the
first catalog module. The AWS details are in [AWS decisions](aws.md).

**Consequences.** Nothing the catalog renders ever starts on a cluster that
cannot give it an identity. The bootstrap needs the `aws` provider on aws.
Versions are pinned and move with the socle release. floci 2.1.0 has no
add-on API, so the e2e roots leave them off.

**Sources.** [Cilium before Flux](../architecture/cilium-before-flux.md#the-order-of-the-releases) · #48.

## SOCLE-24: CoreDNS by Helm on aws, not the EKS add-on

**accepted** · 2026-09-24 · [`opentofu/bootstrap/cilium.tf`](../../opentofu/bootstrap/cilium.tf) (`helm_release.coredns`)

**Context.** The flag that removed the VPC CNI also removed CoreDNS, and
Flux's source-controller must resolve `ghcr.io`. The EKS managed add-on
cannot be created before a CNI: its pods never schedule, it sits `DEGRADED`,
and the aws provider waits for `ACTIVE` until its 20-minute timeout. AKS
deploys CoreDNS as a system component whatever the network plugin.

**Decision.** On aws the bootstrap module installs CoreDNS (chart 1.47.1,
CoreDNS 1.14.6) by Helm right after Cilium, as `coredns` behind a `kube-dns`
Service at the `.10` address of the service range, with two replicas and a
disruption budget of one. On azure nothing is installed: AKS's own CoreDNS
runs once Cilium does.

**Consequences.** Nothing downstream can tell it from the add-on. The socle,
not AWS, tracks which CoreDNS runs on which Kubernetes minor. Not measured on
a real AKS.

**Sources.** [Cilium before Flux](../architecture/cilium-before-flux.md#coredns) ·
aws provider `waitAddonCreated`.

## SOCLE-25: flux-modules is public

**accepted** · 2026-10-01 · [`.github/actions/e2e-cluster/action.yaml`](../../.github/actions/e2e-cluster/action.yaml)

**Context.** The first push created the GHCR packages private, and GitHub has
no API to change a package's visibility. A private artifact needs a pull
secret in every cluster.

**Decision.** `ghcr.io/do-now-io/socle/flux-modules` is public (anonymous
pull measured 200 on 2026-10-01). The e2e pulls it with no secret, as a
client does.

**Consequences.** `artifact_pull_secret` is only for a mirror.

**Sources.** [Pull from a private registry](../guides/private-registry.md).

## SOCLE-26: opentofu-modules goes public at v1

**proposed** · 2026-10-01 · [`.github/workflows/publish-artifact.yaml`](../../.github/workflows/publish-artifact.yaml) (`publish-modules`)

**Context.** `ghcr.io/do-now-io/socle/opentofu-modules` is private while the
socle is under development (anonymous pull 403).

**Decision.** It goes public at v1, a one-time change in the package
settings.

**Consequences.** Until then `tofu init` against the published package, and
`cosign verify` of it, need a GitHub token with `read:packages`.

**Sources.** [Pull from a private registry](../guides/private-registry.md#the-opentofu-modules-package).

## SOCLE-27: One module per chart release, two collector modules

**accepted** · 2026-09-28 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf)

**Context.** A module is one `ResourceSet`, one namespace, one toggle, one
`values` surface. A single `monitoring` module would have to say which chart
`values` goes to, and turning traces off would need a sub-switch the
contract has no shape for. The agent and the gateway are the same chart in
two modes.

**Decision.** Six modules, one chart release each, one namespace each:
`otel_agent`, `otel_gateway`, `victoria_metrics`, `victoria_logs`,
`victoria_traces`, `grafana`.

**Consequences.** `kube.<m>.values` always means one chart's values. A client
can run the gateway alone where DaemonSets are unwelcome. A disabled module
garbage-collects its own namespace without deleting another's.

**Sources.** [Observability](../architecture/observability.md).

## SOCLE-28: OTLP everywhere, the otelcol-k8s collector, no remote-write

**accepted** · 2026-09-28 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml), [`oci/catalog/otel-gateway/resourceset.yaml`](../../oci/catalog/otel-gateway/resourceset.yaml)

**Context.** All three Victoria backends ingest OTLP over HTTP natively. The
`otelcol-k8s` distribution has 74 components against contrib's 251, carries
`otlphttp` and not `prometheusremotewrite`. `victoria-metrics-k8s-stack`
brings the VictoriaMetrics operator, vmagent, vmalert, Alertmanager,
kube-state-metrics, node-exporter and Grafana in one release, a second
collection layer beside OpenTelemetry. `opentelemetry-kube-stack` needs the
OpenTelemetry operator, whose webhooks need cert-manager by default.

**Decision.** Every signal crosses as OTLP over HTTP, from the plain
`opentelemetry-collector` chart in two releases, to single-node backends.
Neither stack chart, nor the cluster variants of the backends.

**Consequences.** One exporter, three signal endpoints, no operator. A client
who outgrows single-node needs a later module, not a switch.

**Sources.** [Observability](../architecture/observability.md#what-talks-to-what).

## SOCLE-29: No dependsOn between the monitoring modules

**accepted** · 2026-09-28 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml), [`oci/catalog/grafana/resourceset.yaml`](../../oci/catalog/grafana/resourceset.yaml)

**Context.** The collectors retry an absent backend; Grafana starts without
its datasources answering. Ordering would only make a slow backend block the
ones that are ready.

**Decision.** No `dependsOn` between the six. Each collector adds a signal's
exporter, and Grafana a datasource, only when that backend's `enabled` is
true in the inputs.

**Consequences.** Turning a backend off removes its pipelines and datasource
in the same reconciliation, with no collector retrying into a Service that is
gone. A module that needs a pipeline or a datasource carries it.

**Sources.** [Observability](../architecture/observability.md#what-talks-to-what).

## SOCLE-30: A PVC by default, an emptyDir on request

**accepted** · 2026-09-29 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf) (`storage_size`)

**Context.** Each backend needs a volume. GKE, AKS and Kapsule ship a default
StorageClass; EKS marks none default since 1.30, so a claim with no class
stays `Pending` there.

**Decision.** Each backend asks for a PVC of the cluster's default
StorageClass, with no class named in the template. `storage_size = ""`
renders no claim: the backend keeps its data in an `emptyDir`. No per-cloud
default class in the templates.

**Consequences.** On a socle EKS the client sets `storage_size = ""` until a
default class exists, and the data is lost when the pod moves; the gap is the
foundations', and the catalog does not hide it. floci's k3s ships
`local-path` as default, so the e2e exercises the PVC path.

**Sources.** [Observability](../architecture/observability.md#where-the-data-lives).

## SOCLE-31: The socle's dashboards, on OpenTelemetry names

**accepted** · 2026-09-29 · [`oci/catalog/otel-agent/dashboards/`](../../oci/catalog/otel-agent/dashboards/), [`oci/catalog/otel-gateway/dashboards/`](../../oci/catalog/otel-gateway/dashboards/)

**Context.** The community Kubernetes dashboards read kube-state-metrics and
node-exporter names. Adding both would be a second collection layer beside
the collectors, which already gather the same signals.

**Decision.** The socle writes its own dashboards on the names
VictoriaMetrics stores (OpenTelemetry metrics under
`-opentelemetry.usePrometheusNaming`), each shipped by the module whose
metrics it shows: nodes and pods by `otel_agent`, workloads by
`otel_gateway`. No kube-state-metrics, no node-exporter.

**Consequences.** Grafana names no module: a dashboard is a ConfigMap
labelled `grafana_dashboard`, under its module's toggle. The community
dashboards do not work unmodified.

**Sources.** [Observability](../architecture/observability.md#reading).
