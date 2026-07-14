#!/usr/bin/env bash
# online-duo-up.sh — boot 2 real dev-flavor instances as 2 real players for the
# online multiplayer debug harness (.claude/skills/online-multiplayer-debug/).
#
# Composes existing infra, doesn't rebuild it:
#   - .claude/skills/shared/mg-emu.sh claims 2 pool ports, boots two AVDs in
#     parallel, and force-foregrounds the app on both once installed.
#   - .claude/skills/shared/emulator-pool.sh underneath (RAM preflight, zombie
#     reap, session-aware lease keepalive).
#
# Builds ONE accelerated dev-debug APK (writes to Firebase mission-geo-dev, the
# real backend — NEVER prod) and installs it on both instances. Both instances
# MUST run the SAME build: the client-side timers this harness scales are
# per-build consts, so a speed mismatch between A and B would desync their
# countdowns/reveals (see debug_timing_config.dart). Server-shared state
# (room.config.roundDurationSeconds, presence, disconnect thresholds) is safe
# regardless — this is purely a client display-timing concern.
#
# USAGE
#   bash online-duo-up.sh [--online-speed N] [--ranked-speed N] [--avd phone|tablet7|tablet10] [--skip-build]
#                          [--autoplay-a off|win|lose] [--autoplay-b off|win|lose]
#
#   --online-speed N   DEBUG_ONLINE_SPEED dart-define (default 6)
#   --ranked-speed N    DEBUG_RANKED_SPEED dart-define (default 3, capped by the
#                       server-floored 10s ranked question — see SKILL.md)
#   --avd KIND          AVD kind for instance A (default: phone). Instance B
#                       automatically uses the persistently-decoupled
#                       `mission_geo_phone_b` clone (see setup-phone-b-identity.sh)
#                       when KIND is the default "phone" — this is what gives A
#                       and B distinct, stable Firebase identities. Overriding
#                       KIND to tablet7/tablet10 boots the SAME AVD for both
#                       instances (no pre-provisioned decoupled clone exists for
#                       tablets) — the identity guard below will legitimately
#                       FAIL in that case; only override --avd if you've set up
#                       your own distinct tablet identity out of band.
#   --skip-build         Reuse the existing APK at build/app/outputs/flutter-apk/
#                        app-dev-debug.apk instead of rebuilding (fast iteration
#                        when only Dart UI/logic outside the harness changed —
#                        skip if you touched any pacing/debug-tile code).
#   --autoplay-a MODE    Ranked auto-play mode for instance A: off (default) /
#                        win (auto-submits the correct answer every question,
#                        driving a match to completion) / lose (never answers —
#                        same net effect as off, kept as an explicit choice for
#                        symmetry). See debug_ranked_autoplay.dart. Only takes
#                        effect if at least one of --autoplay-a/--autoplay-b is
#                        passed (both instances default to off otherwise, so a
#                        plain run behaves exactly as before this flag existed).
#   --autoplay-b MODE    Same, for instance B.
#
# OUTPUT
#   Prints the two ANDROID_SERIAL values (emulator-<portA> / emulator-<portB>)
#   and the accelerated dart-define values used, then leaves both emulators
#   running with the app foreground — ready for the manual scenario walkthrough
#   in SKILL.md. Ports stay claimed until you call `mg_emu_down` (source
#   mg-emu.sh again in a fresh shell) — release them when you're done, other
#   agents share this 3-port pool.
#
# Each Bash tool call is a fresh shell — re-source mg-emu.sh in any later call
# that needs mg_emu_swap / mg_emu_scrcpy / mg_emu_down / mg_emu_health.

set -euo pipefail

ONLINE_SPEED=6
RANKED_SPEED=3
AVD_KIND=phone
SKIP_BUILD=0
AUTOPLAY_A=off
AUTOPLAY_B=off
AUTOPLAY_REQUESTED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --online-speed) ONLINE_SPEED="$2"; shift 2 ;;
    --ranked-speed) RANKED_SPEED="$2"; shift 2 ;;
    --avd) AVD_KIND="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --autoplay-a) AUTOPLAY_A="$2"; AUTOPLAY_REQUESTED=1; shift 2 ;;
    --autoplay-b) AUTOPLAY_B="$2"; AUTOPLAY_REQUESTED=1; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

for _v in "$AUTOPLAY_A" "$AUTOPLAY_B"; do
  case "$_v" in
    off|win|lose) ;;
    *) echo "invalid --autoplay-a/--autoplay-b value: $_v (expected off|win|lose)" >&2; exit 1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=/dev/null
source .claude/skills/shared/mg-emu.sh

# ── App Check debug token bootstrap ─────────────────────────────────────────
# android/firebase_debug_token.{dev,prod}.properties are gitignored, so every
# fresh worktree (git-workflow-branch-worktree skill) starts without them.
# Without the dev file, BuildConfig.FIREBASE_APP_CHECK_DEBUG_TOKEN is blank,
# MainActivity's installFixedAppCheckDebugTokenIfNeeded() no-ops, and the
# Firebase App Check SDK falls back to a fresh random UUID on every install —
# one that is NOT in the mission-geo-dev Firebase Console debug-token
# allow-list, so every Firestore/RTDB call this harness depends on (room
# creation, ranked queue, presence) comes back PERMISSION_DENIED. The build
# and install both succeed silently; only the online calls fail. See
# "Common Failures and Fixes" below.
#
# This harness only ever builds --flavor dev, so the prod file is copied
# best-effort (for whichever other flow in this worktree needs --flavor
# prod) but is NOT hard-required here.
PRIMARY_CHECKOUT="/home/mrjack/git/mission-geo"
_ensure_appcheck_token_file() {
  local flavor="$1" required="$2"
  local rel="android/firebase_debug_token.${flavor}.properties"
  local primary="$PRIMARY_CHECKOUT/android/firebase_debug_token.${flavor}.properties"
  [ -f "$rel" ] && return 0
  if [ -f "$primary" ]; then
    echo "== $rel missing (gitignored, fresh worktree) — copying from primary checkout: $primary =="
    cp "$primary" "$rel"
    return 0
  fi
  if [ "$required" -eq 1 ]; then
    echo "FAIL: $rel is missing and no primary checkout copy was found at $primary." >&2
    echo "  Without it, App Check falls back to a random per-install UUID (not allow-listed)" >&2
    echo "  and every Firestore/RTDB call this harness depends on comes back PERMISSION_DENIED." >&2
    echo "  Register a UUID in Firebase Console -> mission-geo-dev -> App Check -> Manage debug" >&2
    echo "  tokens, then create $rel with 'token=<uuid>' (see $rel.example)." >&2
    exit 1
  else
    echo "WARN: $rel missing and no primary checkout copy at $primary — skipping (this harness only builds --flavor dev, so this is non-fatal)." >&2
  fi
}
echo "== Ensuring App Check debug token files are present =="
_ensure_appcheck_token_file dev 1
_ensure_appcheck_token_file prod 0

# Instance B's AVD: the decoupled clone for the default "phone" case (see
# header comment above), or the same kind as A when overridden — in which
# case both instances share one golden image and the identity guard below is
# expected to catch it.
AVD_KIND_B="$AVD_KIND"
if [ "$AVD_KIND" = "phone" ]; then
  echo "== Ensuring the decoupled B identity (mission_geo_phone_b) is provisioned =="
  bash .claude/skills/online-multiplayer-debug/scripts/setup-phone-b-identity.sh
  AVD_KIND_B="mission_geo_phone_b"
else
  echo "WARN: --avd $AVD_KIND overrides the default — no pre-provisioned decoupled clone exists for it. Both instances will share one golden image; expect the identity guard below to fail unless you've set one up yourself." >&2
fi

echo "== online-duo-up: claiming 2 pool ports (A: $AVD_KIND, B: $AVD_KIND_B) =="
mg_emu_up "$AVD_KIND" "$AVD_KIND_B"

APK="build/app/outputs/flutter-apk/app-dev-debug.apk"
if [ "$SKIP_BUILD" -eq 1 ] && [ -f "$APK" ]; then
  echo "== --skip-build: reusing existing $APK =="
else
  echo "== Building ONE accelerated dev-debug APK (DEBUG_ONLINE_SPEED=$ONLINE_SPEED, DEBUG_RANKED_SPEED=$RANKED_SPEED) =="
  flutter build apk --debug --flavor dev \
    --dart-define=APP_FLAVOR=dev \
    --dart-define=DEBUG_ONLINE_SPEED="$ONLINE_SPEED" \
    --dart-define=DEBUG_RANKED_SPEED="$RANKED_SPEED"
fi

echo "== Installing on both instances =="
mg_emu_install "$APK"

echo "== Launching + foregrounding the app on both instances =="
mg_emu_app

# shellcheck source=/dev/null
source .claude/skills/online-multiplayer-debug/scripts/online-chaos.sh

_env_file="$(mg__emu_env)"
# shellcheck source=/dev/null
source "$_env_file"
read -r -a _ports <<< "$EMU_PORTS"

# ── Persistent adb attachment (survives an agent handoff) ───────────────────
# This harness never runs `flutter run` (build-once + adb install + one-shot
# adb from here on), so mg_emu_up's mg_keepalive_start is the only thing
# keeping the leases fresh — and it dies with the session that called it. A
# common pattern here is boot-then-hand-off (e.g. to an inspector agent that
# only issues one-shot adb), which can outlive the booting session. Arm one
# persistent `adb logcat` per claimed serial so the pool sees the ports as
# genuinely in use regardless of which session is still around — see
# mg_emu_arm_logcat_pin's doc comment in mg-emu.sh. Torn down by mg_emu_down.
echo "== Arming persistent adb attachment on both instances (survives a session handoff) =="
mg_emu_arm_logcat_pin "${_ports[@]}"

# ── Per-instance ranked auto-play ────────────────────────────────────────────
# Only touches the app when at least one --autoplay-a/--autoplay-b was passed
# — a plain run (both default "off") skips this entirely and behaves exactly
# as before this flag existed. Cold-restarts (force-stop + am start with the
# `debug_ranked_autoplay` extra) each instance so DebugRankedAutoplay picks up
# the mode on its next main() — see mg_chaos_set_ranked_autoplay's doc comment
# in online-chaos.sh for why a plain am start on the running activity isn't
# enough.
if [ "$AUTOPLAY_REQUESTED" -eq 1 ] && [ "${#_ports[@]}" -eq 2 ]; then
  _serial_a="emulator-${_ports[0]}"
  _serial_b="emulator-${_ports[1]}"
  echo "== Setting ranked auto-play (A=$AUTOPLAY_A, B=$AUTOPLAY_B) — cold-restarting both =="
  mg_chaos_set_ranked_autoplay "$_serial_a" "$AUTOPLAY_A"
  mg_chaos_set_ranked_autoplay "$_serial_b" "$AUTOPLAY_B"
  # Let both processes actually come back up before the identity guard below
  # starts polling for the MG_DEBUG_UID log line.
  sleep 6
elif [ "$AUTOPLAY_REQUESTED" -eq 1 ]; then
  echo "WARN: expected 2 ports, got ${#_ports[@]} (${EMU_PORTS}) — skipping ranked auto-play setup." >&2
fi

# ── Identity guard ──────────────────────────────────────────────────────────
# Both instances MUST have distinct Firebase anonymous UIDs — this harness
# tests 2-PLAYER interactions, and a shared identity silently invalidates
# joining, ranked pairing, and every chaos scenario without any visible error
# (see "MG_DEBUG_UID identical on both instances" in SKILL.md's Common
# Failures table for the history of why this needs an automated check).
echo "== Verifying the two instances have distinct identities =="
if [ "${#_ports[@]}" -ne 2 ]; then
  echo "WARN: expected 2 ports, got ${#_ports[@]} (${EMU_PORTS}) — skipping identity check." >&2
else
  _serial_a="emulator-${_ports[0]}"
  _serial_b="emulator-${_ports[1]}"
  _uid_a="" _uid_b=""
  for _i in 1 2 3 4 5 6 7 8 9 10; do
    # `|| true`: mg_chaos_tail_uid's internal grep returns non-zero on no
    # match (no MG_DEBUG_UID line yet, still signing in) — under this
    # script's `set -e`, an unguarded assignment would abort the whole
    # script on the very first empty poll instead of retrying.
    _uid_a="$(mg_chaos_tail_uid "$_serial_a" || true)"
    _uid_b="$(mg_chaos_tail_uid "$_serial_b" || true)"
    [ -n "$_uid_a" ] && [ -n "$_uid_b" ] && break
    sleep 3
  done
  if [ -z "$_uid_a" ] || [ -z "$_uid_b" ]; then
    echo "WARN: could not read a UID from one or both instances after 30s (sign-in may still be in progress, or you're running an APK built before the MG_DEBUG_UID log line existed). Verify manually with mg_chaos_tail_uid before trusting 2-player results." >&2
  elif [ "$_uid_a" = "$_uid_b" ]; then
    echo "FAIL: both instances share the SAME Firebase UID ($_uid_a)." >&2
    echo "  $_serial_a and $_serial_b are not distinct players — every 2-player scenario" >&2
    echo "  (join by code, ranked pairing, all 5 chaos scenarios) is INVALID until this is fixed." >&2
    echo "  See 'MG_DEBUG_UID identical on both instances' in SKILL.md's Common Failures table." >&2
    exit 1
  else
    echo "  OK — distinct identities: $_serial_a=$_uid_a / $_serial_b=$_uid_b"
  fi
fi

echo
echo "== online-duo-up ready =="
mg_emu_list
echo
echo "Both instances are running the SAME accelerated build (DEBUG_ONLINE_SPEED=$ONLINE_SPEED, DEBUG_RANKED_SPEED=$RANKED_SPEED)."
if [ "$AUTOPLAY_REQUESTED" -eq 1 ]; then
  echo "Ranked auto-play: A=$AUTOPLAY_A, B=$AUTOPLAY_B (mg_chaos_set_ranked_autoplay <serial> <mode> to change mid-session)."
fi
echo "Next: open the debug launcher (bottom-right FAB / home tab 'debug' route) on each."
echo "See SKILL.md for the A-creates/B-joins and ranked-queue-both walkthroughs, and the manual chaos scenario checklist."
echo
echo "When done: source .claude/skills/shared/mg-emu.sh && mg_emu_down   (releases both ports for other agents)"
