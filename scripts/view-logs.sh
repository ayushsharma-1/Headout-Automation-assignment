#!/bin/bash

# Script to view deployment and application logs
# Usage: ./view-logs.sh [deployment|app|all]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display logs with color
show_logs() {
    local log_type="$1"
    local log_path="$2"
    
    echo -e "${BLUE}=== $log_type Logs ===${NC}"
    
    if [[ -f "$log_path" ]]; then
        echo -e "${GREEN}Log file: $log_path${NC}"
        echo ""
        tail -n 50 "$log_path" | while IFS= read -r line; do
            if echo "$line" | grep -q "ERROR"; then
                echo -e "${RED}$line${NC}"
            elif echo "$line" | grep -q "WARN"; then
                echo -e "${YELLOW}$line${NC}"
            elif echo "$line" | grep -q "INFO"; then
                echo -e "${GREEN}$line${NC}"
            else
                echo "$line"
            fi
        done
    else
        echo -e "${YELLOW}Log file not found: $log_path${NC}"
    fi
    echo ""
}

# Main function
main() {
    local log_type="${1:-all}"
    
    case "$log_type" in
        "deployment")
            echo -e "${BLUE}Showing deployment logs...${NC}"
            echo ""
            
            # Find latest deployment log
            if [[ -d "/tmp/deployment-logs" ]]; then
                local latest_log=$(ls -t /tmp/deployment-logs/deploy-*.log 2>/dev/null | head -n1 || echo "")
                if [[ -n "$latest_log" ]]; then
                    show_logs "Latest Deployment" "$latest_log"
                else
                    echo -e "${YELLOW}No deployment logs found${NC}"
                fi
                
                # Show all deployment logs
                echo -e "${BLUE}All deployment logs:${NC}"
                ls -la /tmp/deployment-logs/ 2>/dev/null || echo "No logs directory found"
            else
                echo -e "${YELLOW}No deployment logs directory found${NC}"
            fi
            ;;
            
        "app")
            echo -e "${BLUE}Showing application logs...${NC}"
            echo ""
            
            # Local application log
            show_logs "Local Application" "/tmp/java-app.log"
            
            # EC2 application log (if accessible)
            if [[ -f "/tmp/ec2-public-ip.txt" ]]; then
                local ec2_ip=$(cat /tmp/ec2-public-ip.txt)
                echo -e "${BLUE}EC2 Application logs at $ec2_ip:${NC}"
                echo "To view EC2 logs, run:"
                echo "ssh -i ~/.ssh/your-key.pem ec2-user@$ec2_ip 'tail -f /opt/java-app/app.log'"
            fi
            ;;
            
        "all")
            echo -e "${BLUE}Showing all logs...${NC}"
            echo ""
            
            # Deployment logs
            if [[ -d "/tmp/deployment-logs" ]]; then
                local latest_deploy_log=$(ls -t /tmp/deployment-logs/deploy-*.log 2>/dev/null | head -n1 || echo "")
                if [[ -n "$latest_deploy_log" ]]; then
                    show_logs "Latest Deployment" "$latest_deploy_log"
                fi
                
                local latest_elb_log=$(ls -t /tmp/deployment-logs/create-elb-*.log 2>/dev/null | head -n1 || echo "")
                if [[ -n "$latest_elb_log" ]]; then
                    show_logs "Latest ELB Creation" "$latest_elb_log"
                fi
            fi
            
            # Application logs
            show_logs "Application" "/tmp/java-app.log"
            
            # Show running processes
            echo -e "${BLUE}=== Running Java Processes ===${NC}"
            ps aux | grep java | grep -v grep || echo "No Java processes found"
            echo ""
            
            # Show network status
            echo -e "${BLUE}=== Network Status ===${NC}"
            netstat -tuln | grep :9000 || echo "No process listening on port 9000"
            echo ""
            
            # Show AWS resources if available
            if [[ -f "/tmp/alb-dns.txt" ]]; then
                local alb_dns=$(cat /tmp/alb-dns.txt)
                echo -e "${BLUE}=== AWS Resources ===${NC}"
                echo "Load Balancer DNS: $alb_dns"
                echo "Test URL: http://$alb_dns"
            fi
            
            if [[ -f "/tmp/ec2-public-ip.txt" ]]; then
                local ec2_ip=$(cat /tmp/ec2-public-ip.txt)
                echo "EC2 Public IP: $ec2_ip"
                echo "Direct URL: http://$ec2_ip:9000"
            fi
            echo ""
            ;;
            
        *)
            echo "Usage: $0 [deployment|app|all]"
            echo ""
            echo "  deployment  - Show deployment script logs"
            echo "  app         - Show application logs"
            echo "  all         - Show all logs and status (default)"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
