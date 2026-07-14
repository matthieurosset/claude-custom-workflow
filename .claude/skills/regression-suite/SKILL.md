---
name: regression-suite
description: Run the Mission Geo deterministic regression suite on the phone AVD + Firebase emulator. Use when you want to run smoke tests before releasing, after a code change, or to debug a failing scenario. Paramétrable --tier smoke|full and --only <feature>.
---

# Regression Suite — Mission Geo

## Overview

The regression suite is a set of Flutter integration tests that run against a
**deterministic seeded state** (sqlite + SharedPreferences wiped and re-populated
by `TestMode.initialize()`) so every run starts from the same baseline regardless
of previous state. Firebase is pointed at the local emulator suite — no network,
no real accounts.

**This skill is also invoked as a mandatory pre-flight gate in the
`android-releaser` skill before any AAB upload. A FAIL aborts the release.**

## Tier system

| Tier | When | What |
|---|---|---|
| `smoke` | Default, every release | ~8 scenarios: cold start, each mode entry point, Découverte picker regression |
| `full` | Deep validation, gated datasets | All smoke + Swiss/Austria/Croatia/Italy dataset scenarios (requires `adb push` staging) |

## Prerequisites

Already provisioned on this machine:
- Firebase CLI (`firebase --version` ≥ 13)
- `node` ≥ 20, `java` ≥ 17
- `firebase.json` with `emulators` block (auth 9099, firestore 8080, database 9000)
- `lib/core/testing/` (test_mode, test_seed, test_ids) — no-op in prod
- `integration_test/scenarios/all_scenarios.dart` — aggregator runner
- Shared emulator pool: `.claude/skills/shared/emulator-pool.sh`

## Run the suite

```bash
.claude/skills/regression-suite/run.sh [--tier smoke|full] [--only <feature>]
```

Examples:
```bash
.claude/skills/regression-suite/run.sh                        # smoke tier (default)
.claude/skills/regression-suite/run.sh --tier full            # full tier
.claude/skills/regression-suite/run.sh --only discovery       # single feature file
```

The script:
1. Sources the emulator pool and claims a port (`mg_claim_port`).
2. Boots `mission_geo_phone` AVD (`mg_boot_avd mission_geo_phone`).
3. Starts the Firebase Emulator Suite (singleton guard: refuses to start a second one).
4. Runs `flutter test integration_test/scenarios/...` with the correct dart-defines.
5. Parses PASS/FAIL per scenario and prints a summary table.
6. Always cleans up (release port + kill Firebase emulator) even on failure.

## Manual invocation (one-liner)

If you need to run without the script (emulator + Firebase already running):

```bash
flutter test integration_test/scenarios/all_scenarios.dart \
  --flavor dev \
  --dart-define=APP_FLAVOR=dev \
  --dart-define=USE_FIREBASE_EMULATOR=true \
  --dart-define=MG_TEST_MODE=true \
  --dart-define=MG_TEST_SEED_PROFILE=allUnlocked \
  --dart-define=MG_TEST_TIER=smoke \
  --reporter expanded \
  -d "$ANDROID_SERIAL"
```

Run a single feature:
```bash
flutter test integration_test/scenarios/discovery_test.dart \
  --flavor dev --dart-define=APP_FLAVOR=dev \
  --dart-define=USE_FIREBASE_EMULATOR=true \
  --dart-define=MG_TEST_MODE=true \
  --reporter expanded \
  -d "$ANDROID_SERIAL"
```

## How to add a scenario

1. Create `integration_test/scenarios/<feature>_test.dart`.  Name your
   `testWidgets` calls with the prefix `[smoke]` or `[full]` to indicate tier.

   ```dart
   testWidgets('[smoke] MyFeature loads without crash', (tester) async {
     await bootApp(tester);
     // navigate…
     // assert…
   });
   ```

2. Import the new file in `integration_test/scenarios/all_scenarios.dart` and
   call its `main()` from the aggregator's `main()`.

3. If the scenario needs a testId on a widget, add the `const` string to
   `lib/core/testing/test_ids.dart` (naming: `mg.<zone>.<element>`), add
   `String? testId` to the relevant design-system component, and wire
   `key: testId != null ? ValueKey(testId) : null` on the root widget.

4. Run `flutter analyze` to verify zero errors/warnings before committing.

## Seed profiles

| Profile | What | Use for |
|---|---|---|
| `allUnlocked` | All 5 continents at level 1, 50 000 miles | Default — any deep screen |
| `fresh` | Install neuve — 0 miles, no continent unlocked | Onboarding / unlock flow |
| `midProgress` | Alias for allUnlocked in v1 | Progression scenarios (expand later) |

Set via `--dart-define=MG_TEST_SEED_PROFILE=<profile>`.

## Debugging a failing scenario

1. Run with `--reporter expanded` (already the default in the script).
2. Read the failure message — `pumpUntilFound` prints the last 30 widget types
   before timing out.
3. If a testId is not found, verify:
   - The testId is wired on the correct widget (check `testIds.dart` + the
     component code).
   - The navigation actually reached the expected screen (add a temporary
     `tester.printToConsole(tester.allWidgets.map(...).join())` call).
4. Firebase emulator issues: read `/tmp/fb-emulators.log` (errors show as
   `PERMISSION_DENIED` with a line/column reference).
5. Seed issues: add `debugPrint` to `TestSeed.apply()` and rerun.
