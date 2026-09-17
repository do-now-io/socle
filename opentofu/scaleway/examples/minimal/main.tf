# The smallest deployable socle foundation on Scaleway: a Project, a name, who
# owns it, the Kubernetes version, and the two decisions that have no safe
# default — who may reach the API server, and when it may be upgraded.
#
# Remote state deliberately lives in the consumer's own account and is not
# configured here — see README.md.

provider "scaleway" {
  project_id = var.project_id
  region     = var.region
  zone       = "${var.region}-1"
}

module "socle" {
  source = "../../"

  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name
  owner        = var.owner
  environment  = var.environment

  # No release channel exists on Scaleway, so the version is always explicit.
  kubernetes_version = var.kubernetes_version

  # The control plane cannot be made private on Kapsule. This list is the only
  # boundary there is, and leaving it unset is not an option the module offers.
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Auto-upgrade moves patches only. Tuesday for a dev cluster puts it days
  # ahead of production, which is what makes the ring order deterministic when
  # there is no channel to stagger.
  maintenance_window = {
    day        = "tuesday"
    start_hour = 3
  }

  # What the in-cluster Crossplane provider may provision, scoped to this
  # Project. Kept deliberately narrow here: the example provisions a socle, not
  # a client's application estate.
  crossplane_permission_sets = [
    "RelationalDatabasesFullAccess",
    "ObjectStorageFullAccess",
  ]
}
