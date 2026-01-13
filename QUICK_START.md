# CLIProxyAPI VPS Deployment - Quick Reference

## File Structure

```
cliproxyapi-vps-deployment/
├── install.sh                  # Automated installation script
├── update.sh                   # Update manager with backup/restore
├── uninstall.sh                # Safe uninstallation script
├── config.yaml                 # Configuration template
├── cliproxyapi.service         # Systemd service file
├── migrate-auth-path.sh        # Auth directory path migration
├── fix-auth-persistence.sh     # Fix auth file persistence
├── fix-management-panel.sh     # Diagnose & fix management panel issues
├── MANAGEMENT_API.md           # Complete Management API reference
├── README.md                   # Full documentation
└── QUICK_START.md              # This file
```

## Quick Commands

### Installation
```bash
sudo bash install.sh
```

### Start/Stop Service
```bash
sudo systemctl start cliproxyapi    # Start
sudo systemctl stop cliproxyapi     # Stop
sudo systemctl restart cliproxyapi  # Restart
sudo systemctl status cliproxyapi   # Status
```

### Update
```bash
sudo bash update.sh              # Interactive
sudo bash update.sh --update      # Direct update
sudo bash update.sh --rollback    # Rollback
```

### Uninstall
```bash
sudo bash uninstall.sh           # Interactive menu
# Option 1: Normal uninstall (safe, with backup)
# Option 2: Deep uninstall (removes everything, no backup)
```

### View Logs
```bash
sudo docker compose logs -f       # Real-time
sudo docker compose logs --tail=100  # Last 100 lines
```

### Configuration
```bash
sudo nano /opt/cliproxyapi/CLIProxyAPI/config.yaml
cd /opt/cliproxyapi/CLIProxyAPI && docker compose restart  # Apply changes
```

### Enable Fallback
Configure fallback to local proxy in config.yaml:
```yaml
fallback:
  enabled: true           # Enable fallback
  auto_start: true        # Auto-start local proxy
```

## Management Console

Run the interactive management console:
```bash
cd /opt/cliproxyapi
sudo bash update.sh
```

**Features:**
- Updates & Rollback
- Backup & Restore
- Service control (start/stop/restart)
- Edit/View config
- OAuth login for all providers
- View credentials
- Manage auth files & logs

## OAuth Login (Add AI Providers)

```bash
cd /opt/cliproxyapi/CLIProxyAPI

# Gemini CLI (Google)
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
```

Copy the URL, open in browser, complete OAuth login.

## Test API (curl)

```bash
# List models
curl http://localhost:8317/v1/models -H "Authorization: Bearer YOUR_API_KEY"

# Chat completion
curl http://localhost:8317/v1/chat/completions -H "Content-Type: application/json" -H "Authorization: Bearer YOUR_API_KEY" -d '{"model": "gemini-2.5-flash", "messages": [{"role": "user", "content": "Hello!"}]}'
```

## Important Paths

| Path | Purpose |
|-------|---------|
| `/opt/cliproxyapi/` | Installation directory |
| `/opt/cliproxyapi/CLIProxyAPI/config.yaml` | Main configuration |
| `/opt/cliproxyapi/auths/` | OAuth tokens |
| `/opt/cliproxyapi/logs/` | Application logs |
| `/opt/cliproxyapi/api-keys.txt` | Your API keys (SECURE!) |
| `/opt/cliproxyapi/backups/` | Automatic backups |

## Ports to Open

- **8317** - Main API (required)
- **8085** - Management API (optional)
- **1455, 54545, 51121, 11451** - Additional services (optional)

## Default Credentials

- **API Keys:** Auto-generated during install
- **Location:** `/opt/cliproxyapi/api-keys.txt`

## URLs After Installation

- **API Endpoint:** `http://YOUR_VPS_IP:8317/v1`
- **Management Panel:** `http://YOUR_VPS_IP:8317/management.html`

## Troubleshooting Commands

```bash
# Check if running
sudo systemctl status cliproxyapi

# Check Docker
docker ps | grep cliproxyapi

# View error logs
sudo docker compose logs | grep -i error

# Restart container
sudo docker compose restart

# Full reinstall (preserves config)
sudo bash install.sh
```

## Common Issues

| Issue | Solution |
|-------|----------|
| Service won't start | `sudo systemctl status cliproxyapi` → check logs |
| Can't connect | Open port 8317: `sudo ufw allow 8317/tcp` |
| 401 Unauthorized | Check API key in api-keys.txt |
| 404 on management.html | Run: `sudo bash fix-management-panel.sh` (auto-diagnose & fix) |
| "unknown provider" | Login to provider first (see OAuth Login) |
| Update fails | Check disk space: `df -h` |
| Fallback not working | Check config: `fallback.enabled: true` |

## Working Directory

Always run docker compose commands from the CLIProxyAPI directory:
```bash
cd /opt/cliproxyapi/CLIProxyAPI
docker compose logs -f
docker compose restart
docker compose ps
```

## Command Line Options

```bash
# Updates
sudo bash update.sh --update          # Update to latest
sudo bash update.sh --rollback        # Rollback

# Service
sudo bash update.sh --health          # Health check
sudo bash update.sh --logs            # View logs

# Configuration
sudo bash update.sh --fix-management  # Fix management key
sudo bash update.sh --credentials     # Show credentials
sudo bash update.sh --edit-config     # Edit config
sudo bash update.sh --view-config     # View config

# OAuth Login
sudo bash update.sh --login-gemini
sudo bash update.sh --login-antigravity
sudo bash update.sh --login-claude
sudo bash update.sh --login-codex
sudo bash update.sh --login-qwen
sudo bash update.sh --login-iflow
sudo bash update.sh --list-accounts
```

## Need More Help?

- **Management API:** `MANAGEMENT_API.md` - Complete API reference with curl examples
- **Full README:** `README.md` - Complete deployment guide
- **Official docs:** https://help.router-for.me/
- **GitHub issues:** https://github.com/router-for-me/CLIProxyAPI/issues
