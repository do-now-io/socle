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
  description = "EKS control plane version. The default tracks the n-1 policy ceiling — not the newest EKS offers, and not one close to the end of its standard support."
  type        = string
  default     = "1.35"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Replace with the consumer's own admin CIDR."
  type        = list(string)
  default     = ["203.0.113.0/32"]
}
