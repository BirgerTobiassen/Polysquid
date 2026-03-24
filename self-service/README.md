# Self-Service Access Portal

A Flask-based web portal that allows users to request temporary network access. Submitted requests are saved as JSON files that polysquid can read and use to dynamically whitelist IPs in the "Self service" Squid proxy.

## Architecture

```text
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  User Browser                                                │
│         │                                                    │
│         ├──> Nginx TLS Proxy (port 443)                      │
│         │       │                                            │
│         │       └──> Flask App (localhost:5000)              │
│         │       │                                            │
│         │       └──> Submits request (IP, duration)          │
│         │              │                                     │
│         │              └──> Saves to /requests/*.json        │
│         │                     │                              │
│         │                     └──> (Shared volume)           │
│         │                            │                       │
│         │                    polysquid reads files           │
│         │                            │                       │
│         │              Updates "Self service" whitelist      │
│         │                            │                       │
│         └────────────────> Squid allows IP temporarily       │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## Directory Structure

```text
self-service/
├── webapp/
│   ├── app.py              # Flask application
│   ├── templates/
│   │   └── portal.html     # Web UI
│   ├── requirements.txt    # Python dependencies
│   └── Dockerfile          # Container definition
├── install.sh              # Install/build/enable/start the self-service stack
├── build.sh                # Helper for manual build/start/stop/log workflows
├── whitelist-manager.py    # Helper to read request files
├── polysquid-self-service.service  # systemd unit template
├── polysquid-self-service-nginx.service  # HTTPS proxy service
├── nginx/
│   └── nginx.conf          # TLS reverse proxy config
├── requests/               # Shared volume (prepared by install.sh)
└── README.md              # This file

```

Shared system path:

- `/etc/polysquid/certs/`   # TLS certs: fullchain.pem + privkey.pem

## Setup

### 1. TLS Certificates (Let's Encrypt Recommended)

Certificate issuance, renewal, and deployment are documented centrally in the main README:

- [TLS Certificates (Let's Encrypt DNS-01)](../README.md#4-tls-certificates-lets-encrypt-dns-01)

Use that section as the source of truth for certificate setup.

The self-service stack expects:

- `/etc/polysquid/certs/fullchain.pem`
- `/etc/polysquid/certs/privkey.pem`

### 2. Install the Stack

```bash
cd /opt/polysquid/self-service
sudo ./install.sh
```

The installer:

- builds `polysquid-self-service:latest`
- creates the `requests/` directory if missing
- renders systemd units using the current repository path
- installs the units into `/etc/systemd/system/`
- enables and starts both the app and nginx services

For iterative local operations after installation, `build.sh` is still available for `build`, `restart`, `logs`, and `clean` workflows.

### 3. Verify the Service

```bash
# Check HTTPS portal
curl -k https://localhost/

# View status
sudo systemctl status polysquid-self-service.service
sudo systemctl status polysquid-self-service-nginx.service

# View logs
docker logs -f polysquid_self_service
docker logs -f polysquid_self_service_nginx
```

## Integration with Polysquid

The Flask app writes request files to the installed repository's `self-service/requests/` directory
(commonly `/opt/polysquid/self-service/requests/`). Each file is a JSON object:

```json
{
  "timestamp": "2026-03-23T12:34:56.789123Z",
  "source_ip": "192.168.1.100",
  "duration_minutes": 60,
  "expires_at": "2026-03-23T13:34:56.789123Z",
  "reason": "Need to access corporate portal",
  "status": "pending"
}
```

`whitelist-manager.py` can already read these files and generate dynamic ACL entries for active requests.
That helper exists, but the main reconciliation flow in `polysquid.py` does not yet consume its output automatically.
Today, the portal is responsible for request capture and storage; automatic injection into the proxy ACLs still needs to be wired into the main deployment flow.

## API Endpoints

### GET `/`

Serves the web portal form.

### POST `/api/request`

Submit a whitelist request.

**Request body:**

```json
{
  "duration_minutes": 60,
  "reason": "Optional description"
}
```

**Response:**

```json
{
  "status": "success",
  "message": "Request submitted for 60 minutes",
  "request_id": "request_20260323_123456_789123.json",
  "expires_at": "2026-03-23T13:34:56.789123Z"
}
```

### GET `/health`

Health check endpoint.

## Configuration

Environment variables (set in systemd unit):

- `REQUESTS_DIR`: Path to requests directory (default: `/shared/requests`)
- `REQUEST_PORT`: Flask port (default: `5000`)
- `LOG_LEVEL`: Logging level (default: `INFO`)

## Security Considerations

1. **Source IP Trust**: The app uses `X-Real-IP` from nginx (falling back to the socket peer address). Keep the Flask app behind the provided nginx proxy so clients cannot set this header directly.
2. **Rate Limiting**: Consider adding rate limiting to prevent abuse (currently not implemented).
3. **Request Validation**: The app validates duration (1–1440 minutes) and IP format.
4. **File Permissions**: Request files are world-readable in the shared volume. Ensure only authorized processes read them.
5. **Container Security**: Run the Flask container with minimal privileges, read-only rootfs where possible.

## Troubleshooting

### Container won't start

```bash
docker logs polysquid_self_service
```

### Cannot access the web portal

- Check firewall: `sudo firewall-cmd --add-port=443/tcp --permanent`
- Check app binding: `docker ps | grep polysquid_self_service`
- Check proxy binding: `docker ps | grep polysquid_self_service_nginx`
- Check app logs: `docker logs polysquid_self_service`
- Check proxy logs: `docker logs polysquid_self_service_nginx`

### Let's Encrypt DNS-01 validation fails

- Verify you created the TXT record exactly at `_acme-challenge.polysquid-test.uit.no`
- Check DNS propagation from an external resolver: `dig TXT _acme-challenge.polysquid-test.uit.no`
- If you use manual DNS validation, do not remove the TXT record until Certbot confirms the challenge succeeded

### Requests not being processed

- Verify requests directory exists: `ls -la /opt/polysquid/self-service/requests/`
- Check request files: `cat /opt/polysquid/self-service/requests/request_*.json`
- Test whitelist manager: `python3 whitelist-manager.py /opt/polysquid/self-service/requests`

## Future Enhancements

- [ ] Integrate request processing into polysquid.py
- [ ] Rate limiting and quota management
- [ ] Request history / dashboard
- [ ] Email notifications
- [ ] Authentication / registration system
- [ ] Automatic request expiry cleanup
