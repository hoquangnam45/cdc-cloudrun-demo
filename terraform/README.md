# Separated Terraform Deployment Guide

This directory contains the separated Terraform configurations for infrastructure and services.

## Directory Structure

```
terraform/
├── infrastructure/      # VPC, Cloud SQL, VPC Connector
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── networking.tf
│   └── database.tf
└── services/           # 8 Cloud Run services
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── cloud_run.tf
```

## Why Separate Infrastructure and Services?

**Benefits:**
1. **Independent Lifecycle**: Update services without touching infrastructure
2. **Faster Deployments**: Redeploy services in ~2-3 minutes vs 10-15 minutes for full stack
3. **Better CI/CD**: Services can be deployed by CI/CD while infrastructure remains stable
4. **Cost Optimization**: Tear down services during off-hours, keep infrastructure running
5. **Testing**: Easy to test different service configurations without recreating infrastructure

## Deployment Order

### 1. Deploy Infrastructure (One-time or rarely changed)

```bash
./deploy-infrastructure.sh <project-id> <db-user> <db-password> [region]
```

**Example:**
```bash
./deploy-infrastructure.sh my-gcp-project dbuser MySecurePass123 us-central1
```

This creates:
- VPC network
- VPC Access Connector
- Cloud SQL PostgreSQL instance with PgBouncer
- Private service connection

**Time:** ~10-12 minutes

### 2. Build Docker Images

```bash
./build.sh <project-id>
```

**Time:** ~5-10 minutes (Native image takes longer)

### 3. Deploy Services (Can be done repeatedly)

```bash
./deploy-services.sh <project-id> <db-user> <db-password> [region]
```

**Example:**
```bash
./deploy-services.sh my-gcp-project dbuser MySecurePass123 us-central1
```

This creates all 8 Cloud Run services:
- jvm-hikari, jvm-hikari-pgbouncer
- jvm-cloud-sql, jvm-cloud-sql-pgbouncer
- native-hikari, native-hikari-pgbouncer
- native-cloud-sql, native-cloud-sql-pgbouncer

**Time:** ~2-3 minutes

## Common Workflows

### Update Service Configuration

```bash
# Edit service configs in terraform/services/cloud_run.tf
cd terraform/services
terraform apply \
  -var="gcp_project_id=..." \
  -var="vpc_connector_id=..." \
  -var="db_instance_connection_name=..." \
  -var="db_private_ip=..."
```

Or use the script:
```bash
./deploy-services.sh <project-id> <db-user> <db-password>
```

### Redeploy After Code Changes

```bash
# 1. Build new images
./build.sh <project-id>

# 2. Force Cloud Run to pull new images
cd terraform/services
terraform apply -replace=google_cloud_run_v2_service.jvm_hikari -auto-approve
# Or redeploy all services
./deploy-services.sh <project-id> <db-user> <db-password>
```

### Scale Services to Zero (Save Costs)

```bash
cd terraform/services

# Edit cloud_run.tf and set min_instance_count = 0 for all services
# Then apply
terraform apply -auto-approve
```

Or use gcloud:
```bash
for service in jvm-hikari jvm-hikari-pgbouncer jvm-cloud-sql jvm-cloud-sql-pgbouncer \
               native-hikari native-hikari-pgbouncer native-cloud-sql native-cloud-sql-pgbouncer; do
  gcloud run services update hello-cloud-run-$service \
    --region=us-central1 --min-instances=0
done
```

### Destroy Services (Keep Infrastructure)

```bash
cd terraform/services
terraform destroy \
  -var="gcp_project_id=..." \
  -var="vpc_connector_id=..." \
  -var="db_instance_connection_name=..." \
  -var="db_private_ip=..."
```

### Destroy Everything

```bash
# 1. Destroy services first
cd terraform/services
terraform destroy -auto-approve

# 2. Then destroy infrastructure
cd ../infrastructure
terraform destroy -auto-approve
```

## Manual Deployment (Without Scripts)

### Infrastructure

```bash
cd terraform/infrastructure

terraform init

terraform apply \
  -var="gcp_project_id=my-project" \
  -var="gcp_region=us-central1" \
  -var="db_user=dbuser" \
  -var="db_password=securepass"

# Save outputs for services deployment
terraform output -json > ../infrastructure-outputs.json
```

### Services

```bash
cd terraform/services

# Get infrastructure outputs
VPC_CONNECTOR=$(cd ../infrastructure && terraform output -raw vpc_connector_id)
DB_CONN_NAME=$(cd ../infrastructure && terraform output -raw db_instance_connection_name)
DB_IP=$(cd ../infrastructure && terraform output -raw db_private_ip)

terraform init

terraform apply \
  -var="gcp_project_id=my-project" \
  -var="gcp_region=us-central1" \
  -var="db_user=dbuser" \
  -var="db_password=securepass" \
  -var="vpc_connector_id=$VPC_CONNECTOR" \
  -var="db_instance_connection_name=$DB_CONN_NAME" \
  -var="db_private_ip=$DB_IP"
```

## Troubleshooting

### Error: Infrastructure not deployed
```
❌ Error: Infrastructure not deployed!
Please run ./deploy-infrastructure.sh first
```

**Solution:** Deploy infrastructure before services:
```bash
./deploy-infrastructure.sh <project-id> <db-user> <db-password>
```

### Error: Variable not set
```
Error: No value for required variable
```

**Solution:** Services require infrastructure outputs. Make sure to pass all variables:
- `vpc_connector_id`
- `db_instance_connection_name`
- `db_private_ip`

### Services can't connect to database

**Solution:** Verify infrastructure is properly deployed:
```bash
cd terraform/infrastructure
terraform output
```

Check that:
- VPC connector exists
- Cloud SQL instance is running
- Private IP is assigned

## Advanced: Using Terraform Workspaces

Manage multiple environments (dev, staging, prod):

```bash
# Infrastructure
cd terraform/infrastructure
terraform workspace new dev
terraform workspace new prod

terraform workspace select dev
terraform apply -var-file=dev.tfvars

# Services
cd terraform/services
terraform workspace new dev
terraform workspace select dev
terraform apply -var-file=dev.tfvars
```

## Migration from Single Terraform Directory

If you have an existing deployment in the old `terraform/` directory:

1. **Export existing state**:
   ```bash
   cd terraform
   terraform state pull > old-state.json
   ```

2. **Import infrastructure resources**:
   ```bash
   cd infrastructure
   terraform import google_compute_network.vpc projects/PROJECT/global/networks/vpc-name
   # ... import other resources
   ```

3. **Import service resources**:
   ```bash
   cd ../services
   terraform import google_cloud_run_v2_service.jvm_hikari projects/PROJECT/locations/REGION/services/hello-cloud-run-jvm-hikari
   # ... import other services
   ```

Or simply destroy the old deployment and redeploy with the new structure.
