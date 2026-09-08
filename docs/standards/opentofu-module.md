# OpenTofu module conformance checklist

Every foundations module — `opentofu/aws`, `opentofu/gcp`,
`opentofu/azure`, `opentofu/scaleway` — must pass this checklist before
it is accepted. One standard, four clouds, so that a consumer who has
adopted one can read the next without relearning anything.

**Every item below is verifiable by a command or a named review step.** An
item that cannot be checked objectively does not belong here; if you find
one, that is a defect in this document.

> **Status: draft, unapproved.** Needs a maintainer's sign-off. Two
> deliverables from the same ticket are still missing: the copyable
> module skeleton, and the reusable CI configuration. The skeleton must
> implement this checklist rather than precede it, which is why it comes
> second.

---

## 1. Structure

- [ ] **One flat root module per cloud**, at `opentofu/<cloud>/`. Network,
      cluster and identities live in the same module. No internal
      submodule tree, and no separately consumable network/cluster/IAM
      modules — the deliverable is one empty-shell cluster, and splitting
      it multiplies the combinations that have to be tested without
      serving a use case anyone asked for.
      *Verify:* `ls opentofu/*/` shows `.tf` files and no `modules/`
      directory.
- [ ] **Standard file layout.** `main.tf`, `variables.tf`, `outputs.tf`,
      `versions.tf`. Resources may be split into topic files
      (`network.tf`, `cluster.tf`, `iam.tf`) but never into a submodule.
      *Verify:* review step — the four required files exist.
- [ ] **`examples/` holds at least one minimal deployable example** that a
      consumer can copy and apply against an empty project.
      *Verify:* `test -d opentofu/<cloud>/examples/minimal`
- [ ] **`tests/` holds the module's own tests.** See section 5.
      *Verify:* `test -d opentofu/<cloud>/tests`

## 2. Interface

- [ ] **Every variable is typed.** No bare `any` unless the value is
      genuinely opaque, and then with a comment saying why.
      *Verify:* review step — no `type = any` without justification.
- [ ] **Constraints are enforced by `validation` blocks, not by
      documentation.** Anything with a known-good set of values rejects
      the rest at plan time.
      *Verify:* a `tofu test` case asserts the rejection (section 5).
- [ ] **Recommended positions are module defaults.** A consumer who sets
      nothing gets the recommended configuration.
      *Verify:* review step — the minimal example sets only what is
      genuinely per-consumer (project, region, name).
- [ ] **Decisions with no good default have no default.** Where forcing a
      choice is the point — a maintenance window, for instance — the
      variable is required. A silent default means nobody decided.
      *Verify:* review step against the cloud's research document.
- [ ] **Options we would never recommend are absent, not exposed.** An
      option in the interface is an option we support and test.
      *Verify:* review step against the cloud's research document.
- [ ] **Naming is consistent across all four clouds.** Same concept, same
      variable name; cloud-specific names only for cloud-specific
      concepts.
      *Verify:* review step — diff the variable names across
      `opentofu/*/variables.tf`.
- [ ] **Outputs expose everything needed to bootstrap the Flux-pulled
      socle**: cluster endpoint, cluster CA, OIDC issuer URL, the
      workload identity binding, and the identity the in-cluster
      Crossplane provider assumes.
      *Verify:* `tofu output` on the minimal example lists all of them.
- [ ] **No output leaks a secret.** Anything sensitive is marked
      `sensitive = true`, and long-lived credentials are not outputs at
      all.
      *Verify:* review step, plus the secret scan in section 4.

## 3. Quality

- [ ] **`tofu fmt` is clean.**
      *Verify:* `tofu fmt -check -diff -recursive opentofu/` — already
      gated in `pr-static.yaml`.
- [ ] **`tofu validate` passes on every root module.**
      *Verify:* already gated in `pr-static.yaml`.
- [ ] **TFLint passes with a per-cloud ruleset.** Each module carries a
      `.tflint.hcl` enabling that cloud's provider plugin; the generic
      ruleset alone catches almost nothing cloud-specific.
      *Verify:* `test -f opentofu/<cloud>/.tflint.hcl`, and TFLint is
      already gated in `pr-static.yaml`.
- [ ] **Generated documentation is committed and current.**
      *Verify:* `terraform-docs markdown . --output-check` exits clean.
- [ ] **pre-commit runs fmt, validate, TFLint and terraform-docs
      locally**, so CI is a safety net rather than the first feedback.
      *Verify:* `pre-commit run --all-files` exits clean.

## 4. Security

- [ ] **Trivy misconfiguration scan reports no HIGH or CRITICAL finding.**
      *Verify:* already gated in `pr-static.yaml` (SARIF to code
      scanning; fork PRs gate on HIGH/CRITICAL directly).
- [ ] **No secret is committed, in any form** — no keys, no tokens, no
      example values that look real.
      *Verify:* `trivy fs --scanners secret .` reports nothing.
- [ ] **No credential is accepted as a variable.** Modules authenticate
      through the provider's ambient credentials or workload identity
      federation, never a passed-in key.
      *Verify:* review step — no variable named or typed as a
      credential.
- [ ] **Every billable resource carries the standard label set** —
      owner, environment, and the socle version that created it — so
      that cost can be attributed and orphans can be found.
      *Verify:* review step; the label block is part of the skeleton.

## 5. Tests

Two levels, and the second one already exists.

- [ ] **Unit level: `tofu test`.** Native, no extra toolchain, no Go
      dependency for contributors. It covers what static checks cannot:
      that `validation` blocks actually reject bad input, that defaults
      resolve to the recommended configuration, and that conditional
      logic produces the intended plan.
      *Verify:* `tofu test` passes in `opentofu/<cloud>/`.
- [ ] **Every `validation` block has a test that trips it.** A validation
      nobody tested is a validation nobody knows works.
      *Verify:* review step — one failing-input case per validation.
- [ ] **Integration level: an ephemeral apply against a cloud
      emulator.** Plan-only is not enough — it does not prove the module
      converges. `integration.yaml` runs
      `init → plan → apply → destroy` against floci emulators, and each
      leg declares whether it can apply or only plan.
      *Verify:* the `Integration tests` workflow is green **and** the leg
      says `apply`.
- [ ] **GCP is plan-only today, and the reason is not ours to fix.**
      floci-gcp emulates no Compute Engine API, so the network resources
      have nowhere to be created; and the google provider segfaults
      reading back the emulator's cluster, dereferencing the cluster's
      legacy ABAC field unguarded where the emulator omits it. GCP
      convergence is therefore unproven.
      *Verify:* review step — the exception stays visible in the workflow
      summary.
- [ ] **Scaleway's gap is recorded, not silently tolerated.** No
      emulator exists, so its apply currently runs offline, which proves
      only that the module is valid while it holds no resources. Either
      a disposable project or emulator support is needed before the
      Scaleway module can claim this item.
      *Verify:* review step — this is a known exception, and it must
      stay visible in the workflow summary.

Terratest was considered and rejected: it buys more expressive
post-apply assertions at the cost of putting Go in the path of every
contributor, and the emulator apply already covers convergence.

## 6. Versioning and distribution

- [ ] **SemVer, and majors mean what they say.** Removing a variable,
      renaming an output, or changing a default in a way that forces
      replacement is a major.
      *Verify:* review step at release time.
- [ ] **Published as a cosign-signed OCI artifact**, the same way the
      socle itself is distributed. OpenTofu has consumed `oci://` module
      sources since 1.10:
      `source = "oci://<registry>/<repo>//opentofu/gcp?tag=vX.Y.Z"`.
      *Verify:* `tofu init` succeeds against the published artifact from
      a clean cache.
- [ ] **Consumers are told to pin by digest, and how to verify the
      signature themselves.** This one needs stating plainly:
      **OpenTofu does not verify OCI signatures.** It will happily pull
      an unsigned or tampered artifact. Signing is therefore only worth
      something if the consumer runs `cosign verify` — in CI, before
      `init` — or enforces it through registry policy. A checklist item
      that implied `oci://` gave us verified provenance would be selling
      a guarantee that does not exist.
      *Verify:* review step — the consumer documentation carries the
      `cosign verify` step, not just the `source` line.
- [ ] **Renovate keeps provider and action versions moving.**
      *Verify:* `renovate.json` covers the module's dependency
      manifests.

## 7. Compatibility with automation

- [ ] **Remote state lives in the consumer's own account**, and the
      module does not create or assume a backend.
      *Verify:* review step — no `backend` block in the module; the
      example documents one.
- [ ] **A single `tofu apply` converges with no interactive input and no
      out-of-band step.** No local scripts, no manual console click, no
      `kubectl` in the middle.
      *Verify:* the integration workflow already applies with
      `-input=false -auto-approve`.
- [ ] **Runnable by an isolated CI runner** holding only the roles the
      apply needs.
      *Verify:* review step — the consumer documentation lists those
      roles.
- [ ] **Idempotent.** A second apply plans no changes.
      *Verify:* add `tofu plan -detailed-exitcode` after the integration
      apply; exit code 0 means no drift, 2 means this item fails.

## 8. Provider and OpenTofu compatibility

- [ ] **`required_version` has a floor that reflects what the module
      actually needs.** OCI module distribution (section 6) requires
      OpenTofu **1.10 or later**, so `>= 1.10` is the floor. The
      existing modules declare `>= 1.8` and must be raised.
      *Verify:* `grep required_version opentofu/*/versions.tf`
- [ ] **Provider constraints are bounded ranges, not open floors.** These
      modules are consumed through a `module` block, so they are child
      modules: they must declare a range with an **upper bound**
      (`>= 6.0, < 7.0`) and must not pin an exact version, which would
      make them impossible to compose. The present `>= 6.0` is the
      defect — it is unbounded, so a provider major release can break
      every consumer without anything changing in this repo.
      *Verify:* review step — every entry in `required_providers` has
      both bounds.
- [ ] **`.terraform.lock.hcl` is committed for every `examples/`
      directory, and for no module.** Examples are root modules and
      should be reproducible; the module itself must not carry a lock, or
      it constrains its consumers.
      *Verify:* `git ls-files '*/.terraform.lock.hcl'` lists only paths
      under `examples/`.
- [ ] **The support matrix is documented and tested.** The OpenTofu and
      provider versions the module is tested against are stated, and CI
      tests the floor, not only the latest.
      *Verify:* review step — the matrix exists and the integration
      workflow covers the declared floor.

---

## Known gaps in this checklist

Stated rather than left for a reviewer to discover:

- **The skeleton and the reusable CI configuration do not exist yet.** The
  ticket asks for all three, and the acceptance criterion "the template
  itself passes the checklist" cannot be met until the skeleton is
  written.
- **Several items are review steps, not commands.** Naming consistency,
  default appropriateness and label coverage resist automation. They are
  honest review steps rather than fake automation, but they depend on a
  reviewer applying them consistently.
- **Nothing here checks that a module's decisions match its cloud's
  research document.** That link is currently a review step pointing at
  a document, which is weaker than it sounds.
