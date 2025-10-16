#!/bin/bash

# Set locale for consistent number formatting
export LC_NUMERIC=C

# Configuration - accept number of requests from CLI parameter
NUM_REQUESTS=${1:-3}  # Default to 3 requests if no parameter provided

# Validate input
if ! [[ "$NUM_REQUESTS" =~ ^[0-9]+$ ]] || [ "$NUM_REQUESTS" -lt 1 ]; then
  echo "Error: Number of requests must be a positive integer"
  echo "Usage: $0 [number_of_requests]"
  echo "Example: $0 5"
  exit 1
fi

echo "Configuration: Running $NUM_REQUESTS requests per service"
echo ""

# Get URLs from terraform outputs
cd terraform 2>/dev/null || { echo "Error: terraform directory not found. Run from project root."; exit 1; }

echo "Fetching service URLs from terraform..."
JVM_DIRECT_URL=$(terraform output -raw jvm_cloud_sql_url 2>/dev/null)
NATIVE_DIRECT_URL=$(terraform output -raw native_cloud_sql_url 2>/dev/null)
JVM_PGBOUNCER_URL=$(terraform output -raw jvm_cloud_sql_pgbouncer_url 2>/dev/null)
NATIVE_PGBOUNCER_URL=$(terraform output -raw native_cloud_sql_pgbouncer_url 2>/dev/null)

# Validate URLs
if [[ -z "$JVM_DIRECT_URL" || -z "$NATIVE_DIRECT_URL" || -z "$JVM_PGBOUNCER_URL" || -z "$NATIVE_PGBOUNCER_URL" ]]; then
  echo "Error: Could not retrieve service URLs from terraform. Make sure services are deployed."
  exit 1
fi

cd ..

services=(
  "JVM Direct:$JVM_DIRECT_URL"
  "Native Direct:$NATIVE_DIRECT_URL"
  "JVM PgBouncer:$JVM_PGBOUNCER_URL"
  "Native PgBouncer:$NATIVE_PGBOUNCER_URL"
)

# Arrays to store results for summary
declare -A results
declare -A totals
declare -A averages

echo "=========================================="
echo "Warm Container Performance Test"
echo "Testing $NUM_REQUESTS consecutive requests per service"
echo "Cold start (1st request) excluded from warm average"
echo "=========================================="

for service_info in "${services[@]}"; do
  name=$(echo "$service_info" | cut -d':' -f1)
  url=$(echo "$service_info" | cut -d':' -f2-)
  
  echo "Testing $name..."
  
  total=0
  requests=()
  
  for i in $(seq 1 $NUM_REQUESTS); do
    start_time=$(date +%s.%N)
    curl -s "$url/metrics/startup" > /dev/null
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l)
    
    requests+=("$duration")
    
    # Add to total only if not the first request (exclude cold start from average)
    if [ $i -gt 1 ]; then
      total=$(echo "$total + $duration" | bc -l)
    fi
    sleep 0.5
  done
  
  # Store results for summary
  results["$name"]="${requests[*]}"
  totals["$name"]="$total"
  # Calculate average excluding first request (warm requests only)
  warm_requests_count=$((NUM_REQUESTS - 1))
  if [ $warm_requests_count -gt 0 ]; then
    averages["$name"]=$(echo "scale=3; $total / $warm_requests_count" | bc -l)
  else
    averages["$name"]="${requests[0]}"  # If only 1 request, use that value
  fi
done

echo ""
echo "=========================================="
echo "PERFORMANCE SUMMARY"
echo "=========================================="
echo ""

# Print detailed results
printf "%-18s %12s %12s\n" "Service" "Cold Start" "Warm Average"
echo "----------------------------------------------"

for service_info in "${services[@]}"; do
  name=$(echo "$service_info" | cut -d':' -f1)
  read -a req_times <<< "${results[$name]}"
  avg="${averages[$name]}"
  
  printf "%-18s %11.3fs %11.3fs\n" \
    "$name" "${req_times[0]}" "$avg"
done

echo ""
echo "=========================================="
echo "COLD START vs WARM PERFORMANCE ANALYSIS"
echo "=========================================="

# Cold start analysis (first request)
echo "🥶 COLD START PERFORMANCE (First Request):"
echo "-------------------------------------------"

fastest_cold_service=""
fastest_cold_time=999999
slowest_cold_service=""
slowest_cold_time=0

for service_info in "${services[@]}"; do
  name=$(echo "$service_info" | cut -d':' -f1)
  read -a req_times <<< "${results[$name]}"
  first_req="${req_times[0]}"
  
  printf "%-18s %7.3fs\n" "$name" "$first_req"
  
  if (( $(echo "$first_req < $fastest_cold_time" | bc -l) )); then
    fastest_cold_time="$first_req"
    fastest_cold_service="$name"
  fi
  
  if (( $(echo "$first_req > $slowest_cold_time" | bc -l) )); then
    slowest_cold_time="$first_req"
    slowest_cold_service="$name"
  fi
done

echo ""
echo "🏆 Fastest Cold Start: $fastest_cold_service (${fastest_cold_time}s)"
echo "🐌 Slowest Cold Start: $slowest_cold_service (${slowest_cold_time}s)"

echo ""
echo "🔥 WARM PERFORMANCE (Average Excluding Cold Start):"
echo "------------------------------------------------"

# Find fastest and slowest average
fastest_warm_service=""
fastest_warm_time=999999
slowest_warm_service=""
slowest_warm_time=0

for service_info in "${services[@]}"; do
  name=$(echo "$service_info" | cut -d':' -f1)
  avg="${averages[$name]}"
  
  printf "%-18s %7.3fs\n" "$name" "$avg"
  
  if (( $(echo "$avg < $fastest_warm_time" | bc -l) )); then
    fastest_warm_time="$avg"
    fastest_warm_service="$name"
  fi
  
  if (( $(echo "$avg > $slowest_warm_time" | bc -l) )); then
    slowest_warm_time="$avg"
    slowest_warm_service="$name"
  fi
done

echo ""
echo "🏆 Fastest Warm Average: $fastest_warm_service (${fastest_warm_time}s)"
echo "🐌 Slowest Warm Average: $slowest_warm_service (${slowest_warm_time}s)"
echo ""
echo "=========================================="
echo "PERFORMANCE COMPARISONS"
echo "=========================================="

# Get first request times for cold start comparison
jvm_direct_cold=$(echo "${results['JVM Direct']}" | cut -d' ' -f1)
native_direct_cold=$(echo "${results['Native Direct']}" | cut -d' ' -f1)
jvm_pgbouncer_cold=$(echo "${results['JVM PgBouncer']}" | cut -d' ' -f1)
native_pgbouncer_cold=$(echo "${results['Native PgBouncer']}" | cut -d' ' -f1)

# Get average times for warm performance comparison
jvm_direct_avg="${averages['JVM Direct']}"
native_direct_avg="${averages['Native Direct']}"
jvm_pgbouncer_avg="${averages['JVM PgBouncer']}"
native_pgbouncer_avg="${averages['Native PgBouncer']}"

echo "📊 COLD START COMPARISONS (First Request):"
echo "--------------------------------------------"

if [[ -n "$jvm_direct_cold" && -n "$native_direct_cold" ]]; then
  cold_native_improvement=$(LC_NUMERIC=C echo "scale=4; ($jvm_direct_cold - $native_direct_cold) / $jvm_direct_cold * 100" | bc -l)
  echo "   Native vs JVM (Direct): $(printf "%.2f" "$cold_native_improvement")% improvement"
fi

if [[ -n "$jvm_pgbouncer_cold" && -n "$native_pgbouncer_cold" ]]; then
  cold_pgbouncer_improvement=$(LC_NUMERIC=C echo "scale=4; ($jvm_pgbouncer_cold - $native_pgbouncer_cold) / $jvm_pgbouncer_cold * 100" | bc -l)
  echo "   Native vs JVM (PgBouncer): $(printf "%.2f" "$cold_pgbouncer_improvement")% improvement"
fi

echo ""
echo "📊 WARM PERFORMANCE COMPARISONS (Average):"
echo "--------------------------------------------"

if [[ -n "$jvm_direct_avg" && -n "$native_direct_avg" ]]; then
  warm_native_improvement=$(LC_NUMERIC=C echo "scale=4; ($jvm_direct_avg - $native_direct_avg) / $jvm_direct_avg * 100" | bc -l)
  echo "   Native vs JVM (Direct): $(printf "%.2f" "$warm_native_improvement")% improvement"
fi

if [[ -n "$jvm_pgbouncer_avg" && -n "$native_pgbouncer_avg" ]]; then
  warm_pgbouncer_improvement=$(LC_NUMERIC=C echo "scale=4; ($jvm_pgbouncer_avg - $native_pgbouncer_avg) / $jvm_pgbouncer_avg * 100" | bc -l)
  echo "   Native vs JVM (PgBouncer): $(printf "%.2f" "$warm_pgbouncer_improvement")% improvement"
fi

if [[ -n "$jvm_direct_avg" && -n "$jvm_pgbouncer_avg" ]]; then
  jvm_pgbouncer_improvement=$(LC_NUMERIC=C echo "scale=4; ($jvm_direct_avg - $jvm_pgbouncer_avg) / $jvm_direct_avg * 100" | bc -l)
  echo "   PgBouncer vs Direct (JVM): $(printf "%.2f" "$jvm_pgbouncer_improvement")% improvement"
fi

if [[ -n "$native_direct_avg" && -n "$native_pgbouncer_avg" ]]; then
  native_pgbouncer_improvement=$(LC_NUMERIC=C echo "scale=4; ($native_direct_avg - $native_pgbouncer_avg) / $native_direct_avg * 100" | bc -l)
  echo "   PgBouncer vs Direct (Native): $(printf "%.2f" "$native_pgbouncer_improvement")% improvement"
fi

echo ""
echo "=========================================="
echo "Test Complete!"