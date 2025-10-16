#!/bin/bash

# set -e  # Temporarily disabled to debug

# Unified Cloud Run Performance Testing Script
# Combines functionality from compare_services.sh and test_warm_performance.sh
# - Collects service metrics (startup times, memory usage, configuration)
# - Tests cold start performance
# - Tests warm performance with configurable request count
# - Provides comprehensive comparison analysis

# Default configuration
DEFAULT_REQUEST_COUNT=10

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Set locale to prevent formatting issues
export LC_NUMERIC=C

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "OPTIONS:"
  echo "  -r, --requests COUNT     Number of warm requests per service (default: $DEFAULT_REQUEST_COUNT)"
  echo "  -h, --help              Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0                      # Run full test suite with defaults (10 warm requests)"
  echo "  $0 -r 5                 # Run with 5 warm requests per service"
  echo "  $0 -r 20                # Run with 20 warm requests per service"
}

# Parse command line arguments
REQUEST_COUNT=$DEFAULT_REQUEST_COUNT

while [[ $# -gt 0 ]]; do
  case $1 in
    -r|--requests)
      REQUEST_COUNT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Validate request count
if ! [[ "$REQUEST_COUNT" =~ ^[0-9]+$ ]] || [ "$REQUEST_COUNT" -le 0 ]; then
  echo "Error: Request count must be a positive integer"
  exit 1
fi

print_header() {
  local title="$1"
  local title_length=${#title}
  local total_width=88
  local padding=$(( (total_width - title_length - 4) / 2 ))
  
  echo ""
  echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║${NC}                                                                                        ${GREEN}║${NC}"
  echo -e "${GREEN}║${NC} ${YELLOW}⚡ $title${NC}$(printf "%*s" $(( total_width - title_length - 4 )) "")${GREEN}║${NC}"
  echo -e "${GREEN}║${NC}                                                                                        ${GREEN}║${NC}"
  echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

print_section() {
  local title="$1"
  local title_length=${#title}
  local total_width=82
  
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC} ${YELLOW}🚀 $title${NC}$(printf "%*s" $(( total_width - title_length - 4 )) "")${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

# Check if we're in the correct directory
if [ -f "terraform/terraform.tfstate" ]; then
  cd terraform
elif [ ! -f "terraform.tfstate" ]; then
  echo -e "${RED}Error: Run this script from the project root or terraform directory${NC}"
  echo "Make sure services are deployed first"
  exit 1
fi

# Check dependencies
if ! command -v jq &> /dev/null; then
  echo -e "${RED}Error: jq is required but not installed. Install with: sudo apt-get install jq${NC}"
  exit 1
fi

if ! command -v bc &> /dev/null; then
  echo -e "${RED}Error: bc is required but not installed. Install with: sudo apt-get install bc${NC}"
  exit 1
fi

# Array of all services (Cloud SQL Connector only)
declare -a services=(
  "jvm_cloud_sql"
  "jvm_cloud_sql_pgbouncer"
  "native_cloud_sql"
  "native_cloud_sql_pgbouncer"
)

# Storage for all metrics
declare -A service_urls
declare -A startup_times
declare -A memory_usage
declare -A image_types
declare -A pool_types
declare -A profiles
declare -A initial_response_times
declare -A warm_avg_times
declare -A warm_response_counts

# Get service URLs
print_section "Getting Service URLs"
for service in "${services[@]}"; do
  URL=$(terraform output -raw ${service}_url 2>/dev/null)
  if [ -z "$URL" ]; then
    echo -e "${YELLOW}⚠️  Skipping ${CYAN}$service${NC} ${YELLOW}(not found in terraform outputs)${NC}"
    continue
  fi
  service_urls[$service]="$URL"
  echo -e "🌐 ${CYAN}$service${NC}: $URL"
done

if [ ${#service_urls[@]} -eq 0 ]; then
  echo -e "${RED}Error: No services found in terraform outputs${NC}"
  exit 1
fi



# Function to test warm performance
test_warm_performance() {
  local service="$1"
  local url="${service_urls[$service]}"
  
  echo -e "  ${YELLOW}🔥 Testing warm performance for ${CYAN}$service${NC} ${YELLOW}($REQUEST_COUNT requests)...${NC}"
  
  # Array to store all response times for warm performance
  local response_times=()
  local successful_requests=0
  local test_failed=false
  
  for ((i=1; i<=REQUEST_COUNT; i++)); do
    start_time=$(date +%s.%N)
    # Get both response content and HTTP status code
    response=$(curl -s --max-time 30 -w "HTTPSTATUS:%{http_code}" "$url/messages" 2>/dev/null || echo "ERROR")
    end_time=$(date +%s.%N)
    
    # Extract HTTP status code and response body
    if [[ "$response" == *"HTTPSTATUS:"* ]]; then
      http_code=$(echo "$response" | sed -n 's/.*HTTPSTATUS:\([0-9]*\)$/\1/p')
      response_body=$(echo "$response" | sed 's/HTTPSTATUS:[0-9]*$//')
    else
      http_code="000"
      response_body="$response"
    fi
    
    # Stop if curl request failed or HTTP error status or contains error content
    if [ "$response_body" = "ERROR" ] || [ -z "$response_body" ] || 
       [ "$http_code" = "000" ] || [ "$http_code" -ge 400 ] ||
       [[ "$response_body" == *"Error:"* ]] || [[ "$response_body" == *"Service Unavailable"* ]]; then
      echo -e "    ${RED}❌ Request $i failed (HTTP: $http_code) - stopping warm performance test${NC}"
      test_failed=true
      # Clear all response times to ensure no partial average is calculated
      response_times=()
      break
    fi
    
    duration=$(echo "$end_time - $start_time" | bc)
    
    # Store all response times for warm performance analysis
    response_times+=("$duration")
    ((successful_requests++))
  done
  
  # Calculate warm average only if ALL requests succeeded
  if [ "$test_failed" = true ]; then
    warm_avg_times[$service]="N/A"
    warm_response_counts[$service]=0
    echo -e "    ${RED}Warm performance test failed - no average calculated${NC}"
  elif [ ${#response_times[@]} -gt 0 ]; then
    local total=0
    for time in "${response_times[@]}"; do
      total=$(echo "$total + $time" | bc)
    done
    warm_avg_times[$service]=$(echo "scale=4; $total / ${#response_times[@]}" | bc)
    warm_response_counts[$service]=${#response_times[@]}
    echo -e "    🏆 Warm average: ${warm_avg_times[$service]}s (${#response_times[@]} requests)"
  else
    warm_avg_times[$service]="N/A"
    warm_response_counts[$service]=0
    echo -e "    ${RED}No successful warm requests${NC}"
  fi
  
  echo ""
}

# Function to collect service metrics
collect_service_metrics() {
  print_section "Service Metrics Collection & Initial Response Times"
  
  for service in "${!service_urls[@]}"; do
    local url="${service_urls[$service]}"
    echo -e "🔍 ${CYAN}Testing service:${NC} ${YELLOW}$service${NC}"
    
    # Measure initial response time when fetching metrics
    start_time=$(date +%s.%N)
    METRICS=$(curl -s --max-time 60 "$url/metrics" 2>/dev/null || echo "{}")
    end_time=$(date +%s.%N)
    
    if [ "$METRICS" = "{}" ]; then
      echo -e "${RED}❌ Failed to collect metrics${NC}"
      initial_response_times[$service]="N/A"
      startup_times[$service]="N/A"
      memory_usage[$service]="N/A"
      image_types[$service]="N/A"
      pool_types[$service]="N/A"
      profiles[$service]="N/A"
    else
      # Calculate and store initial response time
      response_duration=$(echo "$end_time - $start_time" | bc)
      initial_response_times[$service]="$response_duration"
      
      # Parse and store all metrics
      app_startup_time=$(echo "$METRICS" | jq -r '.startupTimeSeconds // "N/A"')
      memory_mb=$(echo "$METRICS" | jq -r '.memory.usedMB // "N/A"')
      image_type=$(echo "$METRICS" | jq -r '.imageType // "Unknown"')
      pool_type=$(echo "$METRICS" | jq -r '.connectionPool // "N/A"')
      profile=$(echo "$METRICS" | jq -r '.profile // "N/A"')
      
      # Show detailed breakdown with reduced colors
      if [ "$app_startup_time" != "N/A" ]; then
        echo -e "🎯 Response=${response_duration}s | ⚡ App=${app_startup_time}s | 💾 Memory=${memory_mb}MB | 🏗️  Image=${image_type}"
      else
        echo -e "🎯 Response=${response_duration}s | 💾 Memory=${memory_mb}MB | 🏗️  Image=${image_type}"
      fi
      
      startup_times[$service]="$app_startup_time"
      memory_usage[$service]="$memory_mb"
      image_types[$service]="$image_type"
      pool_types[$service]="$pool_type"
      profiles[$service]="$profile"
    fi
    echo ""
  done
}

# Run service metrics collection (includes initial response time measurement)
collect_service_metrics

# Run performance tests (services should be warm now)
print_section "Warm Performance Tests"

if [ ${#service_urls[@]} -eq 0 ]; then
  echo -e "${RED}No services available for performance testing${NC}"
else
  for service in "${!service_urls[@]}"; do
    test_warm_performance "$service"
  done
fi

print_section "Performance Comparison"

echo -e "${CYAN}┌──────────────────────────────┬──────────────────┬──────────────┬──────────────┬──────────────┬──────────────┬──────────┐${NC}"
printf "${CYAN}│${NC} %-28s ${CYAN}│${NC} %-16s ${CYAN}│${NC} %-12s ${CYAN}│${NC} %-12s ${CYAN}│${NC} %-12s ${CYAN}│${NC} %-12s ${CYAN}│${NC} %-8s ${CYAN}│${NC}\n" \
  "Service" "Type" "Start (s)" "Cold (s)" "Warm (s)" "Memory (MB)" "Requests"
echo -e "${CYAN}├──────────────────────────────┼──────────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────┤${NC}"

for service in "${!service_urls[@]}"; do
  display_name=$(echo "$service" | tr '_' '-')
  app_startup="${startup_times[$service]:-N/A}"
  initial_response="${initial_response_times[$service]:-N/A}"
  warm_time="${warm_avg_times[$service]:-N/A}"
  memory="${memory_usage[$service]:-N/A}"
  req_count="${warm_response_counts[$service]:-0}"

  # Truncate long values for display
  if [[ "$app_startup" != "N/A" && ${#app_startup} -gt 9 ]]; then
    app_startup=$(printf "%.3f" $app_startup)
  fi
  if [[ "$initial_response" != "N/A" && ${#initial_response} -gt 11 ]]; then
    initial_response=$(printf "%.3f" $initial_response)
  fi
  if [[ "$warm_time" != "N/A" && ${#warm_time} -gt 11 ]]; then
    warm_time=$(printf "%.3f" $warm_time)
  fi
  if [[ "$memory" != "N/A" && ${#memory} -gt 9 ]]; then
    memory=$(printf "%.1f" $memory)
  fi

  printf "${CYAN}│${NC} %-28s ${CYAN}│${NC} %-16s ${CYAN}│${NC} %-12s ${CYAN}│${NC} %-12s ${CYAN}│${NC} %-12s ${CYAN}│${NC} %-12s ${CYAN}│${NC} %-8s ${CYAN}│${NC}\n" \
    "$display_name" \
    "${image_types[$service]:-Unknown}" \
    "$app_startup" \
    "$initial_response" \
    "$warm_time" \
    "$memory" \
    "$req_count"
done
echo -e "${CYAN}└──────────────────────────────┴──────────────────┴──────────────┴──────────────┴──────────────┴──────────────┴──────────┘${NC}"

# Summary analysis
print_section "Summary Analysis"

# Connection pool analysis
echo -e "${GREEN}🔗 Connection Pool Analysis:${NC}"

# Compare Direct vs PgBouncer for same image types
for image_type in "JVM" "Native (GraalVM)"; do
  direct_service=""
  pgbouncer_service=""
  
  for service in "${!service_urls[@]}"; do
    if [[ "${image_types[$service]:-Unknown}" == "$image_type" ]]; then
      if [[ $service == *_pgbouncer ]]; then
        pgbouncer_service=$service
      else
        direct_service=$service
      fi
    fi
  done
  
  if [ -n "$direct_service" ] && [ -n "$pgbouncer_service" ]; then
    direct_initial=${initial_response_times[$direct_service]}
    pgbouncer_initial=${initial_response_times[$pgbouncer_service]}
    
    if [ "$direct_initial" != "N/A" ] && [ "$pgbouncer_initial" != "N/A" ] && [ -n "$direct_initial" ] && [ -n "$pgbouncer_initial" ]; then
      initial_diff=$(echo "scale=4; (1 - $pgbouncer_initial / $direct_initial) * 100" | bc)
      if (( $(echo "$initial_diff > 0" | bc -l) )); then
        echo -e "  ${CYAN}$image_type${NC} ❄️  Initial Response: PgBouncer is $(printf "%.2f" $initial_diff)% faster than Direct"
      else
        initial_diff_abs=$(echo "scale=4; $initial_diff * -1" | bc)
        echo -e "  ${CYAN}$image_type${NC} ❄️  Initial Response: Direct is $(printf "%.2f" $initial_diff_abs)% faster than PgBouncer"
      fi
    fi
    
    direct_warm=${warm_avg_times[$direct_service]}
    pgbouncer_warm=${warm_avg_times[$pgbouncer_service]}
    
    if [ "$direct_warm" != "N/A" ] && [ "$pgbouncer_warm" != "N/A" ] && [ -n "$direct_warm" ] && [ -n "$pgbouncer_warm" ]; then
      warm_diff=$(echo "scale=4; (1 - $pgbouncer_warm / $direct_warm) * 100" | bc)
      if (( $(echo "$warm_diff > 0" | bc -l) )); then
        echo -e "  ${CYAN}$image_type${NC} 🔥 Warm Performance: PgBouncer is $(printf "%.2f" $warm_diff)% faster than Direct"
      else
        warm_diff_abs=$(echo "scale=4; $warm_diff * -1" | bc)
        echo -e "  ${CYAN}$image_type${NC} 🔥 Warm Performance: Direct is $(printf "%.2f" $warm_diff_abs)% faster than PgBouncer"
      fi
    fi
  fi
done

# Performance insights summary
echo ""
echo -e "${GREEN}🎯 Key Performance Insights:${NC}"

# Find fastest startup
fastest_startup_service=""
fastest_startup_time=""
for service in "${!service_urls[@]}"; do
  startup_time="${startup_times[$service]}"
  if [ "$startup_time" != "N/A" ] && [ -n "$startup_time" ]; then
    if [ -z "$fastest_startup_time" ] || (( $(echo "$startup_time < $fastest_startup_time" | bc -l) )); then
      fastest_startup_time="$startup_time"
      fastest_startup_service="$service"
    fi
  fi
done

# Find lowest memory
lowest_memory_service=""
lowest_memory=""
for service in "${!service_urls[@]}"; do
  memory="${memory_usage[$service]}"
  if [ "$memory" != "N/A" ] && [ -n "$memory" ]; then
    if [ -z "$lowest_memory" ] || (( $(echo "$memory < $lowest_memory" | bc -l) )); then
      lowest_memory="$memory"
      lowest_memory_service="$service"
    fi
  fi
done

# Find fastest warm performance
fastest_warm_service=""
fastest_warm_time=""
slowest_warm_service=""
slowest_warm_time=""
for service in "${!service_urls[@]}"; do
  warm_time="${warm_avg_times[$service]}"
  if [ "$warm_time" != "N/A" ] && [ -n "$warm_time" ]; then
    if [ -z "$fastest_warm_time" ] || (( $(echo "$warm_time < $fastest_warm_time" | bc -l) )); then
      fastest_warm_time="$warm_time"
      fastest_warm_service="$service"
    fi
    if [ -z "$slowest_warm_time" ] || (( $(echo "$warm_time > $slowest_warm_time" | bc -l) )); then
      slowest_warm_time="$warm_time"
      slowest_warm_service="$service"
    fi
  fi
done

# Find slowest startup
slowest_startup_service=""
slowest_startup_time=""
for service in "${!service_urls[@]}"; do
  startup_time="${startup_times[$service]}"
  if [ "$startup_time" != "N/A" ] && [ -n "$startup_time" ]; then
    if [ -z "$slowest_startup_time" ] || (( $(echo "$startup_time > $slowest_startup_time" | bc -l) )); then
      slowest_startup_time="$startup_time"
      slowest_startup_service="$service"
    fi
  fi
done

# Find highest memory
highest_memory_service=""
highest_memory=""
for service in "${!service_urls[@]}"; do
  memory="${memory_usage[$service]}"
  if [ "$memory" != "N/A" ] && [ -n "$memory" ]; then
    if [ -z "$highest_memory" ] || (( $(echo "$memory > $highest_memory" | bc -l) )); then
      highest_memory="$memory"
      highest_memory_service="$service"
    fi
  fi
done

if [ -n "$fastest_startup_service" ]; then
  echo -e "  🚀 Fastest Startup: ${CYAN}$(echo "$fastest_startup_service" | tr '_' '-')${NC} (${fastest_startup_time}s)"
fi
if [ -n "$slowest_startup_service" ]; then
  echo -e "  🐌 Slowest Startup: ${CYAN}$(echo "$slowest_startup_service" | tr '_' '-')${NC} (${slowest_startup_time}s)"
fi
if [ -n "$lowest_memory_service" ]; then
  echo -e "  💾 Lowest Memory: ${CYAN}$(echo "$lowest_memory_service" | tr '_' '-')${NC} (${lowest_memory}MB)"
fi
if [ -n "$highest_memory_service" ]; then
  echo -e "  📈 Highest Memory: ${CYAN}$(echo "$highest_memory_service" | tr '_' '-')${NC} (${highest_memory}MB)"
fi
if [ -n "$fastest_warm_service" ]; then
  echo -e "  🏆 Fastest Warm: ${CYAN}$(echo "$fastest_warm_service" | tr '_' '-')${NC} (${fastest_warm_time}s)"
fi
if [ -n "$slowest_warm_service" ]; then
  echo -e "  🐢 Slowest Warm: ${CYAN}$(echo "$slowest_warm_service" | tr '_' '-')${NC} (${slowest_warm_time}s)"
fi

# Native vs JVM analysis
echo ""
echo -e "${GREEN}⚔️  Native vs JVM Analysis:${NC}"

# Calculate averages for each image type
jvm_startup_total=0
jvm_startup_count=0
native_startup_total=0
native_startup_count=0
jvm_memory_total=0
jvm_memory_count=0
native_memory_total=0
native_memory_count=0
jvm_warm_total=0
jvm_warm_count=0
native_warm_total=0
native_warm_count=0
jvm_response_total=0
jvm_response_count=0
native_response_total=0
native_response_count=0

for service in "${!service_urls[@]}"; do
  image_type="${image_types[$service]:-Unknown}"
  
  if [[ "$image_type" == "JVM" ]]; then
    # JVM startup
    startup_time="${startup_times[$service]}"
    if [ "$startup_time" != "N/A" ] && [ -n "$startup_time" ]; then
      jvm_startup_total=$(echo "$jvm_startup_total + $startup_time" | bc)
      jvm_startup_count=$((jvm_startup_count + 1))
    fi
    
    # JVM memory
    memory="${memory_usage[$service]}"
    if [ "$memory" != "N/A" ] && [ -n "$memory" ]; then
      jvm_memory_total=$(echo "$jvm_memory_total + $memory" | bc)
      jvm_memory_count=$((jvm_memory_count + 1))
    fi
    
    # JVM warm performance
    warm_time="${warm_avg_times[$service]}"
    if [ "$warm_time" != "N/A" ] && [ -n "$warm_time" ]; then
      jvm_warm_total=$(echo "$jvm_warm_total + $warm_time" | bc)
      jvm_warm_count=$((jvm_warm_count + 1))
    fi
    
    # JVM response time
    response_time="${initial_response_times[$service]}"
    if [ "$response_time" != "N/A" ] && [ -n "$response_time" ]; then
      jvm_response_total=$(echo "$jvm_response_total + $response_time" | bc)
      jvm_response_count=$((jvm_response_count + 1))
    fi
    
  elif [[ "$image_type" == "Native (GraalVM)" ]]; then
    # Native startup
    startup_time="${startup_times[$service]}"
    if [ "$startup_time" != "N/A" ] && [ -n "$startup_time" ]; then
      native_startup_total=$(echo "$native_startup_total + $startup_time" | bc)
      native_startup_count=$((native_startup_count + 1))
    fi
    
    # Native memory
    memory="${memory_usage[$service]}"
    if [ "$memory" != "N/A" ] && [ -n "$memory" ]; then
      native_memory_total=$(echo "$native_memory_total + $memory" | bc)
      native_memory_count=$((native_memory_count + 1))
    fi
    
    # Native warm performance
    warm_time="${warm_avg_times[$service]}"
    if [ "$warm_time" != "N/A" ] && [ -n "$warm_time" ]; then
      native_warm_total=$(echo "$native_warm_total + $warm_time" | bc)
      native_warm_count=$((native_warm_count + 1))
    fi
    
    # Native response time
    response_time="${initial_response_times[$service]}"
    if [ "$response_time" != "N/A" ] && [ -n "$response_time" ]; then
      native_response_total=$(echo "$native_response_total + $response_time" | bc)
      native_response_count=$((native_response_count + 1))
    fi
  fi
done

# Calculate and display comparisons
if [ $jvm_startup_count -gt 0 ] && [ $native_startup_count -gt 0 ]; then
  jvm_startup_avg=$(echo "scale=4; $jvm_startup_total / $jvm_startup_count" | bc)
  native_startup_avg=$(echo "scale=4; $native_startup_total / $native_startup_count" | bc)
  startup_improvement=$(echo "scale=2; ($jvm_startup_avg / $native_startup_avg)" | bc)
  echo -e "  🚀 Startup Performance: Native is ${startup_improvement}x faster than JVM"
fi

if [ $jvm_memory_count -gt 0 ] && [ $native_memory_count -gt 0 ]; then
  jvm_memory_avg=$(echo "scale=2; $jvm_memory_total / $jvm_memory_count" | bc)
  native_memory_avg=$(echo "scale=2; $native_memory_total / $native_memory_count" | bc)
  memory_diff=$(echo "scale=2; (1 - $native_memory_avg / $jvm_memory_avg) * 100" | bc)
  if (( $(echo "$memory_diff > 0" | bc -l) )); then
    echo -e "  💾 Memory Usage: Native uses $(printf "%.1f" $memory_diff)% less memory than JVM"
  else
    memory_diff_abs=$(echo "scale=2; $memory_diff * -1" | bc)
    echo -e "  💾 Memory Usage: Native uses $(printf "%.1f" $memory_diff_abs)% more memory than JVM"
  fi
fi

if [ $jvm_warm_count -gt 0 ] && [ $native_warm_count -gt 0 ]; then
  jvm_warm_avg=$(echo "scale=4; $jvm_warm_total / $jvm_warm_count" | bc)
  native_warm_avg=$(echo "scale=4; $native_warm_total / $native_warm_count" | bc)
  warm_diff=$(echo "scale=4; (1 - $native_warm_avg / $jvm_warm_avg) * 100" | bc)
  if (( $(echo "$warm_diff > 0" | bc -l) )); then
    echo -e "  🔥 Warm Performance: Native is $(printf "%.2f" $warm_diff)% faster than JVM"
  else
    warm_diff_abs=$(echo "scale=4; $warm_diff * -1" | bc)
    echo -e "  🔥 Warm Performance: JVM is $(printf "%.2f" $warm_diff_abs)% faster than Native"
  fi
fi

if [ $jvm_response_count -gt 0 ] && [ $native_response_count -gt 0 ]; then
  jvm_response_avg=$(echo "scale=4; $jvm_response_total / $jvm_response_count" | bc)
  native_response_avg=$(echo "scale=4; $native_response_total / $native_response_count" | bc)
  response_diff=$(echo "scale=4; (1 - $native_response_avg / $jvm_response_avg) * 100" | bc)
  if (( $(echo "$response_diff > 0" | bc -l) )); then
    echo -e "  📡 Response Time: Native is $(printf "%.2f" $response_diff)% faster than JVM"
  else
    response_diff_abs=$(echo "scale=4; $response_diff * -1" | bc)
    echo -e "  📡 Response Time: JVM is $(printf "%.2f" $response_diff_abs)% faster than Native"
  fi
fi

echo ""
echo -e "${BLUE}📊 Test Configuration:${NC}"
echo -e "  🔥 Warm requests per service: $REQUEST_COUNT"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}                                                                                  ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${YELLOW}🎉 Unified Performance Testing Complete! 🎊${NC}                               ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                                                  ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
