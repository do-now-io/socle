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
├── catalog/<module>/               # one ResourceSet + its Chainsaw suite
└── clusters/<cloud>/               # which modules each cloud offers
docs/                               # the documentation, rendered by site/
site/                               # the site's generator: Astro + Starlight
.github/
├── workflows/                      # the checks below
├── scripts/                        # what the workflows run; runnable locally
└── e2e/<cloud>/                    # one e2e fixture root per cloud
```

## Local tooling

| Tool | For |
| --- | --- |
| [OpenTofu](https://opentofu.org/) | `tofu fmt`, `validate`, `test` on every module under `opentofu/` |
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
| `pr-static.yaml` | every PR, every push to `main` | YAML and workflows lint clean; `VERSION` is stamped everywhere; `catalog.tf` and the cloud overlays agree and every module ships its e2e suite; every OpenTofu module formats, validates, passes `tofu test` and TFLint, and its terraform-docs block is current; the catalog renders and kubeconforms strictly; Trivy finds no HIGH/CRITICAL misconfiguration and no secret |
| `integration.yaml` | every PR, every push to `main` | every OpenTofu root plans against a cloud emulator ([floci](https://floci.io)) for AWS, GCP and Azure; Scaleway, which has no emulator, plans its minimal example |
| `docs.yaml` | every PR, forks included | the documentation site builds in strict mode: no broken internal link or anchor, no page outside the navigation, no include that does not resolve |
| `pages.yaml` | every push to `main`, every PR event, after every run of `publish-artifact.yaml` on `main` | the site is deployed: the last release at the root, `main` under `/dev/`, and a preview of each open PR from a branch of this repository under `/pr/<N>/`, linked from a comment on the PR |
| `publish-artifact.yaml` | every push | `oci/` is pushed to GHCR and signed; on `main`, the artifact converges on floci's k3s through `e2e.yaml` (one job per module and cloud, each ending in `tofu destroy`), then release-please refreshes its PR |
| `cleanup-artifacts.yaml` | branch deletion, nightly | pre-release tags are deleted: a branch's when it goes or after 7 days, alphas after 30. Release tags are never touched |
| `renovate.yaml` | hourly, Dependency Dashboard edits | dependency updates, opened only once their box is ticked on the dashboard |
| `scorecard.yaml` | weekly, every push to `main` | the OpenSSF Scorecard of the repository |

Workflows follow the same rules everywhere: actions pinned by commit SHA,
the least `permissions:` each job needs, `persist-credentials: false` on
checkout, and `shell: bash` so that a failure on the left of a pipe fails the
step.

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
| `decisions/` | decision records | know what was decided, when, and whether it still holds |

### The rules

1. **One page, one reader, one type.** If a page needs both "do this" and
   "here is why", split it and link the two.
2. **Generated content stays next to the code and is included, never
   copied.** The terraform-docs blocks remain in `opentofu/**/README.md`, kept
   current by `pr-static.yaml`. A page pulls one in with
   `::include{file="opentofu/aws/README.md" section="tf-docs"}`; without
   `section`, the whole file comes in, minus its title. This page is
   `CONTRIBUTING.md`, included that way.
3. **Every decision is a record** in `decisions/NNNN-<slug>.md`, started
   from the [template](docs/decisions/template.md): status (`proposed`,
   `accepted`, `superseded`), date, context, decision, consequences
   (including cost) and sources. Once accepted, a record is not edited; a new
   one supersedes it. A cloud's `index.md` summarises its records and links
   to them.
4. **No working notes in `docs/`.** Questions for a reviewer, session logs and
   "what I measured today" go in the issue or the pull request. A measurement
   that stays true, such as the convergence time of a module, goes in the
   module page under *Measured*, dated.
5. **The four clouds have the same pages under the same names.** Where a page
   does not apply to a cloud, it says so in one line rather than being left
   out.
6. **A catalog module ships its page.** `catalog/<module>.md` is part of the
   module, like its `resourceset.yaml`, its `catalog.tf` entry and its tests.
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
read from the conventional commits since it: a breaking change bumps the
minor before 1.0.0, `feat` the minor, anything else the patch; a
`Release-As: X.Y.Z` footer wins.

1. Every push to `main` publishes `<next>-alpha.N`, signed, and proves it on
   floci (`publish-artifact.yaml`).
2. release-please keeps one release PR open. It only advances to a commit
   whose alpha passed the proofs, and it carries the changelog and every
   version stamp.
3. **Merging that PR is the release.** release-please tags the commit and
   publishes the GitHub release, and the alpha that same push produced gets
   the version as a second tag: same digest, same signature, nothing rebuilt.
   The documentation site then rebuilds its root from that tag.

The full design is in [the Flux catalog](docs/flux-catalog.md#7-publishing-the-artifact-and-releasing)
and [Distribution](docs/distribution.md).
