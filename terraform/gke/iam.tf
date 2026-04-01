resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = local.node_service_account_id
  display_name = "mc-k8s GKE node pool service account"
}

resource "google_service_account" "workload_identity" {
  project      = var.project_id
  account_id   = local.workload_identity_service_account_id
  display_name = "mc-k8s workload identity service account"
}

resource "google_project_iam_member" "gke_nodes" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "workload_identity" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.workload_identity.email}"
}
