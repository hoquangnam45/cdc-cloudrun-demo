#!/bin/bash

# Scale All Cloud Run Services
# Usage: ./scale_all_services.sh <scaling_value>
# Examples:
#   ./scale_all_services.sh 0        # Scale all to exactly 0 instances (manual scaling, force cold starts)
#   ./scale_all_services.sh 1        # Scale all to exactly 1 instance (manual scaling, keep warm)
#   ./scale_all_services.sh 3        # Scale all to exactly 3 instances (manual scaling)
#   ./scale_all_services.sh 1-5      # Scale all between 1-5 instances (autoscaling)
#   ./scale_all_services.sh 0-100    # Restore normal scaling (autoscaling, 0 min, 100 max)

# Set locale for consistent output
export LC_NUMERIC=C

# Parse scaling parameter
SCALING_VALUE=${1}

# Validate parameters
if [[ -z "$SCALING_VALUE" ]]; then
  echo "Error: Missing scaling value"
  echo ""
  echo "Usage: $0 <scaling_value>"
  echo ""
  echo "Scaling values:"
  echo "  0        # Manual scaling: exactly 0 instances (force cold start)"
  echo "  1        # Manual scaling: exactly 1 instance (keep warm)"
  echo "  3        # Manual scaling: exactly 3 instances"
  echo "  1-5      # Autoscaling: between 1-5 instances"
  echo "  0-100    # Autoscaling: normal auto-scaling (0 min, 100 max)"
  echo ""
  echo "Examples:"
  echo "  $0 0       # Force cold starts for all services (manual scaling)"
  echo "  $0 1       # Keep all services warm with 1 instance (manual scaling)"
  echo "  $0 2       # Run all services with exactly 2 instances (manual scaling)"
  echo "  $0 0-100   # Restore normal autoscaling"
  exit 1
fi

# Validate scaling parameter format
if [[ ! "$SCALING_VALUE" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
  echo "Error: Invalid scaling value '$SCALING_VALUE'"
  echo "Must be a number or range (e.g., 0, 1, 1-5, 0-100)"
  exit 1
fi

# Get project and region from terraform outputs
cd terraform 2>/dev/null || { echo "Error: terraform directory not found. Run from project root."; exit 1; }

PROJECT_ID=$(terraform output -raw gcp_project_id 2>/dev/null)
REGION=$(terraform output -raw gcp_region 2>/dev/null)

# Fallback to environment variables or gcloud config if terraform outputs unavailable
if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID=${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}
fi

if [[ -z "$REGION" ]]; then
  REGION=${GCP_REGION:-"asia-southeast1"}
fi

if [[ -z "$PROJECT_ID" ]]; then
  echo "Error: Could not determine project ID"
  echo "Set GCP_PROJECT_ID environment variable or configure gcloud:"
  echo "  export GCP_PROJECT_ID=your-project-id"
  echo "  or: gcloud config set project your-project-id"
  exit 1
fi

cd .. # Return to project root

# Service names (based on terraform configuration)
SERVICES=(
  "hello-cloud-run-jvm-cloud-sql"
  "native-hello-cloud-run-cloud-sql" 
  "hello-cloud-run-jvm-cloud-sql-pgbouncer"
  "native-hello-cloud-run-cloud-sql-pgbouncer"
)

SERVICE_DISPLAY_NAMES=(
  "JVM Direct"
  "Native Direct"
  "JVM PgBouncer" 
  "Native PgBouncer"
)

echo "=========================================="
echo "Scale All Cloud Run Services"
echo "=========================================="
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo "Scaling: $SCALING_VALUE"
echo "Services: ${#SERVICES[@]} total"
echo "=========================================="

# Function to update service scaling
update_service_scaling() {
  local service_name=$1
  local display_name=$2
  local scaling_value=$3

  echo "[$display_name] Updating scaling to: $scaling_value"

  # Parse scaling value and use --scaling flag or min/max instances flags
  if [[ "$scaling_value" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    # Range format: e.g., "1-5" or "0-100" - use min/max instances flags
    min_instances="${BASH_REMATCH[1]}"
    max_instances="${BASH_REMATCH[2]}"

    # Update service scaling using min/max instances flags for range and switch to auto mode
    gcloud beta run services update "$service_name" \
      --scaling=auto \
      --min-instances="$min_instances" \
      --max-instances="$max_instances" \
      --project="$PROJECT_ID" \
      --region="$REGION" \
      --quiet 2>/dev/null
  else
    # Single number format: e.g., "0" or "1" - use --scaling flag for manual scaling
    # The --scaling flag sets both min and max to the same value (manual scaling mode)

    # Update service scaling using --scaling flag for exact instance count
    gcloud beta run services update "$service_name" \
      --scaling="$scaling_value" \
      --project="$PROJECT_ID" \
      --region="$REGION" \
      --quiet 2>/dev/null
  fi

  if [ $? -eq 0 ]; then
    echo "✅ [$display_name] Successfully updated"
  else
    echo "❌ [$display_name] Failed to update"
    return 1
  fi
}

echo ""
echo "Updating scaling for all services..."
echo "------------------------------------"

# Track success/failure
success_count=0
total_count=${#SERVICES[@]}

# Update scaling for all services
for i in "${!SERVICES[@]}"; do
  service="${SERVICES[$i]}"
  display_name="${SERVICE_DISPLAY_NAMES[$i]}"
  
  if update_service_scaling "$service" "$display_name" "$SCALING_VALUE"; then
    ((success_count++))
  fi
  
  # Brief pause between operations
  sleep 1
done

echo ""
echo "Verifying scaling configuration..."
echo "----------------------------------"

# Display current scaling for each service
for i in "${!SERVICES[@]}"; do
  service="${SERVICES[$i]}"
  display_name="${SERVICE_DISPLAY_NAMES[$i]}"

  echo "[$display_name]:"

  # Get current scaling configuration including mode and manual instance count
  scaling_info=$(gcloud run services describe "$service" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --format="value(metadata.annotations['run.googleapis.com/scalingMode'],metadata.annotations['run.googleapis.com/manualInstanceCount'],spec.template.metadata.annotations['autoscaling.knative.dev/minScale'],spec.template.metadata.annotations['autoscaling.knative.dev/maxScale'])" 2>/dev/null)

  if [[ -n "$scaling_info" ]]; then
    scaling_mode=$(echo "$scaling_info" | cut -f1)
    manual_count=$(echo "$scaling_info" | cut -f2)
    min_scale=$(echo "$scaling_info" | cut -f3)
    max_scale=$(echo "$scaling_info" | cut -f4)

    # Handle empty values
    scaling_mode=${scaling_mode:-"automatic"}
    min_scale=${min_scale:-"0"}
    max_scale=${max_scale:-"100"}

    echo "  Mode: $scaling_mode"
    if [[ "$scaling_mode" == "manual" && -n "$manual_count" ]]; then
      echo "  Manual Instance Count: $manual_count"
    fi
    echo "  Min Scale: $min_scale"
    echo "  Max Scale: $max_scale"
  else
    echo "  ❌ Could not retrieve scaling info"
  fi
  echo ""
done

echo ""
echo "=========================================="
echo "Scaling Update Summary"
echo "=========================================="
echo "✅ Successfully updated: $success_count/$total_count services"
echo "🎯 Target scaling: $SCALING_VALUE"

if [[ "$SCALING_VALUE" == "0" ]]; then
  echo "❄️  All services scaled to 0 - next requests will be cold starts"
  echo ""
  echo "To test cold start performance across all services:"
  echo "  ./test_warm_performance.sh 3"
  echo ""
  echo "To restore normal scaling:"
  echo "  $0 0-100"
elif [[ "$SCALING_VALUE" =~ ^[1-9] ]]; then
  echo "🔥 Services scaled up - instances should be warm"
  echo ""
  echo "To test warm performance:"
  echo "  ./test_warm_performance.sh 5"
  echo ""
  echo "To force cold starts:"
  echo "  $0 0"
fi

echo ""
echo "Other scaling options:"
echo "  $0 1        # Manual scaling: exactly 1 warm instance per service"
echo "  $0 3        # Manual scaling: exactly 3 instances per service"
echo "  $0 2-10     # Autoscaling: 2-10 instances per service"
echo "  $0 0-100    # Autoscaling: normal auto-scaling"

if [ $success_count -lt $total_count ]; then
  echo ""
  echo "⚠️  Some services failed to update. Check gcloud permissions and service status."
  exit 1
fi