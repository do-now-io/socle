# OCI module distribution needs OpenTofu 1.10 or later, which is the floor
# the conformance checklist sets. Provider constraints are bounded ranges:
# this is a child module, so an open floor would let a provider major break
# every consumer, and an exact pin would make it impossible to compose.

terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0, < 9.0"
    }
  }
}
