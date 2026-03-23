#!/bin/bash

# Install script for polysquid
# This script sets up a systemd service that periodically checks for updates to services.yaml
# and runs polysquid.py when changes are detected.

set -euo pipefail

# Configuration
REPO_DIR="/opt/polysquid"
REPO_URL="git@github.com:BirgerTobiassen/Polysquid.git"
SERVICE_NAME="polysquid-update"
RECONCILE_SERVICE_NAME="polysquid-reconcile"
TRUSTED_DIR="/usr/local/lib/polysquid"
TRUSTED_EXEC="${TRUSTED_DIR}/polysquid.py"
TRUSTED_UPDATE="${TRUSTED_DIR}/polysquid-update.sh"
CERTS_DIR="/etc/polysquid/certs"
TIMER_INTERVAL="*-*-* *:0/5:00"  # Every 5 minutes

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo $0)"
    exit 1
fi

# Clone or update the repository
if [ ! -d "$REPO_DIR/.git" ]; then
    echo "Cloning repository to $REPO_DIR..."
    git clone "$REPO_URL" "$REPO_DIR"
else
    echo "Repository already exists, pulling latest changes..."
    cd "$REPO_DIR"
    git pull
fi
chown -R root:root "$REPO_DIR"

# Install a trusted, root-owned executor outside the git working tree.
# This prevents code in future git pulls from being executed automatically.
mkdir -p "$TRUSTED_DIR"
install -o root -g root -m 0755 "$REPO_DIR/polysquid.py" "$TRUSTED_EXEC"
install -o root -g root -m 0755 "$REPO_DIR/polysquid-update.sh" "$TRUSTED_UPDATE"

# Create shared TLS cert location used by Squid TLS and self-service nginx.
mkdir -p "$CERTS_DIR"
chmod 755 /etc/polysquid "$CERTS_DIR" 2>/dev/null || true

# Create self-service requests directory for dynamic whitelist submissions.
REQUESTS_DIR="$REPO_DIR/self-service/requests"
mkdir -p "$REQUESTS_DIR"
chmod 755 "$REQUESTS_DIR"

# Create systemd service
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Polysquid Update Service
After=network-online.target

[Service]
Type=oneshot
ExecStart=$TRUSTED_UPDATE
User=root
EOF

# Create boot reconcile service
RECONCILE_SERVICE_FILE="/etc/systemd/system/${RECONCILE_SERVICE_NAME}.service"
cat > "$RECONCILE_SERVICE_FILE" << EOF
[Unit]
Description=Polysquid Reconcile Service State On Boot
After=network-online.target docker.service
Wants=network-online.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 $TRUSTED_EXEC --config $REPO_DIR/services.yaml --base-dir $REPO_DIR
User=root

[Install]
WantedBy=multi-user.target
EOF

# Create systemd timer
TIMER_FILE="/etc/systemd/system/${SERVICE_NAME}.timer"
cat > "$TIMER_FILE" << EOF
[Unit]
Description=Run polysquid update $TIMER_INTERVAL

[Timer]
OnCalendar=$TIMER_INTERVAL
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Reload systemd and enable timer
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.timer"
systemctl enable "${RECONCILE_SERVICE_NAME}.service"

# Create logrotate config for the update log
LOGROTATE_CONF="/etc/logrotate.d/polysquid-update"
cat > "$LOGROTATE_CONF" << EOF
/var/log/polysquid-update.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 644 root root
}
EOF

# Perform an initial reconciliation so enabled services start immediately after install.
/usr/bin/python3 "$TRUSTED_EXEC" --config "$REPO_DIR/services.yaml" --base-dir "$REPO_DIR"

echo "Installation complete!"
echo "Trusted executor installed at: ${TRUSTED_EXEC}"
echo "Trusted updater installed at: ${TRUSTED_UPDATE}"
echo "Shared cert directory prepared at: ${CERTS_DIR}"
echo "Self-service requests directory prepared at: ${REQUESTS_DIR}"
echo "Boot reconcile service enabled: ${RECONCILE_SERVICE_NAME}.service"
echo "Enabled services have been reconciled and started where applicable."
echo "The service will check for updates to services.yaml every 5 minutes and run the trusted executor if changes are found."
echo "To check status: systemctl status ${SERVICE_NAME}.timer"
echo "To view logs: journalctl -u ${SERVICE_NAME}.service or tail /var/log/polysquid-update.log"