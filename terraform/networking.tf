# VPC Network
resource "google_compute_network" "vpc" {
  name                    = "hello-cloud-run-vpc"
  auto_create_subnetworks = false
}

# Subnet for VPC Connector
resource "google_compute_subnetwork" "vpc_connector" {
  name          = "hello-cloud-run-connector-subnet"
  ip_cidr_range = "10.8.0.0/28"
  region        = var.gcp_region
  network       = google_compute_network.vpc.id
}

# VPC Access Connector for Cloud Run
resource "google_vpc_access_connector" "connector" {
  name          = "hello-cloud-run-connector"
  region        = var.gcp_region
  machine_type  = "e2-micro"
  min_instances = 2
  max_instances = 3

  subnet {
    name = google_compute_subnetwork.vpc_connector.name
  }

  depends_on = [google_compute_subnetwork.vpc_connector, google_project_service.vpcaccess]
}

# Private Service Connection for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  name          = "hello-cloud-run-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

# Enable required APIs
resource "google_project_service" "vpcaccess" {
  service            = "vpcaccess.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "servicenetworking" {
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sqladmin" {
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudrun" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}
