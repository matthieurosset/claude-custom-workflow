#!/usr/bin/env bash
# Regression suite runner for Mission Geo.
#
# Usage:
#   run.sh [--tier smoke|full] [--only <feature>]
#
# Examples:
#   run.sh                          # smoke tier (default)
#   run.sh --tier full              # full tier
#   run.sh --only discovery         # single feature file
#
# Exits with code 0 on all-PASS, non-zero on any FAIL.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

# ── Defaults ────────────────────────────────────────────────────────────────
TIER="smoke"
ONLY_FEATURE=""

# ── Parse args ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier)
      TIER="$2"
      shift 2
      ;;
    --only)
      ONLY_FEATURE="$2"
      shift 2
      ;;
    *)
      echo "[regression-suite] Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$TIER" != "smoke" && "$TIER" != "full" ]]; then
  echo "[regression-suite] Invalid tier '$TIER' — must be 'smoke' or 'full'." >&2
  exit 1
fi

# ── Determine test target ────────────────────────────────────────────────────
if [[ -n "$ONLY_FEATURE" ]]; then
  TEST_TARGET="integration_test/scenarios/${ONLY_FEATURE}_test.dart"
  if [[ ! -f "$REPO_ROOT/$TEST_TARGET" ]]; then
    echo "[regression-suite] Scenario file not found: $TEST_TARGET" >&2
    exit 1
  fi
else
  TEST_TARGET="integration_test/scenarios/all_scenarios.dart"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Mission Geo — Regression Suite ($TIER tier)"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Emulator pool ────────────────────────────────────────────────────────────
# shellcheck source=/dev/null
source "$REPO_ROOT/.claude/skills/shared/emulator-pool.sh"

echo "[regression-suite] Claiming emulator port…"
mg_claim_port
mg_boot_avd mission_geo_phone
echo "[regression-suite] Emulator ready: $ANDROID_SERIAL"

# ── Firebase Emulator Suite ──────────────────────────────────────────────────
# Singleton guard: refuse to boot a second suite if one is already running.
for port in 9099 8080 9000 4000; do
  if lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "[regression-suite] Firebase emulator port $port already in use — reusing existing suite." >&2
    FB_ALREADY_RUNNING=1
    break
  fi
done
FB_ALREADY_RUNNING="${FB_ALREADY_RUNNING:-0}"

FB_PID=""
if [[ "$FB_ALREADY_RUNNING" == "0" ]]; then
  echo "[regression-suite] Starting Firebase Emulator Suite…"
  cd "$REPO_ROOT"
  nohup firebase emulators:start --project mission-geo > /tmp/fb-emulators-regression.log 2>&1 &
  disown
  FB_PID=$!

  echo "$FB_PID" > /tmp/fb-emulators-regression.pid

  until grep -q "All emulators ready" /tmp/fb-emulators-regression.log 2>/dev/null; do
    if grep -qE "Error|EADDRINUSE|already in use" /tmp/fb-emulators-regression.log 2>/dev/null; then
      echo "[regression-suite] Firebase emulator failed to start:" >&2
      tail -30 /tmp/fb-emulators-regression.log >&2
      mg_release_port
      exit 1
    fi
    sleep 2
  done
  echo "[regression-suite] Firebase Emulator Suite ready."
else
  echo "[regression-suite] Reusing existing Firebase Emulator Suite."
fi

# ── Cleanup trap ─────────────────────────────────────────────────────────────
_cleanup() {
  echo ""
  echo "[regression-suite] Cleaning up…"
  if [[ -n "$FB_PID" && "$FB_ALREADY_RUNNING" == "0" ]]; then
    kill "$FB_PID" 2>/dev/null || true
    # Also kill any lingering firebase/java processes on our ports.
    for port in 9099 8080 9000 4000; do
      lsof -ti:"$port" | xargs -r kill -9 2>/dev/null || true
    done
  fi
  mg_release_port 2>/dev/null || true
  echo "[regression-suite] Cleanup done."
}
trap _cleanup EXIT INT TERM

# ── Run tests ────────────────────────────────────────────────────────────────
cd "$REPO_ROOT"

echo ""
echo "[regression-suite] Running: flutter test $TEST_TARGET"
echo "[regression-suite] Tier: $TIER | Device: $ANDROID_SERIAL"
echo ""

DART_DEFINES=(
  "--dart-define=APP_FLAVOR=dev"
  "--dart-define=USE_FIREBASE_EMULATOR=true"
  "--dart-define=MG_TEST_MODE=true"
  "--dart-define=MG_TEST_SEED_PROFILE=allUnlocked"
  "--dart-define=MG_TEST_TIER=$TIER"
)

set +e
flutter test "$TEST_TARGET" \
  --flavor dev \
  "${DART_DEFINES[@]}" \
  --reporter expanded \
  -d "$ANDROID_SERIAL"
FLUTTER_EXIT=$?
set -e

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
if [[ $FLUTTER_EXIT -eq 0 ]]; then
  echo "╔══════════════════════════════════════════════╗"
  echo "║  ✓  Regression suite PASSED ($TIER)          ║"
  echo "╚══════════════════════════════════════════════╝"
else
  echo "╔══════════════════════════════════════════════╗"
  echo "║  ✗  Regression suite FAILED ($TIER)          ║"
  echo "║  Check output above for failing scenarios.   ║"
  echo "╚══════════════════════════════════════════════╝"
fi
echo ""

exit $FLUTTER_EXIT
