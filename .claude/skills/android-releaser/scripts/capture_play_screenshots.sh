#!/usr/bin/env bash
# Play Store screenshot capture orchestrator — Stage 1 of 2.
#
# Builds the app as a dev-flavor debug APK (no patch needed — the
# screenshot hooks are permanently committed and gated on kIsDevFlavor),
# seeds the local DB for a fully-unlocked progression state, then loops
# through scenarios × locales, launching the app with a
# `screenshot_scenario` intent extra.
#
# OUTPUT: raw masters written to
#   android/fastlane/screenshot_sources/<device>/<locale>/<stem>.png
# where <device> ∈ phone / tablet7 / tablet10.
#
# Stage 2 (framing) is a separate step:
#   python3 scripts/frame_screenshots.py
# It reads from screenshot_sources and writes framed PNGs to
#   android/fastlane/metadata/android/<locale>/images/<deviceDir>/.
# See scripts/README_store_assets.md for the full two-stage procedure.
#
# Supported AVDs (auto-detected from the running emulator's AVD name):
#   - mission_geo_phone     (phone 1080x2400)   → screenshot_sources/phone/
#   - mission_geo_tablet7   (tablet 1200x1920)  → screenshot_sources/tablet7/
#   - mission_geo_tablet10  (tablet 2560x1800)  → screenshot_sources/tablet10/
#
# Tablets also skip the onboarding walk and reuse the seeded DB from the
# phone AVD (mission_geo_phone must be running and seeded — i.e. you ran
# the phone capture first).
#
# Usage:
#   .claude/skills/android-releaser/scripts/capture_play_screenshots.sh [emulator-PORT] [scenario,...] [locale,...]
#
# Examples (run from repo root). Pass the serial of YOUR pool-claimed emulator
# (5554/5556/5558); the device type is auto-detected from the booted AVD, not the port:
#   .claude/skills/android-releaser/scripts/capture_play_screenshots.sh emulator-5554                    # whichever AVD is on that port
#   .claude/skills/android-releaser/scripts/capture_play_screenshots.sh emulator-5554 landmarkTaj fr-FR  # one scenario, one locale

set -euo pipefail

# This script lives at .claude/skills/android-releaser/scripts/ — 4 levels
# below the repo root.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../../../.."
PROJECT_ROOT="$(pwd)"

# ---------- parse args ----------
DEVICE="${1:-}"
SCENARIOS_FILTER="${2:-}"

if [ -z "$DEVICE" ]; then
  echo "Pass the device explicitly (no auto-detect — too easy to clobber another agent's emu)." >&2
  echo "Pass your pool-claimed serial, e.g. emulator-5554 (the device type is detected from the AVD)." >&2
  exit 1
fi

# ---------- device-type discriminator ----------
AVD_NAME="$(adb -s "$DEVICE" emu avd name 2>/dev/null | head -1 | tr -d '\r')"
case "$AVD_NAME" in
  mission_geo_phone)
    DEVICE_TYPE=phone
    CROP_TOP=130     # phone — tighter top crop
    ;;
  mission_geo_tablet7)
    DEVICE_TYPE=tablet7
    CROP_TOP=0       # 7" tablet — no top crop, leave breathing room
    ;;
  mission_geo_tablet10)
    DEVICE_TYPE=tablet10
    CROP_TOP=0       # 10" tablet — no top crop
    ;;
  *)
    echo "Refusing to run on AVD '$AVD_NAME' — supported: mission_geo_phone, mission_geo_tablet7, mission_geo_tablet10." >&2
    exit 1
    ;;
esac
echo "🎯 Device: $DEVICE (AVD: $AVD_NAME, type: $DEVICE_TYPE)"

# ---------- scenario catalog ----------
# scenario_name : filename_stem
# This is the SHIPPING list (8 shots). homeWithProgress, adventureCountries,
# duelLocal3Players and rankingSwissBrazil still have enum values and injection
# code but are removed from the automated capture run (still inspectable via
# the debug launcher).
ALL_SCENARIOS=(
  "adventureRegions:01_adventure_regions"
  "landmarkTaj:02_landmark_taj_mahal"
  "drawingSouthAfrica:03_drawing_south_africa"
  "searchingChile:04_searching_chile"
  "rankedVs:05_ranked_vs"
  "boosterReveal:06_booster_open"
  "collectionAlbum:07_collection_album"
  "defiClassementPopulation:08_defi_classement_population"
)
# Same shot list on phone and tablet — all 8 scenarios.
SCENARIOS=("${ALL_SCENARIOS[@]}")

# Play Store locale folder → in-app language tag.
# sr-Latn is the in-app value; Play Store accepts the bare "sr" folder.
declare -A LOCALE_TAG=(
  [fr-FR]="fr"
  [en-US]="en"
  [de-DE]="de"
  [sr]="sr-Latn"
  [es-ES]="es"
  [hr]="hr"
)
LOCALES=("fr-FR" "en-US" "de-DE" "sr" "es-ES" "hr")
# Filter via $3 if provided: scripts/capture_play_screenshots.sh emu landmarkTaj fr-FR,en-US
LOCALES_FILTER="${3:-}"
if [ -n "$LOCALES_FILTER" ]; then
  IFS=',' read -ra LOCALES <<< "$LOCALES_FILTER"
fi

# ---------- build ----------
# Dev-flavor debug APK:
#  - BuildConfig.DEBUG=true  → App Check debug token accepted by emulator
#  - APP_FLAVOR=dev          → kIsDevFlavor=true → screenshot hooks active
#  - No --dart-define=SCREENSHOT_MODE needed (hooks are committed code now)
echo "🔨 Building dev-flavor debug APK..."
flutter build apk --debug --flavor dev --dart-define=APP_FLAVOR=dev 2>&1 | tail -3
APK="build/app/outputs/flutter-apk/app-dev-debug.apk"
[ -f "$APK" ] || { echo "APK not produced at $APK" >&2; exit 1; }

echo "📦 Installing on $DEVICE..."
adb -s "$DEVICE" uninstall app.missiongeo.dev 2>&1 | tail -1 || true
adb -s "$DEVICE" install "$APK" 2>&1 | tail -1
adb -s "$DEVICE" root 2>&1 | tail -1

# Tell Android the user has already acknowledged the immersive-mode banner
# ("Viewing full screen — Got it"). Without this, the banner fires on the
# first app launch and leaks into the screencap.
adb -s "$DEVICE" shell settings put secure immersive_mode_confirmations confirmed 2>/dev/null || true

if [ "$DEVICE_TYPE" = "phone" ]; then
  # ---------- first-time onboarding (phone only — hard-coded 1080x2400 taps) ----------
  echo "🚶 Walking through onboarding once (phone)..."
  adb -s "$DEVICE" shell am start -n app.missiongeo.dev/app.missiongeo.MainActivity > /dev/null
  sleep 8
  adb -s "$DEVICE" shell input tap 540 1820  # UMP "Do not consent"
  sleep 4
  adb -s "$DEVICE" shell input tap 540 1586  # pseudo field
  sleep 2
  adb -s "$DEVICE" shell input text "Sam"
  sleep 1
  adb -s "$DEVICE" shell input tap 540 1446  # C'est parti
  sleep 5
  adb -s "$DEVICE" shell input tap 540 2000  # Refuser analytics
  sleep 5
  adb -s "$DEVICE" shell input tap 540 959   # Aventure card
  sleep 4
  # Swipe to find Asia (8th in the carousel)
  for i in 1 2 3 4 5 6 7 8; do
    adb -s "$DEVICE" shell input swipe 850 1000 230 1000 300
    sleep 1
  done
  adb -s "$DEVICE" shell input tap 540 2240  # Choisir cette région
  sleep 3
  adb -s "$DEVICE" shell input tap 336 1483  # Confirmer
  sleep 5
  adb -s "$DEVICE" shell am force-stop app.missiongeo.dev

  # ---------- DB seed (fully unlocked + varied progression) ----------
  echo "💾 Seeding DB..."
  adb -s "$DEVICE" pull /data/data/app.missiongeo.dev/databases/mission_geo.db /tmp/mg-app.db 2>&1 | tail -1
  python3 "$SCRIPT_DIR/seed_screenshot_db.py" /tmp/mg-app.db
else
  # ---------- tablet: skip onboarding, reuse phone's seeded DB ----------
  # The tablet AVD's resolution and the in-app responsive layout make the
  # hard-coded phone taps unusable. Instead, require that the phone capture
  # (mission_geo_phone) was run first — its seeded DB, pulled to /tmp, is
  # exactly what we need for the tablet too (same schema, same progression).
  # /tmp lives on the host, so it survives the read-only AVD swap on the port.
  if [ ! -f /tmp/mg-app.db ]; then
    echo "❌ /tmp/mg-app.db not found. Run the phone capture first to seed the DB:" >&2
    echo "    scripts/capture_play_screenshots.sh emulator-5554" >&2
    exit 1
  fi
  echo "💾 Bootstrapping app data dir on $DEVICE (one short launch)..."
  adb -s "$DEVICE" shell am start -n app.missiongeo.dev/app.missiongeo.MainActivity > /dev/null
  sleep 8
  adb -s "$DEVICE" shell am force-stop app.missiongeo.dev
fi

# Push, then restore ownership + SELinux context. APK reinstall assigns a new
# MCS category to the app process; the pushed file inherits adb's category
# (root) and gets rejected by the kernel ("Sqflite avc denied { open }"
# in logcat). `restorecon` re-applies the path-default context so the new
# app process can read its own DB.
OWNER=$(adb -s "$DEVICE" shell stat -c '%u:%g' /data/data/app.missiongeo.dev/databases/ | tr -d '\r')
adb -s "$DEVICE" push /tmp/mg-app.db /data/data/app.missiongeo.dev/databases/mission_geo.db 2>&1 | tail -1
adb -s "$DEVICE" shell chown "$OWNER" /data/data/app.missiongeo.dev/databases/mission_geo.db
adb -s "$DEVICE" shell chmod 660 /data/data/app.missiongeo.dev/databases/mission_geo.db
adb -s "$DEVICE" shell restorecon /data/data/app.missiongeo.dev/databases/mission_geo.db
adb -s "$DEVICE" shell rm -f /data/data/app.missiongeo.dev/databases/mission_geo.db-journal

# ---------- raw-master output directory wipe (full unfiltered runs only) ----------
# On a full run (no scenario filter), wipe the raw-master directory for every
# active locale before the capture loop. This guarantees that only the new 8
# PNGs remain even when filenames were renumbered or a scenario was replaced.
# Wiping is safe here because the capture loop immediately recreates every file.
# On a filtered single-scenario run, the wipe is skipped so the rest of the
# already-captured raw masters are preserved.
if [ -z "$SCENARIOS_FILTER" ]; then
  for LOCALE in "${LOCALES[@]}"; do
    OUTDIR="android/fastlane/screenshot_sources/$DEVICE_TYPE/$LOCALE"
    if [ -d "$OUTDIR" ]; then
      echo "🗑 Wiping $OUTDIR before full run..."
      rm -f "$OUTDIR"/*.png 2>/dev/null || true
    fi
  done
fi

# ---------- capture loop ----------
for entry in "${SCENARIOS[@]}"; do
  SCENARIO="${entry%%:*}"
  FILESTEM="${entry##*:}"

  # Filter
  if [ -n "$SCENARIOS_FILTER" ] && ! echo ",$SCENARIOS_FILTER," | grep -q ",$SCENARIO,"; then
    continue
  fi

  for LOCALE in "${LOCALES[@]}"; do
    OUTDIR="android/fastlane/screenshot_sources/$DEVICE_TYPE/$LOCALE"
    OUT="$OUTDIR/$FILESTEM.png"
    mkdir -p "$OUTDIR"

    echo "📸 $SCENARIO ($LOCALE) → $OUT"

    LANG_TAG="${LOCALE_TAG[$LOCALE]}"
    adb -s "$DEVICE" shell am force-stop app.missiongeo.dev
    sleep 1
    adb -s "$DEVICE" shell am start \
      -n app.missiongeo.dev/app.missiongeo.MainActivity \
      --es screenshot_scenario "$SCENARIO" \
      --es screenshot_locale "$LANG_TAG" > /dev/null
    # Allow splash bypass + country isolate parse + deep nav + page render.
    # Cold-start can take ~25s on emulator; subsequent launches are faster.
    sleep 30

    # Per-scenario post-launch interactions (tap, type, etc.) to reach the
    # exact capture state when state injection alone can't.
    case "$SCENARIO" in
      landmarkTaj)
        # Tap the input field, then type "IND" by tapping the soft-keyboard
        # keys (Flutter swallows raw `input text`). Coordinates resolved
        # dynamically via uiautomator dump so this works on phone and tablet.
        # Detect the screen size; `wm size` may print Physical (always) and/or
        # Override (when set). Take the last WxH pattern — that's the active
        # one. Disable pipefail locally so the chain can't kill the script.
        set +e
        SIZE_LINE=$(adb -s "$DEVICE" shell wm size 2>/dev/null | tr -d '\r')
        SCREEN_RES=$(echo "$SIZE_LINE" | grep -oE '[0-9]+x[0-9]+' | tail -1)
        SCREEN_W=$(echo "$SCREEN_RES" | cut -dx -f1)
        SCREEN_H=$(echo "$SCREEN_RES" | cut -dx -f2)
        set -e
        # Tap roughly where the input field sits (≈73% down the screen).
        adb -s "$DEVICE" shell input tap $((SCREEN_W / 2)) $((SCREEN_H * 73 / 100))
        sleep 2
        # Dump UI; find I, N, D key bounds dynamically.
        adb -s "$DEVICE" shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1
        UI_XML=$(adb -s "$DEVICE" shell cat /sdcard/ui.xml)
        for key in I N D; do
          set +e
          BOUNDS=$(echo "$UI_XML" | tr '>' '\n' | grep "content-desc=\"$key\"" | head -1 | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1)
          set -e
          if [ -z "$BOUNDS" ]; then
            echo "    ⚠ keyboard key '$key' not found in UIAutomator dump"
            continue
          fi
          NUMS=$(echo "$BOUNDS" | grep -oE '[0-9]+' | tr '\n' ' ')
          L=$(echo "$NUMS" | awk '{print $1}')
          T=$(echo "$NUMS" | awk '{print $2}')
          R=$(echo "$NUMS" | awk '{print $3}')
          B=$(echo "$NUMS" | awk '{print $4}')
          CX=$(( (L + R) / 2 ))
          CY=$(( (T + B) / 2 ))
          adb -s "$DEVICE" shell input tap $CX $CY
          sleep 1
        done
        sleep 1
        ;;
    esac

    adb -s "$DEVICE" exec-out screencap -p > "$OUT"
    # Crop the now-empty navy strip where the system status bar used to
    # live. SystemUiMode.manual hides the status bar but the app's
    # SafeArea-based AppBar still draws background under that area.
    if [ "$CROP_TOP" -gt 0 ]; then
      convert "$OUT" -chop "0x${CROP_TOP}" "$OUT"
    fi
    echo "    saved $(du -h "$OUT" | cut -f1)"
  done
done

echo "✅ Done. Raw masters → android/fastlane/screenshot_sources/$DEVICE_TYPE/"
echo "   Next: python3 scripts/frame_screenshots.py --device $DEVICE_TYPE"
