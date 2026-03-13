# Polysquid

Polysquid is a Python-based tool for managing multiple Squid proxy services using systemd. It reads a YAML configuration file (`services.yaml`) to define and deploy individual Squid instances as Docker containers, with support for scheduling, IP restrictions, domain whitelists/blacklists, and log rotation.

## Features

- **YAML Configuration**: Define services in `services.yaml` with options for ports, scheduling, access controls, and more.
- **Systemd Integration**: Automatically creates systemd services, timers, and logrotate configurations.
- **Docker-Based**: Runs Squid in isolated Docker containers for each service.
- **Automated Updates**: Optional install script sets up a systemd service to periodically check Git for updates to `services.yaml` and redeploy services.
- **Validation**: Validates configuration inputs and skips invalid entries with logging.

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

3. Alternatively, run manually:
   ```bash
   python3 polysquid.py
   ```

## Configuration

Edit `services.yaml` to define your services. Example:

```yaml
services:
  - name: "Example Service"
    port: 3128
    enabled: true
    on_calendar: "Mon-Fri 09:00..17:00"  # Optional scheduling
    allowed_ips: ["192.168.1.0/24", "10.0.0.1"]  # Optional IP restrictions
    whitelist: ["example.com", "trusted.org"]  # Optional domain whitelist
    blacklist: ["blocked.com"]  # Optional domain blacklist
```

- **Required fields**: `name`, `port`, `enabled`
- **Optional fields**: `on_calendar` (systemd calendar format), `allowed_ips` (list of IPs/CIDRs), `whitelist`/`blacklist` (domain lists)

## Usage

- **Manual Deployment**: Run `python3 polysquid.py` to deploy/update services based on `services.yaml`.
- **Automated**: The install script sets up a service that checks Git every 5 minutes for changes to `services.yaml` and runs the script automatically.
- **Logs**: Check systemd logs with `journalctl -u polysquid-update.service`. Persistent logs are written to `/var/log/polysquid-update.log` when updates are detected.
- **Status**: Use `systemctl status polysquid-update.timer` to monitor the timer.

## Requirements

- Python 3 with `pyyaml`
- Docker
- systemd
- Git (for updates)
- Root access for systemd operations

## Directory Structure

- `polysquid.py`: Main script
- `services.yaml`: Configuration file
- `install.sh`: Installation script
- `squid-clients/`: Generated directories for each service (ignored in Git except examples)

## Troubleshooting

- Ensure Docker is running and accessible.
- Check logs in `/var/log/squid/` inside containers or via `docker logs`.
- Validate `services.yaml` syntax with `python3 -c "import yaml; yaml.safe_load(open('services.yaml'))"`.
- For permission issues, run as root or ensure sudo is configured.

