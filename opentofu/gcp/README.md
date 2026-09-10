# Socle foundations — Google Cloud

One flat root module: network, GKE Autopilot cluster, identities. It
provisions an empty-shell cluster and the identities the Flux-pulled socle
needs, then steps away.

```hcl
module "socle" {
  source = "oci://<registry>/<repo>//opentofu/gcp?tag=<version>"

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

A deployable version of that is in [`examples/minimal`](examples/minimal),
which also lists the roles the apply needs and where remote state belongs.

> **OpenTofu does not verify OCI signatures.** It will pull an unsigned or
> tampered artifact without complaint. Run `cosign verify` in CI before
> `tofu init`, or enforce it through registry policy, and pin by digest.

## What is decided for you

Every default traces back to a research document. The short version:

| Decision | Position | Traces to |
| --- | --- | --- |
| Autopilot, no cluster mode option | enforced | [cluster mode](../../docs/gcp/cluster-mode.md) |
| Regular release channel; Extended rejected | default | [managed scope](../../docs/gcp/managed-scope.md) |
| Maintenance window required, no default | required | [managed scope](../../docs/gcp/managed-scope.md) |
| Only free metric components enabled | default | [managed scope](../../docs/gcp/managed-scope.md) |
| Backup for GKE agent off, Velero preferred | default | [managed scope](../../docs/gcp/managed-scope.md) |
| Cost allocation on from day one | default | [cloud observability](../../docs/gcp/cloud-observability.md) |
| Private nodes on, flipping Autopilot's default | default | [network & security](../../docs/gcp/network-security.md) |
| DNS-based control plane endpoint, IP endpoints off | default | [network & security](../../docs/gcp/network-security.md) |
| No Services secondary range — GKE manages it | enforced | [network & security](../../docs/gcp/network-security.md) |
| Crossplane's Google service account created here | enforced | [managed scope](../../docs/gcp/managed-scope.md) |

## What is deliberately absent

Not oversights. An option in the interface is an option that is supported and
tested, so these are refusals:

- **`EXTENDED` as a release channel** — Google forbids Autopilot clusters in it.
- **Any Config Connector toggle** — the add-on is Standard-only and Google
  discourages it in production; Crossplane is the choice.
- **Any Workload Identity toggle** — Autopilot enforces it.
- **`master_authorized_networks` and `master_ipv4_cidr_block`** — they govern
  the IP endpoints this module disables.
- **A CNI or datapath variable** — Autopilot enforces Dataplane V2.
- **Auto-Monitoring and `gke_auto_upgrade_config`** — silent recurring cost.
- **Auto IPAM** — still Preview; a module default has to be GA.
- **Gateway, NetworkPolicy and alerting objects** — catalog concerns, so that
  four clouds share one definition. The module stops at the proxy-only subnet
  a Gateway needs.
- **Any credential as an input** — the module authenticates through the
  provider's ambient credentials, and issues no key.

## One step no apply can finish

Linking a billing account to the BigQuery dataset for the detailed cost export
is a Cloud Console action: Google exposes no API for it, so there is no
Terraform resource and no `gcloud` command. `billing_export_dataset_id` makes
the module create the dataset; a human has to point the billing account at it.
Nothing breaks without that step — the cost data simply never arrives.

## Tests

```bash
tofu test          # 36 runs: every validation, and the defaults
```

Integration: CI plans [`tests/emulator`](tests/emulator) against the floci-gcp
emulator. That proves the module plans coherently against a live API, and does
not prove it converges — two reasons, both outside this module:

- The emulator implements no Compute Engine API, so the VPC, subnetworks,
  router and NAT have nowhere to be created.
- The google provider segfaults reading back the emulator's cluster: it
  dereferences the cluster's legacy ABAC field without a nil check, and the
  emulator omits that field.

The workflow prints that caveat on every run.

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
| [google_project_iam_member.crossplane](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.observability_reader](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_pubsub_topic.upgrade_notifications](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic) | resource |
| [google_service_account.crossplane](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_member.crossplane_workload_identity](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |

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
| <a name="input_crossplane_project_roles"></a> [crossplane\_project\_roles](#input\_crossplane\_project\_roles) | Project roles granted to the identity the in-cluster Crossplane provider assumes. Empty by default: the catalog does not exist yet, and a list written today would be a guess. | `list(string)` | `[]` | no |
| <a name="input_crossplane_service_account_name"></a> [crossplane\_service\_account\_name](#input\_crossplane\_service\_account\_name) | Name of the Crossplane GCP provider's Kubernetes service account. Must match the socle's DeploymentRuntimeConfig — the provider Pod's service account name is not stable across provider revisions unless it is pinned there. | `string` | `"provider-gcp"` | no |
| <a name="input_crossplane_service_account_namespace"></a> [crossplane\_service\_account\_namespace](#input\_crossplane\_service\_account\_namespace) | Namespace of the Crossplane GCP provider's Kubernetes service account. | `string` | `"crossplane-system"` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Refuse to destroy the cluster. On by default; test fixtures turn it off. | `bool` | `true` | no |
| <a name="input_enable_private_nodes"></a> [enable\_private\_nodes](#input\_enable\_private\_nodes) | Nodes get no external address. Flips the Autopilot default, which is public. | `bool` | `true` | no |
| <a name="input_enable_upgrade_notifications"></a> [enable\_upgrade\_notifications](#input\_enable\_upgrade\_notifications) | Create a Pub/Sub topic and publish cluster upgrade notifications to it, so automation can react instead of polling. | `bool` | `true` | no |
| <a name="input_kubernetes_min_version"></a> [kubernetes\_min\_version](#input\_kubernetes\_min\_version) | Floor for the control plane version. Raise-only escape hatch for promoting a minor deliberately; leave null in steady state and let the channel decide. | `string` | `null` | no |
| <a name="input_logging_components"></a> [logging\_components](#input\_logging\_components) | GKE log sources to send to Cloud Logging. SYSTEM\_COMPONENTS cannot be removed; drop WORKLOADS when application logs are collected in-cluster. | `list(string)` | <pre>[<br/>  "SYSTEM_COMPONENTS",<br/>  "WORKLOADS"<br/>]</pre> | no |
| <a name="input_maintenance_exclusions"></a> [maintenance\_exclusions](#input\_maintenance\_exclusions) | Windows during which GKE must not upgrade the cluster. The brake, not the routine: empty by default. | <pre>list(object({<br/>    name       = string<br/>    start_time = string<br/>    end_time   = string<br/>    scope      = string<br/>  }))</pre> | `[]` | no |
| <a name="input_monitoring_components"></a> [monitoring\_components](#input\_monitoring\_components) | GKE metric sources. SYSTEM\_COMPONENTS is free and mandatory; every other component is billed per sample, so none is defaulted on. | `list(string)` | <pre>[<br/>  "SYSTEM_COMPONENTS"<br/>]</pre> | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of an existing custom-mode VPC to attach the cluster to. Mutually exclusive with create\_network. | `string` | `null` | no |
| <a name="input_node_range_cidr"></a> [node\_range\_cidr](#input\_node\_range\_cidr) | Primary range of the cluster subnetwork, used by nodes and by internal load balancers. | `string` | `"10.0.0.0/24"` | no |
| <a name="input_observability_reader_members"></a> [observability\_reader\_members](#input\_observability\_reader\_members) | Principals granted read-only access to this project's metrics — the central observability cluster's federated identity, never a key. | `list(string)` | `[]` | no |
| <a name="input_pod_range_cidr"></a> [pod\_range\_cidr](#input\_pod\_range\_cidr) | Secondary range for Pod addresses. Autopilot fixes 32 Pods per node, so a /26 is consumed per node: a /17 carries 512 nodes. | `string` | `"10.4.0.0/17"` | no |
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
| <a name="output_crossplane_service_account_email"></a> [crossplane\_service\_account\_email](#output\_crossplane\_service\_account\_email) | The identity the in-cluster Crossplane GCP provider assumes. Annotate the provider's Kubernetes service account with it: iam.gke.io/gcp-service-account. |
| <a name="output_crossplane_service_account_kubernetes_binding"></a> [crossplane\_service\_account\_kubernetes\_binding](#output\_crossplane\_service\_account\_kubernetes\_binding) | The Kubernetes service account bound to that identity, as namespace/name. Must match the socle's DeploymentRuntimeConfig. |
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
