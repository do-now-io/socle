# Socle bootstrap — Flux, on any of the four clouds

One module, no cloud provider. It installs `flux-operator`, a `FluxInstance`
saying which controllers run, and the root source the cluster pulls. After
that OpenTofu owns nothing: the operator converges the Flux controllers, and
Flux converges everything the artifact contains.

```hcl
module "bootstrap" {
  source = "oci://<registry>/<repo>//opentofu/bootstrap?tag=<version>"

  cluster_name = "socle-prod"
  environment  = "prod"
  owner        = "platform"
  cluster_type = "kubernetes" # aws | azure | gcp | openshift

  sync_url = "oci://rg.fr-par.scw.cloud/socle/socle"
  sync_ref = "v1.4.0"

  cosign_identity = {
    issuer  = "https://token.actions.githubusercontent.com"
    subject = "https://github.com/do-now-io/socle/.github/workflows/release.yaml@refs/tags/v1.4.0"
  }
}
```

Why the operator rather than `flux bootstrap` or the `flux` provider, and what
its licence costs: [docs/flux-bootstrap.md](../../docs/flux-bootstrap.md).

## Where it runs

Second, always. The foundations module provisions an empty cluster and steps
away; this one is applied against that cluster, from its own root
configuration and its own state. It is deliberately not part of foundations:
a provider configured from the same apply that creates the cluster it talks to
plans badly and destroys worse, and foundations would go from one provider to
three.

It configures no provider itself, so one configuration can bootstrap several
clusters.

## What is decided for you

| Decision | Position | Traces to |
| --- | --- | --- |
| Installer | `flux-operator`, not the CLI, not `flux_bootstrap_git` | [flux-bootstrap](../../docs/flux-bootstrap.md) |
| Operator version | pinned exactly — it is pre-1.0 | [flux-bootstrap](../../docs/flux-bootstrap.md) |
| Flux version | `2.x`, the operator converges it | [flux-bootstrap](../../docs/flux-bootstrap.md) |
| Source kind | `OCIRepository` — the socle ships as an artifact, not a repository | [flux-bootstrap](../../docs/flux-bootstrap.md) |
| The root source | Ours, not `instance.sync` — see below | [flux-bootstrap](../../docs/flux-bootstrap.md) |
| Pruning | on — a dropped object must leave the cluster | [flux-bootstrap](../../docs/flux-bootstrap.md) |
| Reference | required, and `latest`/`main`/`master`/`HEAD` refused | [flux-bootstrap](../../docs/flux-bootstrap.md) |
| Signature | cosign, verified by Flux on every reconciliation | [flux-bootstrap](../../docs/flux-bootstrap.md) |
| Image automation controllers | absent — the version moves through Git | [flux-bootstrap](../../docs/flux-bootstrap.md) |
| Network policies | on | [flux-bootstrap](../../docs/flux-bootstrap.md) |

## Why the root sync is a chart of our own

The `FluxInstance` has a `sync` block, and using it was the first design. A
real cluster showed it cannot express two things this socle needs:

- **no `verify` field**, so no cosign verification;
- **no `targetNamespace`**, so no home for manifests that declare none.

Expressing the first as a kustomize patch was tried and **does not work**: the
operator applies `instance.kustomize.patches` to the Flux components only, not
to the objects it generates for the sync. The patch finds no target and the
instance goes `Stalled` — nothing is deployed at all, while OpenTofu reports a
clean apply. Measured 21 September 2026; see
[docs/flux-bootstrap.md](../../docs/flux-bootstrap.md#cosign).

So the module ships `chart/`, two objects it owns outright — an
`OCIRepository` with its `verify` block and a `Kustomization` with `prune`,
`wait` and an optional `targetNamespace`. Helm carries them because it is the
only provider here that applies a custom resource without needing its CRD at
plan time, and the instance release runs the chart's health check so the CRDs
exist before the sync release starts.

Worth checking on a new cluster all the same:

```sh
kubectl -n flux-system get ocirepository socle -o jsonpath='{.spec.verify}'
```

## What is deliberately absent

- **A Git bootstrap.** `flux bootstrap` writes Flux's own manifests into a Git
  repository and syncs from there. The socle is distributed as one signed OCI
  artifact, so that would add a distribution channel the product does not have,
  plus a write-scoped Git token per client to create, rotate and revoke.
- **The image automation controllers.** They rewrite image tags in Git from
  what they find in a registry. The socle's version moves by a human bumping a
  tag, reviewed.
- **A `kubernetes` or `kubectl` provider.** Every object here is a Helm value.
  `kubernetes_manifest` needs the cluster reachable at plan time, which makes a
  plan impossible before the cluster exists.
- **Multitenancy, off by default.** It locks cross-namespace source references;
  the catalog has not yet said whether it needs them.

## Integration testing

Plan-only, and not even that in CI: this module talks to a cluster, so a plan
needs one. `tofu test` covers the interface — 20 runs, one per validation
block — and runs in `pr-static.yaml` like every other module's.

Convergence is proven by an apply against a real cluster, and nowhere else.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0, < 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.instance](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.operator](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.sync](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Cluster this Flux instance serves. Stamped on every object the operator creates, so a fleet-wide query can tell them apart. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment this cluster serves. Stamped as a label, and the axis the upgrade ring order follows. | `string` | n/a | yes |
| <a name="input_owner"></a> [owner](#input\_owner) | Team accountable for the cluster. Stamped as a label on every object. | `string` | n/a | yes |
| <a name="input_sync_ref"></a> [sync\_ref](#input\_sync\_ref) | The tag, digest or branch to pin. Required with no default: a floating reference would make "which version is deployed" unanswerable, which is the one question the distribution exists to answer. | `string` | n/a | yes |
| <a name="input_sync_url"></a> [sync\_url](#input\_sync\_url) | Where the cluster pulls the socle from. An oci:// artifact by default — the socle is distributed as one signed OCI artifact, not as a Git repository per client. | `string` | n/a | yes |
| <a name="input_cluster_type"></a> [cluster\_type](#input\_cluster\_type) | Which cloud this runs on. The operator uses it to wire workload identity for the controllers: aws, azure and gcp have federated identity, kubernetes covers Scaleway and anything else. | `string` | `"kubernetes"` | no |
| <a name="input_cosign_identity"></a> [cosign\_identity](#input\_cosign\_identity) | Keyless identity the signature must match, as an object of issuer and subject regexes. Null verifies the signature without pinning who produced it, which is weaker and should be temporary. | <pre>object({<br/>    issuer  = string<br/>    subject = string<br/>  })</pre> | `null` | no |
| <a name="input_cosign_verification_enabled"></a> [cosign\_verification\_enabled](#input\_cosign\_verification\_enabled) | Have Flux verify the artifact's cosign signature before applying it, and on every reconciliation after. This is why the root source is a chart of our own rather than the FluxInstance's sync block, which has no verify field. | `bool` | `true` | no |
| <a name="input_flux_components"></a> [flux\_components](#input\_flux\_components) | Flux controllers to install. The image automation pair is absent by default: the socle's version moves through Git, not through a controller rewriting tags in the cluster. | `list(string)` | <pre>[<br/>  "source-controller",<br/>  "kustomize-controller",<br/>  "helm-controller",<br/>  "notification-controller"<br/>]</pre> | no |
| <a name="input_flux_version"></a> [flux\_version](#input\_flux\_version) | Flux version the operator installs and keeps converged. "2.x" tracks the latest 2 series; an exact version pins it. | `string` | `"2.x"` | no |
| <a name="input_helm_timeout_seconds"></a> [helm\_timeout\_seconds](#input\_helm\_timeout\_seconds) | How long to wait for each release to become ready. The operator reconciles the Flux controllers after its own install, so the instance release is the slow one. | `number` | `600` | no |
| <a name="input_instance_size"></a> [instance\_size](#input\_instance\_size) | Resource profile the operator applies to the controllers. Empty is the operator's own default; small, medium and large scale requests and limits together. | `string` | `""` | no |
| <a name="input_multitenant"></a> [multitenant](#input\_multitenant) | Lock cross-namespace source references, so a tenant Kustomization cannot reference another tenant's source. Off until the catalog states what it needs. | `bool` | `false` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace holding the operator and the Flux controllers. | `string` | `"flux-system"` | no |
| <a name="input_network_policy"></a> [network\_policy](#input\_network\_policy) | Let the operator install network policies isolating the Flux namespace. On by default; Cilium and Dataplane V2 both enforce them. | `bool` | `true` | no |
| <a name="input_operator_version"></a> [operator\_version](#input\_operator\_version) | Chart version of flux-operator, which is also the operator's own version. Pinned exactly: the operator is pre-1.0 and its minors are not a stable contract. | `string` | `"0.60.0"` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | Storage class for the source-controller's artifact cache. Empty uses the cluster default. | `string` | `""` | no |
| <a name="input_sync_digest"></a> [sync\_digest](#input\_sync\_digest) | Digest the tag must resolve to, pinning the artifact by content rather than by name. Empty trusts the tag, which a registry can move. | `string` | `""` | no |
| <a name="input_sync_interval"></a> [sync\_interval](#input\_sync\_interval) | How often the root source is checked. One minute is the operator's own default and costs one registry HEAD request. | `string` | `"1m"` | no |
| <a name="input_sync_kind"></a> [sync\_kind](#input\_sync\_kind) | Source kind the operator creates for the root sync. OCIRepository matches the socle's distribution; GitRepository exists for a client who insists on a repository. | `string` | `"OCIRepository"` | no |
| <a name="input_sync_path"></a> [sync\_path](#input\_sync\_path) | Path inside the artifact the root Kustomization builds. | `string` | `"."` | no |
| <a name="input_sync_prune"></a> [sync\_prune](#input\_sync\_prune) | Delete objects the artifact no longer contains. On: without it a version bump could only ever add, and a removed component would linger. | `bool` | `true` | no |
| <a name="input_sync_pull_secret"></a> [sync\_pull\_secret](#input\_sync\_pull\_secret) | Name of an existing Kubernetes secret holding registry credentials for the artifact. Empty means the registry is public or the node identity is enough. | `string` | `""` | no |
| <a name="input_sync_target_namespace"></a> [sync\_target\_namespace](#input\_sync\_target\_namespace) | Namespace for manifests that carry none of their own. Empty leaves each object where it declares itself, which is what a well-formed socle artifact does. | `string` | `""` | no |
| <a name="input_sync_timeout"></a> [sync\_timeout](#input\_sync\_timeout) | How long the root Kustomization waits for health before failing a reconciliation. | `string` | `"5m"` | no |
| <a name="input_sync_wait"></a> [sync\_wait](#input\_sync\_wait) | Have the root Kustomization report ready only once the objects it applied are themselves healthy. | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cosign_verification"></a> [cosign\_verification](#output\_cosign\_verification) | Whether the root artifact's signature is verified, and against which identity. False means an unsigned or foreign artifact would be applied. |
| <a name="output_flux_version"></a> [flux\_version](#output\_flux\_version) | Flux version the operator converges the controllers to. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace holding the operator and the Flux controllers. |
| <a name="output_operator_version"></a> [operator\_version](#output\_operator\_version) | Version of flux-operator installed, which is also the chart version. |
| <a name="output_sync_name"></a> [sync\_name](#output\_sync\_name) | Name of the root source and Kustomization the operator creates. Immutable in the CRD. |
| <a name="output_sync_source"></a> [sync\_source](#output\_sync\_source) | What this cluster pulls, as kind, URL and pinned reference. |
<!-- END_TF_DOCS -->
