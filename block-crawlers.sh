#!/bin/bash

###############################################################################
# Prevent Search Engine Indexing
# Adds robots.txt and meta tags to block crawlers
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
print_header "🚫 Block Search Engine Crawlers"
echo ""
print_info "This will prevent Google, Bing, and other search engines from indexing your site"
echo ""

# Check if Nginx is installed
if ! command -v nginx &> /dev/null; then
    print_error "Nginx is not installed"
    echo ""
    print_info "This script requires Nginx. Install with:"
    echo "  sudo apt install nginx -y"
    exit 1
fi

NGINX_SITES="/etc/nginx/sites-available"
CLIPROXYAPI_CONF="$NGINX_SITES/cliproxyapi"

if [[ ! -f "$CLIPROXYAPI_CONF" ]]; then
    print_error "Nginx configuration not found at $CLIPROXYAPI_CONF"
    echo ""
    print_info "Run security-hardening.sh first to set up Nginx"
    exit 1
fi

###############################################################################
# Create robots.txt
###############################################################################

print_header "Step 1: Creating robots.txt"

WEB_ROOT="/var/www/cliproxyapi"
mkdir -p "$WEB_ROOT"

cat > "$WEB_ROOT/robots.txt" <<'EOF'
# Block all search engine crawlers
User-agent: *
Disallow: /

# Specific crawler blocks
User-agent: Googlebot
Disallow: /

User-agent: Googlebot-Image
Disallow: /

User-agent: Bingbot
Disallow: /

User-agent: Slurp
Disallow: /

User-agent: DuckDuckBot
Disallow: /

User-agent: Baiduspider
Disallow: /

User-agent: YandexBot
Disallow: /

User-agent: ia_archiver
Disallow: /
EOF

chmod 644 "$WEB_ROOT/robots.txt"
print_success "Created robots.txt blocking all crawlers"

###############################################################################
# Update Nginx Configuration
###############################################################################

print_header "Step 2: Updating Nginx Configuration"

# Backup current config
cp "$CLIPROXYAPI_CONF" "$CLIPROXYAPI_CONF.backup.$(date +%Y%m%d_%H%M%S)"
print_info "Backed up Nginx configuration"

# Check if robots.txt location already exists
if grep -q "location = /robots.txt" "$CLIPROXYAPI_CONF"; then
    print_info "robots.txt location already configured"
else
    # Add robots.txt location to server block
    sed -i '/server_name/a\
\
    # Serve robots.txt\
    location = /robots.txt {\
        root /var/www/cliproxyapi;\
        allow all;\
        log_not_found off;\
        access_log off;\
    }' "$CLIPROXYAPI_CONF"

    print_success "Added robots.txt location"
fi

# Add X-Robots-Tag header if not exists
if grep -q "X-Robots-Tag" "$CLIPROXYAPI_CONF"; then
    print_info "X-Robots-Tag header already configured"
else
    # Add to server block (after ssl_certificate if exists, otherwise after server_name)
    if grep -q "ssl_certificate" "$CLIPROXYAPI_CONF"; then
        sed -i '/ssl_certificate_key/a\
\
    # Prevent indexing via HTTP header\
    add_header X-Robots-Tag "noindex, nofollow, nosnippet, noarchive" always;' "$CLIPROXYAPI_CONF"
    else
        sed -i '/server_name/a\
\
    # Prevent indexing via HTTP header\
    add_header X-Robots-Tag "noindex, nofollow, nosnippet, noarchive" always;' "$CLIPROXYAPI_CONF"
    fi

    print_success "Added X-Robots-Tag header"
fi

###############################################################################
# Test and Reload Nginx
###############################################################################

print_header "Step 3: Testing Configuration"

if nginx -t 2>&1 | grep -q "successful"; then
    print_success "Nginx configuration test passed"

    systemctl reload nginx
    print_success "Nginx reloaded"
else
    print_error "Nginx configuration test failed"
    echo ""
    nginx -t
    echo ""
    print_info "Restoring backup configuration..."
    cp "$CLIPROXYAPI_CONF.backup."* "$CLIPROXYAPI_CONF"
    systemctl reload nginx
    exit 1
fi

###############################################################################
# Summary
###############################################################################

print_header "✅ Crawler Blocking Complete!"
echo ""

echo "Configuration Applied:"
echo "  ✅ robots.txt blocks all crawlers"
echo "  ✅ X-Robots-Tag HTTP header added"
echo "  ✅ Nginx configuration updated"
echo ""

echo "What This Does:"
echo "  🚫 Prevents Google from indexing your site"
echo "  🚫 Prevents Bing from indexing your site"
echo "  🚫 Prevents all other search engines"
echo "  🚫 Blocks archive.org (Wayback Machine)"
echo ""

echo "Test Your Configuration:"
echo "  1. Check robots.txt:"
echo "     curl http://your-domain.com/robots.txt"
echo ""
echo "  2. Check HTTP headers:"
echo "     curl -I https://your-domain.com"
echo "     (Look for: X-Robots-Tag: noindex)"
echo ""

echo "Files Created/Modified:"
echo "  📄 /var/www/cliproxyapi/robots.txt"
echo "  📄 $CLIPROXYAPI_CONF"
echo "  💾 Backup: $CLIPROXYAPI_CONF.backup.*"
echo ""

print_info "Your site will NOT appear in search engine results"
echo ""
