#!/bin/bash

# Setup script for Java Application Deployment Pipeline
# This script helps you configure the deployment environment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}    Java Application Deployment Setup Script       ${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo ""

# Function to print colored output
print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if .env file exists
check_env_file() {
    print_step "Checking environment configuration..."
    
    if [[ ! -f .env ]]; then
        print_info "Creating .env file from template..."
        cp .env.example .env
        print_warning "Please edit .env file with your configuration before running deployment scripts"
        
        echo ""
        print_info "Required configuration items:"
        echo "  - AWS_SECRET_ACCESS_KEY: Your AWS secret access key"
        echo "  - GITHUB_REPO_URL: Your GitHub repository SSH URL"
        echo "  - EC2_KEY_PAIR_NAME: Your EC2 key pair name"
        echo "  - VPC_ID: Your VPC ID"
        echo "  - SUBNET_ID_1: First subnet ID (different AZ)"
        echo "  - SUBNET_ID_2: Second subnet ID (different AZ)"
        echo "  - SECURITY_GROUP_ID: Security group allowing ports 22, 80, 9000"
        echo ""
    else
        print_info ".env file already exists"
    fi
}

# Validate prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    local tools=("git" "java" "aws" "docker" "curl" "ssh")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        print_info "Installation commands for Ubuntu/Debian:"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                "java")
                    echo "  sudo apt update && sudo apt install -y openjdk-11-jdk"
                    ;;
                "docker")
                    echo "  curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh"
                    ;;
                "aws")
                    echo "  curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip' && unzip awscliv2.zip && sudo ./aws/install"
                    ;;
                *)
                    echo "  sudo apt update && sudo apt install -y $tool"
                    ;;
            esac
        done
        echo ""
        return 1
    else
        print_info "All required tools are installed"
    fi
}

# Check AWS configuration
check_aws_config() {
    print_step "Checking AWS configuration..."
    
    if aws sts get-caller-identity &> /dev/null; then
        local account_id=$(aws sts get-caller-identity --query Account --output text)
        local user_arn=$(aws sts get-caller-identity --query Arn --output text)
        print_info "AWS credentials configured for account: $account_id"
        print_info "User/Role: $user_arn"
    else
        print_warning "AWS credentials not configured or invalid"
        print_info "Configure AWS credentials using one of these methods:"
        echo "  1. aws configure"
        echo "  2. Set environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
        echo "  3. Use IAM roles (recommended for EC2)"
        echo ""
    fi
}

# Check SSH configuration
check_ssh_config() {
    print_step "Checking SSH configuration..."
    
    if ssh -o BatchMode=yes -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        print_info "GitHub SSH authentication working"
    else
        print_warning "GitHub SSH authentication not working"
        print_info "To configure SSH for GitHub:"
        echo "  1. Generate SSH key: ssh-keygen -t rsa -b 4096 -C 'your-email@example.com'"
        echo "  2. Add key to SSH agent: ssh-add ~/.ssh/id_rsa"
        echo "  3. Add public key to GitHub: https://github.com/settings/keys"
        echo "  4. Test: ssh -T git@github.com"
        echo ""
    fi
}

# Check Docker
check_docker() {
    print_step "Checking Docker configuration..."
    
    if docker version &> /dev/null; then
        print_info "Docker is running"
    else
        print_warning "Docker is not running or not accessible"
        print_info "Try: sudo systemctl start docker"
        print_info "Add user to docker group: sudo usermod -aG docker $USER"
        print_info "Log out and back in for group changes to take effect"
        echo ""
    fi
}

# Create AWS resources
create_aws_resources() {
    print_step "AWS resources that need to be created manually:"
    echo ""
    
    print_info "1. VPC (if not using default):"
    echo "   - Create VPC with CIDR block (e.g., 10.0.0.0/16)"
    echo "   - Create Internet Gateway and attach to VPC"
    echo "   - Create route table with route to Internet Gateway"
    echo ""
    
    print_info "2. Subnets:"
    echo "   - Create at least 2 subnets in different Availability Zones"
    echo "   - Associate subnets with route table"
    echo "   - Enable auto-assign public IP"
    echo ""
    
    print_info "3. Security Group:"
    echo "   - Create security group with these inbound rules:"
    echo "     * SSH (22) from your IP"
    echo "     * HTTP (80) from anywhere (0.0.0.0/0)"
    echo "     * Custom TCP (9000) from anywhere (0.0.0.0/0)"
    echo ""
    
    print_info "4. EC2 Key Pair:"
    echo "   - Create or import key pair for EC2 access"
    echo "   - Save private key securely"
    echo ""
    
    print_info "5. ECR Repository (optional, will be created automatically):"
    echo "   - Repository for Docker images"
    echo ""
}

# Show usage examples
show_usage() {
    print_step "Usage examples:"
    echo ""
    
    print_info "1. Test locally:"
    echo "   ./scripts/deploy.sh local"
    echo ""
    
    print_info "2. Deploy to EC2:"
    echo "   ./scripts/deploy.sh ec2"
    echo ""
    
    print_info "3. Full deployment with load balancer:"
    echo "   ./scripts/deploy.sh full"
    echo ""
    
    print_info "4. Create load balancer only:"
    echo "   ./scripts/create-elb.sh"
    echo ""
    
    print_info "5. Build Docker image:"
    echo "   cd docker && docker build -t java-app . && docker run -p 9000:9000 java-app"
    echo ""
}

# Show next steps
show_next_steps() {
    print_step "Next steps:"
    echo ""
    
    print_info "1. Edit .env file with your configuration"
    print_info "2. Create required AWS resources (VPC, subnets, security groups, key pair)"
    print_info "3. Configure GitHub repository with your Java application"
    print_info "4. Run ./scripts/deploy.sh local to test locally"
    print_info "5. Run ./scripts/deploy.sh full for complete deployment"
    echo ""
    
    print_warning "Important: Review all scripts before running in production!"
    print_warning "This setup is for development/testing. Enhance security for production use."
    echo ""
}

# Main function
main() {
    print_info "This script will help you set up the deployment environment."
    print_info "No changes will be made automatically - this is just a configuration check."
    echo ""
    
    check_env_file
    check_prerequisites || true
    check_aws_config
    check_ssh_config
    check_docker
    echo ""
    
    create_aws_resources
    echo ""
    
    show_usage
    echo ""
    
    show_next_steps
    
    print_step "Setup check completed!"
    print_info "Review the output above and address any warnings before deployment."
}

# Run main function
main "$@"
