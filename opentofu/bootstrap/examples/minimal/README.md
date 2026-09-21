# Minimal bootstrap

Point a cluster at one signed artifact. Everything else comes from the
module's defaults.

```bash
tofu init
tofu apply \
  -var kubeconfig_path=~/.kube/socle-dev.yaml \
  -var sync_url=oci://rg.fr-par.scw.cloud/socle/socle \
  -var sync_ref=v0.1.0
```

The kubeconfig comes from the foundations module, which returns it as a
sensitive output:

```bash
tofu -chdir=../../../scaleway output -raw kubeconfig > ~/.kube/socle-dev.yaml
```

## Order

This runs **after** the foundations apply, against the cluster it created, with
its own state. The two are not one apply: a provider configured from the same
apply that creates the cluster it talks to cannot be planned before that
cluster exists.

## Verifying it worked

```bash
kubectl -n flux-system get fluxinstance flux
kubectl -n flux-system get ocirepository socle
kubectl -n flux-system get kustomization socle
```

The `FluxInstance` reports `Ready` once the operator has reconciled the
controllers. The `OCIRepository` reports the digest it pulled, and — if the
signature patch landed — refuses anything it cannot verify.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0, < 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_bootstrap"></a> [bootstrap](#module\_bootstrap) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_kubeconfig_path"></a> [kubeconfig\_path](#input\_kubeconfig\_path) | Path to a kubeconfig for the target cluster, written from the foundations module's sensitive output. | `string` | n/a | yes |
| <a name="input_sync_ref"></a> [sync\_ref](#input\_sync\_ref) | The tag or digest to pin. No default: pinning is the decision this module exists to record. | `string` | n/a | yes |
| <a name="input_sync_url"></a> [sync\_url](#input\_sync\_url) | The socle artifact this cluster pulls. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Cluster this Flux instance serves. | `string` | `"socle-dev"` | no |
| <a name="input_cluster_type"></a> [cluster\_type](#input\_cluster\_type) | Which cloud this runs on: kubernetes, aws, azure, gcp or openshift. Scaleway is kubernetes — it has no workload identity federation. | `string` | `"kubernetes"` | no |
| <a name="input_cosign_identity"></a> [cosign\_identity](#input\_cosign\_identity) | Keyless identity the artifact's signature must match. | <pre>object({<br/>    issuer  = string<br/>    subject = string<br/>  })</pre> | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment this cluster serves. | `string` | `"dev"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Team accountable for the cluster. | `string` | `"platform"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cosign_verification"></a> [cosign\_verification](#output\_cosign\_verification) | Whether the artifact's signature is verified, and against which identity. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace holding the operator and the Flux controllers. |
| <a name="output_sync_source"></a> [sync\_source](#output\_sync\_source) | What this cluster pulls, and at which pinned reference. |
<!-- END_TF_DOCS -->
