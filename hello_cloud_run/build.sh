#!/bin/bash

set -e

# Build the Spring Boot application
./mvnw clean package

# Build the JVM Docker image
docker build -t gcr.io/$(gcloud config get-value project)/hello-cloud-run-jvm:latest -f Dockerfile.jvm .

# Build the native Docker image
./mvnw spring-boot:build-image -Pnative
