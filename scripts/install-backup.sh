#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf '[backup-install] ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[backup-install] %s\n' "$*"; }

[[ "$EUID" -eq 0 ]] || die "This script must run as root."
TERRARIA_LINUX_USER="${TERRARIA_LINUX_USER:-}"
[[ "$TERRARIA_LINUX_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid TERRARIA_LINUX_USER."
id "$TERRARIA_LINUX_USER" >/dev/null 2>&1 || die "Linux user '$TERRARIA_LINUX_USER' does not exist. Run Terraria Server Setup first."
getent group "$TERRARIA_LINUX_USER" >/dev/null 2>&1 || die "Linux group '$TERRARIA_LINUX_USER' does not exist."

SOURCE_DIR="${1:-}"
[[ -d "$SOURCE_DIR" ]] || die "Backup source directory not found: $SOURCE_DIR"
for path in scripts/backup-world-to-github.sh scripts/restore-world-from-github.sh systemd/terraria-world-backup.service systemd/terraria-world-backup.timer; do
  [[ -f "$SOURCE_DIR/$path" ]] || die "Required file missing: $SOURCE_DIR/$path"
done

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl jq

install -m 0755 "$SOURCE_DIR/scripts/backup-world-to-github.sh" /usr/local/bin/backup-world-to-github.sh
install -m 0755 "$SOURCE_DIR/scripts/restore-world-from-github.sh" /usr/local/bin/restore-world-from-github.sh

rendered_service="$(mktemp)"
trap 'rm -f -- "$rendered_service"' EXIT
sed "s|@@TERRARIA_USER@@|$TERRARIA_LINUX_USER|g" \
  "$SOURCE_DIR/systemd/terraria-world-backup.service" > "$rendered_service"
install -m 0644 "$rendered_service" /etc/systemd/system/terraria-world-backup.service
install -m 0644 "$SOURCE_DIR/systemd/terraria-world-backup.timer" /etc/systemd/system/terraria-world-backup.timer
systemctl daemon-reload

log "Backup tools and timer installed for $TERRARIA_LINUX_USER."
log "Configure /etc/terraria-backup.env on the VM, then run: systemctl enable --now terraria-world-backup.timer"
