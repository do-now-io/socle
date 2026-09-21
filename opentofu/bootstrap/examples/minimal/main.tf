# The smallest bootstrap: point a cluster at one signed artifact and let the
# operator do the rest.
#
# The module configures no provider — a module that configured its own could
# not be called twice for two clusters in one configuration. The kubeconfig
# comes from the foundations module's output, written to a file by the caller.

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

module "bootstrap" {
  source = "../../"

  cluster_name = var.cluster_name
  environment  = var.environment
  owner        = var.owner

  # kubernetes covers Scaleway and anything without workload identity
  # federation; aws, azure and gcp make the operator wire theirs.
  cluster_type = var.cluster_type

  # What this cluster pulls, pinned. A tag, never a moving head.
  sync_url = var.sync_url
  sync_ref = var.sync_ref

  # Flux verifies the artifact's signature before applying it, against the
  # identity that signed it. OpenTofu cannot check an OCI signature; Flux can,
  # and it re-checks on every reconciliation rather than once at install.
  cosign_identity = var.cosign_identity
}
