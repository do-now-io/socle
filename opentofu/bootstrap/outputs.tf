output "inputs" {
  description = "What this module ships into the cluster as the ResourceSetInputProvider's defaultValues, after normalisation against the catalog. The catalog's templates read exactly these paths."
  value       = local.inputs
}

output "socle_version" {
  description = "Tag of the socle artifact the cluster pulls."
  value       = local.version
}

output "artifact" {
  description = "The socle artifact, as OCI URL and tag."
  value = {
    url = var.artifact_url
    tag = local.version
  }
}

output "cosign_identity" {
  description = "Keyless identity the artifact's signature is verified against, on every reconciliation."
  value       = var.cosign_identity
}

output "cilium" {
  description = "Whether this module installed Cilium (aws, azure: the clouds whose foundations create a cluster with no CNI), with the chart versions it pinned. installed is false where the cloud operates Cilium, or when cilium.enabled is false."
  value = {
    installed       = local.cilium_installed
    chart_version   = local.cilium_installed ? local.cilium_chart_version : null
    coredns_version = length(helm_release.coredns) > 0 ? local.coredns_chart_version : null
    hubble          = local.cilium_installed && local.cilium.hubble
    gateway_api     = local.cilium_installed && local.cilium.gateway_api
  }
}

output "eks_addons" {
  description = "The EKS-managed add-ons this module installed (aws only), each as its pinned version, and for the two storage drivers the ARN of the role their controller runs as. Null for an add-on not installed."
  value = {
    pod_identity_agent = length(aws_eks_addon.pod_identity_agent) > 0 ? { version = local.eks_addon_versions.pod_identity_agent } : null
    ebs_csi            = length(aws_eks_addon.ebs_csi) > 0 ? { version = local.eks_addon_versions.ebs_csi, role_arn = aws_iam_role.ebs_csi[0].arn } : null
    efs_csi            = length(aws_eks_addon.efs_csi) > 0 ? { version = local.eks_addon_versions.efs_csi, role_arn = aws_iam_role.efs_csi[0].arn } : null
  }
}

output "namespace" {
  description = "Namespace holding the operator, the Flux controllers and the socle's inputs."
  value       = local.namespace
}

output "operator_version" {
  description = "Version of flux-operator installed, which is also its chart version."
  value       = var.operator_version
}

output "flux_version" {
  description = "Flux version the operator converges the controllers to."
  value       = var.flux_version
}
