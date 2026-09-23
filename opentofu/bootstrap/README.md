# Socle bootstrap — Flux, and the inputs the catalog renders from

One module for four clouds, `helm` as its only provider. It installs
`flux-operator`, a `FluxInstance`, and two literal objects: the client's inputs
and the root source. After that OpenTofu owns those three releases and nothing
else: the operator renders the catalog from the inputs, Flux converges it.

```hcl
module "socle" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/bootstrap?tag=${var.socle_version}"

  cloud        = "aws"
  cluster_name = "acme-prod"
  environment  = "prod"
  owner        = "platform"

  kube = {
    hello = { replicas = 2 }
  }
}
```

The design, and the measurements behind it: [docs/flux-catalog.md](../../docs/flux-catalog.md).

## Where it runs

In the same root as the foundations module, in one apply — see
`opentofu/clusters/<cloud>/`. It configures no provider itself; the root passes
the foundations module's `helm_kubernetes` output to the `helm` provider.

## The catalog schema

`kube` is `{ <module> = { <attribute> = <value> } }`. Only what differs from a
default needs writing; an unknown module or attribute, or a value of the wrong
type, is an error at plan, with the allowed list in the message.

| Module | Attribute | Default | Meaning |
| --- | --- | --- | --- |
| `hello` | `enabled` | `true` | Deploy podinfo as a proof the pipeline works |
| `hello` | `replicas` | `1` | Replicas of the podinfo Deployment |
| `hello` | `message` | `"hello from socle"` | Message podinfo serves |

The schema lives in `catalog.tf`; the templates in `oci/catalog/<module>/`;
each `oci/clusters/<cloud>/kustomization.yaml` lists the modules that cloud
offers, and `catalog_clouds` in `catalog.tf` names the clouds a module is bound
to (absent = every cloud). All of it changes in the same release, and CI
(`.github/scripts/check-catalog-clouds.sh`) fails when the overlays and the
schema disagree.

## Cilium, before Flux

On `aws` and `azure` the foundations create a cluster with no CNI, and
nothing without `hostNetwork`, Flux included, starts until one runs. This
module therefore installs, before `flux-operator`, the Gateway API CRDs
(standard channel, vendored in `gateway-api-crds/`), Cilium, and on `aws`
CoreDNS. On `gcp` and `scaleway` the cloud operates Cilium and none of this
exists. The root passes `cluster_network` from the foundations' outputs:

```hcl
cilium = { hubble = true }            # optional: enabled, hubble, gateway_api
cluster_network = {
  api_endpoint = module.foundations.cluster_endpoint
  service_cidr = module.foundations.service_cidr   # aws
  # pod_cidr   = module.foundations.pod_cidr       # azure
}
```

The templates see what was decided as `inputs.cilium.{installed, gatewayApi,
hubble}`. The design and what was measured are in
[docs/catalog/cilium.md](../../docs/catalog/cilium.md).

## What is decided for you

| Decision | Position |
| --- | --- |
| Templating | Flux Operator `ResourceSet`s in the artifact — never Helm, never OpenTofu |
| What OpenTofu ships | Inputs only: one `ResourceSetInputProvider`, one root `ResourceSet` |
| Applier | `helm_release` over `manifests/`, the one provider that needs no CRD at plan |
| Version | `socle_version` defaults to this module's own; one tag bump moves everything |
| Signature | cosign keyless, verified by Flux on every reconciliation, cannot be disabled |
| Default identity | the release workflow on `main` — a branch build needs an explicit override |
| Source kind | OCI only |
| Namespace | `flux-system`, fixed |
| CNI on aws and azure | Cilium 1.20.2, pinned here: ENI IPAM on aws, BYOCNI overlay on azure, kube-proxy replacement on both |
| DNS on aws | CoreDNS by Helm after Cilium; the EKS add-on cannot exist before a CNI |

## Reading the result

```sh
kubectl -n flux-system get resourcesetinputprovider socle -o yaml   # what the client declared
kubectl -n flux-system get resourceset                              # socle-root and one per module, with Ready
kubectl -n flux-system get ocirepository socle                      # the pulled digest, and SourceVerified
```

Helm's `wait` does not wait for a custom resource to be Ready, so a green
apply proves the objects were deposited, not that they converged. The root
`ResourceSet` (`wait: true`) is the convergence signal; CI reads it.

## Testing

`tofu test` covers the interface — one failing case per validation, and the
defaults and normalisation with a mocked helm provider. Convergence is proven
by `publish-artifact.yaml`'s `e2e-aws-root` and `e2e-aws-catalog` jobs, which
apply on floci against the artifact the same commit published; the
integration legs plan only.

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
| [helm_release.cilium](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.coredns](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.gateway_api_crds](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.instance](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.operator](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.socle](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cloud"></a> [cloud](#input\_cloud) | Which cloud this cluster runs on. Selects the artifact's clusters/<cloud> overlay and the operator's workload identity wiring. Scaleway has no federation the operator knows, so it runs as a plain kubernetes cluster. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Cluster this socle serves. Stamped on every object the operator creates, and exposed to the catalog as inputs.cluster.name. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment this cluster serves. Stamped as a label, exposed as inputs.cluster.environment, and the axis the upgrade rings follow. | `string` | n/a | yes |
| <a name="input_owner"></a> [owner](#input\_owner) | Team accountable for the cluster. Stamped as a label on every object. | `string` | n/a | yes |
| <a name="input_artifact_pull_secret"></a> [artifact\_pull\_secret](#input\_artifact\_pull\_secret) | Name of an existing kubernetes.io/dockerconfigjson Secret in flux-system that Flux uses to pull the artifact from a private registry. Empty for a public registry. The Secret is created outside this module — a credential never enters OpenTofu. | `string` | `""` | no |
| <a name="input_artifact_url"></a> [artifact\_url](#input\_artifact\_url) | OCI repository the socle artifact is pulled from. Override for a mirror; the tag is socle\_version. | `string` | `"oci://ghcr.io/do-now-io/socle/flux-modules"` | no |
| <a name="input_cilium"></a> [cilium](#input\_cilium) | The socle's Cilium, on the clouds whose foundations create a cluster with<br/>no CNI — aws and azure — as `{ enabled, hubble, gateway_api }`, every key<br/>optional: `enabled` (true) installs it before Flux; false means the<br/>cluster brings its own CNI and DNS, which only a test double does.<br/>`hubble` (false) adds Hubble Relay and UI. `gateway_api` (true) makes<br/>Cilium serve the `cilium` GatewayClass. Refused on gcp and scaleway, where<br/>the cloud operates Cilium. Typed `any` and validated like `kube`, so a<br/>misspelt key is an error at plan. Chart versions are pinned in cilium.tf. | `any` | `{}` | no |
| <a name="input_cluster_network"></a> [cluster\_network](#input\_cluster\_network) | What Cilium needs to know about the cluster, from the foundations'<br/>outputs, never from the client: `api_endpoint`, the API server as EKS<br/>returns it (https://host) or AKS does (a bare FQDN), for kube-proxy<br/>replacement; `service_cidr`, the service range, whose `.10` is CoreDNS's<br/>address on aws; `pod_cidr`, Cilium's pool on azure, where the VNet holds<br/>nodes only. Required wherever the socle installs Cilium, ignored<br/>elsewhere. | <pre>object({<br/>    api_endpoint = string<br/>    service_cidr = optional(string)<br/>    pod_cidr     = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_cosign_identity"></a> [cosign\_identity](#input\_cosign\_identity) | Keyless identity the artifact's signature must match, as issuer and subject regexes. Defaults to the socle's release workflow on main, so production never consumes a branch build by accident. Override on a dev cluster testing a branch. Null means this default. Verification cannot be disabled. | <pre>object({<br/>    issuer  = string<br/>    subject = string<br/>  })</pre> | <pre>{<br/>  "issuer": "^https://token\\.actions\\.githubusercontent\\.com$",<br/>  "subject": "^https://github\\.com/do-now-io/socle/\\.github/workflows/publish-artifact\\.yaml@refs/heads/main$"<br/>}</pre> | no |
| <a name="input_flux_components"></a> [flux\_components](#input\_flux\_components) | Flux controllers to install. The image automation pair is absent by default: the socle's version moves through a reviewed tfvars change, not through a controller rewriting tags. | `list(string)` | <pre>[<br/>  "source-controller",<br/>  "kustomize-controller",<br/>  "helm-controller",<br/>  "notification-controller"<br/>]</pre> | no |
| <a name="input_flux_version"></a> [flux\_version](#input\_flux\_version) | Flux version the operator installs and keeps converged. 2.x tracks the latest 2 series; an exact version pins it. | `string` | `"2.x"` | no |
| <a name="input_helm_timeout_seconds"></a> [helm\_timeout\_seconds](#input\_helm\_timeout\_seconds) | How long to wait for each release to become ready. The instance release is the slow one: its health check waits for the operator to converge the controllers. | `number` | `600` | no |
| <a name="input_instance_size"></a> [instance\_size](#input\_instance\_size) | Resource profile the operator applies to the controllers. Empty is the operator's own default; small, medium and large scale requests and limits together. | `string` | `""` | no |
| <a name="input_kube"></a> [kube](#input\_kube) | The catalog modules this cluster enables and their values, as<br/>`{ <module> = { <attribute> = <value> } }`. List only what differs from<br/>the catalog's defaults; an absent module is at its default. Module names<br/>are snake\_case. Typed `any` on purpose: a map(any) refuses two modules with<br/>different attributes, and an object type silently drops a misspelt<br/>attribute — the validations below are what makes a typo an error at plan.<br/>The schema is catalog.tf; the README lists it module by module. | `any` | `{}` | no |
| <a name="input_network_policy"></a> [network\_policy](#input\_network\_policy) | Let the operator install network policies isolating the Flux namespace. On by default; Cilium enforces them on every cloud we ship. | `bool` | `true` | no |
| <a name="input_operator_version"></a> [operator\_version](#input\_operator\_version) | Chart version of flux-operator, which is also the operator's own version. Pinned exactly: the operator is pre-1.0 and its minors are not a stable contract. | `string` | `"0.60.0"` | no |
| <a name="input_socle_version"></a> [socle\_version](#input\_socle\_version) | Tag of the socle artifact to pull. Null means this module's own version, so that one bump of the module tag moves module and artifact together. Set it only on a dev cluster testing a branch build, together with cosign\_identity. | `string` | `null` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | Storage class for the source-controller's artifact cache. Empty uses the cluster default. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_artifact"></a> [artifact](#output\_artifact) | The socle artifact, as OCI URL and tag. |
| <a name="output_cilium"></a> [cilium](#output\_cilium) | Whether this module installed Cilium (aws, azure: the clouds whose foundations create a cluster with no CNI), with the chart versions it pinned. installed is false where the cloud operates Cilium, or when cilium.enabled is false. |
| <a name="output_cosign_identity"></a> [cosign\_identity](#output\_cosign\_identity) | Keyless identity the artifact's signature is verified against, on every reconciliation. |
| <a name="output_flux_version"></a> [flux\_version](#output\_flux\_version) | Flux version the operator converges the controllers to. |
| <a name="output_inputs"></a> [inputs](#output\_inputs) | What this module ships into the cluster as the ResourceSetInputProvider's defaultValues, after normalisation against the catalog. The catalog's templates read exactly these paths. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace holding the operator, the Flux controllers and the socle's inputs. |
| <a name="output_operator_version"></a> [operator\_version](#output\_operator\_version) | Version of flux-operator installed, which is also its chart version. |
| <a name="output_socle_version"></a> [socle\_version](#output\_socle\_version) | Tag of the socle artifact the cluster pulls. |
<!-- END_TF_DOCS -->
