#!/bin/bash

set -e

if [ -z "$1" ]; then
  echo "Usage: ./build-quarkus-optimized.sh <project-id> [region]"
  echo "  region: Optional, defaults to 'asia-southeast1'"
  exit 1
fi

PROJECT_ID=$1
REGION=${2:-asia-southeast1}

echo "===================================="
echo "Building Quarkus Docker Images"
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo "===================================="

REGISTRY="$REGION-docker.pkg.dev"
REPO_PATH="$PROJECT_ID/cloud-run-demo"

echo "Configuring Docker for Artifact Registry..."
gcloud auth configure-docker $REGISTRY

echo "Creating Artifact Registry repository..."
gcloud artifacts repositories create cloud-run-demo \
  --repository-format=docker \
  --location=$REGION \
  --project=$PROJECT_ID \
  --quiet 2>/dev/null || echo "Repository already exists"

cd quarkus_cloud_run

# Build the JVM application
echo ""
echo "Building Quarkus JVM application..."
./mvnw package -DskipTests

# Build and push the JVM image
echo ""
echo "Building JVM Docker image..."
docker build -t $REGISTRY/$REPO_PATH/quarkus-cloud-run-jvm:latest \
  -f Dockerfile.jvm .

echo "Pushing JVM image..."
docker push $REGISTRY/$REPO_PATH/quarkus-cloud-run-jvm:latest

# Build the native application
echo ""
echo "Building Quarkus Native application (this may take 5-10 minutes)..."
./mvnw package -Pnative -DskipTests

# Build and push the native image
echo ""
echo "Building Native Docker image..."
docker build -t $REGISTRY/$REPO_PATH/quarkus-cloud-run-native:latest \
  -f Dockerfile.native .

echo "Pushing Native image..."
docker push $REGISTRY/$REPO_PATH/quarkus-cloud-run-native:latest

cd ..

echo ""
echo "===================================="
echo "Build complete!"
echo "===================================="
echo "Images pushed to:"
echo "  - $REGISTRY/$REPO_PATH/quarkus-cloud-run-jvm:latest"
echo "  - $REGISTRY/$REPO_PATH/quarkus-cloud-run-native:latest"
