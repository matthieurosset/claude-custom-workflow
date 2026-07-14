# Interaction commands — full scripts

Deep-dive detail for `visual-validation-android/SKILL.md` §2 ("Start `flutter run` with hot reload"), §4 ("Navigate"), and §5 ("Mirror with scrcpy"). Read this when you need the exact command transcripts rather than the condensed recipe.

## `flutter run` with hot reload — full setup

The trick across Bash invocations: `flutter run` must stay alive in the background, with its **stdin connected to a FIFO** so the next Bash call can write `r` (reload) / `R` (restart) / `q` (quit) into it.

```bash
# --- Setup ONCE per session, after the emulator is booted ---
FIFO=/tmp/flutter-stdin-$EMULATOR_PORT
[ -p "$FIFO" ] || mkfifo "$FIFO"

# Hold the FIFO writer open so flutter doesn't see EOF and exit. Without
# this, the FIFO closes the moment the spawning shell ends.
( exec 9>"$FIFO"; while :; do sleep 3600; done ) &
echo $! > /tmp/flutter-keeper-$EMULATOR_PORT.pid

# Launch flutter run reading from the FIFO; stdout/stderr to a log file.
nohup flutter run -d emulator-$EMULATOR_PORT \
  < "$FIFO" \
  > /tmp/flutter-$EMULATOR_PORT.log 2>&1 &
echo $! > /tmp/flutter-$EMULATOR_PORT.pid
disown

# Wait until flutter is ready to receive commands (look for the help banner).
until grep -q "Flutter run key commands" /tmp/flutter-$EMULATOR_PORT.log 2>/dev/null; do
  sleep 2
done
echo "flutter run ready on emulator-$EMULATOR_PORT"
```

First-time compile costs ~30–60 s (same as a full APK build). All later iterations use the FIFO:

```bash
# --- Iteration: after editing Dart code ---
echo r > /tmp/flutter-stdin-$EMULATOR_PORT      # hot reload (~1 s, keeps state)
sleep 2
adb -s emulator-$EMULATOR_PORT exec-out screencap -p > /tmp/mg-$EMULATOR_PORT.png
```

If a reload doesn't visibly take effect, dump the log to confirm: `tail -20 /tmp/flutter-$EMULATOR_PORT.log` should show "Reloaded N libraries". A line like "Reloaded 0 of N libraries" means the change wasn't picked up — see the fallback below.

### Hot restart (`R`) — when state needs to reset

`R` rebuilds the Dart isolate and restarts the app from `main()`. ~3–5 s. Use when:
- You changed `main()` or top-level providers / Riverpod scopes
- You added a new `Provider`, route, or top-level constant
- The app is in a weird state (auth token, cache) and you want a clean run

```bash
echo R > /tmp/flutter-stdin-$EMULATOR_PORT
sleep 5
```

### When hot reload is not enough — full rebuild fallback

Some changes require a full APK rebuild. Symptoms / triggers:
- Adding/removing a **Flutter plugin** with native code (`pubspec.yaml` change to a `_plugin`)
- Adding/removing **Android-side files** (Gradle, AndroidManifest, kotlin)
- Adding new **assets** registered in `pubspec.yaml`
- `flutter run` log shows compilation errors that survive an `R`

To rebuild cleanly: stop `flutter run`, build APK, install, restart `flutter run`.

```bash
# Stop the current flutter run (and its stdin keeper) cleanly
echo q > /tmp/flutter-stdin-$EMULATOR_PORT
sleep 3
kill "$(cat /tmp/flutter-keeper-$EMULATOR_PORT.pid)" 2>/dev/null
rm -f /tmp/flutter-stdin-$EMULATOR_PORT /tmp/flutter-keeper-$EMULATOR_PORT.pid /tmp/flutter-$EMULATOR_PORT.pid

# Rebuild and reinstall the APK
flutter build apk --debug
adb -s emulator-$EMULATOR_PORT install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-$EMULATOR_PORT shell am force-stop app.missiongeo

# Restart flutter run for the next iterations (re-do the Setup block above)
```

## `list_elements_on_screen` example output

```jsonc
// example return — bounds are in DEVICE pixels, ready to feed into click_at_coordinates
[
  {"type":"android.view.View","label":"Mon profil","coordinates":{"x":210,"y":210,"width":786,"height":60}},
  {"type":"android.view.View","label":"Badges","coordinates":{"x":105,"y":1060,"width":870,"height":81}},
  ...
]
```

## scrcpy — when to launch vs. skip (full detail)

The emulator runs **headless** by default (`-no-window`), so the user can't see what you're doing. That's fine while you iterate alone via screenshots, but the moment the user needs to *see* the result and react ("rate that animation", "move that button", "tell me if this layout works") — they need a live view. Use `scrcpy`: a USB-cable-style screen mirror that connects to the emulator over ADB, opens a window on the user's desktop, and accepts mouse + keyboard input so they can interact in parallel with your ADB driving.

**When to launch scrcpy:**
- **As the close-out of any UI task**, once your own screenshot pass is green — so the user does their visual validation before you merge
- Before asking the user to validate a UI iteration ("dis-moi si ça te va", "regarde ce design")
- After the user explicitly asks "comment je peux voir ?" or "montre-moi"
- During collaborative design loops where the user will iterate quickly with feedback

**When to skip:**
- *Mid-iteration* agent loops (you alone screenshotting + tweaking before the result is presentable) — but still open it for the final user validation
- Headless CI / batch runs

## ADB fallback (when mobile-mcp is unavailable)

If the mobile-mcp tools aren't loaded in this session, the same operations via raw ADB:
<!-- trigger: inspector lost time tapping blind on whats-new validation, 2026-07-10 -->

```bash
# inspect (XML)
adb -s emulator-$EMULATOR_PORT shell settings put secure accessibility_enabled 1  # REQUIRED first: exposes Flutter's semantics tree to uiautomator (else the dump has no Flutter widgets)
adb -s emulator-$EMULATOR_PORT shell uiautomator dump /sdcard/ui.xml >/dev/null
adb -s emulator-$EMULATOR_PORT shell cat /sdcard/ui.xml | tr '>' '\n' \
  | grep -E 'content-desc="<TARGET LABEL>"'

# screenshot (then Read /tmp/mg-$EMULATOR_PORT.png)
adb -s emulator-$EMULATOR_PORT exec-out screencap -p > /tmp/mg-$EMULATOR_PORT.png

# tap / type
adb -s emulator-$EMULATOR_PORT shell input tap X Y
adb -s emulator-$EMULATOR_PORT shell input text "Claude"  # %s for spaces
adb -s emulator-$EMULATOR_PORT shell input keyevent 4     # BACK
adb -s emulator-$EMULATOR_PORT shell input keyevent 67    # backspace
```

## scrcpy — full launch script

```bash
# Sanity-check first — install once if missing
which scrcpy >/dev/null || {
  echo "scrcpy missing — ask the user to run: ! sudo apt install -y scrcpy" >&2
  exit 1
}

# DISPLAY=:1 (or whatever the user has) → window opens on their desktop, not nowhere
DISPLAY="${DISPLAY:-:1}" nohup scrcpy -s emulator-$EMULATOR_PORT \
  --window-title "Mission Geo" --max-size 800 \
  > /tmp/scrcpy-$EMULATOR_PORT.log 2>&1 &
disown
sleep 2
pgrep -f "scrcpy -s emulator-$EMULATOR_PORT" >/dev/null \
  && echo "scrcpy running" \
  || { echo "scrcpy failed to start, see /tmp/scrcpy-$EMULATOR_PORT.log"; tail -20 /tmp/scrcpy-$EMULATOR_PORT.log; }
```

**Notes:**
- `--max-size 800` keeps the window manageable on a 1080×2400 device (the screenshot size in your context, not the device's actual resolution).
- The user can click/drag/type in the scrcpy window AT THE SAME TIME you're driving via ADB. Coordinate via the conversation — usually you stop driving while they validate.
- If scrcpy errors with `Could not open display`, the `DISPLAY` env var is wrong. Check `echo $DISPLAY` and `WAYLAND_DISPLAY` (X11 = `:0`/`:1`, Wayland needs different setup; ask the user).
- scrcpy survives across Bash invocations because of `nohup` + `disown`; the same teardown step kills it cleanly.

## Related incident rows (moved from the Common Mistakes table)

| Symptom | Cause | Fix |
|---|---|---|
| Onboarding shows "Une erreur est survenue" | Firebase sync hiccup on first boot (the `google_apis` image ships GMS / Play Services, so this is transient, not a missing-services failure) | Force-stop + restart — local profile already saved, onboarding skips |
| `flutter run` errors not visible | Backgrounded process eats stdout | Already redirected to `/tmp/flutter-$EMULATOR_PORT.log` by the setup recipe — `tail -50` it after a reload |
| `flutter run` silently reflects a DIFFERENT worktree's code (even one already deleted from disk) | Gradle/Flutter tooling can resolve a stale project location instead of your worktree's | Check the `flutter run` log's "project located at" line against your own worktree path; or prefer explicit `flutter build apk --debug --flavor dev --dart-define=APP_FLAVOR=dev` + `adb install`, and verify the built APK's path/mtime before trusting it |
| Emulator disappears ~3 min after switching from `flutter run` to raw `adb install` / `am start` driving | No `flutter`/`dart` process stays attached, so the pool keeper reclaims the "idle" port | Manual-ADB workflows always need a keepalive — pair with `mg_emu_up` (mg-emu.sh); explicit build ⇒ explicit keepalive |
