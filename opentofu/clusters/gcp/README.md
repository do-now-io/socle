# Socle on Google Cloud — one apply

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
source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/gcp?tag=${var.socle_version}"
source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/bootstrap?tag=${var.socle_version}"
```

which OpenTofu ≥ 1.8 resolves at init.

## What must exist first

The [foundations prerequisites](../../../docs/gcp/prerequisites.md), plus
`gke-gcloud-auth-plugin` on the machine or runner that applies: the helm
provider obtains its token through it at call time, from the same Application
Default Credentials the google provider uses. Nothing is stored.

The root also declares a stub `aws` provider. The bootstrap module holds the
EKS-managed add-ons, and OpenTofu configures every provider a configuration
names, even one whose resources are all at `count = 0`; the stub skips every
credential and account check and makes no call. No AWS account is involved.

## One cluster per project

A catalog module's identity is a Workload Identity Federation principal,
`principal://…/projects/<number>/…/<project>.svc.id.goog/subject/ns/<ns>/sa/<sa>`:
it names the project, never the cluster. Two socle clusters in one project
would be the same principal for every module — the grants Crossplane makes for
one would serve the other. One socle cluster per project is the supported
topology; give each environment its own project.

## The nodes it starts with

None to size. The cluster is Autopilot: GKE provisions nodes for the pods
that ask for them and bills the pods' requests, so the root has no node group
to configure and nothing for the bootstrap to wait on. GKE also operates the
network (Dataplane V2) and cluster DNS, and installs the Gateway API CRDs: the
bootstrap installs none of them here.

## Values the root derives for you

- `kube.crossplane.dns_records_role`, from the foundations, when
  `gcp.crossplane` is set: the custom role Crossplane grants external-dns on
  the project to write DNS records — project-level, since a zone's own IAM
  is never honoured, so it reaches every zone of the project, bounded by
  external-dns's domain filters.
- `kube.external_dns`: on, filtered to `gcp.gateway_certificate.domains`
  (a wildcard counted once by its apex), when that certificate is requested
  and Crossplane can give external-dns its binding — `kube.crossplane.enabled`
  and `gcp.crossplane` set. Every route on
  the Gateways is `<name>.<domain>`, so that domain is the zone it writes to.

The project's id and number, and the two certificates the shared Gateways
terminate TLS with, come from the foundations too; they are not client inputs.

What you write under `kube` always wins: `external_dns = { enabled = false }`
turns it off, `domain_filters` replaces the derived one.

## A private registry

While `ghcr.io/do-now-io/socle/flux-modules` is private, Flux needs a pull secret. Create it
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

- **Replacing the cluster.** A ForceNew change makes the DNS endpoint unknown
  at plan, and the helm provider cannot refresh its releases:
  `tofu apply -var-file=prod.tfvars -target=module.foundations`, then the
  full apply.
- **Changing `gcp.gateway_certificate.domains`.** A certificate's domains
  cannot change in place, so the apply creates two new certificates before
  deleting the old ones. They are created, not issued: the public Gateway's
  map moves to its new certificate at once, and TLS fails there until Google
  has issued it — minutes, once the authorization records resolve. The
  internal Gateway moves only when Flux reconciles the new certificate's
  name, after the apply has tried to delete the old one: expect an "in use"
  error, wait for the Gateway to name the new certificate, and apply again.
- **Destroying.** The cluster carries deletion protection: set
  `gcp.deletion_protection = false` and apply before `tofu destroy`. Releases
  are deleted before the cluster, which needs the API: if the runner can no
  longer reach it, `tofu state rm module.socle` first. The catalog is also
  uninstalled before Crossplane's grants are removed — it reads Crossplane's
  principal off them — so Crossplane still holds them while it deletes every
  module's binding. After a `state rm`, nothing deletes those bindings: they
  stay in the project, and a socle created there next inherits them; remove
  them by hand.
- **Destroying takes two runs.** GKE's Gateway controller removes the
  Gateways' load balancers asynchronously, after the cluster is gone, so the
  first `tofu destroy` fails on what those load balancers still reference:
  the certificate map ("can't delete certificate map that is referenced by a
  target proxy"), the regional certificate ("referenced by a
  CertificateMapEntry or other resources") and the proxy-only subnetwork
  ("already being used"). A few minutes later a second `tofu destroy`
  completes. Measured on a sandbox (2026-10-07): the first run otherwise
  removed everything, and no Workload Identity binding was left in the
  project policy — the catalog, and with it Crossplane's deletion of each
  module's bindings, ran before Crossplane's own grants went. The Velero
  bucket is kept, by design.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0, < 7.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 8.0, < 9.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0, < 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_foundations"></a> [foundations](#module\_foundations) | ../../gcp | n/a |
| <a name="module_socle"></a> [socle](#module\_socle) | ../../bootstrap | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_gcp"></a> [gcp](#input\_gcp) | The foundations module's inputs, grouped; project\_id and region also configure the google provider. Required keys are the ones the module leaves without a default; every other key is optional and passes through as-is. | <pre>object({<br/>    project_id                               = string<br/>    region                                   = string<br/>    cluster_name                             = string<br/>    owner                                    = string<br/>    environment                              = string<br/>    maintenance_window                       = object({ start_time = string, end_time = string, recurrence = string })<br/>    project_number                           = optional(string)<br/>    additional_labels                        = optional(map(string))<br/>    network_name                             = optional(string)<br/>    create_network                           = optional(bool)<br/>    create_subnetwork                        = optional(bool)<br/>    subnetwork_name                          = optional(string)<br/>    pod_range_name                           = optional(string)<br/>    node_range_cidr                          = optional(string)<br/>    pod_range_cidr                           = optional(string)<br/>    proxy_only_range_cidr                    = optional(string)<br/>    create_proxy_only_subnet                 = optional(bool)<br/>    create_nat                               = optional(bool)<br/>    subnet_flow_logs_enabled                 = optional(bool)<br/>    enable_private_nodes                     = optional(bool)<br/>    control_plane_ip_endpoints_enabled       = optional(bool)<br/>    control_plane_dns_allow_external_traffic = optional(bool)<br/>    gateway_api_enabled                      = optional(bool)<br/>    release_channel                          = optional(string)<br/>    maintenance_exclusions                   = optional(list(object({ name = string, start_time = string, end_time = string, scope = string })))<br/>    kubernetes_min_version                   = optional(string)<br/>    enable_upgrade_notifications             = optional(bool)<br/>    logging_components                       = optional(list(string))<br/>    monitoring_components                    = optional(list(string))<br/>    cost_allocation_enabled                  = optional(bool)<br/>    backup_agent_enabled                     = optional(bool)<br/>    billing_export_dataset_id                = optional(string)<br/>    billing_export_dataset_location          = optional(string)<br/>    observability_reader_members             = optional(list(string))<br/>    deletion_protection                      = optional(bool)<br/>    crossplane                               = optional(object({ allowed_roles = optional(list(string), []) }))<br/>    gateway_certificate                      = optional(object({ dns_zone = string, domains = list(string) }))<br/>  })</pre> | n/a | yes |
| <a name="input_socle_version"></a> [socle\_version](#input\_socle\_version) | The socle release this cluster runs. In a client's copy this variable is also in both module sources (?tag=), so this one line moves foundations, bootstrap and the artifact together. | `string` | n/a | yes |
| <a name="input_artifact_pull_secret"></a> [artifact\_pull\_secret](#input\_artifact\_pull\_secret) | Name of an existing dockerconfigjson Secret in flux-system for a private registry. Empty for a public one; the Secret is created outside OpenTofu. | `string` | `""` | no |
| <a name="input_artifact_url"></a> [artifact\_url](#input\_artifact\_url) | Override of the OCI repository the artifact is pulled from, for a mirror. Null keeps the socle registry. | `string` | `null` | no |
| <a name="input_cosign_identity"></a> [cosign\_identity](#input\_cosign\_identity) | Override of the signature identity the cluster trusts. Null keeps the bootstrap module's default, the release workflow on main. Set it only on a dev cluster testing a branch build. | <pre>object({<br/>    issuer  = string<br/>    subject = string<br/>  })</pre> | `null` | no |
| <a name="input_kube"></a> [kube](#input\_kube) | Catalog modules and their values, as { <module> = { <attribute> = <value> } }. Only what differs from the defaults; validated against the catalog by the bootstrap module. | `any` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_artifact"></a> [artifact](#output\_artifact) | The socle artifact this cluster pulls, as URL and tag. |
| <a name="output_cluster_dns_endpoint"></a> [cluster\_dns\_endpoint](#output\_cluster\_dns\_endpoint) | The control plane's DNS endpoint, the access path the socle and its automation use. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the GKE cluster. |
| <a name="output_inputs"></a> [inputs](#output\_inputs) | What the catalog renders from, after normalisation. Compare with kubectl -n flux-system get resourcesetinputprovider socle -o yaml. |
<!-- END_TF_DOCS -->
