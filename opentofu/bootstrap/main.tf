# Socle bootstrap: Flux, and the inputs the catalog renders from.
#
# Terraform ships inputs only. The socle OCI artifact ships the templates, one
# ResourceSet per catalog module, and Flux Operator renders, reconciles and
# garbage-collects. Three Helm releases, in order: the operator, a
# FluxInstance with no sync block, and an envelope of two literal objects — a
# ResourceSetInputProvider carrying the client's config and a ResourceSet
# carrying the root source with its cosign verification. Helm is the applier,
# never the templater: docs/flux-catalog.md §3.
#
# On aws and azure three more releases precede the operator — the Gateway API
# CRDs, Cilium and (aws) CoreDNS — because those clusters are created with no
# CNI and Flux cannot run, let alone render, without one: cilium.tf.

locals {
  # Bumped with the module's own tag. VERSION at the repo root is the source;
  # .github/scripts/check-version.sh fails CI when this drifts from it.
  socle_version = "0.0.0" # x-release-please-version

  version = coalesce(var.socle_version, local.socle_version)

  # Everything the operator and Flux install lives here. Fixed rather than a
  # variable: the operator's own defaults, RBAC and network policies assume it.
  namespace = "flux-system"

  # The operator wires workload identity from this enum. Scaleway has none it
  # knows, so it is a plain kubernetes cluster.
  cluster_type = {
    aws      = "aws"
    gcp      = "gcp"
    azure    = "azure"
    scaleway = "kubernetes"
  }[var.cloud]

  common_labels = {
    "app.kubernetes.io/part-of"   = "socle"
    "socle.do-now.io/cluster"     = var.cluster_name
    "socle.do-now.io/environment" = var.environment
    "socle.do-now.io/owner"       = var.owner
  }

  # What reaches the cluster, as the ResourceSetInputProvider's defaultValues.
  # The catalog's templates read exactly these paths.
  inputs = {
    cloud = var.cloud
    cluster = {
      name        = var.cluster_name
      environment = var.environment
      owner       = var.owner
    }
    socle = {
      url        = var.artifact_url
      version    = local.version
      pullSecret = var.artifact_pull_secret
    }
    cosign  = var.cosign_identity
    modules = local.modules
    # What the bootstrap decided about the network, for the templates that
    # depend on it: `installed` — the socle's Cilium runs here, and with it
    # the Gateway API CRDs; `gatewayApi` — it serves the `cilium`
    # GatewayClass, so no other implementation is needed; `hubble` — Relay
    # and UI exist. All false where the cloud operates Cilium.
    cilium = {
      installed  = local.cilium_installed
      gatewayApi = local.cilium_installed && local.cilium.gateway_api
      hubble     = local.cilium_installed && local.cilium.hubble
    }
  }
}

# 1. The operator. The official chart, pinned exactly. After the network:
# its pod has no hostNetwork and its controllers resolve ghcr.io.
resource "helm_release" "operator" {
  name       = "flux-operator"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart      = "flux-operator"
  version    = var.operator_version

  namespace        = local.namespace
  create_namespace = true

  wait    = true
  timeout = var.helm_timeout_seconds

  values = [yamlencode({
    commonLabels = local.common_labels
  })]

  depends_on = [helm_release.cilium, helm_release.coredns]
}

# 2. The instance: which controllers run, how they are wired. No sync block —
# the root source is the envelope below. The health check makes this release
# return only once the operator has converged Flux and its CRDs exist, so the
# envelope's custom resources do not race them.
resource "helm_release" "instance" {
  name       = "flux-instance"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart      = "flux-instance"
  version    = var.operator_version

  namespace = local.namespace

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
        type          = local.cluster_type
        size          = var.instance_size
        networkPolicy = var.network_policy
      }
      commonMetadata = { labels = local.common_labels }
      storage        = { class = var.storage_class }
    }
    healthcheck = {
      enabled = true
      timeout = "${var.helm_timeout_seconds}s"
    }
    commonLabels = local.common_labels
  })]

  depends_on = [helm_release.operator]
}

# 3. The envelope: the client's inputs and the root source, two literal
# objects. Helm carries them because it is the only provider that applies a
# custom resource without needing its CRD at plan time — the condition for
# foundations and this module sharing one root.
resource "helm_release" "socle" {
  name  = "socle"
  chart = "${path.module}/manifests"

  namespace = local.namespace

  wait    = true
  timeout = var.helm_timeout_seconds

  values = [yamlencode({
    inputs = local.inputs
  })]

  depends_on = [helm_release.instance]
}
