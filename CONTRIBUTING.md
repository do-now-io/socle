# Contributing to the socle

Thank you for helping. This file is the one place that says how the
repository works for a contributor: what lives where, what each check proves,
how the documentation is organised and how a release is cut. The
documentation site renders it as its *Contributing* page.

## How to contribute

- **Something is missing or wrong?** Open an
  [issue](https://github.com/do-now-io/socle/issues/new) and the maintainers
  take it from there.
- **You know the fix?** Open a pull request directly. A documentation fix
  needs no issue first; every page of the site has an *Edit this page* link
  to its source.
- **A security problem?** Never in a public issue: see [SECURITY.md](SECURITY.md).

Commits follow [Conventional Commits](https://www.conventionalcommits.org/):
`type(scope): what changes`, for example `fix(catalog): …` or `docs(aws): …`.
The type is not decoration: it is what names the next version (see
[Releases](#releases)).

## Repository layout

```
opentofu/
├── aws/  gcp/  azure/  scaleway/   # foundations, one module per cloud
├── bootstrap/                      # Cilium, Flux Operator, inputs, catalog.tf
└── clusters/aws/                   # the root a client copies: one apply
oci/
├── catalog/<module>/               # one ResourceSet + its Chainsaw suite (tests/e2e)
├── clusters/<cloud>/               # which modules each cloud offers
├── tests/e2e/                      # the socle's own suites: root, disabled, destroyed
└── .ci/                            # fixtures CI renders the catalog and the envelope with
docs/                               # the documentation, rendered by site/
site/                               # the site's generator: Astro + Starlight
.github/
├── workflows/                      # the checks below
├── actions/e2e-cluster/            # brings a floci cluster up and down for an e2e job
├── scripts/                        # what the workflows run; runnable locally
└── e2e/<cloud>/                    # one e2e fixture root per cloud
```

## Local tooling

| Tool | For |
| --- | --- |
| [OpenTofu](https://opentofu.org/) 1.10 or later | `tofu fmt`, `validate`, `test` on every module under `opentofu/` |
| [TFLint](https://github.com/terraform-linters/tflint) | the per-cloud rulesets (`.tflint.hcl` in each module) |
| [terraform-docs](https://terraform-docs.io/) 0.20 | the reference between `BEGIN_TF_DOCS` and `END_TF_DOCS` in each module README |
| [Trivy](https://trivy.dev/) | misconfiguration and secret scans |
| yamllint | every YAML file, strict (`.yamllint.yaml`) |
| [flux-operator](https://fluxoperator.dev/) CLI, Helm, kubeconform | rendering and validating the catalog |
| [Chainsaw](https://kyverno.github.io/chainsaw/) | the e2e suites under `oci/catalog/<module>/tests/e2e` |
| Node.js 24 | the documentation site (`site/`) |

The scripts under `.github/scripts/` run as they do in CI, from anywhere in
the repository: `check-version.sh`, `check-catalog-clouds.sh`.

## What each check proves

| Workflow | When | What a green run proves |
| --- | --- | --- |
| `pr-static.yaml` | every PR, every push to `main` | YAML and workflows lint clean; `VERSION` is stamped everywhere; `catalog.tf` and the cloud overlays agree and every module ships its e2e suite; every OpenTofu module formats, validates, passes `tofu test` and TFLint, and its terraform-docs block is current; the catalog renders and kubeconforms strictly, and every cloud overlay builds with kustomize; no secret is committed. Trivy's misconfiguration findings: on same-repo PRs and pushes the SARIF is uploaded and the gate is the **Code scanning results / Trivy** check; only on fork PRs does the job itself fail on HIGH/CRITICAL |
| `integration.yaml` | every PR, every push to `main` | each foundations module plans against a cloud emulator: [floci](https://floci.io) for AWS, floci-gcp, floci-az; Scaleway, which has no emulator, plans its minimal example offline. The Azure leg is `continue-on-error`: floci-az's certificate fails Go's x509 validation. A plan, not an apply |
| `docs.yaml` | every PR, forks included | the documentation site builds in strict mode: no broken internal link or anchor, no page outside the navigation, no include that does not resolve |
| `pages.yaml` | every push to `main`, every PR event, after every run of `publish-artifact.yaml` | the site is deployed: the last release at the root, `main` under `/dev/`, and a preview of each open PR from a branch of this repository under `/pr/<N>/`, linked from a comment on the PR |
| `publish-artifact.yaml` | every push, every branch | both packages are pushed to GHCR and signed; the artifact converges on floci's k3s through `e2e.yaml` (one job per module and cloud, each ending in `tofu destroy`). On `main` only: release-please refreshes its PR, and on the release, `promote` tags the alpha |
| `cleanup-artifacts.yaml` | branch deletion, manual dispatch, nightly | pre-release tags are deleted: a branch's when it goes or after 7 days, alphas after 30. Release tags are never touched |
| `renovate.yaml` | hourly, Dependency Dashboard edits | dependency updates, opened only once their box is ticked on the dashboard. Skipped until the `RENOVATE_APP_ID` variable and the `RENOVATE_APP_PRIVATE_KEY` secret exist |
| `scorecard.yaml` | weekly, every push to `main` | the OpenSSF Scorecard of the repository |

Workflows follow the same rules everywhere: actions pinned by commit SHA,
the least `permissions:` each job needs, `persist-credentials: false` on
checkout, and `shell: bash` so that a failure on the left of a pipe fails the
step. Runners are `ubuntu-24.04`, pinned rather than `ubuntu-latest`, so a
runner image change is a deliberate one-line commit.

`publish-artifact.yaml` runs once at a time on `main`, never cancelled, so an
alpha, its proofs, the release PR and a promotion never interleave. On any
other branch a new push cancels the run in flight: the proof of a replaced
commit is worth nothing.

**`e2e` is the one e2e context a ruleset can require.** The e2e matrix is
discovered, so its job names cannot be listed in a ruleset; the `e2e` job
needs every other job and is red if any of them is. The `protect-main`
ruleset requires the five static checks (yamllint, actionlint, OpenTofu,
kubeconform, Trivy), not `e2e`. Each e2e job publishes a JUnit report: the
Checks tab shows one check per job, the failing step named.

## Testing

Three levels:

1. **Static**, in `pr-static.yaml`: `tofu test` on every module that has
   tests, one failing case per `validation` block, defaults and normalisation
   with mocked providers; the renders kubeconformed. Unit tests are
   `tofu test`, not Terratest: no Go in a contributor's path.
2. **Integration**, in `integration.yaml`: a plan of each foundations module
   against an emulator.
3. **e2e**, in `e2e.yaml`, called by `publish-artifact.yaml` with the tag it
   just pushed: the artifact applied on floci 2.1.0's real k3s, proven by
   [Chainsaw](https://kyverno.github.io/chainsaw/).

The e2e jobs:

- **`root (<cloud>)`** applies the real `opentofu/clusters/<cloud>` once with
  `.github/e2e/<cloud>/floci.tfvars`, runs the socle's `root` suite and every
  module's `health` tests, uninstalls the socle, asserts the cluster empty,
  and destroys it.
- **`<module> (<cloud>)`**, one per module the cloud's overlay deploys,
  applies the bare fixture root `.github/e2e/<cloud>/`, runs the `root` suite
  and the module's `health` tests, then its `module` tests alone, then turns
  the module off and on through `tofu apply` with a second plan that must be
  empty, then uninstalls the socle and destroys the cluster.

What a module's suite holds, its labels, and the habits every suite keeps
are in the [Catalog module standard](docs/reference/catalog-module-standard.md).
`.github/actions/e2e-cluster` is the only shell in the e2e: it brings floci
up and tears it down.

What floci cannot prove, and the e2e therefore does not claim:

- **One node, flannel, kube-proxy and CoreDNS already there.** Every root it
  applies sets `cilium.enabled = false`; Cilium, ENI IPAM and Gateway API on
  Cilium are not exercised.
- **No EKS add-on API** in floci 2.1.0: the add-ons are off on both fixture
  roots, and Pod Identity is not served.
- **IAM is accepted, not enforced**: a role reaches floci's IAM, its
  permissions are not tested.
- **A second apply of the real root fails**: floci does not read back several
  EKS attributes (logging, encryption config, upgrade policy). Hence one
  apply in the `root` job, and a bare fixture root for the mutations.
- **floci 2.x specifics**: the EKS token webhook rejects the `test`/`test`
  key, so the action registers an IAM user first; floci refuses a presigned
  token after 60 s, so Chainsaw's kubeconfig carries a ServiceAccount token;
  a pod reaches floci at the container's IP (`FLOCI_IP`), not at
  `localhost`.

## Documentation

The documentation lives in `docs/` and is published at
<https://do-now-io.github.io/socle/>: the last release at the root, `main`
under [`/dev/`](https://do-now-io.github.io/socle/dev/), and every open pull
request from a branch of this repository under `/pr/<N>/`, linked from a
comment on the PR. The site itself is in `site/`; it reads `docs/` and holds
no content of its own.

### The structure

Every page is **one** of four kinds ([Diátaxis](https://diataxis.fr/)), and
the folder says which:

| Folder | Kind | For a reader who wants to… |
| --- | --- | --- |
| `getting-started/` | tutorial | go from zero to a converged cluster, one page per cloud |
| `guides/` | how-to | get one task done: configure, enable a module, upgrade, uninstall |
| `architecture/` | explanation | understand how the parts fit together, and why |
| `reference/` | reference | look something up: inputs, artifacts, compatibility, the standards |
| `clouds/<cloud>/` | per cloud | know what the socle builds on that cloud: `index`, `prerequisites`, `foundations`, `limits` |
| `catalog/` | per module | know what a module installs, what it may be given, and what it needs |
| `decisions/` | decision records, not published on the site | know what was decided, when, and whether it still holds |

### The rules

1. **One page, one reader, one type.** If a page needs both "do this" and
   "here is why", split it and link the two.
2. **Generated content stays next to the code and is included, never
   copied.** The terraform-docs blocks remain in `opentofu/**/README.md`, kept
   current by `pr-static.yaml`. A page pulls one in with
   `::include{file="opentofu/aws/README.md" section="tf-docs"}`; without
   `section`, the whole file comes in, minus its title. This page is
   `CONTRIBUTING.md`, included that way.
3. **Decisions are grouped in `docs/decisions/<group>.md`**: one file per
   cloud, one per catalog module, and `socle.md` for the rest. Each decision
   is a `##` section `<GROUP>-NN`, numbered within its file, never renumbered
   or reused, with its status (`accepted` only when the code implements it,
   `proposed` otherwise, `superseded by <GROUP>-NN` when the code no longer
   follows it), its date, context, decision, consequences (including cost)
   and sources. An accepted section is never edited, except to mark it
   superseded; a changed decision is a new section. A new file starts from
   [`docs/decisions/_template.md`](https://github.com/do-now-io/socle/blob/main/docs/decisions/_template.md). The site
   publishes none of `docs/decisions/`, and no published page links to it:
   a page states what holds, the decision file keeps why.
4. **No working notes in `docs/`.** Questions for a reviewer, session logs and
   "what I measured today" go in the issue or the pull request. A measurement
   that stays true, such as the convergence time of a module, goes in the
   page under *Measured*, dated.
5. **The four clouds have the same pages under the same names.** Where a page
   does not apply to a cloud, it says so in one line rather than being left
   out.
6. **A catalog module ships its page.** `catalog/<module>.md` is part of the
   module, like its `resourceset.yaml`, its `catalog.tf` entry and its tests.
   It starts from [`docs/catalog/_template.md`](https://github.com/do-now-io/socle/blob/main/docs/catalog/_template.md) and
   its frontmatter carries `description`, `category` and `requires`, which
   feed the catalog's overview.
7. **File names are kebab-case, without a cloud or product prefix**: the
   folder already says `aws`.
8. **The site build is a pull request check, in strict mode.** A broken
   internal link or anchor, a page outside the navigation or an include that
   does not resolve fails it.

### Writing a page

- Every page starts with frontmatter: a `title` and a one-line `description`.
- Link with **relative paths to the Markdown file**, as GitHub resolves them:
  `[upgrade](../guides/upgrade.md)`. The site turns a link to one of its pages
  into that page's address, and a link to any other file of the repository
  into its address on GitHub, at the version being read.
- The landing page is not in `docs/`: it is `site/src/pages/index.astro`,
  and its module list is read from `catalog.tf` at build time.
- A socle version in an example (`socle_version = "…"`) is the last release,
  never a version picked by hand. End its line with
  `# x-release-please-version` and list the file under `extra-files` in
  `release-please-config.json`: release-please then rewrites it with every
  other stamp. `check-version.sh` fails on an annotated line that drifts from
  `VERSION`, or whose file release-please does not list.
- The navigation follows the folders. A page's place within its folder is
  `sidebar.order` in its frontmatter.
- To preview the site:

  ```sh
  cd site
  npm ci
  npm run dev       # http://localhost:4321/socle/dev/
  npm run build     # the strict build CI runs
  ```

## Releases

Nobody types a version. `VERSION` is the last release, and the next one is
read from the conventional commits since it: a `Release-As: X.Y.Z` footer
wins; otherwise a breaking change (`type!:` or a `BREAKING CHANGE:` footer)
bumps the minor before 1.0.0 and the major after, `feat` the minor, anything
else the patch. `1.0.0` is therefore only ever reached through a
`Release-As: 1.0.0` footer. The first release is `0.1.0`, the config's
`initial-version`.

1. Every push to `main` publishes `<next>-alpha.N`, signed, and proves it on
   floci (`publish-artifact.yaml`). Commits of the types release-please hides
   from the changelog (`chore`, `docs`, `refactor`, `ci`, …) open no release
   PR on their own, but their alphas still publish.
2. release-please keeps one release PR open. It only advances to a commit
   whose alpha passed the proofs, and it carries the changelog and every
   version stamp.
3. **Merging that PR is the release.** release-please tags the commit and
   publishes the GitHub release, and `promote` gives the alpha that same push
   produced the version as a second tag: same digest, same signature, nothing
   rebuilt. `.github/scripts/release.sh` refuses when the tag is not the
   commit's `VERSION`, when no alpha was built from the commit, and when the
   version already exists as another digest; re-running it after a partial
   promotion finishes the job. The documentation site then rebuilds its root
   from that tag.

What this needs from the repository and from you:

- **Settings → Actions → General → "Allow GitHub Actions to create and
  approve pull requests"**: release-please opens its PR with the workflow
  token.
- **Rebase merges only.** Every commit must land on `main` with its own
  conventional message: a merge commit, or a squash titled otherwise, is
  invisible to the version bump.
- **Wait for `e2e` before merging a PR.** Merging deletes the branch, and
  `cleanup-artifacts.yaml` then deletes its branch tags within seconds,
  including the one the PR's e2e jobs still pull: a job still running fails
  on `MANIFEST_UNKNOWN`. Branch names that slugify alike (`feat-x` and
  `feat/x`) share their tags: deleting one deletes the other's.
- **Do not rename `publish-artifact.yaml`.** Its path is part of the signed
  subject; every deployed `cosign_identity` would stop matching.

The design is in [Distribution](docs/architecture/distribution.md); the
decisions are in [Socle decisions](docs/decisions/socle.md).
