#!/usr/bin/env bash
# setup-phone-b-identity.sh — one-time provisioning of a SECOND, PERSISTENTLY
# DISTINCT phone AVD ("mission_geo_phone_b") for the online multiplayer debug
# harness (.claude/skills/online-multiplayer-debug/).
#
# WHY THIS EXISTS
#   mg_emu_up phone phone boots 2 QEMU processes of the SAME golden
#   mission_geo_phone.avd image, always in `-read-only` mode (mg-emu.sh /
#   emulator-pool.sh use `-read-only` deliberately so parallel instances of
#   the same AVD never corrupt each other's base image — every write during a
#   `-read-only` session is a private, ephemeral overlay discarded at exit).
#   That golden image ALREADY has the dev app installed and Firebase
#   anonymous-signed-in, baked in from ordinary (non-harness, non-read-only)
#   single-instance dev usage over time. Both harness instances read FROM
#   that same baked-in state and `adb install -r` preserves it — so without
#   a distinct golden image for the second player, both instances share the
#   IDENTICAL anonymous UID, silently invalidating every 2-player scenario.
#
# THE FIX
#   Clone the golden image once (excluding the quickboot snapshot — the
#   harness always boots with `-no-snapshot-load` so it's dead weight, ~2GB
#   saved), then boot the CLONE exactly once WITHOUT `-read-only` and WITH
#   `-wipe-data` so the wipe + a fresh app launch + fresh Firebase anonymous
#   sign-in actually PERSIST back to the clone's own base image (a
#   `-read-only` boot would discard them at exit — this only works non-read-
#   only). After this one-time decoupling, `mission_geo_phone_b` has its own
#   stable, distinct baked-in identity forever, and every future HARNESS boot
#   of it (read-only, via mg_emu_up) reloads that same distinct state — no
#   re-provisioning, no re-onboarding, identical to how `mission_geo_phone`
#   already behaves for instance A.
#
# IDEMPOTENT — safe to call every time online-duo-up.sh runs. Skips
# everything (clone + decoupling boot) if mission_geo_phone_b already exists
# and is already decoupled (sentinel file). Takes a few minutes on first run
# (disk copy of ~3-4GB + one emulator boot cycle); near-instant afterward.
#
# USAGE
#   bash setup-phone-b-identity.sh
#   (no arguments — always targets mission_geo_phone -> mission_geo_phone_b)

set -euo pipefail

MG_ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
AVD_DIR="${MG_AVD_DIR:-$HOME/.android/avd}"
SRC_NAME="mission_geo_phone"
DST_NAME="mission_geo_phone_b"
SRC_AVD="$AVD_DIR/${SRC_NAME}.avd"
DST_AVD="$AVD_DIR/${DST_NAME}.avd"
DST_INI="$AVD_DIR/${DST_NAME}.ini"
SENTINEL="$DST_AVD/.mg_identity_decoupled"

if [ -f "$SENTINEL" ]; then
  echo "setup-phone-b-identity: $DST_NAME already provisioned and decoupled — nothing to do."
  exit 0
fi

[ -d "$SRC_AVD" ] || { echo "setup-phone-b-identity: source AVD not found at $SRC_AVD" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_ROOT/.claude/skills/shared/emulator-pool.sh"

# ── Step 1: clone the golden image (skip if already cloned but not yet
# decoupled — e.g. a previous run was interrupted before the boot step) ──────
if [ ! -d "$DST_AVD" ]; then
  echo "== setup-phone-b-identity: cloning $SRC_NAME -> $DST_NAME (excluding quickboot snapshot) =="
  cp -r "$SRC_AVD" "$DST_AVD"
  rm -rf "${DST_AVD:?}/snapshots"
  echo "avd.ini.encoding=UTF-8
path=$DST_AVD
path.rel=avd/${DST_NAME}.avd
target=android-36" > "$DST_INI"
  echo "  cloned ($(du -sh "$DST_AVD" | cut -f1))"
else
  echo "== setup-phone-b-identity: $DST_AVD already exists, skipping clone =="
fi

# ── Step 2: one-time NON-read-only wipe-data boot to decouple identity ──────
echo "== setup-phone-b-identity: claiming a port for the one-time decoupling boot =="
mg_claim_port

echo "== Booting $DST_NAME WITHOUT -read-only (required for -wipe-data to persist) =="
mg__ram_preflight || { mg_release_port; exit 1; }
mg__kill_port_qemu "$MG_PORT"
touch "$MG_LOCK_DIR/$MG_PORT.owned" "$MG_LOCK_DIR/$MG_PORT.lease"
nohup "$MG_EMULATOR_BIN" -avd "$DST_NAME" -no-window -no-audio \
  -gpu "$MG_GPU" -no-snapshot-save -no-snapshot-load -wipe-data \
  -port "$MG_PORT" > "/tmp/emulator-$MG_PORT.log" 2>&1 &
disown

until [ "$("$MG_ADB" -s "emulator-$MG_PORT" shell getprop sys.boot_completed 2>/dev/null | command tr -d '\r')" = "1" ]; do
  mg_keepalive
  sleep 5
done
mg_keepalive
echo "  $DST_NAME booted (wiped) on emulator-$MG_PORT"

APK="$REPO_ROOT/build/app/outputs/flutter-apk/app-dev-debug.apk"
if [ ! -f "$APK" ]; then
  echo "== No dev-debug APK found — building one for the decoupling install =="
  (cd "$REPO_ROOT" && flutter build apk --debug --flavor dev --dart-define=APP_FLAVOR=dev)
fi

echo "== Installing + launching to trigger a fresh anonymous sign-in =="
"$MG_ADB" -s "emulator-$MG_PORT" install -r -d "$APK" >/tmp/mg-setup-phone-b-install.log 2>&1 \
  || { echo "install FAILED — see /tmp/mg-setup-phone-b-install.log" >&2; exit 1; }
"$MG_ADB" -s "emulator-$MG_PORT" shell monkey -p app.missiongeo.dev -c android.intent.category.LAUNCHER 1 >/dev/null

echo "== Waiting (up to 60s) for the fresh anonymous UID to appear in logcat =="
NEW_UID=""
for _i in $(seq 1 20); do
  NEW_UID="$("$MG_ADB" -s "emulator-$MG_PORT" logcat -d 2>/dev/null \
    | grep -o 'MG_DEBUG_UID=[A-Za-z0-9]*' | tail -1 | cut -d= -f2 || true)"
  [ -n "$NEW_UID" ] && break
  mg_keepalive
  sleep 3
done

if [ -z "$NEW_UID" ]; then
  echo "FAIL: no MG_DEBUG_UID seen after 60s — decoupling boot did not confirm a fresh sign-in." >&2
  echo "  Not marking $DST_NAME as decoupled. Re-run this script, or install an APK built from" >&2
  echo "  a commit that includes the MG_DEBUG_UID log line in lib/main.dart." >&2
  mg_release_port
  exit 1
fi
echo "  fresh anonymous UID confirmed: $NEW_UID"

# ── Step 3: clean shutdown so the wipe + install + sign-in PERSIST (this is
# NOT a -read-only session, so a normal kill flushes state to disk) ─────────
echo "== Shutting down cleanly to persist the decoupled identity =="
"$MG_ADB" -s "emulator-$MG_PORT" emu kill >/dev/null 2>&1 || true
for _i in $(seq 1 30); do
  "$MG_ADB" -s "emulator-$MG_PORT" get-state >/dev/null 2>&1 || break
  sleep 1
done
mg_release_port

touch "$SENTINEL"
echo
echo "== setup-phone-b-identity: done. $DST_NAME is now a persistent, distinct identity ($NEW_UID). =="
echo "Future online-duo-up.sh runs will boot it read-only, alongside mission_geo_phone, with no re-provisioning."
