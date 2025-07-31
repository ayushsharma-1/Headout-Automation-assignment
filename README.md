# Java Application Deployment Pipeline

This project provides a complete deployment pipeline for a Java application from GitHub to AWS with load balancing.

## Project Structure

```
Headout/
├── scripts/
│   ├── deploy.sh           # Main deployment script
│   ├── clone-repo.sh       # Repository cloning script
│   ├── start-java-app.sh   # Java application startup script
│   └── create-elb.sh       # AWS ELB creation script
├── docker/
│   ├── Dockerfile          # Docker configuration
│   └── docker-compose.yml  # Docker compose for local testing
├── aws/
│   ├── elb-config.json     # Load balancer configuration
│   └── user-data.sh        # EC2 instance initialization script
├── github/
│   └── workflows/
│       └── deploy.yml      # GitHub Actions CI/CD pipeline
├── test-app/
│   ├── src/
│   │   └── main/
│   │       └── java/
│   │           └── TestServer.java
│   ├── build/
│   │   └── libs/
│   │       └── project.jar  # Test JAR file
│   └── pom.xml             # Maven configuration for test app
├── .env.example            # Environment variables template
├── .gitignore             # Git ignore file
└── README.md              # This file
```

## Prerequisites

1. **AWS CLI** installed and configured
2. **Docker** installed
3. **Java 11+** installed
4. **Git** configured with SSH keys
5. **GitHub** repository access

## Configuration

### 1. Environment Variables

Copy `.env.example` to `.env` and fill in the required values:

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
