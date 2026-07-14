---
name: visual-validation-android
description: Use when modifying UI/visual elements in this Mission Geo Flutter app and the change must be verified on a real Android render — fixing a UI bug, changing styling/layout, adding a screen, or before claiming a visual fix is done.
---

# Visual Validation on Android

## Overview

Closes the loop between code and what the user sees. Boot the project's headless Android emulator, drive the app via ADB (or mobile-mcp), screenshot, read the image, modify, repeat. **Never claim a UI change works without a screenshot showing it.**

## When to Use

- About to assert "rendering is fixed", "layout looks right", or any visual claim
- Building or modifying a page, widget, padding, theme color
- Investigating a user-reported visual bug ("titre sous la barre", "bouton mal placé")
- Need to compare a page against the rest of the app for cohérence

**Skip for:** pure-logic refactors (services, providers, tests) where no UI is touched.

## Prerequisites (already provisioned)

- **3 canonical AVDs**, Android 16 (API 36, **`google_apis`** — never `google_apis_playstore`, whose Play Store self-updates GMS mid-session and kills foreground apps), x86_64, portrait, in `~/.android/avd/`:
  - `mission_geo_phone` — Pixel 7 (1080×2400, density 420), 2 GB RAM
  - `mission_geo_tablet7` — Nexus 7 2013 (1200×1920, density 320), 1.5 GB RAM
  - `mission_geo_tablet10` — Pixel C (2560×1800, density 320), 1.5 GB RAM
- **Port pool helper** `.claude/skills/shared/emulator-pool.sh` — atomic 3-port (5554/5556/5558) allocation; source it instead of hand-rolling a port loop (see step 1).
- `ANDROID_HOME` + platform-tools/cmdline-tools on PATH (`~/.bashrc`); Flutter via fvm; `/dev/kvm` accessible (ACL on user); `mobile-mcp` registered for this project (`claude mcp list`); `scrcpy` at `/usr/bin/scrcpy` (ask the user to `! sudo apt install -y scrcpy` if missing).

Recreating an AVD from scratch, running several emulators at once, swapping AVDs on a held port for tablet checks, and the Impeller/Skia APK-install caveat: **`references/emulator-lifecycle.md`**.

## Core Loop

```
Boot emulator (once per session)
   │
   ▼
flutter run with hot reload (once per session) ──► Screenshot ──► Read image
                                                       ▲             │
                                                       │             ▼
                                            echo r > FIFO ◄── Modify code
                                                       │
                                                       ▼
                                  Need user-visible validation? ── yes ──► Launch scrcpy mirror
                                                       │ no                       │
                                                       ▼                          ▼
                                         User validates the feature ◄────────────┘
                                                       │
                                                       ▼
                                  Quit scrcpy + flutter + shut down emulator
```

Stop iterating only when the screenshot matches the expected rendering.
Shut the emulator down (and scrcpy if it was launched) once the user has validated the feature — leaving them running consumes RAM/CPU and may interfere with the next session.

## Commands

### 1. Boot emulator headless (start of session)

> **Atomic port allocation (memory `feedback_emulator_must_be_free`).** Multiple agents run in parallel. Use the shared pool helper — it claims one of **3 ports (5554 / 5556 / 5558)** with an `flock` held for your **whole session**, boots `-read-only`, and **waits 3 min then retries indefinitely** if all 3 ports are busy. Never hand-roll a port loop, never assume a port is idle, never kill an instance you didn't boot.

```bash
# Source the shared pool, claim a port, boot the phone on it.
source "$(git rev-parse --show-toplevel)/.claude/skills/shared/emulator-pool.sh"
mg_claim_port                       # blocks until it owns one of 5554/5556/5558
mg_boot_avd mission_geo_phone       # read-only, waits for full boot
EMULATOR_PORT=$MG_PORT              # the rest of this skill keeps using $EMULATOR_PORT
echo "Phone up on emulator-$EMULATOR_PORT"
```

Claude shells are non-interactive so `~/.bashrc` PATH exports don't load — the pool helper references binaries by absolute path for you; that's why it exists instead of raw commands. `mg_claim_port` exports `$ANDROID_SERIAL` too. **Each Bash tool call is a fresh shell**, so re-`source` the helper (and re-set `MG_PORT=$EMULATOR_PORT`) in any later call using `mg_swap_avd` / `mg_release_port`. Plain `adb`/`flutter` calls only need `$EMULATOR_PORT`.

**Long investigation session with no `flutter run`/`dart` process attached** (pure ADB or mobile-mcp driving) — call `mg_keepalive_start` immediately after `mg_claim_port`. Without a live dart driver, the pool's self-healing reclaim treats the port as idle and kills it after ~3 min, even mid-investigation. <!-- trigger: Inspector lost emulator twice mid-investigation, lease reclaimed, 2026-07-10 -->

**Also mandatory the moment a check involves manual multi-step ADB navigation** — even with a `flutter run` driver attached, a slow sequence of `uiautomator dump` + manual taps between reloads can outrun the reaper's idle window. Don't reserve `mg_keepalive_start` for driverless sessions only. <!-- trigger: pool reaper reclaimed a live multi-step ADB session, 2026-07-12 -->

**Remember `EMULATOR_PORT` for the rest of the session** — note it in a status update so a context compaction can't lose it. If you lose it, recover via `adb devices` + cross-reference `/tmp/emulator-*.log`. Cold boot ~30–60 s; screencaps ~200 ms after.

**Do not** fall back to a physical device if boot fails (almost always a PATH issue — fix the command) and **do not** kill an instance you didn't boot — other agents own the other two ports.

### 2. Start `flutter run` with hot reload (default workflow)

Hot reload turns each iteration into ~1 s instead of ~30–60 s for a full APK rebuild, AND preserves the app's navigation state. **Use this by default**; only fall back to a full rebuild when hot reload can't pick up a change (plugin/native/asset changes — see `references/interaction-commands.md`).

```bash
# --- Setup ONCE per session, after the emulator is booted ---
FIFO=/tmp/flutter-stdin-$EMULATOR_PORT
[ -p "$FIFO" ] || mkfifo "$FIFO"
( exec 9>"$FIFO"; while :; do sleep 3600; done ) &        # keeps FIFO open so flutter doesn't see EOF
echo $! > /tmp/flutter-keeper-$EMULATOR_PORT.pid
nohup flutter run -d emulator-$EMULATOR_PORT < "$FIFO" > /tmp/flutter-$EMULATOR_PORT.log 2>&1 &
echo $! > /tmp/flutter-$EMULATOR_PORT.pid
disown
until grep -q "Flutter run key commands" /tmp/flutter-$EMULATOR_PORT.log 2>/dev/null; do sleep 2; done
```

```bash
# --- Iteration: after editing Dart code ---
echo r > /tmp/flutter-stdin-$EMULATOR_PORT      # hot reload (~1 s, keeps state)
sleep 2
adb -s emulator-$EMULATOR_PORT exec-out screencap -p > /tmp/mg-$EMULATOR_PORT.png
```

`tail -20 /tmp/flutter-$EMULATOR_PORT.log` should show "Reloaded N libraries" — "Reloaded 0 of N" means the change wasn't picked up. Use `R` (hot restart, ~3–5 s, rebuilds the isolate from `main()`) when you changed top-level providers/routes/constants, or the app is in a weird state:

```bash
echo R > /tmp/flutter-stdin-$EMULATOR_PORT
sleep 5
```

Full setup transcript and the full-rebuild fallback (stop flutter, `flutter build apk --debug`, reinstall, restart): **`references/interaction-commands.md`**.

### 3. Inspect what's on screen — `list_elements_on_screen` first, screenshot only when needed

**Default to `mcp__mobile__mobile_list_elements_on_screen`** — it returns the accessibility tree as compact JSON (~2-5 KB) with each element's `label`, `type`, and **device-coordinate** `bounds`. That's enough for almost every functional check ("is the section gone?", "did the button render?") at a fraction of the token cost of an image.

**Take a screenshot only when** the question is genuinely visual — alignment, padding, color, overflow, layered z-order — or when the element you need is missing from the tree. Use `mcp__mobile__mobile_take_screenshot` (delivers the image directly into the conversation).

**Target `resource-id` first.** Canonical design-system components (`AccentButton`, `PrimaryButton`, `SecondaryButton`, `MenuButton`, `PickerOptionCard`, `BottomNavBar` tabs, `HomeHeaderBar` pills, app-bar back buttons, home/défi tiles) carry a stable `testId` surfaced as `Semantics(identifier: ...)`, which Android reports as `resource-id` in `uiautomator dump` and as the element's identifier in `list_elements_on_screen`. Match on `resource-id` before touching `bounds`/coordinates — it survives layout shifts and locale changes. See `lib/core/testing/test_ids.dart` for the full registry.

**A11y-tree blind spots in Flutter**: a `GestureDetector` / `InkWell` with no `Semantics` wrapping (or no `testId` passed) won't appear with a `resource-id` in `list_elements` (common offenders: custom-painted regions in the drawing/searching games, scroll handles, one-off page-local widgets). Fall back to a screenshot to locate it, or coordinate-tap via `bounds` as a last resort.

**Coordinate gotcha**: the screenshot rendered in your context is NOT 1:1 pixels with the device. Never eyeball a tap from the screenshot image. Either take bounds from `list_elements`/`uiautomator dump` (already device pixels), or confirm via `mcp__mobile__mobile_get_screen_size` and compute the exact ratio `device_size / rendered_size` before tapping — recompute every session, it varies by AVD. <!-- trigger: taps ratés validation chrono Défi (Inspector, x2), 2026-07-08 -->

### 4. Navigate (tap, swipe, type)

```text
mcp__mobile__mobile_click_on_screen_at_coordinates(device, x, y)
mcp__mobile__mobile_swipe_on_screen(device, direction, [x, y, distance])
mcp__mobile__mobile_press_button(device, button)        # BACK, HOME, ENTER, …
mcp__mobile__mobile_type_keys(device, text, submit)     # types into focused element; submit=true presses ENTER after
```

Click the **center** of `list_elements`' bounds (`x + width/2`, `y + height/2`). **Prefer `uiautomator dump` + exact `bounds=` extraction over screenshot-pixel-coordinate taps** — for invisible-to-a11y targets, only fall back to screenshot-derived coordinates in `click_on_screen_at_coordinates` when a UI dump genuinely has no matching node. <!-- trigger: keepalive/manual-navigation session reclaimed by pool reaper, 2026-07-12 -->

Raw-ADB fallback for when mobile-mcp isn't loaded: **`references/interaction-commands.md`**.

### 5. Mirror to the user's screen with scrcpy — the user's own visual validation

> **Standard close-out for UI work (memory `feedback_user_tests_via_scrcpy`):** visual validation is **two passes, in order**. First YOU validate visually via screenshots + self-critique — mandatory, never skipped. **Then**, once your pass is green, open a scrcpy mirror so the **user** validates the rendering too, before merge. Never tell the user "je te laisse faire la validation" as if the whole visual check were theirs.

Launch it: as the close-out of any UI task once your own screenshot pass is green, before asking the user to validate an iteration, or when they ask "montre-moi". Skip it: mid-iteration while you alone are screenshotting/tweaking (still open it for the final validation), and for headless CI/batch runs.

Full launch script + `DISPLAY`/troubleshooting notes: **`references/interaction-commands.md`**.

### 6. Shut down (after the feature is validated)

Once the user has validated the visual change AND any merge/push step in `git-workflow-branch-worktree` is done, tear down **your own session only**, in order: quit scrcpy if launched → quit `flutter run` via the FIFO (`echo q`) → kill the FIFO keeper → release your port via `mg_release_port` (never a bare `adb emu kill`, it leaves the pool lock held — see `references/emulator-lifecycle.md` for the exact commands).

**Do not** shut down between iterations on the same task — only when the task is complete and the user is done reviewing (booting again costs 30–60 s). **Do not** issue a global `pkill qemu-system` or `adb kill-server` — those nuke other agents' emulators and break their session. Same for scrcpy: target your own `-s emulator-$EMULATOR_PORT` instance.

## Crash Recovery / Zombie Reaping

A crashed emulator's `qemu-system` process does not die on its own — it lingers as a ~3 GB zombie, and `adb emu kill` is a no-op on it. Rebooting on the same port without reaping first stacks a second qemu → RAM exhaustion → more crashes. The pool helpers (`mg_boot_avd`, `mg_kill_current`, `mg_swap_avd`, `mg_emu_swap`) already reap before booting, so manual intervention should never be needed. If the spiral already happened: `mg_emu_doctor` (auto-reaps everything) or `mg__kill_port_qemu <port>` (targeted). Full detail: **`references/emulator-lifecycle.md`**.

## Validation Discipline

1. **Cheap checks first.** For a functional question, `list_elements_on_screen` (~2 KB JSON) is enough; no screenshot needed. Reach for `take_screenshot` only when the question is genuinely about pixels.
2. **Screenshot the broken state first** when you do screenshot. Without a baseline, you can't prove improvement.
3. **Find a reference page in the same module** that already renders correctly. Match that pattern; don't invent a new one. (Example: when fixing `lib/pages/modes/adventure/adventure_drawing_game_page.dart`, look at `lib/pages/modes/adventure/adventure_typing_game_page.dart`.)
4. **Verify after every code change** — `list_elements` for "did the right thing happen?", screenshot for "does it look right?". No "I'm sure this works."
5. **Test more than the happy path.** Loading state, empty state, error state. Use `flutter run` log for runtime errors (`tail /tmp/flutter-$EMULATOR_PORT.log`).
6. **Compare cohérence:** widget proportions, padding, AppBar style, icon colors should match neighbouring pages. <!-- trigger: false B6 regression from screenshot round-trip latency, 2026-07-08 -->
7. **Real-time/wall-clock behavior (timers, animation-scale tests) needs log-timestamp evidence, not screenshot-interval comparisons.** Tool round-trip latency between two screenshots can exceed the interval you're measuring, producing a false regression. Read the actual elapsed time from the Flutter log (e.g. a logged `duration_ms`) instead of timing screenshots.

## Common Mistakes

<!-- trigger: inspecteur shop-icon, build stale + emulator reclaimed, 2026-07-08 -->

| Symptom | Cause | Fix |
|---|---|---|
| Tap lands on the keyboard, not the button | Soft keyboard pushed layout up; cached coords stale | Re-dump UI after keyboard appears, or `input keyevent 4` first |
| Screenshot is all-black or stale | Screencap ran before frame committed | Add `sleep 1` after navigation, or wait for an `adb logcat` "frame" event |
| Reload runs but the screen doesn't reflect the change | "Reloaded 0 of N libraries" — change is in a code path the reloader can't patch | Try `R` (hot restart). If still wrong → full rebuild fallback |
| `flutter run` exits immediately after launch | FIFO had no writer when launched, so flutter saw EOF on stdin | The keeper-loop in the setup MUST start before `flutter run`; don't reorder |
| `list_elements_on_screen` doesn't show the widget you can clearly see in the screenshot | Either it's outside the resource-id rollout (shop/carnet/lobby/ranked/debug-launcher/game canvases — phase 2, not yet covered), or a one-off `GestureDetector`/`InkWell` with no `Semantics` wrapping | Canonical components (buttons, `PickerOptionCard`, app-bar back buttons, `BottomNavBar` tabs, home/header chrome) DO expose a `resource-id` via `test_ids.dart` — re-check the id first (§3). Only fall back to a screenshot + `click_on_screen_at_coordinates` with device-pixel coords (1080×2400 for `mission_geo_phone`) for genuinely uncovered widgets <!-- trigger: stale row detected by shipper drift check, 2026-07-14 --> |
| Click at `(x, y)` from the screenshot doesn't land on the target | Image rendered in your context isn't 1:1 with device pixels | Multiply by `device_size / rendered_size`, or just take the bounds from `list_elements` (already in device coords) |
| ANY custom in-app keyboard/canvas (not just geordle) — blind `adb shell input tap`/`input text` misses or hits the wrong target | Synthetic taps carry no OS IME awareness; only a UI dump reveals the widget's real bounds | Always `uiautomator dump` (or `list_elements_on_screen`) for bounds BEFORE tapping any custom keyboard/canvas — never send blind coordinates |
<!-- trigger: 2 inspectors, ~570px tap offset, 2026-07-11 -->
| Custom on-screen keyboard (e.g. geordle) — some rows/keys never respond to `adb shell input tap`/`input text` on a headless AVD | Synthetic touch/key events don't always reach custom Flutter keyboard widgets — reliability varies row by row | For text-entry-heavy screens, seed the app state via `run-as <appId> sqlite3` (like the regression tests) instead of driving the keyboard; reserve real ADB taps for single-tap widgets |
<!-- trigger: geordle keyboard unresponsive to synthetic taps on headless AVD, inspection Pays du jour, 2026-07-10 -->
| Typing game keyboard ignores `adb shell input text`/`keyevent` entirely | `FlagTypingKeyboard` is a custom in-app Flutter widget, not the Android system IME | Tap the rendered letter buttons (coordinates via `uiautomator dump`); submit by tapping the country-name suggestion chip in `FlagTypingCarousel` — there's no Enter key |
<!-- trigger: inspector perk-validation session, 2026-07-11 -->
| Downsampled pixel-diff between frames reports "frozen" / no visual change | Coarse pixel-diff averages hide real motion under large uniform-color regions (ocean, landmass fill) | Treat pixel-diff as a hint only — confirm freeze/motion by directly reading two frames' images, not the diff score |
<!-- trigger: 2 false freeze positives, inspectors, 2026-07-11 -->
| Need a deterministic game state (specific round/stat/mode) to repro or screenshot — plain game tile in the Debug launcher starts a random round | Home tiles (e.g. "Classement · world") have no forced-stat picker | Use the Debug launcher's numbered screenshot-scenario buttons instead (e.g. "08 · Classement Population") — they pin the exact state via `ScreenshotConfig.scenario` |
<!-- trigger: inspector lost time hunting a deterministic classement round, 2026-07-14 -->

10 more incident rows (GMS self-update reboots, stale-worktree resolution, port conflicts, Impeller/`am start` crashes, onboarding sync hiccup, AppBar title clipping / FAB overlap, …): **`references/emulator-lifecycle.md`**, **`references/interaction-commands.md`**, **`references/common-mistakes-extra.md`**.

## Iteration Loop (the discipline that matters)

1. `list_elements_on_screen` (cheap) — describe what's there. If the question is functional, this may be enough on its own. If it's about pixels, also `take_screenshot`
2. `grep -rn` visible text/labels to find the source widget
3. Locate a sibling page that does the right thing — that's your spec
4. Make the **smallest** change that aligns with the sibling
5. `echo r > FIFO` (hot reload). Verify: re-run `list_elements_on_screen` for the functional check; screenshot only if the change is visual. If hot reload reports "Reloaded 0 of N", try `R`; if still off, fall back to full rebuild
6. If still wrong, **go back to step 3** — don't stack fixes blindly
7. Only claim done when the verification matches expectation; only commit after that
8. After the user validates the feature (and any merge/push is complete), **shut the emulator (and scrcpy if launched) down** — see §6

## Red Flags — STOP and re-screenshot

- "The diff looks correct so it must work" → take the screenshot
- "Hot reload probably picked it up" → take the screenshot
- "It's just a padding change" → take the screenshot
- About to commit without a post-fix screenshot → take the screenshot

## Red Flags — STOP and shut down

- Task validated by the user but emulator still running → `adb -s emulator-$EMULATOR_PORT emu kill` (only your port — never a port you didn't boot)
- About to end the session without checking `adb devices` → check it
- Leaving a backgrounded `flutter run` alive after the task is done → kill it
