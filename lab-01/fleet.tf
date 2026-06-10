data "google_project" "project" {
  project_id = var.project_id
}

resource "google_project_service" "fleet_apis" {
  for_each = toset([
    "gkehub.googleapis.com",
    "multiclusterservicediscovery.googleapis.com",
    "multiclusteringress.googleapis.com",
    "trafficdirector.googleapis.com"
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_service_identity" "mci_sa" {
  provider   = google-beta
  project    = var.project_id
  service    = "multiclusteringress.googleapis.com"
  depends_on = [google_project_service.fleet_apis]
}

resource "time_sleep" "wait_for_apis" {
  create_duration = "60s"
  depends_on      = [google_project_service.fleet_apis]
}

resource "google_project_iam_member" "mci_sa_admin" {
  project    = var.project_id
  role       = "roles/container.admin"
  member     = "serviceAccount:${google_project_service_identity.mci_sa.email}"
  depends_on = [google_project_service_identity.mci_sa, time_sleep.wait_for_apis]
}

resource "google_gke_hub_membership" "memberships" {
  provider      = google-beta
  for_each      = toset(var.regions)
  project       = var.project_id
  membership_id = "gke-${each.value}"
  endpoint {
    gke_cluster { resource_link = "//container.googleapis.com/${google_container_cluster.clusters[each.value].id}" }
  }
  depends_on = [time_sleep.wait_for_apis, google_container_cluster.clusters]
}

resource "google_gke_hub_feature" "mcs" {
  provider   = google-beta
  name       = "multiclusterservicediscovery"
  location   = "global"
  project    = var.project_id
  depends_on = [time_sleep.wait_for_apis]
}

resource "google_project_iam_member" "mcs_importer_network_viewer" {
  project    = var.project_id
  role       = "roles/compute.networkViewer"
  member     = "serviceAccount:${var.project_id}.svc.id.goog[gke-mcs/gke-mcs-importer]"
  depends_on = [google_gke_hub_feature.mcs]
}

resource "google_gke_hub_feature" "ingress" {
  provider = google-beta
  name     = "multiclusteringress"
  location = "global"
  project  = var.project_id
  depends_on = [
    google_gke_hub_membership.memberships,
    google_gke_hub_feature.mcs,
    google_project_iam_member.mci_sa_admin,
    google_project_iam_member.mcs_importer_network_viewer
  ]
  spec {
    multiclusteringress { config_membership = "projects/${var.project_id}/locations/global/memberships/gke-asia-northeast1" }
  }
}
