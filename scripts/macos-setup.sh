#!/usr/bin/env bash
set -euo pipefail

: "${RDP_PASSWORD:?RDP_PASSWORD is required}"
TS_IP="$(tailscale ip -4 | head -n 1)"
[[ "$TS_IP" == 100.* ]] || { echo "Tailscale IP not found" >&2; exit 1; }

# Native macOS RDP server; macOS GitHub-hosted runners might not provide
# interactive Screen Recording and Accessibility consent (TCC).
echo 'WARNING: hosted macOS may deny Screen Recording and Accessibility.'

# v0.9.11 is pinned to a verified, official Apple Silicon release asset.
# Downloading the release saves ~6-7 minutes of recompiling Rust each run.
VERSION="v0.9.11"
ASSET="macrdp-${VERSION}-aarch64-apple-darwin.tar.gz"
EXPECTED_SHA256="63ce4467069951a627ebf8a30bb477f1c0a5e85bea68444725b2bfede80f13b6"
ARTIFACT_DIR="${RUNNER_TEMP}/macrdp-release"
mkdir -p "$ARTIFACT_DIR"
curl --fail --location --show-error --silent --retry 3 --retry-delay 2 \
  "https://github.com/clintcan/macrdp/releases/download/${VERSION}/${ASSET}" \
  -o "${ARTIFACT_DIR}/${ASSET}"
printf '%s  %s\n' "$EXPECTED_SHA256" "${ARTIFACT_DIR}/${ASSET}" | shasum -a 256 --check
tar -xzf "${ARTIFACT_DIR}/${ASSET}" -C "$ARTIFACT_DIR"
MACRDP_BIN="$(find "$ARTIFACT_DIR" -type f -name macrdp -print -quit)"
[[ -n "$MACRDP_BIN" ]] || { echo "Official macrdp tarball did not contain a macrdp executable" >&2; exit 1; }
chmod +x "$MACRDP_BIN"
codesign --force --sign - "$MACRDP_BIN"

# macrdp refuses --skip-auth on non-loopback binds.
# Create a separate, temporary local macOS account for PAM authentication.
# Avoid changing the GitHub-hosted runner user's existing password.
USERNAME="rdpuser"
sudo sysadminctl -addUser "$USERNAME" -fullName "Temporary RDP User" \
  -password "$RDP_PASSWORD" -admin
id "$USERNAME" >/dev/null
sudo dscl . -authonly "$USERNAME" "$RDP_PASSWORD"

# --password-file is not supported. Store the credential in the runner's
# ephemeral Keychain, and let macrdp read it via --keychain (not process argv).

security add-generic-password -U -a "$USERNAME" -s macrdp \
  -w "$RDP_PASSWORD" -T /usr/bin/security
if ! security find-generic-password -s macrdp -a "$USERNAME" -w >/dev/null; then
  echo 'Unable to read macrdp credential from macOS Keychain.' >&2
  exit 1
fi

LOG_FILE="${RUNNER_TEMP}/macrdp.log"
echo "Launching macrdp on private Tailscale ${TS_IP}:3389..."
nohup "$MACRDP_BIN" \
  --bind "${TS_IP}:3389" \
  --username "$USERNAME" \
  --keychain \
  --virtual-display --width 1440 --height 900 \
  --map-ctrl-to-cmd \
  >"$LOG_FILE" 2>&1 < /dev/null &
MACRDP_PID=$!
echo "$MACRDP_PID" > "${RUNNER_TEMP}/macrdp.pid"

for attempt in $(seq 1 20); do
  if ! kill -0 "$MACRDP_PID" 2>/dev/null; then
    echo 'macrdp exited unexpectedly:' >&2
    tail -80 "$LOG_FILE" >&2 || true
    exit 1
  fi
  if nc -z -G 2 "$TS_IP" 3389 2>/dev/null; then
    echo "macrdp RDP server is listening on ${TS_IP}:3389."
    # Backward-compatible :3390 alias. This listens only on the Tailscale IP.
    nohup python3 "$GITHUB_WORKSPACE/scripts/rdp-port-alias.py" "$TS_IP" 3390 "$TS_IP" 3389 \
      >"$RUNNER_TEMP/rdp-port-alias.log" 2>&1 < /dev/null &
    ALIAS_PID=$!
    alias_ready=0
    for try in $(seq 1 10); do
      if ! kill -0 "$ALIAS_PID" 2>/dev/null; then break; fi
      if nc -z -G 2 "$TS_IP" 3390 2>/dev/null; then alias_ready=1; break; fi
      sleep 1
    done
    if [[ "$alias_ready" != 1 ]]; then
      echo 'macOS compatibility port 3390 failed to start' >&2
      tail -40 "$RUNNER_TEMP/rdp-port-alias.log" >&2 || true
      exit 1
    fi
    echo "Compatibility listener ${TS_IP}:3390 -> :3389 ready."
    echo 'Note: TCP listeners do not prove screen capture/input authorization.'
    exit 0
  fi
  sleep 1
done

echo 'macrdp did not begin listening on the Tailscale address:' >&2
tail -80 "$LOG_FILE" >&2 || true
exit 1
