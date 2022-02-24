locals {
  name            = "slo-generator"
  selector_labels = {
    "app.kubernetes.io/name"      = local.name
    "app.kubernetes.io/component" = "api"
  }
  labels = merge(local.selector_labels, {
    "app.kubernetes.io/managed-by" = "terraform-kubernetes-google-slo-generator"
    "app.kubernetes.io/version"    = var.generator-version
  })
}

module "prometheus-pushgateway" {
  source  = "heureka/prometheus-pushgateway/kubernetes"
  version = "1.0.2"

  name                 = "slo-generator-pushgateway"
  namespace            = var.namespace
  requests             = var.pushgateway-requests
  limits               = var.pushgateway-limits
  servicemonitor-label = var.servicemonitor-label
}

resource "google_service_account" "slo-generator" {
  project = var.storage-project

  account_id   = local.name
  display_name = "SLO Generator"
}

resource "google_service_account_iam_binding" "slo-generator-workload-identity" {
  service_account_id = google_service_account.slo-generator.name
  role               = "roles/iam.workloadIdentityUser"
  members            = ["serviceAccount:${var.gke-project}.svc.id.goog[${var.namespace}/${local.name}]"]
}

resource "google_storage_bucket" "slos" {
  project = var.storage-project

  location = var.bucket-location
  name     = var.bucket-name

  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "slo-generator-gcs-object-viewer" {
  bucket = google_storage_bucket.slos.id
  member = "serviceAccount:${google_service_account.slo-generator.email}"
  role   = "roles/storage.objectViewer"
}

resource "google_storage_bucket_iam_member" "slo-generator-gcs-legacy-bucket-reader" {
  bucket = google_storage_bucket.slos.id
  member = "serviceAccount:${google_service_account.slo-generator.email}"
  role   = "roles/storage.legacyBucketReader"
}

resource "kubernetes_service_account" "slo-generator" {
  metadata {
    name        = local.name
    namespace   = var.namespace
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.slo-generator.email
    }
  }
}

resource "kubernetes_deployment" "slo-generator" {
  metadata {
    name      = local.name
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    selector {
      match_labels = local.selector_labels
    }
    template {
      metadata {
        labels = local.labels
        name   = local.name
      }
      spec {
        service_account_name = kubernetes_service_account.slo-generator.metadata[0].name
        node_selector        = {
          "iam.gke.io/gke-metadata-server-enabled" : "true"
        }
        container {
          name  = local.name
          image = "${var.image}:${var.image-tag}"
          args  = ["api", "--config", "/etc/config/config.yaml"]
          volume_mount {
            mount_path = "/etc/config/config.yaml"
            sub_path   = "config.yaml"
            name       = "config"
          }
          volume_mount {
            mount_path = "/tmp"
            name       = "tmp"
          }
          port {
            container_port = 8080
            name           = "http"
          }
          resources {
            requests = var.api-requests
            limits   = var.api-limits
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.slo-generator.metadata[0].name
          }
        }
        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_config_map" "slo-generator" {
  metadata {
    name      = local.name
    namespace = var.namespace
    labels    = local.labels
  }
  data = {
    "config.yaml" = templatefile("${path.module}/config.yaml", {
      prometheus-backend-url = var.prometheus-backend-url
    })
  }
}

resource "kubernetes_service" "slo-generator" {
  metadata {
    name      = local.name
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    type = "ClusterIP"
    port {
      port        = 8080
      name        = "http"
      target_port = kubernetes_deployment.slo-generator.spec[0].template[0].spec[0].container[0].port[0].name
    }
    selector = local.selector_labels
  }
}

resource "kubernetes_ingress" "slo-generator" {
  count = var.ingress-host == "" ? 0 : 1

  metadata {
    name      = local.name
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    ingress_class_name = var.ingress-class-name
    rule {
      host = var.ingress-host
      http {
        path {
          backend {
            service_name = kubernetes_service.slo-generator.metadata[0].name
            service_port = kubernetes_service.slo-generator.spec[0].port[0].name
          }
          path = "/"
        }
      }
    }
  }
}
