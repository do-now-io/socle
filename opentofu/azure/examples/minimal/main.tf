# The smallest deployable socle foundation on Azure: a region, a name, who
# owns it, and the handful of variables the module deliberately leaves with
# no default. Everything else is the module's recommended position.
#
# Remote state deliberately lives in the consumer's own account and is not
# configured here — see README.md.

provider "azurerm" {
  features {}
}

module "socle" {
  source = "../../"

  location            = var.location
  cluster_name        = var.cluster_name
  owner               = var.owner
  environment         = var.environment
  resource_group_name = var.resource_group_name

  # Greenfield: let the module build the resource group and VNet. Point
  # resource_group_name/vnet_name/node_subnet_id at existing ones instead
  # when the consumer already owns them.
  create_resource_group = true
  create_vnet           = true

  zones = var.zones

  system_node_pool_vm_size = var.system_node_pool_vm_size

  kubernetes_version = var.kubernetes_version

  # No good default exists for when maintenance is allowed to run, so the
  # module has none — replace with windows that fit the consumer's own
  # operations.
  maintenance_window_auto_upgrade = var.maintenance_window_auto_upgrade
  maintenance_window_node_os      = var.maintenance_window_node_os
}
