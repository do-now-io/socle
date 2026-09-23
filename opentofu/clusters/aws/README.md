# Socle on AWS — one apply

The cluster, then Flux and the catalog on it, from one root and one tfvars.

```sh
cp prod.tfvars.example prod.tfvars   # edit
tofu init
tofu apply -var-file=prod.tfvars
```

Upgrading the socle is one line in the tfvars, `socle_version`, then
`tofu init && tofu apply`. In a client's copy the version is also in both
`source` attributes, pointed at the modules package rather than the socle
artifact — one OCI tag cannot carry both shapes (PR #15):

```hcl
source = "oci://ghcr.io/do-now-io/socle/modules//opentofu/aws?tag=${var.socle_version}"
source = "oci://ghcr.io/do-now-io/socle/modules//opentofu/bootstrap?tag=${var.socle_version}"
```

which OpenTofu ≥ 1.8 resolves at init.

## What must exist first

The [foundations prerequisites](../../../docs/aws/prerequisites.md), plus the
`aws` CLI on the machine or runner that applies: the helm provider obtains its
token through `aws eks get-token` at call time, from the same credentials the
aws provider uses. Nothing is stored.

## A private registry

While `ghcr.io/do-now-io/socle` is private, Flux needs a pull secret. Create it
once, outside OpenTofu, then name it in the tfvars:

```sh
kubectl -n flux-system create secret docker-registry ghcr-auth \
  --docker-server=ghcr.io --docker-username=<github user> --docker-password=<token with read:packages>
```

```hcl
artifact_pull_secret = "ghcr-auth"
```

The credential never enters OpenTofu or its state. A public registry needs
none of this.

## Reading the result

```sh
kubectl -n flux-system get resourceset             # socle-root and one per module
kubectl -n flux-system get ocirepository socle     # pulled digest, SourceVerified
```

A green apply proves the objects were deposited; the root `ResourceSet`
reports whether they converged.

## When one apply is not enough

- **Replacing the cluster.** A ForceNew change (the foundations README lists
  them) makes the endpoint unknown at plan, and the helm provider cannot
  refresh its releases: `tofu apply -var-file=prod.tfvars -target=module.foundations`,
  then the full apply.
- **Destroying with the API unreachable.** Releases are deleted before the
  cluster, which is the right order, but it needs the API: if the runner is no
  longer in `cluster_endpoint_public_access_cidrs`, `tofu state rm module.socle`
  first.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0, < 7.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0, < 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_foundations"></a> [foundations](#module\_foundations) | ../../aws | n/a |
| <a name="module_socle"></a> [socle](#module\_socle) | ../../bootstrap | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws"></a> [aws](#input\_aws) | The foundations module's inputs, grouped, plus the region for the aws provider. Required keys are the ones the module leaves without a default; every other key is optional and passes through as-is. | <pre>object({<br/>    region                               = string<br/>    cluster_name                         = string<br/>    owner                                = string<br/>    environment                          = string<br/>    availability_zones                   = list(string)<br/>    cluster_endpoint_public_access_cidrs = list(string)<br/>    kubernetes_version                   = string<br/>    additional_tags                      = optional(map(string))<br/>    create_vpc                           = optional(bool)<br/>    vpc_id                               = optional(string)<br/>    private_subnet_ids                   = optional(list(string))<br/>    public_subnet_ids                    = optional(list(string))<br/>    vpc_cidr                             = optional(string)<br/>    create_nat_gateway                   = optional(bool)<br/>    vpc_flow_logs_enabled                = optional(bool)<br/>    secrets_encryption_enabled           = optional(bool)<br/>    secrets_encryption_kms_key_arn       = optional(string)<br/>    cluster_log_types                    = optional(list(string))<br/>    log_retention_days                   = optional(number)<br/>    force_update_version                 = optional(bool)<br/>  })</pre> | n/a | yes |
| <a name="input_socle_version"></a> [socle\_version](#input\_socle\_version) | The socle release this cluster runs. In a client's copy this variable is also in both module sources (?tag=), so this one line moves foundations, bootstrap and the artifact together. | `string` | n/a | yes |
| <a name="input_artifact_pull_secret"></a> [artifact\_pull\_secret](#input\_artifact\_pull\_secret) | Name of an existing dockerconfigjson Secret in flux-system for a private registry. Empty for a public one; the Secret is created outside OpenTofu. | `string` | `""` | no |
| <a name="input_artifact_url"></a> [artifact\_url](#input\_artifact\_url) | Override of the OCI repository the artifact is pulled from, for a mirror. Null keeps the socle registry. | `string` | `null` | no |
| <a name="input_cosign_identity"></a> [cosign\_identity](#input\_cosign\_identity) | Override of the signature identity the cluster trusts. Null keeps the bootstrap module's default, the release workflow on main. Set it only on a dev cluster testing a branch build. | <pre>object({<br/>    issuer  = string<br/>    subject = string<br/>  })</pre> | `null` | no |
| <a name="input_kube"></a> [kube](#input\_kube) | Catalog modules and their values, as { <module> = { <attribute> = <value> } }. Only what differs from the defaults; validated against the catalog by the bootstrap module. | `any` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_artifact"></a> [artifact](#output\_artifact) | The socle artifact this cluster pulls, as URL and tag. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | The control plane's API endpoint. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the EKS cluster. |
| <a name="output_inputs"></a> [inputs](#output\_inputs) | What the catalog renders from, after normalisation. Compare with kubectl -n flux-system get resourcesetinputprovider socle -o yaml. |
<!-- END_TF_DOCS -->
