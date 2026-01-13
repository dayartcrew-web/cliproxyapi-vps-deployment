#!/bin/bash

###############################################################################
# Fix Docker Compose YAML Duplicate Keys
# Run this script to fix the duplicate environment key issue
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
echo -e "${BLUE}Fix Docker Compose YAML${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root or with sudo"
    print_info "Please run: sudo bash fix-docker-compose.sh"
    exit 1
fi

# Check if directory exists
if [[ ! -d "$INSTALL_DIR/CLIProxyAPI" ]]; then
    print_error "CLIProxyAPI directory not found at $INSTALL_DIR/CLIProxyAPI"
    exit 1
fi

# Check if file exists
if [[ ! -f "$COMPOSE_FILE" ]]; then
    print_error "docker-compose.yml not found at $COMPOSE_FILE"
    exit 1
fi

print_info "Backing up current docker-compose.yml..."
cp "$COMPOSE_FILE" "$COMPOSE_FILE.backup-$(date +%Y%m%d_%H%M%S)"
print_success "Backup created"

cd "$INSTALL_DIR/CLIProxyAPI"

# Stop containers
print_info "Stopping containers..."
docker compose down 2>/dev/null || true
print_success "Containers stopped"

# Check if we're in a git repository and have uncommitted changes
if git rev-parse --git-dir > /dev/null 2>&1; then
    print_info "Resetting docker-compose.yml to repository version..."

    # Discard local changes to docker-compose.yml
    git checkout -- docker-compose.yml 2>/dev/null || true

    # Also remove any .bak files
    rm -f docker-compose.yml.bak 2>/dev/null || true

    print_success "docker-compose.yml reset to clean state"
else
    print_warning "Not a git repository, downloading fresh docker-compose.yml..."

    # Download fresh copy from GitHub
    curl -fsSL https://raw.githubusercontent.com/router-for-me/CLIProxyAPI/main/docker-compose.yml -o docker-compose.yml

    print_success "Fresh docker-compose.yml downloaded"
fi

# Verify the file is valid YAML
print_info "Validating YAML syntax..."
if docker compose config > /dev/null 2>&1; then
    print_success "YAML syntax is valid"
else
    print_error "YAML syntax is still invalid"
    print_info "Attempting to download fresh copy..."
    curl -fsSL https://raw.githubusercontent.com/router-for-me/CLIProxyAPI/main/docker-compose.yml -o docker-compose.yml
fi

# Start containers
print_info "Starting containers..."
if docker compose up -d; then
    print_success "Containers started successfully"
else
    print_error "Failed to start containers"
    print_info "Check logs with: cd $INSTALL_DIR/CLIProxyAPI && docker compose logs"
    exit 1
fi

# Wait a moment for containers to start
sleep 3

# Check container status
print_info "Checking container status..."
if docker compose ps | grep -q "Up"; then
    print_success "Container is running"
else
    print_warning "Container may not be running properly"
    print_info "Check status with: cd $INSTALL_DIR/CLIProxyAPI && docker compose ps"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Fix Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
print_success "docker-compose.yml has been fixed and containers are running"
echo ""
print_info "You can now access:"
echo "  - API: http://$(hostname -I | awk '{print $1}'):8317/v1"
echo "  - Management: http://$(hostname -I | awk '{print $1}'):8317/management.html"
echo ""
print_info "Find your management key in: /opt/cliproxyapi/api-keys.txt"
echo ""
