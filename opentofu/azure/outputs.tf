# Everything needed to bootstrap the Flux-pulled socle, and nothing that is
# a long-lived credential. The cluster CA is marked sensitive; no key
# material is produced by this module at all, so none can be output.

output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.socle.name
}

output "location" {
  description = "Region the cluster and its resources were created in."
  value       = local.location
}

output "cluster_endpoint" {
  description = "The control plane's private FQDN — the only reachable endpoint, since this module always disables the public one."
  value       = azurerm_kubernetes_cluster.socle.private_fqdn
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate, for building a kubeconfig."
  value       = azurerm_kubernetes_cluster.socle.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "The cluster's OIDC issuer — what a workload identity federation binding built by the layer above (Crossplane's provider, or anything else) will need."
  value       = azurerm_kubernetes_cluster.socle.oidc_issuer_url
}

output "resource_group_name" {
  description = "Name of the resource group the cluster and its resources live in, whether this module created it or not."
  value       = local.resource_group_name
}

output "vnet_name" {
  description = "Name of the VNet the cluster is attached to, whether this module created it or not."
  value       = local.vnet_name
}

output "pod_cidr" {
  description = "Range the bootstrap module hands Cilium as its cluster pool. Passed through, never set on the cluster: azurerm refuses pod_cidr under BYO CNI."
  value       = var.pod_cidr
}

output "node_subnet_id" {
  description = "ID of the node subnet."
  value       = local.node_subnet_id
}

output "tags" {
  description = "The standard tag set applied to every billable resource this module creates."
  value       = local.tags
}

output "helm_kubernetes" {
  description = "Drop-in value for the helm provider's kubernetes attribute, so a root configures it in one line. Carries no credential: kubelogin obtains a short-lived Entra token from the caller's Azure CLI login at call time; the server ID is AKS's well-known Entra application. PRECONDITION NOT YET MET BY THIS MODULE: the exec only authenticates against a cluster with Entra ID authentication enabled (azure_active_directory_role_based_access_control), which this module does not configure yet — local accounts remain its auth path. Enabling it is a pending decision for docs/azure; until then this output is the shape a root will consume, not a working login."
  value = {
    host                   = azurerm_kubernetes_cluster.socle.kube_config[0].host
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.socle.kube_config[0].cluster_ca_certificate)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      args        = ["get-token", "--login", "azurecli", "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"]
    }
  }
  sensitive = true
}
