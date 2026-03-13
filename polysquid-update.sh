#!/bin/bash

REPO_DIR="/opt/polysquid"
LOG_FILE="/var/log/polysquid-update.log"

cd "$REPO_DIR" || { echo "$(date): Failed to cd to $REPO_DIR" | tee -a "$LOG_FILE"; exit 1; }

# Get current hash of services.yaml
old_hash=$(git rev-parse HEAD:services.yaml 2>/dev/null || echo "")

# Pull latest changes
if git pull --quiet; then
    echo "$(date): Git pull successful"
else
    echo "$(date): Failed to pull from Git" | tee -a "$LOG_FILE"
    exit 1
fi

# Get new hash
new_hash=$(git rev-parse HEAD:services.yaml 2>/dev/null || echo "")

# If services.yaml changed, run polysquid.py
if [ "$old_hash" != "$new_hash" ] && [ -n "$new_hash" ]; then
    echo "$(date): services.yaml updated (old: $old_hash, new: $new_hash), running polysquid.py" | tee -a "$LOG_FILE"
    if python3 polysquid.py 2>&1 | tee -a "$LOG_FILE"; then
        echo "$(date): polysquid.py completed successfully" | tee -a "$LOG_FILE"
    else
        echo "$(date): polysquid.py failed with exit code $?" | tee -a "$LOG_FILE"
    fi
else
    echo "$(date): No changes to services.yaml (hash: $new_hash)"
fi