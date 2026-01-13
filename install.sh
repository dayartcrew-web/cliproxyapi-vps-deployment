#!/bin/bash

###############################################################################
# CLIProxyAPI VPS Installation Script for Ubuntu
# Author: Sisyphus
# Version: 1.0.0
# Description: Automated installation and setup of CLIProxyAPI on Ubuntu VPS
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
REPO_URL="https://github.com/router-for-me/CLIProxyAPI.git"
DEFAULT_PORT=8317
SERVICE_NAME="cliproxyapi"

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
        print_info "Please run: sudo bash install.sh"
        exit 1
    fi
}

detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi

    source /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID

    print_info "Detected OS: $OS $VERSION"

    if [[ "$OS" != "ubuntu" ]] && [[ "$OS" != "debian" ]]; then
        print_warning "This script is designed for Ubuntu/Debian. Other distros may require manual adjustments."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

###############################################################################
# Installation Steps
###############################################################################

install_docker() {
    print_header "Installing Docker"

    if command -v docker &> /dev/null; then
        print_success "Docker is already installed: $(docker --version)"
    else
        print_info "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
        sudo usermod -aG docker $USER
        print_success "Docker installed successfully"
        print_warning "You may need to log out and log back in for group changes to take effect."
    fi
}

install_docker_compose() {
    print_header "Installing Docker Compose"

    if docker compose version &> /dev/null; then
        print_success "Docker Compose is already installed: $(docker compose version)"
    else
        print_info "Installing Docker Compose..."
        sudo apt-get update
        sudo apt-get install -y docker-compose-plugin
        print_success "Docker Compose installed successfully"
    fi
}

setup_directories() {
    print_header "Setting Up Directories"

    sudo mkdir -p $INSTALL_DIR
    sudo mkdir -p $INSTALL_DIR/auths
    sudo mkdir -p $INSTALL_DIR/logs
    sudo mkdir -p $INSTALL_DIR/config

    print_success "Directories created at $INSTALL_DIR"
}

clone_repository() {
    print_header "Cloning CLIProxyAPI Repository"

    if [[ -d "$INSTALL_DIR/CLIProxyAPI" ]]; then
        print_warning "CLIProxyAPI directory already exists. Pulling latest changes..."
        cd $INSTALL_DIR/CLIProxyAPI
        git pull origin main
    else
        print_info "Cloning repository..."
        git clone $REPO_URL $INSTALL_DIR/CLIProxyAPI
    fi

    print_success "Repository updated successfully"
}

setup_config() {
    print_header "Setting Up Configuration"

    # Config must be in CLIProxyAPI directory for docker-compose volume mount
    local config_file="$INSTALL_DIR/CLIProxyAPI/config.yaml"

    # Remove if it's a directory (docker creates directory if file doesn't exist)
    if [[ -d "$config_file" ]]; then
        print_warning "Removing incorrectly created config directory..."
        rm -rf "$config_file"
    fi

    if [[ ! -f "$config_file" ]]; then
        print_info "Creating config.yaml from example..."
        cp $INSTALL_DIR/CLIProxyAPI/config.example.yaml $config_file

        # Set default values
        sed -i 's/host: ""/host: "0.0.0.0"/' $config_file
        sed -i 's/port: 8317/port: 8317/' $config_file
        sed -i 's/auth-dir: "~\/\.cli-proxy-api"/auth-dir: "\/opt\/cliproxyapi\/auths"/' $config_file

        # Enable remote management
        sed -i 's/allow-remote: false/allow-remote: true/' $config_file

        # Disable control panel restriction (enable it)
        sed -i 's/disable-control-panel: true/disable-control-panel: false/' $config_file

        # Generate management secret key
        MGMT_SECRET=$(openssl rand -hex 32)
        sed -i "s/secret-key: \"\"/secret-key: \"${MGMT_SECRET}\"/" $config_file

        # Generate random API keys
        generate_api_keys "$config_file" "$MGMT_SECRET"

        print_success "Configuration file created at $config_file"
        print_warning "Please edit $config_file to configure your API providers"
    else
        print_success "Configuration file already exists at $config_file"
    fi

    # Also create a symlink in parent directory for convenience
    if [[ ! -L "$INSTALL_DIR/config.yaml" ]]; then
        ln -sf "$config_file" "$INSTALL_DIR/config.yaml"
        print_info "Created symlink: $INSTALL_DIR/config.yaml -> $config_file"
    fi
}

generate_api_keys() {
    local config_file=$1
    local mgmt_secret=$2

    print_info "Generating secure API keys..."

    # Generate 3 random API keys
    KEY1=$(openssl rand -hex 16)
    KEY2=$(openssl rand -hex 16)
    KEY3=$(openssl rand -hex 16)

    # Update config with generated keys
    sed -i "s/your-api-key-1/${KEY1}/" $config_file
    sed -i "s/your-api-key-2/${KEY2}/" $config_file
    sed -i "s/your-api-key-3/${KEY3}/" $config_file

    # Save keys to a secure file
    local keys_file="$INSTALL_DIR/api-keys.txt"
    local VPS_IP=$(hostname -I | awk '{print $1}')
    
    cat > $keys_file <<EOF
# ╔═══════════════════════════════════════════════════════════════╗
# ║           CLIProxyAPI Credentials                              ║
# ║           Generated on: $(date)                                 
# ║           KEEP THESE SECURE!                                   ║
# ╚═══════════════════════════════════════════════════════════════╝

# ════════════════════════════════════════════════════════════════
# API Keys (for client authentication)
# ════════════════════════════════════════════════════════════════
# Use these keys in the Authorization header:
# Authorization: Bearer <API_KEY>

API_KEY_1=$KEY1
API_KEY_2=$KEY2
API_KEY_3=$KEY3

# ════════════════════════════════════════════════════════════════
# Management Panel Access
# ════════════════════════════════════════════════════════════════
# Access URL: http://${VPS_IP}:8317/v0/management?key=<MANAGEMENT_KEY>

MANAGEMENT_KEY=$mgmt_secret

# ════════════════════════════════════════════════════════════════
# Quick Access URLs
# ════════════════════════════════════════════════════════════════
API_ENDPOINT=http://${VPS_IP}:8317/v1
MANAGEMENT_URL=http://${VPS_IP}:8317/v0/management?key=$mgmt_secret

# ════════════════════════════════════════════════════════════════
# Test Commands
# ════════════════════════════════════════════════════════════════
# List models:
# curl http://${VPS_IP}:8317/v1/models -H "Authorization: Bearer $KEY1"
#
# Chat completion:
# curl http://${VPS_IP}:8317/v1/chat/completions -H "Content-Type: application/json" -H "Authorization: Bearer $KEY1" -d '{"model": "gemini-2.5-flash", "messages": [{"role": "user", "content": "Hello!"}]}'
EOF

    chmod 600 $keys_file
    print_success "API keys generated and saved to $keys_file"
    print_warning "Please keep these keys secure!"
}

setup_permissions() {
    print_header "Setting Permissions"

    sudo chown -R $USER:$USER $INSTALL_DIR
    sudo chmod 755 $INSTALL_DIR
    sudo chmod 700 $INSTALL_DIR/auths
    sudo chmod 700 $INSTALL_DIR/logs

    print_success "Permissions set correctly"
}

create_systemd_service() {
    print_header "Creating Systemd Service"

    local service_file="/etc/systemd/system/$SERVICE_NAME.service"

    sudo tee $service_file > /dev/null <<EOF
[Unit]
Description=CLIProxyAPI Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR/CLIProxyAPI
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME

    print_success "Systemd service created and enabled"
}

configure_firewall() {
    print_header "Configuring Firewall"

    if command -v ufw &> /dev/null; then
        print_info "UFW firewall detected. Configuring rules..."

        read -p "Allow CLIProxyAPI ports (8317, 8085, 1455, 54545, 51121, 11451)? (y/N): " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo ufw allow 8317/tcp
            sudo ufw allow 8085/tcp
            sudo ufw allow 1455/tcp
            sudo ufw allow 54545/tcp
            sudo ufw allow 51121/tcp
            sudo ufw allow 11451/tcp
            print_success "Firewall rules added"
        else
            print_info "Skipping firewall configuration"
        fi
    else
        print_info "UFW not detected. Please configure your firewall manually."
    fi
}

start_service() {
    print_header "Starting CLIProxyAPI Service"

    cd $INSTALL_DIR/CLIProxyAPI

    if docker compose ps | grep -q "Up"; then
        print_warning "Service is already running"
    else
        print_info "Starting service..."
        docker compose up -d

        # Wait for service to be healthy (increased timeout)
        print_info "Waiting for service to start..."
        sleep 10

        # Check multiple times with retries
        local retries=3
        local success=false

        for i in $(seq 1 $retries); do
            if docker compose ps 2>/dev/null | grep -q "Up"; then
                success=true
                break
            fi
            print_info "Waiting... (attempt $i/$retries)"
            sleep 5
        done

        if $success; then
            print_success "CLIProxyAPI started successfully"
        else
            print_warning "Service may still be starting..."
            print_info "Check status with: cd $INSTALL_DIR/CLIProxyAPI && docker compose ps"
            print_info "Check logs with: cd $INSTALL_DIR/CLIProxyAPI && docker compose logs -f"
        fi
    fi
}

print_final_instructions() {
    print_header "Installation Complete!"

    local VPS_IP=$(hostname -I | awk '{print $1}')
    local MGMT_KEY=$(grep "MANAGEMENT_KEY=" $INSTALL_DIR/api-keys.txt 2>/dev/null | cut -d'=' -f2)
    local API_KEY=$(grep "API_KEY_1=" $INSTALL_DIR/api-keys.txt 2>/dev/null | cut -d'=' -f2)

    cat <<EOF

${GREEN}CLIProxyAPI has been successfully installed and started!${NC}

${BLUE}═══════════════════════════════════════════════════════════════${NC}
${BLUE}SERVICE STATUS${NC}
${BLUE}═══════════════════════════════════════════════════════════════${NC}
  Status: sudo systemctl status $SERVICE_NAME
  Logs:   cd $INSTALL_DIR/CLIProxyAPI && docker compose logs -f

${BLUE}═══════════════════════════════════════════════════════════════${NC}
${BLUE}CONFIGURATION${NC}
${BLUE}═══════════════════════════════════════════════════════════════${NC}
  Config file:    $INSTALL_DIR/CLIProxyAPI/config.yaml
  Auth directory: $INSTALL_DIR/auths
  Credentials:    $INSTALL_DIR/api-keys.txt

${BLUE}═══════════════════════════════════════════════════════════════${NC}
${BLUE}ACCESS URLS${NC}
${BLUE}═══════════════════════════════════════════════════════════════${NC}
  API Endpoint:      http://${VPS_IP}:8317/v1
  Management Panel:  http://${VPS_IP}:8317/management.html (Key: ${MGMT_KEY})

${BLUE}═══════════════════════════════════════════════════════════════${NC}
${BLUE}OAUTH LOGIN COMMANDS (Add AI Providers)${NC}
${BLUE}═══════════════════════════════════════════════════════════════${NC}
  cd $INSTALL_DIR/CLIProxyAPI

  # Gemini CLI (Google account)
  docker compose exec cli-proxy-api ./CLIProxyAPI -login -no-browser

  # Antigravity
  docker compose exec cli-proxy-api ./CLIProxyAPI -antigravity-login -no-browser

  # Claude Code
  docker compose exec cli-proxy-api ./CLIProxyAPI -claude-login -no-browser

  # OpenAI Codex
  docker compose exec cli-proxy-api ./CLIProxyAPI -codex-login -no-browser

  # Qwen Code
  docker compose exec cli-proxy-api ./CLIProxyAPI -qwen-login -no-browser

  # iFlow
  docker compose exec cli-proxy-api ./CLIProxyAPI -iflow-login -no-browser

${BLUE}═══════════════════════════════════════════════════════════════${NC}
${BLUE}TEST COMMANDS${NC}
${BLUE}═══════════════════════════════════════════════════════════════${NC}
  # List available models
  curl http://127.0.0.1:8317/v1/models -H "Authorization: Bearer ${API_KEY}"

  # Test chat completion
  curl http://127.0.0.1:8317/v1/chat/completions -H "Content-Type: application/json" -H "Authorization: Bearer ${API_KEY}" -d '{"model": "gemini-2.5-flash", "messages": [{"role": "user", "content": "Hello!"}]}'

${YELLOW}═══════════════════════════════════════════════════════════════${NC}
${YELLOW}IMPORTANT${NC}
${YELLOW}═══════════════════════════════════════════════════════════════${NC}
  - Your credentials are in: $INSTALL_DIR/api-keys.txt
  - Management URL with key: http://${VPS_IP}:8317/v0/management?key=${MGMT_KEY}
  - Keep these keys secure and don't share them

${BLUE}Documentation:${NC} https://help.router-for.me/

EOF
}

###############################################################################
# Main Installation Flow
###############################################################################

main() {
    print_header "CLIProxyAPI VPS Installer"

    check_root
    detect_os

    # Ask for confirmation
    print_info "This will install CLIProxyAPI to $INSTALL_DIR"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled"
        exit 0
    fi

    # Execute installation steps
    install_docker
    install_docker_compose
    setup_directories
    clone_repository
    setup_config
    setup_permissions
    create_systemd_service
    configure_firewall
    start_service

    print_final_instructions
}

# Run main function
main "$@"
