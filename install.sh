#!/bin/bash

# Install script for polysquid
# This script sets up a systemd service that periodically checks for updates to services.yaml
# and runs polysquid.py when changes are detected.

set -e

# Configuration
REPO_DIR="/opt/polysquid"
REPO_URL="git@github.com:BirgerTobiassen/Polysquid.git"
SERVICE_NAME="polysquid-update"
UPDATE_SCRIPT="/usr/local/bin/polysquid-update.sh"
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

# Create the update script
cat > "$UPDATE_SCRIPT" << 'EOF'
#!/bin/bash

REPO_DIR="/opt/polysquid"

cd "$REPO_DIR" || exit 1

# Get current hash of services.yaml
old_hash=$(git rev-parse HEAD:services.yaml 2>/dev/null || echo "")

# Pull latest changes
git pull --quiet

# Get new hash
new_hash=$(git rev-parse HEAD:services.yaml 2>/dev/null || echo "")

# If services.yaml changed, run polysquid.py
if [ "$old_hash" != "$new_hash" ] && [ -n "$new_hash" ]; then
    echo "$(date): services.yaml updated, running polysquid.py"
    python3 polysquid.py
else
    echo "$(date): No changes to services.yaml"
fi
EOF

chmod +x "$UPDATE_SCRIPT"

# Create systemd service
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Polysquid Update Service
After=network-online.target

[Service]
Type=oneshot
ExecStart=$UPDATE_SCRIPT
User=root
EOF

# Create systemd timer
TIMER_FILE="/etc/systemd/system/${SERVICE_NAME}.timer"
cat > "$TIMER_FILE" << EOF
[Unit]
Description=Run polysquid update $TIMER_INTERVAL
Persistent=true

[Timer]
OnCalendar=$TIMER_INTERVAL

[Install]
WantedBy=timers.target
EOF

# Reload systemd and enable timer
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.timer"

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

echo "Installation complete!"
echo "The service will check for updates to services.yaml every 5 minutes and run polysquid.py if changes are found."
echo "To check status: systemctl status ${SERVICE_NAME}.timer"
echo "To view logs: journalctl -u ${SERVICE_NAME}.service or tail /var/log/polysquid-update.log"