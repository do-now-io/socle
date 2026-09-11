# Integration fixture: applies the module against the floci-gcp emulator, so
# that CI proves the module converges — init, plan, apply, destroy — without a
# cloud account or a secret.
#
# What this covers: the GKE cluster, the project role bindings, and the
# upgrade-notification topic.
#
# What it cannot cover: floci-gcp emulates no Compute Engine API, so the VPC,
# the subnetworks, the Cloud Router and Cloud NAT are out of reach. The
# fixture therefore attaches to a network it does not create. Those resources
# are exercised by `tofu test` at plan level only, and that gap is real — it
# is recorded in the workflow summary rather than papered over.

variable "endpoint" {
  description = "Base URL of the floci-gcp emulator."
  type        = string
  default     = "http://localhost:4588"
}

# Credentials are not cryptographically validated by the emulator; the token
# exists only so the provider does not go looking for real ones.
provider "google" {
  project = "socle-emulator"
  region  = "us-central1"

  access_token          = "floci-emulator-token"
  user_project_override = false

  container_custom_endpoint        = "${var.endpoint}/container/v1/"
  iam_custom_endpoint              = "${var.endpoint}/"
  iam_beta_custom_endpoint         = "${var.endpoint}/v1/"
  pubsub_custom_endpoint           = "${var.endpoint}/v1/"
  resource_manager_custom_endpoint = "${var.endpoint}/v1/"
  service_usage_custom_endpoint    = "${var.endpoint}/v1/"
}

module "socle" {
  source = "../../"

  project_id   = "socle-emulator"
  region       = "us-central1"
  cluster_name = "socle-emulator"
  owner        = "platform"
  environment  = "dev"

  # No Compute Engine in the emulator: attach to a network and subnetwork
  # rather than creating them.
  create_network           = false
  network_name             = "default"
  create_subnetwork        = false
  subnetwork_name          = "default"
  pod_range_name           = "pods"
  create_proxy_only_subnet = false
  create_nat               = false

  maintenance_window = {
    start_time = "2026-01-03T02:00:00Z"
    end_time   = "2026-01-03T14:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA"
  }

  # Exercises the project IAM read-modify-write path.
  observability_reader_members = ["serviceAccount:reader@socle-emulator.iam.gserviceaccount.com"]

  # The fixture destroys what it creates.
  deletion_protection = false
}

output "cluster_name" {
  description = "Proves the cluster came back from the emulator."
  value       = module.socle.cluster_name
}

output "upgrade_notifications_topic" {
  description = "Proves the notification topic was created and wired to the cluster."
  value       = module.socle.upgrade_notifications_topic
}
