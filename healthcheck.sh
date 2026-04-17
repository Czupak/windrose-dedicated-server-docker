#!/usr/bin/env bash
set -euo pipefail

SERVERDIR=${SERVERDIR:-/data}
PORT=${PORT:-7777}
QUERYPORT=${QUERYPORT:-7778}
HEALTHCHECK_REQUIRE_UDP=${HEALTHCHECK_REQUIRE_UDP:-false}
HEALTHCHECK_FAIL_ON_LOG_PATTERNS=${HEALTHCHECK_FAIL_ON_LOG_PATTERNS:-true}
HEALTHCHECK_LOG_SCAN_LINES=${HEALTHCHECK_LOG_SCAN_LINES:-120}
HEALTHCHECK_LOG_FILE=${HEALTHCHECK_LOG_FILE:-$SERVERDIR/R5/Saved/Logs/R5.log}
HEALTHCHECK_FAIL_PATTERNS=${HEALTHCHECK_FAIL_PATTERNS:-Cannot resolve addresses for host|GsStream .* broken|GcStream is broken|Server Authorization failed|Login finished with error|kernel32\.dll, status c0000135}
SERVER_DESC="$SERVERDIR/R5/ServerDescription.json"

log() {
  echo "[healthcheck] $*"
}

check_udp_port() {
  local port_hex
  port_hex="$(printf '%04X' "$1")"

  awk -v target=":$port_hex" '
    NR > 1 {
      local_addr = toupper($2)
      if (substr(local_addr, length(local_addr) - 4) == target) {
        found = 1
      }
    }
    END {
      exit(found ? 0 : 1)
    }
  ' /proc/net/udp /proc/net/udp6
}

check_recent_log_failures() {
  [[ -f "$HEALTHCHECK_LOG_FILE" ]] || return 0

  local match
  match="$(tail -n "$HEALTHCHECK_LOG_SCAN_LINES" "$HEALTHCHECK_LOG_FILE" | grep -Ein "$HEALTHCHECK_FAIL_PATTERNS" | tail -n 1 || true)"

  if [[ -n "$match" ]]; then
    log "fatal runtime pattern found in recent log: $match"
    return 1
  fi

  return 0
}

if ! pgrep -f 'WindroseServer-Win64-Shipping.exe' >/dev/null 2>&1; then
  log "server process not found"
  exit 1
fi

if [[ ! -d "$SERVERDIR/R5" ]]; then
  log "server data directory missing at $SERVERDIR/R5"
  exit 1
fi

if [[ "$HEALTHCHECK_REQUIRE_UDP" == "true" ]]; then
  if ! check_udp_port "$PORT" && ! check_udp_port "$QUERYPORT"; then
    log "neither UDP port $PORT nor $QUERYPORT is listening yet"
    exit 1
  fi
fi

if [[ "$HEALTHCHECK_FAIL_ON_LOG_PATTERNS" == "true" ]]; then
  if ! check_recent_log_failures; then
    exit 1
  fi
fi

if [[ -f "$SERVER_DESC" ]]; then
  if ! jq -e '.ServerDescription_Persistent' "$SERVER_DESC" >/dev/null 2>&1; then
    log "ServerDescription.json exists but is not valid JSON"
    exit 1
  fi
else
  log "ServerDescription.json not generated yet"
fi

log "ok"
