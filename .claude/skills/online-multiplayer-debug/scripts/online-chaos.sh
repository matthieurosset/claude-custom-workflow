#!/usr/bin/env bash
# online-chaos.sh — adb chaos primitives for the online multiplayer debug
# harness (.claude/skills/online-multiplayer-debug/). Sourceable function
# library, not a standalone script — every function takes an EXPLICIT serial
# (e.g. emulator-5554), never auto-detects one. Use the serials printed by
# online-duo-up.sh (or `adb devices`).
#
# USAGE
#   source .claude/skills/online-multiplayer-debug/scripts/online-chaos.sh
#   mg_chaos_kill_app emulator-5554
#   mg_chaos_airplane_on emulator-5556
#   mg_chaos_airplane_off emulator-5556
#   mg_chaos_background emulator-5554 15
#   mg_chaos_tail_room_code emulator-5554
#   mg_chaos_set_ranked_autoplay emulator-5554 win
#
# Each function maps to a named manual scenario in SKILL.md:
#   mg_chaos_kill_app        -> Host stall on roundResult / Ranked forfeit (host side,
#                                regime 3 — immediate, unaffected by the threshold below)
#   mg_chaos_airplane_on/off -> Ranked forfeit (opponent past 30s _opponentStaleThreshold,
#                                regime 2 — up from 9s, 2026-07 threshold bump),
#                                Background grace (<30s survives / >30s stops).
#                                NOTE: which side is cut matters since the 2026-07
#                                life-loss redesign — cutting the GUEST bleeds it a
#                                life per question closed during the gap (no more
#                                presence leniency); cutting the HOST pauses the
#                                match instead (only the host advances questions).
#                                See SKILL.md's split "cut the GUEST"/"cut the HOST"
#                                rows for the exact expectations.
#   mg_chaos_background      -> Background grace window
#   mg_chaos_tail_room_code  -> Bridge instance A's room code to instance B
#                                (MG_DEBUG_ROOM_CODE=<code>, printed via debugPrint
#                                by debugCreateRoomAndWait)
#   mg_chaos_set_ranked_autoplay -> Per-instance ranked auto-play mode (drives a match
#                                to a real win/loss/ELO/forfeit outcome — see SKILL.md's
#                                "Ranked Auto-Play" section and the Manual Chaos
#                                Scenario Checklist's ranked outcome rows)

MG_APP_ID="${MG_APP_ID:-app.missiongeo.dev}"

# ── mg_chaos_kill_app <serial> ────────────────────────────────────────────
# Force-stops the app process (simulates a hard crash/kill — NOT a graceful
# background). Tests: does the OTHER player's client detect the disconnect
# quickly (ranked: regime 3, ~3-5s via onDisconnect node removal — NOT the
# 30s regime-2 stale-ts threshold, which only applies to a still-alive-but-
# unreachable opponent / casual heartbeat-stale)?
mg_chaos_kill_app() {
  local serial="$1"
  [ -n "$serial" ] || { echo "usage: mg_chaos_kill_app <serial>" >&2; return 1; }
  adb -s "$serial" shell am force-stop "$MG_APP_ID"
  echo "  $serial: force-stopped $MG_APP_ID"
}

# ── mg_chaos_airplane_on/off <serial> ─────────────────────────────────────
# Cuts all network (Firestore/RTDB listeners drop without an onDisconnect
# trigger from the CLIENT side, but RTDB's own server-side onDisconnect
# handlers still fire). Closer to a real "lost wifi" than force-stop: the app
# process stays alive, only connectivity dies.
#
# Primitive: `svc wifi`/`svc data` (direct binder calls), NOT the
# `settings put global airplane_mode_on` + `am broadcast AIRPLANE_MODE` combo.
# On Android 16 (google_apis emulator image used here) the broadcast route is
# broken: the shell is not always allowed to send AIRPLANE_MODE, `am broadcast`
# throws SecurityException, and the old code didn't check the exit status —
# it printed "airplane mode ON" regardless, a false-pass that made every chaos
# scenario relying on it silently no-op. `svc wifi disable`/`svc data disable`
# hits ConnectivityService directly, doesn't need the broadcast permission,
# and is verified working on the Android 16 image. Both legs (wifi AND data)
# are toggled because the emulator's default network can be either depending
# on the AVD config — cutting only one can leave the other carrying traffic.
mg_chaos_airplane_on() {
  local serial="$1"
  [ -n "$serial" ] || { echo "usage: mg_chaos_airplane_on <serial>" >&2; return 1; }
  local rc=0
  adb -s "$serial" shell svc wifi disable || rc=1
  adb -s "$serial" shell svc data disable || rc=1
  if [ "$rc" -ne 0 ]; then
    echo "  $serial: FAILED to disable wifi/data (svc command errored — see output above)" >&2
    return 1
  fi
  echo "  $serial: network OFF (svc wifi/data disable)"
}

mg_chaos_airplane_off() {
  local serial="$1"
  [ -n "$serial" ] || { echo "usage: mg_chaos_airplane_off <serial>" >&2; return 1; }
  local rc=0
  adb -s "$serial" shell svc wifi enable || rc=1
  adb -s "$serial" shell svc data enable || rc=1
  if [ "$rc" -ne 0 ]; then
    echo "  $serial: FAILED to re-enable wifi/data (svc command errored — see output above)" >&2
    return 1
  fi
  echo "  $serial: network ON (svc wifi/data enable)"
}

# ── mg_chaos_background <serial> <secs> ───────────────────────────────────
# Sends the app to background (HOME) for <secs> seconds, then relaunches it.
# Tests the background-grace window (bg-grace 30s in online_game_provider.dart):
# a short background (<30s) should preserve the heartbeat/session; a long one
# (>30s) should let it lapse.
mg_chaos_background() {
  local serial="$1" secs="${2:-15}"
  [ -n "$serial" ] || { echo "usage: mg_chaos_background <serial> <secs>" >&2; return 1; }
  adb -s "$serial" shell input keyevent KEYCODE_HOME
  echo "  $serial: backgrounded for ${secs}s..."
  sleep "$secs"
  adb -s "$serial" shell monkey -p "$MG_APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null
  echo "  $serial: relaunched $MG_APP_ID"
}

# ── mg_chaos_tail_room_code <serial> ──────────────────────────────────────
# Scrapes the most recent MG_DEBUG_ROOM_CODE=<code> line from this instance's
# logcat buffer — the bridge for "instance A creates, instance B joins by
# code" without reading the screen. Prints the code alone (empty if not found
# yet — debugCreateRoomAndWait logs it only after createRoom() resolves).
mg_chaos_tail_room_code() {
  local serial="$1"
  [ -n "$serial" ] || { echo "usage: mg_chaos_tail_room_code <serial>" >&2; return 1; }
  adb -s "$serial" logcat -d 2>/dev/null \
    | grep -o 'MG_DEBUG_ROOM_CODE=[A-Z0-9]*' \
    | tail -1 \
    | cut -d= -f2
}

# ── mg_chaos_tail_uid <serial> ─────────────────────────────────────────────
# Scrapes the most recent MG_DEBUG_UID=<uid> line from this instance's logcat
# buffer (logged once by MyApp in lib/main.dart whenever the signed-in
# anonymous Firebase UID becomes available or changes — dev flavor only).
# Prints the UID alone (empty if the app hasn't finished signing in yet, or
# was launched before this log line existed on an older build).
#
# This is the identity check online-duo-up.sh runs automatically after boot
# to guard against both instances sharing one Firebase identity (which
# invalidates every 2-player scenario — see the "MG_DEBUG_UID identical on
# both instances" entry in SKILL.md's Common Failures table).
mg_chaos_tail_uid() {
  local serial="$1"
  [ -n "$serial" ] || { echo "usage: mg_chaos_tail_uid <serial>" >&2; return 1; }
  adb -s "$serial" logcat -d 2>/dev/null \
    | grep -o 'MG_DEBUG_UID=[A-Za-z0-9]*' \
    | tail -1 \
    | cut -d= -f2
}

# ── mg_chaos_set_ranked_autoplay <serial> <off|win|lose> ──────────────────
# Cold-restarts the app on <serial> with the `debug_ranked_autoplay` launch
# intent extra so DebugRankedAutoplay.initFromIntent() (lib/core/dev/
# debug_ranked_autoplay.dart) picks it up on THIS process's next main(). Both
# harness instances run the SAME compiled APK (see debug_timing_config.dart's
# pacing scalers, which must stay identical on both) — a dart-define can't
# give instance A `win` and instance B `off`, only a per-process runtime read
# of that instance's own launch intent can. online-duo-up.sh calls this once
# per instance right after mg_emu_app when `--autoplay-a`/`--autoplay-b` is
# passed; call it directly mid-session to flip a mode without a full restart
# of the harness.
#
# force-stop first: an `am start` on an already-resumed activity fires
# onNewIntent(), not a fresh main()/runApp() — the extra would never reach
# DebugRankedAutoplay without killing the process. This DOES tear down any
# match currently open on that instance — only call it between matches (e.g.
# right after boot, or after leaving a finished match), not mid-round.
mg_chaos_set_ranked_autoplay() {
  local serial="$1" value="${2:-off}"
  [ -n "$serial" ] || { echo "usage: mg_chaos_set_ranked_autoplay <serial> <off|win|lose>" >&2; return 1; }
  case "$value" in
    off|win|lose) ;;
    *) echo "invalid mode: $value (expected off|win|lose)" >&2; return 1 ;;
  esac
  adb -s "$serial" shell am force-stop "$MG_APP_ID"
  adb -s "$serial" shell am start -n "$MG_APP_ID/app.missiongeo.MainActivity" \
    -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \
    --es debug_ranked_autoplay "$value" >/dev/null
  echo "  $serial: relaunched with debug_ranked_autoplay=$value"
}
