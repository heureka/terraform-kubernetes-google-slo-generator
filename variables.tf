variable "gke-project" {
  type        = string
  description = "ID of the project which contains the GKE cluster in which the generator is going to live."
}

variable "generator-version" {
  type        = string
  description = "omni-slo-generator version to use"

  default = "1.0.1"
}

variable "storage-project" {
  type        = string
  description = "ID of the project which will be used for buckets etc."
}

variable "namespace" {
  type        = string
  description = "kubernetes namespace where to deploy slo generator"
}

variable "image" {
  type        = string
  description = "slo-generator image to use"

  default = "ghcr.io/heureka/omni-slo-generator"
}

variable "image-tag" {
  type        = string
  description = "slo-generator image tag to use"

  default = "releases-1.0.1"
}

variable "api-requests" {
  type        = map(string)
  description = "requests for the api in kubernetes"

  default = {
    cpu    = "200m"
    memory = "200Mi"
  }
}

variable "api-limits" {
  type        = map(string)
  description = "limits for the api in kubernetes"

  default = {
    cpu    = "200m"
    memory = "200Mi"
  }
}

variable "prometheus-backend-url" {
  type        = string
  description = "URL for the prometheus backend to read metrics from"

  default = "http://mimir-nginx.monitoring:8888/prometheus"
}

variable "prometheus-backend-orgid-header" {
  type        = string
  description = "URL for the prometheus backend to read metrics from"

  default = ""
}

variable "ingress-host" {
  type        = string
  description = "host at which the api should be available outside of kubernetes"

  default = ""
}

variable "ingress-class-name" {
  type        = string
  description = "ingress class to use for an ingress resource"

  default = "nginx"
}

variable "bucket-location" {
  type        = string
  description = "location for the GCS bucket which SLOs will be read from"

  default = "EU"
}

variable "bucket-name" {
  type        = string
  description = "name of the GCS bucket which SLOs will be read from"
}


variable "servicemonitor-label" {
  type        = map(string)
  description = "Special label for ServiceMonitor resource, in case your prometheus has `serviceMonitorSelector` set"

  default = {}
}

variable "scrape_interval_seconds" {
  type        = number
  description = "Interval to sleep between computations of scraped metrics"

  default = 30
}

variable "extra-env" {
  type        = map(string)
  description = "Additional plain (non-secret) environment variables to set on the generator container. Keys are env var names, values are their literal values."

  default = {}
}

variable "env-from-secrets" {
  type        = list(string)
  description = "Names of existing Kubernetes Secrets (in the same namespace) whose keys are injected as environment variables via envFrom. Secret keys must be named exactly as the target env vars."

  default = []
}

variable "wiki-enabled" {
  type        = bool
  description = "Enable the wiki documentation feature. Syncs the Confluence credentials from Vault into a Kubernetes Secret (via the External Secrets Operator) and injects them, along with the wiki env vars, into the generator container."

  default = false
}

variable "team" {
  type        = string
  description = "Team this instance generates documentation for. Used as the parent page name and isolation guard. Required when wiki-enabled is true."

  default = ""
}

variable "wiki-confluence-vault-key" {
  type        = string
  description = "Vault key (as resolved by the namespace's SecretStore) holding the Confluence credentials for the wiki feature."

  default = "kv-common/slo-generator"
}

variable "wiki-confluence-secret-keys" {
  type        = list(string)
  description = "Property names to read from the Vault key and expose as env vars for the wiki feature. Each becomes both the env var name and the Vault property name, so they must match the names the generator expects."

  default = [
    "OMNI_SLO_GENERATOR_CONFLUENCE_TOKEN",
    "OMNI_SLO_GENERATOR_CONFLUENCE_EMAIL",
    "OMNI_SLO_GENERATOR_CONFLUENCE_SPACE_KEY",
    "OMNI_SLO_GENERATOR_CONFLUENCE_ROOT_PAGE_ID",
  ]
}

variable "wiki-secret-store-name" {
  type        = string
  description = "Name of the (Cluster)SecretStore to read the wiki credentials from. Defaults to the namespace name when empty."

  default = ""
}

variable "wiki-secret-store-kind" {
  type        = string
  description = "Kind of the External Secrets store to read the wiki credentials from. Use ClusterSecretStore for cluster-scoped stores."

  default = "SecretStore"

  validation {
    condition     = contains(["SecretStore", "ClusterSecretStore"], var.wiki-secret-store-kind)
    error_message = "wiki-secret-store-kind must be either \"SecretStore\" or \"ClusterSecretStore\"."
  }
}

variable "wiki-secret-wait-timeout" {
  type        = string
  description = "How long terraform waits for the External Secrets Operator to report the wiki ExternalSecret as Ready before failing the apply."

  default = "3m"
}

variable "wiki-secret-refresh-interval" {
  type        = string
  description = "How often the External Secrets Operator re-reads the wiki credentials from Vault."

  default = "1h"
}
