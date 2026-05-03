#!/usr/bin/env bash

run_as_steam() {
  HOME="$STEAM_HOME" \
    XDG_DATA_HOME="$STEAM_HOME/.local/share" \
    XDG_CONFIG_HOME="$STEAM_HOME/.config" \
    XDG_CACHE_HOME="$STEAM_HOME/.cache" \
    DISPLAY="${DISPLAY:-:99}" \
    WINEPREFIX="$WINEPREFIX" \
    WINEARCH="$WINEARCH" \
    WINEDLLOVERRIDES="$WINEDLLOVERRIDES" \
    su -m -s /bin/bash steam -c "$*"
}

run_wine_as_steam() {
  run_as_steam "xvfb-run --auto-servernum --server-args='-screen 0 1024x768x16 -nolisten tcp' bash -lc $(quote "$*")"
}

wine_prefix_ready() {
  [[ -f "$WINEPREFIX/system.reg" && -f "$WINEPREFIX/drive_c/windows/system32/kernel32.dll" ]] || return 1
  grep -q '^#arch=win64' "$WINEPREFIX/system.reg" || return 1
}

init_wine() {
  mkdir -p "$WINEPREFIX"
  chown -R steam:steam "$STEAM_HOME" 2>/dev/null || true

  if wine_prefix_ready; then
    log_ok "Wine prefix already initialized and ready"
    return
  fi

  for attempt in 1 2; do
    if [[ "$attempt" -eq 1 ]]; then
      log_info "Initializing Wine prefix (attempt $attempt/2)"
    else
      log_warn "Wine prefix incomplete, rebuilding it (attempt $attempt/2)"
      log_info "Removing old prefix: $WINEPREFIX"
      rm -rf "$WINEPREFIX"
      mkdir -p "$WINEPREFIX"
      chown -R steam:steam "$STEAM_HOME" 2>/dev/null || true
    fi

    log_info "Starting wineboot init (will timeout after 120s)..."
    local start_time=$SECONDS
    run_wine_as_steam "timeout 120 bash -c 'winecfg -v win10 >/tmp/windrose-wineboot.log 2>&1 || true; wineboot --init >>/tmp/windrose-wineboot.log 2>&1 || true; wineserver -w >/dev/null 2>&1 || true'" || true
    local elapsed=$((SECONDS - start_time))
    log_ok "wineboot completed in ${elapsed}s"

    if grep -q 'socket.*Function not implemented' /tmp/windrose-wineboot.log 2>/dev/null; then
      log_error "Wine prefix initialization failed: wineboot detected 'socket: Function not implemented'"
      log_error "Host kernel or seccomp profile is blocking socket family AF_ALG (38)."
      log_error "See TROUBLESHOOTING.md section 'Wine prefix fails in restricted environments (seccomp)' for fixes."
      exit 1
    fi

    log_info "Checking if Wine prefix is ready..."
    if wine_prefix_ready; then
      log_ok "Wine prefix ready and functional"
      return
    fi

    dump_wine_diagnostics
    log_warn "Wine prefix check failed, continuing to next attempt..."
  done

  log_error "Wine prefix initialization failed after 2 attempts"
  dump_wine_diagnostics
  print_log_file "Recent Wine boot log:" "/tmp/windrose-wineboot.log"
  exit 1
}

rebuild_wine_prefix() {
  log "Rebuilding Wine prefix at $WINEPREFIX"
  rm -rf "$WINEPREFIX"
  mkdir -p "$WINEPREFIX"
  chown -R steam:steam "$STEAM_HOME" 2>/dev/null || true
  init_wine
}
