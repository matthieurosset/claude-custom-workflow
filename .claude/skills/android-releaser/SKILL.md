---
name: android-releaser
description: Use when releasing or managing Mission Geo on Google Play Console — building/uploading an AAB, deploying to internal/beta/production, promoting between tracks, bumping versionCode, updating store listing/screenshots/changelogs, managing staged rollouts, or regenerating Play Store screenshots via the debug-driven capture pipeline. Triggers on "release", "publier", "déployer sur Android", "Play Store", "Play Console", "fastlane", "supply", "track internal/beta/prod", "promouvoir", "changelog", "screenshot Play", "mettre à jour les screenshots", "regénérer les screens", "capture pipeline". Use BEFORE any release-related action.
---

# Android Releaser — Mission Geo Play Console

## Overview

**Iron Law:** every Play Console action that fastlane can handle goes through `android/fastlane/Fastfile` lanes — never through the Play Console UI for things fastlane manages (AAB upload, track promotion, listing texts, changelogs, screenshots, staged rollouts). The Play Console UI is only for what fastlane can't touch (content rating, data safety, etc. — see "What fastlane CAN'T do" below).

The pipeline is set up — service account, signing key, lanes are all live. Mission Geo is currently on the **internal** track only. The first production release is the immediate target.

**Sources of truth:**
- `android/fastlane/Fastfile` — every lane
- `android/fastlane/Appfile` — package_name + JSON key path
- `android/fastlane/play-console-key.json` — service account credentials (**gitignored — never commit, never paste anywhere**)
- `android/fastlane/metadata/android/<locale>/` — listing texts, changelogs, images
- `pubspec.yaml` line `version: X.Y.Z+N` — `+N` is the Play versionCode
- Memory: `[[project-fastlane-play-pipeline]]`, `[[feedback-worktree-signing-symlinks]]`

## When to Apply

**Apply BEFORE any of:**
- Releasing a new build (any track)
- Promoting a release between tracks
- Editing Play Store listing (title, description, screenshots, changelogs)
- **Regenerating Play Store screenshots** (see "Updating screenshots" below — has its own apply-patch workflow)
- Configuring or troubleshooting staged rollouts
- Bumping versionCode for a release
- User says "release", "publier", "déployer", "push to Play", "promouvoir prod", "release notes", "mettre à jour les screenshots", "regénérer les screens"

**Skip for:**
- Reading existing Fastfile/Appfile to understand the setup
- Pure code work that doesn't touch release artifacts
- Crashlytics/Analytics investigations (use `mission-geo-analytics` instead)
- Local-only debug/profile builds (no Play involvement)

## Pipeline anatomy

```
android/
├── key.properties                      # Symlinked from main worktree (signing — gitignored)
├── firebase_debug_token.properties     # Symlinked from main worktree (gitignored)
├── app/build.gradle.kts                # Reads pubspec versionCode/Name via flutter.*
└── fastlane/
    ├── Appfile                         # package_name + json_key_file
    ├── Fastfile                        # 6 lanes (see below)
    ├── play-console-key.json           # Service account credentials (GITIGNORED)
    └── metadata/android/<locale>/
        ├── title.txt                   # ≤30 chars
        ├── short_description.txt       # ≤80 chars
        ├── full_description.txt        # ≤4000 chars
        ├── video.txt                   # YouTube URL, optional, ≤100 chars
        ├── changelogs/<N>.txt          # MANDATORY for each shipped versionCode N, ≤500 chars
        └── images/                     # featureGraphic.png + icon.png (flat) + phoneScreenshots/ sevenInchScreenshots/ tenInchScreenshots/ (subfolders)
```

> ### Iron rule: changelogs, every locale, every time
>
> Whenever a `changelogs/<N>.txt` is created or edited, write it in **all six** locale dirs (`fr-FR`, `en-US`, `de-DE`, `sr`, `es-ES`, `hr`) in the same change. No exceptions — mirrors CLAUDE.md's i18n iron rule.
>
> - Each locale file must be a **real translation** of the fr-FR source — never a copy-paste of the French text, never left stale from a previous versionCode.
> - Never ship a **subset** of locales — a listing update visible in 5 languages and silently missing in the 6th is a shipped bug just like a missing UI string.
> - The pre-flight loop below ("Changelog file exists… in every locale") is the enforcement check — it must pass with 0 `MISSING` lines before `deploy_internal`/`release_internal`.

`pubspec.yaml` controls versioning:
```yaml
version: 1.0.0+2   # ↑ versionName (1.0.0)  ↑ versionCode (2) — must increment for every release
```

### "Quoi de neuf ?" popup — before a player-facing release

If this release adds player-facing content (new mode/season/country/dataset/game content — never a fix, refactor, or perf work), add a `WhatsNewEntry` for the new versionCode in `lib/core/config/whats_new_config.dart`, plus its 6 locale keys under a `whatsNew.items.*` namespace in `lib/i18n/*.i18n.json`, then `dart run slang`. Fixes/perf/refactors → no entry, ship silently. See memory `whats-new-user-facing-content-only`.

## Quick Reference — Lanes

All lanes run from `android/` with bundler (Gemfile at repo root).

| Lane | Cmd (prefix `bundle exec --gemfile=../Gemfile fastlane`) | What | When |
|---|---|---|---|
| `ping` | `fastlane ping` | Smoke test — fastlane version + package_name + pubspec version | Sanity-check setup |
| `bump` | `fastlane bump` | Increments `+N` in pubspec.yaml. **Modifies a tracked file — commit it after.** | Before every release (Play rejects duplicate versionCode) |
| `build` | `fastlane build` | `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab` (requires `android/key.properties` for signing) | Local AAB build, no upload |
| `deploy_internal` | `fastlane deploy_internal` | Uploads existing AAB to track `internal`, `release_status: completed`. **Skips metadata/images/screenshots** — never auto-overwrites listing. Uploads changelog (needs `changelogs/<N>.txt`). | After `bump` + `build` |
| `release_internal` | `fastlane release_internal` | One-shot: `bump` + `build` + `deploy_internal` | Standard ship-to-internal command |
| `promote_internal_to_production` | `fastlane promote_internal_to_production` | Promotes the latest internal release to production (no AAB re-upload, no listing/changelog touch) | Graduation step (after internal validation) |

**For extra control** (validate-only, custom track, staged rollout) — invoke `supply` directly:
```bash
bundle exec --gemfile=../Gemfile fastlane run supply \
  track:production validate_only:true \
  skip_upload_aab:true skip_upload_apk:true
```

## MANDATORY: Regression suite gate (BLOCKING — runs BEFORE build/upload)

**This step is mandatory and blocking.  A FAIL stops the release — do not
proceed to step 2 or beyond until the suite is green.**

Run the smoke regression suite against the phone AVD + Firebase emulator:

```bash
.claude/skills/regression-suite/run.sh --tier smoke
```

If the suite PASSES, continue.  If it FAILS:
1. Identify the failing scenario from the expanded reporter output.
2. Fix the regression (in a feature branch — never directly on main).
3. Re-run the suite.  Only proceed when all smoke scenarios are green.

**Rationale:** Several alpha regressions (DatasetSource routing, dataset picker
filter, FR overseas territories) shipped undetected because no end-to-end gate
existed.  This suite closes that gap.  The gate runs on the `dev` flavor
(never writes to prod; consistent with `[[feedback_no_device_builds_without_greenlight]]`).

---

## Mandatory pre-flight before any deploy (build/upload checklist)

1. **Symlinks present** (in any worktree other than main) — see `[[feedback-worktree-signing-symlinks]]`:
   ```bash
   ln -s /home/mrjack/git/mission-geo/android/key.properties android/key.properties
   ln -s /home/mrjack/git/mission-geo/android/firebase_debug_token.properties android/firebase_debug_token.properties
   ```
2. **Changelog file exists** for the versionCode about to ship — in **every locale** (see the iron rule above: real translations, never a subset):
   ```bash
   N=$(grep '^version:' pubspec.yaml | sed 's/.*+//')
   for loc in fr-FR en-US de-DE sr es-ES hr; do
     [ -f android/fastlane/metadata/android/$loc/changelogs/$N.txt ] || echo "MISSING $loc/changelogs/$N.txt"
   done
   ```
3. **`supply validate_only`** dry-run — catches char-limit violations, missing changelogs, auth issues:
   ```bash
   bundle exec --gemfile=../Gemfile fastlane run supply \
     track:internal validate_only:true \
     skip_upload_aab:true skip_upload_apk:true \
     skip_upload_metadata:false skip_upload_changelogs:true \
     skip_upload_images:true skip_upload_screenshots:true
   ```

## Track strategy

```
internal  →  beta  →  production
   │           │           ▲
   └───────────┴───── promotion (no AAB re-upload) ─────┘
```

- **internal** (≤100 testers, no Google review): every dev build. Default for `release_internal`.
- **beta** (open or closed, light review): pre-prod hardening.
- **production** (full review, public): cannot un-publish — only release a new versionCode.

**Promote vs re-upload:**
- Same versionCode moves between tracks → `promote_internal_to_production` (or custom supply call with `track_promote_to:`).
- New versionCode → `release_internal` first, validate, then promote.

**Staged rollout (production only):**
```bash
bundle exec --gemfile=../Gemfile fastlane run supply \
  track:production track_promote_to:production \
  release_status:inProgress rollout:0.05    # 5% → bump to 0.20, 0.50, 1.0 iteratively
```
- Halt: `release_status:halted` (stops new installs, existing keep)
- Resume: re-run with `release_status:inProgress` and new `rollout`
- Finalize: `release_status:completed` (drops `userFraction`, ships 100%)

## Metadata management

### Locale mapping

Mission Geo in-app locales = `fr`, `en`, `de`, `sr-Latn`, `es`, `hr`. Play Console uses different codes:

| In-app | Play Console folder | Notes |
|---|---|---|
| `fr` | `fr-FR` | Default |
| `en` | `en-US` | Use `en-US` not `en-GB` |
| `de` | `de-DE` | |
| `sr-Latn` | `sr` | **Play does NOT support `sr-Latn`** — use `sr`, content must be in Latin script |
| `es` | `es-ES` | |
| `hr` | `hr` | |

Every text file must exist in ALL 6 locales when shipping prod.

### Character limits (Play API enforced)

| Field | Max | File |
|---|---|---|
| Title | 30 | `title.txt` |
| Short description | 80 | `short_description.txt` |
| Full description | 4000 | `full_description.txt` |
| Changelog (per version, per locale) | 500 | `changelogs/<N>.txt` |
| Video URL | 100 | `video.txt` |

`supply validate_only` rejects over-limit content before upload.

### Default Fastfile skip behavior

`deploy_internal` and `promote_internal_to_production` ship with:
```
skip_upload_metadata: true       # listing text NEVER auto-overwritten
skip_upload_images: true         # featureGraphic/icon NEVER auto-overwritten
skip_upload_screenshots: true    # screenshots NEVER auto-overwritten
skip_upload_changelogs: false    # changelogs DO upload (per-versionCode)
```

**Why:** listing/screenshots evolve at a different cadence than the AAB. A typo fix on listing shouldn't require a new build. A new AAB shouldn't risk wiping curated screenshots.

### Intentionally updating listing / screenshots

When you DO want to push listing or screenshots, run `supply` directly with the flags off and an explicit `version_code` (so it knows which changelog applies):
```bash
bundle exec --gemfile=../Gemfile fastlane run supply \
  track:internal version_code:<N> \
  skip_upload_aab:true skip_upload_apk:true \
  skip_upload_metadata:false skip_upload_images:false skip_upload_screenshots:false \
  skip_upload_changelogs:false
```

## Listing & screenshots — what to ship

### Screenshot specs (Play Store)

| Slot | Folder | Count | Aspect | Min/Max | Mission Geo |
|---|---|---|---|---|---|
| Phone | `phoneScreenshots/` | 2–8 | Portrait 9:16 (app is portrait-locked) | 320 short / 3840 long | **8 × 6 locales = 48** |
| 7" tablet | `sevenInchScreenshots/` | 1–8 | Portrait | same | **8 × 6 locales = 48** |
| 10" tablet | `tenInchScreenshots/` | 1–8 | Portrait | same | **8 × 6 locales = 48** |
| TV | `tvScreenshots/` | — | — | — | N/A |
| Wear | `wearScreenshots/` | — | — | — | N/A |

**Naming**: prefix with `01_`, `02_`, … to lock order on Play Store (files uploaded in lexicographic order).

### Mission Geo shot list (8 shots, same set on all 3 device tiers)

| # | File | Screen | State |
|---|---|---|---|
| 1 | `01_adventure_regions.png` | Adventure regions list | Mixed progress + locked tile |
| 2 | `02_landmark_taj_mahal.png` | Landmark typing | Taj Mahal photo + question |
| 3 | `03_drawing_south_africa.png` | Drawing game | 🇿🇦 ~50% coloured (fallback 🇧🇷) |
| 4 | `04_searching_chile.png` | Searching/map | "Trouve le Chili", zoomed on South America |
| 5 | `05_ranked_vs.png` | Ranked intro | Countdown frozen at 3 |
| 6 | `06_booster_open.png` | Booster reveal | Gold booster, Japan card revealed |
| 7 | `07_collection_album.png` | Collection album | Europe sticker page 1, ~50% owned |
| 8 | `08_defi_classement_population.png` | Classement Défi | Population: NG/BR/MX placed (3/5), JP+DE in pool |

### Graphics specs

| Slot | File path | Spec |
|---|---|---|
| Feature graphic | `images/featureGraphic.png` | **Exactly 1024×500 px**, JPEG or 24-bit PNG **without alpha**, ≤8 MB |
| Icon | `images/icon.png` | 512×512, 32-bit PNG **with alpha** |
| TV banner | `images/tvBanner.png` | 1280×720 — N/A (no TV build) |
| Promo graphic | `images/promoGraphic.png` | 180×120 — legacy, optional |

These are **flat single files inside `images/`** — not subfolders. `supply` discovers them at `metadata/android/<locale>/images/<type>.{png,jpg,jpeg}` (`supply/lib/supply.rb:21`). A subfolder layout silently uploads nothing (the run completes in <1 s with no `⬆️ Uploading image` lines, just `Uploaded all items` — useless).

Mission Geo's original 4 feature graphics (fr-FR, en-US, de-DE, sr) were produced externally via the ChatGPT prompt (see [[project-fastlane-play-pipeline]]) and dropped at `images/featureGraphic.png` — they remain hand-tuned and are never regenerated by the script below.

**New locales (es-ES, hr onward): `scripts/frame_feature_graphic.py`.** Composites the 1024×500 feature graphic procedurally from `assets/store/feature_graphic_base.png` (background artwork, shared across all locales) + the locale's `t.splash.tagline` string (bottom-left, white DynaPuff, orange underline swoosh) + the MISSION GEO logo badge (right side). It reuses `ACCENT`/`WHITE`/`load_font`/`paste_logo`/`parse_words`/`wrap_lines` from `frame_screenshots.py`, so headline wrapping follows the same NBSP-glue rules (see below).

```bash
python3 scripts/frame_feature_graphic.py --locale es-ES
python3 scripts/frame_feature_graphic.py --locale hr
```

⚠️ Called with no `--locale`, it regenerates **all 6** locale folders in `LOCALE_I18N_FILE` — including the 4 hand-tuned ones. Always pass `--locale <code>` for a single new locale; never run it bare unless you intend to overwrite fr-FR/en-US/de-DE/sr too.

Calibration was tuned against the 4 existing hand-made graphics (en-US and de-DE reproduce pixel-identical; fr-FR and sr wrap to a slightly different — but clean — line break, because the originals were hand-tuned per locale rather than generated from one shared `MAX_TEXT_W`).

## Updating screenshots — two-stage pipeline

**Trigger phrases:** *"mettre à jour les screenshots", "regénérer les screens / screenshots", "refresh les captures", "redo the Play Store screenshots", "update screenshots".*

See also: `scripts/README_store_assets.md` for the framing-tool contract.

### Architecture

The pipeline has two discrete stages:

```
Stage 1 — CAPTURE (capture_play_screenshots.sh)
  Raw masters → android/fastlane/screenshot_sources/<device>/<locale>/<key>.png

Stage 2 — FRAME (frame_screenshots.py)
  Raw masters → framed marketing PNGs → android/fastlane/metadata/android/<locale>/images/<deviceDir>/<key>.png
```

**Why two stages:** framing can be re-run/tweaked (copy, geometry, bezel) without re-capturing. Each stage is independent and reproducible.

**Why committed code and not a patch:** screenshot hooks live in `lib/core/dev/screenshot_config.dart` and the callsites in several game files. Every hook is gated on `kIsDevFlavor` which is `const false` in prod builds — the compiler eliminates the branches entirely. Zero prod footprint, no patch lifecycle to manage.

### What the committed hooks do

| File | Role |
|---|---|
| `lib/core/dev/screenshot_config.dart` | `ScreenshotScenario` enum, `ScreenshotConfig` singleton (`scenario` mutable static, `active` getter, `initFromIntent()`, `pushScenarioRoute()`), per-scenario helpers |
| `MainActivity.kt` | `configureFlutterEngine` override with `mission_geo/screenshot` MethodChannel piping `screenshot_scenario` + `screenshot_locale` intent extras to Dart |
| `lib/main.dart` | `if (kIsDevFlavor) await ScreenshotConfig.initFromIntent()` before runApp; hides debug banner when active |
| `lib/pages/splash/splash_screen.dart` | Fast-bypass branch skips Firebase auth + sync (emulator Play Services too old); pushes the scenario route |
| `lib/pages/modes/ranked/ranked_match_page.dart` | Freeze countdown + inject fake p2 opponent for `rankedVs` |
| `lib/pages/modes/adventure/widgets/region_carousel.dart` | Force Pays tab (index 1) for `adventureCountries` |
| `lib/pages/modes/booster/booster_album_page.dart` | Override album initial page + `goToPage` for `collectionAlbum` |
| `lib/pages/modes/booster/booster_open_page.dart` | Skip sachet phase, pre-load cards, trigger first reveal for `boosterReveal` |
| `lib/core/services/datasets/dataset_install_registry.dart` | Bypass `isInstalled()` for CH + IT datasets when `adventureCountries` active |
| `lib/pages/games/drawing/state/drawing_game_provider.dart` | Pre-fill biggest 50% zones with correct colour via `screenshotDrawingPrefillRatio()` |
| `lib/pages/games/drawing/widgets/color_palette.dart` | Scroll palette 60 px for `drawingSouthAfrica` |
| `lib/pages/games/searching/state/searching_game_provider.dart` | `showCorrectAnswer=true, isCorrect=true` for `searchingChile` |
| `lib/pages/games/searching/widgets/map_canvas.dart` | Continental zoom (width/60 clamped 9–16) + suppress zoom-on-correct animation for `searchingChile` |
| `lib/pages/modes/defi/classement/state/classement_provider.dart` | Forced NG/BR/MX/JP/DE population round via `screenshotClassementSpec()` |
| `lib/pages/debug/debug_launcher_page.dart` | 'Screenshots Play Store' section with one `_LaunchTile` per scenario for interactive preview |

### Prerequisites

1. **Emulator via the shared pool** — claim one of the 3 pool ports (5554/5556/5558) atomically so the capture never collides with a parallel agent. The capture script auto-detects the device type from the **booted AVD name** (`mission_geo_phone` / `mission_geo_tablet7` / `mission_geo_tablet10`), so just boot the AVD you want to shoot. **Never `emu kill` an emulator you didn't start** — release only your own port.

   ```bash
   source "$(git rev-parse --show-toplevel)/.claude/skills/shared/emulator-pool.sh"
   mg_claim_port
   mg_boot_avd mission_geo_phone          # phone screenshots first
   # then capture the tablet tiers by swapping on the SAME port:
   #   mg_swap_avd mission_geo_tablet7
   #   mg_swap_avd mission_geo_tablet10
   # when fully done:  mg_release_port
   ```

2. **Worktree symlinks** present (signing + App Check debug token) — see [[feedback-worktree-signing-symlinks]]. The orchestrator builds a DEBUG APK; without the App Check debug token, Firebase calls would hang on the splash.

3. **Branch + worktree** for this work — never on `main` directly.

### The full workflow (5 steps)

```bash
# ── Step 1 — Capture raw masters per device tier
# Phone first (seeds the DB for tablets to reuse):
.claude/skills/android-releaser/scripts/capture_play_screenshots.sh emulator-5554
# ↳ Builds dev-flavor debug APK (APP_FLAVOR=dev → kIsDevFlavor=true → hooks active).
# ↳ Installs + adb-root + walks onboarding once (UMP refuse + pseudo "Sam" + Asia region).
# ↳ Seeds the DB (2450 miles, 5 hints, 4 unlocked continents + datasets, level-10 XP, ~50% album).
# ↳ Loops 8 scenarios × 6 locales = 48 captures (~21 min).
# ↳ Writes RAW masters to android/fastlane/screenshot_sources/phone/<locale>/<key>.png.

# Then swap AVD and repeat for tablet7 and tablet10 (reuses the seeded DB from /tmp):
# mg_swap_avd mission_geo_tablet7
# .claude/skills/android-releaser/scripts/capture_play_screenshots.sh emulator-5554
# mg_swap_avd mission_geo_tablet10
# .claude/skills/android-releaser/scripts/capture_play_screenshots.sh emulator-5554

# ── Step 2 — Visually verify raw masters (NOT optional)
for loc in fr-FR en-US de-DE sr es-ES hr; do
  mkdir -p /tmp/mg-previews/$loc
  for f in android/fastlane/screenshot_sources/phone/$loc/*.png; do
    convert "$f" -resize 400x "/tmp/mg-previews/$loc/$(basename $f)"
  done
done
# Read each /tmp/mg-previews/<loc>/<key>.png. Check:
#   - Target screen reached (not stuck on splash/Home).
#   - Locale strings rendering (German/Serbian Latin etc.).
#   - State correctly injected (Chile green, half-filled ZA flag, VS intro frozen at 3, etc.).
#   - 2450 miles + 5 hints visible in adventure shots.
# Re-run a single scenario if something is off:
#   capture_play_screenshots.sh emulator-5554 searchingChile fr-FR

# ── Step 3 — Wipe stale framed metadata (prevents old-key PNGs from shipping)
for loc in fr-FR en-US de-DE sr es-ES hr; do
  rm -f android/fastlane/metadata/android/$loc/images/phoneScreenshots/*.png
  rm -f android/fastlane/metadata/android/$loc/images/sevenInchScreenshots/*.png
  rm -f android/fastlane/metadata/android/$loc/images/tenInchScreenshots/*.png
done

# ── Step 4 — Frame all raw masters
pip install pillow   # if not yet installed
python3 scripts/frame_screenshots.py
# ↳ Reads screenshot_sources/<device>/<locale>/<key>.png
# ↳ Writes framed PNGs to metadata/android/<locale>/images/<deviceDir>/<key>.png
# ↳ Applies brand gradient, device bezel, MISSION GEO stamp, localized headline.
# ↳ Run with --device phone / --only 01_adventure_regions to re-frame a subset.

# ── Step 5 — Review and commit only the framed diff
git status    # should show only metadata/.../images/**/*.png changes
git add android/fastlane/metadata/android/*/images/
git add android/fastlane/screenshot_sources/   # commit raw masters too
git commit -m "chore(screenshots): regenerate Play Store screenshots vX"
```

### Filtering (faster iteration on one scenario)

```bash
# Single scenario, all 6 locales
.claude/skills/android-releaser/scripts/capture_play_screenshots.sh emulator-5554 landmarkTaj

# Single scenario, single locale (fastest — ~45s)
.claude/skills/android-releaser/scripts/capture_play_screenshots.sh emulator-5554 landmarkTaj fr-FR

# Multiple scenarios + multiple locales
.claude/skills/android-releaser/scripts/capture_play_screenshots.sh emulator-5554 drawingSouthAfrica,searchingChile fr-FR,en-US
```

Current shipping scenarios (must match the `ScreenshotScenario` enum):
`adventureRegions`, `landmarkTaj`, `drawingSouthAfrica`, `searchingChile`, `rankedVs`, `boosterReveal`, `collectionAlbum`, `defiClassementPopulation`.

Retained for manual debug but NOT in the automated run:
`homeWithProgress`, `adventureCountries`, `rankingSwissBrazil`, `duelLocal3Players`.

### Adding or changing a scenario

When the shot list evolves (new feature, replace an old scenario, change state injection):

1. **Edit `lib/core/dev/screenshot_config.dart`**:
   - Add a value to `ScreenshotScenario` enum.
   - Add a deep route in `_routeFor` (path-only routes) OR add a `case` in `pushScenarioRoute` (typed routes with constructor args).
   - If the scenario needs state injection, add a `screenshotXxxSpec()` helper that returns `null` outside the scenario.
2. **Hook the helper** in the target page/notifier. Gate every override on `ScreenshotConfig.scenario == ScreenshotScenario.xxx` (always inside a `kIsDevFlavor` check or after `ScreenshotConfig.active`).
3. **Add a `_LaunchTile`** in the 'Screenshots Play Store' section of `lib/pages/debug/debug_launcher_page.dart` for interactive testing.
4. **Update `ALL_SCENARIOS`** in `capture_play_screenshots.sh` with the new stem.
5. **Update `SCREENS`** in `scripts/frame_screenshots.py` with the new key + 4-locale headlines.
6. **Iterate**: use the Debug screen tile first, then run the orchestrator filtered to your scenario:
   ```bash
   .claude/skills/android-releaser/scripts/capture_play_screenshots.sh emulator-5554 myNewScenario fr-FR
   ```
7. **Commit** `screenshot_config.dart` + callsite + debug tile + orchestrator + frame_screenshots.py together.

### Common pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| Capture shows the splash screen ("Chargement…") | Splash bypass took longer than 30 s (cold APK install) | Re-run the single scenario — second pass uses warm caches. If persistent, increase the `sleep 30` in the orchestrator |
| Capture shows Home instead of target scenario | Typed route not registered in `pushScenarioRoute` | Add a `case` in `pushScenarioRoute` for the scenario |
| State override doesn't apply | Notifier race: `_initialize()` overwrites the injected state | Apply the override at the EARLIEST notifier write for that field |
| Wrong locale in capture | `initFromIntent()` didn't receive the locale extra | Check Kotlin `getLocale` handler via `adb shell dumpsys activity \| grep -A2 screenshot_locale` |
| Soft keyboard typing fails via `adb shell input text` | Flutter's IME bridge swallows raw text events | Use per-key `input tap` against UIAutomator-dumped bounds — see `landmarkTaj` case in the orchestrator |
| Hooks not active (scenario stays `none`) | Built without dev flavor | Build with `--flavor dev --dart-define=APP_FLAVOR=dev` (the orchestrator does this automatically) |
| Two agents fight over the same port | Both tried to self-allocate a port without the pool | Always `source .claude/skills/shared/emulator-pool.sh` + `mg_claim_port` |
| Old-key PNGs shipping with new captures | Stale framed metadata not wiped before framing | Always run Step 3 (wipe `metadata/.../images/`) before `frame_screenshots.py` |
| Framing shows wrong/missing headline | SCREENS key doesn't match the capture stem | Check that `frame_screenshots.py` SCREENS keys exactly match ALL_SCENARIOS stems in the capture script |

### After framing: ship the screenshots

Upload framed metadata PNGs via `supply` (see "Intentionally updating listing / screenshots" above):

```bash
N=$(grep '^version:' pubspec.yaml | sed 's/.*+//')
bundle exec --gemfile=../Gemfile fastlane run supply \
  track:internal version_code:$N \
  skip_upload_aab:true skip_upload_apk:true \
  skip_upload_metadata:true skip_upload_images:true \
  skip_upload_screenshots:false skip_upload_changelogs:true
```

`skip_upload_screenshots:false` is the only flag you really need; everything else stays untouched.

## What fastlane CAN'T do (Play Console UI only)

No fastlane equivalent — manual Play Console work, typically once during initial production setup:

| Field | Location |
|---|---|
| **IARC content rating questionnaire** | Production → App content → Content ratings |
| **Data safety form** | Production → App content → Data safety |
| **Target audience and content** | Production → App content → Target audience |
| **Ads declaration** | Production → App content → Ads |
| **Government / news app status** | Production → App content |
| **Pricing & distribution** | Production → Distribution (country availability matrix) |
| **Pre-registration** | Growth → Pre-registration |
| **Store listing experiments (A/B)** | Growth → Store listing experiments |
| **User review replies** | Quality → Ratings and reviews |
| **In-app products / subscriptions** | Monetisation → Products |
| **App signing key rotation** | Setup → App signing |

These don't re-occur per release. If a fresh prod release is blocked with "App content declarations incomplete", first fix the missing forms in Play Console UI, then re-run the supply call — fastlane retries automatically when `rescue_changes_not_sent_for_review: true` (default).

## Validate before shipping production

```bash
# 1. Dry-run validate
bundle exec --gemfile=../Gemfile fastlane run supply \
  track:production validate_only:true skip_upload_aab:true skip_upload_apk:true \
  skip_upload_metadata:false skip_upload_images:false skip_upload_screenshots:false \
  skip_upload_changelogs:true

# 2. Check all 6 locales have content
for loc in fr-FR en-US de-DE sr es-ES hr; do
  for f in title short_description full_description; do
    [ -s android/fastlane/metadata/android/$loc/$f.txt ] || echo "MISSING $loc/$f.txt"
  done
done

# 3. Check changelog exists for current versionCode (in all locales)
N=$(grep '^version:' pubspec.yaml | sed 's/.*+//')
for loc in fr-FR en-US de-DE sr es-ES hr; do
  [ -f android/fastlane/metadata/android/$loc/changelogs/$N.txt ] || echo "MISSING $loc/changelogs/$N.txt"
done

# 4. Check screenshot counts (every locale, every device type)
for loc in fr-FR en-US de-DE sr es-ES hr; do
  for dev in phoneScreenshots sevenInchScreenshots tenInchScreenshots; do
    count=$(ls android/fastlane/metadata/android/$loc/images/$dev 2>/dev/null | wc -l)
    echo "$loc/$dev: $count"
  done
done
```

Only after all 4 return clean → run `release_internal` then `promote_internal_to_production` (or `supply` with staged rollout).

## Red Flags — STOP

| Symptom | Cause | Action |
|---|---|---|
| `Cannot find changelog because no version code given` | Metadata-only run without `version_code:N` | Add `version_code:N` to the supply call |
| `Execution failed for task ':app:signReleaseBundle' > NullPointerException` | Missing `key.properties` symlinks in worktree | See [[feedback-worktree-signing-symlinks]] |
| `Changes cannot be sent for review automatically` | First time on a track / pending Play Console declarations | Default `rescue_changes_not_sent_for_review:true` retries with the flag; if it persists, fix the declaration in Play Console UI manually |
| `Invalid release - cannot have status completed with rollout fraction` | Mixed `release_status:completed` with `rollout:` | Use `release_status:inProgress` for staged rollouts |
| AAB size > 200 MB warning | Bundle is heavy (Mission Geo ~220 MB) | Set `ack_bundle_installation_warning:true` if Play rejects (currently auto-acked, may break in future) |
| About to push to **production** | Highest-risk action | MUST validate dry-run + show diff + get explicit user OK before |
| Updating screenshots / listing | Overwrites carefully-curated content | Always show user what's about to change first, get explicit OK |
| Service account key visible in `git status` | Catastrophic credential leak | `git restore --staged android/fastlane/play-console-key.json` immediately; if pushed, **rotate the key in GCP** then `bfg` / `git filter-repo` history |
| User says "merger" or "ça marche" | Validation, not push authorization | Merge is OK, but `git push origin main` requires SEPARATE explicit user approval — see `[[feedback-merge-does-not-imply-push]]` |
| Committing PNG screenshots mixed with Dart/Kotlin edits | Screenshot PNG diff should be isolated — review shows both code and assets | Check `git status`: only `metadata/.../phoneScreenshots/*.png` should be in the diff for a pure screenshot update run. Code changes belong in their own commit. |

## Recovery

### "Production rollout going badly"
```bash
# Halt — existing installs OK, no new ones
bundle exec --gemfile=../Gemfile fastlane run supply \
  track:production track_promote_to:production \
  release_status:halted version_code:<N>
```
Fix forward in next versionCode. Play Store doesn't support true rollback — only ship a fixed new versionCode.

<!-- trigger: tentative d'annulation v27 alpha, 4 échecs, 2026-07-08 -->
### "Cancel/undo a test-track release (internal/alpha/beta)"
Impossible — `release_status:halted` and staged rollout only exist for `production` (see Track strategy). Interrupting the upload mid-flight, or re-pointing to a lower versionCode, does NOT un-ship what testers already have: Play's anti-downgrade check rejects a lower versionCode with a 403 at commit. Only levers: ship a HIGHER versionCode with the fix, or manually pause the track / drop testers in the Play Console UI.

**Fastlane trap:** `supply` run with every `skip_upload_*` flag set commits an EMPTY edit and prints "Successfully finished" without ever calling `tracks().update` — the exit code proves nothing happened. Verify any track mutation by re-reading `edits().tracks().get`, never by trusting the CLI output alone.

### "Service account key compromised"
1. Revoke in GCP Console → IAM → Service accounts → `play-console-release@…` → Keys → delete
2. Generate new JSON key from the same service account
3. Drop into `android/fastlane/play-console-key.json` (same path, gitignored — no code change)
4. Verify with `bundle exec fastlane ping`

### "I bumped versionCode but the build failed"
```bash
git restore -- pubspec.yaml
```
Bump reverted. Re-run `release_internal` after fixing the build issue.

### "I committed the JSON key by mistake"
**Immediate:**
1. **Revoke the key in GCP NOW** (the file IS the credential — assume leak the moment it's in any commit)
2. Remove from git history (`git filter-repo` or BFG, not just `git rm`)
3. Generate new key, place at same path
4. Confirm `.gitignore` covers `android/fastlane/play-console-key.json`
5. Force-push only after explicit user approval

## Sub-skills required

- **`git-workflow-branch-worktree`** — REQUIRED before any change to fastlane configs or metadata. Release work is still code work, never on `main` directly.
- **`visual-validation-android`** — REQUIRED when capturing screenshots. Drives the Android emulator + captures PNG via `adb`.
- **`mission-geo-design-system`** — when producing the feature graphic or icon: colors must come from `AppColors`, typography from DynaPuff (display) / Quicksand (body).

## References

- [Fastlane `supply` reference](https://docs.fastlane.tools/actions/supply/)
- [Play Console — Track structure](https://support.google.com/googleplay/android-developer/answer/9845334)
- [Play Console — Preview assets specs](https://support.google.com/googleplay/android-developer/answer/9866151)
- [Google Play Developer API — Edits model](https://developers.google.com/android-publisher/edits)
- Memory: `[[project-fastlane-play-pipeline]]` — service account, lanes, locale mapping
- Memory: `[[feedback-worktree-signing-symlinks]]` — required symlinks for release builds in worktrees
- Memory: `[[feedback-merge-does-not-imply-push]]` — never push without explicit user approval
