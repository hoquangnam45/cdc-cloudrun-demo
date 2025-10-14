# Cloud SQL Instance WITH Managed Connection Pooling (Enterprise Plus)
resource "google_sql_database_instance" "pooled" {
  name             = "hello-cloud-run-pooled-${random_id.db_suffix.hex}"
  database_version = "POSTGRES_15"
  region           = var.gcp_region

  depends_on = [google_service_networking_connection.private_vpc_connection]

  deletion_protection = false

  settings {
    tier              = "db-perf-optimized-N-2"  # Enterprise Plus tier
    edition           = "ENTERPRISE_PLUS"
    availability_type = "ZONAL"
    disk_size         = 10

    ip_configuration {
      ipv4_enabled    = true
      private_network = google_compute_network.vpc.id
      ssl_mode        = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"
    }

    backup_configuration {
      enabled = false
    }

    # Enable managed connection pooling (PgBouncer)
    connection_pool_config {
      connection_pooling_enabled = true
    }
  }
}

# Cloud SQL Instance WITHOUT Managed Connection Pooling (Enterprise Plus, but no PgBouncer)
# Same tier as pooled instance for fair comparison - only difference is PgBouncer enabled/disabled
resource "google_sql_database_instance" "standard" {
  name             = "hello-cloud-run-standard-${random_id.db_suffix.hex}"
  database_version = "POSTGRES_15"
  region           = var.gcp_region

  depends_on = [google_service_networking_connection.private_vpc_connection]

  deletion_protection = false

  settings {
    tier              = "db-perf-optimized-N-2"  # Same tier as pooled instance for fair comparison
    edition           = "ENTERPRISE_PLUS"         # Required for db-perf-optimized tier
    availability_type = "ZONAL"
    disk_size         = 10

    ip_configuration {
      ipv4_enabled    = true
      private_network = google_compute_network.vpc.id
      ssl_mode        = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"
    }

    backup_configuration {
      enabled = false
    }

    # No connection_pool_config - standard tier doesn't support it
  }
}

resource "random_id" "db_suffix" {
  byte_length = 4
}

# Database for pooled instance
resource "google_sql_database" "pooled" {
  name     = var.db_name
  instance = google_sql_database_instance.pooled.name
}

resource "google_sql_user" "pooled" {
  name     = var.db_user
  instance = google_sql_database_instance.pooled.name
  password = var.db_password
}

# Database for standard instance
resource "google_sql_database" "standard" {
  name     = var.db_name
  instance = google_sql_database_instance.standard.name
}

resource "google_sql_user" "standard" {
  name     = var.db_user
  instance = google_sql_database_instance.standard.name
  password = var.db_password
}