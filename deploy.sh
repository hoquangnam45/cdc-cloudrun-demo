#!/bin/bash

set -e

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "Usage: ./deploy.sh <project-id> <db-user> <db-password> [region]"
  echo ""
  echo "Example:"
  echo "  ./deploy.sh my-project-id dbuser mypassword us-central1"
  exit 1
fi

PROJECT_ID=$1
DB_USER=$2
DB_PASSWORD=$3
REGION=${4:-us-central1}

echo "===================================="
echo "Deploying Cloud Run Demo"
echo "===================================="
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo "DB User: $DB_USER"
echo ""

# Change to terraform directory
cd terraform

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Plan the deployment
echo ""
echo "Planning deployment..."
terraform plan \
  -var="gcp_project_id=$PROJECT_ID" \
  -var="gcp_region=$REGION" \
  -var="db_user=$DB_USER" \
  -var="db_password=$DB_PASSWORD"

# Ask for confirmation
# echo ""
# read -p "Do you want to proceed with the deployment? (yes/no): " CONFIRM
#
# if [ "$CONFIRM" != "yes" ]; then
#   echo "Deployment cancelled."
#   exit 0
# fi

# Apply the configuration
echo ""
echo "Applying Terraform configuration..."
terraform apply -auto-approve \
  -var="gcp_project_id=$PROJECT_ID" \
  -var="gcp_region=$REGION" \
  -var="db_user=$DB_USER" \
  -var="db_password=$DB_PASSWORD"

echo ""
echo "===================================="
echo "Deployment complete!"
echo "===================================="
echo ""
echo "Service URLs:"
terraform output
