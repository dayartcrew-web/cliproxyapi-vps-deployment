#!/bin/bash

###############################################################################
# Fix Docker Volume Mounts for CLIProxyAPI
# This ensures auth files and config persist across restarts
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
COMPOSE_FILE="$INSTALL_DIR/CLIProxyAPI/docker-compose.yml"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Fix Docker Volume Mounts${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root or with sudo"
    exit 1
fi

# Check if file exists
if [[ ! -f "$COMPOSE_FILE" ]]; then
    print_error "docker-compose.yml not found at $COMPOSE_FILE"
    exit 1
fi

print_info "Current docker-compose.yml configuration:"
echo ""
grep -A 10 "volumes:" "$COMPOSE_FILE" || echo "No volumes found"
echo ""

# Check if auths directory is already mounted
if grep -q "/opt/cliproxyapi/auths" "$COMPOSE_FILE"; then
    print_success "Auth directory is already mounted in docker-compose.yml"
    print_info "Auth files should persist across restarts"

    # Verify the mount is correct
    print_info "Verifying mount configuration..."
    grep "auths" "$COMPOSE_FILE"
else
    print_warning "Auth directory is NOT mounted in docker-compose.yml"
    print_info "This is why your auth config resets on restart!"
    echo ""
    print_info "Fixing docker-compose.yml..."

    # Backup
    cp "$COMPOSE_FILE" "$COMPOSE_FILE.backup-$(date +%Y%m%d_%H%M%S)"
    print_success "Backup created"

    # Add volume mount for auths directory
    # Find the volumes section and add the auth mount
    if grep -q "volumes:" "$COMPOSE_FILE"; then
        # Volumes section exists, add to it
        sed -i '/volumes:/a\      - /opt/cliproxyapi/auths:/root/.cli-proxy-api' "$COMPOSE_FILE"
        print_success "Added auth directory mount to existing volumes section"
    else
        # No volumes section, need to add one
        print_warning "No volumes section found, this might require manual editing"
        print_info "Please add this to your docker-compose.yml under the service:"
        echo ""
        echo "    volumes:"
        echo "      - ./config.yaml:/CLIProxyAPI/config.yaml"
        echo "      - /opt/cliproxyapi/auths:/root/.cli-proxy-api"
        echo ""
    fi
fi

# Show the current configuration
echo ""
print_info "Current volume mounts in docker-compose.yml:"
grep -A 5 "volumes:" "$COMPOSE_FILE" || echo "No volumes found"
echo ""

# Ask if user wants to restart
print_warning "Docker containers need to be restarted for changes to take effect"
read -p "Restart containers now? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd "$INSTALL_DIR/CLIProxyAPI"

    print_info "Stopping containers..."
    docker compose down

    print_info "Starting containers with new configuration..."
    docker compose up -d

    print_success "Containers restarted"

    # Check if auth files exist
    if [[ -d "/opt/cliproxyapi/auths" ]] && [[ "$(ls -A /opt/cliproxyapi/auths)" ]]; then
        print_success "Auth files found in /opt/cliproxyapi/auths"
        print_info "These should now persist across restarts"
    else
        print_warning "No auth files found yet"
        print_info "Login to a provider: docker compose exec cli-proxy-api ./CLIProxyAPI -login -no-browser"
    fi
else
    print_info "Skipped restart. Run manually when ready:"
    echo "  cd $INSTALL_DIR/CLIProxyAPI"
    echo "  docker compose down"
    echo "  docker compose up -d"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Fix Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

print_info "To verify auth persistence:"
echo "  1. Login to a provider"
echo "  2. Restart: sudo systemctl restart cliproxyapi"
echo "  3. Check: curl http://localhost:8317/v1/models"
echo ""
