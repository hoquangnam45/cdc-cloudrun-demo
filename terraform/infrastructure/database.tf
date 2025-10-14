resource "google_sql_database_instance" "main" {
  name             = "hello-cloud-run-instance-${random_id.db_suffix.hex}"
  database_version = "POSTGRES_15"
  region           = var.gcp_region

  deletion_protection = false

  settings {
    tier              = "db-g1-small"  # 100 max connections (was 25 with db-f1-micro)
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

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "random_id" "db_suffix" {
  byte_length = 4
}

resource "google_sql_database" "main" {
  name     = var.db_name
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "main" {
  name     = var.db_user
  instance = google_sql_database_instance.main.name
  password = var.db_password
}