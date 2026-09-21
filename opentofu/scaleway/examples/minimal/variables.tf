variable "project_id" {
  description = "Scaleway Project to deploy into. One Project per environment — it is the only boundary Scaleway offers for both IAM and cost."
  type        = string
}

variable "region" {
  description = "Region for the cluster and its network."
  type        = string
  default     = "fr-par"
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

variable "kubernetes_version" {
  description = "Kubernetes minor to deploy. Explicit by design: Scaleway has no release channel."
  type        = string
  default     = "1.35"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API server. No default: whoever deploys this has to say who gets in."
  type        = list(string)
}
