# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **VPS Linux deployment automation repository** for CLIProxyAPI - an AI model proxy server that provides OpenAI-compatible API interfaces for multiple AI providers (Gemini, Claude, OpenAI Codex, Qwen, iFlow).

**IMPORTANT: This repository is ONLY for Ubuntu/Debian VPS deployments. For other platforms, see the official documentation.**

**Official Documentation:** https://help.router-for.me/

**What This Repository Provides:**
- Custom installation script (`install.sh`) for Ubuntu/Debian VPS
- Automated update and backup system (`update.sh`)
- Safe uninstallation script (`uninstall.sh`)
- Pre-configured systemd service for auto-start on boot
- Custom directory structure at `/opt/cliproxyapi`
- Interactive management console

**Key Architecture:**
- CLIProxyAPI is deployed to `/opt/cliproxyapi/CLIProxyAPI` via Git clone
- The actual CLIProxyAPI application runs in a Docker container
- Official Docker image: `eceasy/cli-proxy-api:latest`
- OAuth tokens stored in `/opt/cliproxyapi/auths`
- Configuration at `/opt/cliproxyapi/CLIProxyAPI/config.yaml`
- Managed by systemd service (`cliproxyapi.service`)

## Installation - THIS REPOSITORY

**This repository's install.sh is ONLY for Linux VPS (Ubuntu/Debian):**

```bash
# Clone this deployment repository
git clone https://github.com/your-repo/cliproxyapi-vps-deployment.git
cd cliproxyapi-vps-deployment

# Run VPS installation (requires root, Ubuntu/Debian only)
sudo bash install.sh
```

**Supported Operating Systems:**
- Ubuntu 20.04+
- Debian 11+

**Requirements:**
- Root or sudo access
- At least 1GB RAM
- 10GB free disk space

## Other Installation Methods (Not This Repository)

For non-VPS deployments, use the official CLIProxyAPI installation methods:

**Linux (Official Installer):**
```bash
curl -fsSL https://raw.githubusercontent.com/brokechubb/cliproxyapi-installer/refs/heads/master/cliproxyapi-installer | bash
```

**macOS (Homebrew):**
```bash
brew install cliproxyapi
brew services start cliproxyapi
```

**Windows:**
- Download from [GitHub Releases](https://github.com/router-for-me/CLIProxyAPI/releases)
- Or use [Desktop GUI (EasyCLI)](https://github.com/router-for-me/EasyCLI/releases)

**Local Config.yaml (Windows/macOS example):**
```yaml
host: ""                           # Empty string = localhost only (secure default)
port: 8325                          # Different port from VPS (8317)
auth-dir: "C:\\Users\\USERNAME\\.cli-proxy-api"  # Windows path
remote-management:
  allow-remote: false               # Disabled for local use
  secret-key: "hashed-key"
  disable-control-panel: false
api-keys:
  - "dummy-key-12345"
```

**VPS vs Local Configuration Differences:**

| Setting | VPS (Docker) | Local (Windows/macOS) |
|---------|--------------|----------------------|
| `host` | `"0.0.0.0"` (all interfaces) | `""` or `"127.0.0.1"` (localhost only) |
| `port` | `8317` | `8325` or custom |
| `auth-dir` | `/root/.cli-proxy-api` (container) | `C:\Users\...\` or `~/.cli-proxy-api` |
| `allow-remote` | `true` (for remote access) | `false` (local only) |
| Volume mounts | Required for persistence | Not needed (native filesystem) |

**Docker (Manual):**
```bash
docker run --rm -p 8317:8317 \
  -v /path/to/your/config.yaml:/CLIProxyAPI/config.yaml \
  -v /path/to/your/auth-dir:/root/.cli-proxy-api \
  eceasy/cli-proxy-api:latest
```

**Build from Source:**
```bash
git clone https://github.com/router-for-me/CLIProxyAPI.git
cd CLIProxyAPI
go build -o cli-proxy-api ./cmd/server
```

## Essential Commands

### Service Management
```bash
# Start/stop/restart service
sudo systemctl start cliproxyapi
sudo systemctl stop cliproxyapi
sudo systemctl restart cliproxyapi
sudo systemctl status cliproxyapi

# View logs
cd /opt/cliproxyapi/CLIProxyAPI && docker compose logs -f
cd /opt/cliproxyapi/CLIProxyAPI && docker compose logs --tail=100
```

### Update Management
```bash
# Interactive management console (recommended)
sudo bash update.sh

# Command-line updates
sudo bash update.sh --update          # Update to latest
sudo bash update.sh --rollback        # Rollback to previous version
sudo bash update.sh --health          # Health check
sudo bash update.sh --credentials     # Show credentials
```

### Uninstallation
```bash
# Run uninstall script (interactive menu)
sudo bash uninstall.sh

# Two modes available:
# 1) Normal uninstall - Safe with backup option, asks for confirmation
# 2) Deep uninstall - Removes EVERYTHING, no backup, requires typing "DELETE EVERYTHING"

# Deep uninstall removes:
# - All installation files
# - Docker images and volumes
# - Firewall rules
# - Systemd service
# - All logs and temp files
# - Docker system cleanup (prune)
```

### OAuth Provider Login
```bash
cd /opt/cliproxyapi/CLIProxyAPI

# Login commands (run inside Docker container)
docker compose exec cli-proxy-api ./CLIProxyAPI -login -no-browser              # Gemini CLI
docker compose exec cli-proxy-api ./CLIProxyAPI -antigravity-login -no-browser  # Antigravity
docker compose exec cli-proxy-api ./CLIProxyAPI -claude-login -no-browser       # Claude Code
docker compose exec cli-proxy-api ./CLIProxyAPI -codex-login -no-browser        # OpenAI Codex
docker compose exec cli-proxy-api ./CLIProxyAPI -qwen-login -no-browser         # Qwen Code
docker compose exec cli-proxy-api ./CLIProxyAPI -iflow-login -no-browser        # iFlow
```

### Configuration
```bash
# Edit configuration
sudo nano /opt/cliproxyapi/CLIProxyAPI/config.yaml

# Apply configuration changes
cd /opt/cliproxyapi/CLIProxyAPI && docker compose restart
```

## Critical File Paths

| Path | Purpose |
|------|---------|
| `/opt/cliproxyapi/` | Main installation directory (host) |
| `/opt/cliproxyapi/CLIProxyAPI/` | Cloned CLIProxyAPI repository (host) |
| `/opt/cliproxyapi/CLIProxyAPI/config.yaml` | **Main configuration file** (host, mounted to container) |
| `/opt/cliproxyapi/auths/` | OAuth tokens and session data (host, mounted to `/root/.cli-proxy-api` in container) |
| `/root/.cli-proxy-api` | Auth directory **inside container** (config.yaml uses this path) |
| `/opt/cliproxyapi/logs/` | Application logs (host) |
| `/opt/cliproxyapi/api-keys.txt` | Generated API keys and credentials (host) |
| `/opt/cliproxyapi/backups/` | Automatic backups from update.sh (host) |
| `/etc/systemd/system/cliproxyapi.service` | Systemd service definition |
| `~/cliproxyapi-backup-YYYYMMDD_HHMMSS/` | Final backup location (uninstall.sh) |

## API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `http://YOUR_VPS_IP:8317/v1` | OpenAI-compatible API endpoint for chat completions, models, etc. |
| `http://YOUR_VPS_IP:8317/management.html` | Web management panel (enter secret key from api-keys.txt) |
| `/v0/management/*` | Management API endpoints (use `Authorization: Bearer <key>`) |

## Architecture & Design

### Deployment Flow
1. **install.sh** sets up the environment:
   - Installs Docker and Docker Compose
   - Creates directory structure at `/opt/cliproxyapi`
   - Clones CLIProxyAPI repository from `https://github.com/router-for-me/CLIProxyAPI.git`
   - Generates secure API keys (3 random keys via `openssl rand -hex 16`)
   - Creates systemd service for auto-start on boot
   - Starts the Docker container

2. **CLIProxyAPI runs in Docker**:
   - Working directory: `/opt/cliproxyapi/CLIProxyAPI`
   - Service type: `oneshot` with `RemainAfterExit=yes`
   - Commands: `docker compose up -d` (start), `docker compose down` (stop)

3. **OAuth Authentication**:
   - Tokens stored in `/opt/cliproxyapi/auths` (mounted into container)
   - Login commands execute inside Docker container using `-no-browser` flag
   - User copies OAuth URL to browser to complete authentication

### Configuration System

**config.yaml structure:**
- Server settings: `host: "0.0.0.0"`, `port: 8317`
- Management panel: `remote-management.secret-key`, `remote-management.allow-remote`
- OAuth tokens directory: `auth-dir: "/root/.cli-proxy-api"` (container path, mounted from `/opt/cliproxyapi/auths` on host)
- API authentication: `api-keys: []` (list of client API keys)
- Load balancing: `routing.strategy` (round-robin or fill-first)
- Fallback support: `fallback.enabled`, `fallback.auto-start`

**Key configuration notes:**
- Config file MUST be in CLIProxyAPI directory (not parent) for Docker volume mount
- Docker volume mount: `-v /path/to/config.yaml:/CLIProxyAPI/config.yaml`
- Auth directory mount: `-v /opt/cliproxyapi/auths:/root/.cli-proxy-api` (host path → container path)
- **CRITICAL**: config.yaml must use `/root/.cli-proxy-api` (container path), NOT `/opt/cliproxyapi/auths` (host path)
- install.sh copies `config.example.yaml` to `config.yaml` if not exists
- Management secret key is auto-generated: `openssl rand -hex 32`
- API keys are generated and saved to `/opt/cliproxyapi/api-keys.txt`

**Official Docker Image:**
- Image: `eceasy/cli-proxy-api:latest`
- Repository: https://github.com/router-for-me/CLIProxyAPI
- Config location inside container: `/CLIProxyAPI/config.yaml`
- Default auth directory inside container: `/root/.cli-proxy-api`

### Update System (update.sh)

**Backup mechanism:**
- Creates timestamped backups in `/opt/cliproxyapi/backups/backup_YYYYMMDD_HHMMSS/`
- Backs up: config.yaml, auths directory, docker-compose.yml
- Keeps last 10 backups automatically (cleans older ones)

**Update flow:**
1. Create automatic backup
2. Git pull latest changes from main branch
3. Rebuild Docker container (`docker compose down`, `docker compose pull`, `docker compose up -d`)
4. Run health check (container status, API endpoint response, log errors)

**Rollback:**
- Git-based: Resets to previous commit in reflog
- Backup-based: Restores config and auths from backup directory

### Management Features (update.sh interactive menu)

The update.sh script provides an interactive console with:
- **Updates**: Check, update, rollback
- **Backup/Restore**: Manual backup, restore from backup list
- **Service**: Health check, logs, start/stop/restart
- **Configuration**: Edit config, view config, regenerate management key
- **OAuth**: Login to all providers, list accounts
- **Files**: View auth/logs directories, clear logs

## Common Development Patterns

### When modifying install.sh (Linux VPS Only)
- **CRITICAL**: This script is ONLY for Ubuntu/Debian VPS deployments
- Always check root with `check_root()` function
- Always check OS with `detect_os()` function (validates Ubuntu/Debian)
- Use color functions: `print_success`, `print_error`, `print_warning`, `print_info`
- Set `set -e` to exit on any error
- Generate secure keys with `openssl rand -hex 32` or `openssl rand -hex 16`
- Update `print_final_instructions()` to reflect any changes to URLs or credentials
- Test only on Ubuntu 20.04+ or Debian 11+

### When modifying update.sh
- Always create backup before making changes (`create_backup()`)
- Use `cd $INSTALL_DIR/CLIProxyAPI` before docker compose commands
- Keep backup limit at 10 (`backup_count -gt 10`)
- Include health check after updates
- Add sleep delays after service restarts (5-10 seconds for stabilization)

### When modifying uninstall.sh
- Always ask for confirmation before destructive operations
- Provide optional backup before uninstalling
- Check if service/files exist before attempting removal
- Verify uninstallation with `verify_uninstallation()` function
- Use color functions for clear user feedback
- Make Docker image removal optional (user may have other containers)
- Preserve user data by default, only remove with explicit "YES" confirmation

### When modifying config.yaml template
- Keep `auth-dir: "/root/.cli-proxy-api"` (container path, not host path!)
- Ensure `host: "0.0.0.0"` for external access
- Set `allow-remote: true` for remote management access
- Use placeholder values that install.sh will replace (e.g., `CHANGE_THIS_TO_SECURE_RANDOM_KEY`)
- Remember: Docker volume mounts `/opt/cliproxyapi/auths` (host) to `/root/.cli-proxy-api` (container)

## Security Considerations

1. **API Keys**: Generated using `openssl rand -hex 16` (16 bytes = 128 bits)
2. **Management Secret**: Generated using `openssl rand -hex 32` (32 bytes = 256 bits)
3. **Credentials File**: `/opt/cliproxyapi/api-keys.txt` is chmod 600 (owner read/write only)
4. **Auth Directory**: `/opt/cliproxyapi/auths` is chmod 700 (owner access only)
5. **Firewall Ports**: Default ports are 8317 (API), 8085 (Management), plus 1455, 54545, 51121, 11451

## Troubleshooting

### Service won't start
```bash
sudo systemctl status cliproxyapi
cd /opt/cliproxyapi/CLIProxyAPI && docker compose logs
docker ps | grep cliproxyapi
```

### Management panel 404 error
**IMPORTANT:** Check if the panel is intentionally disabled first:
```bash
grep "disable-control-panel" /opt/cliproxyapi/CLIProxyAPI/config.yaml
```

**If `disable-control-panel: true`:**
- This is **expected behavior** (not an error)
- Server intentionally skips downloading management.html
- `/management.html` returns 404 by design
- Management API endpoints (`/v0/management/*`) still work
- Use this for API-only deployments or custom UI hosting

**If `disable-control-panel: false` but still 404:**
- Check if management.html was downloaded: `docker compose logs | grep "management asset"`
- Should see: "management asset updated successfully"
- If not, ensure `disable-control-panel: false` in config.yaml
- Run diagnostic: `sudo bash fix-management-panel.sh`
- Access at: http://YOUR_VPS_IP:8317/management.html
- API endpoints use different path: `/v0/management/*`

### OAuth login fails
- Check auth directory is writable: `sudo chmod 700 /opt/cliproxyapi/auths`
- Verify container is running: `docker ps | grep cli-proxy-api`
- Use `-no-browser` flag for VPS deployments (copy URL to local browser)

### Configuration changes not applied
- Always restart after config edits: `cd /opt/cliproxyapi/CLIProxyAPI && docker compose restart`
- Config must be at `/opt/cliproxyapi/CLIProxyAPI/config.yaml` (not parent directory)

## Installation Method Comparison

| Method | Best For | Platform | Notes |
|--------|----------|----------|-------|
| **This repo's install.sh** | Ubuntu/Debian VPS | Linux only | Custom paths, systemd, backup system, update manager |
| **Official brokechubb installer** | Standard Linux | Linux | Community-supported, automated |
| **Homebrew** | macOS users | macOS | Native integration |
| **Windows releases** | Windows users | Windows | Pre-built binaries or GUI |
| **Docker manual** | Any platform | Cross-platform | Direct Docker control |
| **Build from source** | Developers | Cross-platform | Requires Go toolchain |

## Important Notes

- **Official Documentation**: https://help.router-for.me/ (Quick Start, Docker guides, Tutorials)
- **Official CLIProxyAPI Repo**: https://github.com/router-for-me/CLIProxyAPI
- **Working Directory**: All `docker compose` commands must run from `/opt/cliproxyapi/CLIProxyAPI`
- **Docker Image**: Official image is `eceasy/cli-proxy-api:latest`
- **Systemd Service**: Type is `oneshot` with `RemainAfterExit=yes` (not a traditional daemon)
- **Default Port**: 8317 (configurable in config.yaml)
- **Docker Compose**: Uses v2 syntax (`docker compose` not `docker-compose`)
- **Auth Directory**: Host path is `/opt/cliproxyapi/auths`, container path is `/root/.cli-proxy-api`
- **IMPORTANT**: config.yaml must use container path (`/root/.cli-proxy-api`), not host path
- **Supported OS**: Ubuntu 20.04+, Debian 11+ only
