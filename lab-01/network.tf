resource "google_compute_network" "vpc" {
  name                    = "${var.network_prefix}-vpc"
  auto_create_subnetworks = false
  mtu                     = 8896
  depends_on              = [google_project_service.base_apis]
}

resource "google_compute_subnetwork" "subnets" {
  for_each      = toset(var.regions)
  name          = "${var.network_prefix}-node-subnet"
  region        = each.value
  network       = google_compute_network.vpc.id
  ip_cidr_range = each.value == "europe-west4" ? "10.0.1.0/24" : "10.0.2.0/24"
}

resource "google_compute_subnetwork" "proxy_subnets" {
  for_each      = toset(var.regions)
  name          = "${var.network_prefix}-proxy-subnet-${each.value}"
  region        = each.value
  network       = google_compute_network.vpc.id
  ip_cidr_range = each.value == "europe-west4" ? "10.1.1.0/24" : "10.1.2.0/24"
  purpose       = "GLOBAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

resource "google_compute_address" "gateway_ips" {
  for_each     = toset(var.regions)
  name         = "qwen-gateway-ip-${each.value}"
  region       = each.value
  subnetwork   = google_compute_subnetwork.subnets[each.value].id
  address_type = "INTERNAL"
}

resource "google_compute_firewall" "allow_internal" {
  name    = "${var.network_prefix}-allow-internal"
  network = google_compute_network.vpc.name
  allow { protocol = "all" }
  source_ranges = ["10.0.0.0/8", "10.1.0.0/16"]
}

resource "google_compute_firewall" "allow_health_checks" {
  name    = "${var.network_prefix}-allow-hc"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = ["8000"]
  }
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
}
