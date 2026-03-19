# Polysquid

Polysquid is a Python-based tool for managing multiple Squid proxy services using systemd. It reads a YAML configuration file (`services.yaml`) to define and deploy individual Squid instances as isolated Docker containers, with support for scheduled start/stop, IP restrictions, domain filtering, and Log rotation.

## Features

- **YAML Configuration**: Define services declaratively with ports, scheduling, access controls, and filtering rules.
- **Docker Isolation**: Each Squid service runs in its own container with isolated configuration, logs, and cache.
- **Systemd Integration**: Automatically creates services, timers for schedule-based start/stop, and log rotation configs.
- **Advanced Scheduling**: Schedule services by working hours, day of week, or custom calendar ranges with automatic shutdown.
- **Flexible Access Control**: Combine IP/CIDR whitelisting, domain blacklists, and domain whitelists with convenient shared configuration support.
- **Automated Updates**: Monitors Git for `services.yaml` changes and redeploys affected services without downtime.
- **Validation**: Comprehensive input validation with detailed logging of issues.

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

### 2. Configure

Edit `services.yaml` with your services:

```yaml
services:
  - name: "Office Proxy"
    port: 3128
    enabled: true
    on_calendar: "Mon..Fri 08:00..18:00"  # Auto start/stop weekdays 8am-6pm
    allowed_ips:
      - 192.168.1.0/24
      - 10.0.0.0/8
    blacklist:
      - .ads.com
      - .malware.net
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

   This clones the repository to `/opt/polysquid`, sets up systemd services and timers for automated updates (checking every 5 minutes), copies the update script to `/usr/local/bin/`, and configures log rotation for update logs.

3. Alternatively, run manually without installation:

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
    enabled: true
    on_calendar: "Mon..Fri 09:00..17:00"  # Optional scheduling
    allowed_ips: ["192.168.1.0/24", "10.0.0.1"]  # Optional IP restrictions
    whitelist: ["example.com", "trusted.org"]  # Optional domain whitelist
    blacklist: ["blocked.com"]  # Optional domain blacklist
```

**Required fields**: `name`, `port`, `enabled`

**Optional fields**:

- `on_calendar`: Systemd calendar format for scheduled start/stop. Format: `"DAY HOUR1..HOUR2"` (e.g., `"Mon..Fri 08:00..18:00"`)
- `allowed_ips`: List of source IP addresses or CIDR ranges allowed to connect
- `whitelist`: List of destination domains allowed (takes precedence over blacklist)
- `blacklist`: List of destination domains denied

### Advanced: Shared Configurations

Reduce repetition by defining shared calendars and lists:

```yaml
services:
  - name: "Shared Whitelist Example"
    port: 3128
    enabled: true
    whitelist:
      - shared.lists.office_sites
      - shared.lists.dev_tools
  - name: "Scheduled Example"
    port: 3129
    enabled: true
    on_calendar: shared.calendars.work_hours

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

1. If whitelist is defined: only whitelisted domains are allowed (blacklist is ignored)
2. If no whitelist: blacklisted domains are denied, others allowed
3. Source IP restrictions apply to all traffic

**Example**: Restrictive policy (whitelist + IP restrictions)

```yaml
- name: "Corporate Proxy"
  port: 3128
  enabled: true
  allowed_ips:
    - 192.168.1.0/24   # Only office network
  whitelist:
    - .company.com
    - .github.com
    - .npm.org
```

**Example**: Permissive with blocklist

```yaml
- name: "General Proxy"
  port: 3129
  enabled: true
  allowed_ips: ["0.0.0.0/0"]  # Any source (default if omitted)
  blacklist:
    - .malware.net
    - .phishing.com
```

## Usage

### Deployment

**Automated**:

- The install script sets up a systemd timer that checks Git every 5 minutes for changes to `services.yaml`
- Changes automatically trigger `polysquid.py` to redeploy affected services
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
systemctl list-units "squid-*"
```

Start/stop individual services:

```bash
sudo systemctl start squid-example.service
sudo systemctl stop squid-example.service
```

View service logs:

```bash
sudo docker logs squid_example
sudo journalctl -u squid-example.service
```

### Timer Scheduling

Services with `on_calendar` defined have start/stop timers:

```bash
# View timer status
sudo systemctl list-timers "squid-*-start.timer"
sudo systemctl list-timers "squid-*-stop.timer"

# View next scheduled triggers
sudo systemctl status squid-example-start.timer
```

### Update Monitoring

Check if automated updates are working:

```bash
sudo systemctl status polysquid-update.timer
sudo journalctl -u polysquid-update.service
tail -f /var/log/polysquid-update.log
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
├── polysquid-update.sh       # Git change detection and auto-deploy
├── install.sh                # Installation script
├── services.yaml             # Configuration file
├── README.md                 # This file
└── squid-clients/            # Generated per-service directories
    └── <service>/
        ├── systemd/          # Systemd unit files and timers
        ├── conf/             # squid.conf (generated)
        ├── logs/             # Container logs (mounted)
        └── cache/            # Squid cache (mounted, persistent)
```

**Installed Locations** (when using install.sh):

- Repository: `/opt/polysquid/`
- Update script: `/usr/local/bin/polysquid-update.sh`
- Systemd units: `/etc/systemd/system/squid-*.{service,timer}`
- Log rotation: `/etc/logrotate.d/squid-*` and `/etc/logrotate.d/polysquid-update`
- Update logs: `/var/log/polysquid-update.log`

## Advanced Topics

### Calendar Format

The `on_calendar` field uses systemd calendar syntax:

```yaml
on_calendar: "Mon..Fri 08:00..18:00"       # Weekdays 8am-6pm
on_calendar: "Mon..Fri 08:00..12:00, 13:00..18:00"  # Split schedule (with lunch break)
on_calendar: "Sat 09:00..17:00"            # Saturdays only
on_calendar: "00:00..23:59:59"             # Every day (equivalent to no scheduling)
```

**Behavior**: Services automatically start at the first time and stop at the second time.

### Docker Image Configuration

By default, Polysquid uses `ubuntu/squid:6.13-25.04_beta`. Override with:

```bash
# Environment variable
export POLYSQUID_IMAGE="ubuntu/squid:latest"
python3 polysquid.py

# Or in installation
POLYSQUID_IMAGE="ubuntu/squid:latest" sudo ./install.sh

# Check current containers
docker ps --filter "name=squid_" --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
```

### Domain Filtering Rules

- Domains should include the leading dot for subdomain matching: `.example.com` matches `proxy.example.com` and `example.com`
- Exact domains without dot: `example.com` matches only `example.com`
- Whitelist takes precedence: if whitelist is defined, any non-whitelisted traffic is denied
- Blacklist is bypassed by whitelist rules

Example:

```yaml
- name: "Strict Corporate"
  port: 3128
  whitelist:
    - .github.com        # Matches github.com and all subdomains
    - .npm.org
    - localhost          # Exact match
```

### Performance Considerations

- Each service runs in a separate Docker container; memory/CPU resources scale linearly
- Squid cache is persistent per service (stored in `squid-clients/<service>/cache/`)
- Logs are compressed and rotated daily (30-day retention by default)
- Systemd timers have 1-second accuracy; use for scheduling, not precise timing
- Git polling every 5 minutes is configurable in timer but recommended minimum is 1 minute

### Security Considerations

- Services require root for systemd operations
- Docker daemon access is equivalent to root privileges
- Enforce strong IP restrictions at the proxy level when needed
- Monitor logs for suspicious access patterns
- Use domain whitelists (not blacklists) for high-security environments
- Share `services.yaml` with appropriate Git access controls

## Troubleshooting

### Service won't start

```bash
# Check systemd status and logs
sudo systemctl status squid-<servicename>.service
sudo journalctl -u squid-<servicename>.service -n 20 -e
```

### Container crashes or exits

```bash
# View container logs
sudo docker logs squid_<servicename>

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
sudo systemctl status polysquid-update.timer
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
sudo systemctl disable squid-<servicename>-start.timer
sudo systemctl enable --now squid-<servicename>-start.timer

# Stop all Squid services and clear stale containers
sudo systemctl stop 'squid-*.service'
sudo docker rm -f $(docker ps -a --filter "name=squid_" -q)
```

## License

See LICENSE file or repository for details.

## Contributing

Issues, pull requests, and feedback are welcome on GitHub.
