#!/bin/bash

###############################################################################
# CLIProxyAPI VPS Uninstallation Script
# Author: Sisyphus
# Version: 1.0.0
# Description: Safe and complete removal of CLIProxyAPI from Ubuntu VPS
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
BACKUP_LOCATION="$HOME/cliproxyapi-backup-$(date +%Y%m%d_%H%M%S)"

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
        print_info "Please run: sudo bash uninstall.sh"
        exit 1
    fi
}

###############################################################################
# Backup Functions
###############################################################################

create_final_backup() {
    print_header "Creating Final Backup (Optional)"

    read -p "Do you want to backup your configuration and auth files before uninstalling? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Creating backup at: $BACKUP_LOCATION"

        mkdir -p "$BACKUP_LOCATION"

        # Backup config
        if [[ -f "$INSTALL_DIR/CLIProxyAPI/config.yaml" ]]; then
            cp "$INSTALL_DIR/CLIProxyAPI/config.yaml" "$BACKUP_LOCATION/"
            print_success "Config backed up"
        fi

        # Backup auths
        if [[ -d "$INSTALL_DIR/auths" ]]; then
            cp -r "$INSTALL_DIR/auths" "$BACKUP_LOCATION/"
            print_success "Auth files backed up"
        fi

        # Backup API keys
        if [[ -f "$INSTALL_DIR/api-keys.txt" ]]; then
            cp "$INSTALL_DIR/api-keys.txt" "$BACKUP_LOCATION/"
            print_success "API keys backed up"
        fi

        # Backup existing backups directory
        if [[ -d "$INSTALL_DIR/backups" ]]; then
            cp -r "$INSTALL_DIR/backups" "$BACKUP_LOCATION/"
            print_success "Existing backups backed up"
        fi

        # Set permissions
        chmod 700 "$BACKUP_LOCATION"

        print_success "Backup completed at: $BACKUP_LOCATION"
        echo ""
        print_warning "IMPORTANT: Save this backup before closing your session!"
        echo ""
    else
        print_info "Skipping backup"
    fi
}

###############################################################################
# Uninstallation Functions
###############################################################################

stop_service() {
    print_header "Stopping CLIProxyAPI Service"

    if systemctl is-active --quiet $SERVICE_NAME; then
        print_info "Stopping service..."
        systemctl stop $SERVICE_NAME
        print_success "Service stopped"
    else
        print_info "Service is not running"
    fi
}

disable_service() {
    print_header "Disabling Systemd Service"

    if systemctl is-enabled --quiet $SERVICE_NAME 2>/dev/null; then
        print_info "Disabling service..."
        systemctl disable $SERVICE_NAME
        print_success "Service disabled"
    else
        print_info "Service is not enabled"
    fi
}

remove_service_file() {
    print_header "Removing Service File"

    local service_file="/etc/systemd/system/$SERVICE_NAME.service"

    if [[ -f "$service_file" ]]; then
        print_info "Removing systemd service file..."
        rm -f "$service_file"
        systemctl daemon-reload
        print_success "Service file removed"
    else
        print_info "Service file not found"
    fi
}

stop_docker_containers() {
    print_header "Stopping Docker Containers"

    if [[ -d "$INSTALL_DIR/CLIProxyAPI" ]]; then
        if [[ -f "$INSTALL_DIR/CLIProxyAPI/docker-compose.yml" ]]; then
            print_info "Stopping Docker containers..."
            docker compose -f "$INSTALL_DIR/CLIProxyAPI/docker-compose.yml" down 2>/dev/null || true
            print_success "Docker containers stopped"
        else
            print_info "docker-compose.yml not found"
        fi
    else
        print_info "CLIProxyAPI directory not found"
    fi
}

remove_docker_images() {
    print_header "Removing Docker Images (Optional)"

    read -p "Do you want to remove CLIProxyAPI Docker images? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Removing Docker images..."

        # Remove CLI Proxy API images
        docker images | grep "cli-proxy-api" | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true
        docker images | grep "eceasy/cli-proxy-api" | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true

        print_success "Docker images removed"

        # Cleanup unused Docker resources
        read -p "Run Docker system prune to cleanup unused resources? (y/N): " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker system prune -f
            print_success "Docker cleanup completed"
        fi
    else
        print_info "Skipping Docker image removal"
    fi
}

remove_installation_directory() {
    print_header "Removing Installation Directory"

    if [[ -d "$INSTALL_DIR" ]]; then
        print_warning "This will permanently delete: $INSTALL_DIR"
        print_warning "This includes all configurations, auth files, and logs!"
        read -p "Are you absolutely sure? Type 'YES' to confirm: " confirmation

        if [[ "$confirmation" == "YES" ]]; then
            print_info "Removing installation directory..."
            rm -rf "$INSTALL_DIR"
            print_success "Installation directory removed"
        else
            print_info "Skipping directory removal (answered: $confirmation)"
            print_warning "Installation files remain at: $INSTALL_DIR"
        fi
    else
        print_info "Installation directory not found"
    fi
}

remove_firewall_rules() {
    print_header "Removing Firewall Rules (Optional)"

    if command -v ufw &> /dev/null; then
        read -p "Remove firewall rules for CLIProxyAPI ports? (y/N): " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Removing firewall rules..."

            # Remove port rules
            ufw delete allow 8317/tcp 2>/dev/null || true
            ufw delete allow 8085/tcp 2>/dev/null || true
            ufw delete allow 1455/tcp 2>/dev/null || true
            ufw delete allow 54545/tcp 2>/dev/null || true
            ufw delete allow 51121/tcp 2>/dev/null || true
            ufw delete allow 11451/tcp 2>/dev/null || true

            print_success "Firewall rules removed"
        else
            print_info "Skipping firewall rule removal"
        fi
    else
        print_info "UFW not detected, skipping firewall rules"
    fi
}

cleanup_docker() {
    print_header "Docker Cleanup (Optional)"

    read -p "Remove Docker and Docker Compose? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_warning "This will remove Docker completely from your system!"
        read -p "Are you sure? Type 'YES' to confirm: " confirmation

        if [[ "$confirmation" == "YES" ]]; then
            print_info "Removing Docker..."

            # Stop all containers
            docker stop $(docker ps -aq) 2>/dev/null || true

            # Remove Docker packages
            apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true

            # Remove Docker directories
            rm -rf /var/lib/docker
            rm -rf /var/lib/containerd

            print_success "Docker removed"
        else
            print_info "Skipping Docker removal"
        fi
    else
        print_info "Keeping Docker installed"
    fi
}

###############################################################################
# Verification Functions
###############################################################################

verify_uninstallation() {
    print_header "Verifying Uninstallation"

    local issues=0
    local warnings=0

    echo -e "${BLUE}Scanning system for CLIProxyAPI remnants...${NC}"
    echo ""

    # Check systemd service
    print_info "Checking systemd service..."
    if systemctl list-units --full -all | grep -q "$SERVICE_NAME.service"; then
        print_warning "  ✗ Service still exists in systemd"
        ((issues++))
    else
        print_success "  ✓ Service removed from systemd"
    fi

    # Check service file
    if [[ -f "/etc/systemd/system/$SERVICE_NAME.service" ]]; then
        print_warning "  ✗ Service file still exists: /etc/systemd/system/$SERVICE_NAME.service"
        ((issues++))
    else
        print_success "  ✓ Service file removed"
    fi

    echo ""

    # Check installation directory
    print_info "Checking installation directory..."
    if [[ -d "$INSTALL_DIR" ]]; then
        print_warning "  ✗ Installation directory still exists: $INSTALL_DIR"
        local dir_size=$(du -sh "$INSTALL_DIR" 2>/dev/null | cut -f1)
        echo "     Size: $dir_size"
        echo "     Files: $(find "$INSTALL_DIR" -type f 2>/dev/null | wc -l)"
        ((issues++))
    else
        print_success "  ✓ Installation directory removed"
    fi

    echo ""

    # Check Docker containers
    print_info "Checking Docker containers..."
    if docker ps -a 2>/dev/null | grep -q "cli-proxy-api"; then
        print_warning "  ✗ Docker containers still exist:"
        docker ps -a | grep "cli-proxy-api" | sed 's/^/     /'
        ((issues++))
    else
        print_success "  ✓ No Docker containers found"
    fi

    # Check Docker images
    if docker images 2>/dev/null | grep -q "cli-proxy-api\|eceasy/cli-proxy-api"; then
        print_warning "  ✗ Docker images still exist:"
        docker images | grep "cli-proxy-api\|eceasy/cli-proxy-api" | sed 's/^/     /'
        ((warnings++))
    else
        print_success "  ✓ No Docker images found"
    fi

    echo ""

    # Check ports
    print_info "Checking network ports..."
    if netstat -tuln 2>/dev/null | grep -q ":8317"; then
        print_warning "  ✗ Port 8317 is still in use"
        netstat -tuln | grep ":8317" | sed 's/^/     /'
        ((issues++))
    else
        print_success "  ✓ Port 8317 is free"
    fi

    if netstat -tuln 2>/dev/null | grep -q ":3737"; then
        print_warning "  ✗ Port 3737 (Turnstile) is still in use"
        ((warnings++))
    else
        print_success "  ✓ Port 3737 is free"
    fi

    echo ""

    # Check security-related files
    print_info "Checking security components..."

    # Nginx configurations
    if [[ -f "/etc/nginx/sites-available/cliproxyapi" ]] || [[ -f "/etc/nginx/sites-enabled/cliproxyapi" ]]; then
        print_warning "  ✗ Nginx configuration still exists"
        [[ -f "/etc/nginx/sites-available/cliproxyapi" ]] && echo "     - /etc/nginx/sites-available/cliproxyapi"
        [[ -f "/etc/nginx/sites-enabled/cliproxyapi" ]] && echo "     - /etc/nginx/sites-enabled/cliproxyapi"
        ((issues++))
    else
        print_success "  ✓ Nginx configuration removed"
    fi

    # Nginx backups
    local nginx_backups=$(find /etc/nginx/sites-available /etc/nginx/sites-enabled -name "*.backup.*" -o -name "cliproxyapi*" 2>/dev/null | wc -l)
    if [[ $nginx_backups -gt 0 ]]; then
        print_warning "  ✗ Found $nginx_backups Nginx backup file(s)"
        ((warnings++))
    else
        print_success "  ✓ No Nginx backup files"
    fi

    # Turnstile validator
    if systemctl list-units --full -all 2>/dev/null | grep -q "turnstile-validator"; then
        print_warning "  ✗ Turnstile validator service still exists"
        ((issues++))
    else
        print_success "  ✓ Turnstile validator removed"
    fi

    if [[ -d "/opt/turnstile-validator" ]]; then
        print_warning "  ✗ Turnstile validator directory still exists"
        ((issues++))
    else
        print_success "  ✓ Turnstile validator directory removed"
    fi

    # Fail2ban
    if [[ -f "/etc/fail2ban/jail.d/cliproxyapi.conf" ]]; then
        print_warning "  ✗ Fail2ban configuration still exists"
        ((warnings++))
    else
        print_success "  ✓ Fail2ban configuration removed"
    fi

    # Web root
    if [[ -d "/var/www/cliproxyapi" ]]; then
        print_warning "  ✗ Web root directory still exists"
        ((warnings++))
    else
        print_success "  ✓ Web root directory removed"
    fi

    echo ""

    # Check firewall rules
    print_info "Checking firewall rules..."
    if command -v ufw &>/dev/null; then
        local fw_rules=$(ufw status 2>/dev/null | grep -i "8317\|8085\|1455\|54545\|51121\|11451\|3737" | wc -l)
        if [[ $fw_rules -gt 0 ]]; then
            print_warning "  ✗ Found $fw_rules firewall rule(s) still active"
            ufw status | grep -i "8317\|8085\|1455\|54545\|51121\|11451\|3737" | sed 's/^/     /'
            ((warnings++))
        else
            print_success "  ✓ No CLIProxyAPI firewall rules found"
        fi
    else
        print_info "  - UFW not installed (skipping firewall check)"
    fi

    echo ""

    # Check process/running instances
    print_info "Checking running processes..."
    if pgrep -f "CLIProxyAPI\|cli-proxy-api" >/dev/null 2>&1; then
        print_warning "  ✗ CLIProxyAPI process still running"
        ps aux | grep -i "CLIProxyAPI\|cli-proxy-api" | grep -v grep | sed 's/^/     /'
        ((issues++))
    else
        print_success "  ✓ No CLIProxyAPI processes running"
    fi

    echo ""

    # Check temp files
    print_info "Checking temporary files..."
    local temp_files=$(find /tmp -name "*cliproxyapi*" -o -name "*cli-proxy-api*" -o -name "*turnstile*" 2>/dev/null | wc -l)
    if [[ $temp_files -gt 0 ]]; then
        print_warning "  ✗ Found $temp_files temporary file(s)"
        ((warnings++))
    else
        print_success "  ✓ No temporary files found"
    fi

    echo ""

    # Check backups
    print_info "Checking backup locations..."
    if [[ -d "$HOME/cliproxyapi-backup-"* ]] 2>/dev/null; then
        local backup_count=$(ls -1d "$HOME"/cliproxyapi-backup-* 2>/dev/null | wc -l)
        print_info "  ℹ Found $backup_count backup(s) in home directory"
        echo "     (These are intentional backups, safe to delete manually if not needed)"
    else
        print_success "  ✓ No backups found in home directory"
    fi

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

    # Summary
    if [[ $issues -eq 0 ]] && [[ $warnings -eq 0 ]]; then
        print_success "✅ CLEAN UNINSTALL - No issues detected!"
        echo ""
        echo -e "${GREEN}System is completely clean of CLIProxyAPI${NC}"
        return 0
    elif [[ $issues -eq 0 ]] && [[ $warnings -gt 0 ]]; then
        print_warning "⚠️  MOSTLY CLEAN - $warnings warning(s) detected"
        echo ""
        echo -e "${YELLOW}Minor remnants found (not critical):${NC}"
        echo "  - These items may be shared with other services"
        echo "  - Or are intentional backups"
        echo "  - Manual cleanup recommended if needed"
        return 0
    else
        print_error "❌ INCOMPLETE UNINSTALL - $issues critical issue(s) detected"
        if [[ $warnings -gt 0 ]]; then
            echo -e "${YELLOW}   Plus $warnings warning(s)${NC}"
        fi
        echo ""
        echo -e "${RED}Manual cleanup required for critical issues${NC}"
        echo ""
        echo "Run these commands to clean up:"

        if systemctl list-units --full -all | grep -q "$SERVICE_NAME.service"; then
            echo "  sudo systemctl stop $SERVICE_NAME"
            echo "  sudo systemctl disable $SERVICE_NAME"
            echo "  sudo rm /etc/systemd/system/$SERVICE_NAME.service"
            echo "  sudo systemctl daemon-reload"
        fi

        if [[ -d "$INSTALL_DIR" ]]; then
            echo "  sudo rm -rf $INSTALL_DIR"
        fi

        if docker ps -a 2>/dev/null | grep -q "cli-proxy-api"; then
            echo "  docker rm -f \$(docker ps -a | grep cli-proxy-api | awk '{print \$1}')"
        fi

        return 1
    fi
}

###############################################################################
# Main Uninstallation Flow
###############################################################################

show_uninstall_summary() {
    print_header "CLIProxyAPI Uninstallation Summary"

    echo -e "${YELLOW}This will remove:${NC}"
    echo "  - CLIProxyAPI systemd service"
    echo "  - Docker containers"
    echo "  - Installation directory: $INSTALL_DIR"
    echo "  - Service configuration files"
    echo ""
    echo -e "${YELLOW}Optional removals:${NC}"
    echo "  - Docker images"
    echo "  - Firewall rules"
    echo "  - Docker engine (if desired)"
    echo ""
    echo -e "${GREEN}You can backup before uninstalling:${NC}"
    echo "  - Configuration files"
    echo "  - Auth tokens"
    echo "  - API keys"
    echo ""
}

deep_uninstall_mode() {
    print_header "Deep Uninstall Mode"

    echo -e "${RED}WARNING: Deep uninstall will remove EVERYTHING related to CLIProxyAPI${NC}"
    echo -e "${RED}This includes:${NC}"
    echo "  - All files in $INSTALL_DIR"
    echo "  - Docker images (eceasy/cli-proxy-api)"
    echo "  - Docker volumes and networks"
    echo "  - Systemd service files"
    echo "  - Firewall rules"
    echo "  - Logs and temporary files"
    echo "  - All backups in $INSTALL_DIR/backups"
    echo "  - Nginx configurations (if created by security scripts)"
    echo "  - Fail2ban rules (if created by security scripts)"
    echo "  - Cloudflare Turnstile validation server (if installed)"
    echo ""
    echo -e "${YELLOW}This is IRREVERSIBLE and will NOT create a backup!${NC}"
    echo ""
    read -p "Are you ABSOLUTELY SURE? Type 'DELETE EVERYTHING' to confirm: " confirmation

    if [[ "$confirmation" != "DELETE EVERYTHING" ]]; then
        print_info "Deep uninstall cancelled"
        return 1
    fi

    print_header "Executing Deep Uninstall"

    # Stop service
    print_info "Stopping service..."
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    systemctl disable $SERVICE_NAME 2>/dev/null || true

    # Stop and remove all Docker containers
    print_info "Removing all Docker containers..."
    docker compose -f "$INSTALL_DIR/CLIProxyAPI/docker-compose.yml" down -v 2>/dev/null || true

    # Remove all Docker images
    print_info "Removing all CLIProxyAPI Docker images..."
    docker images | grep "cli-proxy-api" | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true
    docker images | grep "eceasy/cli-proxy-api" | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true

    # Remove systemd service
    print_info "Removing systemd service..."
    rm -f /etc/systemd/system/$SERVICE_NAME.service
    systemctl daemon-reload

    # Remove security-related files
    print_info "Removing security configurations..."

    # Turnstile validation server
    if systemctl list-units --full -all | grep -q "turnstile-validator"; then
        systemctl stop turnstile-validator 2>/dev/null || true
        systemctl disable turnstile-validator 2>/dev/null || true
        rm -f /etc/systemd/system/turnstile-validator.service
        rm -rf /opt/turnstile-validator
        systemctl daemon-reload
        print_success "Removed Turnstile validation server"
    fi

    # Nginx configurations created by security scripts
    if [[ -f "/etc/nginx/sites-available/cliproxyapi" ]]; then
        rm -f /etc/nginx/sites-available/cliproxyapi
        rm -f /etc/nginx/sites-enabled/cliproxyapi
        print_success "Removed Nginx configuration"
    fi

    # Nginx configuration backups
    rm -f /etc/nginx/sites-available/cliproxyapi.backup.* 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/*.backup.* 2>/dev/null || true

    # robots.txt and web root
    rm -rf /var/www/cliproxyapi 2>/dev/null || true

    # Fail2ban jail for CLIProxyAPI
    if [[ -f "/etc/fail2ban/jail.d/cliproxyapi.conf" ]]; then
        rm -f /etc/fail2ban/jail.d/cliproxyapi.conf
        systemctl restart fail2ban 2>/dev/null || true
        print_success "Removed Fail2ban configuration"
    fi

    # Remove installation directory completely
    print_info "Removing installation directory..."
    rm -rf "$INSTALL_DIR"

    # Remove firewall rules (including security script additions)
    print_info "Removing firewall rules..."
    ufw delete allow 8317/tcp 2>/dev/null || true
    ufw delete allow 8085/tcp 2>/dev/null || true
    ufw delete allow 1455/tcp 2>/dev/null || true
    ufw delete allow 54545/tcp 2>/dev/null || true
    ufw delete allow 51121/tcp 2>/dev/null || true
    ufw delete allow 11451/tcp 2>/dev/null || true
    ufw delete allow 80/tcp comment 'HTTP' 2>/dev/null || true
    ufw delete allow 443/tcp comment 'HTTPS' 2>/dev/null || true
    ufw delete allow 3737/tcp comment 'Turnstile Validator' 2>/dev/null || true
    ufw delete allow from 127.0.0.1 to any port 8317 2>/dev/null || true

    # Clean up any remaining Docker resources
    print_info "Cleaning Docker resources..."
    docker system prune -af --volumes 2>/dev/null || true

    # Remove any symlinks
    print_info "Removing symlinks..."
    rm -f /opt/cliproxyapi 2>/dev/null || true

    # Clean up any temp files
    print_info "Removing temporary files..."
    rm -rf /tmp/cliproxyapi* 2>/dev/null || true
    rm -rf /tmp/cli-proxy-api* 2>/dev/null || true
    rm -rf /tmp/turnstile* 2>/dev/null || true

    print_success "Deep uninstall completed"

    return 0
}

main() {
    print_header "CLIProxyAPI VPS Uninstaller"

    check_root

    echo -e "${YELLOW}Choose uninstall mode:${NC}"
    echo "  1) Normal uninstall (with backup option)"
    echo "  2) Deep uninstall (remove everything, no backup)"
    echo "  0) Cancel"
    echo ""
    read -p "Select mode (1/2/0): " -n 1 -r mode
    echo ""
    echo ""

    case $mode in
        1)
            # Normal uninstall mode
            show_uninstall_summary

            print_warning "This will uninstall CLIProxyAPI from your VPS!"
            read -p "Continue with uninstallation? (y/N): " -n 1 -r
            echo

            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Uninstallation cancelled"
                exit 0
            fi

            # Execute uninstallation steps
            create_final_backup
            stop_service
            disable_service
            stop_docker_containers
            remove_service_file
            remove_docker_images
            remove_installation_directory
            remove_firewall_rules
            cleanup_docker
            verify_uninstallation
            ;;
        2)
            # Deep uninstall mode
            if deep_uninstall_mode; then
                verify_uninstallation
            else
                exit 0
            fi
            ;;
        0)
            print_info "Uninstallation cancelled"
            exit 0
            ;;
        *)
            print_error "Invalid option"
            exit 1
            ;;
    esac

    # Final summary
    print_header "Uninstallation Complete"

    cat <<EOF

${GREEN}CLIProxyAPI has been uninstalled from your VPS!${NC}

${BLUE}═══════════════════════════════════════════════════════════════${NC}
${BLUE}SUMMARY${NC}
${BLUE}═══════════════════════════════════════════════════════════════${NC}

EOF

    if [[ -d "$BACKUP_LOCATION" ]]; then
        echo -e "${GREEN}✓ Backup saved at:${NC} $BACKUP_LOCATION"
        echo ""
    fi

    if [[ -d "$INSTALL_DIR" ]]; then
        echo -e "${YELLOW}⚠ Installation directory preserved:${NC} $INSTALL_DIR"
        echo -e "  To remove manually: ${YELLOW}sudo rm -rf $INSTALL_DIR${NC}"
        echo ""
    fi

    echo -e "${BLUE}To reinstall CLIProxyAPI:${NC}"
    echo "  sudo bash install.sh"
    echo ""

    print_success "Thank you for using CLIProxyAPI!"

}

# Run main function
main "$@"
