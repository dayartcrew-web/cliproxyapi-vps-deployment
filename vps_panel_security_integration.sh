#!/bin/bash

###############################################################################
# CloudPanel Integration Script
# Detects and updates existing Nginx configurations
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

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
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

clear
print_header "🔧 CloudPanel Integration Setup"
echo ""
print_info "This script will integrate CLIProxyAPI with your existing CloudPanel setup"
echo ""

###############################################################################
# Detect CloudPanel
###############################################################################

print_header "Step 1: Detecting Environment"

CLOUDPANEL_INSTALLED=false
NGINX_CONF=""
DOMAIN=""
IS_CLOUDPANEL=false

# Check if CloudPanel is installed
if [[ -d "/home/cloudpanel" ]] || command -v clpctl &> /dev/null; then
    IS_CLOUDPANEL=true
    print_success "CloudPanel detected"
else
    print_info "CloudPanel not detected - standard VPS mode"
fi

# Find existing Nginx configurations
echo ""
print_info "Scanning for existing Nginx configurations..."

if [[ -d "/etc/nginx/sites-enabled" ]]; then
    # List all configs except default
    CONFIGS=($(ls -1 /etc/nginx/sites-enabled/ 2>/dev/null | grep -v "^default$" || true))

    if [[ ${#CONFIGS[@]} -gt 0 ]]; then
        echo ""
        echo "Found existing Nginx configurations:"
        for i in "${!CONFIGS[@]}"; do
            echo "  $((i+1)). ${CONFIGS[$i]}"
        done
        echo "  $((${#CONFIGS[@]}+1)). Create new configuration"
        echo ""

        read -p "Select a configuration to update (1-$((${#CONFIGS[@]}+1))): " choice

        if [[ "$choice" -le "${#CONFIGS[@]}" ]] && [[ "$choice" -ge 1 ]]; then
            NGINX_CONF="/etc/nginx/sites-enabled/${CONFIGS[$((choice-1))]}"
            DOMAIN="${CONFIGS[$((choice-1))]}"
            print_success "Selected: $NGINX_CONF"
        else
            print_info "Will create new configuration"
        fi
    else
        print_info "No existing configurations found - will create new"
    fi
fi

# If no config selected, ask for domain
if [[ -z "$NGINX_CONF" ]]; then
    echo ""
    read -p "Enter your domain/subdomain (e.g., api.example.com): " DOMAIN

    if [[ -z "$DOMAIN" ]]; then
        print_error "Domain is required"
        exit 1
    fi

    # Check if config exists for this domain
    if [[ -f "/etc/nginx/sites-available/$DOMAIN" ]]; then
        NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
        print_info "Found existing config for $DOMAIN"
    else
        NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
        print_info "Will create new config for $DOMAIN"
    fi
fi

###############################################################################
# Detect Configuration Type
###############################################################################

print_header "Step 2: Analyzing Configuration"

BACKUP_FILE="${NGINX_CONF}.backup.$(date +%Y%m%d_%H%M%S)"

if [[ -f "$NGINX_CONF" ]]; then
    # Backup existing config
    cp "$NGINX_CONF" "$BACKUP_FILE"
    print_success "Backed up existing config to: $BACKUP_FILE"

    # Analyze config
    echo ""
    print_info "Analyzing existing configuration..."

    # Check SSL
    if grep -q "ssl_certificate" "$NGINX_CONF"; then
        print_success "SSL already configured"
        HAS_SSL=true
    else
        print_warning "No SSL detected"
        HAS_SSL=false
    fi

    # Check proxy_pass
    if grep -q "proxy_pass" "$NGINX_CONF"; then
        EXISTING_PROXY=$(grep "proxy_pass" "$NGINX_CONF" | head -1 | sed 's/.*proxy_pass \(.*\);/\1/')
        print_info "Existing proxy: $EXISTING_PROXY"
    fi

    # Check CloudPanel specific markers
    if grep -q "CLOUDPANEL" "$NGINX_CONF" || grep -q "/home/" "$NGINX_CONF"; then
        print_success "CloudPanel configuration detected"
        IS_CLOUDPANEL=true
    fi
else
    print_info "No existing configuration - will create new"
    HAS_SSL=false
fi

###############################################################################
# Update/Create Configuration
###############################################################################

print_header "Step 3: Updating Nginx Configuration"

# Function to add CLIProxyAPI location blocks
add_cliproxyapi_blocks() {
    local config_file="$1"
    local temp_file="${config_file}.tmp"

    # Check if already has CLIProxyAPI configuration
    if grep -q "# CLIProxyAPI Configuration" "$config_file"; then
        print_warning "CLIProxyAPI configuration already exists"
        return 0
    fi

    # Find the server block for port 443 or 80
    if grep -q "listen 443" "$config_file"; then
        SERVER_MARKER="listen 443"
    elif grep -q "listen 80" "$config_file"; then
        SERVER_MARKER="listen 80"
    else
        print_error "Cannot find server block in config"
        return 1
    fi

    # Create modified config
    awk -v marker="$SERVER_MARKER" '
    /'"$SERVER_MARKER"'/ {
        print
        if (!added) {
            print ""
            print "    # CLIProxyAPI Configuration"
            print "    # Added by setup script on " strftime("%Y-%m-%d %H:%M:%S")
            print ""
            print "    # Security headers"
            print "    add_header X-Robots-Tag \"noindex, nofollow, nosnippet, noarchive\" always;"
            print "    add_header X-Content-Type-Options \"nosniff\" always;"
            print "    add_header X-Frame-Options \"SAMEORIGIN\" always;"
            print "    add_header X-XSS-Protection \"1; mode=block\" always;"
            print "    add_header Referrer-Policy \"no-referrer-when-downgrade\" always;"
            print ""
            print "    # Rate limiting for API"
            print "    limit_req_zone $binary_remote_addr zone=cliproxyapi_limit:10m rate=10r/s;"
            print ""
            print "    # Proxy to CLIProxyAPI"
            print "    location / {"
            print "        limit_req zone=cliproxyapi_limit burst=20 nodelay;"
            print ""
            print "        proxy_pass http://127.0.0.1:8317;"
            print "        proxy_http_version 1.1;"
            print "        proxy_set_header Host $host;"
            print "        proxy_set_header X-Real-IP $remote_addr;"
            print "        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
            print "        proxy_set_header X-Forwarded-Proto $scheme;"
            print ""
            print "        # Timeouts"
            print "        proxy_connect_timeout 60s;"
            print "        proxy_send_timeout 60s;"
            print "        proxy_read_timeout 60s;"
            print "    }"
            print ""
            print "    # robots.txt for crawler blocking"
            print "    location = /robots.txt {"
            print "        add_header Content-Type text/plain;"
            print "        return 200 \"User-agent: *\\nDisallow: /\\n\";"
            print "    }"
            print ""
            added=1
        }
        next
    }
    { print }
    ' "$config_file" > "$temp_file"

    # Replace original
    mv "$temp_file" "$config_file"
    print_success "Added CLIProxyAPI configuration blocks"
}

# Update or create configuration
if [[ -f "$NGINX_CONF" ]]; then
    # Update existing config
    print_info "Updating existing configuration..."
    add_cliproxyapi_blocks "$NGINX_CONF"
else
    # Create new configuration
    print_info "Creating new configuration..."

    cat > "$NGINX_CONF" <<EOF
# CLIProxyAPI Configuration
# Generated on $(date)
# Domain: $DOMAIN

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    # Let's Encrypt ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Redirect to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    # SSL certificates (configure with certbot)
    # ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
    ssl_prefer_server_ciphers on;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Robots-Tag "noindex, nofollow, nosnippet, noarchive" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=cliproxyapi_limit:10m rate=10r/s;

    # Proxy to CLIProxyAPI
    location / {
        limit_req zone=cliproxyapi_limit burst=20 nodelay;

        proxy_pass http://127.0.0.1:8317;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # robots.txt
    location = /robots.txt {
        add_header Content-Type text/plain;
        return 200 "User-agent: *\\nDisallow: /\\n";
    }
}
EOF

    print_success "Created new Nginx configuration"

    # Enable site
    if [[ ! -L "/etc/nginx/sites-enabled/$DOMAIN" ]]; then
        ln -s "$NGINX_CONF" "/etc/nginx/sites-enabled/$DOMAIN"
        print_success "Enabled site configuration"
    fi
fi

###############################################################################
# Update CLIProxyAPI to bind localhost
###############################################################################

print_header "Step 4: Updating CLIProxyAPI Configuration"

CLIPROXYAPI_CONFIG="/opt/cliproxyapi/CLIProxyAPI/config.yaml"

if [[ -f "$CLIPROXYAPI_CONFIG" ]]; then
    # Backup config
    cp "$CLIPROXYAPI_CONFIG" "$CLIPROXYAPI_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"

    # Update host binding
    if grep -q 'host: "0.0.0.0"' "$CLIPROXYAPI_CONFIG"; then
        sed -i 's/host: "0.0.0.0"/host: "127.0.0.1"/' "$CLIPROXYAPI_CONFIG"
        print_success "Updated CLIProxyAPI to bind to localhost only"
    else
        print_info "CLIProxyAPI already bound to localhost"
    fi
else
    print_warning "CLIProxyAPI config not found at $CLIPROXYAPI_CONFIG"
fi

###############################################################################
# Test Configuration
###############################################################################

print_header "Step 5: Testing Configuration"

# Test Nginx
if nginx -t 2>&1 | grep -q "successful"; then
    print_success "Nginx configuration test passed"

    # Reload Nginx
    systemctl reload nginx
    print_success "Nginx reloaded"
else
    print_error "Nginx configuration test failed"
    echo ""
    nginx -t
    echo ""

    if [[ -f "$BACKUP_FILE" ]]; then
        print_warning "Restoring backup configuration..."
        cp "$BACKUP_FILE" "$NGINX_CONF"
        systemctl reload nginx
        print_info "Backup restored"
    fi

    exit 1
fi

# Restart CLIProxyAPI if config was updated
if [[ -f "$CLIPROXYAPI_CONFIG" ]]; then
    print_info "Restarting CLIProxyAPI..."
    docker compose -f /opt/cliproxyapi/CLIProxyAPI/docker-compose.yml restart
    sleep 3
    print_success "CLIProxyAPI restarted"
fi

###############################################################################
# SSL Setup Guidance
###############################################################################

print_header "Step 6: SSL Certificate Setup"

if [[ "$HAS_SSL" == "false" ]]; then
    echo ""
    print_info "SSL is not configured yet. To set up Let's Encrypt:"
    echo ""
    echo "  sudo certbot --nginx -d $DOMAIN"
    echo ""
    print_warning "After running certbot, uncomment the SSL certificate lines in:"
    echo "  $NGINX_CONF"
else
    print_success "SSL already configured"
fi

###############################################################################
# Summary
###############################################################################

print_header "✅ Integration Complete!"
echo ""

echo "Configuration Summary:"
echo "  Domain: $DOMAIN"
echo "  Nginx Config: $NGINX_CONF"
echo "  Backup: $BACKUP_FILE"
echo "  CLIProxyAPI: http://127.0.0.1:8317"
echo ""

echo "What Was Added/Updated:"
echo "  ✅ Security headers (X-Robots-Tag, X-Frame-Options, etc.)"
echo "  ✅ Rate limiting (10 requests/second)"
echo "  ✅ Reverse proxy to CLIProxyAPI"
echo "  ✅ robots.txt for crawler blocking"
echo "  ✅ CLIProxyAPI bound to localhost only"
echo ""

if [[ "$IS_CLOUDPANEL" == "true" ]]; then
    echo "CloudPanel Integration:"
    echo "  ✅ Preserved existing CloudPanel configuration"
    echo "  ✅ Added CLIProxyAPI blocks alongside existing rules"
    echo "  ✅ Compatible with CloudPanel SSL management"
    echo ""
fi

echo "Access Your Service:"
if [[ "$HAS_SSL" == "true" ]]; then
    echo "  Management Panel: https://$DOMAIN/management.html"
    echo "  API Endpoint: https://$DOMAIN/v1"
else
    echo "  Setup SSL first, then access:"
    echo "  Management Panel: https://$DOMAIN/management.html"
    echo "  API Endpoint: https://$DOMAIN/v1"
fi
echo ""

echo "Next Steps:"
if [[ "$HAS_SSL" == "false" ]]; then
    echo "  1. Run: sudo certbot --nginx -d $DOMAIN"
fi
echo "  2. Test your setup: curl -I https://$DOMAIN"
echo "  3. Access management panel: https://$DOMAIN/management.html"
echo "  4. Optional: Run 'sudo bash setup-turnstile.sh' for CAPTCHA protection"
echo ""

print_info "Nginx configuration backup saved at:"
echo "  $BACKUP_FILE"
echo ""
