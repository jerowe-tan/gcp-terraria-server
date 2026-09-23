#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf '[worlds] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "$EUID" -eq 0 ]] || die "This script must run as root."
TERRARIA_LINUX_USER="${TERRARIA_LINUX_USER:-}"
[[ "$TERRARIA_LINUX_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid TERRARIA_LINUX_USER."

WORLD_DIR="/home/$TERRARIA_LINUX_USER/.local/share/Terraria/Worlds"
WORLD_PATH_FILE=/etc/terraria/world-path
CONFIG_PATH=/etc/terraria/serverconfig.txt
BACKUP_ENV=/etc/terraria-backup.env

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
  switch)
    name="${2:-}"
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ && "$name" != . && "$name" != .. ]] \
      || die "Use exact filename shown by list-worlds, without .wld."
    world="$WORLD_DIR/$name.wld"
    [[ -s "$world" && ! -L "$world" ]] || die "World file does not exist or is empty: $world"
    [[ -f "$CONFIG_PATH" && ! -L "$CONFIG_PATH" && -f "$WORLD_PATH_FILE" && ! -L "$WORLD_PATH_FILE" ]] \
      || die "Server configuration is missing or invalid. Create a world first."
    current_world="$(awk -F= '$1 == "world" {print substr($0, 7); exit}' "$CONFIG_PATH")"
    [[ -n "$current_world" && "$current_world" == "$(< "$WORLD_PATH_FILE")" ]] \
      || die "World path metadata and server configuration disagree; inspect VM before switching."
    if [[ "$world" == "$current_world" ]]; then
      printf '[worlds] %s is already selected.\n' "$name"
      exit 0
    fi
    [[ ! -e "$BACKUP_ENV" || ( -f "$BACKUP_ENV" && ! -L "$BACKUP_ENV" ) ]] \
      || die "Backup environment file is not a regular file: $BACKUP_ENV"

    temporary="$(mktemp -d /etc/terraria/.switch-world.XXXXXX)"
    cp -a -- "$CONFIG_PATH" "$temporary/config"
    cp -a -- "$WORLD_PATH_FILE" "$temporary/world-path"
    [[ ! -f "$BACKUP_ENV" ]] || cp -a -- "$BACKUP_ENV" "$temporary/backup-env"
    timer_was_active=false
    server_stopped=false
    completed=false
    cleanup() {
      trap - EXIT
      if [[ "$completed" != true ]]; then
        cp -a -- "$temporary/config" "$CONFIG_PATH"
        cp -a -- "$temporary/world-path" "$WORLD_PATH_FILE"
        [[ ! -f "$temporary/backup-env" ]] || cp -a -- "$temporary/backup-env" "$BACKUP_ENV"
        if [[ "$server_stopped" == true ]]; then
          systemctl restart terraria.service || true
          printf '[worlds] Restored previous world configuration after failed switch.\n' >&2
        fi
      fi
      if [[ "$timer_was_active" == true ]]; then
        systemctl start terraria-world-backup.timer || true
      fi
      rm -rf -- "$temporary"
    }
    trap cleanup EXIT

    if systemctl is-active --quiet terraria-world-backup.timer; then
      timer_was_active=true
      systemctl stop terraria-world-backup.timer
    fi
    systemctl is-active --quiet terraria-world-backup.service \
      && die "Backup is running. Retry after it finishes."
    systemctl stop terraria.service
    server_stopped=true

    sed "s|^world=.*$|world=$world|" "$CONFIG_PATH" > "$temporary/new-config"
    install -o root -g "$TERRARIA_LINUX_USER" -m 0640 "$temporary/new-config" "$CONFIG_PATH"
    printf '%s\n' "$world" > "$WORLD_PATH_FILE"
    if [[ -f "$BACKUP_ENV" ]]; then
      awk -v world="$world" '
        /^TERRARIA_WORLD_PATH=/ { print "TERRARIA_WORLD_PATH=" world; found=1; next }
        { print }
        END { if (!found) print "TERRARIA_WORLD_PATH=" world }
      ' "$BACKUP_ENV" > "$temporary/new-backup-env"
      chmod --reference="$BACKUP_ENV" "$temporary/new-backup-env"
      chown --reference="$BACKUP_ENV" "$temporary/new-backup-env"
      mv -- "$temporary/new-backup-env" "$BACKUP_ENV"
    fi

    systemctl start terraria.service
    port="$(awk -F= '$1 == "port" {print $2; exit}' "$CONFIG_PATH")"
    port="${port:-7777}"
    listening=false
    for attempt in $(seq 1 60); do
      if systemctl is-failed --quiet terraria.service; then
        die "Terraria failed to load $name."
      fi
      if systemctl is-active --quiet terraria.service \
        && ss -ltnH | awk '{print $4}' | grep -Eq "(:|\\])${port}$"; then
        listening=true
        break
      fi
      sleep 2
    done
    [[ "$listening" == true ]] || die "Terraria did not listen on port $port after switching to $name."
    completed=true
    printf '[worlds] Switched to %s. Terraria is listening on port %s.\n' "$name" "$port"
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
  *) die "Usage: manage-worlds.sh list | switch WORLD_NAME | delete WORLD_NAME 'DELETE WORLD_NAME'" ;;
esac
