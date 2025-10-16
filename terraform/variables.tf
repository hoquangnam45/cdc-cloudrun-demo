variable "gcp_project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "gcp_region" {
  description = "The GCP region for resources."
  type        = string
  default     = "us-central1"
}

variable "db_name" {
  description = "The name of the Cloud SQL database."
  type        = string
  default     = "hello-cloud-run-db"
}

variable "db_user" {
  description = "The username for the Cloud SQL database."
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "The password for the Cloud SQL database."
  type        = string
  sensitive   = true
}