# Cloud Run Service URLs (4 services: JVM/Native × Direct/PgBouncer)
output "jvm_cloud_sql_url" {
  value       = google_cloud_run_v2_service.jvm_cloud_sql.uri
  description = "JVM + Cloud SQL Connector (Direct connection to Standard instance)"
}

output "native_cloud_sql_url" {
  value       = google_cloud_run_v2_service.native_cloud_sql.uri
  description = "Native Image + Cloud SQL Connector (Direct connection to Standard instance)"
}

output "jvm_cloud_sql_pgbouncer_url" {
  value       = google_cloud_run_v2_service.jvm_cloud_sql_pgbouncer.uri
  description = "JVM + Cloud SQL Connector + PgBouncer (Enterprise Plus instance)"
}

output "native_cloud_sql_pgbouncer_url" {
  value       = google_cloud_run_v2_service.native_cloud_sql_pgbouncer.uri
  description = "Native Image + Cloud SQL Connector + PgBouncer (Enterprise Plus instance)"
}

# Database outputs - Standard Instance (no managed pooling)
output "db_standard_instance_name" {
  value = google_sql_database_instance.standard.name
}

output "db_standard_connection_name" {
  value = google_sql_database_instance.standard.connection_name
}

output "db_standard_private_ip" {
  value = google_sql_database_instance.standard.private_ip_address
}

# Database outputs - Pooled Instance (with managed pooling/PgBouncer)
output "db_pooled_instance_name" {
  value = google_sql_database_instance.pooled.name
}

output "db_pooled_connection_name" {
  value = google_sql_database_instance.pooled.connection_name
}

output "db_pooled_private_ip" {
  value = google_sql_database_instance.pooled.private_ip_address
}