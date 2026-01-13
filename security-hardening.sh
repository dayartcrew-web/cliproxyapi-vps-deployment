#!/bin/bash

###############################################################################
# CLIProxyAPI Security Hardening Script
# Automates security best practices for VPS deployment
###############################################################################

set -e

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

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root or with sudo"
    exit 1
fi

INSTALL_DIR="/opt/cliproxyapi"
CONFIG_FILE="$INSTALL_DIR/CLIProxyAPI/config.yaml"

clear
print_header "🔒 CLIProxyAPI Security Hardening"
echo ""
print_info "This script will apply security best practices to your deployment"
echo ""

# Check if CLIProxyAPI is installed
if [[ ! -d "$INSTALL_DIR" ]]; then
    print_error "CLIProxyAPI not found at $INSTALL_DIR"
    exit 1
fi

echo "Security hardening will:"
echo "  1. ✅ Install and configure UFW firewall"
echo "  2. ✅ Install Fail2ban for bot protection"
echo "  3. ✅ Bind CLIProxyAPI to localhost only"
echo "  4. ✅ Generate strong management key"
echo "  5. ✅ Configure security headers"
echo "  6. ✅ Set up rate limiting"
echo "  7. ✅ Harden SSH configuration"
echo "  8. ✅ Install Nginx reverse proxy (optional)"
echo ""

read -p "Continue with security hardening? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Security hardening cancelled"
    exit 0
fi

echo ""
print_header "Step 1: System Update"
print_info "Updating package lists..."
apt update -qq

print_success "System updated"
echo ""

###############################################################################
# Step 2: Firewall Configuration
###############################################################################

print_header "Step 2: Firewall Configuration (UFW)"

# Check if UFW is installed
if ! command -v ufw &> /dev/null; then
    print_info "Installing UFW..."
    apt install ufw -y
    print_success "UFW installed"
fi

# Configure UFW
print_info "Configuring firewall rules..."

# Allow SSH first (don't lock ourselves out!)
ufw allow 22/tcp comment 'SSH'
print_info "Allowed SSH (port 22)"

# Allow HTTP and HTTPS
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
print_info "Allowed HTTP/HTTPS (ports 80, 443)"

# Allow CLIProxyAPI only from localhost
ufw allow from 127.0.0.1 to any port 8317 comment 'CLIProxyAPI localhost'
print_info "Allowed CLIProxyAPI from localhost only"

# Enable UFW
ufw --force enable

print_success "Firewall configured and enabled"
ufw status verbose
echo ""

###############################################################################
# Step 3: Fail2ban Installation
###############################################################################

print_header "Step 3: Bot Protection (Fail2ban)"

if ! command -v fail2ban-client &> /dev/null; then
    print_info "Installing Fail2ban..."
    apt install fail2ban -y
    print_success "Fail2ban installed"
else
    print_info "Fail2ban already installed"
fi

# Configure Fail2ban for CLIProxyAPI
print_info "Configuring Fail2ban..."

cat > /etc/fail2ban/filter.d/cliproxyapi.conf <<'EOF'
[Definition]
# Detect failed authentication attempts
failregex = .*401.*Unauthorized.*<HOST>
            .*403.*Forbidden.*<HOST>
ignoreregex =
EOF

cat > /etc/fail2ban/jail.d/cliproxyapi.conf <<'EOF'
[cliproxyapi]
enabled = true
port = 8317,443
filter = cliproxyapi
logpath = /var/log/nginx/access.log
maxretry = 5
findtime = 600
bantime = 3600
action = iptables-multiport[name=cliproxyapi, port="8317,443", protocol=tcp]
EOF

systemctl restart fail2ban
print_success "Fail2ban configured"
echo ""

###############################################################################
# Step 4: Secure CLIProxyAPI Binding
###############################################################################

print_header "Step 4: Secure CLIProxyAPI Configuration"

# Backup config
print_info "Backing up config.yaml..."
cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"

# Change host binding to localhost
print_info "Binding CLIProxyAPI to localhost only..."
if grep -q 'host: "0.0.0.0"' "$CONFIG_FILE"; then
    sed -i 's/host: "0.0.0.0"/host: "127.0.0.1"/' "$CONFIG_FILE"
    print_success "Changed host binding from 0.0.0.0 to 127.0.0.1"
else
    print_info "Host binding already set to localhost"
fi

# Generate new management key if needed
current_key=$(grep "secret-key:" "$CONFIG_FILE" | grep -v "^#" | awk '{print $2}' | tr -d '"')
if [[ "$current_key" == "CHANGE_THIS_TO_SECURE_RANDOM_KEY" ]] || [[ -z "$current_key" ]]; then
    print_info "Generating strong management key (256-bit)..."
    NEW_KEY=$(openssl rand -hex 32)
    sed -i "s/secret-key: \".*\"/secret-key: \"$NEW_KEY\"/" "$CONFIG_FILE"

    # Save to api-keys.txt
    echo "" >> "$INSTALL_DIR/api-keys.txt"
    echo "# Management Key Updated: $(date)" >> "$INSTALL_DIR/api-keys.txt"
    echo "MANAGEMENT_KEY=$NEW_KEY" >> "$INSTALL_DIR/api-keys.txt"

    print_success "New management key generated and saved"
else
    print_info "Management key already configured"
fi

print_success "CLIProxyAPI configuration secured"
echo ""

###############################################################################
# Step 5: SSH Hardening
###############################################################################

print_header "Step 5: SSH Hardening"

print_warning "This will disable SSH password authentication"
print_info "Ensure you have SSH key access configured!"
echo ""
read -p "Continue with SSH hardening? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Hardening SSH configuration..."

    # Backup SSH config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)

    # Update SSH config
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

    # Restart SSH
    systemctl restart sshd

    print_success "SSH hardened (password auth disabled)"
else
    print_info "Skipping SSH hardening"
fi

echo ""

###############################################################################
# Step 6: Nginx Installation (Optional)
###############################################################################

print_header "Step 6: Nginx Reverse Proxy (Optional)"

echo "Installing Nginx will provide:"
echo "  - SSL/TLS termination"
echo "  - Rate limiting"
echo "  - Security headers"
echo "  - Better performance"
echo ""
read -p "Install and configure Nginx? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Installing Nginx..."
    apt install nginx -y

    print_info "Installing Certbot for Let's Encrypt..."
    apt install certbot python3-certbot-nginx -y

    print_success "Nginx and Certbot installed"
    echo ""

    # Get domain name
    read -p "Enter your domain name (or press Enter to skip): " DOMAIN

    if [[ ! -z "$DOMAIN" ]]; then
        print_info "Creating Nginx configuration for $DOMAIN..."

        cat > /etc/nginx/sites-available/cliproxyapi <<EOF
# CLIProxyAPI Reverse Proxy Configuration
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # SSL certificates (uncomment after running certbot)
    # ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req zone=api burst=20 nodelay;

    location / {
        proxy_pass http://127.0.0.1:8317;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

        # Enable site
        ln -sf /etc/nginx/sites-available/cliproxyapi /etc/nginx/sites-enabled/

        # Test config
        if nginx -t 2>&1 | grep -q "successful"; then
            systemctl reload nginx
            print_success "Nginx configuration created"
            echo ""
            print_info "Next steps:"
            echo "  1. Ensure DNS points to this server"
            echo "  2. Run: sudo certbot --nginx -d $DOMAIN"
            echo "  3. Uncomment SSL lines in /etc/nginx/sites-available/cliproxyapi"
        else
            print_error "Nginx configuration test failed"
        fi
    else
        print_info "Skipping Nginx configuration (no domain provided)"
    fi
else
    print_info "Skipping Nginx installation"
fi

echo ""

###############################################################################
# Step 7: Restart CLIProxyAPI
###############################################################################

print_header "Step 7: Applying Changes"

print_info "Restarting CLIProxyAPI..."
docker compose -f "$INSTALL_DIR/CLIProxyAPI/docker-compose.yml" restart

sleep 5
print_success "CLIProxyAPI restarted"
echo ""

###############################################################################
# Summary
###############################################################################

print_header "✅ Security Hardening Complete!"
echo ""

echo "Applied Security Measures:"
echo "  ✅ UFW firewall enabled and configured"
echo "  ✅ Fail2ban installed for bot protection"
echo "  ✅ CLIProxyAPI bound to localhost only"
echo "  ✅ Strong management key generated"

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "  ✅ SSH password authentication disabled"
fi

echo ""
echo "Configuration Files:"
echo "  Config backup: $CONFIG_FILE.backup.*"
echo "  SSH backup: /etc/ssh/sshd_config.backup.*"
echo "  Firewall rules: sudo ufw status"
echo "  Fail2ban status: sudo fail2ban-client status"
echo ""

echo "Next Steps:"
echo "  1. Review SECURITY.md for complete security guide"
echo "  2. Set up SSL certificate with Let's Encrypt"
echo "  3. Configure Nginx reverse proxy (if not done)"
echo "  4. Test your deployment: https://$DOMAIN"
echo "  5. Monitor logs regularly"
echo ""

print_warning "IMPORTANT: Save your new management key:"
echo ""
tail -2 "$INSTALL_DIR/api-keys.txt"
echo ""

print_info "Firewall Status:"
ufw status verbose
echo ""

print_info "For SSL setup, run:"
echo "  sudo certbot --nginx -d $DOMAIN"
echo ""
