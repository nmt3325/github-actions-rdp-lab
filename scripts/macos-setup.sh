#!/usr/bin/env bash
set -euo pipefail

: "${RDP_PASSWORD:?RDP_PASSWORD is required}"
TS_IP="$(tailscale ip -4 | head -n 1)"
[[ "$TS_IP" == 100.* ]] || { echo "Tailscale IP not found" >&2; exit 1; }

echo 'WARNING: macOS GitHub-hosted runners may lack TCC Screen Recording and Accessibility grants.'
echo 'This option builds macrdp for experimental remote access. No TCC bypass is attempted.'

git clone --depth=1 --branch v0.9.11 https://github.com/clintcan/macrdp.git "$RUNNER_TEMP/macrdp-source"
cd "$RUNNER_TEMP/macrdp-source"
cargo build --release
codesign -s - --force target/release/macrdp

PASSWORD_FILE="$RUNNER_TEMP/.macrdp-pass"
(umask 077; printf '%s\n' "$RDP_PASSWORD" > "$PASSWORD_FILE")
chmod 600 "$PASSWORD_FILE"

nohup target/release/macrdp \
  --bind "$TS_IP:3390" \
  --skip-auth \
  --password-file "$PASSWORD_FILE" \
  --virtual-display --width 1440 --height 900 \
  > "$RUNNER_TEMP/macrdp.log" 2>&1 &
echo $! > "$RUNNER_TEMP/macrdp.pid"
sleep 8
if ! kill -0 "$(cat "$RUNNER_TEMP/macrdp.pid")" 2>/dev/null; then
  cat "$RUNNER_TEMP/macrdp.log"
  exit 1
fi
echo 'Experimental macrdp is running. Connection may show a blank screen or reject input without interactive TCC consent.'
