#!/bin/bash

set -e

# Quarkus Jib Build Script
# Builds and pushes both JVM and Native images using Jib (no Docker daemon required)

if [ -z "$1" ]; then
  echo "Usage: $0 <project-id> [region]"
  echo "Example: $0 cloud-run-demo-475108 asia-southeast1"
  exit 1
fi

PROJECT_ID=$1
REGION=${2:-asia-southeast1}

echo "===================================="
echo "Building Quarkus Images with Jib"
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo "===================================="

# Configure gcloud for Artifact Registry authentication
echo "Configuring gcloud for Artifact Registry..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev

# Create Artifact Registry repository if it doesn't exist
echo "Creating Artifact Registry repository..."
gcloud artifacts repositories create cloud-run-demo \
  --repository-format=docker \
  --location=$REGION \
  --project=$PROJECT_ID \
  --description="Cloud Run demo images" 2>/dev/null || echo "Repository already exists"

cd quarkus_cloud_run

# Build and push JVM image with Jib
echo ""
echo "Building and pushing JVM image with Jib..."
export GCP_PROJECT_ID=$PROJECT_ID
./mvnw clean package \
  -Dquarkus.container-image.push=true \
  -Dquarkus.container-image.name=quarkus-cloud-run-jvm \
  -Dquarkus.container-image.tag=latest \
  -DskipTests

echo ""
echo "JVM image pushed successfully!"

# Build and push Native image with Jib (Jib will handle the native build in a container)
echo ""
echo "Building and pushing Native image with Jib (this may take 5-10 minutes)..."
./mvnw clean package -Pnative \
  -Dquarkus.container-image.push=true \
  -Dquarkus.container-image.name=quarkus-cloud-run-native \
  -Dquarkus.container-image.tag=latest \
  -Dquarkus.native.container-build=true \
  -Dquarkus.native.builder-image=quay.io/quarkus/ubi-quarkus-mandrel-builder-image:jdk-21 \
  -DskipTests

echo ""
echo "Native image pushed successfully!"

cd ..

echo ""
echo "===================================="
echo "Build complete!"
echo "===================================="
echo "Images pushed to:"
echo "  - ${REGION}-docker.pkg.dev/${PROJECT_ID}/cloud-run-demo/quarkus-cloud-run-jvm:latest"
echo "  - ${REGION}-docker.pkg.dev/${PROJECT_ID}/cloud-run-demo/quarkus-cloud-run-native:latest"
