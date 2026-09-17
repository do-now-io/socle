# Integration fixture: plans the module against the floci-az emulator, so
# that CI proves the module resolves its providers, data sources and inputs
# without a cloud account or a secret.
#
# A fixture, not the bare module, because azurerm has no environment-only
# configuration path: it hard-requires an explicit
# `provider "azurerm" { features {} }` block regardless of what's set in the
# environment. Confirmed empirically against floci-az directly: a plan with
# every ARM_* variable set and no provider block still fails with "Provider
# requires explicit configuration."

variable "endpoint" {
  description = "Hostname (no scheme) of the floci-az emulator — azurerm's metadata_host always prepends https:// itself."
  type        = string
  default     = "localhost:4577"
}

# floci-az implements Azure's own custom-cloud metadata discovery contract
# (GET /metadata/endpoints — the same mechanism real sovereign clouds like
# Azure Germany or Azure China use), so metadata_host is enough on its own —
# no need to override each service's endpoint individually. Credentials
# aren't cryptographically validated by the emulator; they exist only so
# the provider does not go looking for real ones.
#
# azurerm's metadata discovery is HTTPS-only, unconditionally — confirmed
# empirically, there is no plaintext override. floci-az must run with
# FLOCI_AZ_TLS_ENABLED=true, and its self-signed certificate (served at
# GET /_floci/tls-cert) must be trusted before this plan runs — Go's HTTP
# client honors SSL_CERT_FILE, so no system trust store change is needed.
# `environment` isn't the fixed public/usgovernment/german/china enum here:
# once metadata_host is set, it must instead match the "name" floci-az's
# own metadata response declares — "floci-az".
provider "azurerm" {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  tenant_id       = "00000000-0000-0000-0000-000000000002"
  client_id       = "00000000-0000-0000-0000-000000000000"
  client_secret   = "floci-emulator-secret"
  use_cli         = false

  metadata_host = var.endpoint
  environment   = "floci-az"

  resource_provider_registrations = "none"

  features {}
}

module "socle" {
  source = "../../"

  location            = "francecentral"
  cluster_name        = "socle-emulator"
  owner               = "platform"
  environment         = "dev"
  resource_group_name = "socle-emulator"

  create_resource_group = true
  create_vnet           = true

  kubernetes_version = "1.34"

  maintenance_window_auto_upgrade = {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "+00:00"
  }

  maintenance_window_node_os = {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Saturday"
    start_time  = "02:00"
    utc_offset  = "+00:00"
  }
}

output "cluster_name" {
  description = "Proves the cluster came back from the emulator."
  value       = module.socle.cluster_name
}
