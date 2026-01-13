# CLIProxyAPI Security Hardening Guide

Complete guide to securing your CLIProxyAPI VPS deployment against bots, injection attacks, and setting up SSL/TLS certificates.

## Table of Contents

- [SSL/TLS Certificate Setup](#ssltls-certificate-setup)
- [Bot Protection](#bot-protection)
- [XSS & Injection Prevention](#xss--injection-prevention)
- [Network Security](#network-security)
- [Authentication & Access Control](#authentication--access-control)
- [Monitoring & Logging](#monitoring--logging)
- [Security Checklist](#security-checklist)

---

## SSL/TLS Certificate Setup

### Option 1: Nginx Reverse Proxy with Let's Encrypt (Recommended)

**Step 1: Install Nginx and Certbot**

```bash
# Update system
sudo apt update

# Install Nginx
sudo apt install nginx -y

# Install Certbot for Let's Encrypt
sudo apt install certbot python3-certbot-nginx -y
```

**Step 2: Configure Nginx Reverse Proxy**

```bash
# Create Nginx configuration
sudo nano /etc/nginx/sites-available/cliproxyapi
```

Add this configuration:

```nginx
# HTTP - Redirect to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name your-domain.com;

    # Let's Encrypt ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Redirect all HTTP to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS - Reverse Proxy to CLIProxyAPI
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name your-domain.com;

    # SSL certificates (will be added by Certbot)
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Content Security Policy
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'" always;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_req zone=api_limit burst=20 nodelay;

    # Proxy settings
    location / {
        proxy_pass http://localhost:8317;
        proxy_http_version 1.1;

        # Preserve original request info
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # Buffer settings
        proxy_buffering off;
        proxy_request_buffering off;
    }

    # Management panel - Additional rate limiting
    location /management.html {
        limit_req zone=api_limit burst=5 nodelay;
        proxy_pass http://localhost:8317;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Management API - Extra protection
    location /v0/management/ {
        limit_req zone=api_limit burst=5 nodelay;
        proxy_pass http://localhost:8317;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Deny access to sensitive files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
```

**Step 3: Enable Site and Obtain SSL Certificate**

```bash
# Enable the site
sudo ln -s /etc/nginx/sites-available/cliproxyapi /etc/nginx/sites-enabled/

# Test Nginx configuration
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx

# Obtain SSL certificate from Let's Encrypt
sudo certbot --nginx -d your-domain.com

# Follow prompts:
# - Enter your email
# - Agree to terms
# - Choose to redirect HTTP to HTTPS (option 2)
```

**Step 4: Set Up Auto-Renewal**

```bash
# Test renewal
sudo certbot renew --dry-run

# Certbot auto-renewal is set up via systemd timer
sudo systemctl status certbot.timer

# Manual renewal (if needed)
sudo certbot renew
```

**Step 5: Update CLIProxyAPI Configuration**

```bash
# Edit config.yaml
sudo nano /opt/cliproxyapi/CLIProxyAPI/config.yaml
```

Update binding (since Nginx handles external traffic):

```yaml
# CLIProxyAPI only needs to listen on localhost
host: "127.0.0.1"  # Changed from 0.0.0.0
port: 8317
```

Restart CLIProxyAPI:

```bash
cd /opt/cliproxyapi/CLIProxyAPI
docker compose restart
```

---

### Option 2: Caddy (Automatic HTTPS)

Caddy automatically obtains and renews SSL certificates.

**Install Caddy:**

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy
```

**Configure Caddy:**

```bash
sudo nano /etc/caddy/Caddyfile
```

```caddy
your-domain.com {
    # Automatic HTTPS

    # Security headers
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "no-referrer-when-downgrade"
        Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
    }

    # Rate limiting (requires Caddy plugin)
    # Or use external rate limiter like fail2ban

    # Reverse proxy to CLIProxyAPI
    reverse_proxy localhost:8317
}
```

**Restart Caddy:**

```bash
sudo systemctl reload caddy
```

---

## Bot Protection

### 1. Rate Limiting with Fail2ban

**Install Fail2ban:**

```bash
sudo apt install fail2ban -y
```

**Create Fail2ban Filter for CLIProxyAPI:**

```bash
sudo nano /etc/fail2ban/filter.d/cliproxyapi.conf
```

```ini
[Definition]
# Detect too many failed authentication attempts
failregex = .*"Authorization: Bearer.*" 401 .*<HOST>
            .*401.*Unauthorized.*<HOST>
            .*403.*Forbidden.*<HOST>

ignoreregex =
```

**Create Jail Configuration:**

```bash
sudo nano /etc/fail2ban/jail.d/cliproxyapi.conf
```

```ini
[cliproxyapi]
enabled = true
port = 8317,443
filter = cliproxyapi
logpath = /var/log/nginx/access.log
maxretry = 5
findtime = 600
bantime = 3600
action = iptables-multiport[name=cliproxyapi, port="8317,443", protocol=tcp]
```

**Restart Fail2ban:**

```bash
sudo systemctl restart fail2ban
sudo fail2ban-client status cliproxyapi
```

### 2. IP Whitelisting (Optional)

For management endpoints, restrict to trusted IPs:

**In Nginx:**

```nginx
location /v0/management/ {
    # Allow specific IPs
    allow 203.0.113.10;  # Your office IP
    allow 198.51.100.0/24;  # Your network
    deny all;

    proxy_pass http://localhost:8317;
}
```

**In UFW Firewall:**

```bash
# Allow API from anywhere
sudo ufw allow 443/tcp

# Limit connections to management port
sudo ufw limit 8317/tcp

# Allow specific IP for management
sudo ufw allow from 203.0.113.10 to any port 8317
```

### 3. API Key Rotation

Regularly rotate API keys:

```bash
# Generate new API key
NEW_KEY=$(openssl rand -hex 16)

# Add to CLIProxyAPI
curl -X PATCH -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $MGMT_KEY" \
  -d "{\"old\": \"old-key\", \"new\": \"$NEW_KEY\"}" \
  http://localhost:8317/v0/management/api-keys

# Update clients
# Remove old key after migration
```

### 4. Request Throttling in config.yaml

```yaml
# In CLIProxyAPI config.yaml
rate-limiting:
  enabled: true
  requests-per-minute: 60
  burst: 100
```

### 5. Block Search Engine Crawlers (No-Index/No-Follow)

**Prevent indexing by Google, Bing, and other search engines:**

```bash
# Run automated script
sudo bash block-crawlers.sh
```

### 6. Cloudflare Turnstile Protection (CAPTCHA for Management Panel)

**Add CAPTCHA challenge to /management.html to block bots:**

```bash
# Run automated setup
sudo bash setup-turnstile.sh
```

**What it does:**
- ✅ Requires human verification to access management panel
- ✅ Blocks automated bots and scripts
- ✅ Session-based access (1 hour validity)
- ✅ Cloudflare-powered bot detection

**Setup Steps:**

1. **Get Cloudflare Turnstile Keys:**
   - Visit: https://dash.cloudflare.com/
   - Go to Turnstile section
   - Add your site
   - Copy Site Key and Secret Key

2. **Run Setup Script:**
   ```bash
   sudo bash setup-turnstile.sh
   # Enter your Site Key
   # Enter your Secret Key
   # Enter your domain name
   ```

3. **How It Works:**
   ```
   User visits /management.html
   → Redirected to /turnstile-challenge
   → User completes CAPTCHA
   → Token validated with Cloudflare API
   → Session cookie created (1 hour)
   → Access granted to /management.html
   ```

**Manual Configuration (if needed):**

See the detailed setup in `setup-turnstile.sh` or configure manually:

1. Install Node.js validation server
2. Create challenge page with Turnstile widget
3. Configure Nginx to protect /management.html
4. Set up session validation

**Service Management:**

```bash
# Check status
sudo systemctl status turnstile-validator

# View logs
sudo journalctl -u turnstile-validator -f

# Restart service
sudo systemctl restart turnstile-validator
```

**Configuration:**
- Validator runs on: `http://127.0.0.1:3737`
- Challenge page: `/turnstile-challenge`
- Session timeout: 1 hour
- Protected endpoints: `/management.html`

**Manual Configuration:**

**Create robots.txt:**

```bash
# Create web root
sudo mkdir -p /var/www/cliproxyapi

# Create robots.txt
sudo nano /var/www/cliproxyapi/robots.txt
```

```txt
# Block all search engine crawlers
User-agent: *
Disallow: /

# Specific crawlers
User-agent: Googlebot
Disallow: /

User-agent: Bingbot
Disallow: /

User-agent: ia_archiver
Disallow: /
```

**Add to Nginx configuration:**

```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;

    # Prevent indexing via HTTP header
    add_header X-Robots-Tag "noindex, nofollow, nosnippet, noarchive" always;

    # Serve robots.txt
    location = /robots.txt {
        root /var/www/cliproxyapi;
        allow all;
        log_not_found off;
        access_log off;
    }

    # Rest of configuration...
}
```

**Reload Nginx:**

```bash
sudo nginx -t
sudo systemctl reload nginx
```

**Test:**

```bash
# Check robots.txt
curl http://your-domain.com/robots.txt

# Check HTTP headers
curl -I https://your-domain.com | grep -i robot
# Should show: X-Robots-Tag: noindex, nofollow, nosnippet, noarchive
```

**What This Blocks:**
- ✅ Google search indexing
- ✅ Bing search indexing
- ✅ All other search engines
- ✅ Archive.org (Wayback Machine)
- ✅ AI crawlers (ChatGPT, Bard, etc.)
- ✅ Image search indexing
- ✅ Snippet/preview generation

---

## XSS & Injection Prevention

### 1. Input Validation

CLIProxyAPI validates inputs, but add extra protection at the reverse proxy level:

**Nginx ModSecurity:**

```bash
# Install ModSecurity
sudo apt install libnginx-mod-security -y

# Copy recommended config
sudo cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf

# Enable ModSecurity
sudo nano /etc/modsecurity/modsecurity.conf
```

Change `SecRuleEngine DetectionOnly` to:
```
SecRuleEngine On
```

**Add OWASP Core Rule Set:**

```bash
cd /etc/modsecurity
sudo git clone https://github.com/coreruleset/coreruleset.git
sudo mv coreruleset/crs-setup.conf.example crs-setup.conf
sudo mv coreruleset/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example \
   coreruleset/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
```

### 2. Content Security Policy

Already included in Nginx config above. For direct CLIProxyAPI deployment:

```yaml
# In config.yaml (if supported by CLIProxyAPI)
security-headers:
  Content-Security-Policy: "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
  X-Content-Type-Options: "nosniff"
  X-Frame-Options: "SAMEORIGIN"
  X-XSS-Protection: "1; mode=block"
```

### 3. API Key Requirements

**Enforce API keys for all requests:**

```yaml
# config.yaml
api-keys:
  - "your-strong-api-key-1"
  - "your-strong-api-key-2"

# Disable API key bypass
allow-no-api-key: false
```

### 4. CORS Configuration

**Restrict CORS to trusted domains:**

```yaml
# config.yaml
cors:
  enabled: true
  allowed-origins:
    - "https://your-frontend-domain.com"
    - "https://app.your-domain.com"
  allowed-methods:
    - GET
    - POST
  allowed-headers:
    - Authorization
    - Content-Type
```

**In Nginx (if CLIProxyAPI doesn't support):**

```nginx
# Add to server block
add_header Access-Control-Allow-Origin "https://your-domain.com" always;
add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;
add_header Access-Control-Allow-Credentials "true" always;

if ($request_method = OPTIONS) {
    return 204;
}
```

---

## Network Security

### 1. Firewall Configuration

```bash
# Enable UFW
sudo ufw enable

# Allow SSH (important - don't lock yourself out!)
sudo ufw allow 22/tcp

# Allow HTTPS
sudo ufw allow 443/tcp

# Allow HTTP (for Let's Encrypt challenges)
sudo ufw allow 80/tcp

# If using Nginx, BLOCK direct access to CLIProxyAPI port
sudo ufw deny 8317/tcp

# Or allow only from localhost
sudo ufw allow from 127.0.0.1 to any port 8317

# Check status
sudo ufw status verbose
```

### 2. Docker Network Isolation

```yaml
# docker-compose.yml
version: '3.8'
services:
  cli-proxy-api:
    image: eceasy/cli-proxy-api:latest
    container_name: cli-proxy-api
    restart: unless-stopped
    networks:
      - cliproxyapi_internal
    ports:
      # Only expose to localhost
      - "127.0.0.1:8317:8317"
    volumes:
      - ./config.yaml:/CLIProxyAPI/config.yaml:ro
      - /opt/cliproxyapi/auths:/root/.cli-proxy-api

networks:
  cliproxyapi_internal:
    driver: bridge
    internal: false
```

### 3. SSH Hardening

```bash
# Disable password authentication
sudo nano /etc/ssh/sshd_config
```

Set:
```
PasswordAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
```

Restart SSH:
```bash
sudo systemctl restart sshd
```

---

## Authentication & Access Control

### 1. Strong Management Keys

```bash
# Generate strong management key (256-bit)
openssl rand -hex 32

# Update in config.yaml
secret-key: "your-256-bit-key-here"
```

### 2. Separate API Keys for Different Services

```yaml
# config.yaml
api-keys:
  - "frontend-app-key-xxxxxxxx"      # For frontend
  - "mobile-app-key-yyyyyyyy"        # For mobile
  - "internal-service-key-zzzzzzzz"  # For internal services
```

Track which key is used by which service.

### 3. Disable Unnecessary Features

```yaml
# Disable control panel if not needed
remote-management:
  disable-control-panel: true  # API-only mode

# Disable unused providers
# Remove unused OAuth logins
```

---

## Monitoring & Logging

### 1. Enable Detailed Logging

```bash
# Create log directory
sudo mkdir -p /opt/cliproxyapi/logs

# Update docker-compose.yml
docker compose logs -f > /opt/cliproxyapi/logs/cliproxyapi.log &
```

### 2. Monitor Failed Authentication

```bash
# Watch for failed auth attempts
sudo tail -f /var/log/nginx/access.log | grep "401\|403"

# Check Fail2ban status
sudo fail2ban-client status cliproxyapi
```

### 3. Set Up Alerts

**Install monitoring (optional):**

```bash
# Simple log monitoring with logwatch
sudo apt install logwatch -y

# Configure daily email reports
sudo nano /etc/cron.daily/00logwatch
```

### 4. Regular Security Audits

```bash
# Check listening ports
sudo netstat -tlnp | grep LISTEN

# Check active connections
sudo netstat -an | grep :8317

# Check firewall rules
sudo ufw status numbered

# Check fail2ban jails
sudo fail2ban-client status

# Review Docker containers
docker ps -a

# Check for unauthorized changes
sudo find /opt/cliproxyapi -type f -mtime -1
```

---

## Security Checklist

### Initial Setup
- [ ] Set up SSL/TLS certificates (Let's Encrypt or commercial)
- [ ] Configure reverse proxy (Nginx or Caddy)
- [ ] Enable firewall (UFW)
- [ ] Install and configure Fail2ban
- [ ] Block search engine crawlers (robots.txt + X-Robots-Tag)
- [ ] Disable direct port access (only allow via reverse proxy)
- [ ] Generate strong management keys (256-bit)
- [ ] Generate strong API keys (128-bit minimum)
- [ ] Disable SSH password authentication
- [ ] Set up SSH key-based authentication only

### Configuration
- [ ] Bind CLIProxyAPI to localhost only (`host: "127.0.0.1"`)
- [ ] Enable `allow-remote: true` only if needed
- [ ] Set strong `secret-key` in config.yaml
- [ ] Configure CORS with specific allowed origins
- [ ] Disable control panel if not needed
- [ ] Set up rate limiting
- [ ] Configure security headers
- [ ] Enable request logging

### Network Security
- [ ] Close all unnecessary ports
- [ ] Enable UFW firewall
- [ ] Configure Fail2ban rules
- [ ] Set up IP whitelisting for management
- [ ] Isolate Docker network
- [ ] Disable IPv6 if not needed

### Ongoing Maintenance
- [ ] Rotate API keys monthly
- [ ] Rotate management keys quarterly
- [ ] Update SSL certificates (auto-renewal check)
- [ ] Review access logs weekly
- [ ] Check Fail2ban bans weekly
- [ ] Update Docker image monthly
- [ ] Update system packages weekly
- [ ] Review firewall rules monthly
- [ ] Audit user access monthly
- [ ] Backup config and auth data weekly

### Monitoring
- [ ] Set up log monitoring
- [ ] Configure failed authentication alerts
- [ ] Monitor disk usage
- [ ] Monitor network traffic
- [ ] Check for suspicious activity
- [ ] Review Docker container logs

---

## Quick Security Hardening Script

Run this script after initial installation:

```bash
#!/bin/bash
# security-hardening.sh

echo "🔒 CLIProxyAPI Security Hardening"
echo ""

# 1. Install Nginx and Certbot
echo "Installing Nginx and Certbot..."
sudo apt update
sudo apt install nginx certbot python3-certbot-nginx fail2ban ufw -y

# 2. Configure UFW
echo "Configuring firewall..."
sudo ufw --force enable
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow from 127.0.0.1 to any port 8317

# 3. Bind CLIProxyAPI to localhost
echo "Securing CLIProxyAPI binding..."
sudo sed -i 's/host: "0.0.0.0"/host: "127.0.0.1"/' /opt/cliproxyapi/CLIProxyAPI/config.yaml

# 4. Restart services
cd /opt/cliproxyapi/CLIProxyAPI
docker compose restart

echo ""
echo "✅ Basic hardening complete!"
echo ""
echo "Next steps:"
echo "1. Set up domain name"
echo "2. Run: sudo certbot --nginx -d your-domain.com"
echo "3. Configure Nginx reverse proxy (see SECURITY.md)"
echo "4. Set up Fail2ban rules"
```

---

## Additional Resources

- **Let's Encrypt:** https://letsencrypt.org/
- **Nginx Security:** https://nginx.org/en/docs/http/ngx_http_ssl_module.html
- **Fail2ban:** https://www.fail2ban.org/
- **OWASP Top 10:** https://owasp.org/www-project-top-ten/
- **ModSecurity:** https://modsecurity.org/
- **UFW Guide:** https://help.ubuntu.com/community/UFW

---

## Emergency Response

### If Compromised:

1. **Immediate Actions:**
   ```bash
   # Stop the service
   sudo systemctl stop cliproxyapi

   # Block all traffic
   sudo ufw default deny incoming

   # Check active connections
   sudo netstat -an | grep ESTABLISHED
   ```

2. **Investigate:**
   ```bash
   # Check logs
   docker compose logs --tail=1000

   # Check auth files for tampering
   ls -la /opt/cliproxyapi/auths/

   # Review config changes
   sudo diff /opt/cliproxyapi/CLIProxyAPI/config.yaml /opt/cliproxyapi/backups/latest/config.yaml
   ```

3. **Recovery:**
   ```bash
   # Restore from backup
   sudo bash update.sh
   # Select: Restore from backup

   # Regenerate all keys
   sudo bash update.sh
   # Select: Fix Management Key

   # Update API keys
   # (Use Management API to replace all keys)
   ```

4. **Harden and Resume:**
   - Review this security guide
   - Implement missing protections
   - Monitor closely for 48 hours
