variable "gke-project" {
  type        = string
  description = "ID of the project which contains the GKE cluster in which the generator is going to live."
}

variable "generator-version" {
  type        = string
  description = "slo-generator version to use"

  default = "2.2.0"
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

  // This is not ideal, but let's wait for https://github.com/google/slo-generator/issues/159
  default = "gcr.io/slo-generator-ci-a2b4/slo-generator"
}

variable "image-tag" {
  type        = string
  description = "slo-generator image tag to use"

  default = "2.2.0"
}

variable "api-requests" {
  type        = map(string)
  description = "requests for the api in kubernetes"

  default = {
    cpu    = "100m"
    memory = "200Mi"
  }
}

variable "api-limits" {
  type        = map(string)
  description = "limits for the api in kubernetes"

  default = {
    cpu    = "100m"
    memory = "200Mi"
  }
}

variable "prometheus-backend-url" {
  type        = string
  description = "URL for the prometheus backend to read metrics from"

  default = "http://cortex-nginx.monitoring:8888/prometheus"
}

variable "ingress-host" {
  type        = string
  description = "host at which the api should be available outside of kubernetes"
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


variable "pushgateway-requests" {
  type        = map(string)
  description = "requests for the pushgateway in kubernetes"

  default = {
    cpu    = "100m"
    memory = "128Mi"
  }
}

variable "pushgateway-limits" {
  type        = map(string)
  description = "limits for the pushgateway in kubernetes"

  default = {
    cpu    = "100m"
    memory = "128Mi"
  }
}

variable "servicemonitor-label" {
  type        = map(string)
  description = "Special label for ServiceMonitor resource, in case your prometheus has `serviceMonitorSelector` set"

  default = {}
}