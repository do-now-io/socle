# The smallest deployable socle foundation on Google Cloud: a project, a
# region, a name, and who owns it. Everything else is the module's
# recommended position.
#
# Remote state deliberately lives in the consumer's own account and is not
# configured here — see README.md.

provider "google" {
  project = var.project_id
  region  = var.region
}

module "socle" {
  source = "../../"

  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name
  owner        = var.owner
  environment  = var.environment

  # Greenfield: let the module build the VPC. Point network_name at an
  # existing one instead when the consumer already owns a network.
  create_network = true

  # No good default exists for when a cluster may be upgraded, so the module
  # has none. Saturday 02:00 UTC for twelve hours is the prod slot of the
  # ring order (dev Tuesday, staging Wednesday, prod Saturday). This example
  # is dev by default and keeps it; a dev cluster in an estate takes the
  # Tuesday window, so that it upgrades first.
  maintenance_window = {
    start_time = "2026-01-03T02:00:00Z"
    end_time   = "2026-01-03T14:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA"
  }
}
