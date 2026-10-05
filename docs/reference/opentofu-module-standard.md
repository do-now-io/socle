---
title: OpenTofu module standard
description: The checklist a reviewer runs on an OpenTofu module of the socle, each item verifiable by a command or a named review step.
sidebar:
  order: 4
---

Every foundations module, and the bootstrap module, passes this before it is
accepted. Every item is verifiable by a command or a named review step.

## 1. Structure

- [ ] **One flat root module per cloud**, at `opentofu/<cloud>/`. Network,
      cluster and identities together; no submodule tree.
      *Verify:* `ls opentofu/*/` shows `.tf` files and no `modules/`.
- [ ] **Standard layout:** `main.tf`, `variables.tf`, `outputs.tf`,
      `versions.tf`, plus optional topic files.
      *Verify:* review step.
- [ ] **`examples/` holds a minimal deployable example.**
      *Verify:* `test -d opentofu/<cloud>/examples/minimal`
- [ ] **`tests/` holds the module's tests.**
      *Verify:* `test -d opentofu/<cloud>/tests`
- [ ] **OpenTofu 1.10 or later**, the floor OCI module distribution needs.
      *Verify:* `required_version = ">= 1.10"` in `versions.tf`.

## 2. Interface

- [ ] **Every variable is typed**, no bare `any` without a comment saying why.
      *Verify:* review step.
- [ ] **Constraints live in `validation` blocks, not documentation.**
      *Verify:* a `tofu test` case asserts the rejection.
- [ ] **Recommended positions are the defaults.** Setting nothing gives the
      recommended configuration.
      *Verify:* review step: the example sets only what is per-consumer.
- [ ] **Every defaulted variable declares `nullable = false`**, except where
      the default is itself null. A root that groups its inputs in an object
      passes an omitted key as an explicit null, which OpenTofu keeps
      otherwise
      ([SOCLE-14](../decisions/socle.md#socle-14-nullable--false-on-every-defaulted-variable)).
      *Verify:* review step on `variables.tf`.
- [ ] **Decisions with no good default have no default.** A silent default
      means nobody decided.
      *Verify:* review step against the cloud's decisions.
- [ ] **Options we would not recommend are absent, not exposed.**
      *Verify:* review step against the cloud's decisions.
- [ ] **Naming is consistent across clouds.**
      *Verify:* diff the variable names across `opentofu/*/variables.tf`.
- [ ] **Outputs cover the socle bootstrap:** cluster endpoint, CA,
      `helm_kubernetes` (an exec, no credential), the workload identity
      binding and the in-cluster provider's identity.
      *Verify:* `tofu output` on the example lists all of them.

## 3. Quality and security

- [ ] **`tofu fmt` and `tofu validate` are clean on every root module.**
      *Verify:* gated in `pr-static.yaml`.
- [ ] **TFLint passes with the cloud's provider plugin.** The generic ruleset
      alone catches almost nothing.
      *Verify:* `test -f opentofu/<cloud>/.tflint.hcl`, gated in CI.
- [ ] **Generated documentation is committed and current.**
      *Verify:* `terraform-docs markdown . --output-check` exits clean.
- [ ] **No HIGH or CRITICAL Trivy finding**, and every ignored check carries
      its reason in the code.
      *Verify:* gated in `pr-static.yaml`.
- [ ] **No secret committed, no credential accepted as a variable.** Modules
      authenticate through ambient credentials or workload identity
      federation.
      *Verify:* `trivy fs --scanners secret .`, plus a review of the variable
      list.

## 4. Tests

- [ ] **Unit: `tofu test`.** Native, no Go in a contributor's path. Covers
      what static checks cannot: validations rejecting bad input, defaults
      resolving to the recommended configuration, conditional logic planning
      as intended ([SOCLE-22](../decisions/socle.md#socle-22-tofu-test-not-terratest)).
      *Verify:* `tofu test` passes in `opentofu/<cloud>/`.
- [ ] **Every `validation` block has a test that trips it.**
      *Verify:* review step: one failing-input case per validation.
- [ ] **Integration: a plan against an emulator.** `integration.yaml` plans
      each foundations module against floci (AWS), floci-gcp and floci-az;
      Scaleway, with no emulator, plans its minimal example offline. The
      Azure leg is `continue-on-error`: floci-az's certificate fails Go's
      x509 validation.
      *Verify:* the workflow is green, or the leg's summary says why not.
- [ ] **Convergence: an apply on floci's k3s.** A plan does not prove
      convergence. `e2e.yaml` applies the cloud's real root once, and the
      bootstrap module on a fixture root per module, each ending in `tofu
      destroy`. Only AWS has a root today.
      *Verify:* the `e2e` check is green.
- [ ] **Legs that cannot apply say why, in the run summary.** Recorded
      exceptions, not silent ones.
      *Verify:* review step: the caveat shows on every run.

## 5. Versioning and distribution

- [ ] **SemVer, and majors mean what they say.** Removing a variable,
      renaming an output or forcing replacement is a breaking change: before
      1.0.0 it bumps the minor.
      *Verify:* review step on the commit type (`!` or `BREAKING CHANGE:`).
- [ ] **The module stamps the socle version** in `local.socle_version`,
      annotated `# x-release-please-version`.
      *Verify:* `.github/scripts/check-version.sh`.
- [ ] **Published as a cosign-signed OCI module package.**
      *Verify:* `tofu init` succeeds against the published package from a
      clean cache.
- [ ] **Consumers pin by tag and verify the signature themselves.** A
      client's root writes
      `source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/<cloud>?tag=${var.socle_version}"`.
      OpenTofu does not verify OCI signatures: signing only counts if the
      consumer runs `cosign verify` before `init`
      ([Artifacts](artifacts.md#verify-a-signature)).
      *Verify:* review step: the consumer documentation carries that step.
- [ ] **Renovate keeps provider and action versions moving.**
      *Verify:* `renovate.json` covers the module's manifests.

## 6. Compatibility with automation

- [ ] **Remote state lives in the consumer's account.** The module neither
      creates nor assumes a backend.
      *Verify:* review step: no `backend` block; the example documents one.
- [ ] **A single `tofu apply` converges, with no interactive input and no
      out-of-band step.** Where a cloud makes that impossible, the exception
      is in the module README.
      *Verify:* CI applies with `-input=false -auto-approve`.
- [ ] **Runnable by an isolated CI runner** holding only the roles the apply
      needs.
      *Verify:* review step: the example lists them.
- [ ] **Idempotent.** A second plan is empty.
      *Verify:* `tofu plan -detailed-exitcode` after the apply.
