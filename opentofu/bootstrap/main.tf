# Flux, installed once and then left alone.
#
# Two releases, in order: the operator, then a FluxInstance describing what
# the cluster should run and what it should pull. From the second release on,
# OpenTofu owns nothing else — the operator converges the Flux controllers,
# and Flux converges everything the artifact contains.
#
# The name of the root source and Kustomization is fixed, not derived: it is
# immutable in the CRD, so deriving it from a variable would make renaming a
# cluster a destroy.

locals {
  sync_name = "socle"

  common_labels = {
    "app.kubernetes.io/part-of"   = "socle"
    "socle.do-now.io/cluster"     = var.cluster_name
    "socle.do-now.io/environment" = var.environment
    "socle.do-now.io/owner"       = var.owner
  }

  # The FluxInstance sync spec carries no verify field, so signature checking
  # is expressed as a patch on the OCIRepository the operator generates.
  # Without an identity the signature is checked but its author is not, which
  # is why cosign_identity is the recommended form.
  cosign_patch = var.cosign_identity == null ? yamlencode({
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "OCIRepository"
    metadata   = { name = local.sync_name }
    spec       = { verify = { provider = "cosign" } }
    }) : yamlencode({
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "OCIRepository"
    metadata   = { name = local.sync_name }
    spec = {
      verify = {
        provider = "cosign"
        matchOIDCIdentity = [{
          issuer  = var.cosign_identity.issuer
          subject = var.cosign_identity.subject
        }]
      }
    }
  })

  instance_values = {
    instance = {
      distribution = {
        version  = var.flux_version
        registry = "ghcr.io/fluxcd"
      }
      components = var.flux_components
      cluster = {
        type          = var.cluster_type
        size          = var.instance_size
        networkPolicy = var.network_policy
        multitenant   = var.multitenant
      }
      commonMetadata = {
        labels = local.common_labels
      }
      storage = {
        class = var.storage_class
      }
      sync = {
        name       = local.sync_name
        kind       = var.sync_kind
        url        = var.sync_url
        ref        = var.sync_ref
        path       = var.sync_path
        interval   = var.sync_interval
        pullSecret = var.sync_pull_secret
      }
      kustomize = {
        patches = var.cosign_verification_enabled ? [{ patch = local.cosign_patch }] : []
      }
    }
    commonLabels = local.common_labels
  }
}

resource "helm_release" "operator" {
  name       = "flux-operator"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart      = "flux-operator"
  version    = var.operator_version

  namespace        = var.namespace
  create_namespace = true

  # The instance release below describes objects whose CRDs this release
  # installs, so waiting is not optional.
  wait    = true
  timeout = var.helm_timeout_seconds

  values = [yamlencode({
    commonLabels = local.common_labels
  })]
}

resource "helm_release" "instance" {
  name       = "flux-instance"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart      = "flux-instance"
  version    = var.operator_version

  namespace = var.namespace

  wait    = true
  timeout = var.helm_timeout_seconds

  values = [yamlencode(local.instance_values)]

  depends_on = [helm_release.operator]
}
