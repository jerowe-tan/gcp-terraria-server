#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[configure] %s\n' "$*"; }
die() { printf '[configure] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "This script must run as root."

TERRARIA_INSTALL_DIR="${TERRARIA_INSTALL_DIR:-/opt/terraria}"
TERRARIA_LINUX_USER="${TERRARIA_LINUX_USER:-terraria}"
TERRARIA_PORT="${TERRARIA_PORT:-7777}"
WORLD_NAME="${WORLD_NAME:-TerrariaWorld}"
WORLD_SIZE="${WORLD_SIZE:-medium}"
WORLD_DIFFICULTY="${WORLD_DIFFICULTY:-classic}"
MAX_PLAYERS="${MAX_PLAYERS:-8}"
WORLD_SEED="${WORLD_SEED:-}"
START_SERVER="${START_SERVER:-true}"
PASSWORD_FILE="${PASSWORD_FILE:-}"

cleanup() {
  if [[ -n "$PASSWORD_FILE" && -f "$PASSWORD_FILE" ]]; then
    rm -f -- "$PASSWORD_FILE"
  fi
}
trap cleanup EXIT

[[ -x "$TERRARIA_INSTALL_DIR/current/TerrariaServer.bin.x86_64" ]] \
  || die "Terraria is not installed. Run the Terraria Server Setup workflow first."

id "$TERRARIA_LINUX_USER" >/dev/null 2>&1 \
  || die "Linux user '$TERRARIA_LINUX_USER' does not exist. Run the installer first."

[[ "$WORLD_NAME" =~ ^[A-Za-z0-9._[:space:]-]+$ ]] \
  || die "World name contains unsupported characters."
[[ -z "$WORLD_SEED" || "$WORLD_SEED" =~ ^[A-Za-z0-9._[:space:]-]+$ ]] \
  || die "Seed contains unsupported characters."
[[ "$MAX_PLAYERS" =~ ^[0-9]+$ ]] || die "MAX_PLAYERS must be numeric."
(( MAX_PLAYERS >= 1 && MAX_PLAYERS <= 255 )) || die "MAX_PLAYERS must be between 1 and 255."

case "$WORLD_SIZE" in
  small)  WORLD_SIZE_CODE=1 ;;
  medium) WORLD_SIZE_CODE=2 ;;
  large)  WORLD_SIZE_CODE=3 ;;
  *) die "WORLD_SIZE must be small, medium, or large." ;;
esac

case "$WORLD_DIFFICULTY" in
  classic) WORLD_DIFFICULTY_CODE=0 ;;
  expert)  WORLD_DIFFICULTY_CODE=1 ;;
  master)  WORLD_DIFFICULTY_CODE=2 ;;
  journey) WORLD_DIFFICULTY_CODE=3 ;;
  *) die "WORLD_DIFFICULTY must be classic, expert, master, or journey." ;;
esac

WORLD_FILENAME="$(
  printf '%s' "$WORLD_NAME" \
    | sed -E 's/[[:space:]]+/_/g; s/[^A-Za-z0-9._-]//g'
)"
[[ -n "$WORLD_FILENAME" ]] || die "World name produced an empty filename."

WORLD_DIR="/home/$TERRARIA_LINUX_USER/.local/share/Terraria/Worlds"
WORLD_PATH="$WORLD_DIR/$WORLD_FILENAME.wld"
CONFIG_PATH="/etc/terraria/serverconfig.txt"

install -d -o "$TERRARIA_LINUX_USER" -g "$TERRARIA_LINUX_USER" -m 0755 "$WORLD_DIR"
install -d -o root -g "$TERRARIA_LINUX_USER" -m 0750 /etc/terraria

if [[ -e "$WORLD_PATH" ]]; then
  die "World already exists: $WORLD_PATH. No world was replaced."
fi

if [[ -e "$CONFIG_PATH" ]]; then
  die "A Terraria server configuration already exists at $CONFIG_PATH. Refusing to replace it automatically."
fi

PASSWORD=""
if [[ -n "$PASSWORD_FILE" && -f "$PASSWORD_FILE" ]]; then
  PASSWORD="$(cat "$PASSWORD_FILE")"
  if [[ "$PASSWORD" == *$'\n'* || "$PASSWORD" == *$'\r'* ]]; then
    die "TERRARIA_PASSWORD must not contain newline characters."
  fi
fi

TEMP_CONFIG="$(mktemp)"
trap 'rm -f -- "$TEMP_CONFIG"; cleanup' EXIT

{
  printf 'world=%s\n' "$WORLD_PATH"
  printf 'autocreate=%s\n' "$WORLD_SIZE_CODE"
  printf 'worldname=%s\n' "$WORLD_NAME"
  printf 'difficulty=%s\n' "$WORLD_DIFFICULTY_CODE"
  printf 'maxplayers=%s\n' "$MAX_PLAYERS"
  printf 'port=%s\n' "$TERRARIA_PORT"
  printf 'password=%s\n' "$PASSWORD"
  if [[ -n "$WORLD_SEED" ]]; then
    printf 'seed=%s\n' "$WORLD_SEED"
  fi
} > "$TEMP_CONFIG"

install -o root -g "$TERRARIA_LINUX_USER" -m 0640 "$TEMP_CONFIG" "$CONFIG_PATH"
printf '%s\n' "$WORLD_PATH" > /etc/terraria/world-path
chmod 0644 /etc/terraria/world-path

systemctl enable terraria.service

log "Configuration created."
log "World: $WORLD_PATH"
log "Size: $WORLD_SIZE"
log "Difficulty: $WORLD_DIFFICULTY"
log "Port: $TERRARIA_PORT"

if [[ "$START_SERVER" != "true" ]]; then
  log "Server start was not requested."
  exit 0
fi

log "Starting Terraria. First-time world generation can take several minutes."
systemctl restart terraria.service

for attempt in $(seq 1 120); do
  if systemctl is-failed --quiet terraria.service; then
    journalctl -u terraria.service -n 100 --no-pager >&2 || true
    die "Terraria service failed while generating or loading the world."
  fi

  if [[ -s "$WORLD_PATH" ]]; then
    log "World file created successfully."
    exit 0
  fi

  sleep 5
done

journalctl -u terraria.service -n 100 --no-pager >&2 || true
die "Timed out waiting 10 minutes for Terraria to create the world file."
