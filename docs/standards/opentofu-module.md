# OpenTofu module conformance checklist

Every foundations module must pass this before it is accepted. **Every item is
verifiable by a command or a named review step** — an item that cannot be
checked objectively does not belong here.

> **Status: draft, unapproved.** The copyable module skeleton and the reusable
> CI configuration are still missing. The skeleton has to implement this
> checklist rather than precede it.

---

## 1. Structure

- [ ] **One flat root module per cloud**, at `opentofu/<cloud>/`. Network,
      cluster and identities in the same module — splitting it multiplies the
      combinations to test without serving a use case anyone asked for.
      *Verify:* `ls opentofu/*/` shows `.tf` files and no `modules/`.
- [ ] **Standard file layout:** `main.tf`, `variables.tf`, `outputs.tf`,
      `versions.tf`. Resources may be split into topic files
      (`network.tf`, `cluster.tf`, `iam.tf`) but never into a submodule.
      *Verify:* review step — the four files exist.
- [ ] **`examples/` holds at least one minimal deployable example** a consumer
      can copy and apply against an empty project.
      *Verify:* `test -d opentofu/<cloud>/examples/minimal`
- [ ] **`tests/` holds the module's own tests.** See section 4.
      *Verify:* `test -d opentofu/<cloud>/tests`

## 2. Interface

- [ ] **Every variable is typed.** No bare `any` unless the value is genuinely
      opaque, and then with a comment saying why.
      *Verify:* review step.
- [ ] **Constraints are enforced by `validation` blocks, not documentation.**
      *Verify:* a `tofu test` case asserts the rejection (section 4).
- [ ] **Recommended positions are module defaults.** A consumer who sets
      nothing gets the recommended configuration.
      *Verify:* review step — the minimal example sets only what is genuinely
      per-consumer.
- [ ] **Decisions with no good default have no default.** Where forcing a
      choice is the point — a maintenance window, for instance — the variable
      is required. A silent default means nobody decided.
      *Verify:* review step against the cloud's research document.
- [ ] **Options we would never recommend are absent, not exposed.** An option
      in the interface is an option we support and test.
      *Verify:* review step against the cloud's research document.
- [ ] **Naming is consistent across clouds.** Same concept, same variable
      name; cloud-specific names only for cloud-specific concepts.
      *Verify:* review step — diff the variable names across
      `opentofu/*/variables.tf`.
- [ ] **Outputs expose everything needed to bootstrap the Flux-pulled
      socle:** cluster endpoint, cluster CA, OIDC issuer, the workload
      identity binding, and the identity the in-cluster provider assumes.
      *Verify:* `tofu output` on the minimal example lists all of them.

## 3. Quality and security

- [ ] **`tofu fmt` is clean** and **`tofu validate` passes on every root
      module.**
      *Verify:* already gated in `pr-static.yaml`.
- [ ] **TFLint passes with a per-cloud ruleset.** Each module carries a
      `.tflint.hcl` enabling that cloud's provider plugin; the generic ruleset
      alone catches almost nothing cloud-specific.
      *Verify:* `test -f opentofu/<cloud>/.tflint.hcl`, and TFLint is gated in
      `pr-static.yaml`.
- [ ] **Generated documentation is committed and current.**
      *Verify:* `terraform-docs markdown . --output-check` exits clean.
- [ ] **Trivy reports no HIGH or CRITICAL finding**, and any ignored check
      carries its reason in the code.
      *Verify:* already gated in `pr-static.yaml`.
- [ ] **No secret is committed, and no credential is accepted as a
      variable.** Modules authenticate through ambient credentials or workload
      identity federation, never a passed-in key.
      *Verify:* `trivy fs --scanners secret .`, plus a review step on the
      variable list.

## 4. Tests

Two levels.

- [ ] **Unit: `tofu test`.** Native, no extra toolchain, no Go in a
      contributor's path. It covers what static checks cannot — that
      `validation` blocks reject bad input, that defaults resolve to the
      recommended configuration, and that conditional logic plans as intended.
      *Verify:* `tofu test` passes in `opentofu/<cloud>/`.
- [ ] **Every `validation` block has a test that trips it.** A validation
      nobody tested is a validation nobody knows works.
      *Verify:* review step — one failing-input case per validation.
- [ ] **Integration: an ephemeral apply against a cloud emulator.** Plan-only
      does not prove the module converges. Each leg of `integration.yaml`
      declares whether it applies or only plans.
      *Verify:* the workflow is green **and** the leg says `apply`.
- [ ] **Legs that cannot apply say why, in the workflow summary.** Scaleway
      has no emulator; GCP's emulator has no Compute Engine API and crashes
      the google provider on cluster read-back. Both are recorded exceptions,
      not silent ones.
      *Verify:* review step — the caveat is visible on every run.

Terratest was considered and rejected: more expressive post-apply assertions,
at the cost of putting Go in every contributor's path, and the emulator apply
already covers convergence.

## 5. Versioning and distribution

- [ ] **SemVer, and majors mean what they say.** Removing a variable,
      renaming an output, or changing a default in a way that forces
      replacement is a major.
      *Verify:* review step at release time.
- [ ] **Published as a cosign-signed OCI artifact**, the way the socle itself
      is distributed:
      `source = "oci://<registry>/<repo>//opentofu/<cloud>?tag=vX.Y.Z"`.
      *Verify:* `tofu init` succeeds against the published artifact from a
      clean cache.
- [ ] **Consumers are told to pin by digest, and how to verify the signature
      themselves.** **OpenTofu does not verify OCI signatures** — it will pull
      an unsigned or tampered artifact. Signing is only worth something if the
      consumer runs `cosign verify` before `init`, or enforces it through
      registry policy.
      *Verify:* review step — the consumer documentation carries the
      `cosign verify` step, not just the `source` line.
- [ ] **Renovate keeps provider and action versions moving.**
      *Verify:* `renovate.json` covers the module's dependency manifests.

## 6. Compatibility with automation

- [ ] **Remote state lives in the consumer's own account**, and the module
      neither creates nor assumes a backend.
      *Verify:* review step — no `backend` block in the module; the example
      documents one.
- [ ] **A single `tofu apply` converges with no interactive input and no
      out-of-band step.** No local scripts, no console click, no `kubectl` in
      the middle. Where a cloud makes this impossible, the exception is
      documented in the module README.
      *Verify:* the integration workflow applies with
      `-input=false -auto-approve`.
- [ ] **Runnable by an isolated CI runner** holding only the roles the apply
      needs.
      *Verify:* review step — the example lists those roles.
- [ ] **Idempotent.** A second plan is empty.
      *Verify:* `tofu plan -detailed-exitcode` after the integration apply.

## 7. Provider and OpenTofu compatibility

- [ ] **`required_version` has a floor that reflects what the module actually
      needs.** OCI module distribution sets it.
      *Verify:* `grep required_version opentofu/*/versions.tf`
- [ ] **Provider constraints are bounded ranges.** These are child modules: an
      open floor lets a provider major break every consumer, and an exact pin
      makes the module impossible to compose. Both bounds, always.
      *Verify:* review step — every entry in `required_providers` has both.
- [ ] **`.terraform.lock.hcl` is committed for every `examples/` directory,
      and for no module.** Examples should be reproducible; a module carrying
      a lock constrains its consumers.
      *Verify:* `git ls-files '*/.terraform.lock.hcl'` lists only paths under
      `examples/`.

---

## Known gaps

- **The skeleton and the reusable CI configuration do not exist yet**, so the
  acceptance criterion "the template itself passes the checklist" cannot be
  met.
- **Several items are review steps, not commands.** Naming consistency and
  default appropriateness resist automation; they are honest review steps
  rather than fake automation.
- **Nothing here checks that a module's decisions match its cloud's research
  document.** That link is a review step pointing at a document, which is
  weaker than it sounds.
