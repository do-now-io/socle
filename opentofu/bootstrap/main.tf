# Flux, installed once and then left alone.
#
# Three releases, in order:
#   1. the operator;
#   2. a FluxInstance — which controllers run, and how they are configured —
#      with a health check, so the release only returns once the operator has
#      reconciled Flux and its CRDs exist;
#   3. the root sync, a local chart of two objects: an OCIRepository and a
#      Kustomization.
#
# The third release is not how this started. The FluxInstance has a sync block
# of its own, and using it was the obvious design — until a real cluster
# showed it cannot express two things this socle needs: a cosign verification,
# and a target namespace for manifests carrying none. Its kustomize patches
# reach the Flux components only, and a patch that misses stalls the whole
# instance rather than degrading. Both findings are in docs/flux-bootstrap.md.
#
# Helm carries the two objects because it is the only provider here that
# applies a custom resource without needing its CRD to exist at plan time.
#
# From the third release on, OpenTofu owns nothing: the operator converges the
# controllers, and Flux converges everything the artifact contains.

locals {
  # Immutable in the Kustomization's own reconciliation, so fixed rather than
  # derived: renaming a cluster must not mean recreating its sync.
  sync_name = "socle"

  common_labels = {
    "app.kubernetes.io/part-of"   = "socle"
    "socle.do-now.io/cluster"     = var.cluster_name
    "socle.do-now.io/environment" = var.environment
    "socle.do-now.io/owner"       = var.owner
  }
}

resource "helm_release" "operator" {
  name       = "flux-operator"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart      = "flux-operator"
  version    = var.operator_version

  namespace        = var.namespace
  create_namespace = true

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

  values = [yamlencode({
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
      commonMetadata = { labels = local.common_labels }
      storage        = { class = var.storage_class }
      # No sync block: the root source is the release below.
    }
    # Helm's own wait does not wait for a custom resource to become ready, so
    # without this the sync release would race the CRDs the operator installs.
    healthcheck = {
      enabled = true
      timeout = "${var.helm_timeout_seconds}s"
    }
    commonLabels = local.common_labels
  })]

  depends_on = [helm_release.operator]
}

resource "helm_release" "sync" {
  name  = "socle-sync"
  chart = "${path.module}/chart"

  namespace = var.namespace

  wait    = true
  timeout = var.helm_timeout_seconds

  values = [yamlencode({
    commonLabels = local.common_labels
    sync = {
      name            = local.sync_name
      kind            = var.sync_kind
      url             = var.sync_url
      ref             = var.sync_ref
      digest          = var.sync_digest
      path            = var.sync_path
      interval        = var.sync_interval
      targetNamespace = var.sync_target_namespace
      pullSecret      = var.sync_pull_secret
      prune           = var.sync_prune
      wait            = var.sync_wait
      timeout         = var.sync_timeout
    }
    verify = {
      enabled  = var.cosign_verification_enabled
      identity = var.cosign_identity
    }
  })]

  depends_on = [helm_release.instance]
}
