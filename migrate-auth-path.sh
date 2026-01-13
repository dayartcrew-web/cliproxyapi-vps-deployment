#!/bin/bash

###############################################################################
# Migration Script: Fix Auth Directory Path
# Version: 1.0.0
# Description: Fixes auth-dir path in config.yaml for existing installations
###############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

INSTALL_DIR="/opt/cliproxyapi"
CONFIG_FILE="$INSTALL_DIR/CLIProxyAPI/config.yaml"
COMPOSE_FILE="$INSTALL_DIR/CLIProxyAPI/docker-compose.yml"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Auth Directory Path Migration${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root or with sudo"
    exit 1
fi

# Check if installation exists
if [[ ! -d "$INSTALL_DIR/CLIProxyAPI" ]]; then
    print_error "CLIProxyAPI installation not found at $INSTALL_DIR"
    exit 1
fi

print_info "Checking current configuration..."
echo ""

# Check current auth-dir in config.yaml
current_auth_dir=$(grep "^auth-dir:" "$CONFIG_FILE" | sed 's/auth-dir: *"\(.*\)"/\1/')
echo "Current auth-dir in config.yaml: $current_auth_dir"

# Check if volume mount exists
if grep -q "/opt/cliproxyapi/auths:/root/.cli-proxy-api" "$COMPOSE_FILE"; then
    echo "✓ Volume mount exists in docker-compose.yml"
    volume_mount_ok=true
else
    echo "✗ Volume mount MISSING in docker-compose.yml"
    volume_mount_ok=false
fi

echo ""

# Determine what needs to be fixed
needs_config_fix=false
needs_volume_fix=false

if [[ "$current_auth_dir" != "/root/.cli-proxy-api" ]]; then
    print_warning "Auth-dir path needs updating in config.yaml"
    needs_config_fix=true
fi

if [[ "$volume_mount_ok" == false ]]; then
    print_warning "Volume mount needs adding to docker-compose.yml"
    needs_volume_fix=true
fi

if [[ "$needs_config_fix" == false ]] && [[ "$needs_volume_fix" == false ]]; then
    print_success "Configuration is already correct! No migration needed."
    exit 0
fi

echo ""
print_warning "Migration required!"
echo ""
echo "This script will:"
if [[ "$needs_config_fix" == true ]]; then
    echo "  1. Update config.yaml: auth-dir → /root/.cli-proxy-api"
fi
if [[ "$needs_volume_fix" == true ]]; then
    echo "  2. Add volume mount to docker-compose.yml"
fi
echo "  3. Restart Docker containers"
echo ""
read -p "Continue with migration? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Migration cancelled"
    exit 0
fi

echo ""
print_info "Starting migration..."
echo ""

# Backup files
print_info "Creating backups..."
cp "$CONFIG_FILE" "$CONFIG_FILE.backup-$(date +%Y%m%d_%H%M%S)"
cp "$COMPOSE_FILE" "$COMPOSE_FILE.backup-$(date +%Y%m%d_%H%M%S)"
print_success "Backups created"

# Fix config.yaml
if [[ "$needs_config_fix" == true ]]; then
    print_info "Updating config.yaml..."
    sed -i 's|^auth-dir:.*|auth-dir: "/root/.cli-proxy-api"|' "$CONFIG_FILE"

    # Verify
    new_auth_dir=$(grep "^auth-dir:" "$CONFIG_FILE" | sed 's/auth-dir: *"\(.*\)"/\1/')
    if [[ "$new_auth_dir" == "/root/.cli-proxy-api" ]]; then
        print_success "Config.yaml updated: auth-dir → /root/.cli-proxy-api"
    else
        print_error "Failed to update config.yaml"
        exit 1
    fi
fi

# Fix docker-compose.yml
if [[ "$needs_volume_fix" == true ]]; then
    print_info "Adding volume mount to docker-compose.yml..."

    if grep -q "volumes:" "$COMPOSE_FILE"; then
        # Add to existing volumes section
        sed -i '/volumes:/a\      - /opt/cliproxyapi/auths:/root/.cli-proxy-api' "$COMPOSE_FILE"
        print_success "Volume mount added to docker-compose.yml"
    else
        print_error "No volumes section found in docker-compose.yml"
        print_info "Please manually add:"
        echo "    volumes:"
        echo "      - ./config.yaml:/CLIProxyAPI/config.yaml"
        echo "      - /opt/cliproxyapi/auths:/root/.cli-proxy-api"
        exit 1
    fi
fi

# Restart containers
print_info "Restarting Docker containers..."
cd "$INSTALL_DIR/CLIProxyAPI"
docker compose down
docker compose up -d
print_success "Containers restarted"

# Wait for startup
print_info "Waiting for service to start..."
sleep 8

# Verify
print_info "Verifying migration..."
echo ""

# Check if auth files are visible in container
auth_files=$(docker compose exec cli-proxy-api ls /root/.cli-proxy-api/ 2>/dev/null | wc -l)
if [[ $auth_files -gt 1 ]]; then
    print_success "Auth files are visible in container"
else
    print_warning "No auth files found in container (this is OK if you haven't logged in yet)"
fi

# Check logs for client count
client_count=$(docker compose logs --tail=50 2>&1 | grep "clients" | tail -1)
echo "Latest log: $client_count"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Migration Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

print_success "Auth directory path has been migrated"
echo ""
print_info "Next steps:"
echo "  1. Login to a provider if you haven't already:"
echo "     cd $INSTALL_DIR/CLIProxyAPI"
echo "     docker compose exec cli-proxy-api ./CLIProxyAPI -login -no-browser"
echo ""
echo "  2. Test the API:"
echo "     curl http://localhost:8317/v1/models -H \"Authorization: Bearer YOUR_KEY\""
echo ""
echo "  3. Restart service to verify persistence:"
echo "     sudo systemctl restart cliproxyapi"
echo "     curl http://localhost:8317/v1/models -H \"Authorization: Bearer YOUR_KEY\""
echo ""
print_info "Auth files should now persist across restarts!"
echo ""
