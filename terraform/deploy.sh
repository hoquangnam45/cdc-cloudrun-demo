#!/bin/bash

set -e

# Authenticate with gcloud
gcloud auth application-default login

# Initialize Terraform
terraform init

# Apply the Terraform configuration
terraform apply -auto-approve
