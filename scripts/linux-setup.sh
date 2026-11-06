#!/usr/bin/env bash
set -euo pipefail

: "${RDP_PASSWORD:?RDP_PASSWORD is required}"
TS_IP="$(tailscale ip -4 | head -n 1)"
[[ "$TS_IP" == 100.* ]] || { echo "Tailscale IP not found" >&2; exit 1; }

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  --no-install-recommends xrdp xorgxrdp xfce4 xfce4-terminal dbus-x11

if ! id rdpuser >/dev/null 2>&1; then
  sudo useradd --create-home --shell /bin/bash rdpuser
fi
printf 'rdpuser:%s\n' "$RDP_PASSWORD" | sudo chpasswd
printf 'startxfce4\n' | sudo tee /home/rdpuser/.xsession >/dev/null
sudo chown rdpuser:rdpuser /home/rdpuser/.xsession
sudo chmod 600 /home/rdpuser/.xsession
sudo adduser xrdp ssl-cert || true

# Bind the server to its private Tailscale address only.
sudo python3 - "$TS_IP" <<'PY'
import pathlib, re, sys
path = pathlib.Path('/etc/xrdp/xrdp.ini')
source = path.read_text()
output, n = re.subn(r'(?m)^port=3389\s*$', f'port=tcp://{sys.argv[1]}:3389', source, count=1)
if n != 1:
    raise SystemExit('Could not locate XRDP listen port in config')
path.write_text(output)
PY

sudo systemctl enable xrdp
sudo systemctl restart xrdp-sesman
sudo systemctl restart xrdp
sudo systemctl is-active --quiet xrdp
# XRDP's service may report active before the listener has bound; poll first.
ready=0
for attempt in $(seq 1 30); do
  if sudo ss -lnt | grep -F "$TS_IP:3389" >/dev/null; then
    ready=1
    break
  fi
  sleep 1
done
if [[ "$ready" != 1 ]]; then
  echo "XRDP did not listen on Tailscale IPv4 address" >&2
  sudo journalctl -u xrdp --no-pager -n 60
  exit 1
fi
echo 'XRDP + XFCE configured and bound to Tailscale.'
