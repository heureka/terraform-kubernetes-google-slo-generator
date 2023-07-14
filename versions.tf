terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">=2.22.0"
    }
    google = {
      source  = "hashicorp/google"
      version = ">=3.79.0"
    }
  }
  required_version = ">= 1.1.6"
}
