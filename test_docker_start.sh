#!/usr/bin/env bash
set -euo pipefail

STORE="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
SOCKET="$HOME/.docker/run/docker.sock"
WAIT_ATTEMPTS=36
WAIT_INTERVAL=10

echo "=== step 1: settings-store location ==="
echo "$STORE"

echo "=== step 2: patch settings-store ==="
if [[ -f "$STORE" ]]; then
  _tmp="$(mktemp)"
  jq '. + {"OpenUIOnStartupDisabled": true, "DisplayedOnboarding": true, "ShowInstallScreen": false}' \
    "$STORE" > "$_tmp" && mv "$_tmp" "$STORE" || { echo "WARN: patch failed"; rm -f "$_tmp"; }
  echo "patched:"
  jq '{OpenUIOnStartupDisabled,DisplayedOnboarding,ShowInstallScreen}' "$STORE"
else
  echo "WARN: settings-store not found, creating"
  mkdir -p "$(dirname "$STORE")"
  printf '{"OpenUIOnStartupDisabled":true,"DisplayedOnboarding":true,"ShowInstallScreen":false}\n' > "$STORE"
fi

echo "=== step 3: post-install (symlinks) ==="
if command -v docker >/dev/null 2>&1 && docker desktop version >/dev/null 2>&1; then
  echo "skipped — docker CLI and 'docker desktop' subcommand already functional"
else
  sudo -n true >/dev/null 2>&1 || { echo "WARN: post-install needs sudo; run: sudo -v first"; exit 125; }
  sudo /Applications/Docker.app/Contents/MacOS/install --user "$(id -un)" \
    && echo "post-install ok" || echo "WARN: post-install failed"
fi

echo "=== step 4: start docker desktop ==="
if pgrep -f "com.docker.backend" >/dev/null 2>&1; then
  echo "already running — skipping"
else
  nohup docker desktop start >/dev/null 2>&1 &
  disown $! 2>/dev/null || true
  echo "launched in background (nohup)"
fi

echo "=== step 5: wait for socket ($WAIT_ATTEMPTS x ${WAIT_INTERVAL}s) ==="
for ((i=1; i<=WAIT_ATTEMPTS; i++)); do
  if [[ -S "$SOCKET" ]] && docker info >/dev/null 2>&1; then
    echo "daemon ready after ${i} attempt(s)"
    exit 0
  fi
  echo "  attempt $i/$WAIT_ATTEMPTS — not ready yet"
  sleep "$WAIT_INTERVAL"
done

echo "WARN: daemon not ready after $((WAIT_ATTEMPTS * WAIT_INTERVAL))s"
exit 1
