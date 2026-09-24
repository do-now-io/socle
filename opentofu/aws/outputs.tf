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

output "service_cidr" {
  description = "The Kubernetes service range EKS chose for this cluster (172.20.0.0/16 or 10.100.0.0/16, by VPC CIDR). The bootstrap module gives CoreDNS its .10 address, the one every node's kubelet is told to use. Null on an emulated cluster that reports none (floci)."
  value       = try(aws_eks_cluster.socle.kubernetes_network_config[0].service_ipv4_cidr, null)
}

output "cilium_operator_policy_json" {
  description = "IAM policy the Cilium operator needs in ENI mode — the bootstrap module installs Cilium on this cluster before Flux. For the node role, which this module does not create: whoever creates it attaches this document."
  value       = data.aws_iam_policy_document.cilium_operator.json
}

output "oidc_issuer_url" {
  description = "The cluster's OIDC issuer. Checklist requirement, not this module's identity mechanism — Pod Identity is, IRSA is absent, and nothing here provisions an OIDC trust relationship against it. Null on an emulated cluster that reports no identity (floci), so an apply there still converges."
  value       = try(aws_eks_cluster.socle.identity[0].oidc[0].issuer, null)
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

output "helm_kubernetes" {
  description = "Drop-in value for the helm provider's kubernetes attribute, so a root configures it in one line. Carries no credential: the exec plugin obtains a short-lived token from the caller's ambient AWS credentials at call time, exactly as the aws provider itself authenticates."
  value = {
    host                   = aws_eks_cluster.socle.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.socle.certificate_authority[0].data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.socle.name, "--region", data.aws_region.current.region]
    }
  }
  sensitive = true
}

output "crossplane_role_arn" {
  description = "ARN of the IAM role the catalog's crossplane module's AWS providers run as, through Pod Identity. Null when crossplane is not set."
  value       = one(aws_iam_role.crossplane[*].arn)
}

output "crossplane_permissions_boundary_arn" {
  description = "ARN of the permissions boundary every role Crossplane creates must carry — what kube.crossplane.permissions_boundary takes, and what the client root passes for you. Null when crossplane is not set."
  value       = one(aws_iam_policy.crossplane_boundary[*].arn)
}
