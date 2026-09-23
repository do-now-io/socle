# Everything needed to bootstrap the Flux-pulled socle.
#
# Unlike the other three clouds, this module does produce key material: the
# Crossplane API key. Scaleway has no workload identity federation, so there is
# no federated alternative to output instead — see iam.tf for the full
# reasoning. Everything secret is marked sensitive.

output "cluster_id" {
  description = "ID of the Kapsule cluster, in region/uuid form."
  value       = scaleway_k8s_cluster.socle.id
}

output "cluster_name" {
  description = "Name of the Kapsule cluster."
  value       = scaleway_k8s_cluster.socle.name
}

output "cluster_region" {
  description = "Region of the cluster. A Kapsule cluster lives in exactly one."
  value       = scaleway_k8s_cluster.socle.region
}

output "cluster_type" {
  description = "The control plane offer in force. Derived from environment unless control_plane_type overrides it: production gets a dedicated offer for the SLA and the audit log."
  value       = scaleway_k8s_cluster.socle.type
}

output "cluster_endpoint" {
  description = "URL of the Kubernetes API server. Always public on Kapsule — a fully private control plane does not exist — and reachable only from cluster_endpoint_public_access_cidrs."
  value       = scaleway_k8s_cluster.socle.apiserver_url
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate, for building a kubeconfig."
  value       = scaleway_k8s_cluster.socle.kubeconfig[0].cluster_ca_certificate
  sensitive   = true
}

output "kubeconfig" {
  description = "Raw kubeconfig for the cluster. Sensitive: it carries a bearer token."
  value       = scaleway_k8s_cluster.socle.kubeconfig[0].config_file
  sensitive   = true
}

output "wildcard_dns" {
  description = "DNS wildcard resolving to every ready node. Useful for reaching a NodePort before an ingress path exists."
  value       = scaleway_k8s_cluster.socle.wildcard_dns
}

# The other foundations modules expose an OIDC issuer and a workload identity
# pool here. Scaleway has neither, and returning null is more useful than
# omitting the outputs: it keeps one output surface across four clouds, and it
# makes the absence explicit to whatever consumes it.
output "oidc_issuer_url" {
  description = "Always null. Kapsule exposes no OIDC issuer for workload identity, so nothing can federate against this cluster's ServiceAccount tokens."
  value       = null
}

output "workload_identity_pool" {
  description = "Always null. Scaleway has no workload identity federation — the in-cluster provider authenticates with the API key below instead."
  value       = null
}

output "crossplane_application_id" {
  description = "ID of the IAM application the in-cluster Crossplane provider authenticates as."
  value       = scaleway_iam_application.crossplane.id
}

output "crossplane_access_key" {
  description = "Access key of the Crossplane API key. Not secret on its own, but pair it with crossplane_secret_key."
  value       = scaleway_iam_api_key.crossplane.access_key
}

output "crossplane_secret_key" {
  description = "Secret key for the in-cluster Crossplane provider. This is a long-lived credential because Scaleway offers no alternative; it is bound to the source addresses in crossplane_allowed_cidrs and expires at crossplane_key_expires_at."
  value       = scaleway_iam_api_key.crossplane.secret_key
  sensitive   = true
}

output "cockpit_token_secret" {
  description = "Query-only Cockpit token for the central observability cluster to federate Scaleway's metrics and logs. Null when cockpit_token_enabled is false."
  value       = var.cockpit_token_enabled ? scaleway_cockpit_token.observability[0].secret_key : null
  sensitive   = true
}

output "vpc_id" {
  description = "ID of the VPC the cluster's Private Network sits in, whether the module created it or not."
  value       = local.vpc_id
}

output "private_network_id" {
  description = "ID of the cluster's Private Network."
  value       = scaleway_vpc_private_network.socle.id
}

output "gateway_egress_cidrs" {
  description = "Public addresses the cluster's nodes egress from, one per zone, as /32 CIDRs. This is the estate's stable source address: allow-list it wherever a client needs to admit the cluster."
  value       = local.gateway_egress_cidrs
}

output "security_group_ids" {
  description = "The cluster's own node security groups, keyed by zone. Not the shared Kapsule default, which is common to every cluster in the Project. One per zone because an Instance security group is a zoned resource."
  value       = { for z, sg in scaleway_instance_security_group.socle : z => sg.id }
}

output "tags" {
  description = "The standard tag set applied to every resource this module creates that accepts tags."
  value       = local.tags
}

output "helm_kubernetes" {
  description = "Drop-in value for the helm provider's kubernetes attribute, so a root configures it in one line. Kapsule has no exec credential plugin and accepts the IAM secret key as a bearer token, so the exec emits an ExecCredential from SCW_SECRET_KEY — the variable the scaleway provider already reads — at call time. No token is stored in state."
  value = {
    host                   = scaleway_k8s_cluster.socle.apiserver_url
    cluster_ca_certificate = base64decode(scaleway_k8s_cluster.socle.kubeconfig[0].cluster_ca_certificate)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "sh"
      args        = ["-c", "printf '{\"apiVersion\":\"client.authentication.k8s.io/v1beta1\",\"kind\":\"ExecCredential\",\"status\":{\"token\":\"%s\"}}' \"$SCW_SECRET_KEY\""]
    }
  }
  sensitive = true
}
