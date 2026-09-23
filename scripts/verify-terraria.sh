#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[verify] %s\n' "$*"; }
die() { printf '[verify] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "This script must run as root."

TERRARIA_INSTALL_DIR="${TERRARIA_INSTALL_DIR:-/opt/terraria}"
TERRARIA_LINUX_USER="${TERRARIA_LINUX_USER:-terraria}"
TERRARIA_PORT="${TERRARIA_PORT:-7777}"

BINARY="$TERRARIA_INSTALL_DIR/current/TerrariaServer.bin.x86_64"
CONFIG="/etc/terraria/serverconfig.txt"
WORLD_PATH_FILE="/etc/terraria/world-path"

[[ -x "$BINARY" ]] || die "Terraria binary is missing or not executable: $BINARY"
[[ -f "$CONFIG" ]] || die "Terraria is installed, but no server configuration exists. Run the Terraria World workflow with action 'create-world'."
[[ -f "$WORLD_PATH_FILE" ]] || die "World path metadata is missing: $WORLD_PATH_FILE"

WORLD_PATH="$(cat "$WORLD_PATH_FILE")"
[[ -s "$WORLD_PATH" ]] || die "Configured world file does not exist or is empty: $WORLD_PATH"

if ! systemctl is-active --quiet terraria.service; then
  systemctl status terraria.service --no-pager >&2 || true
  journalctl -u terraria.service -n 100 --no-pager >&2 || true
  die "Terraria service is not running."
fi

PORT_FROM_CONFIG="$(awk -F= '$1 == "port" {print $2; exit}' "$CONFIG")"
PORT="${PORT_FROM_CONFIG:-$TERRARIA_PORT}"

LISTENING=0
for attempt in $(seq 1 24); do
  if ss -ltnH | awk '{print $4}' | grep -Eq "(:|\])${PORT}$"; then
    LISTENING=1
    break
  fi
  sleep 5
done

if (( LISTENING != 1 )); then
  journalctl -u terraria.service -n 100 --no-pager >&2 || true
  die "Terraria service is running, but TCP port $PORT is not listening."
fi

log "Terraria binary: OK"
log "Terraria service: RUNNING"
log "World file: $WORLD_PATH"
log "TCP port: $PORT LISTENING"
log "Terraria server verification succeeded."
