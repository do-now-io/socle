---
title: OpenTofu module standard
description: The checklist a reviewer runs on an OpenTofu module of the socle, each item verifiable by a command or a named review step.
sidebar:
  order: 4
---

Every foundations module, and the bootstrap module, passes this checklist.

## 1. Structure

- [ ] **One flat root module per cloud** at `opentofu/<cloud>/`, no `modules/`. *Verify:* `ls opentofu/*/`.
- [ ] **`main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`**, plus topic files. *Verify:* review.
- [ ] **A minimal example.** *Verify:* `test -d opentofu/<cloud>/examples/minimal`.
- [ ] **Tests.** *Verify:* `test -d opentofu/<cloud>/tests`.
- [ ] **OpenTofu 1.10 or later**, for OCI modules. *Verify:* `required_version = ">= 1.10"`.

## 2. Interface

- [ ] **Every variable typed**; a bare `any` says why in a comment. *Verify:* review.
- [ ] **Constraints in `validation` blocks.** *Verify:* a `tofu test` case asserts the rejection.
- [ ] **Defaults are the recommended positions.** *Verify:* the example sets only per-consumer values.
- [ ] **`nullable = false` on every defaulted variable**, unless the default is null. *Verify:* review.
- [ ] **No default where none is good**; a silent default means nobody decided. *Verify:* review against the [decisions](https://github.com/do-now-io/socle/tree/main/docs/decisions).
- [ ] **Options we would not recommend are absent.** *Verify:* review against the decisions.
- [ ] **Names consistent across clouds.** *Verify:* diff `opentofu/*/variables.tf`.
- [ ] **Outputs for the bootstrap**: endpoint, CA, `helm_kubernetes` (an exec), the workload
      identity binding, the in-cluster provider's identity. *Verify:* `tofu output` on the example.

## 3. Quality and security

- [ ] **`tofu fmt` and `tofu validate` clean.** *Verify:* `pr-static.yaml`.
- [ ] **TFLint with the cloud's plugin.** *Verify:* `test -f opentofu/<cloud>/.tflint.hcl`, gated in CI.
- [ ] **Generated docs current.** *Verify:* `terraform-docs markdown . --output-check`.
- [ ] **No HIGH or CRITICAL Trivy finding**; each ignore states its reason. *Verify:* `pr-static.yaml`.
- [ ] **No committed secret, no credential variable**: ambient credentials or workload identity.
      *Verify:* `trivy fs --scanners secret .` and review.

## 4. Tests

- [ ] **Unit: `tofu test`**, no Go: validations, defaults, conditional logic. *Verify:* `tofu test` passes.
- [ ] **Every `validation` has a test that trips it.** *Verify:* review.
- [ ] **Integration: a plan against an emulator** (`integration.yaml`: floci, floci-gcp, floci-az;
      Scaleway offline; Azure `continue-on-error`). *Verify:* green, or the summary says why.
- [ ] **Convergence: an apply on floci's k3s** (`e2e.yaml`), ending in `tofu destroy`; AWS only today.
      *Verify:* the `e2e` check is green.
- [ ] **A leg that cannot apply says why** in the run summary. *Verify:* review.

## 5. Versioning and distribution

- [ ] **SemVer**: removing a variable, renaming an output or forcing replacement is breaking
      (the minor before 1.0.0). *Verify:* the commit type (`!` or `BREAKING CHANGE:`).
- [ ] **`local.socle_version`** annotated `# x-release-please-version`. *Verify:* `.github/scripts/check-version.sh`.
- [ ] **Published as a cosign-signed OCI package.** *Verify:* `tofu init` from a clean cache.
- [ ] **Consumers pin by `?tag=${var.socle_version}` and run `cosign verify` before `init`**
      ([Artifacts](artifacts.md#verify-a-signature)). *Verify:* the consumer docs carry it.
- [ ] **Renovate moves provider and action versions.** *Verify:* `renovate.json`.

## 6. Compatibility with automation

- [ ] **No `backend` block**; the state is the consumer's. *Verify:* review; the example documents one.
- [ ] **One `tofu apply` converges**, no input, no manual step; exceptions in the README.
      *Verify:* CI applies with `-input=false -auto-approve`.
- [ ] **Runs from an isolated CI runner** with only the roles it needs. *Verify:* the example lists them.
- [ ] **Idempotent.** *Verify:* `tofu plan -detailed-exitcode` after the apply is empty.
