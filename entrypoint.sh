#!/usr/bin/env bash
set -euo pipefail

APPID=${WINDROSE_APP_ID:-4129620}
SERVERDIR=${SERVERDIR:-/data}
STEAM_HOME=${STEAM_HOME:-/home/steam}
WINEPREFIX=${WINEPREFIX:-$STEAM_HOME/.wine}
STEAM_LOGIN=${STEAM_LOGIN:-anonymous}
STEAM_PASS=${STEAM_PASS:-}
UPDATE_ON_START=${UPDATE_ON_START:-true}
GENERATE_SETTINGS=${GENERATE_SETTINGS:-true}
PUID=${PUID:-1000}
PGID=${PGID:-1000}

PORT=${PORT:-7777}
QUERYPORT=${QUERYPORT:-7778}
MULTIHOME=${MULTIHOME:-0.0.0.0}
INVITE_CODE=${INVITE_CODE:-}
SERVER_NAME=${SERVER_NAME:-}
SERVER_NOTE=${SERVER_NOTE:-}
SERVER_PASSWORD=${SERVER_PASSWORD:-}
MAX_PLAYERS=${MAX_PLAYERS:-4}
P2P_PROXY_ADDRESS=${P2P_PROXY_ADDRESS:-127.0.0.1}
FIRST_RUN_TIMEOUT=${FIRST_RUN_TIMEOUT:-120}

SERVER_PID=""
XVFB_PID=""
SERVER_DESC="$SERVERDIR/R5/ServerDescription.json"

log() {
  echo "[windrose] $*"
}

quote() {
  printf '%q' "$1"
}

run_as_steam() {
  su -s /bin/bash steam -c "$*"
}

ensure_user_mapping() {
  groupmod -o -g "$PGID" steam 2>/dev/null || true
  usermod -o -u "$PUID" steam 2>/dev/null || true

  mkdir -p "$SERVERDIR" "$STEAM_HOME"
  chown -R steam:steam /opt/steamcmd "$STEAM_HOME" "$SERVERDIR" 2>/dev/null || true
}

cleanup_xvfb() {
  if [ -n "$XVFB_PID" ] && kill -0 "$XVFB_PID" 2>/dev/null; then
    kill "$XVFB_PID" 2>/dev/null || true
  fi
}

shutdown_server() {
  log "Stopping Windrose dedicated server"
  pkill -TERM -u steam -f 'WindroseServer-Win64-Shipping.exe' 2>/dev/null || true
  pkill -TERM -u steam -f 'wineserver' 2>/dev/null || true

  for _ in $(seq 1 30); do
    if ! pgrep -u steam -f 'WindroseServer-Win64-Shipping.exe|wineserver' >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  pkill -KILL -u steam -f 'WindroseServer-Win64-Shipping.exe|wineserver' 2>/dev/null || true
}

trap 'shutdown_server; exit 0' TERM INT
trap 'cleanup_xvfb' EXIT

init_xvfb() {
  rm -f /tmp/.X99-lock || true
  Xvfb :99 -screen 0 1024x768x16 -nolisten tcp >/dev/null 2>&1 &
  XVFB_PID=$!
}

init_wine() {
  mkdir -p "$WINEPREFIX"
  chown -R steam:steam "$STEAM_HOME" 2>/dev/null || true

  if [ ! -f "$WINEPREFIX/system.reg" ]; then
    log "Initializing Wine prefix"
    run_as_steam "WINEPREFIX=$(quote "$WINEPREFIX") wineboot -i >/dev/null 2>&1 || true"
  fi
}

update_server() {
  if [ "$UPDATE_ON_START" != "true" ]; then
    log "UPDATE_ON_START=false, skipping SteamCMD update"
    return
  fi

  local login_cmd
  if [ "$STEAM_LOGIN" = "anonymous" ]; then
    login_cmd='+login anonymous'
  elif [ -n "$STEAM_PASS" ]; then
    login_cmd="+login $(quote "$STEAM_LOGIN") $(quote "$STEAM_PASS")"
  else
    login_cmd="+login $(quote "$STEAM_LOGIN")"
  fi

  log "Updating or validating server files"
  run_as_steam "mkdir -p $(quote "$SERVERDIR") && /opt/steamcmd/steamcmd.sh +force_install_dir $(quote "$SERVERDIR") $login_cmd +app_update $(quote "$APPID") validate +quit"
}

find_server_exe() {
  find "$SERVERDIR" -iname 'WindroseServer-Win64-Shipping.exe' | head -n 1 || true
}

first_run_generate_config() {
  local exe="$1"

  if [ "$GENERATE_SETTINGS" != "true" ] || [ -f "$SERVER_DESC" ]; then
    return
  fi

  log "First run detected, generating default server config"
  run_as_steam "WINEPREFIX=$(quote "$WINEPREFIX") wine $(quote "$exe") -log -MULTIHOME=$(quote "$MULTIHOME") -PORT=$(quote "$PORT") -QUERYPORT=$(quote "$QUERYPORT") >/tmp/windrose-first-run.log 2>&1" &
  local warmup_pid=$!

  local count=0
  while [ ! -f "$SERVER_DESC" ] && [ "$count" -lt "$FIRST_RUN_TIMEOUT" ]; do
    sleep 1
    count=$((count + 1))
  done

  kill "$warmup_pid" 2>/dev/null || true
  wait "$warmup_pid" 2>/dev/null || true
  pkill -TERM -u steam -f 'wineserver' 2>/dev/null || true

  if [ ! -f "$SERVER_DESC" ]; then
    log "ServerDescription.json was not generated during first run"
  fi
}

patch_server_config() {
  if [ "$GENERATE_SETTINGS" != "true" ]; then
    log "GENERATE_SETTINGS=false, skipping JSON patching"
    return
  fi

  if [ ! -f "$SERVER_DESC" ]; then
    log "ServerDescription.json not found, skipping patch"
    return
  fi

  log "Patching ServerDescription.json from environment"
  tr -d '\r' < "$SERVER_DESC" | jq \
    --arg invite "$INVITE_CODE" \
    --arg name "$SERVER_NAME" \
    --arg note "$SERVER_NOTE" \
    --arg password "$SERVER_PASSWORD" \
    --arg proxy "$P2P_PROXY_ADDRESS" \
    --argjson maxplayers "$MAX_PLAYERS" \
    '
    .ServerDescription_Persistent.P2pProxyAddress = $proxy |
    if $invite != "" then .ServerDescription_Persistent.InviteCode = $invite else . end |
    if $name != "" then .ServerDescription_Persistent.ServerName = $name else . end |
    if $note != "" then .ServerDescription_Persistent.Note = $note else . end |
    if $password != "" then
      .ServerDescription_Persistent.IsPasswordProtected = true |
      .ServerDescription_Persistent.Password = $password
    else
      .ServerDescription_Persistent.IsPasswordProtected = false |
      .ServerDescription_Persistent.Password = ""
    end |
    .ServerDescription_Persistent.MaxPlayerCount = $maxplayers
    ' > "$SERVER_DESC.tmp"

  mv "$SERVER_DESC.tmp" "$SERVER_DESC"
  chown steam:steam "$SERVER_DESC" 2>/dev/null || true
}

start_server() {
  local exe="$1"

  log "Starting Windrose dedicated server"
  log "Executable: $exe"

  run_as_steam "WINEPREFIX=$(quote "$WINEPREFIX") wine $(quote "$exe") -log -MULTIHOME=$(quote "$MULTIHOME") -PORT=$(quote "$PORT") -QUERYPORT=$(quote "$QUERYPORT")" &
  SERVER_PID=$!
  wait "$SERVER_PID"
}

ensure_user_mapping
init_xvfb
init_wine
update_server

SERVER_EXE=$(find_server_exe)
if [ -z "$SERVER_EXE" ]; then
  log "ERROR: Windrose server executable not found"
  find "$SERVERDIR" -maxdepth 4 || true
  exit 1
fi

first_run_generate_config "$SERVER_EXE"
patch_server_config
start_server "$SERVER_EXE"
