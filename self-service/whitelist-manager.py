#!/usr/bin/env python3
"""
Standalone helper for inspecting self-service request files.
Reads request files, filters out expired entries, and can render an example ACL snippet.
The live self-service proxy is reconciled by polysquid.py; this helper is for diagnostics.
"""

import json
import ipaddress
import logging
from pathlib import Path
from datetime import datetime, timezone

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("whitelist-manager")


def load_requests(requests_dir: str) -> dict:
    """
    Load all active request files from the requests directory.
    Returns dict: {source_ip: {duration, expires_at, reason, ...}}
    """
    requests_path = Path(requests_dir)
    active_whitelist = {}
    now = datetime.now(timezone.utc)

    if not requests_path.exists():
        log.warning(f"Requests directory does not exist: {requests_path}")
        return active_whitelist

    for filepath in sorted(requests_path.glob("request_*.json")):
        try:
            with filepath.open() as f:
                req = json.load(f)
            
            expires_at = datetime.fromisoformat(req.get("expires_at", "").replace("Z", "+00:00"))
            
            if expires_at > now:
                # Request is still valid
                source_ip = req.get("source_ip")
                if source_ip and is_valid_source_ip(source_ip):
                    active_whitelist[source_ip] = {
                        "expires_at": req.get("expires_at"),
                        "reason": req.get("reason", ""),
                        "duration_minutes": req.get("duration_minutes"),
                    }
                    log.debug(f"Loaded active request: {source_ip} (expires {req.get('expires_at')})")
                elif source_ip:
                    log.warning(f"Ignoring request with invalid source_ip '{source_ip}' in {filepath.name}")
            else:
                # Request expired, can be archived/deleted
                log.debug(f"Request expired: {filepath.name}")
                # Optionally move to archive or delete
                # filepath.unlink()  # Uncomment to delete expired requests
        except Exception as e:
            log.error(f"Error loading request file {filepath.name}: {e}")
    
    return active_whitelist


def generate_acl_config(active_whitelist: dict) -> str:
    """Generate example Squid ACL config lines for active request IPs."""
    if not active_whitelist:
        return "# No active whitelist requests\n"
    
    lines = ["# Dynamic whitelist from self-service requests", ""]
    
    # Generate ACL definitions (max_srcip_whitelist)
    ips = list(active_whitelist.keys())
    if ips:
        lines.append("acl dynamic_whitelist src " + " ".join(ips))
        lines.append("")
    
    # Generate comments with expiry info
    lines.append("# Request details:")
    for ip, details in active_whitelist.items():
        lines.append(f"# {ip}: expires {details['expires_at']} ({details.get('reason', 'no reason')})")
    
    return "\n".join(lines)


def is_valid_source_ip(value: str) -> bool:
    """Allow only literal IPv4/IPv6 addresses in dynamic whitelist entries."""
    try:
        ipaddress.ip_address(str(value))
        return True
    except ValueError:
        return False


def main():
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: whitelist-manager.py <requests_dir> [output_file]")
        sys.exit(1)
    
    requests_dir = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None
    
    active_whitelist = load_requests(requests_dir)
    config = generate_acl_config(active_whitelist)
    
    if output_file:
        Path(output_file).write_text(config)
        log.info(f"Wrote {len(active_whitelist)} active requests to {output_file}")
    else:
        print(config)


if __name__ == "__main__":
    main()
