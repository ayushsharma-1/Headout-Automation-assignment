#!/bin/bash

# Script to start Java application
# Usage: ./start-java-app.sh [jar-file-path] [port]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_DIR="/tmp/deployment-logs"
LOG_FILE="$LOG_DIR/start-java-app-$(date +%Y%m%d-%H%M%S).log"
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

# Validate prerequisites
validate_prerequisites() {
    log "INFO" "Validating prerequisites for Java application startup..."
    
    # Check if Java is installed
    if ! command -v java &> /dev/null; then
        error_exit "Java is not installed. Please install Java 11 or higher."
    fi
    
    # Check Java version
    local java_version=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2)
    log "INFO" "Java version: $java_version"
    
    # Check if Java version is 11 or higher
    local java_major_version=$(echo "$java_version" | cut -d'.' -f1)
    if [[ "$java_major_version" -lt 11 ]] && [[ "$java_version" != "1.8"* ]]; then
        log "WARN" "Java version might be too old. Java 11+ is recommended."
    fi
    
    log "INFO" "Prerequisites validation completed"
}

# Check if port is available
check_port_availability() {
    local port="$1"
    
    log "INFO" "Checking if port $port is available..."
    
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        log "WARN" "Port $port is already in use"
        
        # Try to find the process using the port
        local pid=$(lsof -t -i:"$port" 2>/dev/null || true)
        if [[ -n "$pid" ]]; then
            local process_info=$(ps -p "$pid" -o pid,ppid,cmd --no-headers 2>/dev/null || echo "Unknown process")
            log "INFO" "Process using port $port: $process_info"
            
            # Ask if we should kill the existing process
            log "WARN" "Attempting to stop existing process on port $port..."
            if kill "$pid" 2>/dev/null; then
                log "INFO" "Successfully stopped process $pid"
                sleep 3
                
                # Double check if port is now free
                if netstat -tuln 2>/dev/null | grep -q ":$port "; then
                    log "WARN" "Port $port is still in use after stopping process"
                    return 1
                else
                    log "INFO" "Port $port is now available"
                    return 0
                fi
            else
                log "ERROR" "Failed to stop process $pid"
                return 1
            fi
        else
            log "ERROR" "Could not identify process using port $port"
            return 1
        fi
    else
        log "INFO" "Port $port is available"
        return 0
    fi
}

# Validate JAR file
validate_jar_file() {
    local jar_file="$1"
    
    log "INFO" "Validating JAR file: $jar_file"
    
    # Check if file exists
    if [[ ! -f "$jar_file" ]]; then
        error_exit "JAR file not found: $jar_file"
    fi
    
    # Check if file is readable
    if [[ ! -r "$jar_file" ]]; then
        error_exit "JAR file is not readable: $jar_file"
    fi
    
    # Get file size
    local file_size=$(stat -f%z "$jar_file" 2>/dev/null || stat -c%s "$jar_file" 2>/dev/null || echo "unknown")
    log "INFO" "JAR file size: $file_size bytes"
    
    # Check if it's a valid JAR file
    if ! file "$jar_file" | grep -q -E "(Java archive|Zip archive)"; then
        log "WARN" "File might not be a valid JAR archive"
    fi
    
    # Try to list JAR contents to verify it's valid
    if jar -tf "$jar_file" > /dev/null 2>&1; then
        log "INFO" "JAR file validation successful"
    else
        log "WARN" "JAR file might be corrupted or invalid"
    fi
    
    # Check for Main-Class in manifest
    local main_class=$(jar -xf "$jar_file" META-INF/MANIFEST.MF 2>/dev/null && grep "Main-Class:" META-INF/MANIFEST.MF 2>/dev/null | cut -d' ' -f2 | tr -d '\r\n' || echo "")
    if [[ -n "$main_class" ]]; then
        log "INFO" "Main class found in manifest: $main_class"
        rm -f META-INF/MANIFEST.MF 2>/dev/null || true
        rmdir META-INF 2>/dev/null || true
    else
        log "WARN" "No Main-Class found in JAR manifest"
    fi
}

# Start Java application
start_java_application() {
    local jar_file="$1"
    local port="$2"
    local app_log="/tmp/java-app.log"
    local pid_file="/tmp/java-app.pid"
    
    log "INFO" "Starting Java application..."
    log "INFO" "JAR file: $jar_file"
    log "INFO" "Expected port: $port"
    log "INFO" "Application log: $app_log"
    log "INFO" "PID file: $pid_file"
    
    # Build Java command
    local java_cmd="java -jar $jar_file"
    
    # Add JVM options for better logging and monitoring
    local jvm_opts=(
        "-Xmx512m"  # Maximum heap size
        "-Xms256m"  # Initial heap size
        "-XX:+UseG1GC"  # Use G1 garbage collector
        "-XX:+PrintGCDetails"  # Print GC details
        "-Djava.awt.headless=true"  # Headless mode
        "-Dfile.encoding=UTF-8"  # UTF-8 encoding
    )
    
    java_cmd="java ${jvm_opts[*]} -jar $jar_file"
    
    log "INFO" "Java command: $java_cmd"
    
    # Start the application in background
    nohup $java_cmd > "$app_log" 2>&1 &
    local app_pid=$!
    
    # Save PID
    echo "$app_pid" > "$pid_file"
    log "INFO" "Application started with PID: $app_pid"
    
    # Wait for application to start
    local max_attempts=60  # 2 minutes timeout
    local attempt=0
    local startup_successful=false
    
    log "INFO" "Waiting for application to start on port $port..."
    
    while [[ $attempt -lt $max_attempts ]]; do
        # Check if process is still running
        if ! kill -0 "$app_pid" 2>/dev/null; then
            log "ERROR" "Application process died unexpectedly"
            log "ERROR" "Last 20 lines of application log:"
            tail -n 20 "$app_log" | while IFS= read -r line; do
                log "ERROR" "APP_LOG: $line"
            done
            return 1
        fi
        
        # Check if application is responding on the port
        if curl -s --connect-timeout 5 "http://localhost:$port" > /dev/null 2>&1; then
            startup_successful=true
            break
        fi
        
        # Alternative check using netstat
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log "INFO" "Port $port is now listening, checking HTTP response..."
        fi
        
        sleep 2
        ((attempt++))
        
        if [[ $((attempt % 15)) -eq 0 ]]; then
            log "DEBUG" "Still waiting for application startup... (attempt $attempt/$max_attempts)"
            log "DEBUG" "Last 5 lines of application log:"
            tail -n 5 "$app_log" | while IFS= read -r line; do
                log "DEBUG" "APP_LOG: $line"
            done
        fi
    done
    
    if [[ "$startup_successful" == "true" ]]; then
        log "INFO" "Application started successfully and is responding on port $port"
        
        # Test the application
        local response=$(curl -s "http://localhost:$port" 2>/dev/null || echo "No response")
        log "INFO" "Application response: ${response:0:100}..."
        
        # Show application info
        log "INFO" "Application startup completed"
        log "INFO" "- PID: $app_pid"
        log "INFO" "- Port: $port"
        log "INFO" "- URL: http://localhost:$port"
        log "INFO" "- Log file: $app_log"
        log "INFO" "- PID file: $pid_file"
        
        return 0
    else
        log "ERROR" "Application failed to start within timeout period"
        log "ERROR" "Process status: $(kill -0 "$app_pid" 2>/dev/null && echo "running" || echo "not running")"
        log "ERROR" "Last 20 lines of application log:"
        tail -n 20 "$app_log" | while IFS= read -r line; do
            log "ERROR" "APP_LOG: $line"
        done
        
        # Kill the process if it's still running
        if kill -0 "$app_pid" 2>/dev/null; then
            log "INFO" "Stopping failed application process..."
            kill "$app_pid" 2>/dev/null || true
        fi
        
        return 1
    fi
}

# Stop existing Java application
stop_existing_application() {
    local pid_file="/tmp/java-app.pid"
    
    if [[ -f "$pid_file" ]]; then
        local old_pid=$(cat "$pid_file")
        log "INFO" "Found existing application PID: $old_pid"
        
        if kill -0 "$old_pid" 2>/dev/null; then
            log "INFO" "Stopping existing application..."
            kill "$old_pid" 2>/dev/null || true
            
            # Wait for process to stop
            local wait_count=0
            while kill -0 "$old_pid" 2>/dev/null && [[ $wait_count -lt 10 ]]; do
                sleep 1
                ((wait_count++))
            done
            
            if kill -0 "$old_pid" 2>/dev/null; then
                log "WARN" "Force killing application process..."
                kill -9 "$old_pid" 2>/dev/null || true
            fi
            
            log "INFO" "Existing application stopped"
        else
            log "INFO" "Previous application process not running"
        fi
        
        rm -f "$pid_file"
    fi
}

# Main function
main() {
    local jar_file="${1:-build/libs/project.jar}"
    local port="${2:-9000}"
    
    # Load environment variables if available
    if [[ -f .env ]]; then
        source .env
        jar_file="${JAR_PATH:-$jar_file}"
        port="${APP_PORT:-$port}"
    fi
    
    log "INFO" "Starting Java application startup process"
    log "INFO" "JAR file: $jar_file"
    log "INFO" "Port: $port"
    
    # Validate prerequisites
    validate_prerequisites
    
    # Validate JAR file
    validate_jar_file "$jar_file"
    
    # Stop any existing application
    stop_existing_application
    
    # Check port availability
    if ! check_port_availability "$port"; then
        error_exit "Port $port is not available"
    fi
    
    # Start the application
    if start_java_application "$jar_file" "$port"; then
        log "INFO" "Java application startup completed successfully"
        echo "Application is running at: http://localhost:$port"
    else
        error_exit "Failed to start Java application"
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
