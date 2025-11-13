#!/usr/bin/env bash
set -e

X86_URL="https://raw.githubusercontent.com/frappe/fc-scripts/refs/heads/develop/mariadb_io_monitor/binary/mariadb_io_monitor.x86"
ARM64_URL="https://raw.githubusercontent.com/frappe/fc-scripts/refs/heads/develop/mariadb_io_monitor/binary/mariadb_io_monitor.arm64"

ARCH=$(uname -m)
BIN="/usr/bin/mariadb_io_monitor"
SERVICE="/etc/systemd/system/mariadb_io_monitor.service"
TIMER="/etc/systemd/system/mariadb_io_monitor.timer"

if [ "$ARCH" = "x86_64" ]; then
    URL="$X86_URL"
elif [ "$ARCH" = "aarch64" ]; then
    URL="$ARM64_URL"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

curl -fsSL -o "$BIN" "$URL"
chmod +x "$BIN"

cat <<EOF > "$SERVICE"
[Unit]
Description=MariaDB IO Monitor
After=network.target

[Service]
ExecStart=$BIN
Restart=always
RestartSec=5
MemoryMax=250M

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > "$TIMER"
[Unit]
Description=Daily restart for mariadb_io_monitor

[Timer]
OnCalendar=daily
Persistent=true
Unit=mariadb_io_monitor.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now mariadb_io_monitor.service
systemctl enable --now mariadb_io_monitor.timer
