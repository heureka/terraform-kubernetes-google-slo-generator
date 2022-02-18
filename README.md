# terraform-kubernetes-google-slo-generator

An extremely opinionated module, that deploys Google's 
[SLO generator](https://github.com/google/slo-generator/) into GKE.

## Assumptions made

* Prometheus backend is a cortex cluster (without multi tenancy)
  * Cortex is running in monitoring namespace and has a nginx pod `cortex-nginx` for proxying (as cortex helm chart does it)
  * This can be overridden variable `prometheus-backend-url`
* Exporter is a pushgateway deployed by this module (might change if [this](https://github.com/google/slo-generator/pull/209) gets merged)
* You want to keep the default policies as shown in slo-exporter's examples (1h, 12h, 7d, 28d)
* You are using ingress nginx controller (this is configurable)
* GKE cluster has [workload identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity) enabled
