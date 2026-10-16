# OCI module distribution needs OpenTofu 1.10 or later, the floor the
# conformance checklist sets. helm applies everything that runs in the
# cluster: it is the one provider that applies a custom resource without
# needing the cluster, or its CRDs, to exist at plan time — which is what lets
# foundations and this module share one root. aws creates the EKS-managed
# add-ons and their identities (eks_addons.tf); on every other cloud it has
# no resource and makes no call — but OpenTofu still configures every
# provider a configuration names, even one whose resources all have
# count = 0, so a root on another cloud declares a stub `aws` provider that
# skips its credential and account checks (README, "Where it runs").
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0, < 4.0"
    }
  }
}
