---
name: online-security-validation
description: Use when modifying online multiplayer code, Firestore/RTDB rules, Cloud Functions for game rooms, or before claiming an online security/reliability fix is verified — runs the Firebase Emulator Suite + Dart integration tests to validate the rule and service contracts.
---

# Online Security Validation

## Overview

Mission Geo's online module enforces its security and reliability invariants at three levels: **Firestore rules** (per-field write authorization), **RTDB rules** (score monotonicity, replay window), and **Dart service code** (transactions, host watchdog, onDisconnect cleanup). Production rules are deployed via the Firebase CLI; testing them against real Firebase is destructive and slow, and prod cannot be exercised with predictable UIDs.

This skill closes the loop with the **Firebase Emulator Suite** + a Flutter integration test that drives two independent Firebase apps in the same process (one acting as Alice, the other as Bob), so every threat the audit identified has a deterministic, reproducible test. **Never claim an online security or reliability change is verified without a green run of `online_security_test.dart` against the emulator suite.**

## When to Use

- Any change to `firestore.rules` or `database.rules.json`
- Any change to `lib/core/services/firebase/firebase_game_room_service.dart`
- Any change to `lib/providers/online_game_provider.dart`'s game-room branch (joinRoom, host watchdog, scores)
- Adding/modifying a Cloud Function under `functions/` that touches `game_rooms` or `online_games`
- Before merging a PR that touches the online module
- After bumping `cloud_firestore`, `firebase_database`, or `firebase_auth`

**Skip for**: pure UI/lobby widget tweaks with no service or rule change; changes to other modes (défi, aventure, duel local).

## Prerequisites

Already provisioned on this machine:
- `firebase` (Firebase CLI) on PATH (`firebase --version` ≥ 13)
- `node` ≥ 20 (the suite needs it)
- `java` ≥ 17 (the suite emulator JVMs)
- `firebase.json` with the `emulators` block (auth 9099, firestore 8080, database 9000, ui 4000)
- `lib/core/services/firebase/firebase_emulator_setup.dart` reading `--dart-define=USE_FIREBASE_EMULATOR=true`
- `android/app/src/debug/res/xml/network_security_config.xml` whitelisting cleartext traffic to `10.0.2.2`/`localhost`/`127.0.0.1` (debug build only)

If anything is missing, do not patch it ad-hoc — re-run `firebase init emulators` or restore from git.

## Core Loop

```
Boot emulator suite (once per session)
   │
   ▼
flutter test integration_test/online_security_test.dart
   --dart-define=USE_FIREBASE_EMULATOR=true
   -d <android-emulator>
   │
   ▼
All tests green ──► Modify code/rules ──► re-run tests
                                   ▲
                                   │
                              Iterate
```

If a test fails, **read `firestore-debug.log` / `database-debug.log`** in the worktree before iterating — they have the exact rule rejection reason (`PERMISSION_DENIED`, evaluation error, line/column).

## Commands

### 1. Boot the emulator suite

The suite uses **fixed ports** (auth 9099, firestore 8080, database 9000, ui 4000), so only **one** can run per machine — treat it as a singleton (memory `feedback_emulator_must_be_free`). Verify the ports are free *before* booting; if a suite is already up, do **not** start a second one.

**Boot with `--project mission-geo-dev`.** The `flutter test` below runs `--flavor dev`, so the Dart clients resolve `DefaultFirebaseOptions.currentPlatform` to the **dev** project (`mission-geo-dev`). Three layers derive their identity from the boot `--project` and MUST match the clients or the suite silently breaks:
- **RTDB namespace** — clients write to `mission-geo-dev-default-rtdb`; `database.rules.json` and the RTDB triggers bind to `<project>-default-rtdb`. Boot with the wrong project and the client's namespace is auto-created rule-less (allow-all), so every *denial* test passes-through and fails, and `leaderboardScoreValidator` reads an empty DB.
- **Functions project path** — callables resolve to `/{project}/{region}/{fn}`; a mismatch is `NOT_FOUND`.
- **CF `databaseURL` pin** — `functions/index.js` pins `${GCLOUD_PROJECT}-default-rtdb…`, i.e. it follows the boot project automatically.

Booting `--project mission-geo` (prod id) against dev-flavor clients is exactly the split that made 20+ scenarios fail. (`.firebaserc` default is already `mission-geo-dev`, so a bare `firebase emulators:start` also works — the explicit flag documents intent.)

```bash
# from the worktree root

# Singleton guard: refuse to boot if a suite is already running on the fixed ports.
for port in 9099 8080 9000 4000; do
  if lsof -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Firebase suite port $port already in use — a suite is already running. Refusing to boot a second one (memory feedback_emulator_must_be_free)." >&2
    exit 1
  fi
done

nohup firebase emulators:start --project mission-geo-dev > /tmp/fb-emulators.log 2>&1 &
disown
echo $! > /tmp/fb-emulators.pid

# wait until ready
until grep -q "All emulators ready" /tmp/fb-emulators.log 2>/dev/null; do
  if grep -qE "Error|EADDRINUSE|already in use" /tmp/fb-emulators.log; then
    tail -30 /tmp/fb-emulators.log; exit 1
  fi
  sleep 2
done
echo READY
```

The UI is at `http://127.0.0.1:4000/` — handy to inspect Firestore docs and RTDB nodes during a failure. Each Java process holds a port; do not boot two suites at once on the same machine.

### 2. Secure a free Android emulator (never assume one is idle)

The integration test installs and drives the app on an Android emulator. A parallel agent (e.g. a `visual-validation-android` run) may already be driving one, so **claim your own port** via the shared pool — it allocates one of **3 ports (5554/5556/5558)** atomically with an `flock` held for your whole session, never colliding with another agent (memory `feedback_emulator_must_be_free`).

```bash
source "$(git rev-parse --show-toplevel)/.claude/skills/shared/emulator-pool.sh"
mg_claim_port                       # blocks (3-min retries) until it owns a port
mg_boot_avd mission_geo_phone       # read-only, waits for full boot
# $ANDROID_SERIAL is exported by the pool — every flutter test / adb call below targets it.
echo "Using $ANDROID_SERIAL (port $MG_PORT)"
```

Each Bash tool call is a fresh shell, so re-`source` the helper and re-set `MG_PORT=<your port>` in the teardown call (§5).

### 3. Run the suite

```bash
flutter test integration_test/online_security_test.dart \
  --flavor dev \
  --dart-define=USE_FIREBASE_EMULATOR=true \
  -d "$ANDROID_SERIAL" 2>&1 | tail -40
```

`--flavor dev` is required: the app is flavored (dev/prod) and the clients must resolve to `mission-geo-dev` — the same project the suite booted with (see §1). Do **not** pass `--flavor prod` / `APP_FLAVOR=prod` here; that repoints the clients at the prod project id and re-opens the namespace split.

Expected end of output:
```
00:0X +N: All tests passed!
```

The test boots two Firebase apps named `alice` and `bob`, signs each anonymously into the auth emulator (distinct UIDs guaranteed), and exercises every audit risk (see "Test matrix" below).

### 4. Iterate — rules hot-reload

The Firestore/RTDB emulator watches `firestore.rules` and `database.rules.json`. **Save the file, re-run the test** — no restart needed. Service-code changes go through the normal hot-restart of `flutter test` (full rebuild on each invocation; ~15 s).

### 5. Tear down

```bash
kill $(cat /tmp/fb-emulators.pid) 2>/dev/null
# Release ONLY your own port — kill the emulator AND drop the pool lock.
# Re-source the helper in this fresh shell and re-bind MG_PORT to your port.
source "$(git rev-parse --show-toplevel)/.claude/skills/shared/emulator-pool.sh"
MG_PORT="${ANDROID_SERIAL#emulator-}"   # e.g. emulator-5556 → 5556
mg_release_port
rm -f firestore-debug.log database-debug.log firebase-debug.log ui-debug.log
```

`*.log` is in `.gitignore`; the cleanup is cosmetic.

## Test Matrix

`integration_test/online_security_test.dart` runs eleven scenarios. Every one of them is mapped to a concrete production risk. **Do not delete a scenario.** When a test becomes irrelevant (e.g. you removed protocol versioning), update the scenario to test the new contract — never silently strip it.

| # | Risk | Asserted via |
|---|---|---|
| T1 | Two distinct UIDs can share a room state | `players.keys` contains both `alice.uid` and `bob.uid` after Bob joins |
| T2 | Direct write of `hostId` by a non-host (host steal) | `expectLater(throwsA(FirebaseException))` on Bob's `update({hostId, players.{bob}.isHost})` |
| T3 | `config` mutation by non-host | `updateConfig` from Bob throws (`NotHostException` or `permission-denied`) |
| T4 | Room deletion by non-host | Bob's `.delete()` throws |
| T5 | Score monotonicity (anti-cheat baseline) | `updateScore(2)` after `updateScore(5)` rejected by RTDB rule |
| T6 | Stale-host promotion succeeds | After backdating Alice's `lastHeartbeat` 5 min, `bob.tryClaimHost` flips `hostId` |
| T7 | Fresh-host promotion rejected | `bob.tryClaimHost` immediately after Alice's create throws `HostStillAliveException` |
| T8 | Expired-room join refused | After backdating `expiresAt`, `bob.joinRoom` throws `RoomExpiredException` |
| T9 | Incompatible `protocolVersion` refused | Recreate room with `protocolVersion: 99`, Bob's join throws `IncompatibleProtocolException` |
| T10 | RTDB replay (future timestamp) refused | Direct `set({lastUpdate: now+1h})` rejected by RTDB rule |
| T11 | Implausible score reverted by Cloud Function | After `startGame`, write 50 answers in <1 s ; the `scoreValidator` function reverts to 0 |

## Adding a New Scenario

1. Identify the threat in plain language. Prefer one assertion per scenario.
2. Add a `test('TN description', () async { … })` to the existing `group('Online security & reliability', …)`.
3. **Always** call `addTearDown(() => _purgeAll(alice, code))` so subsequent tests start from a clean room.
4. If the scenario needs an extra UID, spawn it via `_spawnClient('charlie')` in `setUpAll`.
5. Re-run the suite. Do not commit a flaky scenario.

## Cloud Functions and App Check Notes

The audit committed two Cloud Functions in `functions/index.js` :

- **`scoreValidator`** (RTDB onValueWritten on `/online_games/{roomCode}/scores/{uid}`) — reverts implausible writes by reading round timing from Firestore. In the emulator, the function omits its `region` so the trigger attaches to the emulator's default DB instance (otherwise the `function region is defined outside the database region, will not trigger` warning makes the test silently pass through). In production it pins `region: 'europe-west1'` to match the RTDB instance region.
- **`purgeExpiredRooms`** (`onSchedule('every 1 hours')`) — deletes Firestore rooms whose `expiresAt` is past plus their RTDB subtree, and rooms `finished` for >10 min. There is also an `onCall purgeRoomsNow` exposed for manual or test invocation.

Functions deploy : `firebase deploy --only functions`. Requires the project on the **Blaze (pay-as-you-go) plan** for scheduled functions and outbound network calls.

Firebase **App Check** is wired in `lib/core/services/firebase/firebase_app_check_setup.dart` with Play Integrity (Android release), DeviceCheck (iOS release), and the debug provider in dev builds. Activation is **skipped in emulator mode** (the suite doesn't validate App Check tokens). Console steps the user must do : enable Play Integrity for the project in Google Cloud Console, register the app's SHA-256 fingerprint in Firebase Console > Project Settings > App Check, and add debug device tokens via Firebase Console > App Check > Manage debug tokens.

## Common Failures and Fixes

| Symptom | Cause | Fix |
|---|---|---|
| `[firebase_auth/unknown] Cleartext HTTP traffic to 10.0.2.2 not permitted` | Debug network security config missing or wrong | Restore `android/app/src/debug/res/xml/network_security_config.xml` and confirm `android:networkSecurityConfig` is referenced in `android/app/src/debug/AndroidManifest.xml` with `tools:replace` |
| All tests fail at `runTransaction` with `permission-denied` and `firestore-debug.log` shows `Property <uid> is undefined on object` | A new rule helper accesses `players[uid]` directly when uid may be absent | Use `players.keys().hasAny([uid])` or the existing `isMember()`/`isMemberAfter()` helpers — never raw `[uid] != null` |
| `T6 host claim succeeds when previous host is stale` fails | Either the Dart `tryClaimHost` no longer reads `lastHeartbeat`, or the rule's `previousHostStale()` no longer compares against `request.time` | Revert the offending change; both layers must agree on the staleness threshold (`hostStaleThreshold = 30s`) |
| Suite refuses to boot with `EADDRINUSE` | A previous run is still alive | `pkill -f "firebase emulators"` (only your shell's child) or `kill $(cat /tmp/fb-emulators.pid)` |
| Tests pass locally but rules push to prod fails | Local rules use a CEL feature your prod project's rules version doesn't accept | Run `firebase deploy --only firestore:rules --dry-run` first; the diff is informative |
| Build hangs on `Running Gradle task 'assembleDebug'` for >2 min on first run after a `flutter clean` | Cold cache | Be patient on the first invocation; subsequent runs reuse the APK |

## Discipline

1. **Rules-first**: when adding an online feature, write the test scenario before the rule. The test forces you to articulate the threat model, not paint over it.
2. **Read the debug log**, don't guess. `firestore-debug.log` lines mention the rule line and column at which evaluation failed.
3. **Never `firebase deploy` straight after a green local run.** Confirm with the user explicitly. Production rules are a shared system — apply them only with intent.
4. **Never weaken a rule to make a flaky test pass.** Find the actual cause; the rule is the contract.

## Red Flags — STOP

- About to claim "the online flow is fixed" without running this suite → run it.
- About to deploy rules without showing the dry-run diff to the user → don't.
- Suite was green an hour ago and you've since touched 5 files → re-run before committing.
- A scenario you just added does not fail on the unfixed branch → it does not test what you think; rewrite it.

## Rapid Reference

```bash
# kick the cycle (suite = singleton; emulator = your own free port → $ANDROID_SERIAL, see §2)
nohup firebase emulators:start --project mission-geo-dev > /tmp/fb-emulators.log 2>&1 & disown
until grep -q "All emulators ready" /tmp/fb-emulators.log; do sleep 2; done
flutter test integration_test/online_security_test.dart \
  --flavor dev --dart-define=USE_FIREBASE_EMULATOR=true -d "$ANDROID_SERIAL"

# tear down
kill $(pgrep -f "firebase emulators") 2>/dev/null
[ -n "$ANDROID_SERIAL" ] && adb -s "$ANDROID_SERIAL" emu kill 2>/dev/null
rm -f *-debug.log
```
