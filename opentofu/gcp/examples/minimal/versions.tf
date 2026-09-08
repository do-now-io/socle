# An example is a root module: it pins nothing the module itself pins, and it
# carries a committed lock file so that an apply is reproducible.
#
# There is no backend block on purpose. Remote state belongs in the consumer's
# own account, and the module neither creates nor assumes one.

terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0, < 9.0"
    }
  }
}
