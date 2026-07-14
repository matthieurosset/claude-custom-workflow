#!/usr/bin/env bash
# mg-emu.sh — generalized Android-emulator orchestration for THIS machine's pool.
# Boot 1, 2 or 3 emulators, any phone/tablet mix, on the shared 3-port pool —
# safely (flock per port, session-aware lease keepalive), so parallel agents
# never steal each other's port and emulators don't die on their own.
#
# This SUPERSEDES the old single-purpose scripts/dev/mg-trio.sh. The "3 emulators"
# case is just `mg_emu_up phone tablet7 tablet10` — one use case among many.
#
# ── WHY a layer on top of emulator-pool.sh ───────────────────────────────────
#   emulator-pool.sh = low-level: atomic claim of ONE of ports 5554/5556/5558,
#   held by a keeper for the session. mg-emu.sh = orchestration: claim N ports,
#   boot the AVDs you ask for, keep their leases fresh (mg_keepalive_start — vital
#   when you DON'T run `flutter run`, e.g. build-APK + `am start` + logcat), and
#   give you swap / scrcpy / health / teardown across all of them.
#
# ── USAGE ────────────────────────────────────────────────────────────────────
#   source .claude/skills/shared/mg-emu.sh
#   mg_emu_up phone                      # 1 emulator
#   mg_emu_up phone tablet7              # 2 emulators
#   mg_emu_up phone tablet7 tablet10     # 3 (the former "trio")
#   mg_emu_up phone phone phone          # 3 phones
#   mg_emu_list                          # port <-> AVD this session holds
#   mg_emu_swap <port> <kind>            # switch the AVD on a held port (phone<->tablet)
#   mg_emu_scrcpy on|off [port]          # mirror to the user's display (:1)
#   mg_emu_health                        # per-port: state / boot / foreground
#   mg_emu_down                          # release everything this session holds
#
#   # mission-geo app convenience (this is the mission-geo repo):
#   mg_emu_install [apk]                 # install dev-debug APK on all held ports
#   mg_emu_app                           # settle GMS, launch app, verify foreground
#
# AVD kinds: phone | tablet7 | tablet10  → mission_geo_phone / _tablet7 / _tablet10
#            (a full AVD name also works). Each Bash tool call is a fresh shell,
#            so re-`source` this file in every call. State is keyed by the owning
#            claude session, so it survives across calls.

MG_EMU_ROOT="$(git -C "${BASH_SOURCE%/*}" rev-parse --show-toplevel 2>/dev/null || echo /home/mrjack/git/mission-geo)"
MG_EMU_POOL="$MG_EMU_ROOT/.claude/skills/shared/emulator-pool.sh"
MG_ADB="${MG_ADB:-/usr/bin/adb}"
MG_EMULATOR_BIN="${MG_EMULATOR_BIN:-/home/mrjack/Android/Sdk/emulator/emulator}"
# GPU mode — default `host` (real GPU). Software `swiftshader_indirect` renders a
# black screen in this multi-instance setup (memory
# feedback_emulator_gpu_host_multi_contention). Override MG_GPU only on a headless
# host with no GPU/DISPLAY.
: "${MG_GPU:=host}"
MG_LOCK_DIR="${MG_LOCK_DIR:-/tmp/mg-emu-locks}"
# mission-geo app specifics (used only by mg_emu_install / mg_emu_app)
MG_APP_ID="${MG_APP_ID:-app.missiongeo.dev}"
MG_APK_DEFAULT="${MG_APK_DEFAULT:-$MG_EMU_ROOT/build/app/outputs/flutter-apk/app-dev-debug.apk}"

# Resolve an AVD "kind" to its real AVD name (pass-through for full names).
mg__emu_avd() {
  case "$1" in
    phone)    echo mission_geo_phone ;;
    tablet7)  echo mission_geo_tablet7 ;;
    tablet10) echo mission_geo_tablet10 ;;
    *)        echo "$1" ;;
  esac
}

# Owner-keyed state file (stable across this session's fresh shells).
mg__emu_owner() {
  # nearest 'claude' ancestor pid, else "solo"
  local pid="$$" c
  while [ -n "$pid" ] && [ "$pid" != "1" ] && [ -d "/proc/$pid" ]; do
    c=$(command cat "/proc/$pid/comm" 2>/dev/null)
    [ "$c" = "claude" ] && { echo "$pid"; return; }
    pid=$(command awk '/^PPid:/{print $2; exit}' "/proc/$pid/status" 2>/dev/null)
  done
  echo "solo"
}
mg__emu_env() { echo "/tmp/mg-emu.$(mg__emu_owner).env"; }
# PIDs of persistent `adb -s emulator-<port> logcat` attachments (see
# mg_emu_arm_logcat_pin below) — one file per owning session, read by
# mg_emu_down so a caller never has to remember to clean these up by hand.
mg__emu_logcat_pidfile() { echo "/tmp/mg-emu.$(mg__emu_owner).logcat-pids"; }

# Boot one AVD on an already-claimed port, in the background (non-blocking).
# Applies two safety gates before launching:
#   1. RAM preflight — abort if MemAvailable is below MG_MIN_RAM_MB (~3 GB).
#   2. Zombie reap  — kill any lingering qemu on this port (even if adb-invisible)
#      so we never stack two qemu processes on the same port.
mg__emu_boot_bg() {
  local avd="$1" port="$2"
  # RAM preflight (pool helper must be sourced for mg__ram_preflight).
  if declare -f mg__ram_preflight >/dev/null 2>&1; then
    mg__ram_preflight || return 1
  fi
  # Zombie reap (pool helper must be sourced for mg__kill_port_qemu).
  if declare -f mg__kill_port_qemu >/dev/null 2>&1; then
    mg__kill_port_qemu "$port"
  fi
  "$MG_EMULATOR_BIN" -avd "$avd" -no-window -no-audio \
    -gpu "$MG_GPU" -no-snapshot-save -no-snapshot-load -read-only \
    -port "$port" > "/tmp/emulator-$port.log" 2>&1 &
  disown
}

mg__emu_wait_boot() {
  local port="$1" t=0
  until [ "$("$MG_ADB" -s "emulator-$port" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    touch "$MG_LOCK_DIR/$port.lease" 2>/dev/null
    sleep 3; t=$((t+3))
    [ "$t" -ge 180 ] && { echo "  emulator-$port: boot TIMEOUT (${t}s)" >&2; return 1; }
  done
  echo "  emulator-$port booted (~${t}s)"
}

mg__emu_foreground() {
  "$MG_ADB" -s "emulator-$1" shell dumpsys activity activities 2>/dev/null \
    | grep -m1 -iE "ResumedActivity" | grep -oE "[a-zA-Z0-9._]+/[a-zA-Z0-9._]+" | head -1
}

# ── mg_emu_up <kind...> : claim N ports (1-3) and boot the requested AVDs ─────
mg_emu_up() {
  [ "$#" -ge 1 ] && [ "$#" -le 3 ] || { echo "usage: mg_emu_up <kind> [kind] [kind]  (1-3 of phone/tablet7/tablet10)" >&2; return 1; }
  command -v flock >/dev/null || { echo "flock missing (install util-linux)" >&2; return 1; }
  source "$MG_EMU_POOL" || return 1
  local kinds=("$@") ports=() avds=() k avd
  echo "Claiming $# port(s) from the pool..."
  for k in "${kinds[@]}"; do
    avd=$(mg__emu_avd "$k")
    if mg_claim_port; then
      ports+=("$MG_PORT"); avds+=("$avd")
      echo "  claimed $MG_PORT for $avd"
    else
      echo "Could not claim a port; releasing what we got." >&2
      local p; for p in "${ports[@]}"; do MG_PORT="$p"; mg_release_port; done
      return 1
    fi
  done

  # persist mapping (owner-keyed)
  local env; env=$(mg__emu_env)
  { echo "EMU_PORTS=\"${ports[*]}\""
    local i; for i in "${!ports[@]}"; do echo "EMU_AVD_${ports[$i]}=${avds[$i]}"; done
  } > "$env"

  echo "Booting $# AVD(s) in parallel..."
  local i; for i in "${!ports[@]}"; do mg__emu_boot_bg "${avds[$i]}" "${ports[$i]}"; done
  local rc=0; for i in "${!ports[@]}"; do mg__emu_wait_boot "${ports[$i]}" || rc=1; done

  # CRITICAL: keep the leases fresh (no flutter driver attached in this model).
  mg_keepalive_start "${ports[*]}"

  echo "mg_emu_up done (rc=$rc)."
  mg_emu_list
  return $rc
}

mg_emu_list() {
  local env; env=$(mg__emu_env)
  [ -f "$env" ] || { echo "(no emulators held by this session)"; return 0; }
  source "$env"
  local p; for p in $EMU_PORTS; do
    local v; eval "v=\${EMU_AVD_$p}"
    echo "  emulator-$p -> $v"
  done
}

# ── mg_emu_swap <port> <kind> : switch the AVD on a held port (lock stays) ────
# Uses mg__kill_port_qemu (from the pool helper) to reap any zombie qemu on
# the port BEFORE booting the new AVD — today's plain `adb emu kill` is a no-op
# on a crashed/unreachable emulator, which was the root cause of the stacking
# spiral (multiple qemu processes on the same port → OOM → more crashes).
mg_emu_swap() {
  local port="$1" kind="$2"
  [ -n "$port" ] && [ -n "$kind" ] || { echo "usage: mg_emu_swap <port> <phone|tablet7|tablet10>" >&2; return 1; }
  local env; env=$(mg__emu_env); source "$env" 2>/dev/null
  case " $EMU_PORTS " in *" $port "*) ;; *) echo "port $port not held by this session (have: ${EMU_PORTS:-none})" >&2; return 1 ;; esac
  local avd; avd=$(mg__emu_avd "$kind")
  echo "Swapping emulator-$port -> $avd (lock + keepalive stay held)..."
  touch "$MG_LOCK_DIR/$port.lease" 2>/dev/null
  # Reap any zombie qemu (handles crashed/adb-unreachable instances, not just healthy ones).
  if declare -f mg__kill_port_qemu >/dev/null 2>&1; then
    mg__kill_port_qemu "$port"
  else
    "$MG_ADB" -s "emulator-$port" emu kill >/dev/null 2>&1
  fi
  local i=0; while "$MG_ADB" -s "emulator-$port" get-state >/dev/null 2>&1; do
    touch "$MG_LOCK_DIR/$port.lease" 2>/dev/null; sleep 1; i=$((i+1)); [ "$i" -ge 30 ] && break
  done
  mg__emu_boot_bg "$avd" "$port"
  mg__emu_wait_boot "$port" || { echo "  swap boot failed" >&2; return 1; }
  # update persisted mapping for this port
  grep -v "^EMU_AVD_${port}=" "$env" > "$env.tmp" 2>/dev/null; mv "$env.tmp" "$env"
  echo "EMU_AVD_${port}=$avd" >> "$env"
  echo "emulator-$port now running $avd"
}

# ── mg_emu_scrcpy on|off [port] : mirror to the user's display ────────────────
mg_emu_scrcpy() {
  local action="$1" only="$2"
  local env; env=$(mg__emu_env); source "$env" 2>/dev/null
  local ports="${only:-$EMU_PORTS}"
  [ -n "$ports" ] || { echo "no emulators held" >&2; return 1; }
  case "$action" in
    on)
      command -v scrcpy >/dev/null || { echo "scrcpy missing — ask user to install (snap install scrcpy)" >&2; return 1; }
      local p; for p in $ports; do
        if pgrep -f "scrcpy -s emulator-$p" >/dev/null; then echo "  emulator-$p: scrcpy already running"; continue; fi
        DISPLAY="${DISPLAY:-:1}" nohup scrcpy -s "emulator-$p" --window-title "EMU $p" --max-size 700 \
          > "/tmp/scrcpy-$p.log" 2>&1 &
        disown; sleep 1
        pgrep -f "scrcpy -s emulator-$p" >/dev/null \
          && echo "  emulator-$p: scrcpy up" \
          || { echo "  emulator-$p: scrcpy FAILED"; tail -3 "/tmp/scrcpy-$p.log"; }
      done ;;
    off)
      local p; for p in $ports; do
        pkill -f "scrcpy -s emulator-$p" 2>/dev/null && echo "  emulator-$p: scrcpy stopped" || echo "  emulator-$p: no scrcpy"
        rm -f "/tmp/scrcpy-$p.log"
      done ;;
    *) echo "usage: mg_emu_scrcpy on|off [port]" >&2; return 1 ;;
  esac
}

mg_emu_health() {
  local env; env=$(mg__emu_env); source "$env" 2>/dev/null
  [ -n "$EMU_PORTS" ] || { echo "(no emulators held by this session)"; return 0; }
  local p ok=0 bad=0
  for p in $EMU_PORTS; do
    local state booted fg fgtag
    # `|| true`: a dead/booting port returns non-zero here — the expected case
    # this health check exists to report, not an error; bare under a caller's
    # `set -e` this would abort instead of printing the "problem" line.
    state=$("$MG_ADB" -s "emulator-$p" get-state 2>/dev/null || true)
    booted=$("$MG_ADB" -s "emulator-$p" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
    fg=$(mg__emu_foreground "$p" || true); fgtag="other"; [[ "$fg" == "$MG_APP_ID"/* ]] && fgtag="APP"
    printf "  emulator-%s: state=%s boot=%s fg=%s\n" "$p" "${state:-DEAD}" "${booted:-0}" "$fgtag"
    if [ "$state" = "device" ] && [ "$booted" = "1" ]; then ok=$((ok+1)); else bad=$((bad+1)); fi
  done
  echo "health: $ok ok / $bad problem"
  [ "$bad" -eq 0 ]
}

# ── mg_emu_arm_logcat_pin [port...] : persistent adb attachment ──────────────
# Arms one `adb -s emulator-<port> logcat` process per given port (defaults to
# all ports this session holds) and records its PID in the logcat-pids file.
# Why this exists: mg_keepalive_start (armed automatically by mg_emu_up) only
# renews a port's lease while ITS OWNING SESSION is alive — it self-terminates
# the instant that session dies (by design, so a dead agent can't pin a port
# forever). That breaks a common multi-agent handoff in this harness: one
# agent boots via online-duo-up.sh, then hands off to another agent (e.g. an
# inspector) who drives the rest of the scenario with one-shot adb commands —
# no flutter/dart/java driver ever attaches, and if the ORIGINATING agent's
# session ends first, its keepalive daemon dies and the pool's own per-port
# keeper reclaims the emulator once the lease goes stale (MG_LEASE_TTL, 180s
# by default) even though a different agent is still actively using it.
#
# A persistent logcat attachment sidesteps this entirely: it needs no owning
# session to stay alive, and the pool's attachment checks (mg__driver_attached,
# and the identical check inside the low-level keeper daemon) now recognize a
# genuine `adb ... logcat` stream — but NOT the pool's own short-lived
# get-state/install/shell probes — as live use (see emulator-pool.sh). Call
# this once after boot; call mg_emu_down (or mg_emu_kill_logcat_pins directly)
# when truly done, or these adb processes leak until killed.
mg_emu_arm_logcat_pin() {
  local env; env=$(mg__emu_env); source "$env" 2>/dev/null
  local ports="${*:-$EMU_PORTS}"
  [ -n "$ports" ] || { echo "mg_emu_arm_logcat_pin: no ports (pass explicitly or hold some via mg_emu_up)" >&2; return 1; }
  local pidf; pidf=$(mg__emu_logcat_pidfile)
  : > "$pidf"
  local p pid
  for p in $ports; do
    "$MG_ADB" -s "emulator-$p" logcat >/dev/null 2>&1 &
    pid=$!
    disown
    echo "$pid" >> "$pidf"
    echo "  emulator-$p: persistent logcat attachment armed (pid $pid)"
  done
}

# Kill every logcat pin recorded for this session (no-op if none armed).
mg_emu_kill_logcat_pins() {
  local pidf; pidf=$(mg__emu_logcat_pidfile)
  [ -f "$pidf" ] || return 0
  local pid
  while read -r pid; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
  done < "$pidf"
  rm -f "$pidf"
}

mg_emu_down() {
  source "$MG_EMU_POOL" 2>/dev/null
  mg_keepalive_stop
  mg_emu_kill_logcat_pins
  local env; env=$(mg__emu_env); source "$env" 2>/dev/null
  if [ -z "$EMU_PORTS" ]; then
    echo "mg_emu_down: no session state at $env — NOTHING released (this looked like success before). If this session did claim ports, pass them explicitly: for p in <ports>; do MG_PORT=\$p mg_release_port; done" >&2
    return 1
  fi
  local p; for p in $EMU_PORTS; do
    pkill -f "scrcpy -s emulator-$p" 2>/dev/null
    MG_PORT="$p"; mg_release_port
  done
  rm -f "$env"
  echo "mg_emu_down complete"
  "$MG_ADB" devices
}

# ── mission-geo app convenience ──────────────────────────────────────────────
mg_emu_install() {
  local apk="${1:-$MG_APK_DEFAULT}"
  [ -f "$apk" ] || { echo "APK not found: $apk" >&2; return 1; }
  local env; env=$(mg__emu_env); source "$env" 2>/dev/null
  local p rc=0; for p in $EMU_PORTS; do
    echo "Installing on emulator-$p ..."
    "$MG_ADB" -s "emulator-$p" install -r -d "$apk" >/tmp/mg-emu-install-$p.log 2>&1 \
      && echo "  emulator-$p: installed" || { echo "  emulator-$p: install FAILED (/tmp/mg-emu-install-$p.log)"; rc=1; }
  done
  return $rc
}

# settle GMS (it REPLACE-kills dependent apps on cold boot) then launch + verify
# the app is actually FOREGROUND (process-alive isn't enough), retrying.
mg_emu_app() {
  local env; env=$(mg__emu_env); source "$env" 2>/dev/null
  [ -n "$EMU_PORTS" ] || { echo "no emulators held" >&2; return 1; }
  local p
  for p in $EMU_PORTS; do
    # settle: wait until no fresh com.google.android.gms REPLACE for ~12s
    # `|| true` on every grep -c / mg__emu_foreground call below: both return
    # non-zero on a zero-match/no-resumed-activity result (the common,
    # expected case here, especially under `pipefail`) — bare under a caller's
    # `set -e` (e.g. online-duo-up.sh) that would abort mid-settle/mid-launch.
    local t=0; while [ "$t" -lt 90 ]; do
      local hit; hit=$("$MG_ADB" -s "emulator-$p" logcat -d -t 80 2>/dev/null | grep -c "com.google.android.gms.*REPLACED" || true)
      [ "${hit:-0}" -eq 0 ] && { sleep 12; t=$((t+12)); hit=$("$MG_ADB" -s "emulator-$p" logcat -d -t 40 2>/dev/null | grep -c "com.google.android.gms.*REPLACED" || true); [ "${hit:-0}" -eq 0 ] && break; } || { sleep 5; t=$((t+5)); }
    done
    local ok=0 a; for a in 1 2 3 4 5; do
      "$MG_ADB" -s "emulator-$p" shell monkey -p "$MG_APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
      sleep 6
      local fg; fg=$(mg__emu_foreground "$p" || true)
      if [[ "$fg" == "$MG_APP_ID"/* ]]; then sleep 5; fg=$(mg__emu_foreground "$p" || true); [[ "$fg" == "$MG_APP_ID"/* ]] && { ok=1; break; }; fi
      echo "    emulator-$p: not foreground (attempt $a, fg=$fg) — retry"
    done
    [ "$ok" -eq 1 ] && echo "  emulator-$p: $MG_APP_ID foreground ✓" || echo "  emulator-$p: FAILED to foreground app"
  done
}
