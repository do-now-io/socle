# Flux catalog — one apply, one tfvars, one version

How a client gets a cluster running the socle, chooses its modules and sets
their values, and how one version bump moves the whole estate. One design for
EKS, GKE, AKS and Kapsule.

> **Status: design, v1 in progress.** Every position below was measured on a
> real cluster — floci-backed k3s, on 2026-09-21 and while building on
> 2026-09-22 — unless marked *to verify*.

| Question | Position |
| --- | --- |
| Where the client's config lives | In the client's Git, as OpenTofu: one root per cloud, one tfvars per cluster |
| What Flux syncs from | The socle OCI artifact only — never a client repository |
| Who templates | Flux Operator, through `ResourceSet`s shipped in the artifact |
| What OpenTofu ships into the cluster | Inputs only: one `ResourceSetInputProvider`, one root `ResourceSet` |
| How OpenTofu ships them | A `helm_release` over a folder of two literal manifests — Helm as applier, never as templater |
| Number of applies | One. Foundations and bootstrap in the same root |
| The client's config surface | `socle_version`, `<cloud> = {…}`, `kube = {…}` |
| Validation of `kube` | `any` plus `validation` blocks against the catalog schema — at plan |
| Version pin | `socle_version` in the tfvars drives both module sources and the artifact tag |
| Artifact from `main` | `<next>-alpha.N` on every push, `<next>` read from the conventional commits since the last release; merging release-please's PR re-tags that alpha as the release, cosign keyless |
| Artifact from a branch | A pre-release tag `0.0.0-<branch>.<sha>`, deletable, signed by the branch |
| CI convergence proof | Two jobs in `publish-artifact.yaml`: `e2e-aws-root` applies the real `opentofu/clusters/aws` on floci once and asserts convergence; `e2e-aws-catalog` applies a bare fixture root and runs the mutations, because floci cannot re-apply the real one |

## 1. Three roles, never mixed

| Role | Owner | Holds |
| --- | --- | --- |
| Inputs | OpenTofu, in the client's root | cloud, cluster identity, socle version, `kube` |
| Templates | The socle OCI artifact | one `ResourceSet` per catalog module, per-cloud overlays |
| Rendering | Flux Operator, in the cluster | reads the inputs, renders, reconciles, garbage-collects |

The OpenTofu module knows the catalog only as a schema. The artifact knows
nothing about any client. The operator joins the two with its native API.

**Why not the FluxInstance `sync` block.** It has no `verify` field
(`api/v1/fluxinstance_types.go`, v0.60.0) and `kustomize.patches` never reach
the generated sync objects — a patch that misses stalls the whole instance
while the apply reports green. Measured in PR #28. So the root source is an
object of ours, and making it a `ResourceSet` puts it under the operator's
inventory, drift correction and garbage collection.

**Why not a Git repository per client.** The socle is one signed artifact; a
client repository would add a distribution channel, a write-scoped token per
client and a second place where composition lives.

## 2. What the client writes

One root per cloud, copied from `opentofu/clusters/<cloud>/` and never edited.
One tfvars per cluster:

```hcl
# clusters/prod.tfvars
socle_version = "1.4.2"           # the only line an upgrade touches

aws = {
  region             = "eu-west-3"
  cluster_name       = "acme-prod"
  owner              = "platform"
  environment        = "prod"
  availability_zones = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/24"]
  kubernetes_version = "1.34"
}

kube = {
  cert_manager = { acme_email = "ops@acme.example" }
  external_dns = { domain_filters = ["acme.example"] }
  monitoring   = { enabled = false }
}
```

The `kube` block shows the target catalog; in v1 the catalog holds the
`hello` module only (§10).

Rules the root enforces:

- **`socle_version` is a variable in both module sources — in a client's
  copy.** The modules are published separately from the socle artifact (PR
  #15, one OCI tag cannot carry both shapes), so a client's copy reads:
  `source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/aws?tag=${var.socle_version}"`
  and
  `source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/bootstrap?tag=${var.socle_version}"`.
  OpenTofu ≥ 1.8 resolves both at init from the tfvars (measured with
  1.12.6). A bump is one line and a `tofu init`, which every pipeline runs
  anyway. In the repository, `opentofu/clusters/aws` uses relative sources
  instead, so CI applies it straight from a checkout; the `?tag=` form is
  what a client's copy puts on both sources. The socle artifact itself stays
  at `ghcr.io/do-now-io/socle/flux-modules` (§7).
- **`<cloud>` is a typed object** mirroring the foundations module's
  variables; the root passes them through one by one. Nothing is renamed.
  `aws.kubernetes_version` is required — the foundations module has no
  default for it.
- **`kube` lists only what differs from the catalog's defaults.** A module
  absent from `kube` is at its default, enabled or not as the catalog says.
- **Names are `snake_case`** because that is what HCL writes without quotes.
  The artifact reads `inputs.modules.cert_manager` as-is; Kubernetes object
  names stay `kebab-case` in the templates.
- **The root commits its `.terraform.lock.hcl`**, like the examples do.

### What a typo looks like

```
kube = { cert_manger = {…} }
→ Error: kube: unknown module(s) cert_manger. Catalog: cert_manager, external_dns, monitoring.
kube = { cert_manager = { acme_mail = "x" } }
→ Error: kube.cert_manager: unknown attribute acme_mail. Allowed: enabled, acme_email.
```

**Measured: an `object({…})` type does not do this.** OpenTofu silently drops
unknown attributes when converting to an object type — `podinfoo = {}` and
`replica = 3` both planned as "No changes". `kube` is not `map(any)` either:
a map refuses two modules whose attributes differ — "all map elements must
have the same type" (measured, OpenTofu 1.12.6) — the moment, say,
`cert_manager` and `monitoring` disagree on keys. `kube` is therefore `any`,
validated by `validation` blocks against the catalog schema held in a local.
terraform-docs shows `any`; the README documents the schema.

## 3. What OpenTofu deposits — `opentofu/bootstrap`

One module, no cloud provider, `helm` only. Three releases, in order:

1. **`flux-operator`** — the official chart, exact version pin (pre-1.0).
2. **`flux-instance`** — the official chart, health check on, **no `sync`**.
   `cluster.type` is the only per-cloud value.
3. **`socle`** — `${path.module}/manifests/`, a Helm envelope of two literal
   objects. The only Helm expression in it is `toYaml .Values.inputs`.

```yaml
# manifests/templates/inputs.yaml — the client's config, as OpenTofu validated it
kind: ResourceSetInputProvider
metadata: { name: socle, namespace: flux-system }
spec:
  type: Static
  defaultValues:
    {{- toYaml .Values.inputs | nindent 4 }}
```

```yaml
# manifests/templates/root.yaml — what the cluster pulls, written once
kind: ResourceSet
metadata: { name: socle-root, namespace: flux-system }
spec:
  inputsFrom: [{ kind: ResourceSetInputProvider, name: socle }]
  wait: true
  resourcesTemplate: |
    kind: OCIRepository            # url, tag from inputs; << if inputs.socle.pullSecret >>secretRef<< end >>; verify: cosign with the release identity
    ---
    kind: Kustomization            # path ./clusters/<< inputs.cloud >>, prune, wait
```

The `<< >>` syntax belongs to the operator, not Helm. Helm deposits the file
as-is. **`resourcesTemplate`, not `resources`:** the optional `secretRef` on
the `OCIRepository` only exists when `artifact_pull_secret` is set, and the
operator's block `<< if >>`/`<< end >>` — spanning a whole key, added or
dropped structurally — is not valid YAML inside the structured `resources`
list, whose entries the operator parses before it ever templates them. The
root therefore writes the two objects as a raw multi-document YAML string,
templated as text first, parsed after. Content and order are otherwise
unchanged, and CI still kubeconforms the render strictly (§8).

**Why Helm at all.** Flux reads the Kubernetes API and nothing else; the
first object it acts on must come from outside. Of OpenTofu's ways to write a
Kubernetes object, only `helm_release` applies a custom resource without the
cluster or its CRDs existing at plan time. `kubernetes_manifest` needs both
and breaks a single-root first apply; `local-exec kubectl` is the out-of-band
step the README forbids. The official ControlPlane bootstrap module reaches
the same conclusion and ships a chart for the same reason.

**The envelope's chart version equals `VERSION`.** Measured: the helm
provider does not re-apply a local chart whose templates changed unless its
version or its values changed — a template fix would never propagate
otherwise. Hence `manifests/Chart.yaml`'s version tracks `VERSION`, checked
by `.github/scripts/check-version.sh` together with every module's
`local.socle_version`.

**Every defaulted variable of `opentofu/aws` and `opentofu/bootstrap`
declares `nullable = false`** (except where the default is itself null:
`vpc_id`, `secrets_encryption_kms_key_arn`, `socle_version`, where the
declaration would be a no-op). A root that groups its inputs in an object
(`aws = {…}`, `kube = {…}`) passes an omitted key as an explicit `null`, and
OpenTofu keeps that null — the child module's default is *not* applied —
unless the variable itself declares `nullable = false` (measured, 1.12.6).
That is what lets the root stay bare passthrough with no copy of the
modules' defaults. `gcp`, `azure` and `scaleway` get the same declaration
when their roots are written — pending.

### Interface

| Variable | Default | Notes |
| --- | --- | --- |
| `cloud` | **required** | `aws`, `gcp`, `azure`, `scaleway` — drives `clusters/<cloud>` and `cluster.type` (scaleway → `kubernetes`) |
| `cluster_name`, `environment`, `owner` | **required** | labels, and `inputs.cluster.*` |
| `kube` | `{}` | `any`, validated and normalised against `catalog.tf` |
| `socle_version` | the module's own `local.socle_version` | override for a dev cluster testing a branch artifact |
| `artifact_url` | `oci://ghcr.io/do-now-io/socle/flux-modules` | override for a mirror |
| `artifact_pull_secret` | `""` | name of an existing `kubernetes.io/dockerconfigjson` Secret in `flux-system` for a private registry; the credential is created outside OpenTofu and never enters its state |
| `cosign_identity` | the release workflow on `refs/heads/main` | override to trust a branch build; `null` means the default identity — verification cannot be disabled |
| `operator_version` | exact `x.y.z` | ranges refused |
| `flux_version` | `2.x` | |
| `flux_components` | four controllers | source and kustomize cannot be dropped |
| `network_policy`, `instance_size`, `storage_class`, `helm_timeout_seconds` | as PR #28 | |

Absent by decision: `sync_kind` (OCI only — Git and Bucket are the model the
README refuses), any Git variable, the image automation controllers, a
`kubernetes` provider.

### `catalog.tf` — the schema is the source of truth

```hcl
locals {
  # The target catalog (§10) — not what v1 ships, which is hello only.
  catalog = {
    cert_manager = { enabled = true,  acme_email = null }
    external_dns = { enabled = true,  domain_filters = [] }
    monitoring   = { enabled = false }
  }
  # Normalised: every module present, every attribute present, client values on top.
  modules = { for m, d in local.catalog : m => merge(d, try(var.kube[m], {})) }
}
```

Two validations on `var.kube`: module names ⊂ `keys(local.catalog)`,
attributes ⊂ the module's keys. Per-attribute validations (an e-mail is an
e-mail) live next to them, and a fifth compares each value's kind with its
catalog default's kind — string, number, bool, list, object, read off
`jsonencode`'s first character since HCL has no `type()` — so
`replicas = "three"` is refused at plan too, not silently coerced. The
artifact's templates rely on the normalisation: every key exists, they test
values, never presence.

Adding a catalog module = a folder in the artifact, an entry here, **and** a
line in each `oci/clusters/<cloud>/kustomization.yaml` that offers it, in the
same release. A module that exists on some clouds only is named in
`catalog_clouds` with its clouds (absent = every cloud); a validation will
refuse it at plan on any other cloud once the first such module lands, with
its tripping test. The overlay is what deploys and the schema is what a client
may configure, so `.github/scripts/check-catalog-clouds.sh` fails CI when they
disagree in either direction. The two travel together because the module and the
artifact share `socle_version`.

Each real module carries its own design note under `docs/catalog/`:
[`gateway-api.md`](catalog/gateway-api.md) — the CRDs and one implementation per cloud.

Cilium, CoreDNS on AWS and the Gateway API CRDs are not catalog modules: they precede Flux on the clouds created without a CNI — [catalog/cilium.md](catalog/cilium.md).

## 4. What foundations expose — `helm_kubernetes`

Each foundations module gains one output, so the root's provider block is one
line and identical on every cloud:

```hcl
provider "helm" { kubernetes = module.foundations.helm_kubernetes }
```

The object is `{ host, cluster_ca_certificate, exec = { api_version, command,
args } }`. **No token, no kubeconfig**: the exec plugin gets a short-lived
token at call time from the runner's ambient credentials, exactly as the
cloud provider does. A raw kubeconfig would put a credential in the state,
which three of the four modules refuse by design, and the helm provider does
not accept a kubeconfig string anyway.

| Cloud | `exec` | Note |
| --- | --- | --- |
| AWS | `aws eks get-token --cluster-name …` | measured on floci |
| GCP | `gke-gcloud-auth-plugin` | host is the DNS endpoint |
| Azure | `kubelogin get-token --login azurecli --server-id 6dae42f8-4368-4678-94ff-3960e28e3630` | *to verify* — only authenticates a cluster with Entra ID auth enabled (`azure_active_directory_role_based_access_control`), which `opentofu/azure` does not configure yet; enabling it is a pending decision for `docs/azure` — until then this is the shape a root will consume, not a working login |
| Scaleway | a `sh -c` exec emitting an `ExecCredential` from `SCW_SECRET_KEY` | built: minted at call time, no token in state |

*Verified:* `e2e-aws-root` configures the helm provider with `kubernetes =
module.foundations.helm_kubernetes`, the whole object with every other
attribute absent, and applies (run 35733476935).

## 5. Single root, and its two exceptions

Foundations and bootstrap are called from one root, so a client applies once.
This contradicts PR #28's "second root, own state" and keeps its real point:
each **module** stays at one provider. Measured: the plan passes with the
cluster unknown, the apply converges in about a minute, a second plan is
empty.

Two cases where one apply is not enough, documented in the root's README as
the conformance checklist allows:

1. **Cluster replacement.** A ForceNew change makes the endpoint unknown at
   plan and the helm provider cannot refresh existing releases:
   `tofu apply -target=module.foundations`, then a full apply.
2. **Destroy with the API unreachable.** The graph deletes releases before the
   cluster, correctly; if the runner cannot reach the API,
   `tofu state rm module.socle` first.

And one rule that becomes hard: **no `kubernetes` provider anywhere in this
chain.**

## 6. The artifact

```
oci/
├── clusters/
│   ├── aws/kustomization.yaml       # lists the catalog ResourceSets available on this cloud
│   ├── gcp/  azure/  scaleway/
└── catalog/
    ├── hello/resourceset.yaml       # v1: podinfo, proves the pipeline
    └── <module>/resourceset.yaml
```

Rules for a module template, all measured:

- `inputsFrom: [{ kind: ResourceSetInputProvider, name: socle }]` — the one
  provider, read by every module.
- **The on/off toggle is on each resource's own `metadata.annotations`:**
  `fluxcd.controlplane.io/reconcile: << if inputs.modules.<m>.enabled >>enabled<< else >>disabled<< end >>`.
  **Not in `commonMetadata`** — the operator does not template it, the
  literal string lands on the objects. Placed per resource, disabling removes
  the objects through garbage collection (10 s); re-enabling recreates them.
- Cloud-specific values come from `inputs.cloud` in the template or from the
  `clusters/<cloud>/` overlay, never from OpenTofu. `hello` shows both: its
  message names the cloud through `inputs.cloud`, and each
  `clusters/<cloud>/hello-color.patch.yaml` is a Kustomize patch on the `hello`
  `ResourceSet` that paints podinfo in that cloud's colour — the template stays
  the shared case, the overlay carries what only one cloud needs. The e2e jobs
  assert the colour (`EXPECT_UI_COLOR`).
- One `ResourceSetInputProvider` per **cluster**, not per module: one object
  for OpenTofu regardless of catalog size, shared values (cloud, domain,
  version) available to every module, the client reads his whole config in
  one `kubectl get`. Per-module providers return the day a module must be
  rendered several times with different values; the operator supports it
  without changing this design.

Deleting a `ResourceSet` uninstalls everything it rendered — measured.

## 7. Publishing the artifact, and releasing

One workflow, `publish-artifact.yaml`, on every push. Nobody types a version:
`VERSION` is the **last release**, written by release-please, and the next one
is read from the conventional commits since it.

| Trigger | Tag | Mutable | Signed as |
| --- | --- | --- | --- |
| push to `main` | `<next>-alpha.N` — `<next>` from the commits since the last release, `N` = 1 + the highest alpha already published for `<next>` | no — one per push | `publish-artifact.yaml@refs/heads/main` |
| push to any other branch | `0.0.0-<branch-slug>.<short-sha>` | n/a — one per commit | `publish-artifact.yaml@refs/heads/<branch>` |
| merge of the release PR | `<next>` — a second tag on the digest of the alpha that same push produced | **never overwritten** | the alpha's signature, i.e. `main` |

- **`<next>` is what release-please will propose**, computed the same way by
  `.github/scripts/compute-tag.sh`: a `Release-As: X.Y.Z` footer wins; else a
  breaking change (`type!:` or a `BREAKING CHANGE:` footer) bumps the major —
  the minor before 1.0.0, so `1.0.0` is always a deliberate `Release-As` —
  `feat` bumps the minor, anything else the patch. One bump from the last
  release, not one per commit: after `0.1.0`, a `fix` gives `0.1.1-alpha.1`
  and a `feat` landing next moves the alphas to `0.2.0-alpha.1`. Before the
  first release there is nothing to bump from: release-please starts at the
  config's `initial-version`, `0.1.0` (its default would be `1.0.0` — measured
  in a dry run), and so does the script while `VERSION` reads `0.0.0`. On the
  release commit itself, whose `VERSION` is not in the registry yet, `<next>`
  is `VERSION`. Numbering asks the registry: `crane ls`, filter, numeric
  sort, +1. A registry that cannot answer fails the job.
- **release-please keeps one release PR open** (`release-please-config.json`,
  release type `simple`, tag without `v`). Its job runs after the e2e proofs,
  so the PR only advances to a commit whose alpha converged on floci. The PR
  carries the `CHANGELOG.md` entry and rewrites every version stamp: `VERSION`,
  `.release-please-manifest.json`, and each line annotated
  `# x-release-please-version` — `local.socle_version` in the five modules,
  the envelope's `Chart.yaml`, three tests, the tfvars example, the CI sample.
  `check-version.sh` stays as the net under it. Commits of types release-please
  hides from the changelog (`chore`, `docs`, `refactor`, `ci`, …) do not open a
  PR on their own; their alphas still publish, as `<patch>-alpha.N`.
- **Merging the release PR is the release.** The push publishes the alpha of
  the merge commit and runs the proofs; release-please then tags the commit
  and publishes the GitHub release; `promote` (`.github/scripts/release.sh`)
  finds the alpha whose `org.opencontainers.image.revision` is
  `main@sha1:<that commit>` and gives it the version as a second tag with
  `crane tag`. Same bytes, same signature, so the release is exactly what the
  proofs ran on. The script refuses when the tag is not that commit's
  `VERSION`, when the version is already in the registry, and when no alpha
  was built from the commit. Runs on `main` share one never-cancelled
  concurrency group, so a promotion never interleaves with the next push.
- **Why in one workflow and not `on: release`**: a release created with the
  workflow's own token does not trigger other workflows (GitHub rule), and a
  PAT or a GitHub App would have been the alternative. Chaining the jobs in
  the same run needs neither, and also orders them: alpha → proofs → release
  PR or release → promotion.
- **Repository setting**: release-please opens pull requests with the
  workflow token, which needs "Allow GitHub Actions to create and approve
  pull requests" (Settings → Actions → General). Merges are rebase-only here,
  so every commit lands on `main` with its own conventional message; a merge
  commit or a non-conventional squash title would be invisible to the bump.
- Branch tags are SemVer pre-releases: they sort below any release, never
  match a `>=1.0.0` range, and are obviously temporary. A dev cluster tests
  one by setting `socle_version` and `cosign_identity` to the branch; an
  alpha needs only `socle_version`, the default identity already trusts `main`.
- **Cleanup**: `cleanup-artifacts.yaml` deletes the branch tags of a branch
  when the branch is deleted, on manual dispatch with a branch name, and on a
  schedule for branch tags older than 7 days and alphas older than 30 days.
  A version carrying a release tag never matches — the promoted alpha keeps
  both its tags. It uses the GitHub packages API with `packages: write`.
  GitHub only dispatches `delete`, `schedule` and `workflow_dispatch` from the
  default branch, so the workflow's first real run — and the answer to whether
  `GITHUB_TOKEN` may delete org package versions, else a fine-grained PAT is
  needed — comes after this branch merges. A nested package name is
  `%2F`-encoded in the packages API path (`socle%2Fflux-modules`).
- **Tested how**: the branch path runs in CI on every push of this branch.
  `compute-tag.sh` is exercised on a throwaway git repository with a stubbed
  `crane`: docs-only → patch, feat → minor, existing alphas → N+1, the release
  commit → `VERSION`, fix then feat after a release → `0.1.1` then `0.2.0`,
  breaking before 1.0.0 → minor, `Release-As` → forced, breaking after 1.0.0
  → major. `release.sh` likewise: promotion of a non-latest alpha by its
  commit; a `v`-prefixed tag, a commit without alpha, no alpha at all and a
  released version → refused. The release-please configuration is checked
  with a `release-pr --dry-run` against this branch: 14 files updated, the
  first changelog spanning the whole history. The first real cycle is
  the merge of this PR: `0.1.0-alpha.1`, a release PR titled
  `chore(release): 0.1.0`, and its merge releases `0.1.0`.
- **Alignment with PR #15**: the modules package (`socle/opentofu-modules:<version>`)
  still follows the older rule there — `VERSION` published as an immutable
  tag on every push to `main`. One `socle_version` pins both packages, so it
  should reuse `compute-tag.sh` for its alphas and add a `promote` job of its
  own on `release_created`; noted on the PR.
- **Names**: the artifact is `ghcr.io/do-now-io/socle/flux-modules` — what
  Flux syncs, not a Helm chart — and PR #15's OpenTofu modules package is
  `ghcr.io/do-now-io/socle/opentofu-modules`. Both under the `socle` prefix,
  both pinned by the one `socle_version`. The branch's first pushes went to
  `ghcr.io/do-now-io/socle` before the names were settled; that package, with
  its branch tags and the cleanup probe tag, is dead weight to delete by hand
  in the GHCR UI.
- **Visibility**: the first push created the GHCR package private. GitHub
  offers no API to change a package's visibility — it is a one-time manual
  setting (Package settings → Change visibility → Public). The package is
  private for now.
- **Measured: `GITHUB_TOKEN` with `packages: read` does pull the private
  repo-linked package** (run 35731631539) — a fine-grained PAT is not needed
  for CI. The e2e jobs create the cluster's pull secret from that same token
  after the apply. A client consumes a private registry the same way: name an
  existing pull secret in `artifact_pull_secret` (§3); nothing needs the
  package to be made public first.
- The publish path keeps the token off argv: `flux push` reads the docker
  config `crane auth login` wrote. The e2e jobs pass it to `kubectl create
  secret docker-registry --docker-password` — argv on an ephemeral,
  single-tenant runner, masked in the log; accepted.
- The bootstrap module's default identity trusts `main` only. Production
  cannot consume a branch build without an explicit override in its tfvars,
  which is reviewed like anything else.

Signing is cosign keyless through the GitHub OIDC token; Flux verifies the
subject on every reconciliation. Verification cannot be turned off: an
unsigned artifact is not a socle.

## 8. CI

**Static (`pr-static.yaml`)**, added to what exists: `tofu test` on the
bootstrap module's validations (one failing case per block, plus the
normalisation and the value-kind check), a check that `VERSION` and every
`local.socle_version` agree, and two `kubeconform` passes. (a) The
renders are kubeconformed **strictly**: `flux-operator build rset` of every
`oci/catalog/*/resourceset.yaml` with `oci/.ci/inputs-sample.yaml`, and
`helm template` of `opentofu/bootstrap/manifests` with
`oci/.ci/envelope-values.yaml` (its root `ResourceSet` also built, with
`--inputs-from-provider`). (b) The raw templates under `oci/catalog` and
`oci/clusters` are also kubeconformed, still with `-strict`, but with
`-ignore-missing-schemas` — never over bare `oci/`, because `oci/.ci/` holds
fixtures, not manifests. The `fluxcd.controlplane.io` kinds are templates
(`<< >>` is not YAML the operator has rendered yet) and may be absent from
the datree schema catalog: a missing schema is ignored, a found one is
still enforced strictly. `flux-operator build rset` omits a disabled object
instead of emitting it with `reconcile: disabled`, so on/off behaviour is
asserted on the live cluster, never on the CLI render. kubeconform v0.7.0's
schema-location template uses `{{.ResourceAPIVersion}}`.

**Integration**, built in Task 11: two jobs in `publish-artifact.yaml`, both
`needs: publish`, not a leg of `integration.yaml`. Each starts its own floci
with the Docker socket mounted and the mock flag dropped — Kubernetes needs
both, which is why `integration.yaml`'s legs, still started with
`FLOCI_SERVICES_EKS_MOCK=true`, stay plan-only. Both pull the branch
pre-release the same commit just published, so signature and identity are
exercised end to end.

`e2e-aws-root` applies the real `opentofu/clusters/aws` against floci **once**
(37 resources, ~70 s) and asserts: the root and `hello` `ResourceSet`s Ready,
the `OCIRepository` revision at the published tag with `SourceVerified=True`,
`hello`'s podinfo at 1 replica.

`e2e-aws-catalog` applies a bare fixture root
(`opentofu/clusters/aws/tests/floci/`: an `aws_eks_cluster` plus the real
bootstrap module) and runs the mutations: `hello.enabled = false` →
`HelmRelease` garbage-collected (1 s), re-enable → Ready again (~76 s),
`tofu plan -detailed-exitcode` → exit 0.

**Why two jobs.** floci applies the real root once but does not read back
several attributes the EKS and CloudWatch APIs return (EKS `logging`,
`encryptionConfig`, `upgradePolicy`, `identity`; the log group's `kmsKeyId`;
the flow-log role), so a refresh of the real root always re-discovers the
same drift and a second apply fails on an unsupported `AssociateKmsKey`. The
bare fixture root has none of that surface and is idempotent, so the mutation
and second-plan assertions run there instead. The version-bump assertion is
not in CI — it needs a second signed tag — and stays measured only in the
spike (§11).

Reference run:
<https://github.com/do-now-io/socle/actions/runs/35733476935> — `e2e-aws-root`
2m29s, `e2e-aws-catalog` 3m35s. The `oidc_issuer_url` output of
`opentofu/aws` is now `try(…, null)`: floci's EKS reports no identity, and an
unguarded index there would fail the apply.

## 9. Convergence signal

Helm's `wait` does not wait for a custom resource to be Ready, so the apply
alone does not prove convergence. The root `ResourceSet` has `wait: true`
and reports the health of what it applied on a single object:

```sh
kubectl -n flux-system get resourceset socle-root
```

CI reads it; a client can. A post-install health check Job on the model of
the `flux-instance` chart is the follow-up if the apply itself must fail.

## 10. Out of scope for v1

Real catalog modules (cert-manager, external-dns, monitoring); the GCP, Azure
and Scaleway roots; the health check Job; multi-instance modules; a mirror
registry per client.

## 11. Measurements behind this document

Floci `floci/floci:1.5.34`, k3s v1.34.1, flux-operator 0.60.0, Flux 2.9.5,
OpenTofu 1.12.6, helm provider 3.3.0, aws provider 6.65.0, 2026-09-21.
Plan with the cluster unknown: 5 to add. Apply: 62 s. Value change → rendered:
5 s. Module off → garbage-collected: 10 s. Version bump → root re-verified and
module upgraded: 10 s. Second plan: no changes. Typo in an `object`-typed
`kube`: silently accepted; as `any` with validations: refused with the
allowed list. `commonMetadata.annotations` templating: not evaluated.
Variable in module `source`: resolved from tfvars, both modules follow.

**2026-09-22, from the two `e2e-aws-*` jobs in `publish-artifact.yaml`**
(run <https://github.com/do-now-io/socle/actions/runs/35733476935>):
`e2e-aws-root` applies the real `opentofu/clusters/aws` on floci — 37
resources — in ~70 s, once (2m29s job total); `e2e-aws-catalog` applies the
bare fixture root, then `hello.enabled = false` → `HelmRelease` gone in 1 s,
re-enabled → Ready again in ~76 s, second `tofu plan -detailed-exitcode` →
exit 0 (3m35s job total). `GITHUB_TOKEN` with `packages: read`: pulls the
private repo-linked package (run 35731631539) — no PAT needed. floci's EKS:
no `logging`, `encryptionConfig`, `upgradePolicy` or `identity` read back, no
log-group `kmsKeyId`, no flow-log role — a second apply of the real root
fails on `AssociateKmsKey`.
