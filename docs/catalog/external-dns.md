# Catalog module `external_dns`

external-dns publishes the names of Services, Ingresses and Gateway API
HTTPRoutes into the cloud's DNS zone. One catalog module, one template, one
DNS provider per cloud. Issue #32; the catalog contract is
[docs/flux-catalog.md](../flux-catalog.md).

| Question | Position |
| --- | --- |
| Chart | Official `external-dns` 1.22.0 (app 0.22.0), from `https://kubernetes-sigs.github.io/external-dns/` |
| Where the cloud lives | One `<< if eq inputs.cloud … >>` block per cloud inside the template's socle-values document |
| Default | Off: it needs a zone, which has no default |
| Cloud access, AWS | **The module's own**, with `kube.crossplane` on: an IAM `Role` and its `PodIdentityAssociation`, declared in the module's ResourceSet as Crossplane managed resources. The foundations grant nothing to it |
| Cloud access, GCP | **The module's own**, with `kube.crossplane` on: a `ManagedZoneIAMMember` per zone the client listed and one `ProjectIAMMember` to list zones, bound to the ServiceAccount's own Workload Identity principal. No Google service account |
| Cloud access, elsewhere | A credential the client brings, until Crossplane has a provider on that cloud |
| Route 53 scope | Writes allowed only on names under `domain_filters`, by condition key; reads on every zone (below) |
| Cloud DNS scope | `roles/dns.admin` on each zone in `gcp.crossplane.dns_zones`, nothing else on records; zone listing on the project ([below](#gcp-the-modules-own-members-through-crossplane)) |
| Records | `registry: txt`, owner = cluster name, prefix `socle-`, `upsert-only` unless the client says `sync` |

## What is installed, per cloud

Two layers, after the `crossplane` ResourceSet is Ready — which it is
trivially when Crossplane is off:

1. **The `external-dns` ResourceSet**: the `Namespace` (`external-dns`, Pod
   Security `restricted`) and, with `kube.crossplane.enabled`, the module's
   own access: on AWS its `Role` and `PodIdentityAssociation`
   ([the AWS section](#aws-the-modules-own-role-through-crossplane)), on GCP
   its `ManagedZoneIAMMember`s and `ProjectIAMMember`
   ([the GCP section](#gcp-the-modules-own-members-through-crossplane)).
2. **A child ResourceSet, `external-dns-workload`**, which `dependsOn` each
   of those being `Ready` with Crossplane on: one `HelmRepository`, two
   values ConfigMaps and one `HelmRelease` running as ServiceAccount
   `external-dns/external-dns`. That name is fixed on every cloud: it is the
   subject the association binds on AWS, and the principal the members name
   on GCP.

A foundations module never changes because of the catalog
([docs/flux-catalog.md](../flux-catalog.md) §6): nothing in `opentofu/` is
specific to this module.

| Cloud | Provider | Where the credential comes from |
| --- | --- | --- |
| aws | `aws` (Route 53) | **Crossplane on: the module's own role**, through its Pod Identity association. Crossplane off: the Secret `external-dns-aws` (static keys, see [below](#the-external-dns-aws-secret)), or an association the client made outside the socle — with no Secret, the SDK's default chain picks it up |
| gcp | `google` (Cloud DNS) | **Crossplane on: the module's own members**, on the ServiceAccount's Workload Identity Federation principal. Crossplane off: the client's — a Google service account bound with Workload Identity, named through `values` as `serviceAccount.annotations."iam.gke.io/gcp-service-account"`, or DNS roles the client grants that principal himself |
| azure | `azure` (Azure DNS) | The client: the Secret `external-dns-azure` with `azure.json`, a service principal, or `useWorkloadIdentityExtension` plus the `azure.workload.identity/client-id` annotation and `azure.workload.identity/use` pod label through `values` |
| scaleway | `scaleway` (Scaleway DNS) | The client: the Secret `external-dns-scaleway` with `SCW_ACCESS_KEY` and `SCW_SECRET_KEY`, an API key scoped to DomainsDNSFullAccess |

The client's Secrets stay outside OpenTofu: the bootstrap has no
`kubernetes` provider, and a credential never enters the artifact or the
state.

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

Nothing more for the AWS role: `enabled` and `domain_filters` build it, with
`kube.crossplane.enabled`, and `route53` in the boundary's allowlist
(`aws.crossplane = { allowed_services = ["route53"] }` in the foundations,
[crossplane.md](crossplane.md) §2). On AWS with both on, the bootstrap's `region` must
be set — the association is regional, and the socle's
`ClusterProviderConfig` names no region — or the plan fails.

On GCP, nothing more in `kube` either: the zones external-dns may write are
the ones the client lists in the foundations, `gcp.crossplane.dns_zones`
(managed zone names, in the cluster's project), the only zones whose IAM
policy Crossplane may set. Nothing goes in `gcp.crossplane.allowed_roles`:
`roles/dns.admin` is granted on a zone, which the zone grant allows, and the
project-level lister role is always among the roles Crossplane may grant.
Each `domain_filters` entry should sit in a listed zone; a name in a zone
that is not listed is refused at write, and only external-dns's log says so.

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
- **The GCP project and zone visibility.** `--google-project` is the
  cluster's project, named rather than read from the metadata server: it is
  where the zones and the members are. `--google-zone-visibility=public`: a
  split-horizon private zone of the same name would match the same filters
  and get every record twice. Both are set as an `extraArgs` map, so that a
  client's `extraArgs` map merges into it; a list would replace it whole.
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
- **Render of the AWS access.** With the sample inputs (Crossplane on, a
  boundary, `eu-west-3`) the `access` step renders `Namespace`, `Role`,
  `PodIdentityAssociation`, then the `workload` step the chart; with
  Crossplane off, or on gcp, only the `Namespace` in `access`. Both managed
  resources pass `kubeconform -strict` against the datree catalog **and**
  against the `provider-upjet-aws` v2.8.1 CRDs themselves
  (`package/crds/iam.aws.m.upbound.io_roles.yaml`,
  `eks.aws.m.upbound.io_podidentityassociations.yaml`), which is where the
  field names were taken from. Two filters, one with a trailing dot and
  capitals, render as
  `["acme.example","*.acme.example","internal.acme.example","*.internal.acme.example"]`
  and the policy parses as JSON.
- **Render of the GCP access.** With `oci/.ci/inputs-sample-gcp.yaml`
  (Crossplane on, one zone) the ResourceSet renders `Namespace`, one
  `ManagedZoneIAMMember` `external-dns-<zone>`, the `ProjectIAMMember`
  `external-dns`, then `external-dns-workload` depending on both; with two
  zones, two members and three dependencies; with no zone, the
  `ProjectIAMMember` alone; with Crossplane off, neither, and no
  `dependsOn`. Both kinds pass `kubeconform -strict` against the
  `provider-upjet-gcp` v3.0.0 CRDs
  (`package/crds/dns.gcp.m.upbound.io_managedzoneiammembers.yaml`,
  `cloudplatform.gcp.m.upbound.io_projectiammembers.yaml`). The gcp
  container args end `--provider=google --google-project=<project>
  --google-zone-visibility=public`, and a client's `extraArgs` map is merged
  in beside them (`helm template` of chart 1.22.0). The AWS render is
  byte-identical to what it was before GCP.
- **`tofu test`.** The bootstrap's runs pass, and each new validation has a
  failing case.
- **e2e, disabled.** Both jobs assert that the `external-dns` ResourceSet
  is Ready while disabled, and that its namespace is absent.
- **e2e, against a fake Route 53.** The `external-dns (aws)` job enables the
  module on floci's k3s on every push, through a `patch` of the
  `ResourceSetInputProvider` — what `kube` sets. The steps are the module's
  own, `tests/e2e/chainsaw-test.yaml` (`external-dns-module-aws`), with
  `records.sh` beside it for what the cluster cannot see:

  | Step | What it proves |
  | --- | --- |
  | a fake hosted zone, and the Secret | A hosted zone `e2e.socle.test` in floci's Route 53, and the `external-dns-aws` Secret with test keys and floci's endpoint as a pod sees it |
  | enabled through kube | `values` overrides the socle's `txtOwnerId`; the Deployment runs with `--policy=upsert-only`, the client's owner and the domain filter |
  | an Ingress and a Service | An Ingress becomes an A record and an ExternalName Service a CNAME, each with a `socle-` TXT naming the client's owner |
  | upsert-only keeps | With `upsert-only`, deleting the Ingress leaves its A record |
  | policy = "sync" deletes | After the patch to `sync`, the A record and its TXT go, and the CNAME stays |
  | enabled = false | Disabling the module removes its namespace |
  | with Crossplane on | The module renders its `Role` and its association |
  | floci seam | floci's own `ClusterProviderConfig`, and both objects pointed at it |
  | the Role becomes an IAM role | `socle-e2e-catalog-external-dns` under `/socle/socle-e2e-catalog/`, trusted by `pods.eks.amazonaws.com`, with the `route53` policy carrying the condition key and `*.e2e.socle.test` — read from what Crossplane reports (`status.atProvider`) |
  | floci seam, second half | The association `Synced=False`, and one minute later still no `HelmRelease`: the workload waits for the association |
  | off | The association released by hand, the IAM role deleted, the namespace gone; Crossplane off last |

  Measured first on a local floci: every step passes with the values the
  template renders for aws. A pod reaches floci over the Docker network both share.
- **Not provable on floci.** The fake Route 53 steps run with Crossplane off
  and the Secret seam; the module's role reaching EKS and the pod using it
  are not provable there, for the reasons in
  [the AWS section](#what-floci-proves-and-what-needs-a-real-account).
  Azure and Scaleway have no DNS emulator; their blocks are proven by render
  only. GCP has none either: its proof is a test run by hand on the
  sandbox's GKE ([below](#what-the-sandbox-proves-on-gcp)).

## The `external-dns-aws` Secret

The aws block reads three optional variables from a Secret named
`external-dns-aws` in the `external-dns` namespace: `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY` and `AWS_ENDPOINT_URL`. When the Secret is absent,
no variable is set, and the SDK uses its default chain — with Crossplane on,
the module's own association. This is how the e2e points external-dns at
floci. It is also the way, with Crossplane off, for a client to give the pod
static keys, or a Route 53-compatible endpoint. Anyone who can write Secrets
in that namespace can redirect external-dns, which is already true of anyone
who can edit its Deployment.

## Annotations: the prefix changed in 0.22

external-dns 0.22.0 reads `external-dns.kubernetes.io/hostname` and
`external-dns.kubernetes.io/target`. The older
`external-dns.alpha.kubernetes.io/` annotations are ignored, measured on
floci: no endpoint is generated from them. The template keeps the upstream
default. Workloads and the other catalog modules must use the new prefix.

## AWS: the module's own role, through Crossplane

The first catalog module that uses the promise of
[crossplane.md](crossplane.md) §3. In the `external-dns` ResourceSet, under
`<< if and (eq inputs.cloud "aws") inputs.modules.crossplane.enabled >>`:

| Object | What it is |
| --- | --- |
| `iam.aws.m.upbound.io/v1beta1` `Role` `external-dns/external-dns` | IAM role `<cluster>-external-dns` (external-name: IAM names are account-wide), path `/socle/<cluster>/`, `permissionsBoundary` from `kube.crossplane.permissions_boundary` when set, trust `pods.eks.amazonaws.com` for `sts:AssumeRole` and `sts:TagSession`, one inline policy `route53` |
| `eks.aws.m.upbound.io/v1beta1` `PodIdentityAssociation` `external-dns/external-dns` | `inputs.cluster.region`, `inputs.cluster.name`, namespace `external-dns`, ServiceAccount `external-dns`, `roleArnRef` to the Role |

Both carry the module's reconcile toggle, so disabling the module deletes
the IAM role and the association. `providerConfigRef` is left at its
default, the socle's `ClusterProviderConfig default` on Pod Identity.

### The Route 53 scope — decided: by record name

Two ways were on the table:

- **By zone.** `ChangeResourceRecordSets` on
  `arn:aws:route53:::hostedzone/<id>` for each zone. The tightest resource
  scope, but a hosted zone id is random: nothing maps `acme.example` to
  `Z0123…`, and Crossplane has no data source to look it up. It would take a
  new `zone_ids` attribute the client must copy from the console and keep in
  step with `domain_filters`.
- **By the boundary alone.** `route53:*` on `*`, bounded by Crossplane's
  boundary once the client allows `route53`. Simple, but the boundary names
  services, not resources ([crossplane.md](crossplane.md) §2): the module's
  role could rewrite every zone of the account, another cluster's or the
  company's apex included. The boundary is a ceiling for the cluster, not a
  scope for a module; §2 says the module's own policy keeps it to what it
  needs.

**Chosen: a third, by record name, with nothing new for the client.**
Route 53 has a condition key on the names in a change batch,
`route53:ChangeResourceRecordSetsNormalizedRecordNames`. The policy allows
`ChangeResourceRecordSets` on every hosted zone only when **every** name in
the batch (`ForAllValues:StringLike`) is a `domain_filters` entry or under
one — `acme.example` and `*.acme.example` for each filter, lowercased and
without the trailing dot, the normalised form the key compares. That is
exactly what `domain_filters` already says external-dns may write, now
enforced by IAM rather than by external-dns alone, with no zone id. The
`socle-` TXT records sit under the same names, so they pass.

What stays on every zone, because Route 53 has no condition key for them:
`GetHostedZone`, `ListResourceRecordSets`, `ListTagsForResource(s)` on
`hostedzone/*`, and `ListHostedZones` and `ListHostedZonesByName` on `*`.
The role can therefore **read** every zone of the account. What the name
condition does not stop: a zone of another cluster delegated **under** one of
this cluster's filters (`team.acme.example` under `acme.example`) is writable
by both; the TXT registry keeps them apart, IAM does not. A client who needs
that separation narrows `domain_filters`.

Not measured yet: floci enforces no IAM policy, so the condition key is
proven only as text in the role's policy, not as a refusal. The sandbox apply
is where a write outside the filters must be seen denied.

### Ordering

The ResourceSet `dependsOn` the `crossplane` ResourceSet, so the providers'
CRDs exist before a `Role` is applied, and nothing waits when Crossplane is
off. Then the chart only after the association: EKS Pod Identity injects the
credentials at pod admission, so a pod admitted before its association never
gets them. The chart lives in the child ResourceSet `external-dns-workload`,
whose `dependsOn` names the Role and the association with
`readyExpr: status.conditions.exists(c, c.type == 'Ready' && c.status == 'True')`
— the crossplane module's own pattern for its ProviderConfig. A role that
never turns Ready — boundary refused, `route53` not in the client's allowlist
— leaves the child waiting, the parent not Ready, and `socle-root` with it;
nothing is half-deployed.

**Measured: `steps` alone do not order this.** The first version put the
managed resources in an `access` step and the chart in a `workload` step, as
[crossplane.md](crossplane.md) §4 describes. On floci the chart was applied
beside an association that never synced. A managed resource that has not
been created yet carries `Synced=False` and **no `Ready` condition**, and
kstatus reads a resource without one as healthy, so the step passed. Only an
explicit `readyExpr` on `Ready=True` holds the workload. §4 of
crossplane.md should say so for the next module.

**Turning Crossplane off together with the module** leaves the two managed
resources without a provider to delete them: their finalizers hold the
namespace. Turn the module off first, Crossplane after.

### What floci proves, and what needs a real account

The second half of `tests/e2e/chainsaw-test.yaml` proves, on every push,
that the rendered objects are valid for the real CRDs, that the Role becomes
an IAM role with the path, the trust and the scoped policy, that the
workload is withheld while the association is not Ready, and that turning
the module off deletes the role. One seam, in steps named as such: the test
points both objects at floci's own `ClusterProviderConfig` after the fact,
as the crossplane module's test does.

What floci cannot carry, so the next person does not rediscover it:

- **floci does not implement `CreatePodIdentityAssociation`.** The EKS call
  is routed to floci's S3 emulation and gets a 404 HTML page. The
  association never becomes `Synced`, and its finalizer cannot complete: the
  e2e releases it by hand.
- **floci's k3s runs no EKS Pod Identity Agent.** Even a synced association
  would hand the pod no credential.
- **floci enforces no IAM policy and ignores `PermissionsBoundary`**, as
  [crossplane.md](crossplane.md) measures. A role that is too broad, or one
  without the boundary, would pass.

So the fake Route 53 steps keep the `external-dns-aws` Secret seam, with
Crossplane off. The proof that external-dns writes Route 53 **as its own
role**, that the boundary is carried, and that a name outside the filters is
refused, is the sandbox EKS apply.

## GCP: the module's own members, through Crossplane

The same promise as on AWS ([crossplane.md](crossplane.md) §3), under
`<< if $gcpAccess >>`, `$gcpAccess` being
`and (eq inputs.cloud "gcp") inputs.modules.crossplane.enabled`:

| Object | What it is |
| --- | --- |
| `dns.gcp.m.upbound.io/v1beta1` `ManagedZoneIAMMember` `external-dns/external-dns-<zone>`, one per zone in `inputs.modules.crossplane.dns_zones` | `roles/dns.admin` on that managed zone, in `inputs.cluster.projectId` |
| `cloudplatform.gcp.m.upbound.io/v1beta1` `ProjectIAMMember` `external-dns/external-dns` | `inputs.modules.crossplane.dns_zone_lister_role`, the foundations' `socleDnsZoneLister_<cluster>`, on the project |

Both name one member, the ServiceAccount's own principal:
`principal://iam.googleapis.com/projects/<project number>/locations/global/workloadIdentityPools/<project id>.svc.id.goog/subject/ns/external-dns/sa/external-dns`.
No Google service account is created: GKE's metadata server hands the pod a
token for that principal, and Cloud DNS checks the members against it. Both
carry the module's reconcile toggle, so disabling the module removes them —
the zone and its records stay. `providerConfigRef` is left at its default,
the socle's `ClusterProviderConfig default` on the providers' own Workload
Identity.

### The Cloud DNS scope — by zone

Route 53's answer, a condition on the record names, does not exist here:
Cloud DNS has no condition on the names in a change. A zone, though, is a
resource IAM binds on, and its name is something the client already knows —
it is the name in the console, not a random id as on Route 53. So the scope
is the zone: `roles/dns.admin` on each zone the client listed in the
foundations' `gcp.crossplane.dns_zones`, the only zones on which the
foundations let Crossplane set IAM. That role on a zone is that zone's
records and its own policy, nothing beyond.

What the zone binding cannot answer: external-dns lists the project's zones
on every loop (`ManagedZones.List`, `provider/google/google.go` in v0.22.0)
to find the zone a name belongs to, whatever zone it then writes. That call
is on the project. The `ProjectIAMMember` grants the foundations' lister
role there, `dns.managedZones.list` and `dns.managedZones.get` and nothing on
records, so external-dns **sees** every zone of the project, and writes in
the listed ones only.

**No zone listed**: no `ManagedZoneIAMMember`, the `ProjectIAMMember`
alone. external-dns starts, lists the zones, matches its domain filters,
and every write it attempts is refused — a 403 in its log, nothing in Cloud
DNS. The plan does not refuse it: which zones a cluster may write is the
foundations' decision, and the bootstrap only reads it.

### Ordering

As on AWS: the ResourceSet `dependsOn` the `crossplane` one, and
`external-dns-workload` `dependsOn` each member with
`readyExpr: status.conditions.exists(c, c.type == 'Ready' && c.status == 'True')`.
Workload Identity has no admission-time injection to wait for — the token
is exchanged on each call — but a member that never turns Ready (Crossplane
off in the foundations, a zone the foundations did not list) must hold the
workload as visibly as on AWS: the child waits, the parent is not Ready, and
`socle-root` with it, rather than a pod that silently writes nothing.

The same caveat on turning Crossplane off together with the module: the
members' finalizers then have no provider to release them. Module first,
Crossplane after.

### What the sandbox proves on GCP

No GKE in CI, and floci-gcp serves neither Workload Identity nor Cloud DNS.
`external-dns-module-gcp`, in `tests/e2e/chainsaw-test.yaml`
(labels `phase: module`, `cloud: gcp`, `platform: gke`), is run by hand on
the sandbox's GKE, with the module on as the sandbox's root sets it. It reads
project, zone and domain from the `ResourceSetInputProvider`, names nothing
of the sandbox itself, and turns nothing off:

| Step | What it proves |
| --- | --- |
| each IAM member is Ready | The `ManagedZoneIAMMember` on the first listed zone and the `ProjectIAMMember` carry `roles/dns.admin` and the lister role for the module's own principal, `Synced` and `Ready`, and GCP reports the same role and member back (`status.atProvider`); the workload's `dependsOn` names one member per listed zone and the project's |
| the workload runs on Cloud DNS | The release Ready, the ServiceAccount without an `iam.gke.io/gcp-service-account` annotation, the Deployment on `--provider=google` with the cluster's project, public zones, the domain filter and the `socle-` TXT prefix |
| a Service's name becomes a CNAME | An `ExternalName` Service annotated `<run namespace>.<domain>`; a Job running `host -t CNAME <name> 8.8.8.8` turns `Complete` — `host` exits non-zero until the record resolves, so the internet is the witness |

The record outlives its Service under `upsert-only`, one CNAME and its TXT
per run, named after the run; with `policy = "sync"` on the sandbox,
external-dns removes both.

## Prerequisite and assumptions for the coordinator

- **The EKS Pod Identity Agent add-on.** The module's role on AWS depends
  on it. It is an `aws_eks_addon` in the bootstrap module, on by default,
  installed before flux-operator (#48).
- **The annotation prefix.** The gateway-api and argocd modules must annotate
  with `external-dns.kubernetes.io/`, not the alpha prefix most tutorials
  still show.
- **`gateway_api.enabled`.** The template reads it through `hasKey`. Once the
  gateway-api module is merged, the attribute always exists and the guard
  is harmless. If that module is named anything else, only the key in the
  template's `sources` line changes.
- **The aws root must wire two values into the bootstrap.** On
  `feat/catalog-crossplane`, `opentofu/clusters/aws/main.tf` computes
  `local.kube` with `kube.crossplane.permissions_boundary`, but its
  `module "socle"` passes `kube = var.kube` and no `region`. Without the
  boundary Crossplane's own policy refuses the Role; without the region the
  plan refuses this module with Crossplane on. The fix is two lines in the
  commit that owns that file, not in this one.
- **Open questions.**
  - DNS zones in another GCP project or Azure subscription than the cluster
    are not supported in v1.
  - Azure zones spread over several resource groups are refused rather than
    handled with several instances.
  - The credential Secrets are manual steps until the module declares its
    own role.
