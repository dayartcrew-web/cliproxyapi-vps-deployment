#!/bin/bash

echo "Checking Docker Compose configuration..."
echo ""

if [[ -f /opt/cliproxyapi/CLIProxyAPI/docker-compose.yml ]]; then
    echo "=== Current docker-compose.yml volumes section ==="
    grep -A 20 "volumes:" /opt/cliproxyapi/CLIProxyAPI/docker-compose.yml || echo "No volumes section found!"
    echo ""
    echo "=== Checking if auths directory is mounted ==="
    grep -i "auths" /opt/cliproxyapi/CLIProxyAPI/docker-compose.yml || echo "Auth directory NOT mounted!"
else
    echo "docker-compose.yml not found!"
fi
