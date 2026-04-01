resource "google_compute_firewall" "istio_eastwest" {
  name          = "mc-k8s-gke-istio-eastwest"
  project       = var.project_id
  network       = google_compute_network.this.name
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.aks_source_cidr]
  target_tags   = [local.node_tag]
  description   = "I open the east-west ports explicitly because cross-cloud mesh traffic is where I expect the first weird failure."

  allow {
    protocol = "tcp"
    ports    = ["15012", "15443"]
  }
}

resource "google_compute_firewall" "istio_webhook" {
  name          = "mc-k8s-gke-istio-webhook"
  project       = var.project_id
  network       = google_compute_network.this.name
  direction     = "INGRESS"
  priority      = 1001
  source_ranges = [var.master_ipv4_cidr_block]
  target_tags   = [local.node_tag]
  description   = "Private GKE control planes need port 15017 open for the Istio webhook path."

  allow {
    protocol = "tcp"
    ports    = ["15017"]
  }
}
