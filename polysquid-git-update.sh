#!/bin/bash

REPO_DIR="/opt/polysquid"
LOG_FILE="/var/log/polysquid-update.log"
TRUSTED_EXEC="/usr/local/lib/polysquid/polysquid.py"

cd "$REPO_DIR" || { echo "$(date): Failed to cd to $REPO_DIR" | tee -a "$LOG_FILE"; exit 1; }

if [ ! -x "$TRUSTED_EXEC" ]; then
    echo "$(date): Trusted executor missing or not executable: $TRUSTED_EXEC" | tee -a "$LOG_FILE"
    exit 1
fi

# Get current service config hash before pull
old_hash=$(git rev-parse HEAD:services.yaml 2>/dev/null || echo "")

# Pull latest changes
if git pull --quiet; then
    echo "$(date): Git pull successful" | tee -a "$LOG_FILE"
else
    echo "$(date): Failed to pull from Git" | tee -a "$LOG_FILE"
    exit 1
fi

# Get new service config hash after pull
new_hash=$(git rev-parse HEAD:services.yaml 2>/dev/null || echo "")

# Reconcile when services.yaml changes (request file changes are handled by systemd path trigger)
if [ "$old_hash" != "$new_hash" ] && [ -n "$new_hash" ]; then
    echo "$(date): Reconcile trigger detected (services.yaml changed: $old_hash -> $new_hash), running trusted polysquid executor" | tee -a "$LOG_FILE"
    if /usr/bin/python3 "$TRUSTED_EXEC" --config "$REPO_DIR/services.yaml" --base-dir "$REPO_DIR" 2>&1 | tee -a "$LOG_FILE"; then
        echo "$(date): trusted polysquid executor completed successfully" | tee -a "$LOG_FILE"
    else
        echo "$(date): trusted polysquid executor failed with exit code $?" | tee -a "$LOG_FILE"
    fi
else
    echo "$(date): No changes to services.yaml" | tee -a "$LOG_FILE"
fi