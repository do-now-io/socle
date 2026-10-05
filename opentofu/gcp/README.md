# Socle foundations — Google Cloud

One flat root module: a VPC (or yours), a GKE Autopilot cluster with private
nodes and a DNS-based control plane endpoint, Cloud NAT, and the project
bindings that go with them. It provisions an empty cluster, then steps away:
the catalog arrives through the [bootstrap](../bootstrap/README.md) and Flux.

What it decides for you, what it refuses, and why:
[GCP foundations](../../docs/clouds/gcp/foundations.md). What the project
needs before an apply: [GCP prerequisites](../../docs/clouds/gcp/prerequisites.md).

## Usage

```hcl
module "socle" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/gcp?tag=${var.socle_version}"

  project_id   = "my-project"
  region       = "europe-west1"
  cluster_name = "socle-prod"
  owner        = "platform"
  environment  = "prod"

  create_network = true

  maintenance_window = {
    start_time = "2026-01-03T02:00:00Z"
    end_time   = "2026-01-03T14:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA"
  }
}
```

A deployable version is [`examples/minimal`](examples/minimal/README.md); the
full root, with the bootstrap, is in the
[GCP quickstart](../../docs/getting-started/gcp.md).

> **OpenTofu does not verify OCI signatures.** It pulls an unsigned or
> tampered artifact without complaint — Flux does verify, this does not. Run
> `cosign verify` in CI before `tofu init`, or enforce it through registry
> policy: [distribution](../../docs/architecture/distribution.md).

After the apply, one step is manual: linking the billing account to the
BigQuery dataset `billing_export_dataset_id` creates. Google exposes no API
for it ([GCP limits](../../docs/clouds/gcp/limits.md#what-no-apply-can-finish)).

## Testing

```bash
tofu test          # every validation, and the defaults
```

CI also plans [`tests/emulator`](tests/emulator/main.tf) against the
floci-gcp emulator. What that proves and what it does not is in
[CONTRIBUTING.md](../../CONTRIBUTING.md#what-each-check-proves).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 8.0, < 9.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_bigquery_dataset.billing_export](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/bigquery_dataset) | resource |
| [google_compute_network.socle](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network) | resource |
| [google_compute_router.socle](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router) | resource |
| [google_compute_router_nat.socle](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router_nat) | resource |
| [google_compute_subnetwork.proxy_only](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork) | resource |
| [google_compute_subnetwork.socle](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork) | resource |
| [google_container_cluster.socle](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_cluster) | resource |
| [google_project_iam_member.observability_reader](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_pubsub_topic.upgrade_notifications](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the GKE cluster. Also prefixes the network resources the module creates. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment this cluster serves. Stamped as a label, and the axis the upgrade ring order follows. | `string` | n/a | yes |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | When GKE may touch this cluster. Required on purpose — a silent default<br/>would mean nobody decided when production gets upgraded, and the day of<br/>the week is what orders a dev/staging/prod ring.<br/><br/>start\_time and end\_time are RFC3339 timestamps whose difference is the<br/>window length; recurrence is an RFC5545 RRULE. At least 48 hours of<br/>maintenance availability must remain in any 92-day rolling window, and<br/>only contiguous blocks of four hours or more count. | <pre>object({<br/>    start_time = string<br/>    end_time   = string<br/>    recurrence = string<br/>  })</pre> | n/a | yes |
| <a name="input_owner"></a> [owner](#input\_owner) | Team accountable for the cluster. Stamped as a label on every billable resource. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Google Cloud project that holds the cluster and its network. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region of the cluster and its subnetwork. The cluster is regional; zonal clusters are not offered. | `string` | n/a | yes |
| <a name="input_additional_labels"></a> [additional\_labels](#input\_additional\_labels) | Extra labels merged onto the standard set. Cannot override owner, environment or socle-version. | `map(string)` | `{}` | no |
| <a name="input_backup_agent_enabled"></a> [backup\_agent\_enabled](#input\_backup\_agent\_enabled) | Install the Backup for GKE agent. Off by default: $9 per protected namespace per month, where Velero covers a Persistent-Disk-backed socle for a third of that. | `bool` | `false` | no |
| <a name="input_billing_export_dataset_id"></a> [billing\_export\_dataset\_id](#input\_billing\_export\_dataset\_id) | When set, create a BigQuery dataset to receive the detailed billing export. Linking the billing account to it stays a Console step — Google exposes no API for it. | `string` | `null` | no |
| <a name="input_billing_export_dataset_location"></a> [billing\_export\_dataset\_location](#input\_billing\_export\_dataset\_location) | Location of the billing export dataset. Ignored when billing\_export\_dataset\_id is null. | `string` | `"EU"` | no |
| <a name="input_control_plane_dns_allow_external_traffic"></a> [control\_plane\_dns\_allow\_external\_traffic](#input\_control\_plane\_dns\_allow\_external\_traffic) | Allow user traffic to the DNS-based control plane endpoint. True means the control plane is reachable wherever Google Cloud APIs are, gated by IAM; VPC Service Controls is the network boundary and is set outside this module. | `bool` | `true` | no |
| <a name="input_control_plane_ip_endpoints_enabled"></a> [control\_plane\_ip\_endpoints\_enabled](#input\_control\_plane\_ip\_endpoints\_enabled) | Expose the control plane on IP endpoints. Off: the DNS-based endpoint replaces them, and with it the authorized-networks maintenance problem. | `bool` | `false` | no |
| <a name="input_cost_allocation_enabled"></a> [cost\_allocation\_enabled](#input\_cost\_allocation\_enabled) | Add cluster, namespace and workload labels to the detailed billing export. On from day one because it does not backfill. | `bool` | `true` | no |
| <a name="input_create_nat"></a> [create\_nat](#input\_create\_nat) | Create a Cloud Router and Cloud NAT for egress. A cluster with private nodes and no NAT cannot pull an image from outside Google Cloud. | `bool` | `true` | no |
| <a name="input_create_network"></a> [create\_network](#input\_create\_network) | Create the VPC instead of using an existing one. The common case is a network the consumer already owns. | `bool` | `false` | no |
| <a name="input_create_proxy_only_subnet"></a> [create\_proxy\_only\_subnet](#input\_create\_proxy\_only\_subnet) | Create the proxy-only subnetwork. Set to false when another cluster in the same region and VPC already created it — the pool is shared. | `bool` | `true` | no |
| <a name="input_create_subnetwork"></a> [create\_subnetwork](#input\_create\_subnetwork) | Create the cluster subnetwork. Set to false in a Shared VPC where the network team owns subnets, and supply subnetwork\_name and pod\_range\_name instead. | `bool` | `true` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Refuse to destroy the cluster. On by default; test fixtures turn it off. | `bool` | `true` | no |
| <a name="input_enable_private_nodes"></a> [enable\_private\_nodes](#input\_enable\_private\_nodes) | Nodes get no external address. Flips the Autopilot default, which is public. | `bool` | `true` | no |
| <a name="input_enable_upgrade_notifications"></a> [enable\_upgrade\_notifications](#input\_enable\_upgrade\_notifications) | Create a Pub/Sub topic and publish cluster upgrade notifications to it, so automation can react instead of polling. | `bool` | `true` | no |
| <a name="input_gateway_api_enabled"></a> [gateway\_api\_enabled](#input\_gateway\_api\_enabled) | Run GKE's Gateway API controller and let GKE install and upgrade the standard-channel Gateway API CRDs. On by default and stated rather than assumed: the socle installs nothing for Gateway API on GKE because of it, and its templates target GKE's classes. Off leaves the cluster without Gateway API at all. | `bool` | `true` | no |
| <a name="input_kubernetes_min_version"></a> [kubernetes\_min\_version](#input\_kubernetes\_min\_version) | Floor for the control plane version. Raise-only escape hatch for promoting a minor deliberately; leave null in steady state and let the channel decide. | `string` | `null` | no |
| <a name="input_logging_components"></a> [logging\_components](#input\_logging\_components) | GKE log sources to send to Cloud Logging. SYSTEM\_COMPONENTS cannot be removed; drop WORKLOADS when application logs are collected in-cluster. | `list(string)` | <pre>[<br/>  "SYSTEM_COMPONENTS",<br/>  "WORKLOADS"<br/>]</pre> | no |
| <a name="input_maintenance_exclusions"></a> [maintenance\_exclusions](#input\_maintenance\_exclusions) | Windows during which GKE must not upgrade the cluster. The brake, not the routine: empty by default. | <pre>list(object({<br/>    name       = string<br/>    start_time = string<br/>    end_time   = string<br/>    scope      = string<br/>  }))</pre> | `[]` | no |
| <a name="input_monitoring_components"></a> [monitoring\_components](#input\_monitoring\_components) | GKE metric sources. SYSTEM\_COMPONENTS is free and mandatory; every other component is billed per sample, so none is defaulted on. | `list(string)` | <pre>[<br/>  "SYSTEM_COMPONENTS"<br/>]</pre> | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of an existing custom-mode VPC to attach the cluster to. Mutually exclusive with create\_network. | `string` | `null` | no |
| <a name="input_node_range_cidr"></a> [node\_range\_cidr](#input\_node\_range\_cidr) | Primary range of the cluster subnetwork, used by nodes and by internal load balancers. A /22 carries 1020 nodes, which is what the Pod range allows. | `string` | `"10.0.0.0/22"` | no |
| <a name="input_observability_reader_members"></a> [observability\_reader\_members](#input\_observability\_reader\_members) | Principals granted read-only access to this project's metrics — the central observability cluster's federated identity, never a key. | `list(string)` | `[]` | no |
| <a name="input_pod_range_cidr"></a> [pod\_range\_cidr](#input\_pod\_range\_cidr) | Secondary range for Pod addresses. Autopilot fixes 32 Pods per node, so a /26 is consumed per node: a /16 carries 1024 nodes. Sized generously on purpose — a cluster's Pod range cannot be changed after creation, while the primary range can be expanded in place. | `string` | `"10.4.0.0/16"` | no |
| <a name="input_pod_range_name"></a> [pod\_range\_name](#input\_pod\_range\_name) | Name of the secondary range that carries Pod addresses. Defaults to <cluster\_name>-pods, which is what the module creates; set it when attaching to a subnetwork someone else owns. | `string` | `null` | no |
| <a name="input_proxy_only_range_cidr"></a> [proxy\_only\_range\_cidr](#input\_proxy\_only\_range\_cidr) | Range of the REGIONAL\_MANAGED\_PROXY subnetwork. Regional Application Load Balancers, and therefore Gateways, cannot exist without it. | `string` | `"10.8.0.0/23"` | no |
| <a name="input_release_channel"></a> [release\_channel](#input\_release\_channel) | GKE release channel. REGULAR is Google's recommendation and the estate-wide default; RAPID is outside the GKE SLA and belongs in pre-production only. | `string` | `"REGULAR"` | no |
| <a name="input_subnet_flow_logs_enabled"></a> [subnet\_flow\_logs\_enabled](#input\_subnet\_flow\_logs\_enabled) | Enable VPC flow logs on the cluster subnetwork, at half sampling over ten-minute windows. Vended network logs are billed at $0.25/GiB, which is a dollar or so a month at that sampling for a socle cluster. | `bool` | `true` | no |
| <a name="input_subnetwork_name"></a> [subnetwork\_name](#input\_subnetwork\_name) | Name of an existing subnetwork in var.region to place the cluster in. Required when create\_subnetwork is false, ignored otherwise. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_billing_export_dataset"></a> [billing\_export\_dataset](#output\_billing\_export\_dataset) | Reference of the BigQuery dataset waiting for the detailed billing export. Null when none was requested. The billing account still has to be linked to it by hand. |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Base64-encoded cluster CA certificate, for building a kubeconfig. |
| <a name="output_cluster_dns_endpoint"></a> [cluster\_dns\_endpoint](#output\_cluster\_dns\_endpoint) | The control plane's DNS endpoint — the access path the socle and its automation use. Stable for the life of the cluster and authorised by IAM. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | IP endpoint of the control plane. Empty when IP endpoints are disabled, which is the default. |
| <a name="output_cluster_location"></a> [cluster\_location](#output\_cluster\_location) | Region of the cluster. Regional by default; there is no zonal option. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the GKE cluster. |
| <a name="output_helm_kubernetes"></a> [helm\_kubernetes](#output\_helm\_kubernetes) | Drop-in value for the helm provider's kubernetes attribute, so a root configures it in one line. Uses the DNS endpoint, the only one enabled by default. Carries no credential: gke-gcloud-auth-plugin obtains a short-lived token from the caller's ambient gcloud credentials at call time. |
| <a name="output_labels"></a> [labels](#output\_labels) | The standard label set applied to every billable resource this module creates. |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Name of the VPC the cluster is attached to, whether the module created it or not. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | The cluster's OIDC issuer, for federating an external identity provider against this cluster. |
| <a name="output_pod_range_name"></a> [pod\_range\_name](#output\_pod\_range\_name) | Name of the secondary range carrying Pod addresses. |
| <a name="output_proxy_only_subnetwork_name"></a> [proxy\_only\_subnetwork\_name](#output\_proxy\_only\_subnetwork\_name) | The REGIONAL\_MANAGED\_PROXY subnetwork regional Gateways draw their proxies from. Null when the module did not create it. |
| <a name="output_subnetwork_name"></a> [subnetwork\_name](#output\_subnetwork\_name) | Name of the cluster's subnetwork. |
| <a name="output_upgrade_notifications_topic"></a> [upgrade\_notifications\_topic](#output\_upgrade\_notifications\_topic) | Pub/Sub topic carrying GKE upgrade and security bulletin notifications. Null when notifications are disabled. |
| <a name="output_workload_identity_pool"></a> [workload\_identity\_pool](#output\_workload\_identity\_pool) | The Workload Identity Federation pool. Autopilot enforces it, so this is derived rather than configured. Grant IAM roles to principals in this pool to give a catalog workload direct resource access. |
| <a name="output_workload_identity_principal_prefix"></a> [workload\_identity\_principal\_prefix](#output\_workload\_identity\_principal\_prefix) | Prefix of a workload's IAM principal identifier. Append ns/NAMESPACE/sa/SERVICEACCOUNT. Note that two clusters in one project produce identical principals for the same namespace and service account. |
<!-- END_TF_DOCS -->
