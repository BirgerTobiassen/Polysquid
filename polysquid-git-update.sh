#!/bin/bash

REPO_DIR="/opt/polysquid"
LOG_FILE="/var/log/polysquid-update.log"
TRUSTED_EXEC="/usr/local/lib/polysquid/polysquid.py"

# Tag pattern to pull (e.g., "v1.*", "production-*", etc.)
TAG_PATTERN="${POLYSQUID_TAG_PATTERN:-v*}"

cd "$REPO_DIR" || { echo "$(date): Failed to cd to $REPO_DIR" | tee -a "$LOG_FILE"; exit 1; }

if [ ! -x "$TRUSTED_EXEC" ]; then
    echo "$(date): Trusted executor missing or not executable: $TRUSTED_EXEC" | tee -a "$LOG_FILE"
    exit 1
fi

# Fetch latest tags from remote
if ! git fetch --tags --quiet origin 2>/dev/null; then
    echo "$(date): Warning: Could not fetch tags from remote" | tee -a "$LOG_FILE"
fi

# Get current tag on HEAD
current_tag=$(git describe --tags --always 2>/dev/null || echo "")

# Get latest tag matching the pattern
latest_tag=$(git tag -l "$TAG_PATTERN" --sort=-version:refname --merged origin/HEAD 2>/dev/null | head -1)

if [ -z "$latest_tag" ]; then
    echo "$(date): No tags found matching pattern '$TAG_PATTERN'" | tee -a "$LOG_FILE"
    exit 0
fi

echo "$(date): Current tag: $current_tag, Latest tag: $latest_tag (pattern: $TAG_PATTERN)" | tee -a "$LOG_FILE"

# Only proceed if tag has changed
if [ "$current_tag" = "$latest_tag" ]; then
    echo "$(date): Already at latest tag, no update needed" | tee -a "$LOG_FILE"
    exit 0
fi

# Fetch and checkout the target tag
if ! git fetch --quiet --depth=1 origin tag "$latest_tag"; then
    echo "$(date): Failed to fetch tag $latest_tag from remote" | tee -a "$LOG_FILE"
    exit 1
fi

if ! git checkout --quiet "$latest_tag"; then
    echo "$(date): Failed to checkout tag $latest_tag" | tee -a "$LOG_FILE"
    exit 1
fi

echo "$(date): Checked out tag $latest_tag" | tee -a "$LOG_FILE"

# Get service config hash from new tag
new_hash=$(git rev-parse HEAD:services.yaml 2>/dev/null || echo "")

# Reconcile when tag changed (services.yaml is now at the new tag's version)
if [ -n "$new_hash" ]; then
    echo "$(date): Reconcile trigger detected (tag updated: $current_tag -> $latest_tag), running trusted polysquid executor" | tee -a "$LOG_FILE"
    if /usr/bin/python3 "$TRUSTED_EXEC" --config "$REPO_DIR/services.yaml" --base-dir "$REPO_DIR" 2>&1 | tee -a "$LOG_FILE"; then
        echo "$(date): trusted polysquid executor completed successfully" | tee -a "$LOG_FILE"
    else
        echo "$(date): trusted polysquid executor failed with exit code $?" | tee -a "$LOG_FILE"
    fi
else
    echo "$(date): No changes to services.yaml" | tee -a "$LOG_FILE"
fi