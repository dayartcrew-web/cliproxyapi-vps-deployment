#!/bin/bash

###############################################################################
# Fix Management Panel Script
# Based on: https://help.router-for.me/management/webui
# Purpose: Diagnose and fix management panel (management.html) issues
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
STATIC_DIR="$INSTALL_DIR/CLIProxyAPI/static"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Management Panel Diagnostics & Fix${NC}"
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

print_info "Running diagnostics..."
echo ""

# 1. Check config.yaml settings
print_info "1. Checking config.yaml settings..."
echo ""

disable_panel=$(grep "disable-control-panel:" "$CONFIG_FILE" | awk '{print $2}')
allow_remote=$(grep "allow-remote:" "$CONFIG_FILE" | awk '{print $2}')
secret_key=$(grep "secret-key:" "$CONFIG_FILE" | grep -v "^#" | awk '{print $2}' | tr -d '"')
panel_repo=$(grep "panel-github-repository:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')

echo "  disable-control-panel: $disable_panel"
echo "  allow-remote: $allow_remote"
echo "  secret-key: ${secret_key:0:20}... (truncated)"
echo "  panel-github-repository: $panel_repo"
echo ""

# Check for issues
issues=0

if [[ "$disable_panel" == "true" ]]; then
    print_error "Control panel is DISABLED in config.yaml"
    echo "  Current setting: disable-control-panel: true"
    echo ""
    echo "  When disabled:"
    echo "    - Server SKIPS downloading management.html"
    echo "    - /management.html returns 404"
    echo "    - Use this if hosting UI elsewhere or API-only usage"
    echo ""
    echo "  Fix: Set disable-control-panel: false"
    issues=$((issues+1))
else
    print_success "Control panel is enabled"
    echo "  Server will auto-download management.html from GitHub"
fi

if [[ -z "$secret_key" ]] || [[ "$secret_key" == "CHANGE_THIS_TO_SECURE_RANDOM_KEY" ]]; then
    print_error "Management secret key is not set or is default"
    echo "  Fix: Run 'sudo bash update.sh' → 'Fix Management Key'"
    issues=$((issues+1))
else
    print_success "Management secret key is configured"
fi

if [[ -z "$panel_repo" ]]; then
    print_warning "No GitHub repository configured for management panel"
    echo "  Default repository will be used"
else
    print_success "GitHub repository configured: $panel_repo"
fi

# 2. Check if management.html exists
print_info "2. Checking management.html file..."
echo ""

if [[ -f "$STATIC_DIR/management.html" ]]; then
    file_size=$(stat -f%z "$STATIC_DIR/management.html" 2>/dev/null || stat -c%s "$STATIC_DIR/management.html" 2>/dev/null)
    file_age=$(find "$STATIC_DIR/management.html" -mtime +7 2>/dev/null | wc -l)

    print_success "management.html exists"
    echo "  Location: $STATIC_DIR/management.html"
    echo "  Size: $file_size bytes"

    if [[ $file_age -gt 0 ]]; then
        print_warning "File is older than 7 days (may need update)"
    fi
else
    print_error "management.html NOT FOUND"
    echo "  Expected location: $STATIC_DIR/management.html"
    issues=$((issues+1))
fi

# 3. Check Docker container logs
print_info "3. Checking Docker container logs..."
echo ""

cd "$INSTALL_DIR/CLIProxyAPI"

# Check if container is running
if docker compose ps | grep -q "cli-proxy-api.*Up"; then
    print_success "Docker container is running"

    # Check logs for management panel messages
    echo ""
    echo "Recent management-related log entries:"
    docker compose logs --tail=100 2>&1 | grep -i "management" | tail -5

    # Check if panel was downloaded
    if docker compose logs --tail=200 2>&1 | grep -q "management asset updated successfully"; then
        print_success "Management panel was downloaded successfully"
    else
        print_warning "No log entry for successful panel download"
        print_info "The panel may still be downloading or there may be an issue"
    fi
else
    print_error "Docker container is NOT running"
    issues=$((issues+1))
fi

# 4. Test management endpoint
print_info "4. Testing management.html endpoint..."
echo ""

response=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8317/management.html")

if [[ "$response" == "200" ]]; then
    print_success "Management panel is accessible (HTTP $response)"
elif [[ "$response" == "404" ]]; then
    print_error "Management panel returns 404 Not Found"
    issues=$((issues+1))
else
    print_warning "Unexpected response: HTTP $response"
    issues=$((issues+1))
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [[ $issues -eq 0 ]]; then
    print_success "No issues found! Management panel should be working."
    echo ""
    print_info "Access the panel at:"
    VPS_IP=$(hostname -I | awk '{print $1}')
    echo "  http://$VPS_IP:8317/management.html"
    echo ""
    print_info "Management key:"
    echo "  $(cat /opt/cliproxyapi/api-keys.txt | grep MANAGEMENT_KEY | cut -d= -f2)"
    exit 0
fi

echo -e "${YELLOW}Found $issues issue(s)${NC}"
echo ""
echo "Recommended fixes:"
echo ""

# Offer automatic fix
read -p "Would you like to automatically fix these issues? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Manual fix required. Follow the suggestions above."
    exit 1
fi

echo ""
print_info "Applying fixes..."
echo ""

# Fix 1: Enable control panel if disabled
if [[ "$disable_panel" == "true" ]]; then
    print_info "Enabling control panel in config.yaml..."
    sed -i 's/disable-control-panel: true/disable-control-panel: false/' "$CONFIG_FILE"
    print_success "Control panel enabled"
fi

# Fix 2: Add GitHub repository if missing
if [[ -z "$panel_repo" ]]; then
    print_info "Adding default GitHub repository to config.yaml..."

    # Check if remote-management section exists
    if grep -q "remote-management:" "$CONFIG_FILE"; then
        # Add panel-github-repository under remote-management
        sed -i '/remote-management:/a\  panel-github-repository: "https://github.com/router-for-me/Cli-Proxy-API-Management-Center"' "$CONFIG_FILE"
        print_success "GitHub repository added"
    else
        print_warning "remote-management section not found in config.yaml"
        print_info "Please add manually or regenerate config.yaml"
    fi
fi

# Fix 3: Create static directory if missing
if [[ ! -d "$STATIC_DIR" ]]; then
    print_info "Creating static directory..."
    mkdir -p "$STATIC_DIR"
    chmod 755 "$STATIC_DIR"
    print_success "Static directory created"
fi

# Fix 4: Restart container to trigger panel download
print_info "Restarting Docker container to trigger panel download..."
docker compose down
docker compose up -d

print_success "Container restarted"

# Wait for startup
print_info "Waiting for service to start and download panel..."
sleep 15

# Check logs
echo ""
print_info "Checking download progress..."
docker compose logs --tail=50 | grep -i "management"

# Final test
echo ""
print_info "Testing endpoint again..."
sleep 5
response=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8317/management.html")

echo ""
echo -e "${BLUE}========================================${NC}"
if [[ "$response" == "200" ]]; then
    echo -e "${GREEN}✓ Fix Complete!${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    print_success "Management panel is now accessible!"
    echo ""
    VPS_IP=$(hostname -I | awk '{print $1}')
    echo "Access at: http://$VPS_IP:8317/management.html"
    echo ""
    echo "Management key:"
    cat /opt/cliproxyapi/api-keys.txt | grep MANAGEMENT_KEY
else
    echo -e "${YELLOW}⚠ Partial Fix${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    print_warning "Management panel still returns HTTP $response"
    echo ""
    print_info "Additional steps:"
    echo "  1. Check logs: docker compose logs -f"
    echo "  2. Verify internet connectivity for GitHub downloads"
    echo "  3. Check firewall rules"
    echo "  4. Wait a few more minutes for the panel to download"
    echo ""
    print_info "Manual check:"
    echo "  ls -la $STATIC_DIR/"
    echo "  docker compose logs | grep -i management"
fi

echo ""
