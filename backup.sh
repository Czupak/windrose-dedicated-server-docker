#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

dotenv_value() {
  local key="$1"

  if [[ ! -f "$ENV_FILE" ]]; then
    return 1
  fi

  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, "", $0); print $0}' "$ENV_FILE" | tail -n 1
}

DATA_DIR="${DATA_DIR:-$SCRIPT_DIR/data}"
BACKUP_DIR="${BACKUP_DIR:-$(dotenv_value BACKUP_DIR || true)}"
BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-$(dotenv_value BACKUP_RETENTION_DAYS || true)}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP="$(date +%F-%H%M%S)"
ARCHIVE_PATH="$BACKUP_DIR/windrose-backup-$TIMESTAMP.tar.gz"

log() {
  echo "[windrose] $*"
}

if [[ ! -d "$DATA_DIR/R5" ]]; then
  log "Error: expected data directory not found at $DATA_DIR/R5"
  exit 1
fi

mkdir -p "$BACKUP_DIR"

log "Creating backup at $ARCHIVE_PATH"
tar -czf "$ARCHIVE_PATH" -C "$DATA_DIR" R5

if [[ "$BACKUP_RETENTION_DAYS" =~ ^[0-9]+$ ]] && [[ "$BACKUP_RETENTION_DAYS" -gt 0 ]]; then
  find "$BACKUP_DIR" -maxdepth 1 -type f -name 'windrose-backup-*.tar.gz' -mtime +"$BACKUP_RETENTION_DAYS" -print -delete || true
fi

log "Backup complete: $ARCHIVE_PATH"
