#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
SELF_NAME="${WINDROSE_CMD_NAME:-$(basename "$0")}"

# ANSI color policy: disable colors when NO_COLOR is set or stdout is not a TTY.
if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
  _COLOR_RESET=''
  _COLOR_CYAN=''
  _COLOR_GREEN=''
  _COLOR_YELLOW=''
  _COLOR_RED=''
else
  _COLOR_RESET='\033[0m'
  _COLOR_CYAN='\033[0;36m'
  _COLOR_GREEN='\033[0;32m'
  _COLOR_YELLOW='\033[1;33m'
  _COLOR_RED='\033[0;31m'
fi

log_info() {
  echo -e "${_COLOR_CYAN}[windrose]${_COLOR_RESET} $*"
}

log_ok() {
  echo -e "${_COLOR_GREEN}[windrose]${_COLOR_RESET} $*"
}

log_warn() {
  echo -e "${_COLOR_YELLOW}[windrose]${_COLOR_RESET} $*"
}

log_error() {
  echo -e "${_COLOR_RED}[windrose]${_COLOR_RESET} $*"
}

log_skip() {
  echo -e "${_COLOR_YELLOW}[windrose]${_COLOR_RESET} [SKIP] $*"
}

prompt_text() {
  printf '%b' "${_COLOR_YELLOW}[windrose]${_COLOR_RESET} $1"
}

prompt_confirm_default_no() {
  local question="$1"
  local answer

  if [[ ! -t 0 || ! -t 1 ]]; then
    log_skip "Non-interactive shell detected; defaulting to No: $question"
    return 1
  fi

  read -r -p "$(prompt_text "$question ${_COLOR_YELLOW}[y/N]${_COLOR_RESET}: ")" answer
  case "${answer,,}" in
  y | yes)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

fatal_exit() {
  local message="$1"
  local next_step="${2:-Review the error above and rerun ./$SELF_NAME after fixing the configuration.}"

  log_error "$message"
  log_info "Next step: $next_step"
  exit 1
}

log_step() {
  echo -ne "${_COLOR_CYAN}[windrose]${_COLOR_RESET} $1..."
}

screen_title() {
  printf '\n%s\n' "== $1 =="
}

screen_section() {
  printf '\n%s\n' "[$1]"
}

screen_kv() {
  printf '  %-18s %s\n' "$1" "$2"
}

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
if [[ "$BACKUP_DIR" != /* ]]; then
  BACKUP_DIR="$SCRIPT_DIR/$BACKUP_DIR"
fi
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-$(dotenv_value BACKUP_RETENTION_DAYS || true)}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
BACKUP_FORMAT="${BACKUP_FORMAT:-$(dotenv_value BACKUP_FORMAT || true)}"
BACKUP_FORMAT="${BACKUP_FORMAT:-tar.gz}"
BACKUP_SCOPE="${BACKUP_SCOPE:-$(dotenv_value BACKUP_SCOPE || true)}"
BACKUP_SCOPE="${BACKUP_SCOPE:-full}"
TIMESTAMP="$(date +%F-%H%M%S)"
declare -a CREATED_BACKUPS=()

case "$BACKUP_FORMAT" in
tar.gz)
  ARCHIVE_EXT="tar.gz"
  ;;
zip)
  ARCHIVE_EXT="zip"
  ;;
*)
  fatal_exit "unsupported BACKUP_FORMAT '$BACKUP_FORMAT' (supported: tar.gz, zip)" "Set BACKUP_FORMAT to tar.gz or zip in .env, then rerun ./$SELF_NAME."
  ;;
esac

case "$BACKUP_SCOPE" in
full | save | both) ;;
*)
  fatal_exit "unsupported BACKUP_SCOPE '$BACKUP_SCOPE' (supported: full, save, both)" "Set BACKUP_SCOPE to full, save, or both in .env, then rerun ./$SELF_NAME."
  ;;
esac

run_quiet() {
  "$@" >/dev/null 2>&1
}

install_zip_package() {
  if command -v apt-get >/dev/null 2>&1; then
    if [[ "$EUID" -eq 0 ]]; then
      run_quiet apt-get install -y zip
    elif command -v sudo >/dev/null 2>&1; then
      run_quiet sudo apt-get install -y zip
    else
      log_error "need root privileges to install zip (sudo not available)."
      return 1
    fi
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    if [[ "$EUID" -eq 0 ]]; then
      run_quiet dnf install -y zip
    elif command -v sudo >/dev/null 2>&1; then
      run_quiet sudo dnf install -y zip
    else
      log_error "need root privileges to install zip (sudo not available)."
      return 1
    fi
    return 0
  fi

  if command -v yum >/dev/null 2>&1; then
    if [[ "$EUID" -eq 0 ]]; then
      run_quiet yum install -y zip
    elif command -v sudo >/dev/null 2>&1; then
      run_quiet sudo yum install -y zip
    else
      log_error "need root privileges to install zip (sudo not available)."
      return 1
    fi
    return 0
  fi

  if command -v apk >/dev/null 2>&1; then
    if [[ "$EUID" -eq 0 ]]; then
      run_quiet apk add --no-cache zip
    elif command -v sudo >/dev/null 2>&1; then
      run_quiet sudo apk add --no-cache zip
    else
      log_error "need root privileges to install zip (sudo not available)."
      return 1
    fi
    return 0
  fi

  if command -v pacman >/dev/null 2>&1; then
    if [[ "$EUID" -eq 0 ]]; then
      run_quiet pacman -Sy --noconfirm zip
    elif command -v sudo >/dev/null 2>&1; then
      run_quiet sudo pacman -Sy --noconfirm zip
    else
      log_error "need root privileges to install zip (sudo not available)."
      return 1
    fi
    return 0
  fi

  log_error "unsupported package manager. Install zip manually."
  return 1
}

ensure_zip_available() {
  if command -v zip >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -t 0 || ! -t 1 ]]; then
    log_skip "Non-interactive shell detected; defaulting to No: zip command not found. Install it now?"
    log_info "Next step: install zip package manually, or set BACKUP_FORMAT=tar.gz and rerun ./$SELF_NAME."
    return 1
  fi

  if prompt_confirm_default_no "zip command not found. Install it now?"; then
    log_info "Installing zip package..."
    if ! install_zip_package; then
      log_error "failed to install zip package."
      log_info "Next step: install zip manually or set BACKUP_FORMAT=tar.gz, then rerun ./$SELF_NAME."
      return 1
    fi
    if ! command -v zip >/dev/null 2>&1; then
      log_error "zip command still not available after installation."
      log_info "Next step: verify zip is on PATH or set BACKUP_FORMAT=tar.gz, then rerun ./$SELF_NAME."
      return 1
    fi
    log_ok "zip package installed successfully."
  else
    log_error "zip is required for BACKUP_FORMAT=zip. Install zip or set BACKUP_FORMAT=tar.gz"
    log_info "Next step: install zip or set BACKUP_FORMAT=tar.gz in .env, then rerun ./$SELF_NAME."
    return 1
  fi
}

if [[ ! -d "$DATA_DIR/R5" ]]; then
  fatal_exit "expected data directory not found at $DATA_DIR/R5" "Verify DATA_DIR points to your Windrose data path, then rerun ./$SELF_NAME."
fi

if [[ "$BACKUP_SCOPE" == "save" || "$BACKUP_SCOPE" == "both" ]]; then
  if [[ ! -d "$DATA_DIR/R5/Saved" ]]; then
    fatal_exit "expected save directory not found at $DATA_DIR/R5/Saved" "Verify DATA_DIR and BACKUP_SCOPE, then rerun ./$SELF_NAME."
  fi
fi

mkdir -p "$BACKUP_DIR"
BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd)"

screen_title "Windrose Backup"
screen_section "Configuration"
screen_kv "scope:" "$BACKUP_SCOPE"
screen_kv "format:" "$BACKUP_FORMAT"
screen_kv "source:" "$DATA_DIR"
screen_kv "output dir:" "$BACKUP_DIR"
screen_kv "retention:" "${BACKUP_RETENTION_DAYS} days"

create_archive() {
  local label="$1"
  local archive_path="$2"
  shift 2

  screen_section "Backup: $label"

  log_step "Create archive"
  if [[ "$BACKUP_FORMAT" == "zip" ]]; then
    if ! (
      cd "$DATA_DIR"
      zip -qr "$archive_path" "$@" >/dev/null 2>&1
    ); then
      echo -e " ${_COLOR_RED}FAIL${_COLOR_RESET}"
      log_error "Failed to create backup archive: $archive_path"
      return 1
    fi
  else
    if ! tar -czf "$archive_path" -C "$DATA_DIR" "$@" >/dev/null 2>&1; then
      echo -e " ${_COLOR_RED}FAIL${_COLOR_RESET}"
      log_error "Failed to create backup archive: $archive_path"
      return 1
    fi
  fi
  echo -e " ${_COLOR_GREEN}OK${_COLOR_RESET}"
  screen_kv "archive:" "$(basename "$archive_path")"

  log_step "Verify archive integrity"
  if [[ "$BACKUP_FORMAT" == "zip" ]]; then
    if ! zip -T "$archive_path" >/dev/null 2>&1; then
      echo -e " ${_COLOR_RED}FAIL${_COLOR_RESET}"
      log_error "Backup integrity verification failed: $archive_path"
      return 1
    fi
  else
    if ! tar -tzf "$archive_path" >/dev/null 2>&1; then
      echo -e " ${_COLOR_RED}FAIL${_COLOR_RESET}"
      log_error "Backup integrity verification failed: $archive_path"
      return 1
    fi
  fi
  echo -e " ${_COLOR_GREEN}OK${_COLOR_RESET}"

  CREATED_BACKUPS+=("$archive_path")
}

if [[ "$BACKUP_FORMAT" == "zip" ]]; then
  ensure_zip_available || exit 1
fi

if [[ "$BACKUP_SCOPE" == "full" || "$BACKUP_SCOPE" == "both" ]]; then
  create_archive "full" "$BACKUP_DIR/windrose-backup-full-$TIMESTAMP.$ARCHIVE_EXT" R5
fi

if [[ "$BACKUP_SCOPE" == "save" || "$BACKUP_SCOPE" == "both" ]]; then
  save_items=(R5/Saved)
  if [[ -f "$DATA_DIR/R5/ServerDescription.json" ]]; then
    save_items+=(R5/ServerDescription.json)
  fi
  create_archive "save" "$BACKUP_DIR/windrose-backup-save-$TIMESTAMP.$ARCHIVE_EXT" "${save_items[@]}"
fi

if [[ "$BACKUP_RETENTION_DAYS" =~ ^[0-9]+$ ]] && [[ "$BACKUP_RETENTION_DAYS" -gt 0 ]]; then
  find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'windrose-backup-*.tar.gz' -o -name 'windrose-backup-*.zip' \) -mtime +"$BACKUP_RETENTION_DAYS" -delete >/dev/null 2>&1 || true
fi

screen_section "Summary"
screen_kv "created:" "${#CREATED_BACKUPS[@]}"
if [[ "${#CREATED_BACKUPS[@]}" -gt 0 ]]; then
  for created_backup in "${CREATED_BACKUPS[@]}"; do
    screen_kv "archive:" "$(basename "$created_backup")"
  done
fi
log_ok "Backup completed."
