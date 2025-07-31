# Deployment Guide - Java Application to AWS

## Quick Start

### 1. Initial Setup
```bash
# Run the setup script to check prerequisites
./setup.sh

# Edit environment variables
cp .env.example .env
nano .env  # or your preferred editor
```

### 2. Required Environment Variables

Fill these values in your `.env` file:

```bash
# AWS Configuration (pre-filled for your account)
AWS_ACCESS_KEY_ID=AKIA2YAMAEGNMHFB2JMV
AWS_SECRET_ACCESS_KEY=YOUR_SECRET_KEY_HERE  # ⚠️ ADD YOUR SECRET KEY
AWS_REGION=ap-south-1
AWS_ACCOUNT_ID=738759549338

# GitHub Repository (⚠️ CHANGE TO YOUR REPO)
GITHUB_REPO_URL=git@github.com:username/repository.git

# EC2 Configuration (⚠️ CREATE THESE RESOURCES)
EC2_KEY_PAIR_NAME=your-key-pair-name
VPC_ID=vpc-xxxxxxxxx
SUBNET_ID_1=subnet-xxxxxxxxx  # Different AZ
SUBNET_ID_2=subnet-yyyyyyyyy  # Different AZ  
SECURITY_GROUP_ID=sg-xxxxxxxxx
```

### 3. AWS Resources to Create

#### VPC and Networking (if not using default VPC)
```bash
# Create VPC
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=java-app-vpc}]'

# Create subnets in different AZs
aws ec2 create-subnet --vpc-id vpc-xxxxxxxxx --cidr-block 10.0.1.0/24 --availability-zone ap-south-1a
aws ec2 create-subnet --vpc-id vpc-xxxxxxxxx --cidr-block 10.0.2.0/24 --availability-zone ap-south-1b
```

#### Security Group
```bash
# Create security group
aws ec2 create-security-group \
  --group-name java-app-sg \
  --description "Security group for Java application" \
  --vpc-id vpc-xxxxxxxxx

# Add inbound rules
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0  # ⚠️ Restrict to your IP in production

aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 9000 \
  --cidr 0.0.0.0/0
```

#### EC2 Key Pair
```bash
# Create key pair
aws ec2 create-key-pair --key-name your-key-pair-name --query 'KeyMaterial' --output text > ~/.ssh/your-key-pair-name.pem
chmod 400 ~/.ssh/your-key-pair-name.pem
```

### 4. Deployment Options

#### Option A: Local Testing
```bash
./scripts/deploy.sh local
```
This will:
- Clone your repository
- Start the Java application locally on port 9000
- Test at http://localhost:9000

#### Option B: EC2 Deployment
```bash
./scripts/deploy.sh ec2
```
This will:
- Clone repository
- Create/start EC2 instance
- Deploy application to EC2
- Application accessible via EC2 public IP:9000

#### Option C: Full Deployment with Load Balancer
```bash
./scripts/deploy.sh full
```
This will:
- All of Option B, plus:
- Create Application Load Balancer
- Create target group with health checks
- Register EC2 instance with load balancer
- Application accessible via load balancer URL

#### Option D: Load Balancer Only
```bash
./scripts/create-elb.sh
```
Creates load balancer for existing EC2 instances.

### 5. GitHub Actions Setup

Add these secrets to your GitHub repository (Settings > Secrets and variables > Actions):

```
AWS_ACCESS_KEY_ID: AKIA2YAMAEGNMHFB2JMV
AWS_SECRET_ACCESS_KEY: your-secret-key
EC2_KEY_PAIR_NAME: your-key-pair-name
SECURITY_GROUP_ID: sg-xxxxxxxxx
SUBNET_ID_1: subnet-xxxxxxxxx
```

Push to `main` branch to trigger automatic deployment.

## Detailed Configuration

### Load Balancer Settings

#### Parameters Set:
- **Type**: Application Load Balancer (Layer 7)
- **Scheme**: Internet-facing
- **Protocol**: HTTP (port 80 → 9000)
- **Target Type**: EC2 instances
- **Health Check**: HTTP GET / every 30s
- **Timeout**: 5 seconds
- **Healthy Threshold**: 2 successes
- **Unhealthy Threshold**: 3 failures

#### Parameters NOT Set (Production TODO):
- **HTTPS/SSL**: Configure SSL certificate
- **WAF**: Web Application Firewall
- **Access Logs**: S3 logging
- **Sticky Sessions**: Session affinity
- **Cross-Zone Load Balancing**: Enhanced distribution

### Error Handling Features

#### Script-Level Error Handling:
- **Prerequisite Validation**: Checks for required tools and credentials
- **Retry Logic**: Automatic retries for network operations
- **Process Monitoring**: Validates application startup
- **Port Conflict Resolution**: Stops conflicting processes
- **Resource Cleanup**: Removes temporary files on exit

#### Application Health Monitoring:
- **Startup Verification**: Waits for HTTP response before marking success
- **Health Check Endpoint**: `/health` returns JSON status
- **Process Monitoring**: Validates Java process is running
- **Log Analysis**: Captures and displays application logs

#### AWS Resource Management:
- **Existing Resource Detection**: Reuses existing ALB/target groups
- **Resource Tagging**: Tags all resources for easy identification
- **State Persistence**: Saves resource IDs for reuse
- **Rollback Capability**: Manual cleanup procedures documented

### Logging and Monitoring

#### Log Locations:
```bash
# Deployment logs
/tmp/deployment-logs/deploy-YYYYMMDD-HHMMSS.log
/tmp/deployment-logs/create-elb-YYYYMMDD-HHMMSS.log

# Application logs
/tmp/java-app.log          # Local deployment
/opt/java-app/app.log      # EC2 deployment

# Process ID files
/tmp/java-app.pid          # Application process ID
/tmp/ec2-instance-id.txt   # EC2 instance ID
/tmp/alb-dns.txt           # Load balancer DNS name
```

#### Log Levels:
- **INFO**: Normal operations and status updates
- **WARN**: Non-critical issues that don't stop deployment
- **ERROR**: Critical issues that stop deployment
- **DEBUG**: Detailed troubleshooting information

### Troubleshooting

#### Common Issues:

1. **AWS Credentials Invalid**
   ```bash
   aws sts get-caller-identity
   aws configure list
   ```

2. **SSH Key Not Working**
   ```bash
   ssh-add ~/.ssh/your-key-pair-name.pem
   ssh -T git@github.com
   ```

3. **Application Not Starting**
   ```bash
   tail -f /tmp/java-app.log
   netstat -tuln | grep 9000
   ```

4. **Load Balancer Health Checks Failing**
   ```bash
   # Check security groups allow port 9000
   # Verify application responds to GET /
   curl http://instance-ip:9000/
   ```

5. **GitHub Actions Failing**
   - Check repository secrets are set
   - Verify AWS permissions
   - Check workflow logs in GitHub

### Security Considerations

#### Current Security Level: DEVELOPMENT/TESTING
⚠️ **Do not use in production without these enhancements:**

1. **Network Security**:
   - Use private subnets for application servers
   - Implement network ACLs
   - Restrict security group rules to specific IPs

2. **Access Control**:
   - Use IAM roles instead of access keys
   - Implement least privilege access
   - Enable MFA for all accounts

3. **Data Protection**:
   - Enable HTTPS/SSL
   - Use AWS Secrets Manager for sensitive data
   - Encrypt data at rest and in transit

4. **Monitoring**:
   - Enable CloudTrail for API logging
   - Set up CloudWatch alarms
   - Implement log aggregation

### Cost Optimization

#### Current Resources:
- **EC2**: 1 × t3.micro (~$8/month)
- **ALB**: ~$16/month + $0.008/LCU-hour
- **Data Transfer**: $0.09/GB outbound

#### Cost Reduction Tips:
- Use EC2 Spot Instances for non-production
- Schedule instances (stop when not needed)
- Use smaller instance types for testing
- Monitor with AWS Cost Explorer

### Scaling Considerations

#### Horizontal Scaling:
```bash
# Add more EC2 instances
aws ec2 run-instances --count 2 --instance-type t3.micro ...

# Register with target group
aws elbv2 register-targets --target-group-arn $TG_ARN --targets Id=i-xxx,Port=9000
```

#### Auto Scaling:
- Create Launch Template
- Set up Auto Scaling Group
- Configure scaling policies

#### Database Considerations:
- Current setup: In-memory only
- Production: Add RDS/DynamoDB
- Implement connection pooling

## Support and Maintenance

### Regular Tasks:
1. **Security Updates**: Keep OS and Java updated
2. **Log Rotation**: Monitor disk space usage
3. **Backup**: Implement application data backup
4. **Monitoring**: Set up alerts for failures

### Health Checks:
```bash
# Application health
curl http://your-alb-dns.ap-south-1.elb.amazonaws.com/health

# Instance health
aws elbv2 describe-target-health --target-group-arn $TG_ARN

# Load balancer status
aws elbv2 describe-load-balancers --names java-app-alb
```

### Performance Monitoring:
```bash
# View application logs
./scripts/view-logs.sh

# Monitor resource usage
top
df -h
free -m
```

---

**Remember**: This is a development/testing setup. Enhance security, monitoring, and reliability before production use!
