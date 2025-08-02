#!/bin/bash

# Script to create AWS Application Load Balancer with comprehensive configuration
# Usage: ./create-elb.sh
# Description:
#   - Creates Application Load Balancer with Internet-facing access
#   - Configures Target Groups with health checks on port 9000
#   - Sets up HTTP listener on port 80 forwarding to application port 9000
#   - Registers EC2 instances automatically
#   - Implements comprehensive health monitoring and logging
#
# Load Balancer Parameters:
#   Type: Application Load Balancer
#   Scheme: Internet-facing
#   Protocol: HTTP (port 80 -> 9000)
#   Health Check: HTTP on / endpoint, 30s interval, 5s timeout
#   Target Type: EC2 instances
#
# Author: Infrastructure Team
# Version: 1.0
# Date: $(date +%Y-%m-%d)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_DIR="/tmp/deployment-logs"
LOG_FILE="$LOG_DIR/create-elb-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Load environment variables
load_env() {
    if [[ -f .env ]]; then
        log "INFO" "Loading environment variables from .env"
        set -a
        source .env
        set +a
    else
        error_exit ".env file not found. Please copy .env.example to .env and configure it."
    fi
}

# Validate AWS prerequisites
validate_aws_prerequisites() {
    log "INFO" "Validating AWS prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured or invalid."
    fi
    
    # Validate required environment variables
    local required_vars=("VPC_ID" "SUBNET_ID_1" "SUBNET_ID_2" "SECURITY_GROUP_ID" "AWS_REGION")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error_exit "Required environment variable $var is not set"
        fi
    done
    
    log "INFO" "AWS prerequisites validation completed"
}

# Check if load balancer already exists
check_existing_alb() {
    log "INFO" "Checking for existing load balancer: $ALB_NAME"
    
    local alb_arn=$(aws elbv2 describe-load-balancers \
        --names "$ALB_NAME" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    if [[ "$alb_arn" != "None" && "$alb_arn" != "null" ]]; then
        log "INFO" "Load balancer already exists: $alb_arn"
        echo "$alb_arn" > "/tmp/alb-arn.txt"
        
        # Get ALB DNS name
        local alb_dns=$(aws elbv2 describe-load-balancers \
            --load-balancer-arns "$alb_arn" \
            --query 'LoadBalancers[0].DNSName' \
            --output text \
            --region "$AWS_REGION")
        
        log "INFO" "Load balancer DNS: $alb_dns"
        echo "$alb_dns" > "/tmp/alb-dns.txt"
        
        return 0
    else
        log "INFO" "No existing load balancer found"
        return 1
    fi
}

# Create Application Load Balancer
create_alb() {
    log "INFO" "Creating Application Load Balancer: $ALB_NAME"
    
    # Create load balancer
    local alb_arn=$(aws elbv2 create-load-balancer \
        --name "$ALB_NAME" \
        --subnets "$SUBNET_ID_1" "$SUBNET_ID_2" \
        --security-groups "$SECURITY_GROUP_ID" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --tags Key=Name,Value="$ALB_NAME" Key=Environment,Value=production \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text \
        --region "$AWS_REGION")
    
    if [[ -z "$alb_arn" || "$alb_arn" == "null" ]]; then
        error_exit "Failed to create Application Load Balancer"
    fi
    
    log "INFO" "Application Load Balancer created: $alb_arn"
    echo "$alb_arn" > "/tmp/alb-arn.txt"
    
    # Wait for load balancer to be active
    log "INFO" "Waiting for load balancer to become active..."
    aws elbv2 wait load-balancer-available \
        --load-balancer-arns "$alb_arn" \
        --region "$AWS_REGION"
    
    # Get load balancer DNS name
    local alb_dns=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region "$AWS_REGION")
    
    log "INFO" "Load balancer DNS: $alb_dns"
    echo "$alb_dns" > "/tmp/alb-dns.txt"
    
    return 0
}

# Create target group
create_target_group() {
    log "INFO" "Creating target group: $TARGET_GROUP_NAME"
    
    # Check if target group already exists
    local existing_tg_arn=$(aws elbv2 describe-target-groups \
        --names "$TARGET_GROUP_NAME" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    if [[ "$existing_tg_arn" != "None" && "$existing_tg_arn" != "null" ]]; then
        log "INFO" "Target group already exists: $existing_tg_arn"
        echo "$existing_tg_arn" > "/tmp/target-group-arn.txt"
        return 0
    fi
    
    # Create new target group
    local tg_arn=$(aws elbv2 create-target-group \
        --name "$TARGET_GROUP_NAME" \
        --protocol HTTP \
        --port 9000 \
        --vpc-id "$VPC_ID" \
        --target-type instance \
        --health-check-enabled \
        --health-check-interval-seconds 30 \
        --health-check-path / \
        --health-check-port traffic-port \
        --health-check-protocol HTTP \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --matcher HttpCode=200 \
        --tags Key=Name,Value="$TARGET_GROUP_NAME" Key=Environment,Value=production \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text \
        --region "$AWS_REGION")
    
    if [[ -z "$tg_arn" || "$tg_arn" == "null" ]]; then
        error_exit "Failed to create target group"
    fi
    
    log "INFO" "Target group created: $tg_arn"
    echo "$tg_arn" > "/tmp/target-group-arn.txt"
    
    # Configure health check settings
    log "INFO" "Configuring target group health check settings..."
    aws elbv2 modify-target-group \
        --target-group-arn "$tg_arn" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region "$AWS_REGION" >> "$LOG_FILE" 2>&1
    
    log "INFO" "Target group health check configured"
}

# Register EC2 instances with target group
register_targets() {
    local tg_arn="$1"
    
    log "INFO" "Registering EC2 instances with target group..."
    
    # Get EC2 instance ID if available
    local instance_id=""
    if [[ -f "/tmp/ec2-instance-id.txt" ]]; then
        instance_id=$(cat "/tmp/ec2-instance-id.txt")
        log "INFO" "Found EC2 instance ID: $instance_id"
    else
        # Try to find instances by tag
        instance_id=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=$APP_NAME" "Name=instance-state-name,Values=running" \
            --query 'Reservations[0].Instances[0].InstanceId' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "None")
        
        if [[ "$instance_id" == "None" || "$instance_id" == "null" ]]; then
            log "WARN" "No running EC2 instances found for app: $APP_NAME"
            log "WARN" "Target group created but no targets registered"
            return 0
        fi
    fi
    
    log "INFO" "Registering instance $instance_id with target group"
    aws elbv2 register-targets \
        --target-group-arn "$tg_arn" \
        --targets Id="$instance_id",Port=9000 \
        --region "$AWS_REGION"
    
    log "INFO" "Instance registered with target group"
    
    # Wait for target to become healthy
    log "INFO" "Waiting for target to become healthy..."
    local max_attempts=20
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        local target_health=$(aws elbv2 describe-target-health \
            --target-group-arn "$tg_arn" \
            --targets Id="$instance_id",Port=9000 \
            --query 'TargetHealthDescriptions[0].TargetHealth.State' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "unknown")
        
        log "DEBUG" "Target health status: $target_health (attempt $((attempt + 1))/$max_attempts)"
        
        if [[ "$target_health" == "healthy" ]]; then
            log "INFO" "Target is healthy"
            break
        elif [[ "$target_health" == "unhealthy" ]]; then
            log "WARN" "Target is unhealthy, continuing to wait..."
        fi
        
        sleep 15
        ((attempt++))
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log "WARN" "Target did not become healthy within timeout period"
        log "WARN" "Check application status and security group configuration"
    fi
}

# Create listener
create_listener() {
    local alb_arn="$1"
    local tg_arn="$2"
    
    log "INFO" "Creating listener for load balancer..."
    
    # Check if listener already exists
    local existing_listener=$(aws elbv2 describe-listeners \
        --load-balancer-arn "$alb_arn" \
        --query 'Listeners[?Port==`80`].ListenerArn' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -n "$existing_listener" && "$existing_listener" != "None" ]]; then
        log "INFO" "Listener already exists: $existing_listener"
        return 0
    fi
    
    # Create new listener
    local listener_arn=$(aws elbv2 create-listener \
        --load-balancer-arn "$alb_arn" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$tg_arn" \
        --query 'Listeners[0].ListenerArn' \
        --output text \
        --region "$AWS_REGION")
    
    if [[ -z "$listener_arn" || "$listener_arn" == "null" ]]; then
        error_exit "Failed to create listener"
    fi
    
    log "INFO" "Listener created: $listener_arn"
    echo "$listener_arn" > "/tmp/listener-arn.txt"
}

# Display load balancer information
display_alb_info() {
    log "INFO" "=== Load Balancer Configuration Summary ==="
    
    if [[ -f "/tmp/alb-dns.txt" ]]; then
        local alb_dns=$(cat "/tmp/alb-dns.txt")
        log "INFO" "Load Balancer URL: http://$alb_dns"
        log "INFO" "DNS Name: $alb_dns"
    fi
    
    if [[ -f "/tmp/alb-arn.txt" ]]; then
        local alb_arn=$(cat "/tmp/alb-arn.txt")
        log "INFO" "Load Balancer ARN: $alb_arn"
    fi
    
    if [[ -f "/tmp/target-group-arn.txt" ]]; then
        local tg_arn=$(cat "/tmp/target-group-arn.txt")
        log "INFO" "Target Group ARN: $tg_arn"
    fi
    
    log "INFO" "=== Load Balancer Parameters Set ==="
    log "INFO" "- Type: Application Load Balancer"
    log "INFO" "- Scheme: Internet-facing"
    log "INFO" "- Protocol: HTTP"
    log "INFO" "- Port: 80 (external) -> 9000 (target)"
    log "INFO" "- Target Type: Instance"
    log "INFO" "- Health Check Protocol: HTTP"
    log "INFO" "- Health Check Path: /"
    log "INFO" "- Health Check Port: Traffic Port (9000)"
    log "INFO" "- Health Check Interval: 30 seconds"
    log "INFO" "- Health Check Timeout: 5 seconds"
    log "INFO" "- Healthy Threshold: 2 consecutive successes"
    log "INFO" "- Unhealthy Threshold: 3 consecutive failures"
    log "INFO" "- Success Codes: 200"
    
    log "INFO" "=== Load Balancer Parameters NOT Set ==="
    log "INFO" "- SSL/TLS: Not configured (HTTP only)"
    log "INFO" "- WAF: Not attached"
    log "INFO" "- Access Logs: Disabled"
    log "INFO" "- Connection Draining: Using defaults"
    log "INFO" "- Sticky Sessions: Not enabled"
    log "INFO" "- Cross-Zone Load Balancing: Using defaults"
    log "INFO" "- Deletion Protection: Disabled"
    
    log "INFO" "=== Security Considerations ==="
    log "INFO" "- Add HTTPS/SSL for production"
    log "INFO" "- Configure WAF for security"
    log "INFO" "- Enable access logs for monitoring"
    log "INFO" "- Review security group rules"
    log "INFO" "- Consider using private subnets for targets"
}

# Main function
main() {
    log "INFO" "Starting AWS Application Load Balancer creation process"
    
    # Change to script directory
    cd "$(dirname "$0")/.."
    
    # Load environment variables
    load_env
    
    # Validate AWS prerequisites
    validate_aws_prerequisites
    
    # Check if ALB already exists
    if check_existing_alb; then
        log "INFO" "Using existing load balancer"
    else
        # Create new ALB
        create_alb
    fi
    
    # Create target group
    create_target_group
    
    # Get ARNs
    local alb_arn=$(cat "/tmp/alb-arn.txt")
    local tg_arn=$(cat "/tmp/target-group-arn.txt")
    
    # Create listener
    create_listener "$alb_arn" "$tg_arn"
    
    # Register targets
    register_targets "$tg_arn"
    
    # Display information
    display_alb_info
    
    log "INFO" "AWS Application Load Balancer setup completed successfully"
    
    if [[ -f "/tmp/alb-dns.txt" ]]; then
        local alb_dns=$(cat "/tmp/alb-dns.txt")
        echo ""
        echo "✅ Load Balancer is ready!"
        echo "🌐 Access your application at: http://$alb_dns"
        echo "📝 Check logs at: $LOG_FILE"
    fi
}

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up temporary files..."
}

# Set trap for cleanup
trap cleanup EXIT

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
