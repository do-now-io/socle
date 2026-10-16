# Anonymous `tofu init` of the published OCI modules needs OpenTofu 1.13 or
# later (below it, ghcr refuses the anonymous token: issue #89), which is the
# floor the conformance checklist sets. Provider constraints are bounded
# ranges: this is a child module, so an open floor would let a provider major
# break every consumer, and an exact pin would make it impossible to compose.

terraform {
  required_version = ">= 1.13"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}
