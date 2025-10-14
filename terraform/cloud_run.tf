# Cloud Run Services - Simplified Configuration
# 4 services: JVM/Native × Direct/PgBouncer (Cloud SQL Connector only)
# All services use the same pooled instance (Enterprise Plus with PgBouncer)
# - Direct services connect to port 5432 (standard PostgreSQL)
# - PgBouncer services connect to port 6432 (managed PgBouncer)

# ========================================
# Direct Connection Services (Port 5432 - bypasses PgBouncer)
# ========================================

resource "google_cloud_run_v2_service" "jvm_cloud_sql" {
  name                = "hello-cloud-run-jvm-cloud-sql"
  location            = var.gcp_region
  deletion_protection = false

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = "asia-southeast1-docker.pkg.dev/${var.gcp_project_id}/cloud-run-demo/quarkus-cloud-run-jvm:latest"
      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }

      env {
        name  = "QUARKUS_PROFILE"
        value = "cloud-sql"
      }
      env {
        name  = "INSTANCE_CONNECTION_NAME"
        value = google_sql_database_instance.standard.connection_name
      }
      env {
        name  = "DB_NAME"
        value = var.db_name
      }
      env {
        name  = "DB_USER"
        value = var.db_user
      }
      env {
        name  = "DB_PASS"
        value = var.db_password
      }

      startup_probe {
        http_get {
          path = "/actuator/health/ready"
          port = 8080
        }
        initial_delay_seconds = 15
        period_seconds        = 10
        failure_threshold     = 10
        timeout_seconds       = 3
      }
    }
  }

  depends_on = [google_sql_database_instance.standard]
}

resource "google_cloud_run_v2_service" "native_cloud_sql" {
  name                = "native-hello-cloud-run-cloud-sql"
  location            = var.gcp_region
  deletion_protection = false

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = "asia-southeast1-docker.pkg.dev/${var.gcp_project_id}/cloud-run-demo/quarkus-cloud-run-native:latest"
      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }

      env {
        name  = "QUARKUS_PROFILE"
        value = "cloud-sql"
      }
      env {
        name  = "INSTANCE_CONNECTION_NAME"
        value = google_sql_database_instance.standard.connection_name
      }
      env {
        name  = "DB_NAME"
        value = var.db_name
      }
      env {
        name  = "DB_USER"
        value = var.db_user
      }
      env {
        name  = "DB_PASS"
        value = var.db_password
      }

      startup_probe {
        http_get {
          path = "/actuator/health/ready"
          port = 8080
        }
        initial_delay_seconds = 15
        period_seconds        = 10
        failure_threshold     = 10
        timeout_seconds       = 3
      }
    }
  }

  depends_on = [google_sql_database_instance.standard]
}

# ========================================
# PgBouncer Services (Port 6432 - uses managed PgBouncer)
# ========================================

resource "google_cloud_run_v2_service" "jvm_cloud_sql_pgbouncer" {
  name                = "hello-cloud-run-jvm-cloud-sql-pgbouncer"
  location            = var.gcp_region
  deletion_protection = false

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = "asia-southeast1-docker.pkg.dev/${var.gcp_project_id}/cloud-run-demo/quarkus-cloud-run-jvm:latest"
      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }

      env {
        name  = "QUARKUS_PROFILE"
        value = "cloud-sql-pgbouncer"
      }
      env {
        name  = "INSTANCE_CONNECTION_NAME"
        value = google_sql_database_instance.pooled.connection_name
      }
      env {
        name  = "DB_NAME"
        value = var.db_name
      }
      env {
        name  = "DB_USER"
        value = var.db_user
      }
      env {
        name  = "DB_PASS"
        value = var.db_password
      }

      startup_probe {
        http_get {
          path = "/actuator/health/ready"
          port = 8080
        }
        initial_delay_seconds = 15
        period_seconds        = 10
        failure_threshold     = 10
        timeout_seconds       = 3
      }
    }
  }

  depends_on = [google_sql_database_instance.pooled]
}

resource "google_cloud_run_v2_service" "native_cloud_sql_pgbouncer" {
  name                = "native-hello-cloud-run-cloud-sql-pgbouncer"
  location            = var.gcp_region
  deletion_protection = false

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = "asia-southeast1-docker.pkg.dev/${var.gcp_project_id}/cloud-run-demo/quarkus-cloud-run-native:latest"
      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }

      env {
        name  = "QUARKUS_PROFILE"
        value = "cloud-sql-pgbouncer"
      }
      env {
        name  = "INSTANCE_CONNECTION_NAME"
        value = google_sql_database_instance.pooled.connection_name
      }
      env {
        name  = "DB_NAME"
        value = var.db_name
      }
      env {
        name  = "DB_USER"
        value = var.db_user
      }
      env {
        name  = "DB_PASS"
        value = var.db_password
      }

      startup_probe {
        http_get {
          path = "/actuator/health/ready"
          port = 8080
        }
        initial_delay_seconds = 15
        period_seconds        = 10
        failure_threshold     = 10
        timeout_seconds       = 3
      }
    }
  }

  depends_on = [google_sql_database_instance.pooled]
}

# ========================================
# IAM - Public Access (for demo purposes)
# ========================================

resource "google_cloud_run_service_iam_member" "jvm_cloud_sql_public" {
  service  = google_cloud_run_v2_service.jvm_cloud_sql.name
  location = google_cloud_run_v2_service.jvm_cloud_sql.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "native_cloud_sql_public" {
  service  = google_cloud_run_v2_service.native_cloud_sql.name
  location = google_cloud_run_v2_service.native_cloud_sql.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "jvm_cloud_sql_pgbouncer_public" {
  service  = google_cloud_run_v2_service.jvm_cloud_sql_pgbouncer.name
  location = google_cloud_run_v2_service.jvm_cloud_sql_pgbouncer.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "native_cloud_sql_pgbouncer_public" {
  service  = google_cloud_run_v2_service.native_cloud_sql_pgbouncer.name
  location = google_cloud_run_v2_service.native_cloud_sql_pgbouncer.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
