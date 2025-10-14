# Hello Cloud Run Demo

A comprehensive demonstration project showcasing Cloud Run optimization techniques using Spring Boot. This project compares:

- **JVM vs Native Image**: Traditional JVM vs GraalVM Native Image
- **Database-Level Pooling**: Direct connections vs PgBouncer (Enterprise Plus)
- **Cloud SQL Connector**: Google-managed connection management with HikariCP pooling
- **Startup Probes**: Impact of proper readiness checks on cold starts

The demo uses **two Cloud SQL instances**: standard tier (no managed pooling) and Enterprise Plus (with PgBouncer).

## Architecture

The project deploys **4 Cloud Run services** with different configurations across **two Cloud SQL instances**:

**Direct Connection Services** (Standard tier: `db-g1-small`, no managed pooling):
1. **JVM + Cloud SQL Connector**: Traditional JVM with Google-managed connection pooling (HikariCP for pool management)
2. **Native + Cloud SQL Connector**: GraalVM Native Image with Cloud SQL Connector (HikariCP for pool management)

**PgBouncer Services** (Enterprise Plus: `db-perf-optimized-N-2`, managed pooling enabled):
3. **JVM + Cloud SQL Connector + PgBouncer**: JVM with Cloud SQL Connector via PgBouncer (port 6432)
4. **Native + Cloud SQL Connector + PgBouncer**: Native Image with Cloud SQL Connector via PgBouncer (port 6432)

**Key Architectural Points**:
- **Two Database Instances**: Separate standard and Enterprise Plus instances for true comparison
- **PgBouncer**: Enabled via `connection_pool_config` on Enterprise Plus instance (port 6432)
- **Cloud SQL Connector**: Google-managed connection handling via Cloud SQL Admin API
- **HikariCP**: Always enabled by default for JDBC connection pooling (works alongside Cloud SQL Connector)
- **Simplified Configuration**: Uses only Cloud SQL Connector (eliminates direct JDBC variants)

All services include:
- REST API with CRUD operations on a `Message` entity
- Custom readiness endpoint (`/actuator/health/readiness`)
- Startup probes configured for optimal cold start behavior
- No VPC Access Connector needed (Cloud SQL Connector handles networking)

## Prerequisites

### Required Tools
- **Java 17+**: For building the application
- **Docker**: For building container images
- **gcloud CLI**: For GCP authentication and API management
- **Terraform**: For infrastructure provisioning (v1.0+)

### GCP Requirements
- Active GCP project with billing enabled
- Sufficient IAM permissions:
  - Cloud Run Admin
  - Cloud SQL Admin
  - Compute Network Admin
  - Service Account User

## Development Environment Setup

This project requires GraalVM for building native images. A setup script is provided to automate the installation.

### Automated GraalVM Setup

1.  **Run the setup script**:
    ```bash
    ./setup_graalvm.sh
    ```
    This script will:
    - Download and extract GraalVM for Java 17.
    - Set the `JAVA_HOME` and `PATH` environment variables in your `~/.bashrc` file.
    - Install the `native-image` component.

2.  **Update your shell environment**:
    After the script finishes, run the following command to apply the changes to your current terminal session:
    ```bash
    source ~/.bashrc
    ```

    Alternatively, you can open a new terminal.

## Quick Start

### 1. Authenticate with GCP

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

### 2. Enable Required APIs

```bash
gcloud services enable \
  run.googleapis.com \
  sqladmin.googleapis.com \
  vpcaccess.googleapis.com \
  servicenetworking.googleapis.com \
  compute.googleapis.com
```

### 3. Build Docker Images

Build both JVM and Native images (Native image build takes 5-10 minutes):

```bash
./build.sh YOUR_PROJECT_ID
```

This script:
- Configures Docker for Artifact Registry (or GCR)
- Builds the JVM image with multi-stage Docker build
- Builds the Native image with GraalVM Native Image
- Pushes both images to Artifact Registry or GCR

### 4. Deploy with Terraform

Deploy everything (infrastructure + services) with Terraform:

```bash
cd terraform
terraform init
terraform apply \
  -var="gcp_project_id=YOUR_PROJECT_ID" \
  -var="gcp_region=asia-southeast1" \
  -var="db_user=dbadmin" \
  -var="db_password=YOUR_SECURE_PASSWORD"
```

This provisions:
- VPC network with private service connection
- VPC Access Connector for Cloud Run
- Cloud SQL PostgreSQL instance (standard tier, private IP)
- 8 Cloud Run services with startup probes
- IAM bindings for public access (demo only)

⏱️ **Complete deployment takes approximately 10-15 minutes**

**Alternative: Use the deploy script**

```bash
./deploy.sh YOUR_PROJECT_ID dbuser securepassword asia-southeast1
```

## Project Structure

```
cloud_run_demo/
├── hello_cloud_run/              # Spring Boot application
│   ├── src/
│   │   ├── main/
│   │   │   ├── java/
│   │   │   │   └── com/example/hello_cloud_run/
│   │   │   │       ├── HelloCloudRunApplication.java
│   │   │   │       ├── Message.java              # JPA Entity
│   │   │   │       ├── MessageRepository.java    # Spring Data JPA
│   │   │   │       ├── MessageController.java    # REST Controller
│   │   │   │       ├── MetricsController.java    # Performance metrics
│   │   │   │       └── health/
│   │   │   │           └── DatabaseHealthIndicator.java
│   │   │   └── resources/
│   │   │       ├── application.properties
│   │   │       ├── application-hikari.properties
│   │   │       ├── application-hikari-pgbouncer.properties
│   │   │       ├── application-cloud-sql.properties
│   │   │       └── application-cloud-sql-pgbouncer.properties
│   │   └── test/
│   ├── Dockerfile.jvm            # Multi-stage JVM build
│   ├── Dockerfile.native         # Multi-stage Native build
│   ├── pom.xml                   # Maven config with GraalVM Native
│   └── mvnw                      # Maven Wrapper
├── terraform/
│   ├── main.tf                   # Provider configuration
│   ├── variables.tf              # Input variables
│   ├── outputs.tf                # Output values (8 service URLs)
│   ├── database.tf               # Cloud SQL configuration
│   ├── networking.tf             # VPC and VPC Connector
│   └── cloud_run.tf              # 8 Cloud Run services
├── build.sh                      # Docker image build script
├── deploy.sh                     # Terraform deployment script
├── compare_services.sh           # Performance comparison script
└── README.md                     # This file
```

## API Endpoints

All services expose the same REST API:

### Message CRUD Operations

```bash
# Create a message
curl -X POST https://SERVICE_URL/messages \
  -H "Content-Type: application/json" \
  -d '{"content":"Hello Cloud Run!"}'

# Get all messages
curl https://SERVICE_URL/messages

# Get message by ID
curl https://SERVICE_URL/messages/1

# Update a message
curl -X PUT https://SERVICE_URL/messages/1 \
  -H "Content-Type: application/json" \
  -d '{"content":"Updated message"}'

# Delete a message
curl -X DELETE https://SERVICE_URL/messages/1
```

### Health Endpoints

```bash
# Readiness probe (checks database connectivity)
curl https://SERVICE_URL/actuator/health/readiness

# Liveness probe
curl https://SERVICE_URL/actuator/health/liveness

# General health
curl https://SERVICE_URL/actuator/health
```

### Metrics Endpoints (Perfect for Demo!)

```bash
# Get all metrics including startup time, memory usage, and image type
curl https://SERVICE_URL/metrics | jq

# Get just startup metrics
curl https://SERVICE_URL/metrics/startup | jq

# Get just memory metrics
curl https://SERVICE_URL/metrics/memory | jq
```

**Example Response:**
```json
{
  "application": "hello-cloud-run",
  "profile": "hikari",
  "imageType": "Native (GraalVM)",
  "connectionPool": "HikariCP",
  "startupTimeMs": 87,
  "startupTimeSeconds": "0.087",
  "uptimeMs": 45230,
  "uptimeSeconds": "45.230",
  "memory": {
    "usedMB": "42.35",
    "totalMB": "128.00",
    "maxMB": "256.00",
    "freeMB": "85.65",
    "usagePercent": "16.5%"
  },
  "jvm": {
    "version": "17.0.8",
    "vendor": "GraalVM Community",
    "name": "Substrate VM"
  },
  "timestamp": "2025-10-14T10:30:45.123Z"
}
```

## Testing Readiness Endpoints

The custom `DatabaseHealthIndicator` checks database connectivity:

```bash
# Healthy response (database connected)
$ curl https://SERVICE_URL/actuator/health/readiness
{"status":"UP"}

# Unhealthy response (database unreachable)
{"status":"DOWN"}
```

This demonstrates:
- Spring Boot Actuator health checks
- Database connectivity validation
- Cloud Run startup probe integration

## Terraform Infrastructure

### Networking
- **VPC Network**: Private network for Cloud SQL
- **VPC Connector**: Connects Cloud Run to VPC (10.8.0.0/28)
- **Service Networking**: Private service connection for Cloud SQL
- **Firewall Rules**: Automatic with VPC connector

### Cloud SQL
- **Instance Type**: db-f1-micro (demo purposes)
- **Database**: PostgreSQL 15
- **Networking**: Private IP only (no public IP)
- **Backups**: Disabled for demo (enable for production)

### Cloud Run
- **Concurrency**: Default (80 requests/container)
- **Min Instances**: 0 (scales to zero)
- **Max Instances**: Unlimited
- **Memory**:  512Mi (JVM), 256Mi (Native)
- **CPU**: 1000m (1 vCPU)

## Performance Comparison

### Automated Comparison Script

Use the provided script to compare all 8 service configurations side-by-side:

```bash
# Compare all 8 services and display results in a table
./compare_services.sh
```

The script collects metrics from:
- **4 Direct Connection Services**: Using port 5432, larger connection pools
- **4 PgBouncer Services**: Using port 6432, smaller connection pools (PgBouncer handles pooling)

**Example Output:**
```
Service                        | Image Type      | Connection Pool      | Profile      | Startup (s)     | Memory (MB)
----------------------------------------------------------------------------------------------
jvm-hikari                     | JVM             | HikariCP             | hikari       | 5.234           | 425.50
jvm-hikari-pgbouncer           | JVM             | HikariCP             | hikari-pg... | 5.187           | 420.25
jvm-cloud-sql                  | JVM             | Cloud SQL Connector  | cloud-sql    | 5.456           | 438.75
jvm-cloud-sql-pgbouncer        | JVM             | Cloud SQL Connector  | cloud-sql... | 5.398           | 432.10
native-hikari                  | Native (GraalVM)| HikariCP             | hikari       | 0.087           | 145.30
native-hikari-pgbouncer        | Native (GraalVM)| HikariCP             | hikari-pg... | 0.082           | 142.15
native-cloud-sql               | Native (GraalVM)| Cloud SQL Connector  | cloud-sql    | 0.095           | 158.20
native-cloud-sql-pgbouncer     | Native (GraalVM)| Cloud SQL Connector  | cloud-sql... | 0.091           | 155.45
```

### Expected Results

| Configuration | Cold Start | Memory Usage | Startup Time | Pool Size | Port |
|---------------|------------|--------------|--------------|-----------|------|
| **JVM + HikariCP (Direct)** | ~8-12s | ~400-500MB | ~5-8s | 5 | 5432 |
| **JVM + HikariCP (PgBouncer)** | ~8-12s | ~400-500MB | ~5-8s | 2 | 6432 |
| **JVM + Cloud SQL (Direct)** | ~8-12s | ~400-500MB | ~5-8s | 5 | Auto |
| **JVM + Cloud SQL (PgBouncer)** | ~8-12s | ~400-500MB | ~5-8s | 2 | Auto |
| **Native + HikariCP (Direct)** | ~1-3s | ~150-250MB | <0.1s | 5 | 5432 |
| **Native + HikariCP (PgBouncer)** | ~1-3s | ~150-250MB | <0.1s | 2 | 6432 |
| **Native + Cloud SQL (Direct)** | ~1-3s | ~150-250MB | <0.1s | 5 | Auto |
| **Native + Cloud SQL (PgBouncer)** | ~1-3s | ~150-250MB | <0.1s | 2 | Auto |

### Observing Cold Starts

1. **Get Service URLs**:
   ```bash
   cd terraform
   terraform output
   ```

2. **Force a cold start** (scale to zero):
   ```bash
   gcloud run services update SERVICE_NAME \
     --region=us-central1 \
     --min-instances=0
   ```

3. **Measure cold start**:
   ```bash
   time curl https://SERVICE_URL/messages
   ```

4. **Compare startup probe behavior**:
   - JVM services: `initial_delay=10s, period=5s`
   - Native services: `initial_delay=1s, period=1s`

### Key Observations

1. **Native Image Benefits**:
   - Significantly faster cold starts (3-5x faster)
   - Lower memory footprint (50-60% reduction)
   - Instant startup time (<1 second)

2. **Connection Pooling**:
   - **HikariCP**: Application-managed, requires VPC connector, more control
   - **Cloud SQL Connector**: Managed by GCP, automatic IAM auth, simpler setup

3. **Startup Probes**:
   - Native images can use more aggressive probe settings
   - JVM services need longer initial delay for warm-up
   - Proper readiness checks prevent failed requests during startup

## Configuration Details

### Dockerfile Optimization

**JVM Dockerfile** (`Dockerfile.jvm`):
- Multi-stage build with Maven Wrapper
- Eclipse Temurin 17 JDK for build, JRE for runtime
- Non-root user for security
- Optimized JVM flags: `-XX:+UseContainerSupport`, `-XX:MaxRAMPercentage=75.0`

**Native Dockerfile** (`Dockerfile.native`):
- GraalVM Native Image builder
- Distroless base image for minimal attack surface
- Static linking for zero dependencies
- Small final image size (~80MB vs ~200MB for JVM)

### Spring Boot Configuration

**HikariCP Profile** (`application-hikari.properties`):
```properties
spring.datasource.url=jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}
spring.datasource.hikari.maximum-pool-size=10
spring.datasource.hikari.minimum-idle=2
```

**Cloud SQL Connector Profile** (`application-cloud-sql.properties`):
```properties
spring.cloud.gcp.sql.enabled=true
spring.cloud.gcp.sql.database-name=${DB_NAME}
spring.cloud.gcp.sql.instance-connection-name=${INSTANCE_CONNECTION_NAME}
```

### Cloud Run Startup Probes

**JVM Services**:
```yaml
startup_probe:
  http_get:
    path: /actuator/health/readiness
  initial_delay_seconds: 10
  period_seconds: 5
  failure_threshold: 3
```

**Native Services**:
```yaml
startup_probe:
  http_get:
    path: /actuator/health/readiness
  initial_delay_seconds: 1
  period_seconds: 1
  failure_threshold: 5
```

## Cleanup

To avoid incurring charges, delete all resources:

```bash
cd terraform
terraform destroy \
  -var="gcp_project_id=YOUR_PROJECT_ID" \
  -var="db_user=dbuser" \
  -var="db_password=securepassword"
```

Confirm with `yes` when prompted.

## Troubleshooting

### Build Failures

**Native Image Build Errors**:
```bash
# Ensure GraalVM is not required locally (Docker handles it)
# Check Docker has enough resources (8GB+ RAM recommended)
docker system prune -a  # Clean up Docker space
```

**Maven Dependency Issues**:
```bash
cd hello_cloud_run
./mvnw clean install -U  # Force update dependencies
```

### Deployment Issues

**VPC Connector Creation Fails**:
```bash
# Ensure APIs are enabled
gcloud services enable vpcaccess.googleapis.com compute.googleapis.com

# Check quota limits
gcloud compute project-info describe --project=YOUR_PROJECT_ID
```

**Cloud SQL Connection Errors**:
```bash
# Check service logs
gcloud run services logs read SERVICE_NAME --region=us-central1

# Verify private IP connectivity
# Ensure VPC connector is attached to Cloud Run service
```

**Cloud Run Service Won't Start**:
```bash
# Check readiness probe is passing
gcloud run services describe SERVICE_NAME --region=us-central1

# View detailed logs
gcloud logging read "resource.type=cloud_run_revision" --limit=50
```

### Permission Errors

```bash
# Grant necessary roles
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="user:YOUR_EMAIL" \
  --role="roles/run.admin"
```

## Best Practices Demonstrated

1. **Multi-Stage Docker Builds**: Minimize final image size
2. **Maven Wrapper**: Ensure consistent build environment
3. **Non-Root Containers**: Security best practice
4. **Startup Probes**: Prevent premature traffic routing
5. **VPC Networking**: Secure database connections
6. **Infrastructure as Code**: Reproducible deployments
7. **Resource Limits**: Predictable costs and performance
8. **Health Checks**: Application observability

## Further Reading

- [Cloud Run Best Practices](https://cloud.google.com/run/docs/best-practices)
- [GraalVM Native Image](https://www.graalvm.org/latest/reference-manual/native-image/)
- [Spring Boot on Cloud Run](https://spring.io/guides/gs/spring-boot-for-google-cloud-run/)
- [Cloud SQL Private IP](https://cloud.google.com/sql/docs/postgres/configure-private-ip)
- [VPC Access Connector](https://cloud.google.com/vpc/docs/configure-serverless-vpc-access)

## License

This project is for demonstration purposes only.