# Self-Service Access Portal

A Flask-based web portal that allows users to request temporary network access. Submitted requests are saved as JSON files that polysquid can read and use to dynamically whitelist IPs in the "Self service" Squid proxy.

## Architecture

```
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

```
self-service/
├── webapp/
│   ├── app.py              # Flask application
│   ├── templates/
│   │   └── portal.html     # Web UI
│   ├── requirements.txt    # Python dependencies
│   └── Dockerfile          # Container definition
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

### 1. Build the Docker Image

```bash
cd /opt/polysquid/self-service/webapp
docker build -t polysquid-self-service:latest .
```

### 2. Create Shared Directories

The main installer prepares the shared directories used by the self-service stack:

- `/opt/polysquid/self-service/requests`
- `/etc/polysquid/certs`

If you are deploying on a host that has not run the main installer yet, run:

```bash
sudo /opt/polysquid/install.sh
```

### 2a. TLS Certificates (Let's Encrypt Recommended)

Certificate issuance, renewal, and deployment are documented centrally in the main README:

- [TLS Certificates (Let's Encrypt DNS-01)](../README.md#4-tls-certificates-lets-encrypt-dns-01)

Use that section as the source of truth for certificate setup.

### 3. Deploy as systemd Service (Manual)

```bash
sudo cp /opt/polysquid/self-service/polysquid-self-service.service \
        /etc/systemd/system/
sudo cp /opt/polysquid/self-service/polysquid-self-service-nginx.service \
  /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable polysquid-self-service.service
sudo systemctl enable polysquid-self-service-nginx.service
sudo systemctl start polysquid-self-service.service
sudo systemctl start polysquid-self-service-nginx.service
```

### 4. Verify the Service

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

The Flask app writes request files to `/opt/polysquid/self-service/requests/`. Each file is a JSON object:

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

**Next step**: Update polysquid.py to:
1. Read these request files during reconciliation
2. Extract active IPs (where expires_at > now)
3. Dynamically inject them into the "Self service" Squid allowed_ips

This allows users to request temporary access without administrator intervention.

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

1. **IP Spoofing**: The app captures `X-Forwarded-For` header if available. Ensure your proxy/load-balancer is trusted and sets this header correctly.
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
