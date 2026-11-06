#!/usr/bin/env python3
"""Claim a predictable Tailscale MagicDNS name without stealing another node's."""
import json
import os
import subprocess
import sys
import time

system = os.environ.get("SELECTED_OS", "").lower()
if system not in ("windows", "linux", "macos"):
    sys.exit("SELECTED_OS must be windows, linux, or macos")
base = f"rdp-{system}"


def assigned_name():
    raw = subprocess.check_output(["tailscale", "status", "--json"], text=True)
    self = (json.loads(raw).get("Self") or {})
    fqdn = (self.get("DNSName") or "").rstrip(".").lower()
    return fqdn.split(".", 1)[0], fqdn


def candidates():
    yield base
    for number in range(1000):
        yield f"{base}-{number:02d}"


for desired in candidates():
    # Control plane enforces unique names; if a candidate is occupied it
    # may assign an automatic "-1" suffix. Verify the REAL assigned name.
    result = subprocess.run(
        (["tailscale", "set", f"--hostname={desired}"] if sys.platform == "win32" else ["sudo", "-n", "tailscale", "set", f"--hostname={desired}"]),
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        sys.exit(f"Unable to set Tailscale hostname {desired}: {result.stderr.strip()}")
    final_name = ""
    final_fqdn = ""
    for attempt in range(20):
        final_name, final_fqdn = assigned_name()
        if final_name == desired:
            with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as f:
                f.write(f"RDP_HOSTNAME={final_name}\n")
                f.write(f"RDP_DNS_NAME={final_fqdn}\n")
            print(f"Assigned MagicDNS name: {final_fqdn}")
            sys.exit(0)
        # Tailscale may append its own '-1' when a candidate is taken.
        if attempt >= 3 and final_name.startswith(desired + "-"):
            print(f"{desired} is occupied; received {final_name}; trying next suffix")
            break
        time.sleep(0.6)
    else:
        sys.exit(
            f"Hostname assignment did not converge after requesting {desired}; "
            f"last received: {final_fqdn}"
        )

sys.exit("All 1001 hostname candidates were occupied")
