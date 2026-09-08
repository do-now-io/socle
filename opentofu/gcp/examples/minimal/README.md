# Minimal example

A socle foundation with everything left at its recommended position: an
Autopilot cluster on the Regular release channel, private nodes, a DNS-based
control plane endpoint, Cloud NAT, and the identity the in-cluster Crossplane
provider assumes.

```bash
tofu init
tofu apply -var project_id=my-project
```

## Remote state

There is no backend block here, and the module does not create one. State
belongs in the consumer's own account:

```hcl
terraform {
  backend "gcs" {
    bucket = "my-tofu-state"
    prefix = "socle/gcp/dev"
  }
}
```

## Roles the apply needs

The identity running this — a CI runner federated through Workload Identity
Federation, never a key — needs, on the target project:

| Role | For |
| --- | --- |
| `roles/container.admin` | the GKE cluster |
| `roles/compute.networkAdmin` | VPC, subnetworks, router and NAT |
| `roles/iam.serviceAccountAdmin` | the Crossplane service account |
| `roles/resourcemanager.projectIamAdmin` | binding roles to it |
| `roles/pubsub.admin` | the upgrade-notification topic |
| `roles/bigquery.admin` | only when `billing_export_dataset_id` is set |

## After the apply

One step does not belong to any apply: **linking the billing account to the
BigQuery dataset** for the detailed cost export. Google exposes no API for it,
so it is a Cloud Console action. Nothing breaks without it — the cost data
simply never arrives.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 8.0, < 9.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_socle"></a> [socle](#module\_socle) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Google Cloud project to deploy into. Must be empty of a conflicting VPC named after the cluster. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the cluster. | `string` | `"socle-minimal"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment this cluster serves. | `string` | `"dev"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Team accountable for the cluster. | `string` | `"platform"` | no |
| <a name="input_region"></a> [region](#input\_region) | Region for the cluster and its subnetwork. | `string` | `"europe-west1"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Base64-encoded cluster CA certificate. |
| <a name="output_cluster_dns_endpoint"></a> [cluster\_dns\_endpoint](#output\_cluster\_dns\_endpoint) | Control plane DNS endpoint. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the cluster. |
| <a name="output_crossplane_service_account_email"></a> [crossplane\_service\_account\_email](#output\_crossplane\_service\_account\_email) | Identity the in-cluster Crossplane provider assumes. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | The cluster's OIDC issuer URL. |
| <a name="output_upgrade_notifications_topic"></a> [upgrade\_notifications\_topic](#output\_upgrade\_notifications\_topic) | Pub/Sub topic carrying GKE upgrade notifications. |
| <a name="output_workload_identity_pool"></a> [workload\_identity\_pool](#output\_workload\_identity\_pool) | The Workload Identity Federation pool. |
<!-- END_TF_DOCS -->
