# OpenTofu module conformance checklist

Every foundations module passes this before it is accepted. **Every item is
verifiable by a command or a named review step.**

> **Status: draft, unapproved.** The copyable skeleton and the reusable CI
> configuration are still missing; the skeleton has to implement this
> checklist rather than precede it.

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

## 2. Interface

- [ ] **Every variable is typed**, no bare `any` without a comment saying why.
      *Verify:* review step.
- [ ] **Constraints live in `validation` blocks, not documentation.**
      *Verify:* a `tofu test` case asserts the rejection.
- [ ] **Recommended positions are the defaults.** Setting nothing gives the
      recommended configuration.
      *Verify:* review step — the example sets only what is per-consumer.
- [ ] **Decisions with no good default have no default.** A silent default
      means nobody decided.
      *Verify:* review step against the cloud's research document.
- [ ] **Options we would not recommend are absent, not exposed.**
      *Verify:* review step against the cloud's research document.
- [ ] **Naming is consistent across clouds.**
      *Verify:* diff the variable names across `opentofu/*/variables.tf`.
- [ ] **Outputs cover the socle bootstrap:** cluster endpoint, CA, OIDC
      issuer, workload identity binding, and the in-cluster provider's
      identity.
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
      what static checks cannot — validations rejecting bad input, defaults
      resolving to the recommended configuration, conditional logic planning
      as intended.
      *Verify:* `tofu test` passes in `opentofu/<cloud>/`.
- [ ] **Every `validation` block has a test that trips it.**
      *Verify:* review step — one failing-input case per validation.
- [ ] **Integration: an ephemeral apply against an emulator.** Plan-only does
      not prove convergence. Each leg of `integration.yaml` declares whether
      it applies or only plans.
      *Verify:* the workflow is green **and** the leg says `apply`.
- [ ] **Legs that cannot apply say why, in the run summary.** Scaleway has no
      emulator; GCP's has no Compute Engine API and crashes the google
      provider on cluster read-back. Recorded exceptions, not silent ones.
      *Verify:* review step — the caveat shows on every run.

Terratest was rejected: more expressive assertions, at the cost of Go in every
contributor's path, and the emulator apply already covers convergence.

## 5. Versioning and distribution

- [ ] **SemVer, and majors mean what they say.** Removing a variable,
      renaming an output or forcing replacement is a major.
      *Verify:* review step at release time.
- [ ] **Published as a cosign-signed OCI artifact.**
      *Verify:* `tofu init` succeeds against the published artifact from a
      clean cache.
- [ ] **Consumers pin by digest and verify the signature themselves.**
      **OpenTofu does not verify OCI signatures** — it will pull a tampered
      artifact. Signing only counts if the consumer runs `cosign verify`
      before `init`, or registry policy enforces it.
      *Verify:* review step — the consumer documentation carries that step.
- [ ] **Renovate keeps provider and action versions moving.**
      *Verify:* `renovate.json` covers the module's manifests.

## 6. Compatibility with automation

- [ ] **Remote state lives in the consumer's account.** The module neither
      creates nor assumes a backend.
      *Verify:* review step — no `backend` block; the example documents one.
- [ ] **A single `tofu apply` converges, with no interactive input and no
      out-of-band step.** Where a cloud makes that impossible, the exception
      is in the module README.
      *Verify:* CI applies with `-input=false -auto-approve`.
- [ ] **Runnable by an isolated CI runner** holding only the roles the apply
      needs.
      *Verify:* review step — the example lists them.
- [ ] **Idempotent.** A second plan is empty.
      *Verify:* `tofu plan -detailed-exitcode` after the apply.

## 7. Provider and OpenTofu compatibility

- [ ] **`required_version` has a floor that reflects what the module needs.**
      OCI distribution sets it.
      *Verify:* `grep required_version opentofu/*/versions.tf`
- [ ] **Provider constraints are bounded ranges.** These are child modules:
      an open floor lets a provider major break every consumer, an exact pin
      makes the module impossible to compose.
      *Verify:* review step — both bounds on every entry.
- [ ] **`.terraform.lock.hcl` committed for every `examples/` directory, and
      for no module.** A module carrying a lock constrains its consumers.
      *Verify:* `git ls-files '*/.terraform.lock.hcl'` lists only paths under
      `examples/`.
