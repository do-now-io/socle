---
title: Catalog module standard
description: What a catalog module ships, what CI checks of it, how its e2e proof is shaped, and the checklist a reviewer runs.
sidebar:
  order: 5
---

The contract every module under `oci/catalog/` meets. Why the rules are what
they are is in [The Flux catalog](../architecture/flux-catalog.md#how-a-module-template-is-written).
`hello` is the model for the structure, the toggle and the tests; `argocd`
for a module with chart values.

## What a module ships

| Part | Path | Checked by |
| --- | --- | --- |
| The template | `oci/catalog/<kebab-name>/resourceset.yaml`, one `ResourceSet` named after the folder, in `flux-system` | `check-catalog-clouds.sh` (the folder exists for every `catalog.tf` key); `pr-static.yaml` (renders and kubeconforms strictly) |
| The schema entry | `local.catalog` in `opentofu/bootstrap/catalog.tf`: key `<snake_name>` (the folder name with `_` for `-`), every attribute with its default, `enabled` included | `check-catalog-clouds.sh`; the `kube` validations |
| Per-attribute rules | validations of `kube` in `opentofu/bootstrap/variables.tf`, each with a failing case in `tests/validations.tftest.hcl` | `tofu test` |
| The overlays | a line `../../catalog/<kebab-name>/resourceset.yaml` in each `oci/clusters/<cloud>/kustomization.yaml` that offers it | `check-catalog-clouds.sh`, both directions; the kustomize build of each overlay |
| Cloud binding | an entry in `catalog_clouds` when the module is not on every cloud: `<snake_name> = ["aws", …]`, one per line | `check-catalog-clouds.sh`; refused at plan on another cloud |
| The e2e proof | `oci/catalog/<kebab-name>/tests/e2e/chainsaw-test.yaml`, and optionally `values.yaml` beside it | `check-catalog-clouds.sh` fails without the file; `e2e.yaml` runs it |
| The page | `docs/catalog/<kebab-name>.md`, from [`docs/catalog/_template.md`](https://github.com/do-now-io/socle/blob/main/docs/catalog/_template.md) | rule 6 of [CONTRIBUTING](../contributing.md#the-rules); not checked by CI yet |
| The decisions | `docs/decisions/<kebab-name>.md`, from [`docs/decisions/_template.md`](https://github.com/do-now-io/socle/blob/main/docs/decisions/_template.md) | review |

`check-catalog-clouds.sh` reads `catalog_clouds` by shape: one
`name = ["cloud", …]` per line. It fails when an overlay deploys a module
`catalog.tf` does not offer on that cloud, when `catalog.tf` offers one the
overlay does not deploy, when `catalog_clouds` names an unknown module or a
cloud with no overlay, and when a module has no folder or no
`chainsaw-test.yaml`.

## Template rules

- `inputsFrom` the one provider, `ResourceSetInputProvider` `socle`; no
  inline inputs.
- The reconcile toggle on each rendered object's own `metadata.annotations`:
  `fluxcd.controlplane.io/reconcile: << if inputs.modules.<m>.enabled >>enabled<< else >>disabled<< end >>`.
  Never in `commonMetadata`, which the operator does not template.
- One namespace per module, rendered by the module, carrying the toggle.
- Templates test values, never presence: every attribute is in the inputs.
- Cloud-specific values from `inputs.cloud` in the template, or a Kustomize
  patch in an overlay; never a new OpenTofu input for one module.
- A chart is pinned exactly: an `OCIRepository` tag, or a `HelmRepository`
  chart `version` where upstream publishes no OCI chart.
- No inline `spec.values` on the `HelmRelease`. `valuesFrom`, in order:
  ConfigMap `<module>-socle-values`, ConfigMap `<module>-client-values`
  (`<< toYaml inputs.modules.<m>.values >>`), then the Secret named by
  `values_secret` when set, `optional: true`. Both ConfigMaps labelled
  `reconcile.fluxcd.io/watch: Enabled`
  ([SOCLE-06](../decisions/socle.md#socle-06-the-clients-values-win)).
- `values` and `values_secret` in the schema of every module with a chart;
  the chart's secret-bearing paths in `values` refused at plan by a
  validation; `values_secret` validated as a Secret name.
- `resourcesTemplate` rather than `resources` when a block appears or
  disappears under a condition (the optional Secret entry).
- Cloud access as Crossplane managed resources in the module's own
  `ResourceSet`, never an OpenTofu role; the role before the workload, the
  chart in a child `<module>-workload` `ResourceSet` that `dependsOn` the
  role and its association with an explicit `readyExpr`, and the module
  `dependsOn` the `crossplane` `ResourceSet`
  ([SOCLE-04](../decisions/socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)).
- What must survive the module being off (CRDs holding the client's objects)
  is kept explicitly, and the page says so
  ([CRDs when a module is off](../architecture/flux-catalog.md#crds-when-a-module-is-off)).
- The render passes `flux-operator build rset -f <rs> --inputs-from
  oci/.ci/inputs-sample.yaml` and kubeconform `-strict`. A new attribute is
  added to `oci/.ci/inputs-sample.yaml`.

## The e2e proof

`e2e.yaml` discovers the modules from `oci/catalog/*/tests/e2e` and the
clouds from `.github/e2e/<cloud>/`, and runs one job per (module, cloud)
pair whose overlay lists `catalog/<module>/resourceset.yaml`. Nothing names a
module. Each job runs on its own floci, on the bare fixture root
`.github/e2e/<cloud>/`; the real root, `opentofu/clusters/<cloud>`, is
applied once in the `root (<cloud>)` job.

`chainsaw-test.yaml` holds one Chainsaw `Test` per phase, selected by labels:

| Label | Runs | Holds |
| --- | --- | --- |
| `phase: health` | every job, the real root's included | what a converged cluster shows at the catalog defaults: the `ResourceSet` Ready, the workload Available, the socle's own values on the live objects |
| `phase: module` | the module's own job, alone, after `health` | the mutations, each a `patch` of the `ResourceSetInputProvider` `socle`, the object a `tofu apply` changes; the last step leaves the inputs as it found them |
| `phase: destroyed` | after the socle's uninstall, beside the socle's own `destroyed` suite | what must survive the uninstall by design |
| `cloud: any` or `cloud: <cloud>` | every cloud, or that cloud's job only | a per-cloud assertion is a `Test` of its own |
| `platform: any` or `platform: floci` | everywhere, or on floci only | what only floci can state, such as a negative the real cloud would turn positive |

Every job injects `tag`, `cloud`, `cluster` and `floci_ip` as bindings; the
generic suite run during the OpenTofu-driven mutation also gets
`resourceset`. `tests/e2e/values.yaml`, when present, is passed with
`--values` for bindings the job does not set.

After the module's own tests, the job makes the one mutation that goes
through OpenTofu: `kube.<module>.enabled = false` (the socle's `disabled`
suite asserts the `ResourceSet` Ready with nothing rendered and no namespace
left with the module's label), the defaults back, the `root` and the
module's `health` tests again, and a second `tofu plan -detailed-exitcode`
that must be empty. Then the socle is uninstalled and the `destroyed` suites
run.

The `module` phase proves at least:

- every named attribute of the catalog entry reaching the live object it
  feeds;
- the whole `valuesFrom` order: a key the socle sets, overridden by `values`,
  overridden again by the Secret named in `values_secret` (created in the
  module's namespace, labelled `reconcile.fluxcd.io/watch: Enabled`), then
  both cleared and the socle's value back. A test on a key the socle leaves
  unset proves nothing;
- off: every object it rendered garbage-collected, and what that does to the
  modules that depend on it; on again;
- what the module does against the cloud, where floci can show it.

Two habits every suite keeps:

- **Every step carries a `catch`** that prints what the next failure needs:
  `describe`, `events`, `podLogs`.
- **Turning the module off waits for an idle release**: `Ready` and
  `Released` true, no `Reconciling` condition. Each values step drives a Helm
  upgrade; turning the module off while helm-controller still runs it with
  `--wait` makes the uninstall wait for the upgrade's five-minute timeout.

Chainsaw operations come first (`apply`, `patch`, `assert`, `error`, `wait`).
A `script` is the escape hatch for what the cluster cannot show, such as a
record in floci's Route 53, and for a `catch` that prints the node's state.
What floci cannot serve (Pod Identity, today) is a step of its own, named as
such.

## Reviewer checklist

- [ ] The folder is `oci/catalog/<kebab-name>/`; the `catalog.tf` key is the
      same name in `snake_case`; `enabled` is in the entry.
- [ ] `.github/scripts/check-catalog-clouds.sh` passes: every offering
      overlay lists the module, `catalog_clouds` names it if it is
      cloud-bound.
- [ ] Every rendered object carries the reconcile toggle on its own
      metadata, the namespace included.
- [ ] The chart is pinned exactly, its version in `docs/reference/compatibility.md`.
- [ ] No inline `spec.values`; `valuesFrom` is socle, client, Secret, in that
      order; the ConfigMaps carry the watch label.
- [ ] `values` refuses the chart's secret-bearing paths, each refusal with a
      failing `tofu test` case; every new validation has one.
- [ ] Cloud access, if any, is Crossplane resources in this `ResourceSet`,
      before the workload; no change under `opentofu/<cloud>/`.
- [ ] CRDs that hold the client's objects survive the module being off, or
      the page says they do not.
- [ ] `oci/.ci/inputs-sample.yaml` carries every new attribute; the render
      kubeconforms strictly.
- [ ] `tests/e2e/chainsaw-test.yaml` has a `health` and a `module` test, a
      `catch` on every step, and gates the off step on an idle release.
- [ ] The `module` test overrides a key the socle sets, through `values` and
      then `values_secret`, and asserts the result on the live object.
- [ ] `docs/catalog/<kebab-name>.md` exists with `title`, `description`,
      `category` and `requires` frontmatter, and
      `docs/decisions/<kebab-name>.md` holds its decisions.
