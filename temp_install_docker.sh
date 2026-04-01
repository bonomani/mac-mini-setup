#!/usr/bin/env bash
# Temporary direct Docker daemon installer — bypasses install.sh framework
set -uo pipefail

STORE="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
SOCKET="$HOME/.docker/run/docker.sock"
WAIT_ATTEMPTS=36
WAIT_INTERVAL=10

echo "=== patch settings-store ==="
if [[ -f "$STORE" ]]; then
  _tmp="$(mktemp)"
  jq '. + {"OpenUIOnStartupDisabled": true, "DisplayedOnboarding": true, "ShowInstallScreen": false}' \
    "$STORE" > "$_tmp" && mv "$_tmp" "$STORE" || rm -f "$_tmp"
else
  mkdir -p "$(dirname "$STORE")"
  printf '{"OpenUIOnStartupDisabled":true,"DisplayedOnboarding":true,"ShowInstallScreen":false}\n' > "$STORE"
fi
jq '{OpenUIOnStartupDisabled,DisplayedOnboarding,ShowInstallScreen}' "$STORE"

echo "=== start docker ==="
if pgrep -f "com.docker.backend" >/dev/null 2>&1; then
  echo "already running"
else
  docker desktop start &
  disown $! 2>/dev/null || true
  echo "launched"
fi

echo "=== wait for socket ==="
for ((i=1; i<=WAIT_ATTEMPTS; i++)); do
  echo "  attempt $i/$WAIT_ATTEMPTS — socket: $(ls "$SOCKET" 2>/dev/null && echo present || echo absent)"
  if [[ -S "$SOCKET" ]] && docker info >/dev/null 2>&1; then
    echo "daemon ready"
    exit 0
  fi
  sleep "$WAIT_INTERVAL"
done

echo "WARN: not ready after $((WAIT_ATTEMPTS * WAIT_INTERVAL))s"
exit 1
