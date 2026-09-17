# Socle foundations for Azure.
#
# One flat root module: VNet, AKS cluster and identities. It provisions an
# empty-shell AKS Standard + Node Auto-Provisioning cluster and the
# identities the Flux-pulled socle needs, then steps away. Everything above
# that — Cilium, the catalog, the observability stack, application
# infrastructure — arrives through the socle OCI artifact and Crossplane.
#
# Every default here traces back to a research document under docs/azure/.
# Resources live in network.tf and cluster.tf.

locals {
  # Stamped onto every billable resource so cost can be attributed and
  # orphans can be found. Bumped with the module's own tag.
  socle_version = "0.1.0-dev"

  # The standard tag set. Azure tags take any UTF-8 key/value, so no
  # normalisation is needed here.
  tags = merge(
    {
      owner           = var.owner
      environment     = var.environment
      "socle-version" = local.socle_version
    },
    var.additional_tags,
  )

  # The resource group is referenced by name rather than looked up through a
  # data source: it keeps the module free of a lookup that would fail on a
  # resource group the consumer manages elsewhere, and it is what every
  # resource below needs regardless of who created it.
  resource_group_name = var.create_resource_group ? azurerm_resource_group.socle[0].name : var.resource_group_name
  location            = var.create_resource_group ? azurerm_resource_group.socle[0].location : var.location
}
