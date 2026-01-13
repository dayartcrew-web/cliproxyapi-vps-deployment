# CLIProxyAPI Management API Reference

Complete reference for the CLIProxyAPI Management REST API. All endpoints require authentication using the management secret key.

## Table of Contents

- [Authentication](#authentication)
- [Base URL](#base-url)
- [Web UI](#web-ui)
- [Configuration Management](#configuration-management)
- [API Keys Management](#api-keys-management)
- [Provider Management](#provider-management)
  - [Gemini API Keys](#gemini-api-keys)
  - [Claude API Keys](#claude-api-keys)
  - [OpenAI Compatibility Providers](#openai-compatibility-providers)
  - [OAuth Excluded Models](#oauth-excluded-models)
- [Proxy Settings](#proxy-settings)
- [Usage Statistics](#usage-statistics)
- [Troubleshooting](#troubleshooting-web-ui)

---

## Authentication

All management API endpoints require the management secret key configured in `config.yaml`:

```yaml
remote-management:
  secret-key: "YOUR_MANAGEMENT_KEY"
```

**Authentication Header:**
```bash
Authorization: Bearer <MANAGEMENT_KEY>
```

**Example:**
```bash
curl -H 'Authorization: Bearer d9fec4eec99bca9851f5ee5064985f816deb75742e1e6eb3c4268d2e2ecbf2a2' \
  http://localhost:8317/v0/management/config
```

---

## Base URL

**Local Access:**
```
http://localhost:8317/v0/management
```

**Remote Access:**
```
http://YOUR_VPS_IP:8317/v0/management
```

**Web UI:**
```
http://YOUR_VPS_IP:8317/management.html
```
Enter your management key in the web interface.

---

## Web UI

The CLIProxyAPI includes a built-in web-based management interface that provides a user-friendly way to manage your proxy server.

### Accessing the Web UI

**URL:**
```
http://YOUR_VPS_IP:8317/management.html
```

**Authentication:**
When you access the web UI, you'll be prompted to enter your management secret key. Find it at:
```bash
cat /opt/cliproxyapi/api-keys.txt | grep MANAGEMENT_KEY
```

### How It Works

The management panel (`management.html`) is **automatically downloaded** from GitHub when the server starts:

1. **Auto-Download**: On first startup, the server downloads the latest management panel from the configured GitHub repository
2. **Auto-Update**: The server periodically checks for updates and downloads new versions
3. **Local Storage**: The panel is saved to `static/management.html` in the CLIProxyAPI directory

**🔑 Key Behavior:**

| `disable-control-panel` | Download? | `/management.html` Response | API Endpoints |
|------------------------|-----------|----------------------------|---------------|
| `false` (default) | ✅ Yes | ✅ 200 OK (UI loads) | ✅ Work |
| `true` | ❌ **No** | ❌ **404 Not Found** | ✅ Work |

**When `disable-control-panel: true`:**
- Server **intentionally skips** downloading management.html
- Accessing `/management.html` returns 404 **by design** (not an error)
- Use this for API-only deployments or custom UI hosting
- All `/v0/management/*` API endpoints continue to work normally

### Configuration

In `config.yaml`:

```yaml
remote-management:
  allow-remote: true                    # Enable remote management access
  secret-key: "YOUR_MANAGEMENT_KEY"     # Authentication key
  disable-control-panel: false          # Enable/disable web UI
  panel-github-repository: "https://github.com/router-for-me/Cli-Proxy-API-Management-Center"
```

**Configuration Options:**

| Setting | Default | Description |
|---------|---------|-------------|
| `allow-remote` | `false` | Allow management access from non-localhost addresses |
| `secret-key` | Required | Authentication key for management API (auto-hashed if plaintext) |
| `disable-control-panel` | `false` | **`false`**: Auto-download UI from GitHub<br>**`true`**: Skip download, `/management.html` → 404 |
| `panel-github-repository` | Official repo | GitHub repository URL for custom management UI |

### Using a Custom Web UI

You can host your own management UI by pointing to your GitHub repository:

```yaml
remote-management:
  panel-github-repository: "https://github.com/your-org/your-management-ui"
```

The server will:
1. Convert repository URL to GitHub API URL
2. Fetch the latest release
3. Download `management.html` from release assets
4. Optionally validate with SHA256 digest

### Custom Static Path

Override the default `static/` directory using an environment variable:

**In docker-compose.yml:**
```yaml
services:
  cli-proxy-api:
    environment:
      - MANAGEMENT_STATIC_PATH=/custom/path/to/ui
```

**Direct export:**
```bash
export MANAGEMENT_STATIC_PATH=/path/to/your/custom/ui/directory
```

### Disabling the Web UI

To disable the built-in web UI completely, set `disable-control-panel` to `true`:

```yaml
remote-management:
  disable-control-panel: true
```

**⚠️ Important Behavior When Disabled:**
- ❌ Server **WILL NOT** download `management.html` from GitHub
- ❌ Accessing `/management.html` **WILL RETURN 404**
- ✅ Management **API endpoints** (`/v0/management/*`) still work
- ✅ Useful for API-only usage or hosting custom UI elsewhere

**When to Disable:**
- You're using a custom UI hosted on a different server
- You only need API access (no web interface)
- Security requirements: minimize attack surface
- Bandwidth constraints: avoid downloading UI assets

**Note:** Even with the panel disabled, you can still use all management API endpoints via curl or custom applications.

---

## Configuration Management

### Get Full Configuration

Retrieves the complete server configuration.

**Endpoint:** `GET /config`

**Request:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  http://localhost:8317/v0/management/config
```

**Response:**
```json
{
  "host": "0.0.0.0",
  "port": 8317,
  "auth-dir": "/root/.cli-proxy-api",
  "api-keys": ["key1", "key2"],
  "remote-management": {
    "allow-remote": true,
    "secret-key": "***"
  }
}
```

---

## API Keys Management

Manage general API keys that clients use to access the proxy service.

### List API Keys

**Endpoint:** `GET /api-keys`

**Request:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  http://localhost:8317/v0/management/api-keys
```

**Response:**
```json
{
  "api-keys": ["key1", "key2", "key3"]
}
```

### Replace All API Keys

**Endpoint:** `PUT /api-keys`

**Request:**
```bash
curl -X PUT -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '["new-key-1", "new-key-2", "new-key-3"]' \
  http://localhost:8317/v0/management/api-keys
```

**Response:**
```json
{
  "status": "ok"
}
```

### Update Single API Key

**Endpoint:** `PATCH /api-keys`

**By Value:**
```bash
curl -X PATCH -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '{"old": "old-key", "new": "new-key"}' \
  http://localhost:8317/v0/management/api-keys
```

**By Index:**
```bash
curl -X PATCH -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '{"index": 0, "value": "new-key"}' \
  http://localhost:8317/v0/management/api-keys
```

### Delete API Key

**Endpoint:** `DELETE /api-keys`

**By Value:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -X DELETE 'http://localhost:8317/v0/management/api-keys?value=key-to-delete'
```

**By Index:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -X DELETE 'http://localhost:8317/v0/management/api-keys?index=0'
```

---

## Provider Management

### Gemini API Keys

Manage Google Gemini API keys and configurations.

#### List Gemini Keys

**Endpoint:** `GET /gemini-api-key`

**Request:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  http://localhost:8317/v0/management/gemini-api-key
```

**Response:**
```json
{
  "gemini-api-key": [
    {
      "api-key": "AIzaSy...01",
      "base-url": "https://generativelanguage.googleapis.com",
      "headers": {
        "X-Custom-Header": "custom-value"
      },
      "proxy-url": "",
      "excluded-models": ["gemini-1.5-pro", "gemini-1.5-flash"]
    }
  ]
}
```

#### Replace All Gemini Keys

**Endpoint:** `PUT /gemini-api-key`

**Request:**
```bash
curl -X PUT -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '[
    {
      "api-key": "AIzaSy-1",
      "headers": {"X-Custom-Header": "vendor-value"},
      "excluded-models": ["gemini-1.5-flash"]
    },
    {
      "api-key": "AIzaSy-2",
      "base-url": "https://custom.example.com",
      "excluded-models": ["gemini-pro-vision"]
    }
  ]' \
  http://localhost:8317/v0/management/gemini-api-key
```

#### Update Single Gemini Key

**Endpoint:** `PATCH /gemini-api-key`

**By Index:**
```bash
curl -X PATCH -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '{
    "index": 0,
    "value": {
      "api-key": "AIzaSy-1",
      "base-url": "https://custom.example.com",
      "headers": {"X-Custom-Header": "custom-value"},
      "proxy-url": "",
      "excluded-models": ["gemini-1.5-pro", "gemini-pro-vision"]
    }
  }' \
  http://localhost:8317/v0/management/gemini-api-key
```

**By API Key Match:**
```bash
curl -X PATCH -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '{
    "match": "AIzaSy-1",
    "value": {
      "api-key": "AIzaSy-1",
      "headers": {"X-Custom-Header": "custom-value"},
      "proxy-url": "socks5://proxy.example.com:1080",
      "excluded-models": ["gemini-1.5-pro-latest"]
    }
  }' \
  http://localhost:8317/v0/management/gemini-api-key
```

#### Delete Gemini Key

**Endpoint:** `DELETE /gemini-api-key`

**By API Key:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -X DELETE 'http://localhost:8317/v0/management/gemini-api-key?api-key=AIzaSy-1'
```

**By Index:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -X DELETE 'http://localhost:8317/v0/management/gemini-api-key?index=0'
```

---

### Claude API Keys

Manage Anthropic Claude API keys and configurations.

#### List Claude Keys

**Endpoint:** `GET /claude-api-key`

**Request:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  http://localhost:8317/v0/management/claude-api-key
```

**Response:**
```json
{
  "claude-api-key": [
    {
      "api-key": "sk-ant-...",
      "base-url": "https://api.anthropic.com",
      "proxy-url": "socks5://proxy.example.com:1080",
      "headers": {
        "X-Workspace": "team-a"
      },
      "excluded-models": ["claude-3-opus"]
    }
  ]
}
```

#### Replace All Claude Keys

**Endpoint:** `PUT /claude-api-key`

**Request:**
```bash
curl -X PUT -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '[
    {
      "api-key": "sk-ant-a",
      "proxy-url": "socks5://proxy.example.com:1080",
      "headers": {"X-Workspace": "team-a"},
      "excluded-models": ["claude-3-opus"]
    },
    {
      "api-key": "sk-ant-b",
      "base-url": "https://custom.example.com",
      "proxy-url": "",
      "headers": {"X-Env": "prod"},
      "excluded-models": ["claude-3-sonnet", "claude-3.5-haiku"]
    }
  ]' \
  http://localhost:8317/v0/management/claude-api-key
```

#### Update Single Claude Key

**Endpoint:** `PATCH /claude-api-key`

**By Index:**
```bash
curl -X PATCH -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '{
    "index": 1,
    "value": {
      "api-key": "sk-ant-b2",
      "base-url": "https://custom.example.com",
      "proxy-url": "",
      "headers": {"X-Env": "stage"},
      "excluded-models": ["claude-3.7-sonnet"]
    }
  }' \
  http://localhost:8317/v0/management/claude-api-key
```

**By API Key Match:**
```bash
curl -X PATCH -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '{
    "match": "sk-ant-a",
    "value": {
      "api-key": "sk-ant-a",
      "base-url": "",
      "proxy-url": "socks5://proxy.example.com:1080",
      "headers": {"X-Workspace": "team-a"},
      "excluded-models": ["claude-3-opus", "claude-3.5-sonnet"]
    }
  }' \
  http://localhost:8317/v0/management/claude-api-key
```

#### Delete Claude Key

**Endpoint:** `DELETE /claude-api-key`

**By API Key:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -X DELETE 'http://localhost:8317/v0/management/claude-api-key?api-key=sk-ant-b2'
```

**By Index:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -X DELETE 'http://localhost:8317/v0/management/claude-api-key?index=0'
```

**Notes:**
- `headers` is optional; empty/blank pairs are removed automatically
- `excluded-models` blocks specific models; server lowercases, trims, deduplicates entries

---

### OpenAI Compatibility Providers

Manage third-party OpenAI-compatible API providers (OpenRouter, Together AI, etc.).

#### List Providers

**Endpoint:** `GET /openai-compatibility`

**Request:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  http://localhost:8317/v0/management/openai-compatibility
```

**Response:**
```json
{
  "openai-compatibility": [
    {
      "name": "openrouter",
      "base-url": "https://openrouter.ai/api/v1",
      "api-key-entries": [
        {
          "api-key": "sk-or-v1-...",
          "proxy-url": ""
        }
      ],
      "models": [
        {
          "name": "anthropic/claude-3.5-sonnet",
          "alias": "claude-3.5"
        }
      ],
      "headers": {
        "X-Provider": "openrouter"
      }
    }
  ]
}
```

#### Replace All Providers

**Endpoint:** `PUT /openai-compatibility`

**Request:**
```bash
curl -X PUT -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '[
    {
      "name": "openrouter",
      "base-url": "https://openrouter.ai/api/v1",
      "api-key-entries": [{"api-key": "sk-or-123", "proxy-url": ""}],
      "models": [{"name": "anthropic/claude-3.5-sonnet", "alias": "claude-3.5"}],
      "headers": {"X-Provider": "openrouter"}
    }
  ]' \
  http://localhost:8317/v0/management/openai-compatibility
```

#### Update Single Provider

**Endpoint:** `PATCH /openai-compatibility`

**By Name:**
```bash
curl -X PATCH -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '{
    "name": "openrouter",
    "value": {
      "name": "openrouter",
      "base-url": "https://openrouter.ai/api/v1",
      "api-key-entries": [{"api-key": "sk-new-key", "proxy-url": ""}],
      "models": [],
      "headers": {"X-Provider": "openrouter"}
    }
  }' \
  http://localhost:8317/v0/management/openai-compatibility
```

**By Index:**
```bash
curl -X PATCH -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '{
    "index": 0,
    "value": {
      "name": "openrouter",
      "base-url": "https://openrouter.ai/api/v1",
      "api-key-entries": [{"api-key": "sk-new-key", "proxy-url": ""}],
      "models": [],
      "headers": {"X-Provider": "openrouter"}
    }
  }' \
  http://localhost:8317/v0/management/openai-compatibility
```

#### Delete Provider

**Endpoint:** `DELETE /openai-compatibility`

**By Name:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -X DELETE 'http://localhost:8317/v0/management/openai-compatibility?name=openrouter'
```

**By Index:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -X DELETE 'http://localhost:8317/v0/management/openai-compatibility?index=0'
```

---

### OAuth Excluded Models

Configure model blocks for OAuth-based providers (Gemini CLI, Claude Code, etc.).

#### List Excluded Models

**Endpoint:** `GET /oauth-excluded-models`

**Request:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  http://localhost:8317/v0/management/oauth-excluded-models
```

**Response:**
```json
{
  "oauth-excluded-models": {
    "gemini-cli": ["*-preview", "gemini-1.5-flash-8b"],
    "claude": ["*-haiku"],
    "codex": ["gpt-4-turbo-preview"]
  }
}
```

#### Replace All Excluded Models

**Endpoint:** `PUT /oauth-excluded-models`

**Request:**
```bash
curl -X PUT -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '{
    "gemini-cli": ["*-preview"],
    "claude": ["*-haiku", "claude-3-opus"],
    "iflow": ["deepseek-v3.1", "glm-4.5"]
  }' \
  http://localhost:8317/v0/management/oauth-excluded-models
```

#### Update Provider's Excluded Models

**Endpoint:** `PATCH /oauth-excluded-models`

**Add/Update Models:**
```bash
curl -X PATCH -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '{
    "provider": "iflow",
    "models": ["deepseek-v3.1", "glm-4.5"]
  }' \
  http://localhost:8317/v0/management/oauth-excluded-models
```

**Clear Provider's Models:**
```bash
curl -X PATCH -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '{
    "provider": "iflow",
    "models": []
  }' \
  http://localhost:8317/v0/management/oauth-excluded-models
```

#### Delete Provider's Excluded Models

**Endpoint:** `DELETE /oauth-excluded-models`

**Request:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -X DELETE 'http://localhost:8317/v0/management/oauth-excluded-models?provider=iflow'
```

---

## Proxy Settings

Manage the upstream proxy server URL for all outbound requests.

### Get Proxy URL

**Endpoint:** `GET /proxy-url`

**Request:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  http://localhost:8317/v0/management/proxy-url
```

**Response:**
```json
{
  "proxy-url": "socks5://user:pass@127.0.0.1:1080/"
}
```

### Set Proxy URL

**Endpoint:** `PUT /proxy-url` or `PATCH /proxy-url`

**Request (PUT):**
```bash
curl -X PUT -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '{"value": "socks5://user:pass@127.0.0.1:1080/"}' \
  http://localhost:8317/v0/management/proxy-url
```

**Request (PATCH):**
```bash
curl -X PATCH -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -d '{"value": "http://127.0.0.1:8080"}' \
  http://localhost:8317/v0/management/proxy-url
```

**Response:**
```json
{
  "status": "ok"
}
```

### Clear Proxy URL

**Endpoint:** `DELETE /proxy-url`

**Request:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  -X DELETE http://localhost:8317/v0/management/proxy-url
```

**Response:**
```json
{
  "status": "ok"
}
```

---

## Usage Statistics

Retrieve aggregated in-memory request metrics. Statistics are reset on server restart.

### Get Usage Stats

**Endpoint:** `GET /usage`

**Request:**
```bash
curl -H 'Authorization: Bearer <MANAGEMENT_KEY>' \
  http://localhost:8317/v0/management/usage
```

**Response:**
```json
{
  "usage": {
    "total_requests": 24,
    "success_count": 22,
    "failure_count": 2,
    "total_tokens": 13890,
    "requests_by_day": {
      "2024-05-20": 12
    },
    "requests_by_hour": {
      "09": 4,
      "18": 8
    },
    "tokens_by_day": {
      "2024-05-20": 9876
    },
    "tokens_by_hour": {
      "09": 1234,
      "18": 865
    },
    "apis": {
      "POST /v1/chat/completions": {
        "total_requests": 12,
        "total_tokens": 9021,
        "models": {
          "gpt-4o-mini": {
            "total_requests": 8,
            "total_tokens": 7123,
            "details": [
              {
                "timestamp": "2024-05-20T09:15:04.123456Z",
                "tokens": {
                  "input_tokens": 523,
                  "output_tokens": 308,
                  "reasoning_tokens": 0,
                  "cached_tokens": 0,
                  "total_tokens": 831
                }
              }
            ]
          }
        }
      }
    }
  },
  "failed_requests": 2
}
```

**Notes:**
- Statistics are in-memory only and reset on restart
- Hourly counters aggregate all days into same hour bucket (00-23)
- `failed_requests` is a convenience field for `usage.failure_count`

---

## Common Patterns

### Authentication in Scripts

Store your management key in a variable:

```bash
MGMT_KEY="d9fec4eec99bca9851f5ee5064985f816deb75742e1e6eb3c4268d2e2ecbf2a2"
BASE_URL="http://localhost:8317/v0/management"

# Use in requests
curl -H "Authorization: Bearer $MGMT_KEY" "$BASE_URL/config"
```

### Error Handling

All endpoints return standard HTTP status codes:

- `200` - Success
- `400` - Bad Request (invalid parameters)
- `401` - Unauthorized (invalid/missing management key)
- `404` - Not Found
- `500` - Internal Server Error

**Error Response Format:**
```json
{
  "error": {
    "message": "Invalid API key format",
    "type": "invalid_request_error"
  }
}
```

### Batch Operations

To update multiple configurations, chain requests:

```bash
# Update API keys, then update proxy URL
curl -X PUT -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $MGMT_KEY" \
  -d '["key1", "key2"]' \
  "$BASE_URL/api-keys" && \
curl -X PUT -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $MGMT_KEY" \
  -d '{"value": "socks5://proxy:1080"}' \
  "$BASE_URL/proxy-url"
```

---

## VPS Deployment Specific

### Finding Your Management Key

On your VPS installation:

```bash
cat /opt/cliproxyapi/api-keys.txt | grep MANAGEMENT_KEY
```

### Testing from VPS

```bash
# Test locally
curl -H 'Authorization: Bearer YOUR_KEY' \
  http://localhost:8317/v0/management/config

# Test remotely (from another machine)
curl -H 'Authorization: Bearer YOUR_KEY' \
  http://YOUR_VPS_IP:8317/v0/management/config
```

### Common Tasks

**Add a new API key for clients:**
```bash
cd /opt/cliproxyapi/CLIProxyAPI
MGMT_KEY=$(grep MANAGEMENT_KEY /opt/cliproxyapi/api-keys.txt | cut -d= -f2)

# Get current keys
KEYS=$(curl -s -H "Authorization: Bearer $MGMT_KEY" \
  http://localhost:8317/v0/management/api-keys | jq -r '.["api-keys"]')

# Add new key
NEW_KEY=$(openssl rand -hex 16)
echo "$KEYS" | jq ". += [\"$NEW_KEY\"]" | \
  curl -X PUT -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $MGMT_KEY" \
    -d @- http://localhost:8317/v0/management/api-keys
```

**Check usage statistics:**
```bash
curl -H "Authorization: Bearer $MGMT_KEY" \
  http://localhost:8317/v0/management/usage | jq .
```

**Set upstream proxy:**
```bash
curl -X PUT -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $MGMT_KEY" \
  -d '{"value": "socks5://127.0.0.1:1080"}' \
  http://localhost:8317/v0/management/proxy-url
```

---

## Additional Resources

- **Official API Docs:** https://help.router-for.me/management/api
- **Web UI:** http://YOUR_VPS_IP:8317/management.html
- **Project Repository:** https://github.com/router-for-me/CLIProxyAPI
- **VPS Deployment Guide:** See README.md in this repository

---

## Security Notes

1. **Keep Management Key Secret:** Never commit it to version control
2. **Use HTTPS in Production:** Enable TLS in config.yaml for remote access
3. **Restrict Access:** Use firewall rules to limit management API access
4. **Rotate Keys Regularly:** Update management key periodically
5. **Monitor Logs:** Check `/opt/cliproxyapi/logs/` for unauthorized access attempts

```bash
# View recent management API access
docker compose logs --tail=100 | grep "/v0/management"
```

---

## Troubleshooting Web UI

### Management Panel Returns 404

**Symptoms:**
- Accessing `http://YOUR_VPS_IP:8317/management.html` returns 404 Not Found

**Diagnosis:**

```bash
# Run the diagnostic script
sudo bash fix-management-panel.sh
```

**Manual Diagnosis:**

1. **Check if panel is disabled:**
   ```bash
   grep "disable-control-panel" /opt/cliproxyapi/CLIProxyAPI/config.yaml
   ```
   Should show: `disable-control-panel: false`

   **⚠️ Important:** If `disable-control-panel: true`:
   - Server intentionally **skips downloading** management.html
   - `/management.html` **will return 404 by design**
   - This is expected behavior when disabled
   - Management API endpoints still work via `/v0/management/*`

2. **Check if management.html exists:**
   ```bash
   ls -la /opt/cliproxyapi/CLIProxyAPI/static/management.html
   ```

3. **Check Docker logs for download:**
   ```bash
   cd /opt/cliproxyapi/CLIProxyAPI
   docker compose logs | grep -i "management asset"
   ```
   Should show: `management asset updated successfully`

**Solutions:**

1. **Enable control panel in config.yaml:**
   ```bash
   sed -i 's/disable-control-panel: true/disable-control-panel: false/' \
     /opt/cliproxyapi/CLIProxyAPI/config.yaml
   cd /opt/cliproxyapi/CLIProxyAPI && docker compose restart
   ```

2. **Wait for auto-download:**
   The panel downloads automatically on startup. Wait 30-60 seconds after restart.

3. **Check internet connectivity:**
   ```bash
   # Test GitHub access
   curl -I https://github.com/router-for-me/Cli-Proxy-API-Management-Center
   ```

4. **Manual verification:**
   ```bash
   # Check static directory
   ls -la /opt/cliproxyapi/CLIProxyAPI/static/

   # Watch logs for download
   cd /opt/cliproxyapi/CLIProxyAPI
   docker compose logs -f | grep -i management
   ```

### Cannot Log In to Web UI

**Symptoms:**
- Web UI loads but login fails
- "Invalid key" or "Unauthorized" errors

**Solutions:**

1. **Find your management key:**
   ```bash
   cat /opt/cliproxyapi/api-keys.txt | grep MANAGEMENT_KEY
   ```

2. **Regenerate management key:**
   ```bash
   sudo bash update.sh
   # Select: Fix Management Key
   ```

3. **Check config.yaml:**
   ```bash
   grep "secret-key:" /opt/cliproxyapi/CLIProxyAPI/config.yaml
   ```
   Should not be empty or "CHANGE_THIS_TO_SECURE_RANDOM_KEY"

### Web UI Loads But Shows Errors

**Symptoms:**
- UI loads but can't fetch data
- CORS errors in browser console
- API calls fail

**Solutions:**

1. **Check allow-remote setting:**
   ```bash
   grep "allow-remote:" /opt/cliproxyapi/CLIProxyAPI/config.yaml
   ```
   Should show: `allow-remote: true` for remote access

2. **Verify service is running:**
   ```bash
   sudo systemctl status cliproxyapi
   docker ps | grep cli-proxy-api
   ```

3. **Test API endpoint:**
   ```bash
   MGMT_KEY=$(cat /opt/cliproxyapi/api-keys.txt | grep MANAGEMENT_KEY | cut -d= -f2)
   curl -H "Authorization: Bearer $MGMT_KEY" \
     http://localhost:8317/v0/management/config
   ```

### Old Version of Web UI

**Symptoms:**
- Missing features that should be available
- UI looks outdated

**Solutions:**

1. **Check file age:**
   ```bash
   ls -l /opt/cliproxyapi/CLIProxyAPI/static/management.html
   ```

2. **Force re-download:**
   ```bash
   cd /opt/cliproxyapi/CLIProxyAPI
   rm -f static/management.html
   docker compose restart

   # Wait 30 seconds for download
   sleep 30
   docker compose logs | grep "management asset"
   ```

### Custom UI Not Loading

**Symptoms:**
- Configured custom `panel-github-repository` but default UI loads

**Solutions:**

1. **Verify repository setting:**
   ```bash
   grep "panel-github-repository:" /opt/cliproxyapi/CLIProxyAPI/config.yaml
   ```

2. **Check logs for download errors:**
   ```bash
   docker compose logs | grep -i "github\|release\|download"
   ```

3. **Test repository URL:**
   ```bash
   # Should return repository info
   curl -I https://github.com/your-org/your-repo
   ```

4. **Clear and re-download:**
   ```bash
   cd /opt/cliproxyapi/CLIProxyAPI
   rm -rf static/
   docker compose restart
   ```

### Quick Fix Script

Use the automated fix script for common issues:

```bash
sudo bash fix-management-panel.sh
```

This script will:
- ✅ Check all config.yaml settings
- ✅ Verify management.html exists
- ✅ Check Docker container logs
- ✅ Test HTTP endpoint
- ✅ Automatically fix common issues
- ✅ Restart services if needed

---

## Additional Resources

- **Official Web UI Docs:** https://help.router-for.me/management/webui
- **Official API Docs:** https://help.router-for.me/management/api
- **Project Repository:** https://github.com/router-for-me/CLIProxyAPI
- **Management UI Repository:** https://github.com/router-for-me/Cli-Proxy-API-Management-Center

