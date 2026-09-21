variable "kubeconfig_path" {
  description = "Path to a kubeconfig for the target cluster, written from the foundations module's sensitive output."
  type        = string
}

variable "cluster_name" {
  description = "Cluster this Flux instance serves."
  type        = string
  default     = "socle-dev"
}

variable "environment" {
  description = "Environment this cluster serves."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Team accountable for the cluster."
  type        = string
  default     = "platform"
}

variable "cluster_type" {
  description = "Which cloud this runs on: kubernetes, aws, azure, gcp or openshift. Scaleway is kubernetes — it has no workload identity federation."
  type        = string
  default     = "kubernetes"
}

variable "sync_url" {
  description = "The socle artifact this cluster pulls."
  type        = string
}

variable "sync_ref" {
  description = "The tag or digest to pin. No default: pinning is the decision this module exists to record."
  type        = string
}

variable "cosign_identity" {
  description = "Keyless identity the artifact's signature must match."
  type = object({
    issuer  = string
    subject = string
  })
  default = null
}
