#!/usr/bin/env python3

import logging
import os
import re
import subprocess
import yaml

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

BASE_DIR = os.getcwd()
IMAGE = os.getenv('POLYSQUID_IMAGE', "ubuntu/squid:6.13-25.04_beta")

TEMPLATE_CONF = """http_port 3128
cache_dir ufs /var/spool/squid 100 16 256

access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log

acl localnet src all
"""

def validate_service(service):
    required = ['name', 'port', 'enabled']
    for key in required:
        if key not in service:
            logging.warning(f"Skipping service: missing '{key}'")
            return None

    # Validate port
    try:
        port = int(service['port'])
        if port < 1 or port > 65535:
            raise ValueError
    except (ValueError, TypeError):
        logging.warning(f"Skipping service '{service.get('name', 'unknown')}': invalid port")
        return None

    # Validate enabled
    enabled = bool(service['enabled'])

    # Validate calendar format (basic check)
    calendar = service.get('on_calendar', '')
    if calendar:
        try:
            parts = calendar.split()
            if len(parts) != 2 or '..' not in parts[1]:
                raise ValueError("Invalid calendar format")
        except Exception:
            logging.warning(f"Invalid on_calendar for '{service['name']}': {calendar}. Skipping timers.")
            calendar = ''

    # Validate allowed_ips (CIDR or IP)
    allowed_ips = service.get('allowed_ips', [])
    if allowed_ips is None:
        allowed_ips = []
    valid_allowed_ips = []
    for ip in allowed_ips:
        try:
            import ipaddress
            if '/' in str(ip):
                ipaddress.ip_network(str(ip), strict=False)
            else:
                ipaddress.ip_address(str(ip))
            valid_allowed_ips.append(str(ip))
        except Exception:
            logging.warning(f"Ignoring invalid allowed_ip '{ip}' for '{service['name']}')")

    # Validate whitelist/blacklist domains (basic)
    def validate_domains(name, domains):
        if domains is None:
            return []
        valid = []
        for d in domains:
            if not isinstance(d, str) or ' ' in d or d == '':
                logging.warning(f"Ignoring invalid {name} entry '{d}' for '{service['name']}')")
                continue
            valid.append(d)
        return valid

    whitelist = validate_domains('whitelist', service.get('whitelist', []))
    blacklist = validate_domains('blacklist', service.get('blacklist', []))

    return {
        'name': service['name'],
        'port': port,
        'enabled': enabled,
        'calendar': calendar,
        'allowed_ips': valid_allowed_ips,
        'whitelist': whitelist,
        'blacklist': blacklist,
    }


try:
    with open('services.yaml') as f:
        data = yaml.safe_load(f)
    if not isinstance(data, dict) or 'services' not in data:
        raise ValueError("Invalid services.yaml: must have 'services' key")
except (FileNotFoundError, yaml.YAMLError, ValueError) as e:
    logging.error(f"Error loading services.yaml: {e}")
    exit(1)


for service in data['services']:
    validated = validate_service(service)
    if not validated:
        continue

    name = validated['name']
    port = validated['port']
    enabled = validated['enabled']
    calendar = validated['calendar']
    allowed_ips = validated['allowed_ips']
    whitelist = validated['whitelist']
    blacklist = validated['blacklist']


    safe_name = re.sub(r'[^A-Za-z0-9_-]', '', name.replace(' ', '_'))

    client_dir = os.path.join(BASE_DIR, 'squid-clients', safe_name)
    systemd_dir = os.path.join(client_dir, 'systemd')
    conf_dir = os.path.join(client_dir, 'conf')
    log_dir = os.path.join(client_dir, 'logs')
    cache_dir = os.path.join(client_dir, 'cache')
    logrotate_dir = os.path.join(client_dir, 'logrotate')

    os.makedirs(systemd_dir, exist_ok=True)
    os.makedirs(conf_dir, exist_ok=True)
    os.makedirs(log_dir, exist_ok=True)
    os.makedirs(cache_dir, exist_ok=True)
    os.makedirs(logrotate_dir, exist_ok=True)

    # Fix directory permissions for Squid user inside docker (proxy = uid/gid 13)
    subprocess.run(['sudo', 'chown', '-R', '13:13', log_dir])
    subprocess.run(['sudo', 'chown', '-R', '13:13', cache_dir])

    with open(os.path.join(conf_dir, 'squid.conf'), 'w') as f:
        f.write(TEMPLATE_CONF)
        if allowed_ips:
            f.write("acl allowed_ips src")
            for ip in allowed_ips:
                f.write(f" {ip}")
            f.write("\nhttp_access allow allowed_ips\n")
        else:
            f.write("http_access allow localnet\n")
        if whitelist:
            f.write("acl whitelist dstdomain")
            for domain in whitelist:
                f.write(f" {domain}")
            f.write("\nhttp_access allow whitelist\n")
        if blacklist:
            f.write("acl blacklist dstdomain")
            for domain in blacklist:
                f.write(f" {domain}")
            f.write("\nhttp_access deny blacklist\n")
        f.write("http_access deny all\n")

    service_file = os.path.join(systemd_dir, f'squid-{safe_name}.service')
    start_timer_file = os.path.join(systemd_dir, f'squid-{safe_name}-start.timer')
    stop_timer_file = os.path.join(systemd_dir, f'squid-{safe_name}-stop.timer')
    logrotate_file = os.path.join(logrotate_dir, f'squid-{safe_name}.logrotate')

    # Create systemd service
    service_content = f"""[Unit]
Description=Squid Docker instance for {name}
After=docker.service network-online.target

[Service]
Type=simple
Restart=no

ExecStart=/usr/bin/docker run \\
  --name squid_{safe_name} \\
  -v {conf_dir}/squid.conf:/etc/squid/squid.conf \\
  -v {log_dir}:/var/log/squid \\
  -v {cache_dir}:/var/spool/squid \\
  -p {port}:3128 \\
  {IMAGE}

ExecStop=/usr/bin/docker stop squid_{safe_name}
ExecStopPost=/usr/bin/docker rm -f squid_{safe_name}
"""
    with open(service_file, 'w') as f:
        f.write(service_content)

    if calendar:
        # Parse calendar
        parts = calendar.split()
        days = parts[0]
        timerange = parts[1]
        start_time, end_time = timerange.split('..')
        start_calendar = f"{days} {start_time}"
        stop_calendar = f"{days} {end_time}"

        # Start timer
        start_timer_content = f"""[Unit]
Description=Start squid-{safe_name}

[Timer]
OnCalendar={start_calendar}
Persistent=true
AccuracySec=1sec
Unit=squid-{safe_name}.service

[Install]
WantedBy=timers.target
"""
        with open(start_timer_file, 'w') as f:
            f.write(start_timer_content)

        # Stop timer
        stop_timer_content = f"""[Unit]
Description=Stop squid-{safe_name}

[Timer]
OnCalendar={stop_calendar}
Persistent=true
AccuracySec=1sec
Unit=squid-{safe_name}.service

[Install]
WantedBy=timers.target
"""
        with open(stop_timer_file, 'w') as f:
            f.write(stop_timer_content)

    # Logrotate
    logrotate_content = f"""{BASE_DIR}/squid-clients/{safe_name}/logs/*.log {{
    daily
    rotate 30
    compress
    missingok
    notifempty
    delaycompress
    create 640 root adm
    sharedscripts
    postrotate
        systemctl kill -s SIGUSR1 squid-{safe_name}.service >/dev/null 2>&1 || true
    endscript
}}
"""
    with open(logrotate_file, 'w') as f:
        f.write(logrotate_content)

    # Clean old symlinks
    subprocess.run(['sudo', 'rm', '-f', f'/etc/systemd/system/squid-{safe_name}.service'])
    subprocess.run(['sudo', 'rm', '-f', f'/etc/systemd/system/squid-{safe_name}-start.timer'])
    subprocess.run(['sudo', 'rm', '-f', f'/etc/systemd/system/squid-{safe_name}-stop.timer'])
    subprocess.run(['sudo', 'rm', '-f', f'/etc/logrotate.d/squid-{safe_name}'])

    if enabled:
        logging.info(f"Enabled: {name}")
        subprocess.run(['sudo', 'ln', '-s', service_file, f'/etc/systemd/system/squid-{safe_name}.service'])
        if calendar:
            subprocess.run(['sudo', 'ln', '-s', start_timer_file, f'/etc/systemd/system/squid-{safe_name}-start.timer'])
            subprocess.run(['sudo', 'ln', '-s', stop_timer_file, f'/etc/systemd/system/squid-{safe_name}-stop.timer'])
            subprocess.run(['sudo', 'systemctl', 'enable', '--now', f'squid-{safe_name}-start.timer'])
            subprocess.run(['sudo', 'systemctl', 'enable', '--now', f'squid-{safe_name}-stop.timer'])
        else:
            subprocess.run(['sudo', 'systemctl', 'daemon-reload'])
            subprocess.run(['sudo', 'systemctl', 'enable', '--now', f'squid-{safe_name}.service'])
        subprocess.run(['sudo', 'ln', '-s', logrotate_file, f'/etc/logrotate.d/squid-{safe_name}'])
        subprocess.run(['sudo', 'systemctl', 'daemon-reload'])
    else:
        logging.info(f"Disabled: {name}")
        subprocess.run(['sudo', 'systemctl', 'disable', '--now', f'squid-{safe_name}.service'], stderr=subprocess.DEVNULL)
        if calendar:
            subprocess.run(['sudo', 'systemctl', 'disable', '--now', f'squid-{safe_name}-start.timer'], stderr=subprocess.DEVNULL)
            subprocess.run(['sudo', 'systemctl', 'disable', '--now', f'squid-{safe_name}-stop.timer'], stderr=subprocess.DEVNULL)
        subprocess.run(['sudo', 'rm', '-f', f'/etc/logrotate.d/squid-{safe_name}'])
        subprocess.run(['sudo', 'systemctl', 'daemon-reload'])

print("All entries processed.")
