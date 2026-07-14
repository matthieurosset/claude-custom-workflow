---
name: online-multiplayer-debug
description: Use when validating any change to Mission Geo's online multiplayer (casual online rooms or ranked matches) against 2 real dev-flavor instances on the real mission-geo-dev Firebase project — booting 2 emulators as 2 real players, running an accelerated timing profile, or reproducing a disconnect/pairing/host-failover regression. This is the standing validation gate for every future online change.
---

# Online Multiplayer Debug Harness

## Overview

Mission Geo's online module (casual online rooms + ranked matches) has a history of regressions that only show up with **two real clients** exchanging real Firestore/RTDB state — a long wait between rounds, a player who queues then disconnects and freezes the pairing, a host that stalls forever on `roundResult`. None of these reproduce with a single dev-flavor instance or the security-rules emulator suite (`online-security-validation` — that's for rule/transaction correctness, not client-visible pacing or real 2-device disconnect races).

This harness boots **2 real Android emulators**, installs the **same** accelerated dev-debug build on both, and drives them as **2 real players** against the **real `mission-geo-dev` Firebase project** (never prod — dev flavor only). An optional timing profile (`DEBUG_ONLINE_SPEED` / `DEBUG_RANKED_SPEED` dart-defines) compresses match PACING only, so a full casual match or ranked round completes in well under a minute instead of several.

**This is the validation gate for every online-touching change** — casual rooms, ranked matches, presence/heartbeat, Cloud Functions under `functions/` that touch `game_rooms` / ranked queues. Don't claim an online fix is verified without walking at least the casual + ranked self-proofs below, plus whichever chaos scenario the change targets.

## When to Use

- Any change to `lib/providers/online_game_provider.dart`, `lib/providers/ranked_provider.dart`, `lib/providers/ranked_match_provider.dart`
- Any change to `lib/core/services/firebase/firebase_game_room_service.dart` or `firebase_ranked_service.dart`
- Any change to a Cloud Function touching `game_rooms`, ranked queues, or presence (`functions/index.js`)
- Any change to `lib/pages/modes/online/**` or `lib/pages/modes/ranked/**`
- Before merging a PR that touches the online module (in addition to, not instead of, `online-security-validation` when rules/transactions are involved)

**Skip for**: pure défi/adventure/duel-local changes with no online/ranked surface.

## Prerequisites

- 2 free ports on the shared emulator pool (`.claude/skills/shared/emulator-pool.sh` — 5554/5556/5558). Check with `mg_emu_status` before claiming; this harness needs 2, so don't start it if another agent already holds 2+ ports.
- `flutter` on PATH (`export PATH="$HOME/flutter/bin:$PATH"` on this machine).
- The dev Firebase project (`mission-geo-dev`) reachable — this is the REAL backend, not an emulator. Both instances write real data (rooms, ranked stats, queue entries) to it. Debug-created rooms are cheap and expire (`purgeExpiredRooms`), ranked debug-solo rooms are prefixed `DBG`, but a real 2-player ranked match DOES affect real ELO/stats for whatever dev account each emulator is signed in as.
- **Two DISTINCT Firebase identities, one per instance.** Naively booting `mg_emu_up phone phone` would launch two QEMU processes of the SAME golden `mission_geo_phone.avd` image — and since `adb install -r` preserves existing app data, both instances would inherit the identical baked-in anonymous UID (whatever was last signed in on that AVD from ordinary single-instance dev usage), silently invalidating every 2-player scenario (join by code, ranked pairing, all 5 chaos scenarios).
  - **Fix in place**: `online-duo-up.sh` auto-provisions a SECOND, persistently distinct AVD (`mission_geo_phone_b`, a one-time clone of `mission_geo_phone` decoupled via a single non-read-only `-wipe-data` boot — see `setup-phone-b-identity.sh`) and boots instance A on `mission_geo_phone` / instance B on `mission_geo_phone_b`. Both keep stable, distinct identities across every future run — no re-provisioning, no re-onboarding. First run costs a few minutes (disk clone ~3-4GB + one decoupling boot cycle); every run after is instant (idempotent, sentinel-gated).
  - **Automated guard**: regardless of the above, `online-duo-up.sh` verifies the two instances actually ended up with distinct UIDs after boot (`mg_chaos_tail_uid` on both, fails loudly with a non-zero exit on a match) — see "MG_DEBUG_UID identical on both instances" below if it fires. Don't remove this guard even though the fix above should make it a no-op in the common case: it's what stops this exact bug from silently coming back as a false PASS.
  - Only the default `--avd phone` path gets the auto-provisioned decoupled clone; overriding `--avd` to `tablet7`/`tablet10` boots the same tablet AVD for both instances and the guard is expected to fail unless you provision your own distinct identity for it first.
  - **Onboarding/consent re-appearing on `mission_geo_phone_b` every boot?** Every harness boot of it is `-read-only` (see `setup-phone-b-identity.sh`'s header comment), so anything written to SharedPreferences during a read-only session — including "onboarding done" / consent choice — is discarded at exit. If `mission_geo_phone_b` keeps landing on the onboarding/consent screen instead of home on every `online-duo-up.sh` run, persist it the same way the identity itself was decoupled: **one non-read-only boot to click through onboarding + consent once**, then a clean shutdown so it's written back to the AVD's own base image, exactly the pattern `setup-phone-b-identity.sh` already uses for the fresh sign-in. Concretely: claim a port, boot `mission_geo_phone_b` WITHOUT `-read-only` (no `-wipe-data` this time — you want to keep the existing decoupled identity, just add persisted prefs on top), install/launch, manually tap through onboarding + accept/decline consent once, then `adb -s emulator-<port> emu kill` for a clean shutdown (not `mg_release_port`'s zombie-reap path — a normal kill on a non-read-only session flushes to disk same as the identity-decoupling boot does). Every subsequent read-only boot then starts on home, same as `mission_geo_phone` already does from ordinary dev usage.
- **App Check debug token file, per worktree.** `android/firebase_debug_token.dev.properties` is gitignored (see CLAUDE.md's "App Check (debug token pinned)" section), so every fresh worktree (`git-workflow-branch-worktree` skill) starts without it — `BuildConfig.FIREBASE_APP_CHECK_DEBUG_TOKEN` is then blank, `MainActivity.installFixedAppCheckDebugTokenIfNeeded()` no-ops, and the App Check SDK falls back to a fresh random UUID on every install (not allow-listed in the `mission-geo-dev` Firebase Console), silently taking down every Firestore/RTDB call this harness depends on with `PERMISSION_DENIED`. **Fix in place**: `online-duo-up.sh` checks for the file before doing anything else and copies it from the primary checkout (`/home/mrjack/git/mission-geo/android/firebase_debug_token.dev.properties`) with a loud log line, hard-failing with a clear message only if neither copy exists. See "App Check: random UUID / PERMISSION_DENIED storm" below if it still fires.
- **App Check pm-clear race** (a `flutter build`/reinstall inside `online-duo-up.sh` never triggers this — `mg_emu_install` uses `adb install -r -d`, which preserves app data; this only bites a *genuinely* fresh app-data state: first-ever install on a golden AVD image, or an explicit `pm clear`). On a fully fresh data state, `MainActivity`'s SharedPreferences write can lose the race against the App Check SDK's own lazy token generation — 3 different random tokens were observed across 3 cycles in practice. See "App Check: random UUID / PERMISSION_DENIED storm" below for the reliable workaround (write the SharedPreferences XML yourself via `adb shell run-as`, before first launch).

## Quickstart

```bash
cd /home/mrjack/git/mission-geo   # or your worktree
export PATH="$HOME/flutter/bin:$PATH"
bash .claude/skills/online-multiplayer-debug/scripts/online-duo-up.sh
```

This claims 2 pool ports, boots `mission_geo_phone` (instance A) + `mission_geo_phone_b` (instance B — a persistently distinct clone, auto-provisioned on first run only, see "Two DISTINCT Firebase identities" above), builds ONE accelerated dev-debug APK (`DEBUG_ONLINE_SPEED=6`, `DEBUG_RANKED_SPEED=3` by default — override with `--online-speed N` / `--ranked-speed N`), installs it on both, and force-foregrounds the app. It prints the two `ANDROID_SERIAL` values (e.g. `emulator-5554` / `emulator-5556`) — keep them, every chaos primitive below needs an explicit serial. **First run only** takes a few extra minutes to provision `mission_geo_phone_b` (disk clone + one decoupling boot) — every run after is fast.

**Both instances MUST run the identical build.** The pacing scalers are compiled-in consts (`lib/core/dev/debug_timing_config.dart`) — a speed mismatch between A and B desyncs their countdowns/reveals. The script builds once and installs the same APK on both; don't `flutter run` a second, differently-configured instance against one from this script.

Iterating on non-harness online code: rerun `online-duo-up.sh` (drop `--skip-build` only if you didn't touch pacing/debug-tile files — otherwise you're testing a stale build).

**Persistent adb attachment (survives a session handoff).** This harness never runs `flutter run` — it builds once, `adb install`s, then drives everything with one-shot `adb`/logcat calls — so the only thing keeping a claimed port's lease fresh is `mg_emu_up`'s `mg_keepalive_start` daemon, and that daemon dies the instant ITS OWNING SESSION dies (by design — a dead agent must not pin a port forever). That's a problem for the common pattern of one agent booting the harness and then handing off to another (e.g. an inspector agent that only pokes at the emulators with one-shot adb): if the booting agent's session ends first, its keepalive dies, and the pool's own per-port keeper reclaims the emulator once the lease goes stale (`MG_LEASE_TTL`, 180s by default) — **even though a different agent is still actively using it**. `online-duo-up.sh` now arms one `adb -s <serial> logcat` per claimed serial right after boot (`mg_emu_arm_logcat_pin` in `mg-emu.sh`) specifically to survive this: the pool's attachment checks recognize a genuine, long-running `logcat` stream (but NOT its own short-lived `get-state`/`install`/`shell` probes — distinguished by cmdline) as live use, independent of any particular session's liveness. `mg_emu_down` kills these pins along with everything else — don't skip it just because "nothing was using flutter run".

When finished:
```bash
source .claude/skills/shared/mg-emu.sh && mg_emu_down
```
Releases both ports for other agents (and kills the logcat pins above). Don't leave 2 ports pinned after your session ends.

## Dart-Define Contract

| Define | Default | Effect |
|---|---|---|
| `DEBUG_ONLINE_SPEED` | 1 (identity) | Divides casual-online pacing durations (countdown, round-end grace, round-result/final-ranking cosmetic delays) and the room-creation `roundDurationSeconds` (floored at 3s). |
| `DEBUG_RANKED_SPEED` | 1 (identity) | Divides ranked pacing durations (reveal, grace-after-reveal, advance-retry, pair-poll, reveal/end overlay cosmetic delays). |

Both fold to a pure identity function outside `kIsDevFlavor` (const-false in prod builds) or when the speed is 1 — **zero prod footprint**, same discipline as `ScreenshotConfig`. See `lib/core/dev/debug_timing_config.dart`.

### Hard do-not-scale boundary

The scalers apply to **match pacing only**. They must NEVER touch, and currently do NOT touch:

- **Presence / heartbeat cadences**: casual heartbeat 10s, ranked heartbeat 3s (RTDB `match_presence`), host watchdog 8s, background grace 30s (`online_game_provider.dart`).
- **Life loss on question close (`advanceRankedQuestion`)**: user decision (2026-07) — **unconditional, no presence leniency**. Any question without a correct answer costs a life, present, lagging, or disconnected; "regime 1" (a presence-gated leniency that used to exist here) was REMOVED entirely — do not reintroduce it or reference a `getRankedPresenceSnapshot`/`presenceByUid` mechanism, both deleted. A player returning from a hiccup resumes with the lives already spent during the gap and can still finish the match.
- **Disconnect (forfeit-claim) thresholds — TWO distinct regimes, don't conflate them**:
  - **Regime 2 (forfeit-claim on stale ts — dirty network / frozen background)**: `ranked_match_page.dart`'s `_opponentStaleThreshold` + `kHeartbeatStaleMs` in `functions/index.js` (CF-authoritative) — **30s (~3 question rounds), up from 9s**. Coordinated: client and CF must match.
  - **Regime 3 (absent RTDB node after having been seen once — rage-quit/force-stop via `onDisconnect`)**: no dedicated constant, resolves as an immediate `stale = true` — **~3s, unchanged**. Deliberate quits stay punished fast.
  - **Never-seen grace** (`_neverSeenGraceMs` / `NEVER_SEEN_GRACE_MS`) — **15s, unchanged**.
- **The ranked question duration itself** (`_questionDuration` = 10s in `ranked_match_provider.dart`) — this is server-floored (`kRankedMinQuestionMs`=9000ms) specifically to reject premature "everyone answered" advances; scaling it would defeat that anti-instant-draw guard. `DEBUG_RANKED_SPEED` only shrinks the CLIENT overlays around it (reveal, grace, retry) — a ranked round is still ~10s minimum regardless of speed.

Scaling any of the above would make the harness blind to the exact disconnect/timing races it exists to catch. If you're tempted to scale one of them to "make testing faster", don't — use `mg_chaos_background`/`airplane_off` with a shorter manual wait instead, or accept the real-time wait for that one assertion.

## Manual Walkthroughs

**If driving the UI via `adb shell input tap` instead of a physical/manual tap** (e.g. to script "tap the Créer room tile" against a screenshot you took): the phone AVD's real screen is **1080×2400 px**. The `Read` tool renders screenshots scaled down to fit its preview (~1.2x smaller on this setup) — tapping the coordinates you read directly off that preview image lands in the wrong place. Always crop the region you're about to tap and re-check its pixel bounds against the real 1080×2400 frame (e.g. `adb shell wm size`, or scale your preview-read coordinates back up) before issuing the tap — don't trust the preview's apparent pixel grid.

**UI-driving checklist (before you trust what a tap or a scenario result tells you):**
- **Re-dump uiautomator before every tap.** A cached `uiautomator dump` from a prior screen goes stale the moment either instance transitions (lobby → countdown → playing, or any auto-play/auto-advance firing on its own timer) — tapping coordinates resolved from a stale dump lands on whatever is now underneath them, not what you intended. Dump fresh, tap, and don't reuse a dump across more than one action.
- **Verify BOTH clients are actually on `RankedMatchPage` (or the expected casual screen) before trusting a 2-player scenario's result.** A tap that landed wrong, a stale room code, or a navigation race can leave one instance parked on the lobby/home/an error toast while the other proceeds alone — the "match" you're observing is then 1-player, and whatever pass/fail you record is a false finding, not a real result. This is the same class of mistake as the identity guard in "Two DISTINCT Firebase identities" above (a check that looks fine from one instance's perspective can be silently wrong) — confirm the actual screen on EACH serial (screenshot or `dumpsys activity activities` / `mg__emu_foreground`-style resumed-activity check), not just that neither instance crashed.

### Casual self-proof (A creates, B joins)

1. `online-duo-up.sh` → note the two serials (say `emulator-5554`=A, `emulator-5556`=B).
2. On A: home tab → debug launcher (`debug` route) → "Online 2 joueurs (harnais)" section → **"Créer room + attendre"**.
3. Get the code either from A's lobby screen, or:
   ```bash
   source .claude/skills/online-multiplayer-debug/scripts/online-chaos.sh
   mg_chaos_tail_room_code emulator-5554
   ```
4. On B: same section → type the code into "Rejoindre par code" → **"Rejoindre"**. B should appear in A's lobby within a couple seconds.
5. B taps ready, A taps "Démarrer" (start). Countdown should be visibly short (÷6 by default). Full match (3 rounds at `casualSeconds(60)`≈10s each) should complete in well under a minute on BOTH instances, ending on the final ranking screen for both.

### Ranked self-proof (both queue)

1. On A and B: "Online 2 joueurs (harnais)" → **"Ranked file — Classique"** on both (or "Plus ou Moins" on both — must match to pair).
2. Both should search, then pair within ~10-15s (pair-poll is 5s, accelerated by `DEBUG_RANKED_SPEED`).
3. Play to a win/loss/draw. Each round is ~10s minimum (server floor, not accelerated) + accelerated reveal/grace on top.

### No-accel regression check

Run `online-duo-up.sh --online-speed 1 --ranked-speed 1` (or a plain `flutter run --flavor dev --dart-define=APP_FLAVOR=dev` with no speed defines) and confirm casual round duration is 60s and countdown is 5s as before — proves the wraps are inert at speed 1 and this harness hasn't silently changed default online behavior.

## Ranked Auto-Play (Validating Match Outcomes)

Pairing and question timeouts don't need a human, but **win/loss/draw/ELO/forfeit outcomes do** — with both instances AFK, every question times out and every match ends 0-0. `DebugRankedAutoplay` (`lib/core/dev/debug_ranked_autoplay.dart`) lets one or both instances answer automatically so you can actually drive a match to a real outcome.

Three modes: `off` (default — no override, a human taps or nobody does), `win` (auto-submits the correct answer ~1-2s into every question, scaled by `DEBUG_RANKED_SPEED`), `lose` (never answers — same net effect as `off`, but an explicit, self-documenting choice for "this instance must not answer" scenarios).

**Why a runtime toggle, not a dart-define alone:** `online-duo-up.sh` builds ONE shared APK for both instances (both MUST run the identical build — see the pacing-scaler note above). A dart-define bakes into that single build, so it can't give instance A `win` and instance B `off`. `DebugRankedAutoplay` reads a `debug_ranked_autoplay` launch-intent extra per process instead — same mechanism as `ScreenshotConfig`'s scenario/locale extras. A dart-define default (`--dart-define=DEBUG_RANKED_AUTOPLAY=win`) still works for a single manual `flutter run` instance; it's just not how the 2-instance harness sets it.

**Setting it:**

- **Per-instance, at boot** — `online-duo-up.sh --autoplay-a win --autoplay-b off` (or `lose`). Cold-restarts both instances right after `mg_emu_app` with the intent extra, then runs the identity guard against the restarted processes. Omit both flags and nothing changes (no restart, exactly prior behavior).
- **Mid-session, on one instance** — `mg_chaos_set_ranked_autoplay <serial> <off|win|lose>` (from `online-chaos.sh`, already sourced by `online-duo-up.sh`). This force-stops and cold-restarts that instance — only call it BETWEEN matches (right after boot, or after leaving a finished match), not mid-round, since it tears down whatever's currently open.
- **Interactively, on-device** — debug launcher → "Online 2 joueurs (harnais)" → the **"Auto-play classé: …"** tile cycles off → win → lose → off. Takes effect on the NEXT question (the mode is read once per question index), no restart needed — use this over the ADB route when you're already poking at one instance by hand.

**Typical pairing for outcome validation:** A=`win`, B=`off` (or `lose`) — A wins every round, so the match resolves to an A win / B loss within a few questions instead of 3×10s timeouts each. Swap which side is `win` to check the ELO/stats update on the other side of a loss.

## Fairness Measurement (Render Desync + Effective Time)

Ranked's 10s question timer is **server-anchored**: both `_startQuestionTimer` (`ranked_match_page.dart`) and `RankedBarrierNotifier.startQuestionTimer` (`ranked_match_provider.dart`) compute `remaining = 10s - (now - questionStartTime)`, where `questionStartTime` is a Firestore `serverTimestamp()` written once by the host inside `advanceRankedQuestion` (`firebase_game_room_service.dart`). A client that receives its Firestore snapshot for the new question late — slow network, backgrounded momentarily, snapshot listener latency — starts its local timer with `remaining` already eaten into. The visible countdown (`RankedLivesHud`'s `_CenterInfo`) uses the identical formula, so the player literally sees fewer than 10 seconds. This is a design property, not a bug in any one commit — it needs measuring before it's worth fixing.

`lib/pages/modes/ranked/ranked_match_page.dart` logs two dev-only lines (`kIsDevFlavor`-gated, zero prod footprint) that let you measure this directly:

- `MG_DEBUG_QRENDER roomCode=<code> qidx=<n> wallMs=<epoch> anchorMs=<epoch> remainingMs=<ms>` — fired once per question, in a post-frame callback right after this client's `_phase` flips to `question` (the first frame the question is interactive on THIS client). `remainingMs` recomputes what the visible countdown effectively shows at that instant, in ms.
- `MG_DEBUG_QTIMEOUT roomCode=<code> qidx=<n> wallMs=<epoch>` — fired when this client's own local timer fires (`_onTimeout`).

Paired by `roomCode`+`qidx` across the two harness instances, these give: **render-delta** (how far apart the two clients saw the same question appear) and **effective-time-available** (`QTIMEOUT.wallMs - QRENDER.wallMs`, i.e. how much of the 10s this client actually got, independent of the server anchor).

### Running a measurement

1. `online-duo-up.sh --autoplay-a lose --autoplay-b lose` (or `mg_chaos_set_ranked_autoplay <serial> lose` on both mid-session). **Both must be `lose`** (or plain `off` with nobody tapping) — every question must run to its full local timeout on both clients for a clean, complete measurement. `win` on either side means that side never logs `MG_DEBUG_QTIMEOUT` for questions it answers, which is reported as `answered` (excluded from the effective-time stats) rather than fabricated.
2. Ranked self-proof both instances into a match (see above) and let it play 2-3 matches (a few questions each) to get a decent sample.
3. `bash .claude/skills/online-multiplayer-debug/scripts/online-fairness-measure.sh emulator-5554 emulator-5556` — scrapes both logcat buffers, joins by roomCode+qidx, prints a per-question table plus min/median/p90/max for render-delta and each client's effective time.
4. A near-zero render-delta and effective-time consistently close to 10000ms on both sides = no measurable desync in this run. A skewed distribution (one side consistently lower effective-time, or a render-delta that grows) is the signal that motivates the anchoring fix (local-render anchor + server-side tolerance) — don't design that fix from a single anecdotal number, run it across a few matches first.

Script limitations: only pairs a question if BOTH clients rendered it (a client that disconnected first before reaching it is silently excluded from that row); requires the instrumentation to be present in the build under test (a build predating it just produces empty output, not an error — check for "No MG_DEBUG_QRENDER lines found").

## Manual Chaos Scenario Checklist

Load the chaos primitives first: `source .claude/skills/online-multiplayer-debug/scripts/online-chaos.sh`.

| Scenario | Prerequisite | Steps | What to verify |
|---|---|---|---|
| **Host stall on roundResult** | None — casual round timers advance without anyone answering. | Casual match, mid-`roundResult` phase, `mg_chaos_kill_app <hostSerial>` | Known open issue (no auto-advance) — this is a regression check / repro aid for a follow-up fix, not something this harness fixes. Confirm the guest's client behavior (does it hang forever, or degrade gracefully?). |
| **Queue-disconnect pairing** | None. | Both queue for ranked, then `mg_chaos_kill_app` one BEFORE pairing completes | The crash this used to cause is already fixed on `main` (commits `bcf809df`/`0f5017c4`/`aa920261`). This is a REGRESSION check that the fix holds and stale pairing resolves to a sane forfeit/timeout — NOT expected to crash. |
| **Host failover** | None — casual pacing doesn't depend on either side answering. | Casual match in progress, `mg_chaos_kill_app <hostSerial>` | Guest should detect the stale host (`hostStaleThreshold`=30s, real-time — not accelerated) and `tryClaimHost` should promote it. |
| **Ranked forfeit — cut the GUEST (dirty network, regime 2)** | Match past `intro`, into `question` phase on both sides (pair via "Ranked self-proof"). To tell which serial is the guest (non-host): check the `hostId` field of the paired room in `game_rooms/{roomCode}` (Firestore emulator UI) against each serial's uid (`mg_chaos_tail_uid`). Autoplay not required — the host still advances questions on its own timer regardless of the guest's connectivity. | On the GUEST's serial, `mg_chaos_airplane_on`, wait **~15s** (under the 30s regime-2 threshold), then `mg_chaos_airplane_off` | Match must NOT forfeit. The guest returns having lost a life for each question that closed during the ~15s gap (no presence leniency — "regime 1" was removed 2026-07; expect roughly 1 life for a single ~10-12s question cycle), and can keep playing to finish the match. |
| **Ranked forfeit — cut the GUEST past threshold (regime 2)** | Same as above. | On the GUEST's serial, `mg_chaos_airplane_on`, wait **~30-40s** (real-time — `_opponentStaleThreshold`/`kHeartbeatStaleMs` are NOT accelerated; was 9-25s before the 2026-07 threshold bump) | The host should be able to claim a win-by-timeout only after ~30s, not before. `mg_chaos_airplane_off` to restore after (harmless no-op once forfeited). |
| **Ranked forfeit — cut the HOST (regime 2)** | Same pairing/identification as above. Only the host calls `advanceRankedQuestion` (`ranked_match_provider.dart`'s `isHost` gate) — with the host unreachable, no life is deducted from either player until it returns or the guest's watchdog claims a forfeit. | On the HOST's serial, `mg_chaos_airplane_on`, wait **~15s** (under 30s), then `mg_chaos_airplane_off` | Match pauses (no life lost by either player, no question advance) and resumes normally once the host's presence refreshes — this is the visible difference from cutting the guest, since only the host drives question advancement. Waiting **>30s** instead should let the guest claim a win-by-timeout. |
| **Background grace** | None. | Casual or ranked match in progress, `mg_chaos_background <serial> 20` (under 30s) then `mg_chaos_background <serial> 35` (over 30s) | Short (<30s) background should preserve the session/heartbeat on resume AND, for ranked, the match must survive by design now: the background-grace timer (30s, `online_game_provider.dart`) and the regime-2 forfeit threshold (30s) are aligned, so a <30s background never lets the opponent's RTDB presence go stale enough to forfeit. Cutting a GUEST costs it a life per question closed during the gap (same as the dirty-network row above); cutting the HOST pauses the match instead. Long (>30s) background should let the heartbeat lapse (opponent sees a disconnect/forfeit). |
| **Ranked win/loss/ELO outcome** | **A must be `autoplay=win`** (`online-duo-up.sh --autoplay-a win --autoplay-b off`, or the on-device toggle). Without it, both sides time out every question with identical (wrong) answers and the match always resolves to a 0-0 draw — the exact gap this harness v1.1 closes. | Both queue for ranked (see "Ranked self-proof"), let the match play to completion. | A wins every round it answers, so lives diverge instead of dropping in lockstep; match ends in a win/loss (not a draw); winner's ELO/rank increases and loser's decreases; `RankedWon` fires stats/mission credit on the winning side only. |
| **Kill B mid-match (ranked, regime 3)** | **A must be `autoplay=win`** so the match is genuinely progressing (lives diverging, not both AFK-timing-out in lockstep) at the moment B is killed — killing B in a still-symmetric AFK match doesn't exercise anything beyond the "Ranked forfeit" scenario above. | Ranked match with A `autoplay=win`, let 1-2 rounds resolve so A is ahead, then `mg_chaos_kill_app <serialB>`, wait **~3-5s** (regime 3 — a force-stop removes the RTDB node via `onDisconnect`, resolved as an immediate `stale = true` client-side, independent of and unaffected by the regime-2 30s bump) | A's client detects B's absent RTDB presence and claims win-by-timeout quickly (~3-5s, not 30s); the match ends win for A, not a draw, and A's ELO reflects a real match (not an instant 0-round forfeit). |

Don't delete a scenario from this table when it becomes irrelevant — update it to test the new contract, same discipline as `online-security-validation`'s test matrix.

## Common Failures and Fixes

| Symptom | Cause | Fix |
|---|---|---|
| A and B's countdowns visibly drift apart | Different builds installed (one accelerated, one not, or different speed values) | Rerun `online-duo-up.sh` without `--skip-build` so both get the identical APK |
| `mg_chaos_tail_room_code` returns nothing | Room not yet created, or logcat buffer rotated past the line | Re-tap "Créer room + attendre" and retry immediately, or read the code off the lobby screen |
| Ranked round never seems to speed up | `DEBUG_RANKED_SPEED` only shrinks reveal/grace/retry, not the 10s question floor — working as intended | Don't scale it further; see "Hard do-not-scale boundary" |
| `mg_emu_up` fails with `POOL_LOW_RAM` | Another agent already has an emulator up | Check `mg_emu_status` / ask before claiming a 3rd port |
| **`online-duo-up.sh` fails with `FAIL: both instances share the SAME Firebase UID`** | Both instances booted from the same golden AVD image with `adb install -r` (preserves app data) — they inherit the identical anonymous UID already baked into that AVD from prior single-instance dev usage. Every 2-player scenario (join by code, ranked pairing, all 5 chaos scenarios) is invalid when this fires — it is NOT a false alarm. | See the "Two DISTINCT Firebase identities" prerequisite above for the fix in place. **Never** interpret a "static/review PASS" as covering this — it only shows up when actually walking the 2-player scenarios, which is why the guard runs automatically. If you suspect a false positive, verify manually with `mg_chaos_tail_uid <serialA>` / `<serialB>` before assuming the guard is wrong. |
| `mg_chaos_airplane_on`/`off` appears to succeed (prints "network OFF"/"ON") but the other player never detects a disconnect/reconnect | (Historical, fixed) — the old implementation used `settings put airplane_mode_on` + `am broadcast AIRPLANE_MODE`, which throws `SecurityException` on the Android 16 (google_apis) emulator image and wasn't exit-code-checked, so it silently no-op'd while reporting success | Now uses `svc wifi`/`svc data disable\|enable` (direct binder calls, exit codes checked, fails loudly). If it still appears to no-op, that's a real regression — don't assume it's the old bug recurring |
| A port you claimed gets reclaimed ~180s after handing off to another agent, even though that agent is still driving it with one-shot adb | `mg_keepalive_start` (armed by `mg_emu_up`) dies with the session that called it — a different agent continuing with one-shot adb has no live `flutter`/`dart`/`java`/`gradle` driver for the pool to recognize | `online-duo-up.sh` now arms a persistent `adb logcat` per serial (`mg_emu_arm_logcat_pin`) specifically for this — see the "Persistent adb attachment" note in the Quickstart section above. If you booted via a path that skips `online-duo-up.sh`, call `mg_emu_arm_logcat_pin` yourself after boot |
| **App Check: `PERMISSION_DENIED` storm on every Firestore/RTDB call** (matchmaking, room creation, presence all fail; app installs and launches fine) | `logcat` shows `com.google.firebase.appcheck` generating a fresh random debug UUID instead of reusing the pinned one. Two distinct causes — see "App Check debug token bootstrap" below for the full recipe: **(1)** `android/firebase_debug_token.dev.properties` is missing in this worktree (gitignored) so `BuildConfig.FIREBASE_APP_CHECK_DEBUG_TOKEN` is blank and `MainActivity` never writes anything; **(2)** the file IS present, but on a genuinely fresh app-data state (first install on a golden AVD, or an explicit `pm clear`) `MainActivity`'s SharedPreferences write raced and lost against the App Check SDK's own lazy token generation. | **(1)** `online-duo-up.sh` now auto-copies the file from the primary checkout at the top of the script (loud log line) and hard-fails with a clear message if neither copy exists — rerun the script, or copy `android/firebase_debug_token.dev.properties` manually from `/home/mrjack/git/mission-geo/android/`. **(2)** Write the SharedPreferences XML yourself via `adb shell run-as` before the app's first launch after a `pm clear` — see the exact recipe below. |

### App Check debug token bootstrap (the two traps above, in detail)

**Trap 1 — missing token file in a fresh worktree.** `android/firebase_debug_token.dev.properties` is gitignored (per-machine secret, see CLAUDE.md's "App Check (debug token pinned)"), so it does not exist in a freshly created worktree. `online-duo-up.sh` now handles this automatically (checks for the file before claiming any AVD, copies it from `/home/mrjack/git/mission-geo/android/firebase_debug_token.dev.properties` with a loud log line, hard-fails with a clear message if neither copy exists — same best-effort treatment for the `.prod` file, non-fatal since this harness never builds `--flavor prod`). If you're driving `flutter build`/`flutter run` directly instead of through the script, copy the file yourself first:
```bash
cp /home/mrjack/git/mission-geo/android/firebase_debug_token.dev.properties android/
```

**Trap 2 — the pm-clear race.** Even with the token file present, a genuinely fresh app-data state (first-ever install on a golden AVD image, or `adb shell pm clear app.missiongeo.dev`) can let the App Check SDK generate and persist its own random debug UUID before `MainActivity.onCreate`'s `installFixedAppCheckDebugTokenIfNeeded()` gets a chance to overwrite it with ours — 3 different random tokens were observed across 3 repeated `pm clear` cycles in practice. This does NOT happen on the harness's normal path (`mg_emu_install` uses `adb install -r -d`, which preserves existing app data across reinstalls) — only after an explicit `pm clear` or a truly first-ever install.

The reliable workaround is to write the token into the app's SharedPreferences XML directly, via `adb shell run-as`, **before the first launch**. The prefs file name is `com.google.firebase.appcheck.debug.store.<persistenceKey>`, written by `MainActivity.installFixedAppCheckDebugTokenIfNeeded()` (`android/app/src/main/kotlin/app/missiongeo/MainActivity.kt`). `persistenceKey` comes from the Firebase Android SDK (`FirebaseApp.getPersistenceKey()`, `firebase-common`): `base64UrlSafeNoPadding("[DEFAULT]") + "+" + base64UrlSafeNoPadding(<mobilesdk_app_id>)`, where `<mobilesdk_app_id>` is the dev flavor's `client_info.mobilesdk_app_id` in `android/app/src/dev/google-services.json` (the one whose `android_client_info.package_name` is `app.missiongeo.dev`) — deterministic per flavor, so this recipe computes it rather than hardcoding a value that would silently go stale if the Firebase project's app ID ever changes:

```bash
SERIAL=emulator-5554                          # the instance you're pre-seeding
PKG=app.missiongeo.dev
TOKEN=$(sed -n 's/^token=//p' android/firebase_debug_token.dev.properties)
APP_ID=$(python3 -c "
import json
d = json.load(open('android/app/src/dev/google-services.json'))
print(next(c['client_info']['mobilesdk_app_id'] for c in d['client']
           if c['client_info']['android_client_info']['package_name'] == '$PKG'))
")

b64usnp() { printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '=\n'; }
PREFS_NAME="com.google.firebase.appcheck.debug.store.$(b64usnp '[DEFAULT]')+$(b64usnp "$APP_ID")"

# pm clear (or a fresh install) wipes shared_prefs — do this AFTER that, BEFORE first launch:
adb -s "$SERIAL" shell pm clear "$PKG"     # or: fresh `adb install` (no -r) instead of clear
cat <<EOF | adb -s "$SERIAL" shell "run-as $PKG sh -c 'mkdir -p shared_prefs && cat > shared_prefs/${PREFS_NAME}.xml'"
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="com.google.firebase.appcheck.debug.DEBUG_SECRET">$TOKEN</string>
</map>
EOF

# Only NOW launch — the SDK reads the persisted token instead of racing to generate one:
adb -s "$SERIAL" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1
```

Verify it took: `adb -s "$SERIAL" logcat -d | grep -i "appcheck"` should show the token being reused, not generated; a `mg_chaos_tail_uid`/2-player scenario should stop seeing `PERMISSION_DENIED`. The `.prod` variant follows the identical formula against `android/app/src/prod/google-services.json` (package `app.missiongeo`, prefs written under `app.missiongeo`'s own shared_prefs) and `firebase_debug_token.prod.properties` — not spelled out here since this harness never boots `--flavor prod`.

## Discipline

1. **Never scale a presence/heartbeat/disconnect constant** — see the hard boundary above. If a future refactor moves one of these constants, re-verify the new location is still excluded before touching nearby code.
2. **Both instances, same build, always.** A single mismatched instance invalidates every timing assertion in this harness.
3. **Release your 2 ports when done** (`mg_emu_down`) — this is a 3-port shared pool, not a personal sandbox.
4. **Treat this as the validation gate**, not an optional nice-to-have, for any online-touching change — including Firebase cost-mitigation work that alters presence cadence (verify the new cadence still detects disconnects within its documented window).

## Red Flags — STOP

- About to claim an online/ranked fix is verified with only ONE instance → boot the second, this harness exists because single-instance testing missed these bugs before.
- About to scale a duration you're not sure is presence/heartbeat/disconnect-related → check the "Hard do-not-scale boundary" table above and the inline comments in the touched call site before wrapping it in `casual()`/`ranked()`.
- A chaos scenario doesn't reproduce what you expect on the unaccelerated build → don't just accept the accelerated result, re-run with `--online-speed 1 --ranked-speed 1` to rule out a scaling artifact.
