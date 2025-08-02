#!/bin/bash

# Main deployment script for Java application
# Usage: ./deploy.sh [local|ec2|full]
# Description: 
#   1. Clones GitHub repository using SSH
#   2. Starts Java application with 'java -jar build/libs/project.jar' on port 9000
#   3. Creates Dockerfile for EC2 deployment
#   4. Deploys to AWS EC2 instances
#   5. Creates AWS Application Load Balancer with health checks
#
# Author: Deployment Team
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
LOG_FILE="$LOG_DIR/deploy-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"

# Logging function with enhanced error tracking
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local caller="${BASH_SOURCE[2]:-unknown}:${BASH_LINENO[1]:-unknown}"
    
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
    echo "[$timestamp] [$level] [$caller] $message" >> "$LOG_FILE"
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

# Validate prerequisites
validate_prerequisites() {
    log "INFO" "Validating prerequisites..."
    
    # Check required commands
    local required_commands=("git" "java" "aws" "docker")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error_exit "Required command '$cmd' not found. Please install it."
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured or invalid."
    fi
    
    # Check SSH key for GitHub
    if ! ssh -o BatchMode=yes -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        log "WARN" "GitHub SSH authentication might fail. Please ensure SSH keys are configured."
    fi
    
    log "INFO" "Prerequisites validation completed successfully"
}

# Clone repository
clone_repository() {
    log "INFO" "Cloning repository: $GITHUB_REPO_URL"
    
    local repo_dir="temp-repo"
    
    if [[ -d "$repo_dir" ]]; then
        log "INFO" "Repository directory exists, removing..."
        rm -rf "$repo_dir"
    fi
    
    if ! git clone "$GITHUB_REPO_URL" "$repo_dir" 2>> "$LOG_FILE"; then
        error_exit "Failed to clone repository"
    fi
    
    cd "$repo_dir"
    
    # Check if JAR file exists
    if [[ ! -f "$JAR_PATH" ]]; then
        log "WARN" "JAR file not found at $JAR_PATH, creating test JAR..."
        create_test_jar
    fi
    
    log "INFO" "Repository cloned successfully"
}

# Create test JAR if not exists
create_test_jar() {
    log "INFO" "Creating test JAR file..."
    
    mkdir -p build/libs
    
    # Create a simple Java application
    mkdir -p src/main/java/com/test
    cat > src/main/java/com/test/TestServer.java << 'EOF'
package com.test;

import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpExchange;
import java.io.*;
import java.net.InetSocketAddress;

public class TestServer {
    public static void main(String[] args) throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress(9000), 0);
        
        server.createContext("/", new HttpHandler() {
            @Override
            public void handle(HttpExchange exchange) throws IOException {
                String response = "Hello from Java Test Server! Time: " + new java.util.Date();
                exchange.sendResponseHeaders(200, response.length());
                OutputStream os = exchange.getResponseBody();
                os.write(response.getBytes());
                os.close();
            }
        });
        
        server.createContext("/health", new HttpHandler() {
            @Override
            public void handle(HttpExchange exchange) throws IOException {
                String response = "{\"status\":\"healthy\",\"timestamp\":\"" + new java.util.Date() + "\"}";
                exchange.getResponseHeaders().set("Content-Type", "application/json");
                exchange.sendResponseHeaders(200, response.length());
                OutputStream os = exchange.getResponseBody();
                os.write(response.getBytes());
                os.close();
            }
        });
        
        server.setExecutor(null);
        System.out.println("Server starting on port 9000...");
        server.start();
        System.out.println("Server started successfully on http://localhost:9000");
    }
}
EOF

    # Compile and create JAR
    javac -d build/classes src/main/java/com/test/TestServer.java
    cd build/classes
    jar cfe ../libs/project.jar com.test.TestServer com/test/TestServer.class
    cd ../..
    
    log "INFO" "Test JAR created successfully"
}

# Start Java application locally
start_local_app() {
    log "INFO" "Starting Java application locally..."
    
    if [[ ! -f "$JAR_PATH" ]]; then
        error_exit "JAR file not found at $JAR_PATH"
    fi
    
    # Kill any existing process on port 9000
    if netstat -tuln | grep -q ":9000 "; then
        log "WARN" "Port 9000 is already in use, attempting to kill existing process..."
        local pid=$(lsof -t -i:9000 || true)
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
            sleep 2
        fi
    fi
    
    # Start the application
    log "INFO" "Starting Java application: java -jar $JAR_PATH"
    nohup java -jar "$JAR_PATH" > "/tmp/java-app.log" 2>&1 &
    local app_pid=$!
    
    # Wait for application to start
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -s "http://localhost:9000" > /dev/null 2>&1; then
            log "INFO" "Application started successfully (PID: $app_pid)"
            echo "$app_pid" > "/tmp/java-app.pid"
            return 0
        fi
        
        sleep 2
        ((attempt++))
        log "DEBUG" "Waiting for application to start... (attempt $attempt/$max_attempts)"
    done
    
    error_exit "Application failed to start within timeout period"
}

# Deploy to EC2
deploy_to_ec2() {
    log "INFO" "Deploying to EC2..."
    
    # Create or get EC2 instance
    local instance_id=$(get_or_create_ec2_instance)
    
    # Wait for instance to be running
    log "INFO" "Waiting for EC2 instance to be running..."
    aws ec2 wait instance-running --instance-ids "$instance_id" --region "$AWS_REGION"
    
    # Get instance public IP
    local public_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text \
        --region "$AWS_REGION")
    
    log "INFO" "EC2 instance running at $public_ip"
    
    # Copy application to EC2
    deploy_app_to_instance "$public_ip"
    
    echo "$instance_id" > "/tmp/ec2-instance-id.txt"
    echo "$public_ip" > "/tmp/ec2-public-ip.txt"
}

# Get or create EC2 instance
get_or_create_ec2_instance() {
    # Check if instance already exists
    local existing_instance=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$APP_NAME" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    if [[ "$existing_instance" != "None" && "$existing_instance" != "null" ]]; then
        log "INFO" "Using existing EC2 instance: $existing_instance"
        
        # Start instance if stopped
        local state=$(aws ec2 describe-instances \
            --instance-ids "$existing_instance" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text \
            --region "$AWS_REGION")
        
        if [[ "$state" == "stopped" ]]; then
            log "INFO" "Starting stopped instance..."
            aws ec2 start-instances --instance-ids "$existing_instance" --region "$AWS_REGION"
        fi
        
        echo "$existing_instance"
    else
        log "INFO" "Creating new EC2 instance..."
        
        # Create user data script
        create_user_data_script
        
        # Launch new instance
        local instance_id=$(aws ec2 run-instances \
            --image-id "$EC2_AMI_ID" \
            --count 1 \
            --instance-type "$EC2_INSTANCE_TYPE" \
            --key-name "$EC2_KEY_PAIR_NAME" \
            --security-group-ids "$SECURITY_GROUP_ID" \
            --subnet-id "$SUBNET_ID_1" \
            --user-data file://aws/user-data.sh \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$APP_NAME},{Key=Environment,Value=production}]" \
            --query 'Instances[0].InstanceId' \
            --output text \
            --region "$AWS_REGION")
        
        log "INFO" "Created new EC2 instance: $instance_id"
        echo "$instance_id"
    fi
}

# Create user data script
create_user_data_script() {
    mkdir -p aws
    cat > aws/user-data.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y java-11-amazon-corretto docker git

# Start Docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create application directory
mkdir -p /opt/java-app
chown ec2-user:ec2-user /opt/java-app
EOF
}

# Deploy application to EC2 instance
deploy_app_to_instance() {
    local public_ip="$1"
    
    log "INFO" "Deploying application to EC2 instance at $public_ip"
    
    # Wait for SSH to be available
    local max_attempts=20
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/"$EC2_KEY_PAIR_NAME".pem "ec2-user@$public_ip" "echo 'SSH connection successful'" 2>/dev/null; then
            break
        fi
        
        sleep 10
        ((attempt++))
        log "DEBUG" "Waiting for SSH connection... (attempt $attempt/$max_attempts)"
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        error_exit "Failed to establish SSH connection to EC2 instance"
    fi
    
    # Copy JAR file to EC2
    log "INFO" "Copying JAR file to EC2 instance..."
    scp -o StrictHostKeyChecking=no -i ~/.ssh/"$EC2_KEY_PAIR_NAME".pem "$JAR_PATH" "ec2-user@$public_ip:/opt/java-app/"
    
    # Start application on EC2
    log "INFO" "Starting application on EC2 instance..."
    ssh -o StrictHostKeyChecking=no -i ~/.ssh/"$EC2_KEY_PAIR_NAME".pem "ec2-user@$public_ip" << 'EOSSH'
cd /opt/java-app
# Kill any existing Java processes
pkill -f "java -jar" || true
sleep 2

# Start the application
nohup java -jar project.jar > app.log 2>&1 &
echo $! > app.pid

# Wait for application to start
for i in {1..30}; do
    if curl -s http://localhost:9000 > /dev/null 2>&1; then
        echo "Application started successfully"
        exit 0
    fi
    sleep 2
done

echo "Application failed to start"
exit 1
EOSSH
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "Application deployed and started successfully on EC2"
    else
        error_exit "Failed to start application on EC2"
    fi
}

# Create load balancer
create_load_balancer() {
    log "INFO" "Creating Application Load Balancer..."
    
    # Run the ELB creation script
    ./scripts/create-elb.sh
}

# Main function
main() {
    log "INFO" "Starting deployment script with mode: ${1:-full}"
    
    local mode="${1:-full}"
    
    # Change to script directory
    cd "$(dirname "$0")/.."
    
    # Load environment
    load_env
    
    # Validate prerequisites
    validate_prerequisites
    
    case "$mode" in
        "local")
            log "INFO" "Running in local mode"
            clone_repository
            start_local_app
            log "INFO" "Local deployment completed. Application available at http://localhost:9000"
            ;;
        "ec2")
            log "INFO" "Running in EC2 mode"
            clone_repository
            deploy_to_ec2
            log "INFO" "EC2 deployment completed"
            ;;
        "full")
            log "INFO" "Running in full deployment mode"
            clone_repository
            deploy_to_ec2
            create_load_balancer
            log "INFO" "Full deployment completed successfully"
            ;;
        *)
            error_exit "Invalid mode: $mode. Use 'local', 'ec2', or 'full'"
            ;;
    esac
    
    log "INFO" "Deployment script completed successfully"
}

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up temporary files..."
    if [[ -d "temp-repo" ]]; then
        rm -rf temp-repo
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Run main function
main "$@"
