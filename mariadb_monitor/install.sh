#!/usr/bin/env bash
set -euo pipefail

X86_URL="https://raw.githubusercontent.com/frappe/fc-scripts/refs/heads/develop/mariadb_monitor/dist/mariadb_monitor-linux-amd64"
ARM64_URL="https://raw.githubusercontent.com/frappe/fc-scripts/refs/heads/develop/mariadb_monitor/dist/mariadb_monitor-linux-arm64"

ARCH=$(uname -m)
BIN="/tmp/mariadb_monitor"

if [ "$ARCH" = "x86_64" ]; then
    URL="$X86_URL"
elif [ "$ARCH" = "aarch64" ]; then
    URL="$ARM64_URL"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# Stop service (ignore failures)
systemctl stop mariadb_monitor.service 2>/dev/null || true

curl -fsSL -o "$BIN" "$URL"
chmod +x "$BIN"

"$BIN" install
