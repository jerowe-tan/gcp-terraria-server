#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

for command_name in curl jq sha256sum stat flock mktemp install awk; do
  require_command "$command_name"
done

[[ -n "${GITHUB_BACKUP_REPOSITORY:-}" ]] || die "GITHUB_BACKUP_REPOSITORY is required"
[[ -n "${GITHUB_BACKUP_TOKEN:-}" ]] || die "GITHUB_BACKUP_TOKEN is required"
[[ -n "${TERRARIA_WORLD_PATH:-}" ]] || die "TERRARIA_WORLD_PATH is required"

GITHUB_BACKUP_RELEASE_TAG="${GITHUB_BACKUP_RELEASE_TAG:-terraria-world-backups}"
GITHUB_BACKUP_RELEASE_NAME="${GITHUB_BACKUP_RELEASE_NAME:-Terraria World Backups}"
BACKUP_FILE_PREFIX="${BACKUP_FILE_PREFIX:-terraria-world}"
MAX_WORLD_BACKUPS="${MAX_WORLD_BACKUPS:-10}"
BACKUP_STATE_DIR="${BACKUP_STATE_DIR:-/var/lib/terraria-backup}"
TERRARIA_SAVE_SETTLE_SECONDS="${TERRARIA_SAVE_SETTLE_SECONDS:-2}"

[[ "$GITHUB_BACKUP_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
  || die "GITHUB_BACKUP_REPOSITORY must look like owner/repository"
[[ "$BACKUP_FILE_PREFIX" =~ ^[A-Za-z0-9._-]+$ ]] \
  || die "BACKUP_FILE_PREFIX may contain only letters, numbers, dot, underscore, and dash"
[[ "$MAX_WORLD_BACKUPS" =~ ^[1-9][0-9]*$ ]] \
  || die "MAX_WORLD_BACKUPS must be a positive integer"
[[ "$TERRARIA_SAVE_SETTLE_SECONDS" =~ ^[0-9]+$ ]] \
  || die "TERRARIA_SAVE_SETTLE_SECONDS must be a non-negative integer"
[[ -f "$TERRARIA_WORLD_PATH" ]] || die "World file does not exist: $TERRARIA_WORLD_PATH"

force_backup=0
case "${1:-}" in
  "")
    ;;
  --force)
    force_backup=1
    ;;
  *)
    die "Usage: $0 [--force]"
    ;;
esac

mkdir -p "$BACKUP_STATE_DIR"
exec 9>"$BACKUP_STATE_DIR/backup.lock"
if ! flock -n 9; then
  log "Another backup is already running; skipping this interval."
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

if [[ -n "${TERRARIA_SAVE_HOOK:-}" ]]; then
  [[ -x "$TERRARIA_SAVE_HOOK" ]] || die "TERRARIA_SAVE_HOOK is not executable: $TERRARIA_SAVE_HOOK"
  log "Running Terraria save hook."
  "$TERRARIA_SAVE_HOOK"
  sleep "$TERRARIA_SAVE_SETTLE_SECONDS"
else
  log "No TERRARIA_SAVE_HOOK configured; snapshotting the current on-disk world file."
fi

snapshot="$tmp_dir/world.wld"
stable_snapshot=0

for attempt in 1 2 3; do
  before_stat="$(stat -Lc '%s:%Y:%Z' -- "$TERRARIA_WORLD_PATH")"
  cp -- "$TERRARIA_WORLD_PATH" "$snapshot"
  after_stat="$(stat -Lc '%s:%Y:%Z' -- "$TERRARIA_WORLD_PATH")"

  if [[ "$before_stat" == "$after_stat" ]]; then
    stable_snapshot=1
    break
  fi

  log "World file changed while being copied; retrying snapshot (${attempt}/3)."
  sleep 1
done

(( stable_snapshot == 1 )) || die "Could not capture a stable world snapshot after 3 attempts"

world_hash="$(sha256sum "$snapshot" | awk '{print $1}')"
state_file="$BACKUP_STATE_DIR/last-uploaded.sha256"

if (( force_backup == 0 )) && [[ -f "$state_file" ]]; then
  previous_hash="$(tr -d '[:space:]' < "$state_file")"
  if [[ "$previous_hash" == "$world_hash" ]]; then
    log "World is unchanged since the last successful upload; skipping."
    exit 0
  fi
fi

api_base="https://api.github.com/repos/$GITHUB_BACKUP_REPOSITORY"
api_headers=(
  -H "Accept: application/vnd.github+json"
  -H "Authorization: Bearer $GITHUB_BACKUP_TOKEN"
  -H "User-Agent: terraria-world-backup"
)

release_tag_encoded="$(printf '%s' "$GITHUB_BACKUP_RELEASE_TAG" | jq -sRr @uri)"
release_json="$tmp_dir/release.json"

http_status="$(curl -sS -L \
  -o "$release_json" \
  -w '%{http_code}' \
  "${api_headers[@]}" \
  "$api_base/releases/tags/$release_tag_encoded")"

if [[ "$http_status" == "404" ]]; then
  log "Backup release does not exist; creating '$GITHUB_BACKUP_RELEASE_TAG'."

  jq -n \
    --arg tag "$GITHUB_BACKUP_RELEASE_TAG" \
    --arg name "$GITHUB_BACKUP_RELEASE_NAME" \
    '{
      tag_name: $tag,
      name: $name,
      body: "Automated Terraria world backups. Old assets are rotated automatically.",
      draft: false,
      prerelease: false
    }' > "$tmp_dir/create-release.json"

  http_status="$(curl -sS -L \
    -o "$release_json" \
    -w '%{http_code}' \
    -X POST \
    "${api_headers[@]}" \
    -H "Content-Type: application/json" \
    --data-binary @"$tmp_dir/create-release.json" \
    "$api_base/releases")"

  [[ "$http_status" == "201" ]] || {
    message="$(jq -r '.message // "unknown GitHub API error"' "$release_json" 2>/dev/null || true)"
    die "Could not create backup release (HTTP $http_status): $message"
  }
elif [[ "$http_status" != "200" ]]; then
  message="$(jq -r '.message // "unknown GitHub API error"' "$release_json" 2>/dev/null || true)"
  die "Could not read backup release (HTTP $http_status): $message"
fi

release_id="$(jq -er '.id' "$release_json")"
timestamp="$(date -u +'%Y%m%dT%H%M%SZ')"
asset_name="${BACKUP_FILE_PREFIX}-${timestamp}-${world_hash:0:12}.wld"
asset_name_encoded="$(printf '%s' "$asset_name" | jq -sRr @uri)"
upload_json="$tmp_dir/upload.json"

log "Uploading $asset_name."

http_status="$(curl -sS -L \
  -o "$upload_json" \
  -w '%{http_code}' \
  -X POST \
  "${api_headers[@]}" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$snapshot" \
  "https://uploads.github.com/repos/$GITHUB_BACKUP_REPOSITORY/releases/$release_id/assets?name=$asset_name_encoded")"

[[ "$http_status" == "201" ]] || {
  message="$(jq -r '.message // "unknown GitHub API error"' "$upload_json" 2>/dev/null || true)"
  die "Backup upload failed (HTTP $http_status): $message"
}

assets_json="$tmp_dir/assets.json"
http_status="$(curl -sS -L \
  -o "$assets_json" \
  -w '%{http_code}' \
  "${api_headers[@]}" \
  "$api_base/releases/$release_id/assets?per_page=100")"

[[ "$http_status" == "200" ]] || die "Could not list release assets after upload (HTTP $http_status)"

backup_count="$(jq \
  --arg prefix "${BACKUP_FILE_PREFIX}-" \
  '[.[] | select(.name | startswith($prefix)) | select(.name | endswith(".wld"))] | length' \
  "$assets_json")"

if (( backup_count > MAX_WORLD_BACKUPS )); then
  delete_count=$((backup_count - MAX_WORLD_BACKUPS))
  log "Rotating $delete_count old backup(s); keeping the newest $MAX_WORLD_BACKUPS."

  mapfile -t stale_assets < <(
    jq -r \
      --arg prefix "${BACKUP_FILE_PREFIX}-" \
      --argjson n "$delete_count" \
      '[.[] | select(.name | startswith($prefix)) | select(.name | endswith(".wld"))]
       | sort_by(.created_at)
       | .[:$n][]
       | [.id, .name]
       | @tsv' \
      "$assets_json"
  )

  for row in "${stale_assets[@]}"; do
    IFS=$'\t' read -r stale_id stale_name <<< "$row"

    delete_status="$(curl -sS -L \
      -o "$tmp_dir/delete-response.txt" \
      -w '%{http_code}' \
      -X DELETE \
      "${api_headers[@]}" \
      "$api_base/releases/assets/$stale_id")"

    [[ "$delete_status" == "204" ]] \
      || die "Uploaded the new backup, but failed to delete old asset '$stale_name' (HTTP $delete_status)"

    log "Deleted old backup: $stale_name"
  done
fi

printf '%s\n' "$world_hash" > "$tmp_dir/last-uploaded.sha256"
install -m 600 "$tmp_dir/last-uploaded.sha256" "$state_file"

log "Backup complete: $asset_name"
