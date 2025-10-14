# Copilot Instructions for Cloud Run Demo

## Project Overview
Cloud Run optimization demo comparing **4 service configurations**: JVM vs Native Image × Direct vs PgBouncer (Cloud SQL Connector only). Uses **two PostgreSQL Cloud SQL instances**: one standard tier (no managed pooling) and one Enterprise Plus (with PgBouncer/managed connection pooling).

## Architecture

### Service Matrix (4 Cloud Run Services)
```
Image Type × Database Instance (Cloud SQL Connector only)
Direct Connection Services (Standard tier, no managed pooling):
- jvm_cloud_sql (Cloud SQL Connector + HikariCP, pool size 5)
- native_cloud_sql (GraalVM Native + Cloud SQL Connector + HikariCP, pool size 5)

PgBouncer Services (Enterprise Plus with managed pooling):
- jvm_cloud_sql_pgbouncer (Cloud SQL Connector + PgBouncer + HikariCP, pool size 5)
- native_cloud_sql_pgbouncer (GraalVM Native + Cloud SQL Connector + PgBouncer + HikariCP, pool size 5)
```

### Key Design Decisions
- **Two Database Instances**:
  - **Standard Instance**: `db-g1-small` tier, no managed pooling (traditional approach)
  - **Pooled Instance**: `db-perf-optimized-N-2` Enterprise Plus tier with PgBouncer enabled
- **Spring Profiles**: Configuration switching via `SPRING_PROFILES_ACTIVE` env var (`cloud-sql`, `cloud-sql-pgbouncer`)
- **Port Convention**: Direct services use default port, PgBouncer services use port 6432
- **Connection Strategy**: 
  - **Cloud SQL Connector**: Google-managed connection management (via Cloud SQL Admin API)
  - **HikariCP**: Always enabled by default for JDBC connection pooling (works alongside Cloud SQL Connector)
- **Simplified Configuration**: Uses only Cloud SQL Connector (eliminates direct JDBC/HikariCP-only variants)
- **Pool Sizing Strategy**: All services use same pool size (5) for fair comparison - PgBouncer's benefit comes from connection multiplexing at database level
- **Readiness Probes**: Custom `DatabaseHealthIndicator` checks DB connectivity; startup probes prevent premature traffic

## Development Workflows

### Build Commands (from root directory)
```bash
# Build both images (Native takes 5-10 minutes)
./build.sh <project-id>

# Manually build JVM only
docker build -t gcr.io/<project-id>/hello-cloud-run-jvm:latest \
  -f hello_cloud_run/Dockerfile.jvm hello_cloud_run

# Manually build Native only
docker build -t gcr.io/<project-id>/hello-cloud-run-native:latest \
  -f hello_cloud_run/Dockerfile.native hello_cloud_run
```

### Deploy Commands
```bash
# Full deployment with Terraform
cd terraform
terraform init
terraform apply \
  -var="gcp_project_id=<project-id>" \
  -var="gcp_region=<region>" \
  -var="db_user=<db-user>" \
  -var="db_password=<db-password>"

# Alternative: Use deploy script
./deploy.sh <project-id> <db-user> <db-password> [region]
```

### Testing
```bash
# Run Maven tests from hello_cloud_run/
cd hello_cloud_run
./mvnw test

# Test readiness endpoint (replace URL)
curl https://<service-url>/actuator/health/readiness

# Compare all 4 service configurations
./compare_services.sh
```

## Critical Patterns

### Metrics Endpoint for Performance Comparison
`MetricsController.java` exposes `/metrics`, `/metrics/startup`, and `/metrics/memory` endpoints that provide:
- Application startup time (used to measure JVM vs Native performance)
- Memory usage (heap usage, total/max memory)
- Image type detection (JVM vs Native via `org.graalvm.nativeimage.imagecode` property)
- Connection pool type (Cloud SQL Connector vs HikariCP based on profile)
- JVM information (version, vendor, VM name)

Use `./compare_services.sh` to automatically collect and display metrics from all 4 services in a table format.

### Spring Profile Configuration
Each profile file (`application-*.properties`) configures:
1. **Connection**: PgBouncer profiles use port 6432, direct profiles use default port
2. **Pool Size**: HikariCP `maximum-pool-size=5` (same for all services for fair comparison)
3. **Cloud SQL Connector**: Enabled in all profiles via `spring.cloud.gcp.sql.enabled=true`
   - Cloud SQL Connector uses Google-managed connection pooling (NOT PgBouncer)
   - Handles IAM authentication, SSL/TLS, and connection management automatically
   - Connects via Cloud SQL Admin API, not through database port directly

Example: `application-cloud-sql-pgbouncer.properties` uses PgBouncer on port 6432 with `maximum-pool-size=5`

### Environment Variables in Cloud Run
All services use Cloud SQL Connector with these env vars:
- **Required**: `INSTANCE_CONNECTION_NAME` (format: `project:region:instance`), `DB_NAME`, `DB_USER`, `DB_PASS`
- **Profile Selection**: `SPRING_PROFILES_ACTIVE` determines which profile loads (`cloud-sql` or `cloud-sql-pgbouncer`)

See `terraform/cloud_run.tf` for reference configurations.

### Native Image Build Constraints
- **Dummy env vars required**: AOT processing needs valid config during build (see `Dockerfile.native`)
- **PostgreSQL driver initialization**: `--initialize-at-build-time=org.postgresql.Driver` in `pom.xml` native profile
- **No reflection needed**: Spring Boot 3.2.5+ with Spring Native handles JPA/Hibernate reflection automatically

### Terraform Configuration
All infrastructure and services are managed in a single `terraform/` directory:
1. VPC network (`terraform/networking.tf`)
2. Private service connection for Cloud SQL
3. Cloud SQL instances (standard and pooled) (`terraform/database.tf`)
4. 4 Cloud Run services (`terraform/cloud_run.tf`)

Cloud SQL Connector handles networking automatically - no VPC Access Connector needed.


## Common Tasks

### Deploying Everything
1. **Build images**: `./build.sh <project-id> asia-southeast1`
2. **Deploy with Terraform**: 
   ```bash
   cd terraform
   terraform apply \
     -var="gcp_project_id=<project-id>" \
     -var="gcp_region=asia-southeast1" \
     -var="db_user=<db-user>" \
     -var="db_password=<db-password>"
   ```
3. **Alternative**: `./deploy.sh <project-id> <db-user> <db-password> asia-southeast1`

### Adding a New Service Configuration
1. Create new profile file: `hello_cloud_run/src/main/resources/application-<profile>.properties`
2. Add Cloud Run service resource in `terraform/cloud_run.tf` (copy existing service, update name and env vars)
3. Add IAM policy resource: `google_cloud_run_v2_service_iam_member.<resource_name>`
4. Update `terraform/outputs.tf` to expose the new service URL
5. Apply changes: `cd terraform && terraform apply -var="gcp_project_id=..."`

### Modifying Connection Pool Settings
Edit the relevant `application-*.properties` file:
```properties
spring.datasource.hikari.maximum-pool-size=5  # Adjust based on instance count
spring.datasource.hikari.minimum-idle=0       # Keep 0 for serverless
spring.datasource.hikari.connection-timeout=10000
```

### Testing Startup Performance
1. Scale service to zero: `gcloud run services update <service> --min-instances=0`
2. Trigger cold start: `curl https://<service-url>/messages`
3. Check logs: `gcloud run logs read <service> --limit=50`
4. Look for startup time in logs or Cloud Run metrics

## File Reference
- **Application Entry**: `hello_cloud_run/src/main/java/com/example/hello_cloud_run/HelloCloudRunApplication.java`
- **REST API**: `MessageController.java` (CRUD on `/messages`)
- **Health Check**: `health/DatabaseHealthIndicator.java` (validates DB connectivity)
- **Metrics**: `MetricsController.java` (exposes `/metrics`, `/metrics/startup`, `/metrics/memory` for performance comparison)
- **Profiles**: `hello_cloud_run/src/main/resources/application-*.properties`
- **Infrastructure**: `terraform/*.tf` (VPC, Cloud SQL, VPC Connector, 4 Cloud Run services)
- **Comparison Script**: `compare_services.sh` (collects metrics from all 4 services and builds comparison table)
- **Deployment Scripts**: `deploy.sh`

## GCP-Specific Notes
- **Cloud SQL PgBouncer**: Requires Enterprise Plus edition, enabled in pooled instance via `connection_pool_config`
- **Two Database Instances**: Standard tier for direct connections, Enterprise Plus for PgBouncer services
- **Cloud SQL Connector**: Google-managed connection pooling via Cloud SQL Admin API (NOT PgBouncer)
  - Provides automatic IAM authentication, SSL/TLS encryption, and IP whitelisting
  - Connection pooling happens at Google's infrastructure level
  - Different from PgBouncer which is a standalone connection pooler
- **Pool Size Strategy**: All services use same pool size (5) - PgBouncer's benefit is connection multiplexing, not smaller app pools
- **Private IP Only**: Both database instances use private IP; Cloud SQL Connector services handle networking internally
- **No IAM Auth**: Using password auth for simplicity (`spring.cloud.gcp.sql.enable-iam-auth=false`)
- **Public Access**: Services exposed publicly via `google_cloud_run_v2_service_iam_member` (demo only)
