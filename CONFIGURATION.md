# CONFIGURATION CHECKLIST

## ✅ Files Created
- All deployment scripts
- Docker configuration
- GitHub Actions workflow
- Test Java application
- Documentation

## ⚠️ REQUIRED ACTIONS BEFORE DEPLOYMENT

### 1. Environment Variables (.env file)
```bash
# Edit this file with your values
nano .env
```

**MUST CHANGE:**
- `AWS_SECRET_ACCESS_KEY` - Add your AWS secret key
- `GITHUB_REPO_URL` - Change to your actual repository
- `EC2_KEY_PAIR_NAME` - Your EC2 key pair name
- `VPC_ID` - Your VPC ID
- `SUBNET_ID_1` - First subnet ID 
- `SUBNET_ID_2` - Second subnet ID (different AZ)
- `SECURITY_GROUP_ID` - Your security group ID

### 2. AWS Resources to Create

#### A. EC2 Key Pair
```bash
aws ec2 create-key-pair --key-name my-java-app-key --query 'KeyMaterial' --output text > ~/.ssh/my-java-app-key.pem
chmod 400 ~/.ssh/my-java-app-key.pem
```

#### B. Security Group
```bash
# Create security group
aws ec2 create-security-group --group-name java-app-sg --description "Java app security group"

# Add rules (replace sg-xxxxxxxxx with actual ID)
aws ec2 authorize-security-group-ingress --group-id sg-xxxxxxxxx --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id sg-xxxxxxxxx --protocol tcp --port 80 --cidr 0.0.0.0/0  
aws ec2 authorize-security-group-ingress --group-id sg-xxxxxxxxx --protocol tcp --port 9000 --cidr 0.0.0.0/0
```

#### C. VPC and Subnets (if not using default)
```bash
# Get default VPC ID
aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text

# Get subnet IDs in different AZs
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxxxxxx" --query 'Subnets[*].[SubnetId,AvailabilityZone]' --output table
```

### 3. GitHub Configuration

#### A. Repository Setup
1. Create/use existing GitHub repository
2. Add your Java application code
3. Ensure `build/libs/project.jar` exists or will be built

#### B. GitHub Secrets (for Actions)
Go to: Repository → Settings → Secrets and variables → Actions

Add these secrets:
- `AWS_ACCESS_KEY_ID`: AKIA2YAMAEGNMHFB2JMV
- `AWS_SECRET_ACCESS_KEY`: [your secret key]
- `EC2_KEY_PAIR_NAME`: [your key pair name]
- `SECURITY_GROUP_ID`: [your security group ID]
- `SUBNET_ID_1`: [your subnet ID]

### 4. Local Development Setup

#### A. SSH Key for GitHub
```bash
# Generate if you don't have one
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"

# Add to SSH agent
ssh-add ~/.ssh/id_rsa

# Add public key to GitHub
cat ~/.ssh/id_rsa.pub
# Copy this to GitHub → Settings → SSH and GPG keys
```

#### B. AWS CLI Configuration
```bash
aws configure
# Enter your credentials when prompted
```

## 🚀 DEPLOYMENT STEPS

### Step 1: Initial Setup
```bash
./setup.sh
# Review output and fix any issues
```

### Step 2: Configure Environment
```bash
# Edit .env with your values
cp .env.example .env
nano .env
```

### Step 3: Test Locally
```bash
./scripts/deploy.sh local
# Should start application at http://localhost:9000
```

### Step 4: Deploy to AWS
```bash
./scripts/deploy.sh full
# Creates EC2 instance and load balancer
```

### Step 5: Verify Deployment
```bash
./scripts/view-logs.sh
# Check logs for any issues
```

## 📋 VERIFICATION CHECKLIST

- [ ] AWS credentials working (`aws sts get-caller-identity`)
- [ ] GitHub SSH working (`ssh -T git@github.com`)  
- [ ] Docker running (`docker version`)
- [ ] Java installed (`java -version`)
- [ ] .env file configured with real values
- [ ] AWS resources created (VPC, subnets, security group, key pair)
- [ ] GitHub repository accessible
- [ ] GitHub secrets configured (if using Actions)

## 🔍 TESTING

### Local Test
```bash
./scripts/deploy.sh local
curl http://localhost:9000
curl http://localhost:9000/health
```

### EC2 Test
```bash
./scripts/deploy.sh ec2
# Wait for completion, then test using EC2 public IP
```

### Load Balancer Test
```bash
./scripts/deploy.sh full
# Wait for completion, then test using load balancer DNS
```

## 📞 SUPPORT

If you encounter issues:

1. **Check logs**: `./scripts/view-logs.sh`
2. **Verify AWS resources**: Check AWS console
3. **Test connectivity**: `ssh -T git@github.com`
4. **Check prerequisites**: `./setup.sh`

## 🔒 SECURITY NOTES

⚠️ **IMPORTANT**: This setup is for development/testing!

For production:
- Use IAM roles instead of access keys
- Enable HTTPS/SSL
- Restrict security group access
- Enable logging and monitoring
- Use private subnets
- Implement backup strategies
