#!/bin/bash

# Script to clone repository using SSH
# Usage: ./clone-repo.sh <repository-url> [target-directory]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_DIR="/tmp/deployment-logs"
LOG_FILE="$LOG_DIR/clone-repo-$(date +%Y%m%d-%H%M%S).log"
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
    log "INFO" "Validating prerequisites for repository cloning..."
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        error_exit "Git is not installed. Please install git to continue."
    fi
    
    # Check SSH agent and keys
    if ! ssh-add -l &> /dev/null; then
        log "WARN" "SSH agent is not running or no keys loaded"
        log "INFO" "Attempting to start SSH agent and load default key..."
        
        # Try to load default SSH key
        if [[ -f ~/.ssh/id_rsa ]]; then
            eval "$(ssh-agent -s)" 2>> "$LOG_FILE"
            ssh-add ~/.ssh/id_rsa 2>> "$LOG_FILE" || log "WARN" "Failed to add SSH key"
        else
            log "WARN" "No default SSH key found at ~/.ssh/id_rsa"
        fi
    fi
    
    log "INFO" "Prerequisites validation completed"
}

# Test SSH connectivity to GitHub
test_github_ssh() {
    log "INFO" "Testing SSH connectivity to GitHub..."
    
    local ssh_test_output
    if ssh_test_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -T git@github.com 2>&1); then
        if echo "$ssh_test_output" | grep -q "successfully authenticated"; then
            log "INFO" "GitHub SSH authentication successful"
            return 0
        fi
    fi
    
    log "ERROR" "GitHub SSH authentication failed"
    log "ERROR" "SSH test output: $ssh_test_output"
    log "INFO" "Please ensure:"
    log "INFO" "1. SSH key is added to your GitHub account"
    log "INFO" "2. SSH agent is running with your key loaded"
    log "INFO" "3. Repository URL is correct and accessible"
    
    return 1
}

# Clone repository with retries
clone_repository() {
    local repo_url="$1"
    local target_dir="$2"
    local max_retries=3
    local retry_count=0
    
    log "INFO" "Cloning repository: $repo_url"
    log "INFO" "Target directory: $target_dir"
    
    # Remove existing directory if it exists
    if [[ -d "$target_dir" ]]; then
        log "WARN" "Target directory '$target_dir' already exists, removing..."
        rm -rf "$target_dir" || error_exit "Failed to remove existing directory"
    fi
    
    # Attempt to clone with retries
    while [[ $retry_count -lt $max_retries ]]; do
        log "INFO" "Clone attempt $((retry_count + 1))/$max_retries"
        
        if git clone "$repo_url" "$target_dir" 2>> "$LOG_FILE"; then
            log "INFO" "Repository cloned successfully"
            
            # Verify the clone
            if [[ -d "$target_dir/.git" ]]; then
                local commit_hash=$(cd "$target_dir" && git rev-parse HEAD)
                local branch=$(cd "$target_dir" && git branch --show-current)
                log "INFO" "Clone verified - Branch: $branch, Commit: ${commit_hash:0:8}"
                return 0
            else
                log "ERROR" "Clone verification failed - .git directory not found"
            fi
        else
            log "WARN" "Clone attempt $((retry_count + 1)) failed"
        fi
        
        ((retry_count++))
        if [[ $retry_count -lt $max_retries ]]; then
            log "INFO" "Retrying in 5 seconds..."
            sleep 5
        fi
    done
    
    error_exit "Failed to clone repository after $max_retries attempts"
}

# Validate repository structure
validate_repository() {
    local repo_dir="$1"
    
    log "INFO" "Validating repository structure..."
    
    cd "$repo_dir" || error_exit "Failed to change to repository directory"
    
    # Check for JAR file
    local jar_path="build/libs/project.jar"
    if [[ -f "$jar_path" ]]; then
        log "INFO" "Found JAR file at $jar_path"
        local jar_size=$(stat -f%z "$jar_path" 2>/dev/null || stat -c%s "$jar_path" 2>/dev/null || echo "unknown")
        log "INFO" "JAR file size: $jar_size bytes"
    else
        log "WARN" "JAR file not found at $jar_path"
        log "INFO" "Repository structure:"
        find . -name "*.jar" -type f | head -10 | while read -r jar_file; do
            log "INFO" "  Found JAR: $jar_file"
        done
    fi
    
    # Check for common build files
    local build_files=("pom.xml" "build.gradle" "build.gradle.kts" "Makefile")
    for build_file in "${build_files[@]}"; do
        if [[ -f "$build_file" ]]; then
            log "INFO" "Found build file: $build_file"
        fi
    done
    
    log "INFO" "Repository validation completed"
}

# Main function
main() {
    local repo_url="${1:-}"
    local target_dir="${2:-temp-repo}"
    
    if [[ -z "$repo_url" ]]; then
        # Try to load from environment
        if [[ -f .env ]]; then
            source .env
            repo_url="$GITHUB_REPO_URL"
        fi
        
        if [[ -z "$repo_url" ]]; then
            error_exit "Usage: $0 <repository-url> [target-directory]"
        fi
    fi
    
    log "INFO" "Starting repository clone process"
    log "INFO" "Repository URL: $repo_url"
    log "INFO" "Target directory: $target_dir"
    
    # Validate prerequisites
    validate_prerequisites
    
    # Test GitHub SSH connectivity
    if ! test_github_ssh; then
        error_exit "GitHub SSH connectivity test failed"
    fi
    
    # Clone repository
    clone_repository "$repo_url" "$target_dir"
    
    # Validate repository structure
    validate_repository "$target_dir"
    
    log "INFO" "Repository clone process completed successfully"
    echo "Repository cloned to: $(realpath "$target_dir")"
}

# Error handling for script interruption
cleanup() {
    log "INFO" "Cleaning up on script exit..."
}

trap cleanup EXIT

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
