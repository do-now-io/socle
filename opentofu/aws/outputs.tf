# Everything needed to bootstrap the Flux-pulled socle, and nothing that is
# a long-lived credential. The cluster CA is marked sensitive; no key
# material is produced by this module at all, so none can be output.

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.socle.name
}

output "region" {
  description = "Region the cluster and VPC were created in, as resolved from the provider."
  value       = data.aws_region.current.region
}

output "cluster_endpoint" {
  description = "The control plane's API endpoint — the access path the socle and its automation use."
  value       = aws_eks_cluster.socle.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate, for building a kubeconfig."
  value       = aws_eks_cluster.socle.certificate_authority[0].data
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "The cluster's OIDC issuer. Checklist requirement, not this module's identity mechanism — Pod Identity is, IRSA is absent, and nothing here provisions an OIDC trust relationship against it."
  value       = aws_eks_cluster.socle.identity[0].oidc[0].issuer
}

output "crossplane_role_arn" {
  description = "The identity the in-cluster Crossplane AWS provider assumes, via Pod Identity."
  value       = aws_iam_role.crossplane.arn
}

output "crossplane_service_account_kubernetes_binding" {
  description = "The Kubernetes service account bound to that identity, as namespace/name. Must match the socle's DeploymentRuntimeConfig."
  value       = "${var.crossplane_service_account_namespace}/${var.crossplane_service_account_name}"
}

output "vpc_id" {
  description = "ID of the VPC the cluster is attached to, whether this module created it or not."
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ."
  value       = local.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ."
  value       = local.public_subnet_ids
}

output "tags" {
  description = "The standard tag set applied to every billable resource this module creates."
  value       = local.tags
}
