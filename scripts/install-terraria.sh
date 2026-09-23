#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[install] %s\n' "$*"; }
die() { printf '[install] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "This script must run as root."

TERRARIA_VERSION="${TERRARIA_VERSION:-1458}"
TERRARIA_INSTALL_DIR="${TERRARIA_INSTALL_DIR:-/opt/terraria}"
TERRARIA_LINUX_USER="${TERRARIA_LINUX_USER:-terraria}"
TERRARIA_PORT="${TERRARIA_PORT:-7777}"
SERVICE_TEMPLATE="${1:-}"

[[ "$TERRARIA_VERSION" =~ ^[0-9]+$ ]] || die "TERRARIA_VERSION must contain digits only."
[[ "$TERRARIA_INSTALL_DIR" == /* ]] || die "TERRARIA_INSTALL_DIR must be an absolute path."
[[ "$TERRARIA_LINUX_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid TERRARIA_LINUX_USER."
[[ "$TERRARIA_PORT" =~ ^[0-9]+$ ]] || die "TERRARIA_PORT must be numeric."
(( TERRARIA_PORT >= 1 && TERRARIA_PORT <= 65535 )) || die "TERRARIA_PORT must be between 1 and 65535."
[[ -f "$SERVICE_TEMPLATE" ]] || die "Systemd service template not found: $SERVICE_TEMPLATE"

case "$(uname -m)" in
  x86_64|amd64) ;;
  *) die "This installer currently expects an x86_64 VM. Detected: $(uname -m)" ;;
esac

export DEBIAN_FRONTEND=noninteractive

log "Installing required Debian packages."
apt-get update
apt-get install -y --no-install-recommends ca-certificates wget unzip

if id "$TERRARIA_LINUX_USER" >/dev/null 2>&1; then
  log "Linux user '$TERRARIA_LINUX_USER' already exists."
else
  log "Creating Linux user '$TERRARIA_LINUX_USER'."
  useradd \
    --create-home \
    --home-dir "/home/$TERRARIA_LINUX_USER" \
    --shell /bin/bash \
    "$TERRARIA_LINUX_USER"
fi

install -d -o "$TERRARIA_LINUX_USER" -g "$TERRARIA_LINUX_USER" -m 0755 "$TERRARIA_INSTALL_DIR"
install -d -o "$TERRARIA_LINUX_USER" -g "$TERRARIA_LINUX_USER" -m 0755 "$TERRARIA_INSTALL_DIR/releases"
for path in \
  "/home/$TERRARIA_LINUX_USER/.local" \
  "/home/$TERRARIA_LINUX_USER/.local/share" \
  "/home/$TERRARIA_LINUX_USER/.local/share/Terraria" \
  "/home/$TERRARIA_LINUX_USER/.local/share/Terraria/Worlds"; do
  install -d -o "$TERRARIA_LINUX_USER" -g "$TERRARIA_LINUX_USER" -m 0755 "$path"
done
install -d -o root -g "$TERRARIA_LINUX_USER" -m 0750 /etc/terraria

RELEASE_DIR="$TERRARIA_INSTALL_DIR/releases/$TERRARIA_VERSION"
BINARY="$RELEASE_DIR/TerrariaServer.bin.x86_64"

if [[ -x "$BINARY" ]]; then
  log "Terraria version $TERRARIA_VERSION is already installed; skipping download."
else
  DOWNLOAD_URL="https://terraria.org/api/download/pc-dedicated-server/terraria-server-${TERRARIA_VERSION}.zip"
  TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf -- "${TEMP_DIR:-}"' EXIT
  ZIP_PATH="$TEMP_DIR/terraria-server.zip"

  log "Downloading official Terraria dedicated server $TERRARIA_VERSION."
  wget --https-only --output-document="$ZIP_PATH" "$DOWNLOAD_URL" \
    || die "Download failed: $DOWNLOAD_URL"

  unzip -tq "$ZIP_PATH" >/dev/null || die "Downloaded file is not a valid ZIP archive."
  unzip -q "$ZIP_PATH" -d "$TEMP_DIR/extracted"

  SOURCE_DIR="$TEMP_DIR/extracted/$TERRARIA_VERSION/Linux"
  [[ -f "$SOURCE_DIR/TerrariaServer.bin.x86_64" ]] \
    || die "Expected Linux x86_64 server binary was not found in the archive."

  log "Installing Terraria into $RELEASE_DIR."
  rm -rf "$RELEASE_DIR"
  install -d -o "$TERRARIA_LINUX_USER" -g "$TERRARIA_LINUX_USER" -m 0755 "$RELEASE_DIR"
  cp -a "$SOURCE_DIR/." "$RELEASE_DIR/"
  chmod +x "$RELEASE_DIR"/TerrariaServer*
  chown -R "$TERRARIA_LINUX_USER:$TERRARIA_LINUX_USER" "$RELEASE_DIR"
fi

ln -sfn "$RELEASE_DIR" "$TERRARIA_INSTALL_DIR/current"
chown -h "$TERRARIA_LINUX_USER:$TERRARIA_LINUX_USER" "$TERRARIA_INSTALL_DIR/current"

RENDERED_SERVICE="$(mktemp)"
trap 'rm -f -- "$RENDERED_SERVICE"; rm -rf -- "${TEMP_DIR:-}"' EXIT

sed \
  -e "s|@@TERRARIA_USER@@|$TERRARIA_LINUX_USER|g" \
  -e "s|@@INSTALL_DIR@@|$TERRARIA_INSTALL_DIR|g" \
  "$SERVICE_TEMPLATE" > "$RENDERED_SERVICE"

install -o root -g root -m 0644 "$RENDERED_SERVICE" /etc/systemd/system/terraria.service
systemctl daemon-reload

[[ -x "$TERRARIA_INSTALL_DIR/current/TerrariaServer.bin.x86_64" ]] \
  || die "Terraria binary verification failed after installation."

log "Terraria $TERRARIA_VERSION installed successfully."
log "Binary: $TERRARIA_INSTALL_DIR/current/TerrariaServer.bin.x86_64"
log "World directory: /home/$TERRARIA_LINUX_USER/.local/share/Terraria/Worlds"
log "The service is installed but will not start until serverconfig.txt is created."
