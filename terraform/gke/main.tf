locals {
  node_pool_name                         = "primary"
  node_service_account_id                = "mc-k8s-gke-nodes"
  workload_identity_service_account_id   = "mc-k8s-workload"
  node_tag                               = "mc-k8s-gke-nodes"
  ingress_ip_name                        = "mc-k8s-gke-ingress-ip"
}

resource "google_compute_network" "this" {
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "Primary VPC for the zonal GKE cluster and future mesh traffic."
}

resource "google_compute_subnetwork" "this" {
  name                     = var.subnetwork_name
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
  description              = "Node subnet for GKE. I keep the pod and service ranges separate so peering later stays less painful."

  secondary_ip_range {
    range_name    = var.pods_secondary_name
    ip_cidr_range = var.pods_secondary_cidr
  }

  secondary_ip_range {
    range_name    = var.services_secondary_name
    ip_cidr_range = var.services_secondary_cidr
  }
}

resource "google_compute_address" "ingress" {
  name         = local.ingress_ip_name
  project      = var.project_id
  region       = var.region
  address_type = "EXTERNAL"
  description  = "Reserved public IP for the future GKE Istio ingress gateway."
}

resource "google_container_cluster" "this" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.zone

  network    = google_compute_network.this.self_link
  subnetwork = google_compute_subnetwork.this.self_link

  deletion_protection      = false
  remove_default_node_pool = true
  initial_node_count       = 1
  min_master_version       = var.gke_version
  networking_mode          = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_name
    services_secondary_range_name = var.services_secondary_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = true
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = var.release_channel
  }

  resource_labels  = var.labels
  logging_service  = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }

    http_load_balancing {
      disabled = false
    }
  }

  # TODO: add a dedicated monitoring node pool if Prometheus starts stealing too much memory.
}

resource "google_container_node_pool" "primary" {
  name       = local.node_pool_name
  project    = var.project_id
  location   = var.zone
  cluster    = google_container_cluster.this.name
  node_count = var.min_nodes
  version    = var.gke_version

  autoscaling {
    min_node_count = var.min_nodes
    max_node_count = var.max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.node_machine_type
    disk_type       = "pd-balanced"
    disk_size_gb    = 100
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    tags            = [local.node_tag]

    labels = merge(var.labels, {
      cloud = "gke"
      pool  = local.node_pool_name
    })

    metadata = {
      disable-legacy-endpoints = "true"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  lifecycle {
    ignore_changes = [node_count]
  }

  depends_on = [google_project_iam_member.gke_nodes]
}
