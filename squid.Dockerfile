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
	squid -k shutdown -f /etc/squid/squid.conf 2>/dev/null || true

	pid="$(cat /run/squid.pid 2>/dev/null || true)"
	if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
		# Wait briefly for clean shutdown to avoid races on immediate restart.
		i=0
		while kill -0 "$pid" 2>/dev/null; do
			i=$((i + 1))
			[ "$i" -ge 20 ] && break
			sleep 0.25
		done
	fi
fi

rm -f /run/squid.pid /var/run/squid.pid

# If invoked manually without arguments, start Squid with the default command.
if [ "$#" -eq 0 ]; then
	set -- squid -NYC -f /etc/squid/squid.conf
fi

exec "$@"
EOF

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["squid", "-NYC", "-f", "/etc/squid/squid.conf"]
