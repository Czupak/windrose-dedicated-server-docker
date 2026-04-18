#!/usr/bin/env bash
set -euo pipefail

resolve_script_dir() {
    local src="${BASH_SOURCE[0]}"

    while [[ -h "$src" ]]; do
        local dir
        dir="$(cd -P -- "$(dirname -- "$src")" && pwd)"
        src="$(readlink "$src")"
        [[ "$src" != /* ]] && src="$dir/$src"
    done

    cd -P -- "$(dirname -- "$src")" && pwd
}

SCRIPT_DIR="$(resolve_script_dir)"
COMPOSE_DIR="${COMPOSE_DIR:-$SCRIPT_DIR}"
SERVICE_NAME="${SERVICE_NAME:-windrose}"
MODE="${WINDROSE_MODE:-auto}"
DOCKER_BIN="${DOCKER_BIN:-}"
SELF_NAME="${WINDROSE_CMD_NAME:-$(basename "$0")}"
DOCKER_CMD=()

# ANSI color codes
_COLOR_RESET='\033[0m'
_COLOR_CYAN='\033[0;36m'
_COLOR_GREEN='\033[0;32m'
_COLOR_YELLOW='\033[1;33m'
_COLOR_RED='\033[0;31m'

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

log_step() {
    echo -ne "${_COLOR_CYAN}[windrose]${_COLOR_RESET} $1..."
}

init_docker_cmd() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "[windrose] Error: docker is not installed or not in PATH."
        exit 1
    fi

    if [[ -n "$DOCKER_BIN" ]]; then
        read -r -a DOCKER_CMD <<< "$DOCKER_BIN"
        return
    fi

    if docker info >/dev/null 2>&1; then
        DOCKER_CMD=(docker)
    elif command -v sudo >/dev/null 2>&1; then
        DOCKER_CMD=(sudo docker)
    else
        echo "[windrose] Error: docker needs elevated permissions and sudo is not available."
        echo "[windrose] Try running with: DOCKER_BIN='sudo docker' ./$SELF_NAME status"
        exit 1
    fi
}

require_tools() {
    if [[ ! -f "$COMPOSE_DIR/docker-compose.yml" ]]; then
        echo "[windrose] Error: docker-compose.yml not found in $COMPOSE_DIR"
        exit 1
    fi
}

dotenv_value() {
    local key="$1"
    local env_file="$SCRIPT_DIR/.env"

    if [[ ! -f "$env_file" ]]; then
        return 1
    fi

    awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, "", $0); print $0}' "$env_file" | tail -n 1
}

detect_mode() {
    if [[ "$MODE" == "auto" ]]; then
        if [[ -f "$COMPOSE_DIR/docker-compose.dev.yml" && "${COMPOSE_DIR##*/}" == *dev* ]]; then
            echo "dev"
        else
            echo "prod"
        fi
    else
        echo "$MODE"
    fi
}

ACTIVE_MODE="$(detect_mode)"
COMPOSE_FILES=(-f docker-compose.yml)
if [[ "$ACTIVE_MODE" == "dev" && -f "$COMPOSE_DIR/docker-compose.dev.yml" ]]; then
    COMPOSE_FILES+=(-f docker-compose.dev.yml)
fi

dc() {
    (
        cd "$COMPOSE_DIR"
        "${DOCKER_CMD[@]}" compose "${COMPOSE_FILES[@]}" "$@"
    )
}

usage() {
    cat <<EOF
Windrose helper script

Usage:
  $SELF_NAME start
  $SELF_NAME stop
  $SELF_NAME restart
  $SELF_NAME status
  $SELF_NAME logs
  $SELF_NAME notify
  $SELF_NAME test-notify [message]
  $SELF_NAME backup
  $SELF_NAME install-backup-cron [schedule]
  $SELF_NAME pull
  $SELF_NAME update
  $SELF_NAME down
  $SELF_NAME install [target]

Notes:
  - compose directory: $COMPOSE_DIR
  - detected mode: $ACTIVE_MODE
  - docker permissions are auto-detected; set DOCKER_BIN manually only if needed
  - set WINDROSE_MODE=prod or WINDROSE_MODE=dev to override auto detection
  - backup archives default to ./backups with 7-day retention
EOF
}

start_server() {
    echo "[windrose] Starting server ($ACTIVE_MODE mode)..."
    dc up -d
    dc ps
}

stop_server() {
    echo "[windrose] Stopping server..."
    dc stop "$SERVICE_NAME"
}

restart_server() {
    echo "[windrose] Restarting server..."
    if ! dc restart "$SERVICE_NAME"; then
        dc stop "$SERVICE_NAME" || true
        dc up -d
    fi
    dc ps
}

status_server() {
    echo "[windrose] Service status ($ACTIVE_MODE mode):"
    dc ps
}

follow_logs() {
    echo "[windrose] Following logs..."
    dc logs -f "$SERVICE_NAME"
}

run_notifier() {
    echo "[windrose] Starting activity notifier..."
    exec "$SCRIPT_DIR/notify.sh"
}

test_notifier() {
    echo "[windrose] Sending test notification..."
    "$SCRIPT_DIR/notify.sh" test "${*:-⚓ Test notification from Windrose server}"
}

backup_server() {
    local was_running=""
    local backup_exit=0
    local notify_success notify_fail

    notify_success="${BACKUP_NOTIFY_SUCCESS:-$(dotenv_value BACKUP_NOTIFY_SUCCESS || true)}"
    notify_fail="${BACKUP_NOTIFY_FAIL:-$(dotenv_value BACKUP_NOTIFY_FAIL || true)}"
    notify_success="${notify_success:-false}"
    notify_fail="${notify_fail:-true}"
    local discord_upload
    discord_upload="${BACKUP_DISCORD_UPLOAD:-$(dotenv_value BACKUP_DISCORD_UPLOAD || true)}"
    discord_upload="${discord_upload:-false}"

    local backup_scope
    backup_scope="${BACKUP_SCOPE:-$(dotenv_value BACKUP_SCOPE || true)}"
    backup_scope="${backup_scope:-full}"

    local scope_label
    case "$backup_scope" in
        full) scope_label="full backup" ;;
        save) scope_label="save backup" ;;
        both) scope_label="full + save backup" ;;
        *)    scope_label="backup" ;;
    esac

    if dc ps --status running --services 2>/dev/null | grep -Fx "$SERVICE_NAME" >/dev/null 2>&1; then
        was_running="yes"
        log_step "Stopping server for a consistent $scope_label"
        if ! dc stop "$SERVICE_NAME" >/dev/null 2>&1; then
            echo -e " ${_COLOR_RED}FAILED${_COLOR_RESET}"
            log_error "Failed to stop container before backup."
            return 1
        fi
        echo -e " ${_COLOR_GREEN}DONE${_COLOR_RESET}"
    fi

    if [[ ! -f "$SCRIPT_DIR/backup.sh" ]]; then
        log_error "backup script not found at $SCRIPT_DIR/backup.sh"
        backup_exit=1
    elif bash "$SCRIPT_DIR/backup.sh"; then
        backup_exit=0
    else
        backup_exit=$?
    fi

    if [[ -n "$was_running" ]]; then
        log_step "Starting server again"
        if ! dc up -d >/dev/null 2>&1; then
            echo -e " ${_COLOR_RED}FAILED${_COLOR_RESET}"
            log_error "Failed to start container after backup."
            backup_exit=1
        else
            echo -e " ${_COLOR_GREEN}DONE${_COLOR_RESET}"
        fi
    fi

    if [[ "$backup_exit" -eq 0 && "$notify_success" == "true" ]]; then
        "$SCRIPT_DIR/notify.sh" test "⚓ Windrose backup finished successfully on $(hostname -s)." >/dev/null 2>&1 || true
    fi

    if [[ "$backup_exit" -eq 0 && "$discord_upload" == "true" ]]; then
        upload_backup_to_discord || true
    fi

    if [[ "$backup_exit" -ne 0 && "$notify_fail" == "true" ]]; then
        "$SCRIPT_DIR/notify.sh" test "⚓ Windrose backup failed on $(hostname -s) (exit=$backup_exit)." >/dev/null 2>&1 || true
    fi

    return "$backup_exit"
}

upload_backup_to_discord() {
    local discord_url backup_dir latest_file file_size http_code backup_scope

    discord_url="${DISCORD_WEBHOOK_URL:-$(dotenv_value DISCORD_WEBHOOK_URL || true)}"
    if [[ -z "$discord_url" ]]; then
        log_warn "DISCORD_WEBHOOK_URL not set, skipping Discord upload."
        return 0
    fi

    backup_dir="${BACKUP_DIR:-$(dotenv_value BACKUP_DIR || true)}"
    backup_dir="${backup_dir:-$SCRIPT_DIR/backups}"

    backup_scope="${BACKUP_SCOPE:-$(dotenv_value BACKUP_SCOPE || true)}"
    backup_scope="${backup_scope:-full}"

    if [[ "$backup_scope" == "full" ]]; then
        log_info "BACKUP_SCOPE=full, skipping Discord upload (only save backups are uploaded)."
        return 0
    fi

    if [[ "$backup_scope" != "save" && "$backup_scope" != "both" ]]; then
        log_warn "unsupported BACKUP_SCOPE '$backup_scope', skipping Discord upload."
        return 0
    fi

    latest_file="$(find "$backup_dir" -maxdepth 1 -type f \( -name 'windrose-backup-save-*.tar.gz' -o -name 'windrose-backup-save-*.zip' \) -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)"
    if [[ -z "$latest_file" ]]; then
        log_warn "no save backup file found for Discord upload."
        return 0
    fi

    file_size="$(stat -c '%s' "$latest_file" 2>/dev/null || echo 0)"
    local max_discord_size=$(( 25 * 1024 * 1024 ))
    if [[ "$file_size" -gt "$max_discord_size" ]]; then
        log_warn "backup exceeds Discord 25 MB limit ($(( file_size / 1024 / 1024 )) MB), skipping upload."
        return 0
    fi

    log_step "Uploading $(basename "$latest_file") to Discord ($(( file_size / 1024 )) KB)"
    http_code="$(curl -s -o /dev/null -w "%{http_code}" \
        -F "file=@$latest_file" \
        -F "payload_json={\"content\":\"⚓ Backup \`$(basename "$latest_file")\` — $(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
        "$discord_url")"

    if [[ "$http_code" =~ ^2 ]]; then
        echo -e " ${_COLOR_GREEN}DONE${_COLOR_RESET}"
    else
        echo -e " ${_COLOR_RED}FAILED (HTTP $http_code)${_COLOR_RESET}"
    fi
}

install_backup_cron() {
    local schedule="${1:-0 */6 * * *}"
    local backup_cmd="$SCRIPT_DIR/windrose backup"
    local backup_log_dir="$SCRIPT_DIR/backups"
    local backup_log_file="$backup_log_dir/backup.log"
    local cron_tag="# windrose-backup-job"
    local cron_cmd
    local existing_cron filtered_cron
    local had_legacy_entry=""

    if [[ ! -x "$SCRIPT_DIR/windrose" ]]; then
        backup_cmd="$SCRIPT_DIR/serverctl.sh backup"
    fi

    mkdir -p "$backup_log_dir"

    cron_cmd="echo \"[\$(date -Ins)] backup job started\"; if $backup_cmd; then echo \"[\$(date -Ins)] backup job finished successfully\"; else rc=\$?; echo \"[\$(date -Ins)] backup job failed (exit=\$rc)\"; exit \$rc; fi"
    local cron_line="$schedule /bin/bash -lc '$cron_cmd' >> $backup_log_file 2>&1 $cron_tag"

    if ! command -v crontab >/dev/null 2>&1; then
        echo "[windrose] Error: crontab is not available on this host."
        exit 1
    fi

    existing_cron="$(crontab -l 2>/dev/null || true)"

    if printf '%s\n' "$existing_cron" | grep -E "($SCRIPT_DIR/backup\.sh|$SCRIPT_DIR/windrose backup|$SCRIPT_DIR/serverctl\.sh backup|backup job started|windrose-backup-job)" >/dev/null 2>&1; then
        had_legacy_entry="yes"
    fi

    filtered_cron="$(printf '%s\n' "$existing_cron" | grep -Ev "($SCRIPT_DIR/backup\.sh|$SCRIPT_DIR/windrose backup|$SCRIPT_DIR/serverctl\.sh backup|backup job started|windrose-backup-job)" || true)"

    {
        if [[ -n "$filtered_cron" ]]; then
            printf '%s\n' "$filtered_cron"
        fi
        echo "$cron_line"
    } | crontab -

    if [[ -n "$had_legacy_entry" ]]; then
        echo "[windrose] Updated legacy backup cron to use windrose backup:"
    else
        echo "[windrose] Installed backup cron:"
    fi
    echo "$cron_line"
}

pull_image() {
    echo "[windrose] Pulling image defined in compose..."
    dc pull
}

update_server() {
    echo "[windrose] Pulling the selected image tag and recreating the container..."
    dc pull
    dc up -d
    dc ps
}

down_server() {
    echo "[windrose] Stopping and removing the stack..."
    dc down
}

install_self() {
    local target="${1:-/usr/local/bin/windrosectl}"
    local target_dir
    target_dir="$(dirname "$target")"

    mkdir -p "$target_dir"
    cat > "$target" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$SCRIPT_DIR/windrose" "\$@"
EOF
    chmod +x "$target"
    echo "[windrose] Installed launcher at $target"
}

init_docker_cmd
require_tools

case "${1:-help}" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        restart_server
        ;;
    status|ps)
        status_server
        ;;
    logs)
        follow_logs
        ;;
    notify)
        run_notifier
        ;;
    test-notify)
        shift || true
        test_notifier "$@"
        ;;
    backup)
        backup_server
        ;;
    install-backup-cron)
        install_backup_cron "${2:-}"
        ;;
    pull)
        pull_image
        ;;
    update)
        update_server
        ;;
    down)
        down_server
        ;;
    install)
        install_self "${2:-}"
        ;;
    help|-h|--help|"")
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
