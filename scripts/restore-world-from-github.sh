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

usage() {
  cat <<'USAGE'
Usage:
  restore-world-from-github.sh --list
  restore-world-from-github.sh --latest [--yes]
  restore-world-from-github.sh --asset NAME [--yes]

Restore should be run while the Terraria server process is stopped.
If TERRARIA_STOP_HOOK is configured, the hook is run before replacement.
USAGE
}

for command_name in curl jq sha256sum mktemp awk; do
  command -v "$command_name" >/dev/null 2>&1 || die "Required command not found: $command_name"
done

[[ -n "${GITHUB_BACKUP_REPOSITORY:-}" ]] || die "GITHUB_BACKUP_REPOSITORY is required"
[[ -n "${GITHUB_BACKUP_TOKEN:-}" ]] || die "GITHUB_BACKUP_TOKEN is required"
[[ -n "${TERRARIA_WORLD_PATH:-}" ]] || die "TERRARIA_WORLD_PATH is required"

GITHUB_BACKUP_RELEASE_TAG="${GITHUB_BACKUP_RELEASE_TAG:-terraria-world-backups}"
BACKUP_FILE_PREFIX="${BACKUP_FILE_PREFIX:-terraria-world}"
BACKUP_STATE_DIR="${BACKUP_STATE_DIR:-/var/lib/terraria-backup}"

mode="latest"
requested_asset=""
assume_yes=0

while (( $# > 0 )); do
  case "$1" in
    --list)
      mode="list"
      shift
      ;;
    --latest)
      mode="latest"
      shift
      ;;
    --asset)
      [[ $# -ge 2 ]] || die "--asset requires a release asset name"
      mode="asset"
      requested_asset="$2"
      shift 2
      ;;
    --yes)
      assume_yes=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "Unknown argument: $1"
      ;;
  esac
done

api_base="https://api.github.com/repos/$GITHUB_BACKUP_REPOSITORY"
api_headers=(
  -H "Accept: application/vnd.github+json"
  -H "Authorization: Bearer $GITHUB_BACKUP_TOKEN"
  -H "User-Agent: terraria-world-restore"
)

tmp_dir="$(mktemp -d)"
replacement=""
trap 'rm -rf -- "$tmp_dir"; [[ -z "${replacement:-}" ]] || rm -f -- "$replacement"' EXIT

release_tag_encoded="$(printf '%s' "$GITHUB_BACKUP_RELEASE_TAG" | jq -sRr @uri)"
release_json="$tmp_dir/release.json"

http_status="$(curl -sS -L \
  -o "$release_json" \
  -w '%{http_code}' \
  "${api_headers[@]}" \
  "$api_base/releases/tags/$release_tag_encoded")"

[[ "$http_status" == "200" ]] || die "Backup release '$GITHUB_BACKUP_RELEASE_TAG' was not found or is not accessible (HTTP $http_status)"

release_id="$(jq -er '.id' "$release_json")"
assets_json="$tmp_dir/assets.json"

http_status="$(curl -sS -L \
  -o "$assets_json" \
  -w '%{http_code}' \
  "${api_headers[@]}" \
  "$api_base/releases/$release_id/assets?per_page=100")"

[[ "$http_status" == "200" ]] || die "Could not list backup assets (HTTP $http_status)"

if [[ "$mode" == "list" ]]; then
  jq -r \
    --arg prefix "${BACKUP_FILE_PREFIX}-" \
    '[.[] | select(.name | startswith($prefix)) | select(.name | endswith(".wld"))]
     | sort_by(.created_at)
     | reverse
     | .[]
     | "\(.created_at)\t\(.name)\t\(.size) bytes"' \
    "$assets_json"
  exit 0
fi

if [[ "$mode" == "asset" ]]; then
  selected_asset="$(jq -c \
    --arg name "$requested_asset" \
    '[.[] | select(.name == $name)] | first // empty' \
    "$assets_json")"
else
  selected_asset="$(jq -c \
    --arg prefix "${BACKUP_FILE_PREFIX}-" \
    '[.[] | select(.name | startswith($prefix)) | select(.name | endswith(".wld"))]
     | sort_by(.created_at)
     | last // empty' \
    "$assets_json")"
fi

[[ -n "$selected_asset" ]] || die "No matching Terraria world backup asset was found"

asset_id="$(jq -r '.id' <<< "$selected_asset")"
asset_name="$(jq -r '.name' <<< "$selected_asset")"
asset_created_at="$(jq -r '.created_at' <<< "$selected_asset")"
asset_digest="$(jq -r '.digest // empty' <<< "$selected_asset")"

log "Selected backup: $asset_name ($asset_created_at)"

if (( assume_yes == 0 )); then
  [[ -t 0 ]] || die "Interactive confirmation is unavailable; rerun with --yes after stopping Terraria"
  printf 'Type RESTORE to replace %s with %s: ' "$TERRARIA_WORLD_PATH" "$asset_name"
  read -r confirmation
  [[ "$confirmation" == "RESTORE" ]] || die "Restore cancelled"
fi

if [[ -n "${TERRARIA_STOP_HOOK:-}" ]]; then
  [[ -x "$TERRARIA_STOP_HOOK" ]] || die "TERRARIA_STOP_HOOK is not executable: $TERRARIA_STOP_HOOK"
  log "Running Terraria stop hook."
  "$TERRARIA_STOP_HOOK"
else
  log "WARNING: no TERRARIA_STOP_HOOK is configured; ensure Terraria is stopped before continuing."
fi

downloaded_world="$tmp_dir/restored-world.wld"

curl -fsSL \
  -H "Accept: application/octet-stream" \
  -H "Authorization: Bearer $GITHUB_BACKUP_TOKEN" \
  -H "User-Agent: terraria-world-restore" \
  "$api_base/releases/assets/$asset_id" \
  -o "$downloaded_world"

[[ -s "$downloaded_world" ]] || die "Downloaded backup is empty"

downloaded_hash="$(sha256sum "$downloaded_world" | awk '{print $1}')"
if [[ "$asset_digest" == sha256:* ]]; then
  expected_hash="${asset_digest#sha256:}"
  [[ "$downloaded_hash" == "$expected_hash" ]] \
    || die "Downloaded backup hash does not match GitHub's asset digest"
fi

mkdir -p "$BACKUP_STATE_DIR"

if [[ -f "$TERRARIA_WORLD_PATH" ]]; then
  pre_restore_name="pre-restore-$(date -u +'%Y%m%dT%H%M%SZ').wld"
  cp --preserve=mode,ownership,timestamps \
    -- "$TERRARIA_WORLD_PATH" "$BACKUP_STATE_DIR/$pre_restore_name"
  log "Saved current local world as $BACKUP_STATE_DIR/$pre_restore_name"
fi

target_dir="$(dirname -- "$TERRARIA_WORLD_PATH")"
mkdir -p "$target_dir"
replacement="$(mktemp "$target_dir/.terraria-restore.XXXXXX")"
cp -- "$downloaded_world" "$replacement"

if [[ -e "$TERRARIA_WORLD_PATH" ]]; then
  chmod --reference="$TERRARIA_WORLD_PATH" "$replacement"
  chown --reference="$TERRARIA_WORLD_PATH" "$replacement" 2>/dev/null || true
else
  chmod 0644 "$replacement"
  chown --reference="$target_dir" "$replacement" 2>/dev/null || true
fi

mv -f -- "$replacement" "$TERRARIA_WORLD_PATH"
replacement=""
sync "$TERRARIA_WORLD_PATH" 2>/dev/null || sync

log "Restore complete: $asset_name -> $TERRARIA_WORLD_PATH"
log "Restored SHA-256: $downloaded_hash"
