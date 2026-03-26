#!/bin/bash

# Uninstall script for polysquid
# Removes systemd units/timers, logrotate entries, and update helper installed by install.sh.
# Use --purge to also remove /opt/polysquid and /var/log/polysquid-git-update.log.

set -euo pipefail

SERVICE_NAME="polysquid-git-update"
RECONCILE_SERVICE_NAME="polysquid-reconcile"
RECONCILE_PATH_NAME="polysquid-reconcile"
TRUSTED_DIR="/usr/local/lib/polysquid"
TRUSTED_EXEC="${TRUSTED_DIR}/polysquid.py"
TRUSTED_UPDATE="${TRUSTED_DIR}/polysquid-git-update.sh"
REPO_DIR="/opt/polysquid"
UPDATE_LOG="/var/log/polysquid-git-update.log"
PURGE=false

if [[ "${1:-}" == "--purge" ]]; then
    PURGE=true
fi

# Check if running as root
if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root (sudo $0 [--purge])"
    exit 1
fi

echo "Stopping and disabling update timer/service..."
systemctl disable --now "${SERVICE_NAME}.timer" 2>/dev/null || true
systemctl disable --now "${SERVICE_NAME}.service" 2>/dev/null || true
systemctl disable --now "${RECONCILE_SERVICE_NAME}.service" 2>/dev/null || true
systemctl disable --now "${RECONCILE_PATH_NAME}.path" 2>/dev/null || true

echo "Stopping and disabling generated polysquid services/timers..."
# Stop timers first so they cannot race and restart services during uninstall.
for unit in /etc/systemd/system/polysquid-*.timer; do
    if [[ -e "$unit" ]]; then
        unit_name="$(basename "$unit")"
        systemctl disable --now "$unit_name" 2>/dev/null || true
    fi
done

echo "Force-removing running polysquid containers (name prefix: polysquid_)..."
if command -v docker >/dev/null 2>&1; then
    mapfile -t POLYSQUID_CONTAINERS < <(docker ps -aq --filter "name=^polysquid_")
    if [[ "${#POLYSQUID_CONTAINERS[@]}" -gt 0 ]]; then
        docker rm -f "${POLYSQUID_CONTAINERS[@]}" >/dev/null 2>&1 || true
    fi
fi

# Units are disabled without --now because containers are already removed above.
for unit in /etc/systemd/system/polysquid-*.service /etc/systemd/system/polysquid-*.timer; do
    if [[ -e "$unit" ]]; then
        unit_name="$(basename "$unit")"
        systemctl disable "$unit_name" 2>/dev/null || true
    fi
done

echo "Removing generated systemd unit links/files..."
rm -f /etc/systemd/system/${SERVICE_NAME}.service
rm -f /etc/systemd/system/${SERVICE_NAME}.timer
rm -f /etc/systemd/system/${RECONCILE_SERVICE_NAME}.service
rm -f /etc/systemd/system/${RECONCILE_PATH_NAME}.path
rm -f /etc/systemd/system/polysquid-*.service
rm -f /etc/systemd/system/polysquid-*.timer

echo "Removing logrotate entries..."
rm -f /etc/logrotate.d/polysquid-git-update
rm -f /etc/logrotate.d/polysquid-*

echo "Removing trusted updater and executor..."
rm -f "$TRUSTED_UPDATE"
rm -f "$TRUSTED_EXEC"
rmdir "$TRUSTED_DIR" 2>/dev/null || true

if [[ "$PURGE" == true ]]; then
    echo "Purge enabled: removing $REPO_DIR and update log..."
    rm -rf "$REPO_DIR"
    rm -f "$UPDATE_LOG"
fi

echo "Reloading systemd daemon..."
systemctl daemon-reload
echo "Clearing stale failed systemd entries..."
systemctl reset-failed 'polysquid-*' 2>/dev/null || true

echo "Uninstall complete."
if [[ "$PURGE" == false ]]; then
    echo "Tip: run '$0 --purge' to also remove $REPO_DIR and $UPDATE_LOG"
fi
