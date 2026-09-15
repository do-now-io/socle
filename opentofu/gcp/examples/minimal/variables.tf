variable "project_id" {
  description = "Google Cloud project to deploy into. Must be empty of a conflicting VPC named after the cluster."
  type        = string
}

variable "region" {
  description = "Region for the cluster and its subnetwork."
  type        = string
  default     = "europe-west1"
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
