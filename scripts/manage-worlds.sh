#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf '[worlds] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "$EUID" -eq 0 ]] || die "This script must run as root."
TERRARIA_LINUX_USER="${TERRARIA_LINUX_USER:-}"
[[ "$TERRARIA_LINUX_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid TERRARIA_LINUX_USER."

WORLD_DIR="/home/$TERRARIA_LINUX_USER/.local/share/Terraria/Worlds"
WORLD_PATH_FILE=/etc/terraria/world-path
CONFIG_PATH=/etc/terraria/serverconfig.txt

case "${1:-}" in
  list)
    printf '[worlds] Directory: %s\n' "$WORLD_DIR"
    [[ -d "$WORLD_DIR" ]] || { printf '[worlds] No worlds found.\n'; exit 0; }
    active_world=""
    [[ ! -f "$WORLD_PATH_FILE" ]] || active_world="$(< "$WORLD_PATH_FILE")"
    shopt -s nullglob
    worlds=("$WORLD_DIR"/*.wld)
    ((${#worlds[@]} > 0)) || { printf '[worlds] No worlds found.\n'; exit 0; }
    for world in "${worlds[@]}"; do
      [[ -f "$world" && ! -L "$world" ]] || continue
      name="${world##*/}"
      name="${name%.wld}"
      status=inactive
      [[ "$world" != "$active_world" ]] || status=active
      printf '[worlds] %s | %s | %s bytes\n' "$name" "$status" "$(stat -c %s -- "$world")"
    done
    ;;
  delete)
    name="${2:-}"
    confirmation="${3:-}"
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ && "$name" != . && "$name" != .. ]] \
      || die "Use exact filename shown by list-worlds, without .wld."
    [[ "$confirmation" == "DELETE $name" ]] || die "Confirmation must be: DELETE $name"
    world="$WORLD_DIR/$name.wld"
    [[ -f "$world" && ! -L "$world" ]] || die "World file does not exist: $world"

    active_world=""
    [[ ! -f "$WORLD_PATH_FILE" ]] || active_world="$(< "$WORLD_PATH_FILE")"
    config_world=""
    [[ ! -f "$CONFIG_PATH" ]] || config_world="$(awk -F= '$1 == "world" {print substr($0, 7); exit}' "$CONFIG_PATH")"
    if [[ "$world" == "$active_world" || "$world" == "$config_world" ]]; then
      [[ -z "$active_world" || -z "$config_world" || "$active_world" == "$config_world" ]] \
        || die "World path metadata and server configuration disagree; inspect VM before deleting."
      systemctl disable --now terraria.service
      if systemctl list-unit-files terraria-world-backup.timer --no-legend | grep -q '^terraria-world-backup.timer'; then
        systemctl disable --now terraria-world-backup.timer
      fi
      systemctl is-active --quiet terraria-world-backup.service \
        && die "Backup is still running. Retry after it finishes."
      rm -f -- "$CONFIG_PATH" "$WORLD_PATH_FILE"
      printf '[worlds] Stopped Terraria and removed active world configuration.\n'
    fi

    rm -- "$world"
    if [[ -f "$world.bak" && ! -L "$world.bak" ]]; then
      rm -- "$world.bak"
    fi
    printf '[worlds] Deleted %s. GitHub Release backups were not changed.\n' "$name"
    ;;
  *) die "Usage: manage-worlds.sh list | delete WORLD_NAME 'DELETE WORLD_NAME'" ;;
esac
