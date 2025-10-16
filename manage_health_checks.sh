#!/bin/bash

# Health Check Management Script for Cloud Run Services
# Enables or disables startup probes (health checks) using gcloud CLI

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

TERRAFORM_DIR="terraform"

# Cloud Run service configuration
SERVICES=(
  "hello-cloud-run-jvm-cloud-sql"
  "hello-cloud-run-jvm-cloud-sql-pgbouncer"
  "native-hello-cloud-run-cloud-sql"
  "native-hello-cloud-run-cloud-sql-pgbouncer"
)

# Print fancy headers
print_header() {
  local title="$1"
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║${NC} ${YELLOW}⚡ $title${NC}$(printf "%*s" $(( 80 - ${#title} - 4 )) "")${GREEN}║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

usage() {
  echo "Usage: $0 [enable|disable|status]"
  echo ""
  echo "Commands:"
  echo "  enable    Enable health checks (startup probes) for all Cloud Run services"
  echo "  disable   Disable health checks (startup probes) for all Cloud Run services"
  echo "  status    Show current health check status"
  echo ""
  echo "Examples:"
  echo "  $0 enable     # Enable health checks using gcloud CLI"
  echo "  $0 disable    # Disable health checks using gcloud CLI"
  echo "  $0 status     # Show current health check status"
}

check_prerequisites() {
  if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}❌ Error: gcloud command not found${NC}"
    echo "Please install Google Cloud SDK first"
    exit 1
  fi

  # Check if gcloud is authenticated
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
    echo -e "${RED}❌ Error: No active gcloud authentication${NC}"
    echo "Please run 'gcloud auth login' first"
    exit 1
  fi

  # Get project ID from terraform outputs if available
  if [ -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
    PROJECT_ID=$(cd "$TERRAFORM_DIR" && terraform output -raw gcp_project_id 2>/dev/null)
    REGION=$(cd "$TERRAFORM_DIR" && terraform output -raw gcp_region 2>/dev/null)
  fi

  # Try to get from gcloud config if terraform outputs not available
  if [ -z "$PROJECT_ID" ]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
  fi

  if [ -z "$REGION" ]; then
    REGION=$(gcloud config get-value run/region 2>/dev/null)
    if [ -z "$REGION" ]; then
      REGION="asia-southeast1" # Default region
    fi
  fi

  if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}❌ Error: Cannot determine GCP project ID${NC}"
    echo "Please run 'gcloud config set project YOUR_PROJECT_ID' or ensure terraform state is available"
    exit 1
  fi

  echo -e "${BLUE}📋 Using project: ${CYAN}$PROJECT_ID${NC}, region: ${CYAN}$REGION${NC}"
}

get_health_check_status() {
  local enabled_count=0
  local total_count=0
  local services_status=()
  
  for service in "${SERVICES[@]}"; do
    ((total_count++))
    
    # Get service configuration
    local service_config=$(gcloud run services describe "$service" --region="$REGION" --project="$PROJECT_ID" --format="json" 2>/dev/null)
    
    if [ -z "$service_config" ]; then
      services_status+=("$service:not_found")
      continue
    fi
    
    # Check if startup probe has HTTP health check (not just TCP)
    local http_probe=$(echo "$service_config" | jq -r '.spec.template.spec.containers[0].startupProbe.httpGet.path // empty' 2>/dev/null)
    
    if [ -n "$http_probe" ] && [ "$http_probe" != "null" ] && [ "$http_probe" != "empty" ]; then
      ((enabled_count++))
      services_status+=("$service:enabled")
    else
      services_status+=("$service:disabled")
    fi
  done
  
  echo "$enabled_count:$total_count:${services_status[*]}"
}

show_status() {
  print_header "Health Check Status"
  
  local status=$(get_health_check_status)
  local enabled=$(echo $status | cut -d':' -f1)
  local total=$(echo $status | cut -d':' -f2)
  local services_info=$(echo $status | cut -d':' -f3-)
  
  echo -e "📊 ${CYAN}Health Check Configuration:${NC}"
  echo -e "  🔍 Total services: $total"
  echo -e "  ✅ Services with health checks enabled: $enabled"
  echo -e "  ❌ Services with health checks disabled: $((total - enabled))"
  echo ""
  
  # Show individual service status
  echo -e "📋 ${CYAN}Individual Service Status:${NC}"
  for service_status in $services_info; do
    local service=$(echo "$service_status" | cut -d':' -f1)
    local status=$(echo "$service_status" | cut -d':' -f2)
    
    case "$status" in
      "enabled")
        echo -e "  ✅ ${CYAN}$service${NC}: Health checks enabled"
        ;;
      "disabled")
        echo -e "  ❌ ${CYAN}$service${NC}: Health checks disabled"
        ;;
      "not_found")
        echo -e "  🔍 ${CYAN}$service${NC}: Service not found"
        ;;
    esac
  done
  echo ""
  
  if [ "$enabled" -eq "$total" ] && [ "$total" -gt 0 ]; then
    echo -e "${GREEN}🎯 Status: Health checks are ENABLED for all services${NC}"
  elif [ "$enabled" -eq 0 ]; then
    echo -e "${RED}🚫 Status: Health checks are DISABLED for all services${NC}"
  else
    echo -e "${YELLOW}⚠️  Status: Health checks are PARTIALLY configured${NC}"
  fi
  echo ""
}

enable_health_checks() {
  print_header "Enabling Health Checks"
  
  echo -e "🔧 ${CYAN}Enabling startup probes for Cloud Run services...${NC}"
  
  local success_count=0
  local total_count=0
  
  for service in "${SERVICES[@]}"; do
    ((total_count++))
    echo -e "🔍 Processing service: ${CYAN}$service${NC}"
    
    # Check if service exists
    if ! gcloud run services describe "$service" --region="$REGION" --project="$PROJECT_ID" --format="value(metadata.name)" &>/dev/null; then
      echo -e "  ${YELLOW}⚠️  Service not found, skipping...${NC}"
      continue
    fi
    
    echo -e "  ${BLUE}📝 Configuring startup probe...${NC}"
    
    # Use gcloud run services update with startup probe
    if gcloud run services update "$service" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --startup-probe="initialDelaySeconds=15,timeoutSeconds=3,periodSeconds=10,failureThreshold=10,httpGet.port=8080,httpGet.path=/actuator/health/ready"; then
      echo -e "  ${GREEN}✅ Health checks enabled successfully${NC}"
      ((success_count++))
    else
      echo -e "  ${RED}❌ Failed to enable health checks${NC}"
    fi
    
    echo ""
  done
  
  echo -e "${GREEN}🎉 Health checks enabled for $success_count out of $total_count services${NC}"
}

disable_health_checks() {
  print_header "Disabling Health Checks"
  
  echo -e "🔧 ${CYAN}Disabling startup probes for Cloud Run services...${NC}"
  
  local success_count=0
  local total_count=0
  
  for service in "${SERVICES[@]}"; do
    ((total_count++))
    echo -e "🔍 Processing service: ${CYAN}$service${NC}"
    
    # Check if service exists
    if ! gcloud run services describe "$service" --region="$REGION" --project="$PROJECT_ID" --format="value(metadata.name)" &>/dev/null; then
      echo -e "  ${YELLOW}⚠️  Service not found, skipping...${NC}"
      continue
    fi
    
    echo -e "  ${BLUE}📝 Removing startup probe...${NC}"
    
    # Use gcloud run services update to clear startup probe
    if gcloud run services update "$service" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --startup-probe=""; then
      echo -e "  ${GREEN}✅ Health checks disabled successfully${NC}"
      ((success_count++))
    else
      echo -e "  ${RED}❌ Failed to disable health checks${NC}"
    fi
    echo ""
  done
  
  echo -e "${GREEN}🎉 Health checks disabled for $success_count out of $total_count services${NC}"
}

# Main script logic
case "$1" in
  enable)
    check_prerequisites
    enable_health_checks
    echo ""
    show_status
    ;;
  disable)
    check_prerequisites
    disable_health_checks
    echo ""
    show_status
    ;;
  status)
    check_prerequisites
    show_status
    ;;
  *)
    usage
    exit 1
    ;;
esac

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}  ${YELLOW}🎉 Health Check Management Complete! 🎊${NC}                                   ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"