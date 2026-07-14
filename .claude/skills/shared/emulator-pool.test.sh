#!/usr/bin/env bash
# emulator-pool.test.sh — hermetic regression tests for the classification logic.
#
# Focus: a driver (flutter/dart) process can stay ATTACHED to an emulator long
# after its owning session has died (reparented to init), with a dead keeper and
# an ancient lease. The pool must NOT treat such an ORPHAN as "active" — otherwise
# a leaked `flutter run` pins a pool port forever (the v1 failure mode, in a new
# disguise). See the 2026-05-25 immich-flutter-on-5554 incident.
#
# Hermetic: a private MG_LOCK_DIR, a fake `adb` (always reports the emulator
# present), and fake `dart` driver processes built by copying bash to a file
# named "dart" (so /proc/<pid>/comm == "dart"). No real emulator is touched.
#
#   bash .claude/skills/shared/emulator-pool.test.sh
# Exits 0 if all pass, non-zero otherwise.

set -u
HERE="$(cd "${BASH_SOURCE%/*}" && pwd)"

# ---- hermetic environment (must be set BEFORE sourcing the lib) -------------
TMP="$(mktemp -d)"
export MG_LOCK_DIR="$TMP/locks"
mkdir -p "$MG_LOCK_DIR"

# fake adb: pretend the queried emulator always exists (emu_alive=1), no-op kill.
cat > "$TMP/adb" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/adb"
export MG_ADB="$TMP/adb"

# fake driver binary: a copy of bash named "dart" ⇒ comm == "dart".
DART="$TMP/dart"
cp "$(command -v bash)" "$DART"

export MG_LEASE_TTL=180
export MG_KEEPER_MAX=14400      # 4 h — the orphan cut-off for an attached driver
export MG_ACTIVE_LOG_WINDOW=300

# shellcheck disable=SC1090
source "$HERE/emulator-pool.sh"

PIDS=()
cleanup() { local p; for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT

# Spawn a fake driver whose cmdline contains "emulator-<port>" and stays alive.
# `... & wait` defeats bash's single-command exec optimisation so comm stays "dart".
spawn_driver() {
  local port="$1"
  "$DART" -c 'sleep 600 & wait' "emulator-$port" >/dev/null 2>&1 &
  local pid=$!
  PIDS+=("$pid")
  # let /proc settle, then sanity-check we actually faked comm=dart*
  local i comm
  for i in 1 2 3 4 5 6 7 8 9 10; do
    comm=$(cat "/proc/$pid/comm" 2>/dev/null); [ -n "$comm" ] && break; sleep 0.1
  done
  case "$comm" in dart*) ;; *) echo "SETUP ERROR: fake driver comm=$comm (expected dart*)" >&2; exit 99 ;; esac
}

# Fake driver binary named "adb" (comm == "adb") — used to test the logcat
# attachment carve-out without touching a real adb/emulator. Lives in its own
# subdir since $TMP/adb is already taken by the classify-tests' fake adb above
# (comm is derived from the executed file's basename, not its full path, so
# this still reports comm=="adb").
mkdir -p "$TMP/adbdriver"
ADB_FAKE="$TMP/adbdriver/adb"
cp "$(command -v bash)" "$ADB_FAKE"

# Spawn a fake `adb -s emulator-<port> <subcommand>` process (comm "adb",
# cmdline containing the given subcommand) that stays alive.
spawn_fake_adb() {
  local port="$1" subcommand="$2"
  "$ADB_FAKE" -c 'sleep 600 & wait' -s "emulator-$port" "$subcommand" >/dev/null 2>&1 &
  local pid=$!
  PIDS+=("$pid")
  local i comm
  for i in 1 2 3 4 5 6 7 8 9 10; do
    comm=$(cat "/proc/$pid/comm" 2>/dev/null); [ -n "$comm" ] && break; sleep 0.1
  done
  case "$comm" in adb) ;; *) echo "SETUP ERROR: fake adb comm=$comm (expected adb)" >&2; exit 99 ;; esac
}

set_lease_age() {  # port, seconds-ago
  touch -d "@$(( $(date +%s) - $2 ))" "$MG_LOCK_DIR/$1.lease"
}
mk_owned()   { : > "$MG_LOCK_DIR/$1.owned"; }
mk_keeper_alive() {  # spawn a live keeper proxy and record its pid
  sleep 600 & local pid=$!; PIDS+=("$pid"); echo "$pid" > "$MG_LOCK_DIR/$1.keeperpid"
}
rm_keeper()  { rm -f "$MG_LOCK_DIR/$1.keeperpid"; }

PASS=0; FAIL=0
# assert classify(port) returns expected rc (0=reclaimable,1=busy/active,2=free)
assert_rc() {
  local label="$1" port="$2" want="$3" why got
  why=$(mg__classify_port "$port"); got=$?
  if [ "$got" -eq "$want" ]; then
    echo "  PASS  $label  (rc=$got: $why)"; PASS=$((PASS+1))
  else
    echo "  FAIL  $label  (rc=$got want=$want: $why)"; FAIL=$((FAIL+1))
  fi
}
assert_fn() {  # label, expected-rc, function, port
  local label="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then echo "  PASS  $label  (rc=$got)"; PASS=$((PASS+1))
  else echo "  FAIL  $label  (rc=$got want=$want)"; FAIL=$((FAIL+1)); fi
}

echo "== classify() =="

# T1 — THE BUG: orphan driver attached, keeper dead, lease 5 h old, owned present.
#      Must be RECLAIMABLE (rc 0), not "active".
P=15991; spawn_driver $P; rm_keeper $P; mk_owned $P; set_lease_age $P 18000
assert_rc "T1 orphan driver (dead keeper, 5h lease) ⇒ RECLAIMABLE" $P 0

# T2 — live claim: driver attached + LIVE keeper + fresh lease ⇒ active (rc 1).
P=15992; spawn_driver $P; mk_keeper_alive $P; mk_owned $P; set_lease_age $P 5
assert_rc "T2 live keeper + driver ⇒ active" $P 1

# T3 — recent claim courtesy: driver attached, no keeper, lease only 60 s old
#      (< KEEPER_MAX) ⇒ still active (rc 1). Protects a just-launched session.
P=15993; spawn_driver $P; rm_keeper $P; mk_owned $P; set_lease_age $P 60
assert_rc "T3 driver + fresh lease (no keeper) ⇒ active" $P 1

# T4 — plain orphan, NO driver, dead keeper, 5 h lease, owned ⇒ RECLAIMABLE (rc 0).
#      Pre-existing behaviour; must stay green.
P=15994; rm_keeper $P; mk_owned $P; set_lease_age $P 18000
assert_rc "T4 stale, no driver ⇒ RECLAIMABLE" $P 0

echo "== mg__live_attached() (used by the reclaim guards) =="
# T5 — orphan driver must NOT count as live (so doctor/try_claim can reclaim).
P=15995; spawn_driver $P; rm_keeper $P; mk_owned $P; set_lease_age $P 18000
assert_fn "T5 mg__live_attached(orphan) ⇒ NOT live (rc 1)" 1 mg__live_attached $P
# T6 — fresh-lease driver counts as live (guard must protect it).
P=15996; spawn_driver $P; rm_keeper $P; mk_owned $P; set_lease_age $P 30
assert_fn "T6 mg__live_attached(fresh) ⇒ live (rc 0)" 0 mg__live_attached $P

echo "== adb-logcat attachment carve-out (online-duo-up.sh's persistent pin) =="

# T7 — a persistent `adb -s emulator-<port> logcat` attachment DOES count as
#      a driver (this is the whole point of the carve-out: a harness with no
#      flutter/dart/java driver stays "in use" across a session handoff).
P=15997; spawn_fake_adb $P logcat
assert_fn "T7 mg__driver_attached(adb logcat) ⇒ attached (rc 0)" 0 mg__driver_attached $P

# T8 — a short-lived-style `adb -s emulator-<port> get-state` attachment must
#      NOT count — this is the exact self-detection bug the original "NOT adb"
#      exclusion exists to prevent (see mg__driver_attached's doc comment).
#      Using get-state's own subcommand name here as a stand-in for "any
#      non-logcat adb invocation" (install/shell/emu kill behave the same).
P=15998; spawn_fake_adb $P get-state
assert_fn "T8 mg__driver_attached(adb get-state) ⇒ NOT attached (rc 1)" 1 mg__driver_attached $P

# T9 — end-to-end: this is the exact bug being fixed. Keeper dead, lease just
#      past MG_LEASE_TTL (180s — the "reaps after ~180s" symptom's threshold),
#      but a logcat attachment is present and its age is well under
#      MG_KEEPER_MAX (4h — beyond that even a renewing keeper would have given
#      up, see mg__live_attached's doc comment; T1 exercises that far edge with
#      a plain driver). Must classify as active (rc 1), NOT reclaimable —
#      proves the carve-out actually protects a port through
#      mg__classify_port, not just the low-level mg__driver_attached helper.
P=15999; spawn_fake_adb $P logcat; rm_keeper $P; mk_owned $P; set_lease_age $P 200
assert_rc "T9 logcat attachment (dead keeper, lease just past TTL) ⇒ active, not reclaimable" $P 1

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
