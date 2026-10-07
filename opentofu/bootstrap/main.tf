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
# On aws and azure two more releases precede the operator — Cilium and (aws)
# CoreDNS — because those clusters are created with no CNI and Flux cannot
# run, let alone render, without one: cilium.tf. On aws the EKS-managed
# add-ons follow them, the Pod Identity Agent before the operator:
# eks_addons.tf.

locals {
  # Bumped with the module's own tag. VERSION at the repo root is the source;
  # .github/scripts/check-version.sh fails CI when this drifts from it.
  socle_version = "0.1.0" # x-release-please-version

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

  # docs/catalog/cilium.md §4. A shared alias is not possible: GKE serves
  # only its own GatewayClasses, so the name is the cloud's.
  gateway_class_name = {
    aws      = local.cilium_installed && local.cilium.gateway_api ? "cilium" : ""
    azure    = local.cilium_installed && local.cilium.gateway_api ? "cilium" : ""
    gcp      = "gke-l7-global-external-managed"
    scaleway = ""
  }[var.cloud]

  # The foundations' outputs, null when they issued no certificate.
  gateway_certificate_arn      = var.gateway_certificate_arn == null ? "" : var.gateway_certificate_arn
  gateway_certificate_map      = var.gateway_certificate_map == null ? "" : var.gateway_certificate_map
  gateway_regional_certificate = var.gateway_regional_certificate == null ? "" : var.gateway_regional_certificate

  # docs/catalog/gateway-api.md. Where the client kept them and a class
  # serves them — the socle's Cilium's `cilium`, or on gcp GKE's — and,
  # where TLS terminates at the load balancer (aws, gcp), a certificate
  # exists: the socle never serves a route in clear text. On gcp both: the
  # public Gateway's global load balancer takes the map, the private one's
  # regional load balancer the regional certificate, and a Gateway whose
  # listener has no certificate would never be programmed.
  shared_gateways = (
    local.modules.gateway_api.enabled
    && local.modules.gateway_api.gateways
    && (
      var.cloud == "gcp"
      ? local.gateway_certificate_map != "" && local.gateway_regional_certificate != ""
      : local.gateway_class_name == "cilium" && (var.cloud != "aws" || local.gateway_certificate_arn != "")
    )
  )

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
      region      = var.region
      # The cloud account the cluster runs in, on aws: S3 bucket names are
      # global, so a module's bucket carries it (docs/catalog/velero.md).
      # Empty elsewhere.
      accountId = local.account_id
      # The project the cluster runs in, on gcp: a module's Workload Identity
      # principal names its number and the pool named after its id, and a
      # bucket's name carries the number. Empty elsewhere.
      projectId     = try(var.project.id, "")
      projectNumber = try(var.project.number, "")
    }
    socle = {
      url        = var.artifact_url
      version    = local.version
      pullSecret = var.artifact_pull_secret
    }
    cosign  = var.cosign_identity
    modules = local.modules
    # What the bootstrap decided about the network, for the templates that
    # depend on it: `installed` — the socle's Cilium runs here; `gatewayApi`
    # — it has Gateway API on, so the gateway_api module creates the `cilium`
    # GatewayClass and restarts its operator once; `hubble` — Relay and UI
    # exist. All false where the cloud operates Cilium.
    cilium = {
      installed  = local.cilium_installed
      gatewayApi = local.cilium_installed && local.cilium.gateway_api
      hubble     = local.cilium_installed && local.cilium.hubble
    }
    # What the cluster offers for volumes: `snapshots` — the CSI snapshot
    # controller and its CRDs are there, so a template may render a
    # VolumeSnapshotClass. On aws from the add-on this module installed; on
    # gcp always, GKE manages the PD CSI driver and the snapshot CRDs.
    storage = {
      snapshots = var.cloud == "gcp" ? true : local.eks_addon_installed.snapshot_controller
    }
    # The one GatewayClass a template targets for an internet-facing Gateway
    # or HTTPRoute parent, whatever the cloud: Cilium's where the socle runs
    # it, GKE's global external managed load balancer on gcp. Empty where
    # nothing implements Gateway API yet — scaleway, or Cilium with
    # gateway_api off — and a template must then render no Gateway.
    #
    # `shared` — the gateway_api module creates the two shared Gateways,
    # `public` and `private`, in `namespace`, and a route may attach to
    # their `https` listener. `certificateArn` — on aws, the ACM certificate
    # their load balancers terminate TLS with; empty elsewhere.
    # `certificateMap` — on gcp, the Certificate Manager map of the public
    # Gateway, and `regionalCertificate` the certificate of the private
    # one; empty elsewhere.
    gateway = {
      className           = local.gateway_class_name
      shared              = local.shared_gateways
      namespace           = "gateway-system"
      certificateArn      = local.gateway_certificate_arn
      certificateMap      = local.gateway_certificate_map
      regionalCertificate = local.gateway_regional_certificate
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

  lifecycle {
    precondition {
      condition     = var.schedulable_nodes != 0
      error_message = local.no_node_message
    }
  }

  # The Pod Identity Agent too, on aws: every catalog module that talks to
  # AWS gets its credentials from it, and without it they hang silently.
  depends_on = [helm_release.cilium, helm_release.coredns, aws_eks_addon.pod_identity_agent]
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
