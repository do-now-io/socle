# Socle on AWS — one apply

The client root for AWS: the foundations ([`opentofu/aws`](../../aws)), then
the bootstrap module ([`opentofu/bootstrap`](../../bootstrap)) — Cilium,
CoreDNS, the EKS add-ons, Flux — from one tfvars and one `tofu apply`. In
the repository both module sources are relative, and this is the root CI
applies. A first cluster, step by step:
[AWS quickstart](../../../docs/getting-started/aws.md).

```sh
cp prod.tfvars.example prod.tfvars   # edit
tofu init
tofu apply -var-file=prod.tfvars
```

In a client's copy both sources point at the published modules package, the
version taken from the tfvars, which OpenTofu resolves at `tofu init`
(`tofu init -var-file=prod.tfvars`):

```hcl
source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/aws?tag=${var.socle_version}"
source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/bootstrap?tag=${var.socle_version}"
```

Upgrading is then one line, `socle_version`
([upgrade](../../../docs/guides/upgrade.md)). Prerequisites:
[AWS prerequisites](../../../docs/clouds/aws/prerequisites.md).

## In what order

The foundations create one node group, the bootstrap group: two 4 vCPU
Graviton nodes on Spot, untainted, sized for the socle, not for workloads
(`aws.bootstrap_node_*` change it). Cilium is installed beside the group, not
after it: its nodes are Ready only once Cilium runs on them. CoreDNS, the
EKS add-ons, Flux and the catalog wait for the group, and a
`bootstrap_node_count` of zero is refused at plan. The Pod Identity Agent
comes before Flux, the snapshot controller and the storage drivers after
CoreDNS.

## Values the root derives for you

- `kube.crossplane.permissions_boundary`, from the foundations' boundary,
  when `aws.crossplane` is set.
- `kube.external_dns`: on, filtered to `aws.gateway_certificate.domain`,
  when that certificate is requested and Crossplane can give external-dns
  its role — `kube.crossplane.enabled`, `aws.crossplane` set, `route53` in
  its `allowed_services`.

What you write under `kube` always wins: `external_dns = { enabled = false }`
turns it off, `domain_filters` replaces the derived one.

## A mirror

`ghcr.io/do-now-io/socle/flux-modules`, the artifact Flux pulls, is public:
no pull secret. A mirror (`artifact_url`) that needs credentials takes a
`dockerconfigjson` Secret created in `flux-system` outside OpenTofu, named in
`artifact_pull_secret`:
[private registry](../../../docs/guides/private-registry.md).

## Reading the result

```sh
kubectl -n flux-system get resourceset             # socle-root and one per module
kubectl -n flux-system get ocirepository socle     # pulled digest, SourceVerified
```

A green apply proves the objects were deposited; the root `ResourceSet`
reports whether they converged.

## When one apply is not enough

- **Replacing the cluster.** A change that replaces the EKS cluster makes
  the endpoint unknown at plan, and the helm provider cannot refresh its
  releases: `tofu apply -var-file=prod.tfvars -target=module.foundations`,
  then the full apply.
- **Destroying with the API unreachable.** Releases are deleted before the
  cluster, and all but Cilium before the bootstrap nodes, which needs the
  API: if the runner is no longer in
  `cluster_endpoint_public_access_cidrs`, `tofu state rm module.socle` first.

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
| <a name="input_aws"></a> [aws](#input\_aws) | The foundations module's inputs, grouped, plus the region for the aws provider. Required keys are the ones the module leaves without a default; every other key is optional and passes through as-is. | <pre>object({<br/>    region                               = string<br/>    cluster_name                         = string<br/>    owner                                = string<br/>    environment                          = string<br/>    availability_zones                   = list(string)<br/>    cluster_endpoint_public_access_cidrs = list(string)<br/>    kubernetes_version                   = string<br/>    additional_tags                      = optional(map(string))<br/>    create_vpc                           = optional(bool)<br/>    vpc_id                               = optional(string)<br/>    private_subnet_ids                   = optional(list(string))<br/>    public_subnet_ids                    = optional(list(string))<br/>    vpc_cidr                             = optional(string)<br/>    create_nat_gateway                   = optional(bool)<br/>    vpc_flow_logs_enabled                = optional(bool)<br/>    secrets_encryption_enabled           = optional(bool)<br/>    secrets_encryption_kms_key_arn       = optional(string)<br/>    cluster_log_types                    = optional(list(string))<br/>    log_retention_days                   = optional(number)<br/>    force_update_version                 = optional(bool)<br/>    bootstrap_node_instance_types        = optional(list(string))<br/>    bootstrap_node_capacity_type         = optional(string)<br/>    bootstrap_node_count                 = optional(number)<br/>    crossplane                           = optional(object({ allowed_services = optional(list(string), []) }))<br/>    gateway_certificate                  = optional(object({ domain = string, zone = optional(string) }))<br/>  })</pre> | n/a | yes |
| <a name="input_socle_version"></a> [socle\_version](#input\_socle\_version) | The socle release this cluster runs. In a client's copy this variable is also in both module sources (?tag=), so this one line moves foundations, bootstrap and the artifact together. | `string` | n/a | yes |
| <a name="input_artifact_pull_secret"></a> [artifact\_pull\_secret](#input\_artifact\_pull\_secret) | Name of an existing dockerconfigjson Secret in flux-system for a private registry. Empty for a public one; the Secret is created outside OpenTofu. | `string` | `""` | no |
| <a name="input_artifact_url"></a> [artifact\_url](#input\_artifact\_url) | Override of the OCI repository the artifact is pulled from, for a mirror. Null keeps the socle registry. | `string` | `null` | no |
| <a name="input_cilium"></a> [cilium](#input\_cilium) | The socle's Cilium, installed before Flux because EKS is created with no CNI: { enabled = true, hubble = false, gateway\_api = true, values = {} }, every key optional. values is any Cilium chart value, the client's winning; private keys are refused, name a Secret instead. Validated by the bootstrap module. enabled = false is for a cluster that brings its own CNI and DNS — the e2e test double, never a real EKS. | `any` | `{}` | no |
| <a name="input_coredns"></a> [coredns](#input\_coredns) | The CoreDNS installed right after Cilium: { values = {} }. values is any CoreDNS chart value, the client's winning. Validated by the bootstrap module. | `any` | `{}` | no |
| <a name="input_cosign_identity"></a> [cosign\_identity](#input\_cosign\_identity) | Override of the signature identity the cluster trusts. Null keeps the bootstrap module's default, the release workflow on main. Set it only on a dev cluster testing a branch build. | <pre>object({<br/>    issuer  = string<br/>    subject = string<br/>  })</pre> | `null` | no |
| <a name="input_eks_addons"></a> [eks\_addons](#input\_eks\_addons) | The EKS-managed add-ons installed once the nodes run: { pod\_identity\_agent = true, ebs\_csi = true, efs\_csi = false, snapshot\_controller = true }, every key optional. The Pod Identity Agent is what every catalog module's AWS identity, Crossplane's included, gets its credentials from; the two storage drivers need it. The snapshot controller is what the velero module's EBS snapshots need. Versions pinned by the bootstrap module, which validates this. | `any` | `{}` | no |
| <a name="input_kube"></a> [kube](#input\_kube) | Catalog modules and their values, as { <module> = { <attribute> = <value> } }. Only what differs from the defaults; validated against the catalog by the bootstrap module. | `any` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_artifact"></a> [artifact](#output\_artifact) | The socle artifact this cluster pulls, as URL and tag. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | The control plane's API endpoint. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the EKS cluster. |
| <a name="output_inputs"></a> [inputs](#output\_inputs) | What the catalog renders from, after normalisation. Compare with kubectl -n flux-system get resourcesetinputprovider socle -o yaml. |
<!-- END_TF_DOCS -->
