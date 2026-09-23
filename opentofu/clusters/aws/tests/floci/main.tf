# CI fixture: floci applies the real root once but cannot re-apply it (it does
# not read back several EKS/CloudWatch attributes, and AssociateKmsKey is
# unsupported), so the mutation tests — toggle, garbage collection,
# idempotence — run against this bare, idempotent root: a cluster and the
# bootstrap module, nothing else. The real root is applied once by the
# e2e-aws-root job.
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws  = { source = "hashicorp/aws", version = ">= 6.0, < 7.0" }
    helm = { source = "hashicorp/helm", version = ">= 3.0, < 4.0" }
  }
}
variable "socle_version" { type = string }
variable "cosign_identity" {
  type = object({ issuer = string, subject = string })
}
variable "kube" {
  type    = any
  default = {}
}
variable "artifact_pull_secret" {
  type    = string
  default = ""
}
provider "aws" {
  region                      = "eu-west-3"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}
# A test double for floci's emulated EKS, never a real cluster: the endpoint
# is localhost inside a CI runner, floci stores none of these attributes, and
# the hardening lives in the foundations module the other e2e job applies.
#trivy:ignore:AVD-AWS-0038
#trivy:ignore:AVD-AWS-0039
#trivy:ignore:AVD-AWS-0040
#trivy:ignore:AVD-AWS-0041
resource "aws_eks_cluster" "e2e" {
  name     = "socle-e2e-catalog"
  role_arn = "arn:aws:iam::000000000000:role/eks-role"
  vpc_config { subnet_ids = ["subnet-00000001"] }
}
provider "helm" {
  kubernetes = {
    host                   = aws_eks_cluster.e2e.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.e2e.certificate_authority[0].data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.e2e.name, "--region", "eu-west-3"]
    }
  }
}
module "socle" {
  source               = "../../../../bootstrap"
  cloud                = "aws"
  cluster_name         = "socle-e2e-catalog"
  environment          = "dev"
  owner                = "platform"
  region               = "eu-west-3"
  kube                 = var.kube
  socle_version        = var.socle_version
  cosign_identity      = var.cosign_identity
  artifact_pull_secret = var.artifact_pull_secret
  # k3s brings its own CNI, kube-proxy and CoreDNS; the production default
  # would install Cilium over them. See tests/floci.tfvars.
  cilium = { enabled = false }
}
