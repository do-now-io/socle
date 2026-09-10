variable "region" {
  description = "AWS region for the cluster and its VPC. Configures the provider; the module reads it back from there."
  type        = string
  default     = "eu-west-3"
}

variable "cluster_name" {
  description = "Name of the cluster."
  type        = string
  default     = "socle-minimal"
}

variable "owner" {
  description = "Team accountable for the cluster."
  type        = string
  default     = "platform"
}

variable "environment" {
  description = "Environment this cluster serves."
  type        = string
  default     = "dev"
}

variable "availability_zones" {
  description = "AZs the VPC's subnets are spread across."
  type        = list(string)
  default     = ["eu-west-3a", "eu-west-3b"]
}

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.34"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Replace with the consumer's own admin CIDR."
  type        = list(string)
  default     = ["203.0.113.0/32"]
}

variable "coredns_addon_version" {
  description = "CoreDNS add-on version. Check current versions with `aws eks describe-addon-versions` before a real apply."
  type        = string
  default     = "v1.11.4-eksbuild.10"
}

variable "ebs_csi_addon_version" {
  description = "EBS CSI driver add-on version. Same caveat as coredns_addon_version."
  type        = string
  default     = "v1.44.0-eksbuild.1"
}

variable "pod_identity_agent_addon_version" {
  description = "Pod Identity Agent add-on version. Same caveat as coredns_addon_version."
  type        = string
  default     = "v1.3.4-eksbuild.1"
}
