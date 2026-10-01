# CI fixture: floci applies the real root once but cannot re-apply it (it does
# not read back several EKS/CloudWatch attributes, and AssociateKmsKey is
# unsupported), so the per-module jobs of .github/workflows/e2e.yaml — the
# Chainsaw suites, the one OpenTofu-driven mutation, the second plan, the
# destroy — run against this bare, idempotent root: a cluster and the
# bootstrap module, nothing else. The real root is applied once by the
# root job, with floci.tfvars beside this file.
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
# floci 2.x checks that the cluster's subnets exist (1.5 accepted any id), so
# the double owns the smallest VPC that satisfies it: one network, one subnet.
# A floci VPC is a Docker network in RFC 1918 space; nothing else reads it.
#trivy:ignore:AVD-AWS-0178
resource "aws_vpc" "e2e" {
  cidr_block = "10.42.0.0/16"
}
resource "aws_subnet" "e2e" {
  vpc_id     = aws_vpc.e2e.id
  cidr_block = "10.42.0.0/24"
}
# A test double for floci's emulated EKS, never a real cluster: the endpoint
# is localhost inside a CI runner, floci stores none of these attributes, and
# the hardening lives in the foundations module the root job applies.
#trivy:ignore:AVD-AWS-0038
#trivy:ignore:AVD-AWS-0039
#trivy:ignore:AVD-AWS-0040
#trivy:ignore:AVD-AWS-0041
resource "aws_eks_cluster" "e2e" {
  name     = "socle-e2e-catalog"
  role_arn = "arn:aws:iam::000000000000:role/eks-role"
  vpc_config { subnet_ids = [aws_subnet.e2e.id] }
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
  source       = "../../../opentofu/bootstrap"
  cloud        = "aws"
  cluster_name = "socle-e2e-catalog"
  environment  = "dev"
  owner        = "platform"
  region       = "eu-west-3"
  # The job's kube, over the e2e's one fixed value: ArgoCD's redis image from
  # Docker Hub rather than the chart's ecr-public.aws.com. GitHub-hosted
  # runners share egress IPs, and ECR Public answers their anonymous pulls
  # with 429 Too Many Requests — the argocd flake, caught by the module's
  # catch block on runs 36771300863 and 36773729014 (redis:8.6.4-alpine in
  # ImagePullBackOff for five minutes). A client on AWS is not throttled so;
  # the socle's default stays.
  kube = merge({
    argocd = { values = { redis = { image = { repository = "docker.io/library/redis" } } } }
  }, var.kube)
  socle_version        = var.socle_version
  cosign_identity      = var.cosign_identity
  artifact_pull_secret = var.artifact_pull_secret
  # k3s brings its own CNI, kube-proxy and CoreDNS; the production default
  # would install Cilium over them. See floci.tfvars beside this file.
  cilium = { enabled = false }
  # And no EKS add-on API in floci 2.1.0 either (CreateAddon: "Unknown
  # operation", measured 2026-10-01; it exists on nightly). See floci.tfvars.
  eks_addons = { pod_identity_agent = false, ebs_csi = false, snapshot_controller = false }
}
