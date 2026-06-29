locals {
  name = "slo-generator"
  selector_labels = {
    "app.kubernetes.io/name"      = local.name
    "app.kubernetes.io/component" = "api"
  }
  labels = merge(local.selector_labels, {
    "app.kubernetes.io/managed-by" = "terraform-kubernetes-google-slo-generator"
    "app.kubernetes.io/version"    = var.generator-version
  })

  # Name of the Secret synced from Vault (via ExternalSecret) holding the
  # Confluence credentials when the wiki feature is enabled.
  wiki_secret_name = "${local.name}-confluence"

  # Plain wiki env vars set on the container when the feature is enabled.
  # The Confluence credentials themselves come via envFrom (wiki_secret_name).
  wiki_env = var.wiki-enabled ? {
    OMNI_SLO_GENERATOR_WIKI_ENABLED = "true"
    OMNI_SLO_GENERATOR_TEAM         = var.team
  } : {}

  wiki_secrets = var.wiki-enabled ? [local.wiki_secret_name] : []
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
    name      = local.name
    namespace = var.namespace
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.slo-generator.email
    }
  }
}

resource "kubernetes_deployment" "slo-generator" {
  # When the wiki feature is on, the container consumes the Confluence Secret via
  # envFrom. That Secret is produced by the ExternalSecret below, but the
  # reference goes through computed locals, so there is no implicit graph edge —
  # make it explicit so the ExternalSecret is created before the rollout.
  depends_on = [kubernetes_manifest.wiki-confluence-secret]

  lifecycle {
    precondition {
      condition     = !var.wiki-enabled || trimspace(var.team) != ""
      error_message = "team must be set to a non-empty value when wiki-enabled is true."
    }
  }

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
        node_selector = {
          "iam.gke.io/gke-metadata-server-enabled" : "true"
        }
        container {
          name  = local.name
          image = "${var.image}:${var.image-tag}"
          env {
            name  = "OMNI_SLO_GENERATOR_SLO_GCS_BUCKET"
            value = google_storage_bucket.slos.name
          }
          env {
            name  = "OMNI_SLO_GENERATOR_INTERVAL_SECONDS"
            value = var.scrape_interval_seconds
          }
          dynamic "env" {
            for_each = merge(var.extra-env, local.wiki_env)
            content {
              name  = env.key
              value = env.value
            }
          }
          dynamic "env_from" {
            for_each = toset(concat(local.wiki_secrets, var.env-from-secrets))
            content {
              secret_ref {
                name = env_from.value
              }
            }
          }
          volume_mount {
            mount_path = "/etc/config/config.yaml"
            sub_path   = "config.yaml"
            name       = "config"
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
          liveness_probe {
            failure_threshold = 3
            http_get {
              path   = "/metrics"
              port   = "http"
              scheme = "HTTP"
            }
            period_seconds    = 30
            success_threshold = 1
            timeout_seconds   = 2
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.slo-generator.metadata[0].name
          }
        }
      }
    }
  }
}

# Wiki documentation feature: sync Confluence credentials from Vault into a
# Kubernetes Secret via the External Secrets Operator, then inject them as env
# vars (envFrom) on the container. Requires the namespace's SecretStore to have
# read access to the source Vault path (e.g. enabling common secrets for the
# project). The SecretStore is assumed to be named after the namespace.
resource "kubernetes_manifest" "wiki-confluence-secret" {
  count = var.wiki-enabled ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.wiki_secret_name
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      refreshInterval = var.wiki-secret-refresh-interval
      secretStoreRef = {
        name = var.wiki-secret-store-name == "" ? var.namespace : var.wiki-secret-store-name
        kind = var.wiki-secret-store-kind
      }
      target = {
        name = local.wiki_secret_name
      }
      data = [
        for key in var.wiki-confluence-secret-keys : {
          secretKey = key
          remoteRef = {
            key      = var.wiki-confluence-vault-key
            property = key
          }
        }
      ]
    }
  }

  # Block the apply until ESO reports the ExternalSecret as Ready, which means
  # the backing Kubernetes Secret has actually been synced from Vault and
  # exists. Combined with the deployment's depends_on, this ensures the
  # container does not roll out before the secret it consumes via envFrom is
  # present (avoiding a first-apply CreateContainerConfigError race).
  wait {
    condition {
      type   = "Ready"
      status = "True"
    }
  }

  # Fail fast instead of blocking the whole apply indefinitely: if ESO cannot
  # sync the secret (missing Vault key, misconfigured store, missing CRD), the
  # wait above errors after this timeout with a clear signal rather than hanging.
  timeouts {
    create = var.wiki-secret-wait-timeout
    update = var.wiki-secret-wait-timeout
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
      prometheus-backend-url          = var.prometheus-backend-url
      prometheus-backend-orgid-header = var.prometheus-backend-orgid-header
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


resource "kubernetes_manifest" "slo-generator-service-monitor" {
  provider = kubernetes

  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "ServiceMonitor"
    "metadata" = {
      "labels"    = merge(local.labels, var.servicemonitor-label)
      "name"      = local.name
      "namespace" = var.namespace
    }
    "spec" = {
      "endpoints" = [
        {
          path = "/metrics"
          port = kubernetes_service.slo-generator.spec[0].port[0].name
          metricRelabelings = [
            {
              action       = "drop"
              regex        = "events_count"
              sourceLabels = ["__name__"]
            }
          ]
        },
      ]
      "namespaceSelector" = {
        "matchNames" = [
          var.namespace,
        ]
      }
      "selector" = {
        "matchLabels" = local.selector_labels
      }
    }
  }
}


resource "kubernetes_ingress_v1" "slo-generator" {
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
            service {
              name = kubernetes_service.slo-generator.metadata[0].name
              port {
                name = kubernetes_service.slo-generator.spec[0].port[0].name
              }
            }
          }
          path = "/"
        }
      }
    }
  }
}
