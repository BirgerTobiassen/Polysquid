FROM debian:12-slim

# OpenSSL-backed Squid build to avoid GnuTLS chain presentation issues on TLS proxy listeners.
RUN apt-get update \
 && apt-get install -y --no-install-recommends squid-openssl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Create a readable entrypoint script.
# It initializes cache directories and then starts Squid in the foreground.
RUN cat <<'EOF' > /entrypoint.sh
#!/bin/sh
set -e

# Initialize cache layout (safe to run repeatedly).
squid -z -f /etc/squid/squid.conf || true

# Some Squid builds leave a helper process or PID file after `-z`.
# Stop it and remove stale PID files so the foreground start does not fail.
if [ -f /run/squid.pid ]; then
	pid="$(cat /run/squid.pid 2>/dev/null || true)"
	if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
		kill "$pid" 2>/dev/null || true
		sleep 1
	fi
fi

rm -f /run/squid.pid /var/run/squid.pid
exec "$@"
EOF

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["squid", "-NYC", "-f", "/etc/squid/squid.conf"]
