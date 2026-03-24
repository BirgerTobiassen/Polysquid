#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WEBAPP_DIR="$SCRIPT_DIR/webapp"
IMAGE_NAME="polysquid-self-service:latest"
REQUESTS_DIR="$SCRIPT_DIR/requests"
CERTS_DIR="/etc/polysquid/certs"
SYSTEMD_DIR="/etc/systemd/system"
APP_UNIT_SRC="$SCRIPT_DIR/polysquid-self-service.service"
NGINX_UNIT_SRC="$SCRIPT_DIR/polysquid-self-service-nginx.service"
APP_UNIT_DST="$SYSTEMD_DIR/polysquid-self-service.service"
NGINX_UNIT_DST="$SYSTEMD_DIR/polysquid-self-service-nginx.service"

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root (sudo $0)"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required"
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemd is required"
    exit 1
fi

if [[ ! -f "$APP_UNIT_SRC" || ! -f "$NGINX_UNIT_SRC" ]]; then
    echo "Required service unit templates are missing from $SCRIPT_DIR"
    exit 1
fi

mkdir -p "$REQUESTS_DIR"
chmod 755 "$REQUESTS_DIR"

if [[ ! -d "$CERTS_DIR" ]]; then
    echo "Missing TLS cert directory: $CERTS_DIR"
    echo "Run the main install first or create the directory and place fullchain.pem and privkey.pem there."
    exit 1
fi

if [[ ! -f "$CERTS_DIR/fullchain.pem" || ! -f "$CERTS_DIR/privkey.pem" ]]; then
    echo "Missing TLS certificate files in $CERTS_DIR"
    echo "Expected: fullchain.pem and privkey.pem"
    exit 1
fi

echo "Building Docker image: $IMAGE_NAME"
docker build -t "$IMAGE_NAME" "$WEBAPP_DIR"

echo "Installing systemd units for repo path: $REPO_DIR"
sed "s|/opt/polysquid|$REPO_DIR|g" "$APP_UNIT_SRC" > "$APP_UNIT_DST"
sed "s|/opt/polysquid|$REPO_DIR|g" "$NGINX_UNIT_SRC" > "$NGINX_UNIT_DST"

chmod 644 "$APP_UNIT_DST" "$NGINX_UNIT_DST"

echo "Reloading systemd"
systemctl daemon-reload

echo "Enabling services"
systemctl enable polysquid-self-service.service
systemctl enable polysquid-self-service-nginx.service

echo "Starting services"
systemctl restart polysquid-self-service.service
systemctl restart polysquid-self-service-nginx.service

echo "Self-service portal installed"
echo "App unit:    $APP_UNIT_DST"
echo "Proxy unit:  $NGINX_UNIT_DST"
echo "Requests dir: $REQUESTS_DIR"
echo "Check status with: systemctl status polysquid-self-service.service polysquid-self-service-nginx.service"