#!/bin/bash

###############################################################################
# Cloudflare Turnstile Setup for Management Panel
# Adds CAPTCHA protection to /management.html
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
print_header "🛡️ Cloudflare Turnstile Setup"
echo ""
print_info "This will add CAPTCHA protection to /management.html"
echo ""

# Check prerequisites
if ! command -v nginx &> /dev/null; then
    print_error "Nginx is not installed. Install it first."
    exit 1
fi

if ! command -v node &> /dev/null; then
    print_warning "Node.js is not installed. Installing..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    print_success "Node.js installed"
fi

TURNSTILE_DIR="/opt/cliproxyapi/turnstile"

# Detect existing Nginx configurations
print_info "Detecting Nginx configuration..."

NGINX_CONF=""
DOMAIN=""

# Check for existing configs
CONFIGS=($(ls -1 /etc/nginx/sites-enabled/ 2>/dev/null | grep -v "^default$" || true))

if [[ ${#CONFIGS[@]} -gt 1 ]]; then
    echo ""
    echo "Found multiple Nginx configurations:"
    for i in "${!CONFIGS[@]}"; do
        echo "  $((i+1)). ${CONFIGS[$i]}"
    done
    echo ""

    read -p "Select configuration to update (1-${#CONFIGS[@]}): " choice

    if [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#CONFIGS[@]}" ]]; then
        NGINX_CONF="/etc/nginx/sites-available/${CONFIGS[$((choice-1))]}"
        DOMAIN="${CONFIGS[$((choice-1))]}"
    fi
elif [[ ${#CONFIGS[@]} -eq 1 ]]; then
    NGINX_CONF="/etc/nginx/sites-available/${CONFIGS[0]}"
    DOMAIN="${CONFIGS[0]}"
elif [[ -f "/etc/nginx/sites-available/cliproxyapi" ]]; then
    NGINX_CONF="/etc/nginx/sites-available/cliproxyapi"
fi

if [[ -z "$NGINX_CONF" ]] || [[ ! -f "$NGINX_CONF" ]]; then
    print_error "No Nginx configuration found"
    print_info "Please run vps_panel_security_integration.sh or security-hardening.sh first"
    exit 1
fi

print_success "Using config: $NGINX_CONF"

###############################################################################
# Get Cloudflare Turnstile Keys
###############################################################################

print_header "Step 1: Cloudflare Turnstile Configuration"
echo ""
echo "To get your Turnstile keys:"
echo "  1. Go to: https://dash.cloudflare.com/"
echo "  2. Select 'Turnstile' from the left menu"
echo "  3. Click 'Add Site'"
echo "  4. Enter your domain name"
echo "  5. Choose 'Managed' mode (recommended)"
echo "  6. Copy the Site Key and Secret Key"
echo ""

read -p "Enter your Cloudflare Turnstile Site Key: " SITE_KEY
read -p "Enter your Cloudflare Turnstile Secret Key: " SECRET_KEY

if [[ -z "$SITE_KEY" ]] || [[ -z "$SECRET_KEY" ]]; then
    print_error "Both Site Key and Secret Key are required"
    exit 1
fi

if [[ -z "$DOMAIN" ]]; then
    read -p "Enter your domain name (e.g., example.com): " DOMAIN
fi

if [[ -z "$DOMAIN" ]]; then
    print_error "Domain name is required"
    exit 1
fi

###############################################################################
# Create Turnstile Validation Server
###############################################################################

print_header "Step 2: Creating Validation Server"

mkdir -p "$TURNSTILE_DIR"
cd "$TURNSTILE_DIR"

# Create package.json
cat > package.json <<EOF
{
  "name": "turnstile-validator",
  "version": "1.0.0",
  "description": "Cloudflare Turnstile validator for CLIProxyAPI",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cookie-parser": "^1.4.6",
    "body-parser": "^1.20.2"
  }
}
EOF

# Install dependencies
print_info "Installing Node.js dependencies..."
npm install --silent

# Create validation server
cat > server.js <<'SERVEREOF'
const express = require('express');
const cookieParser = require('cookie-parser');
const bodyParser = require('body-parser');
const https = require('https');
const crypto = require('crypto');

const app = express();
const PORT = 3737;

// Cloudflare Turnstile credentials (will be replaced)
const TURNSTILE_SECRET = 'TURNSTILE_SECRET_KEY';
const SESSION_SECRET = crypto.randomBytes(32).toString('hex');

// Store valid sessions (in production, use Redis or database)
const validSessions = new Map();
const SESSION_TIMEOUT = 3600000; // 1 hour

app.use(cookieParser());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Verify Turnstile token with Cloudflare
function verifyTurnstile(token, ip) {
    return new Promise((resolve, reject) => {
        const data = new URLSearchParams({
            secret: TURNSTILE_SECRET,
            response: token,
            remoteip: ip
        }).toString();

        const options = {
            hostname: 'challenges.cloudflare.com',
            port: 443,
            path: '/turnstile/v0/siteverify',
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Content-Length': data.length
            }
        };

        const req = https.request(options, (res) => {
            let body = '';
            res.on('data', (chunk) => body += chunk);
            res.on('end', () => {
                try {
                    const result = JSON.parse(body);
                    resolve(result);
                } catch (e) {
                    reject(e);
                }
            });
        });

        req.on('error', reject);
        req.write(data);
        req.end();
    });
}

// Validate Turnstile token
app.post('/validate', async (req, res) => {
    const { token } = req.body;
    const ip = req.headers['x-real-ip'] || req.ip;

    if (!token) {
        return res.status(400).json({ success: false, error: 'No token provided' });
    }

    try {
        const result = await verifyTurnstile(token, ip);

        if (result.success) {
            // Create session
            const sessionId = crypto.randomBytes(32).toString('hex');
            validSessions.set(sessionId, {
                created: Date.now(),
                ip: ip
            });

            // Clean old sessions
            for (const [key, value] of validSessions.entries()) {
                if (Date.now() - value.created > SESSION_TIMEOUT) {
                    validSessions.delete(key);
                }
            }

            res.json({
                success: true,
                sessionId: sessionId
            });
        } else {
            res.status(403).json({
                success: false,
                error: 'Turnstile verification failed',
                details: result['error-codes']
            });
        }
    } catch (error) {
        console.error('Turnstile verification error:', error);
        res.status(500).json({
            success: false,
            error: 'Internal server error'
        });
    }
});

// Check if session is valid
app.get('/check', (req, res) => {
    const sessionId = req.headers['x-session-id'] || req.cookies.turnstile_session;

    if (!sessionId || !validSessions.has(sessionId)) {
        return res.status(401).json({ valid: false });
    }

    const session = validSessions.get(sessionId);

    // Check if session expired
    if (Date.now() - session.created > SESSION_TIMEOUT) {
        validSessions.delete(sessionId);
        return res.status(401).json({ valid: false, error: 'Session expired' });
    }

    res.json({ valid: true });
});

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'ok', sessions: validSessions.size });
});

app.listen(PORT, '127.0.0.1', () => {
    console.log(`Turnstile validator running on http://127.0.0.1:${PORT}`);
    console.log(`Active sessions: ${validSessions.size}`);
});
SERVEREOF

# Replace secret key
sed -i "s/TURNSTILE_SECRET_KEY/$SECRET_KEY/" server.js

print_success "Validation server created"

###############################################################################
# Create Turnstile Challenge Page
###############################################################################

print_header "Step 3: Creating Challenge Page"

cat > challenge.html <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Security Check - CLIProxyAPI Management</title>
    <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            max-width: 500px;
            width: 100%;
            text-align: center;
        }
        .logo {
            font-size: 48px;
            margin-bottom: 20px;
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 24px;
        }
        p {
            color: #666;
            margin-bottom: 30px;
            line-height: 1.6;
        }
        .turnstile-container {
            display: flex;
            justify-content: center;
            margin: 30px 0;
        }
        .loading {
            display: none;
            color: #667eea;
            font-size: 16px;
            margin-top: 20px;
        }
        .loading.active {
            display: block;
        }
        .error {
            display: none;
            background: #fee;
            color: #c33;
            padding: 12px;
            border-radius: 6px;
            margin-top: 20px;
        }
        .error.active {
            display: block;
        }
        .success {
            display: none;
            background: #efe;
            color: #3c3;
            padding: 12px;
            border-radius: 6px;
            margin-top: 20px;
        }
        .success.active {
            display: block;
        }
        .footer {
            margin-top: 30px;
            color: #999;
            font-size: 12px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🛡️</div>
        <h1>Security Verification</h1>
        <p>Please complete the security check to access the CLIProxyAPI Management Panel.</p>

        <div class="turnstile-container">
            <div class="cf-turnstile"
                 data-sitekey="SITE_KEY_PLACEHOLDER"
                 data-callback="onTurnstileSuccess"
                 data-error-callback="onTurnstileError">
            </div>
        </div>

        <div class="loading">
            <p>Verifying... Please wait.</p>
        </div>

        <div class="error">
            <p id="error-message">Verification failed. Please try again.</p>
        </div>

        <div class="success">
            <p>✓ Verification successful! Redirecting...</p>
        </div>

        <div class="footer">
            Protected by Cloudflare Turnstile<br>
            CLIProxyAPI Management Panel
        </div>
    </div>

    <script>
        function onTurnstileSuccess(token) {
            document.querySelector('.loading').classList.add('active');
            document.querySelector('.error').classList.remove('active');

            fetch('/turnstile/validate', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ token: token })
            })
            .then(response => response.json())
            .then(data => {
                document.querySelector('.loading').classList.remove('active');

                if (data.success) {
                    // Set session cookie
                    document.cookie = 'turnstile_session=' + data.sessionId + '; path=/; max-age=3600; secure; samesite=strict';

                    // Show success message
                    document.querySelector('.success').classList.add('active');

                    // Redirect to management panel
                    setTimeout(() => {
                        window.location.href = '/management.html';
                    }, 1500);
                } else {
                    document.querySelector('.error').classList.add('active');
                    document.getElementById('error-message').textContent =
                        data.error || 'Verification failed. Please try again.';
                }
            })
            .catch(error => {
                document.querySelector('.loading').classList.remove('active');
                document.querySelector('.error').classList.add('active');
                document.getElementById('error-message').textContent =
                    'Network error. Please try again.';
                console.error('Error:', error);
            });
        }

        function onTurnstileError(error) {
            document.querySelector('.error').classList.add('active');
            document.getElementById('error-message').textContent =
                'Turnstile widget failed to load. Please refresh the page.';
            console.error('Turnstile error:', error);
        }
    </script>
</body>
</html>
HTMLEOF

# Replace site key
sed -i "s/SITE_KEY_PLACEHOLDER/$SITE_KEY/" challenge.html

print_success "Challenge page created"

###############################################################################
# Create systemd service
###############################################################################

print_header "Step 4: Creating Systemd Service"

cat > /etc/systemd/system/turnstile-validator.service <<EOF
[Unit]
Description=Cloudflare Turnstile Validator
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$TURNSTILE_DIR
ExecStart=/usr/bin/node $TURNSTILE_DIR/server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable turnstile-validator
systemctl start turnstile-validator

sleep 2

if systemctl is-active --quiet turnstile-validator; then
    print_success "Turnstile validator service started"
else
    print_error "Failed to start turnstile validator service"
    journalctl -u turnstile-validator -n 20
    exit 1
fi

###############################################################################
# Update Nginx Configuration
###############################################################################

print_header "Step 5: Updating Nginx Configuration"

# Backup current config
cp "$NGINX_CONF" "$NGINX_CONF.backup.$(date +%Y%m%d_%H%M%S)"

# Add Turnstile configuration
cat > /etc/nginx/conf.d/turnstile.conf <<'EOF'
# Turnstile validation upstream
upstream turnstile_validator {
    server 127.0.0.1:3737;
}

# Map to check session validity
map $cookie_turnstile_session $session_valid {
    default 0;
    ~. 1;
}
EOF

# Update main nginx config to add Turnstile protection
# Add after server_name in the HTTPS server block
if ! grep -q "location = /turnstile-challenge" "$NGINX_CONF"; then
    sed -i '/server_name '"$DOMAIN"';/a\
\
    # Turnstile Challenge Page\
    location = /turnstile-challenge {\
        root '"$TURNSTILE_DIR"';\
        try_files /challenge.html =404;\
    }\
\
    # Turnstile Validation Endpoint\
    location /turnstile/ {\
        proxy_pass http://turnstile_validator/;\
        proxy_set_header X-Real-IP $remote_addr;\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\
    }\
\
    # Protected Management Panel\
    location = /management.html {\
        # Check session cookie\
        if ($cookie_turnstile_session = "") {\
            return 302 /turnstile-challenge;\
        }\
\
        # Validate session with backend\
        auth_request /turnstile/check;\
        auth_request_set $auth_status $upstream_status;\
\
        # If validation fails, redirect to challenge\
        error_page 401 = /turnstile-challenge;\
\
        # Proxy to CLIProxyAPI\
        proxy_pass http://127.0.0.1:8317;\
        proxy_set_header Host $host;\
        proxy_set_header X-Real-IP $remote_addr;\
    }' "$NGINX_CONF"

    print_success "Nginx configuration updated"
else
    print_info "Turnstile configuration already present"
fi

# Test Nginx config
if nginx -t 2>&1 | grep -q "successful"; then
    print_success "Nginx configuration test passed"
    systemctl reload nginx
    print_success "Nginx reloaded"
else
    print_error "Nginx configuration test failed"
    nginx -t
    print_info "Restoring backup..."
    cp "$NGINX_CONF.backup."* "$NGINX_CONF"
    systemctl reload nginx
    exit 1
fi

###############################################################################
# Summary
###############################################################################

print_header "✅ Cloudflare Turnstile Setup Complete!"
echo ""

echo "Configuration Summary:"
echo "  ✅ Turnstile validator service running on port 3737"
echo "  ✅ Challenge page created at /turnstile-challenge"
echo "  ✅ Management panel protected with CAPTCHA"
echo "  ✅ Session timeout: 1 hour"
echo ""

echo "What Happens Now:"
echo "  1. User visits: https://$DOMAIN/management.html"
echo "  2. Redirected to: https://$DOMAIN/turnstile-challenge"
echo "  3. User completes Cloudflare Turnstile challenge"
echo "  4. Token validated with Cloudflare API"
echo "  5. Session cookie created (1 hour validity)"
echo "  6. User redirected to management panel"
echo ""

echo "Testing:"
echo "  Visit: https://$DOMAIN/management.html"
echo "  You should see the Turnstile challenge page"
echo ""

echo "Service Management:"
echo "  Status:  sudo systemctl status turnstile-validator"
echo "  Restart: sudo systemctl restart turnstile-validator"
echo "  Logs:    sudo journalctl -u turnstile-validator -f"
echo ""

echo "Configuration Files:"
echo "  Validator: $TURNSTILE_DIR/server.js"
echo "  Challenge: $TURNSTILE_DIR/challenge.html"
echo "  Nginx:     $NGINX_CONF"
echo "  Service:   /etc/systemd/system/turnstile-validator.service"
echo ""

print_warning "Note: Only humans who pass the Turnstile challenge can access /management.html"
print_info "Bots and automated scripts will be blocked"
echo ""
