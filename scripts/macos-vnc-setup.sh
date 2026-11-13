#!/usr/bin/env bash
set -euo pipefail

: "${RDP_PASSWORD:?RDP_PASSWORD required}"
TS_IP="$(tailscale ip -4 | head -n 1)"
[[ "$TS_IP" == 100.* ]] || { echo "::error::Tailscale IPv4 unavailable"; exit 1; }

# Apple's legacy VNC authentication uses only eight bytes.
# A dedicated 8-character VNC_PASSWORD secret is preferred.
if [[ -n "${VNC_PASSWORD:-}" ]]; then
  PASS="$VNC_PASSWORD"
  AUTH_SOURCE="VNC_PASSWORD"
else
  PASS="${RDP_PASSWORD:0:8}"
  AUTH_SOURCE="RDP_PASSWORD_FIRST_8"
fi
export LC_ALL=C
if [[ ! "$PASS" =~ ^[[:graph:]]{8}$ ]]; then
  echo "::error::VNC password must be exactly 8 printable ASCII characters. Set VNC_PASSWORD secret."
  exit 1
fi
echo "::add-mask::$PASS"
echo "VNC_AUTH_SOURCE=$AUTH_SOURCE" >> "$GITHUB_ENV"

KICKSTART="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
PLIST="/System/Library/LaunchDaemons/com.apple.screensharing.plist"

# Restrict Apple Remote Management to the ephemeral rdpuser account.
# macOS >= 12.1 may reject kickstart activation; try launchctl as fallback.
if [[ -x "$KICKSTART" ]]; then
  sudo "$KICKSTART" -activate -configure -access -on \
    -allowAccessFor -specifiedUsers \
    -users rdpuser -privs -all \
    -clientopts -setvnclegacy -vnclegacy yes \
    -clientopts -setvncpw -vncpw "$PASS" \
    -restart -agent >"$RUNNER_TEMP/vnc-kickstart.log" 2>&1 || {
      echo "::warning::kickstart could not fully activate Screen Sharing; trying launchctl."
    }
fi

sudo launchctl enable system/com.apple.screensharing 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST" 2>/dev/null || true
sudo launchctl load -w "$PLIST" 2>/dev/null || true

for attempt in $(seq 1 25); do
  # Verify actual RFB banner, not just TCP listener.
  if python3 - "$TS_IP" <<'PY'
import socket,sys
try:
    with socket.create_connection((sys.argv[1],5900),timeout=2) as s:
        s.settimeout(2)
        banner=s.recv(12)
        if banner.startswith(b'RFB 003.'):
            print('VNC RFB banner:',banner.decode('ascii','replace').strip())
            raise SystemExit(0)
except OSError:
    pass
raise SystemExit(1)
PY
  then
    echo "VNC available on $TS_IP:5900 (RFB handshake confirmed)."
    echo "Screen sharing may be view-only due to macOS policy."
    exit 0
  fi
  sleep 2
done

echo "::error::macOS Screen Sharing did not expose an RFB service on TCP 5900."
echo "Apple restricts command-line enablement on recent macOS. GUI/MDM approval may be required."
sudo launchctl print system/com.apple.screensharing 2>&1 | head -25 || true
exit 1
