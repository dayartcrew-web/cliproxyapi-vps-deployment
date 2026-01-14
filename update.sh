#!/bin/bash

###############################################################################
# CLIProxyAPI Update Script for Ubuntu VPS
# Author: Sisyphus
# Version: 1.0.0
# Description: Safe and easy update of CLIProxyAPI on Ubuntu VPS
###############################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/cliproxyapi"
SERVICE_NAME="cliproxyapi"
BACKUP_DIR="/opt/cliproxyapi/backups"

###############################################################################
# Helper Functions
###############################################################################

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo."
        print_info "Please run: sudo bash update.sh"
        exit 1
    fi
}

###############################################################################
# Backup Functions
###############################################################################

create_backup() {
    print_header "Creating Backup"

    local backup_name="backup_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"

    mkdir -p $backup_path

    # Backup config file (from CLIProxyAPI directory)
    if [[ -f "$INSTALL_DIR/CLIProxyAPI/config.yaml" ]]; then
        cp $INSTALL_DIR/CLIProxyAPI/config.yaml $backup_path/
        print_success "Config file backed up"
    fi

    # Backup auth directory
    if [[ -d "$INSTALL_DIR/auths" ]]; then
        cp -r $INSTALL_DIR/auths $backup_path/
        print_success "Auth directory backed up"
    fi

    # Backup docker-compose.yml (if customized)
    if [[ -f "$INSTALL_DIR/CLIProxyAPI/docker-compose.yml" ]]; then
        cp $INSTALL_DIR/CLIProxyAPI/docker-compose.yml $backup_path/
        print_success "Docker compose file backed up"
    fi

    # Create backup info
    cat > $backup_path/backup_info.txt <<EOF
Backup created: $(date)
Version before update: $(cd $INSTALL_DIR/CLIProxyAPI && git describe --tags --always 2>/dev/null || echo "unknown")
EOF

    print_success "Backup created at: $backup_path"

    # Keep only last 10 backups
    local backup_count=$(ls -1 $BACKUP_DIR | wc -l)
    if [[ $backup_count -gt 10 ]]; then
        print_info "Cleaning old backups (keeping last 10)..."
        ls -1t $BACKUP_DIR | tail -n +11 | xargs -I {} rm -rf $BACKUP_DIR/{}
        print_success "Old backups cleaned"
    fi
}

###############################################################################
# Update Functions
###############################################################################

pull_latest() {
    print_header "Pulling Latest Changes"


    # Get current version
    local current_version=$(git describe --tags --always 2>/dev/null || echo "unknown")
    print_info "Current version: $current_version"

    # Pull latest
    git fetch origin
    local latest_version=$(git describe --tags origin/main 2>/dev/null || echo "latest")

    if git rev-parse HEAD > /dev/null 2>&1 && git rev-parse origin/main > /dev/null 2>&1; then
        local commits_behind=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)

        if [[ $commits_behind -eq 0 ]]; then
            print_success "Already up to date!"
            exit 0
        fi

        print_info "$commits_behind commits behind, updating..."
    fi

    git pull origin main

    print_success "Repository updated to latest version"
}

rebuild_docker() {
    print_header "Rebuilding Docker Container"

    # Stop current service
    print_info "Stopping current service..."
    docker_compose_exec down

    # Pull latest Docker image
    print_info "Pulling latest Docker image..."
    docker_compose_exec pull

    # Start service
    print_info "Starting service..."
    docker_compose_exec up -d

    print_success "Docker container rebuilt and started"
}

restore_backup() {
    print_header "Restoring from Backup"

    local backup_list=$(ls -1t $BACKUP_DIR)
    local backup_count=$(echo "$backup_list" | wc -l)

    if [[ $backup_count -eq 0 ]]; then
        print_error "No backups found!"
        exit 1
    fi

    echo "Available backups:"
    echo "$backup_list" | nl

    read -p "Select backup number (1-$backup_count) or 'c' to cancel: " selection

    if [[ $selection == "c" ]] || [[ $selection == "C" ]]; then
        print_info "Restore cancelled"
        exit 0
    fi

    local backup_name=$(echo "$backup_list" | sed -n "${selection}p")

    if [[ -z "$backup_name" ]]; then
        print_error "Invalid selection"
        exit 1
    fi

    local backup_path="$BACKUP_DIR/$backup_name"

    print_warning "This will restore $backup_name"
    print_warning "Current config and auths will be overwritten!"
    read -p "Continue? (y/N): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Restore cancelled"
        exit 0
    fi

    # Restore files
    cp $backup_path/config.yaml $INSTALL_DIR/CLIProxyAPI/
    rm -rf $INSTALL_DIR/auths
    cp -r $backup_path/auths $INSTALL_DIR/

    # Restart service (no cd needed)
    docker_stop
    docker_start

    print_success "Backup restored successfully"
}

###############################################################################
# Health Check
###############################################################################

health_check() {
    print_header "Running Health Check"


    # Check if container is running
    if docker compose -f "$COMPOSE_FILE" ps | grep -q "Up"; then
        print_success "Container is running"
    else
        print_error "Container is not running!"
        return 1
    fi

    # Check API endpoint
    local api_url="http://localhost:8317/v1/models"
    if curl -s -o /dev/null -w "%{http_code}" $api_url | grep -q "200\|401"; then
        print_success "API endpoint is responding"
    else
        print_error "API endpoint is not responding!"
        return 1
    fi

    # Check logs for errors
    if docker_logs --tail=50 2>&1 | grep -qi "error"; then
        print_warning "Errors found in recent logs"
        print_info "Check logs with: docker compose logs -f"
    else
        print_success "No errors in recent logs"
    fi
}

###############################################################################
# Rollback Functions
###############################################################################

rollback() {
    print_header "Rollback to Previous Version"


    if git reflog show | grep -q "pull: Fast-forward"; then
        local previous_commit=$(git reflog show | grep "pull: Fast-forward" | head -n 2 | tail -n 1 | awk '{print $1}')

        print_warning "This will rollback to commit: $previous_commit"
        read -p "Continue? (y/N): " -n 1 -r
        echo

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Rollback cancelled"
            exit 0
        fi

        git reset --hard $previous_commit

        # Rebuild
        docker_stop
        docker compose -f "$COMPOSE_FILE" pull
        docker_start

        print_success "Rollback completed"
    else
        print_error "No previous version to rollback to"
        exit 1
    fi
}

###############################################################################
# Fix Management Key
###############################################################################

fix_management_key() {
    print_header "Fixing Management Key"


    # Generate new management key
    local NEW_KEY=$(openssl rand -hex 32)
    local VPS_IP=$(hostname -I | awk '{print $1}')

    print_info "Generating new management key..."

    # Update config with new plaintext key (will be hashed on restart)
    sed -i "s/secret-key: .*/secret-key: \"$NEW_KEY\"/" config.yaml
    sed -i 's/allow-remote: false/allow-remote: true/' config.yaml
    sed -i 's/disable-control-panel: true/disable-control-panel: false/' config.yaml

    # Update api-keys.txt
    local keys_file="$INSTALL_DIR/api-keys.txt"
    if [[ -f "$keys_file" ]]; then
        # Remove old management key entries
        sed -i '/MANAGEMENT_KEY=/d' $keys_file
        sed -i '/MANAGEMENT_URL=/d' $keys_file
        sed -i '/MANAGEMENT_PANEL=/d' $keys_file
        sed -i '/Management-Key:/d' $keys_file
        sed -i '/Management Secret:/d' $keys_file

        # Add new key
        cat >> $keys_file <<EOF

# ════════════════════════════════════════════════════════════════
# Management Panel Access (Updated: $(date))
# ════════════════════════════════════════════════════════════════
MANAGEMENT_KEY=$NEW_KEY
MANAGEMENT_URL=http://${VPS_IP}:8317/management.html

# Alternative access methods:
# 1. Web UI (recommended):
#    http://${VPS_IP}:8317/management.html
#    Enter Key: $NEW_KEY
#
# 2. API Endpoints (for scripts):
#    curl -H "Authorization: Bearer $NEW_KEY" http://${VPS_IP}:8317/v0/management/proxy-url
EOF
    else
        # Create new keys file
        cat > $keys_file <<EOF
# CLIProxyAPI Credentials
# Generated on: $(date)

MANAGEMENT_KEY=$NEW_KEY
MANAGEMENT_URL=http://${VPS_IP}:8317/management.html
EOF
    fi

    chmod 600 $keys_file

    # Restart service
    print_info "Restarting service..."
    docker_restart
    sleep 5

    print_success "Management key updated!"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}NEW MANAGEMENT ACCESS${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "Management Key: ${YELLOW}$NEW_KEY${NC}"
    echo -e ""
    echo -e "Access URLs:"
    echo -e "  ${YELLOW}http://${VPS_IP}:8317/management.html${NC}"
    echo -e "  ${YELLOW}Management Key: $NEW_KEY${NC}"
    echo -e ""
    echo -e "Saved to: $keys_file"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"

    # Test
    print_info "Testing management endpoint..."
    local response=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8317/management.html")
    if [[ "$response" == "200" ]] || [[ "$response" == "301" ]] || [[ "$response" == "302" ]]; then
        print_success "Management panel is accessible!"
    else
        print_warning "Got HTTP $response - Management panel may need additional configuration"
        print_info "Try accessing: http://${VPS_IP}:8317/management.html (Key: $NEW_KEY)"
    fi
}

###############################################################################
# Show Credentials
###############################################################################

show_credentials() {
    print_header "Current Credentials"

    local keys_file="$INSTALL_DIR/api-keys.txt"
    
    if [[ -f "$keys_file" ]]; then
        cat $keys_file
    else
        print_error "Credentials file not found: $keys_file"
        print_info "Run 'Fix management key' to generate new credentials"
    fi
}

###############################################################################
# Interactive Menu
###############################################################################

show_menu() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}       CLIProxyAPI Management Console${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}── Updates ──${NC}"
    echo "  1) Check for updates"
    echo "  2) Update to latest version"
    echo "  3) Rollback to previous version"
    echo ""
    echo -e "${GREEN}── Backup/Restore ──${NC}"
    echo "  4) Create backup"
    echo "  5) Restore from backup"
    echo "  6) View backup list"
    echo ""
    echo -e "${GREEN}── Service ──${NC}"
    echo "  7) Health check"
    echo "  8) View service logs"
    echo "  9) Restart service"
    echo "  10) Stop service"
    echo "  11) Start service"
    echo ""
    echo -e "${GREEN}── Configuration ──${NC}"
    echo "  12) Edit config.yaml"
    echo "  13) View config.yaml"
    echo "  14) Fix management key (regenerate)"
    echo "  15) Show credentials"
    echo ""
    echo -e "${GREEN}── OAuth Providers ──${NC}"
    echo "  16) Login Gemini CLI"
    echo "  17) Login Antigravity"
    echo "  18) Login Claude Code"
    echo "  19) Login OpenAI Codex"
    echo "  20) Login Qwen Code"
    echo "  21) Login iFlow"
    echo "  22) List logged-in accounts"
    echo ""
    echo -e "${GREEN}── Files ──${NC}"
    echo "  23) View auth directory"
    echo "  24) View logs directory"
    echo "  25) Clear logs"
    echo ""
    echo -e "${YELLOW}── Security ──${NC}"
    echo "  26) Run security hardening"
    echo "  27) Run VPS panel security integration"
    echo "  28) Block search engine crawlers"
    echo "  29) Setup Cloudflare Turnstile (CAPTCHA)"
    echo "  30) View SECURITY.md"
    echo ""
    echo "  0) Exit"
    echo ""
}

###############################################################################
# OAuth Login Functions
###############################################################################

oauth_login() {
    local provider=$1
    local flag=$2
    
    print_header "Login to $provider"
    
    
    print_info "Starting OAuth login for $provider..."
    print_info "Copy the URL and open in your browser to complete login."
    echo ""
    
    docker_container_exec ./CLIProxyAPI $flag -no-browser
    
    echo ""
    print_info "After completing OAuth in browser, the account will be added automatically."
    print_info "Press Enter to continue..."
    read
}

list_accounts() {
    print_header "Logged-in Accounts"
    
    local auth_dir="$INSTALL_DIR/auths"
    
    if [[ -d "$auth_dir" ]]; then
        echo -e "${BLUE}Auth files in $auth_dir:${NC}"
        echo ""
        ls -la $auth_dir 2>/dev/null || echo "No auth files found"
        echo ""
        
        # Count by provider
        echo -e "${BLUE}Summary:${NC}"
        echo "  Gemini:      $(ls $auth_dir/*gemini* 2>/dev/null | wc -l) accounts"
        echo "  Antigravity: $(ls $auth_dir/*antigravity* 2>/dev/null | wc -l) accounts"
        echo "  Claude:      $(ls $auth_dir/*claude* 2>/dev/null | wc -l) accounts"
        echo "  Codex:       $(ls $auth_dir/*codex* 2>/dev/null | wc -l) accounts"
        echo "  Qwen:        $(ls $auth_dir/*qwen* 2>/dev/null | wc -l) accounts"
        echo "  iFlow:       $(ls $auth_dir/*iflow* 2>/dev/null | wc -l) accounts"
    else
        print_warning "Auth directory not found: $auth_dir"
    fi
}

###############################################################################
# File Management Functions
###############################################################################

edit_config() {
    print_header "Edit Configuration"
    
    local config_file="$INSTALL_DIR/CLIProxyAPI/config.yaml"
    
    if [[ -f "$config_file" ]]; then
        # Try different editors
        if command -v nano &> /dev/null; then
            nano "$config_file"
        elif command -v vim &> /dev/null; then
            vim "$config_file"
        elif command -v vi &> /dev/null; then
            vi "$config_file"
        else
            print_error "No text editor found (nano, vim, vi)"
            print_info "Install nano: apt-get install nano"
        fi
        
        print_info "Restart service to apply changes? (y/N)"
        read -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker_restart
            print_success "Service restarted"
        fi
    else
        print_error "Config file not found: $config_file"
    fi
}

view_config() {
    print_header "View Configuration"
    
    local config_file="$INSTALL_DIR/CLIProxyAPI/config.yaml"
    
    if [[ -f "$config_file" ]]; then
        cat "$config_file" | less
    else
        print_error "Config file not found: $config_file"
    fi
}

view_auth_dir() {
    print_header "Auth Directory"
    
    local auth_dir="$INSTALL_DIR/auths"
    
    if [[ -d "$auth_dir" ]]; then
        echo -e "${BLUE}Directory: $auth_dir${NC}"
        echo ""
        ls -lah "$auth_dir"
        echo ""
        echo -e "${BLUE}Total size: $(du -sh $auth_dir | cut -f1)${NC}"
    else
        print_warning "Auth directory not found"
    fi
}

view_logs_dir() {
    print_header "Logs Directory"
    
    local logs_dir="$INSTALL_DIR/logs"
    
    if [[ -d "$logs_dir" ]]; then
        echo -e "${BLUE}Directory: $logs_dir${NC}"
        echo ""
        ls -lah "$logs_dir"
        echo ""
        echo -e "${BLUE}Total size: $(du -sh $logs_dir | cut -f1)${NC}"
    else
        print_info "Logs directory is empty or not found"
        print_info "Logs might be in Docker: docker compose logs"
    fi
}

clear_logs() {
    print_header "Clear Logs"

    print_warning "This will clear all CLIProxyAPI logs"
    echo ""
    echo "Logs to clear:"
    echo "  1) Docker container logs (requires container restart)"
    echo "  2) Host logs directory (/opt/cliproxyapi/logs)"
    echo "  3) Both Docker and host logs"
    echo ""
    read -p "Select option (1/2/3) or N to cancel: " -n 1 -r
    echo ""
    echo ""

    case $REPLY in
        1)
            print_info "Clearing Docker container logs..."

            # Get container ID
            CONTAINER_ID=$(docker compose -f "$COMPOSE_FILE" ps -q cli-proxy-api 2>/dev/null)

            if [[ -z "$CONTAINER_ID" ]]; then
                print_error "Container not running"
                return 1
            fi

            # Truncate Docker logs (requires root)
            print_info "Truncating Docker logs for container $CONTAINER_ID..."

            # Find and truncate log file
            LOG_FILE=$(docker inspect --format='{{.LogPath}}' $CONTAINER_ID 2>/dev/null)

            if [[ -n "$LOG_FILE" ]] && [[ -f "$LOG_FILE" ]]; then
                truncate -s 0 "$LOG_FILE" 2>/dev/null && print_success "Docker logs cleared" || {
                    print_warning "Could not truncate log file directly. Recreating container..."
                    docker_stop
                    docker_start
                    print_success "Container recreated (logs cleared)"
                }
            else
                print_info "Recreating container to clear logs..."
                docker_stop
                docker_start
                print_success "Container recreated (logs cleared)"
            fi
            ;;

        2)
            print_info "Clearing host logs directory..."
            local logs_dir="$INSTALL_DIR/logs"

            if [[ -d "$logs_dir" ]]; then
                # Use find and delete to handle permission issues
                find "$logs_dir" -type f -delete 2>/dev/null && \
                    print_success "Host logs cleared" || \
                    print_error "Failed to clear logs (permission denied?)"
            else
                print_info "Logs directory not found or empty"
            fi
            ;;

        3)
            print_info "Clearing all logs..."

            # Clear Docker logs
            CONTAINER_ID=$(docker compose -f "$COMPOSE_FILE" ps -q cli-proxy-api 2>/dev/null)

            if [[ -n "$CONTAINER_ID" ]]; then
                LOG_FILE=$(docker inspect --format='{{.LogPath}}' $CONTAINER_ID 2>/dev/null)

                if [[ -n "$LOG_FILE" ]] && [[ -f "$LOG_FILE" ]]; then
                    truncate -s 0 "$LOG_FILE" 2>/dev/null || {
                        docker_stop
                        docker_start
                    }
                else
                    docker_stop
                    docker_start
                fi
                print_success "Docker logs cleared"
            fi

            # Clear host logs
            local logs_dir="$INSTALL_DIR/logs"
            if [[ -d "$logs_dir" ]]; then
                find "$logs_dir" -type f -delete 2>/dev/null
                print_success "Host logs cleared"
            fi

            print_success "All logs cleared"
            ;;

        [Nn])
            print_info "Cancelled"
            return 0
            ;;

        *)
            print_error "Invalid option"
            return 1
            ;;
    esac
}

###############################################################################
# Security Functions
###############################################################################

run_security_hardening() {
    print_header "Security Hardening"

    if [[ ! -f "./security-hardening.sh" ]] && [[ ! -f "/root/cliproxyapi-vps-deployment/security-hardening.sh" ]]; then
        print_error "security-hardening.sh not found"
        print_info "Please download the script from the repository first"
        return 1
    fi

    print_info "This will configure comprehensive security for your VPS:"
    echo "  - UFW firewall configuration"
    echo "  - Fail2ban installation and setup"
    echo "  - Bind CLIProxyAPI to localhost only"
    echo "  - SSH hardening"
    echo "  - Optional Nginx reverse proxy with SSL"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ -f "./security-hardening.sh" ]]; then
            bash ./security-hardening.sh
        else
            bash /root/cliproxyapi-vps-deployment/security-hardening.sh
        fi
    else
        print_info "Cancelled"
    fi
}

run_vps_panel_integration() {
    print_header "VPS Panel Security Integration"

    if [[ ! -f "./vps_panel_security_integration.sh" ]] && [[ ! -f "/root/cliproxyapi-vps-deployment/vps_panel_security_integration.sh" ]]; then
        print_error "vps_panel_security_integration.sh not found"
        print_info "Please download the script from the repository first"
        return 1
    fi

    print_info "This will integrate CLIProxyAPI with your existing Nginx setup:"
    echo "  - Detect existing Nginx configurations"
    echo "  - Update (not replace) your current setup"
    echo "  - Add security headers and rate limiting"
    echo "  - Configure reverse proxy to CLIProxyAPI"
    echo "  - Preserve existing SSL certificates"
    echo "  - Compatible with CloudPanel, Plesk, cPanel"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ -f "./vps_panel_security_integration.sh" ]]; then
            bash ./vps_panel_security_integration.sh
        else
            bash /root/cliproxyapi-vps-deployment/vps_panel_security_integration.sh
        fi
    else
        print_info "Cancelled"
    fi
}

run_block_crawlers() {
    print_header "Block Search Engine Crawlers"

    if [[ ! -f "./block-crawlers.sh" ]] && [[ ! -f "/root/cliproxyapi-vps-deployment/block-crawlers.sh" ]]; then
        print_error "block-crawlers.sh not found"
        print_info "Please download the script from the repository first"
        return 1
    fi

    print_info "This will prevent search engines from indexing your site:"
    echo "  - Create robots.txt blocking all crawlers"
    echo "  - Add X-Robots-Tag HTTP header"
    echo "  - Update Nginx configuration"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ -f "./block-crawlers.sh" ]]; then
            bash ./block-crawlers.sh
        else
            bash /root/cliproxyapi-vps-deployment/block-crawlers.sh
        fi
    else
        print_info "Cancelled"
    fi
}

run_setup_turnstile() {
    print_header "Setup Cloudflare Turnstile"

    if [[ ! -f "./setup-turnstile.sh" ]] && [[ ! -f "/root/cliproxyapi-vps-deployment/setup-turnstile.sh" ]]; then
        print_error "setup-turnstile.sh not found"
        print_info "Please download the script from the repository first"
        return 1
    fi

    print_info "This will add CAPTCHA protection to your management panel:"
    echo "  - Require human verification to access /management.html"
    echo "  - Block automated bots and scripts"
    echo "  - Session-based access (1 hour validity)"
    echo "  - Cloudflare-powered bot detection"
    echo ""
    print_warning "You will need Cloudflare Turnstile API keys (free)"
    print_info "Get them at: https://dash.cloudflare.com/turnstile"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ -f "./setup-turnstile.sh" ]]; then
            bash ./setup-turnstile.sh
        else
            bash /root/cliproxyapi-vps-deployment/setup-turnstile.sh
        fi
    else
        print_info "Cancelled"
    fi
}

view_security_docs() {
    print_header "Security Documentation"

    if [[ -f "./SECURITY.md" ]]; then
        less ./SECURITY.md
    elif [[ -f "/root/cliproxyapi-vps-deployment/SECURITY.md" ]]; then
        less /root/cliproxyapi-vps-deployment/SECURITY.md
    else
        print_error "SECURITY.md not found"
        print_info "Download from: https://github.com/your-repo/cliproxyapi-vps-deployment"
    fi
}

###############################################################################
# Main
###############################################################################

main() {
    check_root

    if [[ $# -gt 0 ]]; then
        # Command line mode
        case "$1" in
            --update|-u)
                create_backup
                pull_latest
                rebuild_docker
                health_check
                ;;
            --rollback|-r)
                rollback
                ;;
            --restore)
                restore_backup
                ;;
            --health|-h)
                health_check
                ;;
            --logs|-l)
                docker_logs -f
                ;;
            --fix-management|-m)
                fix_management_key
                ;;
            --credentials|-c)
                show_credentials
                ;;
            --edit-config)
                edit_config
                ;;
            --view-config)
                view_config
                ;;
            --list-accounts)
                list_accounts
                ;;
            --login-gemini)
                oauth_login "Gemini CLI" "-login"
                ;;
            --login-antigravity)
                oauth_login "Antigravity" "-antigravity-login"
                ;;
            --login-claude)
                oauth_login "Claude Code" "-claude-login"
                ;;
            --login-codex)
                oauth_login "OpenAI Codex" "-codex-login"
                ;;
            --login-qwen)
                oauth_login "Qwen Code" "-qwen-login"
                ;;
            --login-iflow)
                oauth_login "iFlow" "-iflow-login"
                ;;
            *)
                echo "Usage: $0 [OPTION]"
                echo ""
                echo "Updates:"
                echo "  --update, -u         Update to latest version"
                echo "  --rollback, -r       Rollback to previous version"
                echo "  --restore            Restore from backup"
                echo ""
                echo "Service:"
                echo "  --health, -h         Run health check"
                echo "  --logs, -l           View service logs"
                echo ""
                echo "Configuration:"
                echo "  --fix-management, -m Regenerate management key"
                echo "  --credentials, -c    Show current credentials"
                echo "  --edit-config        Edit config.yaml"
                echo "  --view-config        View config.yaml"
                echo ""
                echo "OAuth Login:"
                echo "  --login-gemini       Login to Gemini CLI"
                echo "  --login-antigravity  Login to Antigravity"
                echo "  --login-claude       Login to Claude Code"
                echo "  --login-codex        Login to OpenAI Codex"
                echo "  --login-qwen         Login to Qwen Code"
                echo "  --login-iflow        Login to iFlow"
                echo "  --list-accounts      List logged-in accounts"
                exit 1
                ;;
        esac
    else
        # Interactive mode
        while true; do
            show_menu
            read -p "Select an option: " choice

            case $choice in
                # Updates
                1)
                    pull_latest
                    ;;
                2)
                    create_backup
                    pull_latest
                    rebuild_docker
                    health_check
                    ;;
                3)
                    rollback
                    ;;
                # Backup/Restore
                4)
                    create_backup
                    ;;
                5)
                    restore_backup
                    ;;
                6)
                    echo -e "\n${BLUE}Available backups:${NC}"
                    ls -1t $BACKUP_DIR 2>/dev/null | nl || echo "No backups found"
                    ;;
                # Service
                7)
                    health_check
                    ;;
                8)
                    docker_logs -f
                    ;;
                9)
                    print_info "Restarting service..."
                    docker_restart
                    print_success "Service restarted"
                    ;;
                10)
                    print_info "Stopping service..."
                    docker_stop
                    print_success "Service stopped"
                    ;;
                11)
                    print_info "Starting service..."
                    docker_start
                    print_success "Service started"
                    ;;
                # Configuration
                12)
                    edit_config
                    ;;
                13)
                    view_config
                    ;;
                14)
                    fix_management_key
                    ;;
                15)
                    show_credentials
                    ;;
                # OAuth Providers
                16)
                    oauth_login "Gemini CLI" "-login"
                    ;;
                17)
                    oauth_login "Antigravity" "-antigravity-login"
                    ;;
                18)
                    oauth_login "Claude Code" "-claude-login"
                    ;;
                19)
                    oauth_login "OpenAI Codex" "-codex-login"
                    ;;
                20)
                    oauth_login "Qwen Code" "-qwen-login"
                    ;;
                21)
                    oauth_login "iFlow" "-iflow-login"
                    ;;
                22)
                    list_accounts
                    ;;
                # Files
                23)
                    view_auth_dir
                    ;;
                24)
                    view_logs_dir
                    ;;
                25)
                    clear_logs
                    ;;
                # Security
                26)
                    run_security_hardening
                    ;;
                27)
                    run_vps_panel_integration
                    ;;
                28)
                    run_block_crawlers
                    ;;
                29)
                    run_setup_turnstile
                    ;;
                30)
                    view_security_docs
                    ;;
                0)
                    print_info "Goodbye!"
                    exit 0
                    ;;
                *)
                    print_error "Invalid option"
                    ;;
            esac
            
            echo ""
            read -p "Press Enter to continue..."
        done
    fi
}

main "$@"
