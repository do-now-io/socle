# OCI module distribution needs OpenTofu 1.10 or later, the floor the
# conformance checklist sets. helm is the only provider: it is the one that
# applies a custom resource without needing the cluster, or its CRDs, to exist
# at plan time — which is what lets foundations and this module share one root.
terraform {
  required_version = ">= 1.10"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0, < 4.0"
    }
  }
}
