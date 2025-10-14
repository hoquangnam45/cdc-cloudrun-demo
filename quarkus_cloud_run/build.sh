#!/bin/bash

set -e

# Build the JVM Docker image
docker build -t gcr.io/$(gcloud config get-value project)/quarkus-cloud-run-jvm:latest -f Dockerfile.jvm .

# Build the native Docker image
docker build -t gcr.io/$(gcloud config get-value project)/quarkus-cloud-run-native:latest -f Dockerfile.native .
