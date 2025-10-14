#!/bin/bash

set -e

# Cloud Run Service Comparison Script
# Collects metrics from all 4 service configurations and displays them in a table
# Architecture: JVM/Native × Direct/PgBouncer (Cloud SQL Connector only)

echo "========================================"
echo "Cloud Run Service Performance Comparison"
echo "========================================"
echo ""

# Check if we're in the correct directory
if [ -f "terraform/terraform.tfstate" ]; then
  cd terraform
elif [ ! -f "terraform.tfstate" ]; then
  echo "Error: Run this script from the project root or terraform directory"
  echo "Make sure services are deployed first"
  exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Install with: sudo apt-get install jq"
  exit 1
fi

# Array of all services (Cloud SQL Connector only)
declare -a services=(
  "jvm_cloud_sql"
  "jvm_cloud_sql_pgbouncer"
  "native_cloud_sql"
  "native_cloud_sql_pgbouncer"
)

# Store metrics for table display
declare -A startup_times
declare -A memory_usage
declare -A image_types
declare -A pool_types
declare -A profiles

echo "Collecting metrics from all services..."
echo ""

# Collect metrics from each service
for service in "${services[@]}"; do
  # Get the service URL from terraform output
  URL=$(terraform output -raw ${service}_url 2>/dev/null)
  
  if [ -z "$URL" ]; then
    echo "⚠️  Skipping $service (not found in terraform outputs)"
    continue
  fi
  
  echo "Fetching metrics from: $service"
  
  # Fetch metrics with timeout
  METRICS=$(curl -s --max-time 10 "$URL/metrics" 2>/dev/null || echo "{}")
  
  if [ "$METRICS" = "{}" ]; then
    echo "  ❌ Failed to fetch metrics"
    startup_times[$service]="N/A"
    memory_usage[$service]="N/A"
    image_types[$service]="N/A"
    pool_types[$service]="N/A"
    profiles[$service]="N/A"
  else
    # Parse JSON with jq
    startup_times[$service]=$(echo "$METRICS" | jq -r '.startupTimeSeconds // "N/A"')
    memory_usage[$service]=$(echo "$METRICS" | jq -r '.memory.usedMB // "N/A"')
    image_types[$service]=$(echo "$METRICS" | jq -r '.imageType // "N/A"')
    pool_types[$service]=$(echo "$METRICS" | jq -r '.connectionPool // "N/A"')
    profiles[$service]=$(echo "$METRICS" | jq -r '.profile // "N/A"')
    echo "  ✅ Success"
  fi
  echo ""
done

echo ""
echo "========================================"
echo "Results Table"
echo "========================================"
echo ""

# Print table header
printf "%-30s | %-15s | %-20s | %-12s | %-15s | %-15s\n" \
  "Service" "Image Type" "Connection Pool" "Profile" "Startup (s)" "Memory (MB)"
printf "%-30s-+-%-15s-+-%-20s-+-%-12s-+-%-15s-+-%-15s\n" \
  "------------------------------" "---------------" "--------------------" "------------" "---------------" "---------------"

# Print table rows
for service in "${services[@]}"; do
  if [ -n "${startup_times[$service]}" ]; then
    # Format service name for display
    display_name=$(echo "$service" | tr '_' '-')
    
    printf "%-30s | %-15s | %-20s | %-12s | %-15s | %-15s\n" \
      "$display_name" \
      "${image_types[$service]}" \
      "${pool_types[$service]}" \
      "${profiles[$service]}" \
      "${startup_times[$service]}" \
      "${memory_usage[$service]}"
  fi
done

echo ""
echo "========================================"
echo "Summary"
echo "========================================"
echo ""

# Calculate averages (excluding N/A values)
jvm_total=0
jvm_count=0
native_total=0
native_count=0

for service in "${services[@]}"; do
  startup=${startup_times[$service]}
  if [ "$startup" != "N/A" ] && [ -n "$startup" ]; then
    if [[ $service == jvm_* ]]; then
      jvm_total=$(echo "$jvm_total + $startup" | bc)
      ((jvm_count++))
    else
      native_total=$(echo "$native_total + $startup" | bc)
      ((native_count++))
    fi
  fi
done

if [ $jvm_count -gt 0 ]; then
  jvm_avg=$(echo "scale=3; $jvm_total / $jvm_count" | bc)
  echo "Average JVM Startup Time:    ${jvm_avg}s"
fi

if [ $native_count -gt 0 ]; then
  native_avg=$(echo "scale=3; $native_total / $native_count" | bc)
  echo "Average Native Startup Time: ${native_avg}s"
fi

if [ $jvm_count -gt 0 ] && [ $native_count -gt 0 ]; then
  speedup=$(echo "scale=2; $jvm_avg / $native_avg" | bc)
  echo ""
  echo "Native is ${speedup}x faster than JVM on average"
fi

echo ""
echo "Note: These are application startup times, not cold start times."
echo "For cold start metrics, use: time curl https://<service-url>/messages"
echo ""
