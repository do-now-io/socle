# Catalog module `external_dns`

external-dns publishes the names of Services, Ingresses and Gateway API
HTTPRoutes into the cloud's DNS zone. One catalog module, one template, one
DNS provider per cloud. Issue #32; the catalog contract is
[docs/flux-catalog.md](../flux-catalog.md).

| Question | Position |
| --- | --- |
| Chart | Official `external-dns` 1.22.0 (app 0.22.0), from `https://kubernetes-sigs.github.io/external-dns/` |
| Where the cloud lives | One `<< if eq inputs.cloud … >>` block per cloud inside the template's socle-values document |
| Default | Off: it needs a zone, which has no default, and a credential |
| Cloud credential | **None from the socle yet.** The client brings one, per cloud (below). The module's own role, as Crossplane resources it declares, is the next step |
| Records | `registry: txt`, owner = cluster name, prefix `socle-`, `upsert-only` unless the client says `sync` |

## What is installed, per cloud

One `Namespace` (`external-dns`, Pod Security `restricted`), one
`HelmRepository`, two values ConfigMaps and one `HelmRelease` running as
ServiceAccount `external-dns/external-dns`. That name is fixed on every
cloud: it is the subject the module's own identity will be bound to.

**This module creates no cloud identity, and nothing in the socle does for
it.** A foundations module never changes because of the catalog
([docs/flux-catalog.md](../flux-catalog.md) §6), so the role belongs to the
module, as Crossplane resources it declares — a follow-up, see
[the last section](#next-the-modules-own-role-through-crossplane). Until
then, enabling the module on a real cluster means the client brings the
credential:

| Cloud | Provider | What the client brings today |
| --- | --- | --- |
| aws | `aws` (Route 53) | Either the Secret `external-dns-aws` (static keys, see [below](#the-external-dns-aws-secret)), or a Pod Identity association for `external-dns/external-dns` made outside the socle: with no Secret, the SDK's default chain picks it up |
| gcp | `google` (Cloud DNS) | A Google service account bound with Workload Identity, named through `values` as `serviceAccount.annotations."iam.gke.io/gcp-service-account"`; or DNS roles granted directly to the ServiceAccount's Workload Identity Federation principal |
| azure | `azure` (Azure DNS) | The Secret `external-dns-azure` with `azure.json`: a service principal, or `useWorkloadIdentityExtension` plus the `azure.workload.identity/client-id` annotation and `azure.workload.identity/use` pod label through `values` |
| scaleway | `scaleway` (Scaleway DNS) | The Secret `external-dns-scaleway` with `SCW_ACCESS_KEY` and `SCW_SECRET_KEY`, an API key scoped to DomainsDNSFullAccess |

The Secrets stay outside OpenTofu: the bootstrap has no `kubernetes`
provider, and a credential never enters the artifact or the state.

```sh
kubectl -n external-dns create secret generic external-dns-azure \
  --from-file=azure.json
kubectl -n external-dns create secret generic external-dns-scaleway \
  --from-literal=SCW_ACCESS_KEY=… --from-literal=SCW_SECRET_KEY=…
```

Create the Secret after enabling the module, since the namespace comes with
it. On Azure and Scaleway the pod cannot start until it exists. The
HelmRelease uses the `RetryOnFailure` strategy, so Flux retries it every two
minutes until it is Ready.

## What the client may set — `kube.external_dns`

| Attribute | Default | Rule, checked at plan |
| --- | --- | --- |
| `enabled` | `false` | bool |
| `domain_filters` | `[]` | At least one entry when enabled. Each is a lowercase DNS name, with no leading dot and no wildcard |
| `policy` | `"upsert-only"` | `upsert-only` or `sync`. `create-only` is refused |
| `txt_owner_id` | the cluster name | 1 to 63 characters from `[A-Za-z0-9._-]` |

### Free-form values — `values` and `values_secret`

The two attributes every module carries ([docs/flux-catalog.md](../flux-catalog.md) §6):

The HelmRelease has no inline `values:` block. Its `valuesFrom` lists, in
the order helm-controller merges them, later winning:

1. **`external-dns-socle-values`**, a ConfigMap with the socle's defaults and
   the per-cloud block.
2. **`external-dns-client-values`**, a ConfigMap rendered from
   `kube.external_dns.values`.
3. **The Secret named in `values_secret`**, when there is one. The client
   creates it in the `external-dns` namespace with a `values.yaml` key, and
   OpenTofu never reads it. The entry is `optional`, and absent when the
   attribute is empty. Label the Secret `reconcile.fluxcd.io/watch: Enabled`,
   or a change waits for the next interval.

Both ConfigMaps carry the label `reconcile.fluxcd.io/watch: Enabled`.
helm-controller only watches a `valuesFrom` object that carries it, per its
spec. Before the label, the e2e caught the gap: a `policy` change landed in
the ConfigMap, the HelmRelease spec did not change, and the pod kept
`--policy=upsert-only`. Every module that follows the convention needs the
same label.

So a client can override any value, the socle's included, without waiting
for a socle release. This includes `policy`, `txtOwnerId`, `sources`, and a
cloud's `provider` or `env`. A named attribute is a convenience, not a lock:
`values` is merged after the document the attribute feeds, and wins. A list
is replaced, not merged. A client `env` on AWS therefore replaces the
socle's, including the `external-dns-aws` entries.

**Why there is no inline block.** helm-controller merges the `valuesFrom`
entries in order, then `spec.values` over the result:
`chartutil.ChartValuesFromReferences` ends on `MergeMaps(result, values)`.
The helm-controller spec says it in words: "and then inline values
overwriting those". An inline socle default would therefore beat the client
on every key both set.

**Measured.** The e2e sets `values = { txtOwnerId = "socle-e2e-client" }`.
txtOwnerId is a key the socle sets, from `txt_owner_id`, whose default is the
cluster name `socle-e2e-catalog`. The pod runs with
`--txt-owner-id=socle-e2e-client`, and every TXT record in the fake Route 53
names `socle-e2e-client` as owner. A key the socle leaves unset would have
proven nothing.

**Why the cloud moved into the template.** The per-cloud provider and
credential used to be JSON 6902 patches in `oci/clusters/<cloud>/`, on
`spec.values`. A patch cannot reach a value inside a ConfigMap's YAML
string, so each cloud is now a `<< if eq inputs.cloud … >>` block in the
socle-values document. The alternative was to replace the whole document per
cloud. That would copy every shared default four times, and the next shared
change would have to be made in four places. The overlays list the module
and nothing else.

What `values` refuses at plan, because it lands in the OpenTofu state and
in a plain ConfigMap:

| Chart path | Why it is refused |
| --- | --- |
| `secretConfiguration` | The chart turns its `data` into a Secret, so the data would be written in clear upstream of it |
| `env[]` and `provider.webhook.env[]` with a literal `value` under a credential-like name | For example `AWS_SECRET_ACCESS_KEY`, `SCW_SECRET_KEY` or `*_TOKEN`. A `valueFrom` reference passes |
| `extraArgs` keys or entries with a credential-like flag | For example `txt-encrypt-aes-key`, `pdns-api-key` or `rfc2136-tsig-secret` |

## Fixed by the socle, not by a named attribute

Each of these is a socle default. A client can still override it through
`values`, at their own risk.

- **Sources.** They are `service`, `ingress` and `gateway-httproute`. The
  last one is added only when `inputs.modules.gateway_api.enabled` is true.
  external-dns 0.22.0 builds an informer per source and exits when the
  Gateway CRDs are absent. The chain is `WaitForCacheSync` in
  `source/gateway.go`, then `log.Fatal` in `controller/execute.go`. The
  template guards with `hasKey`, so it renders before the gateway-api
  module exists. Measured with `flux-operator build rset`: without the key
  the sources are `[service, ingress]`, and with it they include
  `gateway-httproute`.
- **Registry and TXT prefix.** The registry is `txt` with the prefix
  `socle-`. On Cloud DNS, Azure DNS and Scaleway an Ingress hostname becomes
  a CNAME, and a TXT record cannot share its name.
- **The chart source.** The chart is not published as OCI.
  `registry.k8s.io/external-dns/charts/external-dns` returns 404 for every
  tag we tried, and serves the image only. So the source is the project's
  HTTPS Helm repository, pinned exactly.
- **The AWS region.** It is fixed to `us-east-1`, because Route 53 is a
  global service served from there.
- **Zone ids, filters by label or annotation, extra args, and resources.**
  None of these are in v1.

## Measured

- **Render.** `flux-operator build rset` renders the template for each of
  the four clouds with `oci/.ci/inputs-sample.yaml`, and `kubeconform
  -strict` passes on all of them. Each cloud's socle-values and client-values
  documents, merged in that order, also pass the chart's own schema through
  `helm template` of chart 1.22.0. The AWS container args are `--source=service --source=ingress
  --policy=upsert-only --registry=txt --txt-owner-id=t --txt-prefix=socle-
  --domain-filter=acme.example --provider=aws`.
- **`tofu test`.** The bootstrap's runs pass, and each new validation has a
  failing case.
- **e2e, disabled.** Both jobs assert that the `external-dns` ResourceSet
  is Ready while disabled, and that its namespace is absent.
- **e2e, against a fake Route 53.** `e2e-aws-catalog` enables the module on
  floci's k3s on every push, through `kube` as a client would. The steps are
  in `.github/scripts/e2e/external-dns.sh`:

  | Step | What it proves |
  | --- | --- |
  | `prepare` | A hosted zone `e2e.socle.test` in floci's Route 53, and the `external-dns-aws` Secret with test keys and floci's endpoint |
  | `publish` | `values` overrides the socle's `txtOwnerId`. An Ingress becomes an A record and an ExternalName Service a CNAME, each with a `socle-` TXT naming the client's owner |
  | `kept` | With `upsert-only`, deleting the Ingress leaves its A record |
  | `deleted` | After re-applying with `policy = "sync"`, the A record and its TXT go, and the CNAME stays |
  | GC | Disabling the module removes its namespace |

  Measured first on a local floci: all four steps pass with the values the
  template renders for aws. A pod reaches floci over the Docker bridge both share.
- **Not provable on floci.** The credential here is the Secret seam; the
  module's own role is not provable there, for the reasons in
  [the last section](#next-the-modules-own-role-through-crossplane). GCP,
  Azure and Scaleway have no DNS emulator; their blocks are proven by render
  only.

## The `external-dns-aws` Secret

The aws block reads three optional variables from a Secret named
`external-dns-aws` in the `external-dns` namespace: `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY` and `AWS_ENDPOINT_URL`. When the Secret is absent,
no variable is set, and the SDK uses its default chain — a Pod Identity
association, once the module has one. This is how the e2e points
external-dns at floci. It is also today's way for a client to give the pod
static keys, or a Route 53-compatible endpoint. Anyone who can write Secrets
in that namespace can redirect external-dns, which is already true of anyone
who can edit its Deployment.

## Annotations: the prefix changed in 0.22

external-dns 0.22.0 reads `external-dns.kubernetes.io/hostname` and
`external-dns.kubernetes.io/target`. The older
`external-dns.alpha.kubernetes.io/` annotations are ignored, measured on
floci: no endpoint is generated from them. The template keeps the upstream
default. Workloads and the other catalog modules must use the new prefix.

## Next: the module's own role, through Crossplane

The module's cloud access belongs in the artifact, as Crossplane managed
resources the module declares and its ResourceSet renders
([docs/flux-catalog.md](../flux-catalog.md) §6, and
[crossplane.md](crossplane.md)). The foundations keep nothing specific to
external-dns. An earlier revision of this pull request added an optional
`external_dns` block to each `opentofu/<cloud>/`, which is the shape that rule
excludes. It was removed rather than half-migrated. What the follow-up
declares, per cloud:

| Cloud | Managed resources the module declares |
| --- | --- |
| aws | An IAM role under `/socle/<cluster>/`, carrying Crossplane's boundary, with `ChangeResourceRecordSets` and `ListResourceRecordSets` on the named zones (`ListHostedZones` has no narrower resource than `*`), and its Pod Identity association for `external-dns/external-dns` |
| gcp | A Google service account, `dns.admin` on each managed zone, `dns.reader` on the project (listing zones has no zone-level grant), the Workload Identity binding |
| azure | A user-assigned identity, DNS Zone Contributor on each zone and Reader on their resource group, the federated credential for the ServiceAccount |
| scaleway | An IAM application, a DomainsDNSFullAccess policy on the Project with the source-IP condition, an API key written into `external-dns-scaleway` |

The zones then become module attributes, and the cloud blocks in the
socle-values document read the identity from the module's own resources.

**What blocks proving it today.** The e2e runs on floci, and floci cannot
carry the AWS half of this:

- **floci does not implement `CreatePodIdentityAssociation`.** The EKS call
  is routed to floci's S3 emulation and gets a 404 HTML page. Crossplane's
  `PodIdentityAssociation` never becomes `Synced` there: the crossplane e2e
  prints it as expected-unsynced and deletes it without waiting on its
  finalizer (`.github/scripts/e2e/crossplane.sh`).
- **floci's k3s runs no EKS Pod Identity Agent.** Even a synced association would
  hand the pod no credential, so external-dns could not reach Route 53
  through it.
- **floci enforces no IAM policy and ignores `PermissionsBoundary`**, as
  [crossplane.md](crossplane.md) measures. A role that is too broad would
  pass.

What floci *can* prove is the role and its inline policy reaching IAM, as
the crossplane e2e already does for a module-shaped role. The end-to-end
proof that external-dns writes Route 53 as its own role needs a real
account; until then the e2e keeps the `external-dns-aws` Secret seam.

## Prerequisite and assumptions for the coordinator

- **The EKS Pod Identity Agent add-on.** The module's future role on AWS
  depends on it. The coordinator routed it to the cilium worktree, as an
  `aws_eks_addon` in the foundations that is on by default.
- **The annotation prefix.** The gateway-api and argocd modules must annotate
  with `external-dns.kubernetes.io/`, not the alpha prefix most tutorials
  still show.
- **`gateway_api.enabled`.** The template reads it through `hasKey`. Once the
  gateway-api module is merged, the attribute always exists and the guard
  is harmless. If that module is named anything else, only the key in the
  template's `sources` line changes.
- **Open questions.**
  - DNS zones in another GCP project or Azure subscription than the cluster
    are not supported in v1.
  - Azure zones spread over several resource groups are refused rather than
    handled with several instances.
  - The credential Secrets are manual steps until the module declares its
    own role.
