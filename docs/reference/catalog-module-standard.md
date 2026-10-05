---
title: Catalog module standard
description: What a catalog module ships, what CI checks of it, how its e2e proof is shaped, and the checklist a reviewer runs.
sidebar:
  order: 5
---

The contract every module under `oci/catalog/` meets; the why is in
[The Flux catalog](../architecture/flux-catalog.md#how-a-module-template-is-written).
Models: `hello` for structure and tests, `argocd` for chart values.

## What a module ships

| Part | Path | Checked by |
| --- | --- | --- |
| The template | `oci/catalog/<kebab-name>/resourceset.yaml`, one `ResourceSet` named after the folder, in `flux-system` | `check-catalog-clouds.sh`; `pr-static.yaml` (render, strict kubeconform) |
| The schema entry | `local.catalog` in `opentofu/bootstrap/catalog.tf`, key `<snake_name>`, every attribute with its default, `enabled` included | `check-catalog-clouds.sh`; the `kube` validations |
| Per-attribute rules | `kube` validations in `opentofu/bootstrap/variables.tf`, each failing case in `tests/validations.tftest.hcl` | `tofu test` |
| The overlays | `../../catalog/<kebab-name>/resourceset.yaml` in each offering `oci/clusters/<cloud>/kustomization.yaml` | `check-catalog-clouds.sh`, both directions |
| Cloud binding | `<snake_name> = ["aws", …]` in `catalog_clouds`, one per line, when not on every cloud | `check-catalog-clouds.sh`; refused at plan elsewhere |
| The e2e proof | `oci/catalog/<kebab-name>/tests/e2e/chainsaw-test.yaml`, optional `values.yaml` | `check-catalog-clouds.sh`; `e2e.yaml` runs it |
| The page | `docs/catalog/<kebab-name>.md`, from [`_template.md`](https://github.com/do-now-io/socle/blob/main/docs/catalog/_template.md) | rule 6 of [CONTRIBUTING](../contributing.md#the-rules); the site build |
| The decisions | `docs/decisions/<kebab-name>.md`, from [`_template.md`](https://github.com/do-now-io/socle/blob/main/docs/decisions/_template.md) | review |

## Template rules

- [ ] `inputsFrom` the `ResourceSetInputProvider` `socle`; no inline inputs.
- [ ] `fluxcd.controlplane.io/reconcile: << if inputs.modules.<m>.enabled >>enabled<< else >>disabled<< end >>`
      on each object's own annotations, never in `commonMetadata`.
- [ ] One namespace, rendered by the module, carrying the toggle.
- [ ] Templates test values, never presence.
- [ ] Cloud-specific values from `inputs.cloud` or an overlay patch; never a new OpenTofu input.
- [ ] The chart pinned exactly (OCI tag, or `HelmRepository` `version`), listed in [Compatibility](compatibility.md).
- [ ] No inline `spec.values`; `valuesFrom`: `<module>-socle-values`, `<module>-client-values`, then the
      `values_secret` Secret (`optional: true`); ConfigMaps labelled `reconcile.fluxcd.io/watch: Enabled`
      ([SOCLE-06](../decisions/socle.md#socle-06-the-clients-values-win)).
- [ ] `values` and `values_secret` in the schema; secret-bearing paths refused at plan, each with a failing `tofu test`.
- [ ] `resourcesTemplate` when a block appears under a condition.
- [ ] Cloud access as Crossplane resources in this `ResourceSet`, the chart in a child `<module>-workload`
      that `dependsOn` the role with a `readyExpr`; nothing under `opentofu/<cloud>/`
      ([SOCLE-04](../decisions/socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change)).
- [ ] CRDs that hold your objects kept when off, or the page says not
      ([CRDs when a module is off](../architecture/flux-catalog.md#crds-when-a-module-is-off)).
- [ ] New attributes in `oci/.ci/inputs-sample.yaml`; `flux-operator build rset` renders, kubeconform `-strict` passes.

## The e2e proof

`e2e.yaml` runs one job per (module, cloud) whose overlay lists the module,
each on its own floci with the fixture root `.github/e2e/<cloud>/`; the real
root is applied once, in `root (<cloud>)`.
`chainsaw-test.yaml` holds one `Test` per phase, selected by label:

| Label | Runs | Holds |
| --- | --- | --- |
| `phase: health` | every job, the real root's included | the `ResourceSet` Ready, the workload Available, the socle's values live |
| `phase: module` | the module's job, after `health` | mutations, each a `patch` of the input provider `socle`; the last restores it |
| `phase: destroyed` | after the uninstall | what must survive it |
| `cloud: any` / `cloud: <cloud>` | every cloud, or one | a per-cloud assertion is its own `Test` |
| `platform: any` / `platform: floci` | everywhere, or floci only | what only floci can state |

The `module` phase proves at least:

- [ ] every named attribute reaching its live object;
- [ ] the `valuesFrom` order on a key the socle sets: `values` over it, the
      `values_secret` Secret (labelled `reconcile.fluxcd.io/watch: Enabled`) over that, both cleared;
- [ ] off: everything garbage-collected, and the effect on dependent modules; on again;
- [ ] what it does against the cloud, where floci can show it.

Every step has a `catch` (`describe`, `events`, `podLogs`), and the off step
waits for an idle release (`Ready`, `Released`, no `Reconciling`).

<details>
<summary>Under the hood</summary>

Bindings: `tag`, `cloud`, `cluster`, `floci_ip` (and `resourceset` for the
generic suite); `tests/e2e/values.yaml` adds others through `--values`. After
the module's tests the job sets `kube.<module>.enabled = false` (the
`disabled` suite asserts nothing rendered), restores the defaults, re-runs
`root` and `health`, requires an empty `tofu plan -detailed-exitcode`, then
uninstalls and runs the `destroyed` suites. Chainsaw operations come first;
a `script` only for what the cluster cannot show (a record in floci's Route
53) or a `catch` that prints the node's state. What floci cannot serve (Pod
Identity, today) is a step of its own, named as such.

</details>

## Reviewer checklist

- [ ] Folder `oci/catalog/<kebab-name>/`, key `<snake_name>`, `enabled` in the entry.
- [ ] `.github/scripts/check-catalog-clouds.sh` passes.
- [ ] Every object, the namespace included, carries the toggle.
- [ ] The chart pinned exactly, its version in `docs/reference/compatibility.md`.
- [ ] `valuesFrom` socle, client, Secret; the watch label on both ConfigMaps.
- [ ] Every refusal and validation has a failing `tofu test` case.
- [ ] Cloud access in this `ResourceSet`, before the workload.
- [ ] Kept CRDs, or the page says they go.
- [ ] `oci/.ci/inputs-sample.yaml` updated; the render kubeconforms strictly.
- [ ] `health` and `module` tests, a `catch` on every step, an idle-release gate on off.
- [ ] The `module` test overrides a socle key through `values`, then `values_secret`.
- [ ] Page and decisions file exist; the page has `title`, `description`, `category`, `requires`.
- [ ] The page has a `kube-start` block and a `kube-full` block matching `catalog.tf`.
