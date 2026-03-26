# Polysquid

Polysquid is a Python-based tool for managing multiple Squid proxy services using systemd. It reads a YAML configuration file (`services.yaml`) to define and deploy individual Squid instances as isolated Docker containers, with support for scheduled start/stop, IP restrictions, domain filtering, and Log rotation.

## Features

- **YAML Configuration**: Define services declaratively with ports, scheduling, access controls, and filtering rules.
- **Docker Isolation**: Each Squid service runs in its own container with isolated configuration, logs, and cache.
- **Systemd Integration**: Automatically creates services, timers for schedule-based start/stop, and log rotation configs.
- **Advanced Scheduling**: Schedule services by working hours, day of week, or custom calendar ranges with automatic shutdown.
- **Flexible Access Control**: Combine IP/CIDR whitelisting and domain whitelists with convenient shared configuration support.
- **Automated Updates**: Monitors Git for `services.yaml` changes (every 5 minutes) and redeploys affected services without downtime. Self-service request file changes trigger an immediate reconciliation via a systemd path unit.
- **Validation**: Comprehensive input validation with detailed logging of issues.

## Prerequisites

### TLS Certificates (Let's Encrypt)

Required before running `install.sh` if any service uses `use_tls: true` or you are deploying the self-service portal.

Polysquid components that use TLS share certificate files from:

- `/etc/polysquid/certs/fullchain.pem`
- `/etc/polysquid/certs/privkey.pem`

Choose the validation method that matches your environment.

#### Option A: HTTP-01 (port 80 must be reachable from the internet)

```bash
sudo apt update
sudo apt install -y certbot
sudo certbot certonly --standalone -d polysquid-test.uit.no
```

Certbot temporarily binds port 80 to complete the challenge. Ensure no other service is using port 80 during issuance.

#### Option B: DNS-01 (use when port 80 is blocked by firewall policy)

```bash
sudo apt update
sudo apt install -y certbot
sudo certbot certonly --manual --preferred-challenges dns -d polysquid-test.uit.no
```

When prompted, create the TXT record for:

```text
_acme-challenge.polysquid-test.uit.no
```

Note: `--manual` is interactive and not suitable for unattended renewals. Use a DNS provider Certbot plugin for automated renewals.

#### After issuance (both methods)

Copy the certificate pair into the shared cert path:

```bash
sudo cp /etc/letsencrypt/live/polysquid-test.uit.no/fullchain.pem /etc/polysquid/certs/fullchain.pem
sudo cp /etc/letsencrypt/live/polysquid-test.uit.no/privkey.pem /etc/polysquid/certs/privkey.pem
sudo chmod 600 /etc/polysquid/certs/privkey.pem
```

Restart consumers after updating certs:

```bash
sudo systemctl restart polysquid-nginx.service
# Restart any TLS-enabled squid services if needed:
sudo python3 polysquid.py
```

## Quick Start

### 1. Install

```bash
sudo ./install.sh
```

This sets up:

- Repository at `/opt/polysquid`
- Systemd timer checking for updates every 5 minutes
- Automated redeployment on `services.yaml` changes
- Log rotation for update logs
- An initial reconciliation run so enabled services start immediately after install

### 2. Configure

Edit `services.yaml` with your services:

```yaml
services:
  - name: "Office Proxy"
    port: 3128
    enabled: true
    on_calendar:
      string: "Mon..Fri 08:00..18:00"  # Auto start/stop weekdays 8am-6pm
    allowed_ips:
      - 192.168.1.0/24
      - 10.0.0.0/8
    whitelists:
      list:
        - .example.com
        - .trusted.org
```

### 3. Deploy

Changes to `services.yaml` auto-deploy via the installed timer. For manual deployment:

```bash
sudo python3 polysquid.py
```

## Installation

1. Clone the repository:

   ```bash
   git clone git@github.com:BirgerTobiassen/Polysquid.git
   cd Polysquid
   ```

2. Run the install script (requires root):

   ```bash
   sudo ./install.sh
   ```

  This clones the repository to `/opt/polysquid`, installs trusted root-owned runtime scripts to `/usr/local/lib/polysquid/`, sets up systemd services and timers for automated updates (checking every 5 minutes), configures log rotation for update logs, and performs an initial reconciliation run so enabled services start immediately.

1. Alternatively, run manually without installation:

   ```bash
   python3 polysquid.py
   ```

## Configuration

### Basic Service Definition

Edit `services.yaml` to define your services:

```yaml
services:
  - name: "Example Service"
    port: 3128
    use_tls: true  # Optional: make the main service port a TLS Squid listener
    enabled: true
    on_calendar:
      string: "Mon..Fri 09:00..17:00"  # Optional scheduling
    allowed_ips: ["192.168.1.0/24", "10.0.0.1"]  # Optional IP restrictions
    whitelists:
      list: ["example.com", "trusted.org"]  # Optional domain whitelist
```

**Required fields**: `name`, `port`, `enabled`

**Optional fields**:

- `on_calendar`: Mapping with either `shared: <calendar_name>` or `string: "DAY HOUR1..HOUR2"`
- `allowed_ips`: List of source IP addresses or CIDR ranges allowed to connect
- `whitelists`: Mapping with optional `list`, `shared`, and `edl` lists
- `use_tls`: If true, the main `port` is exposed as a TLS Squid listener instead of plain HTTP

### Advanced: Shared Configurations

Reduce repetition by defining shared calendars and lists:

```yaml
services:
  - name: "Shared Whitelist Example"
    port: 3128
    enabled: true
    whitelists:
      shared:
        - office_sites
        - dev_tools
  - name: "Scheduled Example"
    port: 3129
    enabled: true
    on_calendar:
      shared: work_hours

shared:
  calendars:
    work_hours: "Mon..Fri 08:00..18:00"
    off_hours: "Mon..Fri 18:00..08:00, Sat..Sun 00:00..23:59:59"
  lists:
    office_sites:
      - .example.com
      - .trusted.org
    dev_tools:
      - .github.com
      - .npm.org
```

### Access Control Rules

**Precedence**:

1. If the `whitelists` key is present: only whitelisted domains are allowed, everything else is denied (deny-by-default)
2. If no `whitelists`: all domains from allowed_ips are allowed (allow-by-default)
3. Source IP restrictions apply to all traffic

**Example**: Restrictive policy (whitelist + IP restrictions)

```yaml
- name: "Corporate Proxy"
  port: 3128
  use_tls: true
  enabled: true
  allowed_ips:
    - 192.168.1.0/24   # Only office network
  whitelists:
    list:
      - .company.com
      - .github.com
      - .npm.org

Clients can then connect to the Squid proxy over TLS on `port` using the same
certificate pair stored in `/etc/polysquid/certs/` and mounted for the
self-service HTTPS portal. This adds a
TLS-protected proxy endpoint; it does not enable SSL bump or HTTPS interception.
```

**Example**: Allowlist for general browsing

```yaml
- name: "General Proxy"
  port: 3129
  enabled: true
  allowed_ips: ["0.0.0.0/0"]  # Any source (default if omitted)
  whitelists:
    list:
      - .trusted.com
      - .example.org
```

## Usage

### Deployment

**Automated**:

- The install script sets up a systemd timer that checks Git every 5 minutes for changes to `services.yaml`
- Changes automatically trigger the trusted executor at `/usr/local/lib/polysquid/polysquid.py` to redeploy affected services
- Self-service components are installed and managed separately by `self-service/install.sh`
- A boot reconcile service restores the correct service state after reboot (services start if current time is inside an enabled window)
- No downtime; containers are replaced seamlessly

**Manual**:

```bash
sudo python3 polysquid.py
```

Add `--verbose` for debug logging:

```bash
sudo python3 polysquid.py --verbose
```

### Service Management

View all Squid services:

```bash
systemctl list-units "polysquid-*"
```

Start/stop individual services:

```bash
sudo systemctl start polysquid-example.service
sudo systemctl stop polysquid-example.service
```

View service logs:

```bash
sudo docker logs polysquid_example
sudo journalctl -u polysquid-example.service
```

### Timer Scheduling

Services with `on_calendar` present are timer-managed and do not become always-on services:

```bash
# View timer status
sudo systemctl list-timers "polysquid-*-start.timer"
sudo systemctl list-timers "polysquid-*-stop.timer"

# View next scheduled triggers
sudo systemctl status polysquid-example-start.timer
```

### Update Monitoring

Check if automated updates are working:

```bash
sudo systemctl status polysquid-git-update.timer
sudo journalctl -u polysquid-git-update.service
tail -f /var/log/polysquid-git-update.log
```

Self-service units are managed by the self-service installer:

```bash
sudo systemctl status polysquid-webapp.service
sudo systemctl status polysquid-nginx.service
```

## Requirements

- **Python 3** with `pyyaml`
- **Docker** (with daemon running)
- **systemd** (Linux systems only)
- **Git** (for automated updates via install.sh)
- **Root access** for systemd operations

## Directory Structure

**Repository**:

```text
polysquid/
├── polysquid.py              # Main deployment script
├── polysquid-git-update.sh   # Git change detection and auto-deploy
├── install.sh                # Installation script
├── services.yaml             # Configuration file
├── proxy.Dockerfile          # Squid proxy Docker image definition
├── README.md                 # This file
└── polysquid-services/       # Generated per-service directories
    └── <service>/
        ├── systemd/          # Systemd unit files and timers
        ├── conf/             # squid.conf (generated)
        ├── logs/             # Container logs (mounted)
        └── cache/            # Squid cache (mounted, persistent)
```

**Installed Locations** (when using install.sh):

- Repository: `/opt/polysquid/`
- Trusted runtime scripts: `/usr/local/lib/polysquid/polysquid.py` and `/usr/local/lib/polysquid/polysquid-git-update.sh`
- Systemd units: `/etc/systemd/system/polysquid-*.{service,timer}`
- Log rotation: `/etc/logrotate.d/polysquid-*` and `/etc/logrotate.d/polysquid-git-update`
- Update logs: `/var/log/polysquid-git-update.log`

## Advanced Topics

### Calendar Format

The `on_calendar` field uses systemd calendar syntax:

```yaml
on_calendar:
  string: "Mon..Fri 08:00..18:00"       # Weekdays 8am-6pm
on_calendar:
  string: "Mon..Fri 08:00..12:00, 13:00..18:00"  # Split schedule (with lunch break)
on_calendar:
  string: "Sat 09:00..17:00"            # Saturdays only
on_calendar:
  string: "00:00..23:59:59"             # Every day (equivalent to no scheduling)
```

**Behavior**: Services automatically start at the first time and stop at the second time.

### Docker Image Configuration

Polysquid defaults to `polysquid-proxy:debian-openssl`, a local image built from `proxy.Dockerfile`
using Debian 12 with `squid-openssl`. This avoids GnuTLS chain-delivery issues on TLS-enabled proxy
listeners and is built automatically by `install.sh`.

To build it manually:

```bash
docker build -t polysquid-proxy:debian-openssl -f proxy.Dockerfile .
```

To use a different image, override with the `POLYSQUID_IMAGE` environment variable:

```bash
export POLYSQUID_IMAGE="polysquid-proxy:debian-openssl"
python3 polysquid.py

# Or inline at install time
POLYSQUID_IMAGE="polysquid-proxy:debian-openssl" sudo ./install.sh

# Check current containers
docker ps --filter "name=polysquid_" --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
```

### Domain Filtering Rules

- Domains should include the leading dot for subdomain matching: `.example.com` matches `proxy.example.com` and `example.com`
- Exact domains without dot: `example.com` matches only `example.com`
- Whitelist takes precedence: if whitelist is defined, any non-whitelisted traffic is denied

Example:

```yaml
- name: "Strict Corporate"
  port: 3128
  whitelists:
    list:
      - .github.com        # Matches github.com and all subdomains
      - .npm.org
      - localhost          # Exact match
```

### External Data Lists (EDL)

Whitelists can be populated from external URLs (e.g., EDLManager, blocklists, or custom APIs). EDL entries are fetched during each reconciliation and merged into the whitelist.

**Format**: Use the structured `whitelists` mapping:

```yaml
- name: "EDL-Managed Proxy"
  port: 3128
  whitelists:
    list:
      - .internal.example.com
    shared:
      - office_sites
      - dev_tools
    edl:
      - https://api.edlmanager.com/v1/list/abc123/
      - https://blocklist.example.org/whitelist.txt
```

This structured `whitelists` format is the only supported whitelist format.

**Requirements**:

- URL must be accessible from the polysquid server
- Response format: plaintext (one domain per line, comments with `#`, blank lines ignored)
- Domains are automatically normalized (leading dot added for subdomain matching)
- No authentication supported (connect to services with public endpoints or use a gateway)

**Caching**:

- EDL lists are cached during a single reconciliation run to avoid redundant fetches
- Cache is cleared at the start of each new reconcile, so lists are always fresh
- If a fetch fails, the affected service remains deny-by-default for destinations and an error is logged

**Example EDL response** (plaintext):

```text
# Example EDL response
.example.com
.trusted.org
github.io
# Comments and blank lines are ignored

.npm.org
```

### Performance Considerations

- Each service runs in a separate Docker container; memory/CPU resources scale linearly
- Squid cache is persistent per service (stored in `polysquid-services/<service>/cache/`)
- Logs are compressed and rotated daily (30-day retention by default)
- Systemd timers have 1-second accuracy; use for scheduling, not precise timing
- Git polling every 5 minutes is configurable in timer but recommended minimum is 1 minute
- EDL fetches happen during reconciliation; network timeouts are 10 seconds per URL

### Security Considerations

- Services require root for systemd operations
- Docker daemon access is equivalent to root privileges
- Enforce strong IP restrictions at the proxy level when needed
- Monitor logs for suspicious access patterns
- Domain whitelists enforce deny-by-default, providing the strongest security posture
- Share `services.yaml` with appropriate Git access controls

## Troubleshooting

### Service won't start

```bash
# Check systemd status and logs
sudo systemctl status polysquid-<servicename>.service
sudo journalctl -u polysquid-<servicename>.service -n 20 -e
```

### Container crashes or exits

```bash
# View container logs
sudo docker logs polysquid_<servicename>

# Check if port is already in use
sudo lsof -i :3128

# Verify Docker is running
sudo docker ps
```

### Changes to services.yaml aren't being applied

```bash
# Manually trigger deployment
sudo python3 /opt/polysquid/polysquid.py

# Check if Git has the latest version
cd /opt/polysquid && git log -1 --oneline services.yaml

# Verify the update timer is active
sudo systemctl status polysquid-git-update.timer
```

### Validation errors

```bash
# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('services.yaml')); print('Valid')"

# Run with verbose logging
sudo python3 polysquid.py --verbose

# Check for invalid domains (spaces, special characters)
grep -E '[[:space:]]|\$|@|#' services.yaml
```

### Permission issues

```bash
# Ensure Docker is accessible
sudo usermod -aG docker $USER
newgrp docker

# Verify sudo works without password (optional)
sudo visudo  # Add: %docker ALL=(ALL) NOPASSWD: /usr/bin/docker, /bin/systemctl
```

### Stuck timers or services

```bash
# Force reload systemd
sudo systemctl daemon-reload

# Disable and re-enable a timer
sudo systemctl disable polysquid-<servicename>-start.timer
sudo systemctl enable --now polysquid-<servicename>-start.timer

# Stop all polysquid services and clear stale containers
sudo systemctl stop 'polysquid-*.service'
sudo docker rm -f $(docker ps -a --filter "name=polysquid_" -q)
```

## Self-Service Access Portal

A Flask-based web portal that allows users to request temporary network access. Submitted requests are saved as JSON files that polysquid reads to dynamically whitelist source IPs in the configured Squid proxy.

### Architecture

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

### Self-Service Directory Structure

```text
self-service/
├── webapp/
│   ├── app.py              # Flask application
│   ├── templates/
│   │   └── portal.html     # Web UI
│   ├── requirements.txt    # Python dependencies
│   └── webapp.Dockerfile   # Container definition
├── install.sh              # Install/build/enable/start the self-service stack
├── uninstall.sh            # Disable/remove installed units and containers
├── build.sh                # Helper for manual build/start/stop/log workflows
├── whitelist-manager.py    # Standalone helper to inspect request files
├── polysquid-webapp.service         # systemd unit template (Flask app)
├── polysquid-nginx.service          # systemd unit template (HTTPS proxy)
├── nginx/
│   └── nginx.conf          # TLS reverse proxy config
└── requests/               # Shared volume (prepared by install.sh)
```

Shared system path: `/etc/polysquid/certs/` — TLS certs: `fullchain.pem` + `privkey.pem`

### Setup

**1. TLS Certificates**: See [Prerequisites](#prerequisites) above — the same cert pair is used by both the main proxy and the self-service portal.

**2. Install the stack:**

```bash
cd /opt/polysquid/self-service
sudo ./install.sh
```

The installer:

- Builds `polysquid-webapp:latest`
- Creates the `requests/` directory if missing
- Renders systemd units using the current repository path
- Installs the units into `/etc/systemd/system/`
- Enables and starts both the app and nginx services

For iterative local operations after installation, `build.sh` supports `build`, `restart`, `logs`, and `clean` workflows.

**3. Verify the service:**

```bash
# Check HTTPS portal
curl -k https://localhost/

# View status
sudo systemctl status polysquid-webapp.service
sudo systemctl status polysquid-nginx.service

# View logs
docker logs -f polysquid_webapp
docker logs -f polysquid_nginx
```

**4. Uninstall:**

```bash
cd /opt/polysquid/self-service
sudo ./uninstall.sh

# To also remove the Docker image and requests/ directory:
sudo ./uninstall.sh --purge
```

### Request File Format

The Flask app writes request files to `self-service/requests/` (commonly `/opt/polysquid/self-service/requests/`):

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

Self-service deployment is handled separately by `self-service/install.sh` and uses `polysquid-webapp.service` plus `polysquid-nginx.service`. `whitelist-manager.py` is available as a standalone helper to inspect active requests and generate an example ACL snippet for diagnostics.

### API Endpoints

| Method | Path | Description |
| ------ | ---- | ----------- |
| `GET` | `/` | Serves the web portal form |
| `POST` | `/api/request` | Submit a whitelist request |
| `GET` | `/health` | Health check |

**POST `/api/request` body:**

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

### Environment Variables

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `REQUESTS_DIR` | `/shared/requests` | Path to requests directory |
| `REQUEST_PORT` | `5000` | Flask port |
| `LOG_LEVEL` | `INFO` | Logging level |

### Self-Service Troubleshooting

**Container won't start:**

```bash
docker logs polysquid_webapp
```

**Cannot access the web portal:**

```bash
# Check firewall
sudo firewall-cmd --add-port=443/tcp --permanent

# Check container binding
docker ps | grep polysquid_webapp
docker logs polysquid_webapp
docker logs polysquid_nginx
```

**Requests not being processed:**

```bash
# Verify requests directory and files
ls -la /opt/polysquid/self-service/requests/
cat /opt/polysquid/self-service/requests/request_*.json

# Test whitelist manager
python3 self-service/whitelist-manager.py /opt/polysquid/self-service/requests
```

## License

See LICENSE file or repository for details.

## Contributing

Issues, pull requests, and feedback are welcome on GitHub.
