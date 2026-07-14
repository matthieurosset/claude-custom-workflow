# Emulator lifecycle — provisioning, multi-emulator ops, crash recovery

Deep-dive detail for `visual-validation-android/SKILL.md` §"Prerequisites", §1 ("Boot emulator headless"), §6 ("Shut down"), and "Crash Recovery / Zombie Reaping". Read this when the quick recipes in SKILL.md aren't enough — recreating an AVD, running more than one emulator, swapping AVDs on a held port, or recovering from a crash spiral.

## Why a helper, not raw commands

Claude shells are non-interactive; `~/.bashrc` returns early (`case $- in *i*) ;; *) return;; esac`), so SDK PATH exports after that guard aren't loaded and `which emulator` returns nothing. The pool helper references binaries by absolute path for you. `adb` lives at `/usr/bin/adb` (system package) though, so it works from any PATH regardless.

**Do not fall back to a physical device** if boot fails — fix the command (almost always the PATH issue above). Falling back changes test conditions and pollutes the user's phone.

## Why `google_apis`, never `google_apis_playstore`

The Play Store image runs Play Services that **self-update mid-session** (`com.google.android.gms ... installPackageLI`) and kill foreground apps — Firebase/AdMob ones get bounced ("the app rebooted on its own"), plus heavy memory pressure on a 2 GB guest. `google_apis` still ships GMS so Firebase/AdMob work, but without the Play Store pulling updates the app stays put.

## Recreating an AVD from scratch

All three canonical AVDs (`mission_geo_phone`, `mission_geo_tablet7`, `mission_geo_tablet10`) share the single android-36 system image:

```bash
avdmanager create avd -n mission_geo_phone \
  -k "system-images;android-36;google_apis;x86_64" -d pixel_7 --force
# tablet7 → -d "Nexus 7 2013"  ;  tablet10 → -d pixel_c
# then set hw.ramSize in ~/.android/avd/<name>.avd/config.ini (phone 2048M, tablets 1536M)
# (image: google_apis, NOT google_apis_playstore — see the "Why" note above)
```

## Higher-level option: `mg-emu.sh` (1–3 emulators, any phone/tablet mix)

For anything beyond a single `flutter run` session — **several emulators at once**, or a **build-APK + `am start` + logcat / manual-ADB** workflow (no `flutter run` attached) — use the orchestration layer `.claude/skills/shared/mg-emu.sh` instead of hand-driving the pool. It wraps `emulator-pool.sh` and adds a **session-aware lease keepalive**: ANY multi-step manual-ADB session with no `flutter run` attached MUST call `mg_keepalive_start` immediately after `mg_claim_port` (canonical rule + rationale: SKILL.md §1 "Boot emulator headless"), or the pool reaper reclaims the emulator mid-session — this isn't an `mg-emu.sh`-only nicety. The keepalive stops the instant your session ends, so it can never pin a port for a dead agent.

```bash
source "$(git rev-parse --show-toplevel)/.claude/skills/shared/mg-emu.sh"
mg_emu_up phone                      # 1 emulator
mg_emu_up phone tablet7              # 2
mg_emu_up phone tablet7 tablet10     # 3 (claims 3 ports; leaves others for parallel agents only if you ask for <3)
mg_emu_swap 5554 tablet7             # switch the AVD on a held port (lock kept)
mg_emu_scrcpy on   |  mg_emu_scrcpy off
mg_emu_health  ;  mg_emu_list
mg_emu_install  ;  mg_emu_app        # mission-geo: install dev-debug APK + settle-GMS-then-launch
mg_emu_down                          # release every port this session holds
```

Still use the plain `flutter run` + FIFO recipe in SKILL.md for the common **single-emulator hot-reload** loop — there a `dart` process stays attached, so the pool keeper auto-renews the lease and no keepalive is needed.

## Impeller / Skia for APK-install + `am start` flows

`--no-enable-impeller` only applies to `flutter run`. For workflows that build an APK and launch it via `am start` / `monkey`, the renderer is selected at build time. Always use the **dev-flavor APK** (`flutter build apk --debug --flavor dev --dart-define=APP_FLAVOR=dev`). The dev-flavor manifest (`android/app/src/dev/AndroidManifest.xml`) hard-disables Impeller via `io.flutter.embedding.android.EnableImpeller=false`, so Skia is used and the SwiftShader software-GPU AVDs remain stable. Installing a prod-flavor APK on these AVDs risks a Vulkan/Impeller crash on heavy screens.

## Validating tablets (the 3-tier responsive check)

Your port hosts **one AVD at a time**. To check the 7" / 10" tablet tiers, **swap on the same port** — the pool kills the current AVD and boots the next while keeping your lock held, so no other agent can steal the port during the gap:

```bash
source "$(git rev-parse --show-toplevel)/.claude/skills/shared/emulator-pool.sh"
MG_PORT=$EMULATOR_PORT               # re-bind your claimed port in this fresh shell
mg_swap_avd mission_geo_tablet7      # kill phone, boot 7" tablet on the SAME port
# ... restart flutter run (SKILL.md §2) — the previous app instance died with the old AVD ...
mg_swap_avd mission_geo_tablet10     # then the 10" tablet
```

## Full shutdown sequence

The emulator is heavy (≈2 GB RAM, qemu-system process). Once the user has validated the visual change AND any merge/push step in `git-workflow-branch-worktree` is done, tear down **your own session only** in this order:

```bash
# 1. Quit scrcpy if you launched it (skip otherwise)
pkill -f "scrcpy -s emulator-$EMULATOR_PORT" 2>/dev/null
rm -f /tmp/scrcpy-$EMULATOR_PORT.log

# 2. Quit flutter run cleanly via the FIFO (skip if you didn't start one)
[ -p /tmp/flutter-stdin-$EMULATOR_PORT ] && echo q > /tmp/flutter-stdin-$EMULATOR_PORT
sleep 3

# 3. Kill the FIFO keeper and remove temp files
kill "$(cat /tmp/flutter-keeper-$EMULATOR_PORT.pid 2>/dev/null)" 2>/dev/null
rm -f /tmp/flutter-stdin-$EMULATOR_PORT \
      /tmp/flutter-keeper-$EMULATOR_PORT.pid \
      /tmp/flutter-$EMULATOR_PORT.pid

# 4. Release your port: kill the emulator AND drop the pool lock (frees it for
#    the next agent). Re-source the helper in this fresh shell and re-bind MG_PORT.
source "$(git rev-parse --show-toplevel)/.claude/skills/shared/emulator-pool.sh"
MG_PORT=$EMULATOR_PORT
mg_release_port
sleep 2
adb devices                                          # your port should be gone; others may remain
```

(If you only have raw `adb`, `adb -s emulator-$EMULATOR_PORT emu kill` stops the emulator — but it leaves the pool keeper holding the lock. Always prefer `mg_release_port` so the port is actually freed.)

Keep `/tmp/emulator-$EMULATOR_PORT.log`, `/tmp/flutter-$EMULATOR_PORT.log`, and `/tmp/mg-$EMULATOR_PORT.png` only if useful for the next session — otherwise delete.

## Crash Recovery / Zombie Reaping

**The zombie problem**: when an emulator crashes (Impeller/Vulkan fault, OOM, etc.), its `qemu-system` process does NOT die — it lingers as a ~3 GB zombie. `adb emu kill` is a no-op on a crashed/unreachable instance. If you reboot the emulator on the same port without reaping the zombie first, you stack a second qemu on the same port → RAM exhausts → both instances become unstable → more crashes → more zombies. This is the cascade.

**Prevention (already built in)**: `mg_boot_avd`, `mg_kill_current`, `mg_swap_avd` (pool), and `mg_emu_swap` (mg-emu.sh) all call `mg__kill_port_qemu` before launching a new qemu. You should never need manual intervention if you use these helpers.

**A zombie you don't own blocks your launch too**: `flutter run -d <serial>` polls **every** attached adb device during enumeration, even with an exact `-d` match — another session's zombie (an unreachable `adb shell`) silently hangs your launch. Never reap a port you don't own. Bypass enumeration instead: `flutter build apk --debug --flavor dev --dart-define=APP_FLAVOR=dev` then `adb -s <your-serial> install -r <apk>` and `adb -s <your-serial> shell am start -n app.missiongeo.dev/app.missiongeo.MainActivity` — explicit `-s` throughout, zero device enumeration.
<!-- trigger: inspector run blocked 12+ min by another session's zombie on 5554, 2026-07-14 -->

**Shared Gradle daemon contention**: if `flutter run`/`flutter build` stalls silently (its log stays completely empty, the process sits at 0% CPU in a futex wait, >5 min) while another session is mid-build, it's queued behind the shared Gradle daemon lock, not a zombie — don't wait it out or kill/rebuild. If the worktree already has a committed build, install it directly instead: `ls -la build/app/outputs/flutter-apk/app-dev-debug.apk` (verify its mtime is newer than `git log -1 --format=%cI`), then `adb -s <serial> install -r build/app/outputs/flutter-apk/app-dev-debug.apk` + `adb -s <serial> shell am start -n app.missiongeo.dev/app.missiongeo.MainActivity`. Hot reload isn't needed to validate already-committed code — call `mg_keepalive_start` first since you're driverless (no `flutter run` process attached).
<!-- trigger: inspector starved 21+ min twice behind shared gradle daemon, 2026-07-14 -->

**Manual recovery (if the spiral already happened, and it's YOUR zombie)**:

```bash
source "$(git rev-parse --show-toplevel)/.claude/skills/shared/emulator-pool.sh"
# Option A: auto-detect + reap all zombie/duplicate qemu and free stale locks.
mg_emu_doctor

# Option B: target a specific port directly.
mg__kill_port_qemu 5554   # reaps crashed qemu on port 5554, waits for it to exit
```

**Rules**:
- Never reboot on a port without reaping first.
- Never stack reboots — wait for `mg__kill_port_qemu` to return (bounded ~15 s).
- Monitor `MemAvailable` in `/proc/meminfo`: `mg_boot_avd` and `mg__emu_boot_bg` refuse to boot if `MemAvailable < 3000 MB` (prints `POOL_LOW_RAM`). Free RAM or wait for another emulator to finish before retrying.

## Related incident rows (moved from the Common Mistakes table)

| Symptom | Cause | Fix |
|---|---|---|
| App "rebooted on its own" mid-session | Play Services self-update killing the foreground app (`Killing … missiongeo … stop com.google.android.gms due to installPackageLI`). Fixed by the `google_apis` (non-playstore) image; if it still recurs, it's GMS, not a crash — the app auto-restarts | Use `mg_emu_app` (settles GMS, relaunches, verifies foreground); don't chase it as an app bug |
| Booting another emulator on a free port still fails with "another instance is running" | Existing emulator was started **without** `-read-only`, so it locks the AVD even for new read-only instances | All emulators on this AVD must run with `-read-only`. Coordinate or relaunch the offending one |
| Emulator crashes, rebooting on the same port still crashes / OOM | Crashed qemu process did NOT die — it lingers as a ~3 GB zombie. `adb emu kill` is a no-op on a crashed/unreachable instance. Rebooting stacks a second qemu on the same port → RAM exhaustion → more crashes | Run `mg_emu_doctor` (auto-reaps zombies) or call `source emulator-pool.sh; mg__kill_port_qemu <port>` before the next boot. `mg_boot_avd`, `mg_kill_current`, `mg_swap_avd`, and `mg_emu_swap` now do this automatically. |
| App crashes immediately on heavy screens after `am start` (APK install flow) | Impeller (Vulkan) is on by default in release and some debug builds — SwiftShader (software GPU) can't handle it → GPU fault → crash. **`--no-enable-impeller` only applies to `flutter run`**, not to an APK launched via `am start`. | Build the dev-flavor APK (`--flavor dev`). The dev manifest (`android/app/src/dev/AndroidManifest.xml`) sets `io.flutter.embedding.android.EnableImpeller=false`, so Skia is used automatically and the software GPU is safe. Never install the prod-flavor APK on these AVDs for visual validation. |
