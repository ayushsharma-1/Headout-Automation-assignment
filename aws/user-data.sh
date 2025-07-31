#!/bin/bash
# EC2 User Data Script for Java Application
# This script runs when the EC2 instance first starts

# Update the system
yum update -y

# Install Java 11
yum install -y java-11-amazon-corretto

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install git
yum install -y git

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install additional utilities
yum install -y htop curl wget unzip

# Create application directory
mkdir -p /opt/java-app
chown ec2-user:ec2-user /opt/java-app

# Create systemd service for Java app
cat > /etc/systemd/system/java-app.service << 'EOF'
[Unit]
Description=Java Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/java-app
ExecStart=/usr/bin/java -Xmx512m -Xms256m -XX:+UseG1GC -Djava.awt.headless=true -jar project.jar
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable the service (don't start it yet, as the JAR file isn't there)
systemctl daemon-reload
systemctl enable java-app

# Create log directory
mkdir -p /var/log/java-app
chown ec2-user:ec2-user /var/log/java-app

# Set up log rotation
cat > /etc/logrotate.d/java-app << 'EOF'
/var/log/java-app/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF

# Configure CloudWatch agent (optional)
# Uncomment if you want to send logs to CloudWatch
# wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
# rpm -U ./amazon-cloudwatch-agent.rpm

# Signal that the instance is ready
/opt/aws/bin/cfn-signal -e $? --stack ${AWS::StackName} --resource AutoScalingGroup --region ${AWS::Region} || true

echo "EC2 initialization completed at $(date)" >> /var/log/user-data.log
