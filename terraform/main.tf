terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "random" {
}