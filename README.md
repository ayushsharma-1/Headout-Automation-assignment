# Complete Java Application Deployment Pipeline

This project implements a comprehensive deployment pipeline that performs the following tasks as specified:

1. **Clone repository from GitHub using SSH** ✅
2. **Start Java process with 'java -jar build/libs/project.jar' on port 9000** ✅  
3. **Create Dockerfile for EC2 deployment** ✅
4. **Write GitHub Action for automated deployment** ✅
5. **Create AWS Elastic Load Balancer** ✅

## 🏗️ Architecture Overview

```
GitHub Repository (SSH) → Build & Test → Docker Image → ECR → EC2 Instances → Application Load Balancer
```

## 📁 Project Structure

```
Headout/
├── scripts/
│   ├── deploy.sh              # Main deployment orchestrator
│   ├── clone-repo.sh          # GitHub SSH cloning
│   ├── start-java-app.sh      # Java application startup
│   ├── create-elb.sh          # Load balancer creation
│   └── view-logs.sh           # Log monitoring
├── docker/
│   └── Dockerfile             # Production container configuration
├── .github/workflows/
│   └── deploy.yml             # CI/CD pipeline
├── aws/
│   └── user-data.sh           # EC2 initialization script
├── .env                       # Environment configuration
└── README.md                  # Complete documentation
```

## 📋 Prerequisites

- AWS Account with appropriate IAM permissions
- GitHub repository with SSH access configured
- AWS CLI configured with access keys
- Docker installed locally (for testing)
- Java 11+ installed

## 🚀 Quick Start

### 1. Environment Configuration

Copy and configure the environment file:
```bash
cp .env.example .env
# Edit .env with your AWS credentials and resource IDs
```

### 2. Local Deployment

Test the application locally:
```bash
./scripts/deploy.sh local
```

### 3. EC2 Deployment

Deploy to AWS EC2:
```bash
./scripts/deploy.sh ec2
```

### 4. Full Deployment with Load Balancer

Complete deployment with load balancer:
```bash
./scripts/deploy.sh full
```

## 🔧 Core Components

### Main Deployment Script (`scripts/deploy.sh`)

**Primary Functions:**
- **Repository Cloning**: Uses SSH to clone from GitHub with authentication validation
- **Java Application Startup**: Executes `java -jar build/libs/project.jar` on port 9000
- **Health Monitoring**: Implements comprehensive health checks and process monitoring
- **Error Handling**: Robust error handling with detailed logging and recovery mechanisms

**Deployment Modes:**
- `local`: Local development and testing
- `ec2`: EC2 instance deployment
- `full`: Complete deployment with load balancer

### Load Balancer Script (`scripts/create-elb.sh`)

**Load Balancer Configuration:**
- **Type**: Application Load Balancer (Layer 7)
- **Scheme**: Internet-facing
- **Protocol**: HTTP (Port 80 → 9000)
- **Health Check**: HTTP on `/` endpoint
- **Target Type**: EC2 instances

**Parameters Set:**
- Health check interval: 30 seconds
- Health check timeout: 5 seconds
- Healthy threshold: 2 consecutive successes
- Unhealthy threshold: 3 consecutive failures
- Success codes: 200

**Parameters NOT Set:**
- SSL/TLS termination (HTTP only)
- WAF integration
- Access logging
- Sticky sessions
- Cross-zone load balancing (using defaults)

### Docker Configuration (`docker/Dockerfile`)

**Production Features:**
- **Base Image**: OpenJDK 11 JRE Slim
- **Security**: Non-root user execution
- **Health Checks**: Integrated curl-based health monitoring
- **Optimization**: G1GC, memory limits, headless mode
- **Port**: Exposes 9000 for application access

### GitHub Actions Workflow (`.github/workflows/deploy.yml`)

**Pipeline Stages:**
1. **Test**: Automated testing with Maven/Gradle support
2. **Build**: Compiles application and creates JAR
3. **Docker**: Builds and pushes to AWS ECR
4. **Deploy**: Deploys to EC2 using AWS Systems Manager
5. **Load Balancer**: Creates and configures ALB
6. **Health Check**: Validates deployment success

## 🔐 Security Considerations

- **IAM Roles**: Uses least-privilege IAM roles for EC2 instances
- **Security Groups**: Restricts access to necessary ports only
- **Container Security**: Non-root user execution in containers
- **SSH Keys**: Secure GitHub SSH authentication
- **AWS Credentials**: Stored as GitHub secrets

## 📊 Monitoring & Logging

### Comprehensive Logging
All scripts implement detailed logging with:
- Timestamped entries
- Log levels (INFO, WARN, ERROR, DEBUG)
- Caller information
- Centralized log files in `/tmp/deployment-logs/`

### Health Monitoring
- Application health checks on `/health` endpoint
- Load balancer target health monitoring
- Automated failure detection and alerting
- Process monitoring and restart capabilities

### Log Locations
- Deployment logs: `/tmp/deployment-logs/`
- Application logs: `/tmp/java-app.log`
- Docker logs: `docker logs java-app`

## ⚡ Failure Handling

### Script-Level Failures
- **Repository Clone Failures**: SSH key validation and retry mechanisms
- **Application Startup Failures**: Port conflict resolution and process management
- **AWS Resource Failures**: Resource existence checks and recovery
- **Network Failures**: Timeout handling and retry logic

### Infrastructure Failures
- **EC2 Instance Failures**: Automatic instance replacement
- **Load Balancer Failures**: Health check monitoring and target re-registration
- **Container Failures**: Docker restart policies and health checks
- **Deployment Failures**: Rollback capabilities and error reporting

### Monitoring & Alerting
- Real-time health check monitoring
- Application process monitoring
- Resource utilization tracking
- Automated failure notifications

## 🛠️ AWS Resources Created

1. **EC2 Instances**: t2.micro instances with Java application
2. **Application Load Balancer**: Internet-facing ALB with HTTP listener
3. **Target Groups**: Health-checked targets on port 9000
4. **Security Groups**: Configured for HTTP and SSH access
5. **ECR Repository**: Docker image storage

## 📈 Load Balancer Decision Rationale

**Why Application Load Balancer:**
- Layer 7 routing capabilities
- Health check support for HTTP endpoints
- Integration with AWS services
- Cost-effective for HTTP traffic
- Support for multiple availability zones

**Health Check Configuration:**
- **Path**: `/` (application root)
- **Interval**: 30 seconds (balanced between responsiveness and resource usage)
- **Timeout**: 5 seconds (adequate for simple HTTP responses)
- **Thresholds**: 2 healthy, 3 unhealthy (quick recovery, avoid flapping)

## 🧪 Testing

### Local Testing
```bash
# Test application locally
./scripts/deploy.sh local
curl http://localhost:9000
curl http://localhost:9000/health
```

### EC2 Testing
```bash
# Deploy to EC2
./scripts/deploy.sh ec2
# Check application logs
./scripts/view-logs.sh
```

### Load Balancer Testing
```bash
# Full deployment
./scripts/deploy.sh full
# Test load balancer endpoint
curl http://[ALB-DNS-NAME]
```

## 🔍 Troubleshooting

### Common Issues

1. **SSH Authentication Fails**
   - Verify SSH keys are configured for GitHub
   - Check SSH agent is running
   - Validate repository URL format

2. **Port 9000 Already in Use**
   - Script automatically kills existing processes
   - Check for other applications using the port
   - Review process cleanup in logs

3. **AWS Resource Creation Fails**
   - Verify AWS credentials and permissions
   - Check VPC and subnet configurations
   - Ensure security group rules allow required access

4. **Application Health Checks Fail**
   - Verify application starts correctly
   - Check security group allows port 9000 access
   - Review application logs for startup errors

### Log Analysis
```bash
# View deployment logs
tail -f /tmp/deployment-logs/deploy-*.log

# View application logs
tail -f /tmp/java-app.log

# View container logs
docker logs java-app
```

```bash
cp .env.example .env
```

**Required Variables:**
- `AWS_ACCESS_KEY_ID`: Your AWS access key
- `AWS_SECRET_ACCESS_KEY`: Your AWS secret key
- `AWS_REGION`: ap-south-1 (pre-configured)
- `AWS_ACCOUNT_ID`: 738759549338 (pre-configured)
- `GITHUB_REPO_URL`: SSH URL of your GitHub repository
- `EC2_KEY_PAIR_NAME`: Name of your EC2 key pair
- `VPC_ID`: Your VPC ID (create if needed)
- `SUBNET_ID_1`: First subnet ID for load balancer
- `SUBNET_ID_2`: Second subnet ID for load balancer
- `SECURITY_GROUP_ID`: Security group allowing ports 22, 80, 9000

### 2. AWS Resources Setup

Before running the scripts, ensure you have:
- **VPC** with at least 2 subnets in different AZs
- **Security Group** with inbound rules:
  - Port 22 (SSH)
  - Port 80 (HTTP)
  - Port 9000 (Application)
- **EC2 Key Pair** for instance access

### 3. GitHub Repository

Your repository should contain:
- Java application source code
- `build/libs/project.jar` file
- Proper Maven/Gradle build configuration

## Usage

### Local Development

1. **Clone and start application locally:**
   ```bash
   ./scripts/deploy.sh local
   ```

2. **Build Docker image:**
   ```bash
   cd docker
   docker build -t java-app .
   docker run -p 9000:9000 java-app
   ```

### AWS Deployment

1. **Full deployment (clone + build + deploy):**
   ```bash
   ./scripts/deploy.sh full
   ```

2. **Deploy to existing EC2:**
   ```bash
   ./scripts/deploy.sh ec2
   ```

3. **Create load balancer only:**
   ```bash
   ./scripts/create-elb.sh
   ```

### GitHub Actions

Push to `main` branch triggers automatic deployment:
- Builds Docker image
- Pushes to ECR
- Updates EC2 instances
- Configures load balancer

## Script Details

### deploy.sh
Main orchestration script with modes:
- `local`: Clone and run locally
- `ec2`: Deploy to EC2
- `full`: Complete deployment with ELB

### Error Handling
- Validates prerequisites
- Checks AWS connectivity
- Validates repository access
- Monitors application startup
- Logs all operations

### Logging
All scripts log to:
- Console (colored output)
- Log files in `/tmp/deployment-logs/`

## Load Balancer Configuration

### Parameters Set:
- **Type**: Application Load Balancer
- **Scheme**: Internet-facing
- **Target Type**: Instance
- **Health Check**: HTTP on port 9000
- **Health Check Path**: /
- **Healthy Threshold**: 2
- **Unhealthy Threshold**: 3
- **Timeout**: 5 seconds
- **Interval**: 30 seconds

### Parameters Not Set:
- **SSL/TLS**: Not configured (add later for production)
- **WAF**: Not attached (add for security)
- **Access Logs**: Disabled (enable for production monitoring)
- **Cross-Zone Load Balancing**: Uses default

## Assumptions and Decisions

1. **Java Version**: Assuming Java 11+ (can be modified in Dockerfile)
2. **Application Port**: 9000 (as specified)
3. **Health Check**: Using root path `/` (modify if app has specific health endpoint)
4. **Instance Type**: t3.micro (cost-effective, change for production)
5. **OS**: Amazon Linux 2 (reliable and AWS-optimized)
6. **Repository Structure**: Standard Maven/Gradle with JAR in `build/libs/`
7. **Network**: Using default VPC (specify custom VPC in production)
8. **Security**: Basic security group (enhance for production)

## Troubleshooting

### Common Issues:

1. **SSH Key Issues**
   ```bash
   ssh-add ~/.ssh/id_rsa
   ssh -T git@github.com
   ```

2. **AWS Permissions**
   ```bash
   aws sts get-caller-identity
   ```

3. **Application Not Starting**
   ```bash
   tail -f /tmp/deployment-logs/java-app.log
   ```

4. **Load Balancer Health Checks Failing**
   - Check security group rules
   - Verify application is running on port 9000
   - Check target group health

### Log Locations:
- Deployment logs: `/tmp/deployment-logs/`
- Application logs: `/tmp/java-app.log`
- Docker logs: `docker logs <container_id>`

## Security Considerations

⚠️ **Important**: This is a basic setup. For production:
- Use IAM roles instead of access keys
- Enable HTTPS/SSL
- Implement proper security groups
- Enable CloudTrail and CloudWatch
- Use secrets management
- Implement network ACLs
- Enable VPC flow logs

## Support

For issues or questions:
1. Check logs in `/tmp/deployment-logs/`
2. Verify AWS resources in console
3. Test connectivity manually
4. Review GitHub Actions logs
