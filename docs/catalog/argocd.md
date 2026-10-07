# Catalog module `argocd` — the client's GitOps layer

The socle's model is two layers of GitOps: Flux bootstraps and keeps the socle
converged (this catalog), ArgoCD is what clients ship their applications with.
So ArgoCD is a catalog module like any other, on all four clouds, and the first
one a client is expected to keep on. Part of #32; the module contract is
`docs/flux-catalog.md` §3 and §6.

| Question | Position |
| --- | --- |
| What | The official `argo-cd` chart, `oci://ghcr.io/argoproj/argo-helm/argo-cd:10.9.2` (ArgoCD v3.5.3), one `HelmRelease` in namespace `argocd` |
| Where | Every cloud, the same template, no cloud patch — nothing in ArgoCD is cloud-specific until SSO or an identity for private repositories |
| Default | **On.** It is what a client gets a socle for, and it converges on floci's k3s (measured below) |
| Shape | Non-HA, sized for a small cluster: one replica of each component, the single Redis, requests set, no limits |
| Exposure | `ClusterIP`, `server.insecure: true`, and an `HTTPRoute` on the shared `private` Gateway for `domain` ([gateway-api.md](gateway-api.md)); TLS terminates at the Gateway or its load balancer |
| Identity | Local `admin` kept, Dex off. SSO is a follow-up |
| Client surface | Four typed switches under `kube.argocd`, plus `values`: the client's own chart values, merged over the socle's, the client winning; secrets through `values_secret`, a Secret he owns |

## What is installed

One `ResourceSet` (`oci/catalog/argocd/resourceset.yaml`), three objects, each
carrying the per-resource reconcile toggle on `inputs.modules.argocd.enabled`:

1. `Namespace/argocd`.
2. `OCIRepository/argo-cd-chart` in it — the chart pinned exactly, Helm layer
   copied, refreshed hourly.
3. `ConfigMap/argocd-socle-values` — the socle's own chart values, the table
   below, as a YAML document.
4. `ConfigMap/argocd-client-values` — `kube.argocd.values` as YAML, `{}` by
   default.
5. `HelmRelease/argocd` — `interval: 10m`, `timeout: 10m` (five images on a
   fresh node make helm-controller's default 5 m tight on a small cluster),
   install and upgrade remediation with three retries so a transient does not
   leave the release stalled. **No `spec.values`**: `valuesFrom` lists
   `argocd-socle-values`, `argocd-client-values`, then the client's Secret
   when named (`optional: true`), in that order.

The socle's values, all in `argocd-socle-values`, and why:

| Value | Setting | Why |
| --- | --- | --- |
| `controller`, `server`, `repoServer`, `applicationSet` `.replicas` | 1 | A small cluster. `ha` changes it (below) |
| `redis-ha.enabled` | false | Same |
| `*.resources.requests` | controller 250m/256Mi, repoServer 100m/128Mi, server 50m/64Mi, applicationSet 50m/64Mi, redis 50m/32Mi | Scheduling is honest about what ArgoCD needs; no limits, because a memory limit OOM-kills the controller on a large estate and there is no client knob to raise it in v1 |
| `server.service.type` | `ClusterIP` | Exposure is the Gateway's job (follow-up) |
| `configs.params."server.insecure"` | true | The server speaks plain HTTP in-cluster; TLS terminates at the Gateway |
| `configs.cm."admin.enabled"` | `admin_enabled` | The local account exists until SSO does |
| `global.domain` | `domain`, only when set | The chart derives `configs.cm.url` and `statusbadge.url` from it, and it is the hostname the HTTPRoute follow-up reads |
| `configs.cm.url`, `statusbadge.url` | `""` when `domain` is empty | The chart otherwise ships `https://argocd.example.com`; an empty preset is dropped, so no URL is better than a wrong one |
| `dex.enabled` | false | No identity provider yet |
| `notifications.enabled` | false | Out of scope |
| `crds.install`, `crds.keep` | chart defaults (true, true) | Disabling the module garbage-collects the release; the CRDs stay, as Helm always leaves them |

## What the client may set — `kube.argocd`

| Attribute | Default | Type | Meaning |
| --- | --- | --- | --- |
| `enabled` | `true` | bool | Off garbage-collects the release and its namespace (CRDs remain) |
| `admin_enabled` | `true` | bool | `false` removes the local `admin` account — for when SSO exists, which this module does not configure |
| `domain` | `""` | string | The host ArgoCD is served at, e.g. `argocd.acme.example`. Feeds `global.domain`, hence `configs.cm.url` (login redirects, CLI hints) and later the HTTPRoute hostname. Validated: empty or a lowercase FQDN — no scheme, no port, no path — one validation block, one diagnostic |
| `ha` | `false` | bool | The chart's documented HA layout without autoscaling: the `redis-ha` subchart (three Sentinel-backed Redis behind haproxy) and two replicas of server, repo-server and applicationset. The controller stays at one — more replicas shard clusters, they do not add availability |
| `values` | `{}` | object | Any value of the `argo-cd` chart, as the chart documents it. Merged over the socle's values, the client's winning. No secret material (below) |
| `values_secret` | `""` | string | Name of a Secret in `argocd`, created by the client, with a `values.yaml` key. Merged last. Where private keys and client secrets go |

Kinds are enforced by the catalog-wide kind check (a bool default refuses
`"yes"`, the `{}` default refuses a string for `values`).

### Why a values escape hatch after all

ArgoCD is not configured once by the platform: every client brings local
accounts and their RBAC, repositories and repository credentials, a GitHub App
or an OIDC connector, resource exclusions, custom health checks. That is the
chart's own surface, documented upstream, and changes with every ArgoCD
release. Mirroring it attribute by attribute in `catalog.tf` would be a
second, always-late copy of the chart's `values.yaml`. So the split is:

- **The socle owns the typed switches** — `enabled`, `domain`, `ha`,
  `admin_enabled` — and the defaults below them (sizing, `ClusterIP`,
  `server.insecure`, Dex and notifications off). Those are what CI proves.
- **The client owns `values`**, written in the chart's own vocabulary. It is
  handed to helm-controller untouched and merged with `valuesFrom`, the deep
  merge any Helm user knows: maps merge key by key, lists and scalars are
  replaced. A client who sets `server.replicas` in `values` wins over `ha`,
  and one who sets `configs.cm.url` wins over `domain`: a named attribute is
  a convenience, not a lock, and the override shows in his tfvars.

**Precedence, and why the socle's values are not inline.** helm-controller
merges the `valuesFrom` references in order and then `spec.values` over the
result — `chartutil.ChartValuesFromReferences` ends on
`MergeMaps(result, values)`. The first version of this module wrote its
defaults in `spec.values`, so every socle default beat the client on any key
both set, and `values` could only add keys the socle had not thought of. The
e2e did not see it because it overrode a key the socle leaves unset
(`accounts.e2e`). Now the socle's document is the first reference, so the
order in `valuesFrom` is the whole precedence: socle, client, Secret, later
wins. One consequence: a `clusters/<cloud>/` overlay cannot JSON-patch one
value by path any more, since the values are a string inside a ConfigMap. A
per-cloud value goes in the template, under an `if` on `eq inputs.cloud` in
the socle's document; none exists for ArgoCD.
- **Secrets never cross OpenTofu.** `values` lands in the OpenTofu state, in
  the `ResourceSetInputProvider` and in a ConfigMap, so plan refuses
  `configs.secret`, `configs.credentialTemplates`, `configs.clusterCredentials`
  and any `password`, `sshPrivateKey`, `githubAppPrivateKey`, `bearerToken`,
  `tlsClientCertData` or `tlsClientCertKey` under `configs.repositories`. The
  client puts those in his own Secret (from his secret manager, External
  Secrets, SOPS, by hand) and names it in `values_secret`; it is merged last
  and marked `optional`, so the release does not stall before it exists. An
  ArgoCD-native `repo-creds` Secret labelled
  `argocd.argoproj.io/secret-type: repo-creds` works as well and needs
  nothing from the socle.

A typical client block:

```hcl
kube = {
  argocd = {
    domain = "argocd.acme.example"
    values = {
      configs = {
        cm   = { "accounts.alice" = "apiKey, login" }
        rbac = { "policy.csv" = "g, platform-admins, role:admin" }
        repositories = {
          acme = { url = "https://github.com/acme", type = "git", githubAppID = "12345", githubAppInstallationID = "67890" }
        }
      }
    }
    values_secret = "argocd-values"   # holds configs.repositories.acme.githubAppPrivateKey
  }
}
```

What the socle does not promise: that a client's `values` survive a chart
major. The chart pin moves with `socle_version`, the changelog names it, and
`values` is the client's to adapt — the same deal as any Helm chart he would
install himself.

**Not configurable:** the chart version and the namespace. Applications and
ApplicationSets are not the socle's either: it ships an ArgoCD with no
application, the client fills it (the chart's `extraObjects` in `values`, or
ArgoCD's own declarative setup).

## Per cloud

Nothing but requests, on GCP. GKE Autopilot gives a container that requests
nothing 500m CPU and 2 GiB, so on gcp the socle sets requests on the three
the chart leaves empty: the `redis-secret-init` install hook (50m / 64Mi,
the Autopilot floor) and, with `ha`, each Redis's `sentinel` and
`split-brain-fix` sidecars (10m / 32Mi).

Otherwise nothing. The four `oci/clusters/<cloud>/kustomization.yaml` list
the same template and carry no `argocd` patch. Two things differ per cloud,
and neither is this module's: the Gateway implementation the HTTPRoute binds
to (the gateway-api module), and the workload identity ArgoCD would use to
read private repositories or deploy to other clusters (a foundations
concern, wired through `kube.argocd` when it exists).

## Templating notes

- `values` is rendered with `<< toYaml inputs.modules.argocd.values | nindent 4 >>`
  into its ConfigMap (verified with `flux-operator build rset`: nested maps and
  multi-line `policy.csv` survive, `{}` renders `{}`). Two YAML maps cannot be
  merged in a text template, and helm-controller already does it right.
- The socle's document keeps its `<< if >>` blocks inside the block scalar:
  the operator templates the text before YAML ever parses it, so the
  conditionals behave as they did in `spec.values`. One trap, measured: the
  operator also templates **comments** inside `resourcesTemplate`, so a
  comment quoting `<< if … >>` breaks the render ("missing value for if").
- `resourcesTemplate`, not `resources`: `global.domain`, the `redis-ha`
  block and the Secret in `valuesFrom` only exist under a condition, and the operator's block
  `<< if >>`/`<< end >>` is text templating (same reason as the root
  `ResourceSet`, `opentofu/bootstrap/manifests/templates/root.yaml`).
- HA is one switch, spread as it must be: the `redis-ha` block is a
  `<< if >>` over a whole key; the three replica counts are inline
  `<< if … >>2<< else >>1<< end >>` — a block per component would duplicate
  the `resources` stanzas, and YAML has no key merging.
- `<< if inputs.modules.argocd.domain >>`: an empty string is false in the
  operator's templates, so "set" and "non-empty" are the same test. OpenTofu
  normalises the inputs, so every key exists — templates test values, never
  presence.
- A per-cloud patch on this module would have to patch a string
  (`resourcesTemplate`), not a JSON path as `hello-color.patch.yaml` does.
  None is needed; if one becomes necessary, a Kustomize `replacements` on the
  string or a second, cloud-specific template beside it is the shape.

## Measured

**Render** (`flux-operator build rset` with `oci/.ci/inputs-sample.yaml`,
kubeconform `-strict` against the datree CRD catalog):

| Inputs | Result |
| --- | --- |
| sample: `domain: argocd.example.com`, `ha: false`, `admin_enabled: true` | 5 objects; the HelmRelease has no `spec.values` and `valuesFrom` = socle, client, Secret; the socle document has `global.domain` set, no `url` override, replicas 1/1/1, no `redis-ha`; valid |
| `domain: ""`, `ha: true`, `admin_enabled: false` | in the socle document: `url: ""` and `statusbadge.url: ""` present, `admin.enabled: false`, `redis-ha.enabled: true`, server/repoServer/applicationSet at 2, controller at 1, valid |
| `enabled: false` | no objects generated (the CLI omits disabled resources; on/off is proven on the cluster) |

`tofu test` in `opentofu/bootstrap`: 37 runs, 13 of them for this module —
`ha` and `admin_enabled` refusing a string and a number, `domain` refusing a
list, a scheme and a bare label, `values` refusing a string, `configs.secret`,
`credentialTemplates` and a repository's GitHub App key, `values_secret`
refusing an invalid name; defaults asserted; a valid domain, `ha = true`,
and `values` with a credential-less repository flowing through as written.

**Merge, locally** — `helm template` of the pinned chart with the rendered
socle document then a client file setting
`server.resources.requests.memory: 96Mi`: `argocd-server` requests
`cpu: 50m, memory: 96Mi`; without the client file, `cpu: 50m, memory: 64Mi`.

**e2e** (floci k3s v1.34.1, `ubuntu-latest` runner, PR #34):

Run <https://github.com/do-now-io/socle/actions/runs/35888163280>, tag
`0.0.0-feat-catalog-argocd.7b9fffe`, both jobs green on the first run:

| Job | Step | Measured |
| --- | --- | --- |
| `e2e-aws-root` | real root applied (37 resources), then `resourceset/argocd` Ready and `argocd-server` Available | **53 s** after the wait starts (~2 min after the apply began); job 2m33s against 2m29s before the module |
| `e2e-aws-catalog` | bare fixture root, same wait | **42 s** |
| `e2e-aws-catalog` | `enabled = false` on hello and argocd → both HelmReleases NotFound | **8 s** for the apply and both checks |
| `e2e-aws-catalog` | re-enabled → hello Ready again (~76 s, as before), then `resourceset/argocd` Ready again and `argocd-server` Available | **18 s** after hello — images already on the node |
| `e2e-aws-catalog` | second `tofu plan -detailed-exitcode` | exit 0; job 4m10s against 3m35s before |

**Precedence on the live object** — run
<https://github.com/do-now-io/socle/actions/runs/35906487179>, tag
`0.0.0-feat-catalog-argocd.4db5771`. `tests/floci.tfvars` overrides a key the
socle sets, `server.resources.requests.memory` (64Mi in `argocd-socle-values`),
with 96Mi in `kube.argocd.values`. `e2e-aws-root` reads the `argocd-server`
Deployment: `memory=96Mi cpu=50m` — the client's value, and the socle's
sibling key kept by the deep merge. Same run: `accounts.e2e` in `argocd-cm`
next to the socle's `admin.enabled=true`, convergence 42 s (root) and 52 s
(catalog), argocd garbage-collected on disable and Ready again 18 s after
re-enable.

The 7 GB runner took the module without a resource change: no eviction, no
pending pod, no retry of the HelmRelease. The requests above were not lowered.

**e2e, through Chainsaw** (`tests/e2e/chainsaw-test.yaml`, since the e2e
moved into the modules — `docs/flux-catalog.md` §8). The two jobs above are
now the `root (aws)` job, which runs `argocd-health`, and the `argocd (aws)`
job, which runs it and then `argocd-module`: the precedence proof is a
`patch` of the `ResourceSetInputProvider` with the same two client values the
root job's `.github/e2e/aws/floci.tfvars` carries (`accounts.e2e`, `server` memory 96Mi) asserted
on the live `argocd-cm` and `argocd-server`, then `enabled = false` and back.
For the patch to reach the release before the 10-minute interval, both
values ConfigMaps now carry `reconcile.fluxcd.io/watch: Enabled`, as
external-dns's already did: without it, measured, a client value landed in
`argocd-client-values` and the Deployment kept the old request 209 s later.

## Exposure through Gateway API

`kube.argocd.gateway` names the shared Gateway the route attaches to: `private`
by default, because ArgoCD is an operator's tool and not an internet service.
It can also be `public`, or `""` for no route. The route is rendered only when
`domain` is set and the shared Gateways exist (`inputs.gateway.shared`,
[gateway-api.md](gateway-api.md)).

It is the socle's own `HTTPRoute`, `argocd/argocd-server`, and not the chart's
`server.httproute`. It sits in a child `ResourceSet`, `argocd-route`, which
`dependsOn` its Gateway being `Accepted`. The chart's route would be applied
with the release, possibly before the Gateway API CRDs exist, and a failed
install stalls the release. The route attaches to the `https` listener and
sends `domain` to `argocd-server:80`. `server.insecure: true` is what makes
that port answer in plain HTTP.

On gcp, GKE's load balancer health-checks the backend itself: `GET /` on the
pod's port, healthy on a 200 only. No `HealthCheckPolicy` is needed for
argocd-server. In insecure mode there is no redirect to https, and `/`
without an HTML `Accept` header is served by the UI's file server, which
answers `index.html` with a 200 (`newStaticAssetsHandler`, argo-cd v3.5.3
`server/server.go`; the UI is embedded from `dist/app`, `index.html` at its
root). The sandbox has to confirm it: the backend healthy in the load
balancer.

Not done yet: a `GRPCRoute` for the `argocd` CLI. `argocd login --grpc-web`
works over the HTTPRoute.

On floci there is no shared Gateway, so `tests/e2e/chainsaw-test.yaml`
(`argocd-floci`, `platform: floci`) asserts the negative: `gateway` at its
default, no `argocd-route` ResourceSet. The route itself is the sandbox's
proof.

## Open questions for the coordinator

1. **Renovate does not see the chart pin.** `spec.ref.tag: 10.9.2` sits in a
   string (`resourcesTemplate`), and `hello`'s in a structured list the flux
   manager also does not read inside a `ResourceSet`. A custom regex manager
   over `oci/catalog/*/resourceset.yaml` (`# renovate:` comment convention)
   would cover every module; one PR for all of them, outside this one.
2. **The e2e budget is the module's.** `tests/e2e/chainsaw-test.yaml` gives
   `argocd-health` a 10-minute assert timeout, the chart's own install
   timeout, where the socle's `root` suite keeps 5 minutes: a slow image pull
   fails on this module's test, with its `catch` output — events, the
   HelmRelease, the pods, helm-controller's log, the node's conditions —
   and not on `socle-root`.
3. **HA on a one-node cluster.** `redis-ha` carries a hard anti-affinity and
   needs three nodes; `ha = true` on a smaller cluster leaves Redis pending.
   Not e2e-tested (floci is one node); the validation cannot know the node
   count. Documented here rather than guarded.
