# CLIProxyAPI VPS Deployment

Complete VPS deployment solution for CLIProxyAPI - an AI model proxy server that provides OpenAI/Gemini/Claude/Codex compatible API interfaces.

## 📋 Table of Contents

- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Installation](#-installation)
- [Configuration](#-configuration)
- [Usage](#-usage)
- [Management](#-management)
- [Client Setup](#-client-setup)
- [Uninstallation](#-uninstallation)
- [Troubleshooting](#-troubleshooting)
- [Security](#-security)
- [Advanced](#-advanced)
- [FAQ](#-faq)

## ✨ Features

- **Multiple AI Providers**: Gemini, Claude, OpenAI Codex, Qwen, iFlow
- **OAuth Support**: Use CLI subscriptions via OAuth (no API keys needed)
- **Load Balancing**: Round-robin across multiple accounts
- **Auto Failover**: Switch accounts when quota exceeded
- **Fallback Support**: Fallback to local proxy when remote providers unavailable
- **Management Panel**: Web-based configuration interface
- **Systemd Service**: Auto-start on boot
- **Easy Updates**: Safe update with automatic backups
- **Docker Deployment**: Isolated and easy to manage

## 🔧 Prerequisites

- Ubuntu 20.04+ or Debian 11+
- Root or sudo access
- At least 1GB RAM
- 10GB free disk space
- Open ports: 8317, 8085, 1455, 54545, 51121, 11451

## 🚀 Quick Start

### 1. Clone and Install

```bash
# Clone this repository
git clone https://github.com/your-repo/cliproxyapi-vps-deployment.git
cd cliproxyapi-vps-deployment

# Run installation script
sudo bash install.sh
```

### 2. Configure Providers

Edit the configuration file to add your AI provider credentials:

```bash
sudo nano /opt/cliproxyapi/CLIProxyAPI/config.yaml
```

For OAuth providers (recommended), visit: https://help.router-for.me/

### 3. Access the Service

Your CLIProxyAPI is now running at:

```
API Endpoint: http://YOUR_VPS_IP:8317/v1
Management: http://YOUR_VPS_IP:8317/management.html
```

## 📦 Installation

### Automated Installation (Recommended)

The `install.sh` script handles everything:

```bash
sudo bash install.sh
```

**What it does:**

1. ✅ Checks OS compatibility
2. ✅ Installs Docker and Docker Compose
3. ✅ Creates directory structure at `/opt/cliproxyapi`
4. ✅ Clones CLIProxyAPI repository
5. ✅ Creates configuration files
6. ✅ Generates secure API keys
7. ✅ Sets up systemd service
8. ✅ Configures firewall rules
9. ✅ Starts the service

### Manual Installation

If you prefer manual installation:

```bash
# 1. Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# 2. Create directories
sudo mkdir -p /opt/cliproxyapi/{auths,logs,config}

# 3. Clone repository
git clone https://github.com/router-for-me/CLIProxyAPI.git /opt/cliproxyapi/CLIProxyAPI

# 4. Copy configuration
cp config.yaml /opt/cliproxyapi/
cp cliproxyapi.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable cliproxyapi

# 5. Start service
sudo systemctl start cliproxyapi
```

## ⚙️ Configuration

### Basic Configuration

Edit `/opt/cliproxyapi/CLIProxyAPI/config.yaml`:

```yaml
# Server settings
host: "0.0.0.0"  # Bind to all interfaces
port: 8317          # Default port

# Authentication
api-keys:
  - "your-generated-api-key-1"
  - "your-generated-api-key-2"
```

### Fallback Configuration

Configure fallback to local proxy when remote providers are unavailable:

```yaml
fallback:
  # Enable fallback functionality
  enabled: true

  # Automatically start local proxy when fallback is triggered
  auto_start: true
```

**Benefits of Fallback:**
- Ensures service remains available even when remote providers are down
- Automatic switching to backup/local resources
- Continues serving requests with minimal interruption
- Ideal for production deployments requiring high availability

### Adding Providers

#### Option 1: OAuth (Recommended for CLI Subscriptions)

OAuth providers are configured via the management panel or by following the official guide:

**Gemini CLI OAuth:**
1. Visit http://YOUR_VPS_IP:8317/management.html
2. Enter your management secret key
3. Navigate to OAuth → Gemini CLI
4. Click "Add Account"
5. Follow the Google OAuth flow

**Claude Code OAuth:**
1. Visit management panel at management.html
2. Navigate to OAuth → Claude Code
3. Click "Add Account"
4. Complete Anthropic OAuth

#### Option 2: API Keys

Direct API key configuration in `config.yaml`:

```yaml
# Gemini API Keys
gemini-api-key:
  - api-key: "AIzaSy...your-key"
    models:
      - name: "gemini-2.5-pro"

# Claude API Keys
claude-api-key:
  - api-key: "sk-ant...your-key"
    models:
      - name: "claude-sonnet-4-5-20250929"
```

### Multi-Account Load Balancing

Configure multiple accounts for automatic rotation:

```yaml
codex-api-key:
  - api-key: "sk-atSM...key1"
    prefix: "account1"
  - api-key: "sk-atSM...key2"
    prefix: "account2"
  - api-key: "sk-atSM...key3"
    prefix: "account3"

routing:
  strategy: "round-robin"  # or "fill-first"
```

## 🎯 Usage

### Run the Service

```bash
# Start service
sudo systemctl start cliproxyapi

# Stop service
sudo systemctl stop cliproxyapi

# Restart service
sudo systemctl restart cliproxyapi

# Check status
sudo systemctl status cliproxyapi
```

### OAuth Login (Add AI Providers)

You must login to at least one provider to use the API.

```bash
cd /opt/cliproxyapi/CLIProxyAPI

# Gemini CLI (Google account) - for gemini-2.5-pro, gemini-2.5-flash
docker compose exec cli-proxy-api ./CLIProxyAPI -login -no-browser

# Antigravity - for gemini models via Antigravity
docker compose exec cli-proxy-api ./CLIProxyAPI -antigravity-login -no-browser

# Claude Code - for claude-sonnet, claude-opus
docker compose exec cli-proxy-api ./CLIProxyAPI -claude-login -no-browser

# OpenAI Codex - for gpt-5, gpt-5-codex
docker compose exec cli-proxy-api ./CLIProxyAPI -codex-login -no-browser

# Qwen Code - for qwen models
docker compose exec cli-proxy-api ./CLIProxyAPI -qwen-login -no-browser

# iFlow - for iFlow models
docker compose exec cli-proxy-api ./CLIProxyAPI -iflow-login -no-browser
```

**After running the command:**
1. Copy the URL that appears
2. Open it in your browser
3. Complete the OAuth login
4. The account will be added automatically

**List available models after login:**
```bash
curl http://localhost:8317/v1/models -H "Authorization: Bearer YOUR_API_KEY"
```

### Test API (curl examples)

**List all available models:**
```bash
curl http://localhost:8317/v1/models \
  -H "Authorization: Bearer YOUR_API_KEY"
```

**Test chat completion (Gemini):**
```bash
curl http://localhost:8317/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{"model": "gemini-2.5-flash", "messages": [{"role": "user", "content": "Hello!"}]}'
```

**Test chat completion (GPT-5):**
```bash
curl http://localhost:8317/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{"model": "gpt-5", "messages": [{"role": "user", "content": "Hello!"}]}'
```

**Test chat completion (Claude):**
```bash
curl http://localhost:8317/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{"model": "gemini-claude-sonnet-4-5", "messages": [{"role": "user", "content": "Hello!"}]}'
```

**Single-line version (for copy-paste):**
```bash
curl http://localhost:8317/v1/chat/completions -H "Content-Type: application/json" -H "Authorization: Bearer YOUR_API_KEY" -d '{"model": "gemini-2.5-flash", "messages": [{"role": "user", "content": "Hello!"}]}'
```

### Build from Source

If you need to build from source instead of using Docker:

```bash
cd /opt/cliproxyapi/CLIProxyAPI

# Install Go (if not installed)
sudo apt-get install golang-go

# Build binary
go build -o CLIProxyAPI ./cmd/server/

# Run directly
./CLIProxyAPI
```

### Check Service Health

```bash
# Using systemctl
sudo systemctl status cliproxyapi

# Using Docker
docker ps | grep cliproxyapi

# Check API endpoint
curl http://localhost:8317/v1/models

# Check logs
sudo docker compose logs -f
```

### View Logs

```bash
# Real-time logs
sudo docker compose logs -f

# Last 100 lines
sudo docker compose logs --tail=100

# Logs for specific container
sudo docker compose logs cli-proxy-api
```

### Update to Latest Version

```bash
# Interactive update manager
sudo bash update.sh

# Or command-line update
sudo bash update.sh --update

# Check for updates without applying
sudo bash update.sh --check
```

**What the update script does:**

1. ✅ Creates automatic backup
2. ✅ Pulls latest code
3. ✅ Rebuilds Docker container
4. ✅ Runs health check
5. ✅ Keeps last 10 backups for rollback

### Rollback if Needed

```bash
# Interactive rollback
sudo bash update.sh
# Select option 3: Rollback

# Or command-line rollback
sudo bash update.sh --rollback
```

### Restore from Backup

```bash
# Interactive restore
sudo bash update.sh
# Select option 4: Restore from backup
```

## 📊 Management

### Web Management Panel

Access the management panel at:

```
http://YOUR_VPS_IP:8317/management.html
```

Enter your management secret key from `/opt/cliproxyapi/api-keys.txt` when prompted.

**Features:**
- OAuth account management
- Model configuration
- Usage statistics
- API key management
- Real-time logs

### Management via Command Line

```bash
# View service status
sudo systemctl status cliproxyapi

# Restart service
sudo systemctl restart cliproxyapi

# View logs
sudo docker compose logs -f

# Access container shell
sudo docker exec -it cli-proxy-api sh

# View resource usage
docker stats cli-proxy-api
```

## 🔗 Client Setup

### OpenAI-Compatible Clients

Configure your OpenAI-compatible client to use:

**Base URL:** `http://YOUR_VPS_IP:8317/v1`
**API Key:** Use one of your generated API keys from `/opt/cliproxyapi/api-keys.txt`

### Example: Python OpenAI SDK

```python
from openai import OpenAI

client = OpenAI(
    api_key="your-generated-api-key-1",
    base_url="http://YOUR_VPS_IP:8317/v1"
)

response = client.chat.completions.create(
    model="claude-sonnet-4-5-20250929",
    messages=[
        {"role": "user", "content": "Hello!"}
    ]
)

print(response.choices[0].message.content)
```

### Example: cURL

```bash
curl http://YOUR_VPS_IP:8317/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-api-key" \
  -d '{
    "model": "gemini-2.5-pro",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Example: JavaScript/Fetch

```javascript
const response = await fetch('http://YOUR_VPS_IP:8317/v1/chat/completions', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer your-api-key'
  },
  body: JSON.stringify({
    model: 'claude-sonnet-4-5-20250929',
    messages: [{ role: 'user', content: 'Hello!' }]
  })
});

const data = await response.json();
console.log(data.choices[0].message.content);
```

### Configure Popular AI Tools

#### Claude Code / Cursor

```bash
# Set environment variable
export OPENAI_BASE_URL="http://YOUR_VPS_IP:8317/v1"
export OPENAI_API_KEY="your-api-key"
```

#### Cline (VS Code)

In VS Code settings (`.vscode/settings.json`):

```json
{
  "cline.apiProvider": "openai",
  "cline.openAIBaseUrl": "http://YOUR_VPS_IP:8317/v1",
  "cline.openAIApiKey": "your-api-key",
  "cline.openAiModelId": "claude-sonnet-4-5-20250929"
}
```

#### Roo Code (Cursor)

```json
{
  "api.baseURL": "http://YOUR_VPS_IP:8317/v1",
  "api.apiKey": "your-api-key"
}
```

## 🗑️ Uninstallation

### Uninstall Modes

The uninstall script now supports two modes:

#### 1. Normal Uninstall (Safe, with backup option)
```bash
sudo bash uninstall.sh
# Select option 1
```

**What it does:**

1. ✅ Optional backup of config, auth files, and API keys
2. ✅ Stops and disables the systemd service
3. ✅ Stops and removes Docker containers
4. ✅ Removes systemd service file
5. ✅ Optional: Removes Docker images
6. ✅ Removes installation directory (with explicit confirmation)
7. ✅ Optional: Removes firewall rules
8. ✅ Optional: Removes Docker engine completely
9. ✅ Verifies complete removal

**Backup Location:** `~/cliproxyapi-backup-YYYYMMDD_HHMMSS/`

#### 2. Deep Uninstall (Complete removal, no backup)
```bash
sudo bash uninstall.sh
# Select option 2
```

**Warning:** This mode is **IRREVERSIBLE** and removes **EVERYTHING**!

**What it removes:**
- ✅ All files in `/opt/cliproxyapi`
- ✅ Docker images (`eceasy/cli-proxy-api`)
- ✅ Docker volumes and networks
- ✅ Systemd service files
- ✅ All firewall rules
- ✅ All logs and temporary files
- ✅ All backups in `/opt/cliproxyapi/backups`
- ✅ Symlinks and cache files
- ✅ Docker system cleanup (`docker system prune -af --volumes`)

**Confirmation required:** Type `DELETE EVERYTHING` to proceed

**Use cases for deep uninstall:**
- Complete clean slate before reinstallation
- Removing all traces of CLIProxyAPI
- Freeing maximum disk space
- Server decommissioning

**Important Notes:**

- Deep uninstall does NOT create a backup
- Requires typing `DELETE EVERYTHING` to confirm
- Cannot be undone
- Normal uninstall is recommended for most users

### Manual Uninstallation

If you prefer manual removal:

```bash
# Stop and disable service
sudo systemctl stop cliproxyapi
sudo systemctl disable cliproxyapi

# Remove Docker containers
cd /opt/cliproxyapi/CLIProxyAPI
sudo docker compose down

# Remove systemd service
sudo rm /etc/systemd/system/cliproxyapi.service
sudo systemctl daemon-reload

# Remove installation directory
sudo rm -rf /opt/cliproxyapi

# Optional: Remove firewall rules
sudo ufw delete allow 8317/tcp
sudo ufw delete allow 8085/tcp
sudo ufw delete allow 1455/tcp
sudo ufw delete allow 54545/tcp
sudo ufw delete allow 51121/tcp
sudo ufw delete allow 11451/tcp
```

## 🔍 Troubleshooting

### Service Won't Start

```bash
# Check status
sudo systemctl status cliproxyapi

# View logs for errors
sudo docker compose logs

# Check if ports are in use
sudo netstat -tulpn | grep 8317

# Restart with full logs
sudo docker compose down
sudo docker compose up
```

### Connection Refused

```bash
# Check if service is running
sudo systemctl status cliproxyapi

# Check firewall rules
sudo ufw status

# Open required ports
sudo ufw allow 8317/tcp
sudo ufw allow 8085/tcp
sudo ufw allow 1455/tcp
sudo ufw allow 54545/tcp
sudo ufw allow 51121/tcp
sudo ufw allow 11451/tcp

# Check Docker container
docker ps | grep cliproxyapi
```

### API Returns 401 Unauthorized

1. Check your API key in `/opt/cliproxyapi/api-keys.txt`
2. Verify the key is in `config.yaml` under `api-keys:`
3. Restart service: `sudo systemctl restart cliproxyapi`

### OAuth Login Fails

1. Check management panel configuration:
   ```bash
   sudo nano /opt/cliproxyapi/CLIProxyAPI/config.yaml
   # Verify remote-management.secret-key is set
   ```

2. Check if `remote-management.allow-remote` is true (for external access)

3. Ensure auth directory is writable:
   ```bash
   sudo chmod 700 /opt/cliproxyapi/auths
   ```

### High Memory Usage

Enable commercial mode to reduce memory:

```yaml
# In config.yaml
commercial-mode: true
```

Restart service:
```bash
sudo systemctl restart cliproxyapi
```

### Update Fails

1. Check available disk space:
   ```bash
   df -h
   ```

2. Clear old Docker images:
   ```bash
   docker system prune -a
   ```

3. Restore from backup if needed:
   ```bash
   sudo bash update.sh
   # Select: Restore from backup
   ```

## 🔒 Security

### Secure Your Deployment

#### 1. Use Strong API Keys

```bash
# Generate new secure keys
openssl rand -hex 32
```

Update `config.yaml` with new keys.

#### 2. Enable HTTPS/TLS

Generate SSL certificates (Let's Encrypt recommended):

```bash
sudo apt-get install certbot
sudo certbot certonly --standalone -d your-domain.com
```

Configure in `config.yaml`:

```yaml
tls:
  enable: true
  cert: "/etc/letsencrypt/live/your-domain.com/fullchain.pem"
  key: "/etc/letsencrypt/live/your-domain.com/privkey.pem"
```

#### 3. Restrict Access

Configure firewall to allow only specific IPs:

```bash
sudo ufw allow from YOUR_IP to any port 8317
sudo ufw deny 8317
```

#### 4. Use Reverse Proxy (Nginx)

Install and configure Nginx:

```bash
sudo apt-get install nginx
```

Create `/etc/nginx/sites-available/cliproxyapi`:

```nginx
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://localhost:8317;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable and restart:

```bash
sudo ln -s /etc/nginx/sites-available/cliproxyapi /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

#### 5. Enable Rate Limiting

In `config.yaml`:

```yaml
# Add rate limiting (if supported)
rate-limit:
  enabled: true
  requests-per-minute: 100
```

### Audit Logs

Regularly review logs for suspicious activity:

```bash
# View recent access patterns
sudo docker compose logs --tail=1000 | grep "Authorization"

# Check for failed attempts
sudo docker compose logs --tail=1000 | grep "401\|403"
```

## 🚀 Advanced

### Custom Model Mappings

Create custom model aliases in `config.yaml`:

```yaml
oauth-model-mappings:
  gemini-cli:
    - name: "gemini-2.5-pro"
      alias: "g2.5p"
      fork: true  # Keep both original and alias

    - name: "gemini-2.5-flash"
      alias: "flash"
```

### Multi-Tenant Setup

Configure per-client upstream keys:

```yaml
ampcode:
  upstream-api-keys:
    - upstream-api-key: "amp_key_team_a"
      api-keys:
        - "client-key-1"
        - "client-key-2"
    - upstream-api-key: "amp_key_team_b"
      api-keys:
        - "client-key-3"
```

### Payload Configuration

Modify request parameters automatically:

```yaml
payload:
  default:
    - models:
        - name: "gemini-*"
      params:
        "generationConfig.thinkingConfig.thinkingBudget": 32768
  override:
    - models:
        - name: "gpt-*"
      params:
        "reasoning.effort": "high"
```

### Monitoring with Prometheus

Add monitoring to `docker-compose.yml`:

```yaml
services:
  cli-proxy-api:
    # ... existing config ...
    ports:
      - "9090:9090"  # Prometheus metrics
```

Access metrics at: `http://YOUR_VPS_IP:9090/metrics`

## ❓ FAQ

### Q: Can I use multiple Google accounts?
**A:** Yes! OAuth supports unlimited accounts. Add accounts via the management panel.

### Q: How do I switch between accounts?
**A:** Configure `routing.strategy: "round-robin"` for automatic rotation, or use prefixes like `account1/gemini-2.5-pro`.

### Q: Can I use this with free AI services?
**A:** Yes! OAuth providers (Gemini CLI, Claude Code) use free CLI subscriptions.

### Q: What's the difference between fill-first and round-robin?
**A:**
- `fill-first`: Uses first account until quota exceeded, then switches
- `round-robin`: Distributes requests evenly across all accounts

### Q: How much bandwidth does this use?
**A:** Depends on usage. Expect ~1-5 MB per typical AI request. 10GB/month is sufficient for moderate use.

### Q: Can I host this on a cheap VPS?
**A:** Yes! A $5-10/month VPS with 1GB RAM is sufficient for personal use.

### Q: How do I backup my configuration?
**A:** The update script automatically creates backups. Also manually backup:
```bash
sudo cp /opt/cliproxyapi/CLIProxyAPI/config.yaml ~/backup/
sudo cp -r /opt/cliproxyapi/auths ~/backup/
```

### Q: Can I use my own SSL certificate?
**A:** Yes! Configure in `config.yaml`:
```yaml
tls:
  enable: true
  cert: "/path/to/your/cert.pem"
  key: "/path/to/your/key.pem"
```

### Q: What ports do I need to open?
**A:** Required ports:
- 8317: Main API
- 8085: Management API
- 1455, 54545, 51121, 11451: Additional services (optional)

### Q: How do I monitor usage?
**A:**
- Enable statistics: `usage-statistics-enabled: true`
- Check logs: `sudo docker compose logs --tail=1000`
- Use management panel: http://YOUR_VPS_IP:8317/management.html

## 📚 Additional Resources

### Documentation
- **Official Docs:** https://help.router-for.me/
- **Management API Reference:** See [MANAGEMENT_API.md](MANAGEMENT_API.md) in this repo
- **Quick Reference:** See [QUICK_START.md](QUICK_START.md)
- **Official Management API:** https://help.router-for.me/management/api

### Project Links
- **GitHub Repo:** https://github.com/router-for-me/CLIProxyAPI
- **Issues:** https://github.com/router-for-me/CLIProxyAPI/issues

### Files in This Repository
- `install.sh` - Automated VPS installation
- `update.sh` - Update manager with backup/restore
- `uninstall.sh` - Safe uninstallation script
- `config.yaml` - Configuration template
- `cliproxyapi.service` - Systemd service file
- `migrate-auth-path.sh` - Auth directory path migration for existing installations
- `fix-auth-persistence.sh` - Fix auth file persistence across restarts
- `fix-management-panel.sh` - Diagnose and fix management panel 404 issues
- `MANAGEMENT_API.md` - Complete Management API reference
- `QUICK_START.md` - Quick command reference
- `README.md` - This file

## 📄 License

This deployment configuration is provided as-is. CLIProxyAPI is licensed under MIT License.

## 🤝 Contributing

Contributions welcome! Please open issues or PRs for:
- Bug fixes
- New provider configurations
- Documentation improvements
- Security enhancements

---

**Need Help?**

- Check the [CLIProxyAPI guides](https://help.router-for.me/)
- Open an [issue on GitHub](https://github.com/router-for-me/CLIProxyAPI/issues)
- Join the community discussions

**Enjoy your AI proxy server! 🎉**
