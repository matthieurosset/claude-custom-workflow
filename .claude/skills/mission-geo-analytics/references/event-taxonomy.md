# Event taxonomy — full reference

All custom events go through `FirebaseAnalyticsService` (`lib/core/services/firebase/firebase_analytics_service.dart`). Each entry below shows the param surface, the call site, and notes that affect interpretation in BigQuery.

Param shapes use GA4 types in `event_params`:
- string → `event_params.value.string_value`
- int    → `event_params.value.int_value`
- double → `event_params.value.double_value`

Booleans are encoded as 0/1 ints (not GA4 booleans, which don't exist in BQ export).

## Automatic events (no code)

| Event | Notes |
|---|---|
| `app_open` | Fires on every cold start and bring-to-foreground |
| `first_open` | Fires once per install. Useful as the install marker for D1/D7 retention. |
| `session_start` | Defines the session boundary (30 min idle = new session) |
| `session_engagement` / `user_engagement` | Quality signals |
| `screen_view` | Logged by `AnalyticsNavigatorObserver` on every AutoRoute push. `firebase_screen` param holds the route name (e.g. `AdventureHomeRoute`) |
| `app_exception` | Logged when Crashlytics catches a fatal — useful to join crashes to a session |
| `app_update`, `os_update` | Lifecycle |

## Onboarding (2)

### `onboarding_step_completed`
Where: `lib/pages/onboarding/onboarding_page.dart` — emitted after username step and after consent decision.

| Param | Type | Notes |
|---|---|---|
| `step` | string | `username` or `consent` |

The first emission (`step=username`) happens BEFORE the user has decided on consent. Firebase Analytics is initialised with `setAnalyticsCollectionEnabled(false)` at app start; the SDK buffers events in memory and drops them on flush if the collection stays disabled. So in practice this event only reaches GA4 if the user then accepts consent (the SDK flushes the buffer at that point).

### `onboarding_finished`
Where: emitted after the consent decision in `OnboardingPage._decideConsent`.

| Param | Type | Notes |
|---|---|---|
| `consent_analytics` | int (0/1) | Did the user accept analytics |
| `consent_crash` | int (0/1) | Did the user accept crash reports |

Only fires when the user accepted (collection is OFF otherwise), so in BigQuery the count of this event ≈ the count of users who finished onboarding AND accepted analytics. Refusals are invisible by design.

## Navigation (1)

### `mode_entered`
Where: `lib/pages/home/page.dart` (each card's onTap), `lib/pages/home/widgets/daily_mission_banner.dart`.

| Param | Type | Values |
|---|---|---|
| `mode` | string | `adventure` / `multiplayer` / `defi` / `ranking` / `daily` |

Use this for "which mode is most popular" — it counts taps on the entry card, not deeper engagement. Pair with subsequent events (`activity_completed`, `challenge_finished`, etc.) for engagement depth.

## Adventure (7)

### `region_unlocked`
Where: `lib/providers/adventure_provider.dart._logRegionUnlocked` — fires for all unlock paths (starting region, miles unlock, progressive unlock).

| Param | Type | Notes |
|---|---|---|
| `region_id` | string | E.g. `westernNorthernEurope`, `switzerlandCantons`. See `adventure_regions_config.dart`. |
| `miles_spent` | int | 0 for starting region or legacy miles path; ≥0 for progressive unlocks |
| `unlock_index` | int | 1-based count AFTER the unlock (so 1 = first region, 2 = second, etc.) |

Useful for "which region is unlocked first" (filter `unlock_index = 1`) and "average cost to reach the 5th region" (group by `unlock_index`, average `miles_spent`).

### `region_opened`
Where: `lib/pages/modes/adventure/region_detail_page.dart` — `RegionDetailPage.initState`, post-frame, once per page instance. Was defined but dead code until 2026-07-12; now wired.

| Param | Type | Notes |
|---|---|---|
| `region_id` | string | |
| `progress_pct` | int | `regionGlobalProgressProvider(regionId).globalPercentage`, rounded — the completion % at the moment the page opened (not live-updated). |

Redundant with `screen_view` where `firebase_screen = 'RegionDetailRoute'` for raw open counts, but carries `progress_pct` which `screen_view` doesn't — use this for "do players re-open near-complete regions vs. barely-started ones".

### `activity_started`
Where: `adventure_typing_game_page.dart`, `adventure_drawing_game_page.dart`, `adventure_searching_game_page.dart` — in `initState` AND each time the user advances to the next country within the same page.

| Param | Type | Values |
|---|---|---|
| `region_id` | string | Same set as above |
| `country_code` | string | CCA2 (e.g., `FR`, `JP`). Note: Switzerland canton codes get prefixed (`switzerland_be`) per `GameDataset.getStorageCode` — but here we send the raw CCA2 from the page; cross-check both forms in queries. |
| `activity_type` | string | `typing` / `drawing` / `searching` |
| `question_type` | string | `flag` / `capital` / `shape` / `coats` / `landmark` / `anthem` (for typing); always `flag` for drawing; always `shape` for searching |

### `activity_completed`
Same call sites as `activity_started`. Fires when the user finishes a country (typing: success or game-over after several attempts; drawing/searching: success only — Adventure mode only calls `gameFinishedCallback` on success for those games).

| Param | Type | Notes |
|---|---|---|
| `region_id`, `country_code`, `activity_type`, `question_type` | (same as started) | |
| `success` | int (0/1) | `1` for drawing/searching always; varies for typing |
| `duration_ms` | int | Time between this `activity_started` and now |
| `attempts` | int (nullable) | Only set for typing (number of typing attempts); null for drawing/searching |

Activity success rate = `COUNTIF(success=1) / COUNT(*)`. Drop the `success=1` row count by activity_type to compare "how hard is each modality".

### `recap_quiz_started`
Where: `recap_quiz_page.dart._startQuiz`.

| Param | Type |
|---|---|
| `region_id` | string |

### `recap_quiz_completed`
Where: `recap_quiz_page.dart` when `state.gameOver && !_rewardProcessed`.

| Param | Type | Notes |
|---|---|---|
| `region_id` | string | |
| `score` | int | Correct answers |
| `total` | int | `RecapQuizConfig.totalQuestions` |
| `duration_ms` | int | Time from `_startQuiz` to game over |

Win rate per region = `AVG(score / total) GROUP BY region_id`.

### `hint_purchased`
Where: `hint_shop_page.dart._buyHints` on success.

| Param | Type | Notes |
|---|---|---|
| `hint_type` | string | `HintPack.id` (e.g. `starter`, `adventurer`, `expert`) |
| `country_code` | string | Empty for shop purchases (current implementation passes `''`) — not super useful, but kept for forward compat if we ever expose per-country hint purchases |
| `miles_cost` | int | The cost paid |

## Défi (4)

### `challenge_started`
Where: each défi game page's `initState` (`endless_quiz_game_page.dart`, `plus_ou_moins_game_page.dart`, `classement_game_page.dart`).

| Param | Type | Notes |
|---|---|---|
| `challenge_type` | string | `endless_quiz`, `plus_ou_moins`, `classement` |
| `difficulty` | string (nullable) | For `endless_quiz` only: `beginner`, `intermediate`, `advanced`, `expert` |
| `stat_type` | string (nullable) | For `plus_ou_moins` only: `PlusOuMoinsMode.toString()` (e.g. `PlusOuMoinsMode.population`) |
| `region` | string (nullable) | `ChallengeRegion.value` — `world`, `europe`, etc. |

### `challenge_finished`
Where: same files, in the game-over listener.

| Param | Type | Notes |
|---|---|---|
| `challenge_type` | string | |
| `score` | int | Final score |
| `duration_ms` | int | Time from initState |
| `region` | string (nullable) | |

### `weekly_challenge_started`
Where: `weekly_geohunter_game_page.dart._ensureStartLogged`, `classement_game_page.dart._ensureStartLogged` (when `weeklyBinding != null`), `plus_ou_moins_game_page.dart.initState` (when `weeklyBinding != null`). Fires once per instance (idempotent via `_startedLogged` flag, same lifecycle as the co-located `challenge_started`).

| Param | Type | Notes |
|---|---|---|
| `week_id` | string | ISO 8601 week ID — e.g. `2026-W23`. Identifies the weekly challenge edition. |
| `challenge_type` | string | The base game format: `geohunter`, `classement`, or `plus_ou_moins` (NOT `weekly`). |
| `region` | string (nullable) | `ChallengeRegion.value` — omitted for Géohunter (no region concept). |
| `stat_type` | string (nullable) | For `plus_ou_moins` only: `PlusOuMoinsMode.toString()`. |

Use `COUNT(DISTINCT user_pseudo_id) GROUP BY week_id, challenge_type` to measure weekly challenge reach per format and week.

### `weekly_challenge_finished`
Where: same three pages, at game-over (same guard as above — fires at most once per widget instance).

| Param | Type | Notes |
|---|---|---|
| `week_id` | string | Same as `weekly_challenge_started`. |
| `challenge_type` | string | `geohunter`, `classement`, or `plus_ou_moins`. |
| `score` | int | Final score (same value as the co-located `challenge_finished.score`). |
| `duration_seconds` | int (nullable) | `elapsedMilliseconds ~/ 1000` — integer seconds. Nullable (absent if not computable). |
| `region` | string (nullable) | `ChallengeRegion.value` — omitted for Géohunter. |
| `stat_type` | string (nullable) | For `plus_ou_moins` only. |

Completion rate per week = `COUNT(weekly_challenge_finished) / COUNT(weekly_challenge_started) GROUP BY week_id`. Score distribution per format = `AVG/PERCENTILE_CONT(score) GROUP BY challenge_type, week_id`.

## Daily mission (2)

### `daily_mission_started`
Where: `lib/pages/modes/daily_country/daily_country_page.dart._DailyCountryBodyState.initState`, post-frame, only when the mission isn't already finished. Added 2026-07-12 — top of the funnel, pairs with `daily_mission_completed` below.

No params.

### `daily_mission_completed`
Where: `daily_country_page.dart._maybeClaimReward` — fires once per daily mission, when the recap is first shown.

| Param | Type | Notes |
|---|---|---|
| `mission_count_completed` | int | Won steps among the 8 (0–8) |
| `score_total` | int | Booster card-count for the tier awarded (`dailyCountryBooster(wonCount).cardCount`) — despite the param name this is no longer a miles amount (semantic change, see call site comment) |

Funnel completion rate = `COUNT(daily_mission_completed) / COUNT(daily_mission_started) GROUP BY event_date`.

## Duel local (2)

### `duel_started`
Where: `lib/pages/modes/duel/duel_game_page.dart._DuelGamePageState.initState`. Added 2026-07-12 — pairs with `duel_finished` below (mirrors its args exactly).

| Param | Type | Notes |
|---|---|---|
| `game_type` | string | Hard-coded `mixed`, same caveat as `duel_finished.game_type` |
| `players_count` | int | 2–6 |

### `duel_finished`
Where: `duel_game_page.dart._showFinalRanking`.

| Param | Type | Notes |
|---|---|---|
| `game_type` | string | Hard-coded `mixed` — a duel cycles through several game types per match, so the per-match value isn't meaningful |
| `players_count` | int | 2–6 |
| `winner_index` | int | Index in the `players` array (0-based). Ties resolve to the lowest index — not flagged separately in analytics. |

## Ranked match (3)

Added 2026-07-12. Where: `lib/pages/modes/ranked/ranked_match_page.dart`.

### `ranked_match_started`
Fires once per room, the first time it's observed in `playing` status (right after `_chargeEntryTicketOnce()`).

| Param | Type | Notes |
|---|---|---|
| `match_type` | string | `room.rankedMatchType ?? 'classique'` — `plus_ou_moins` is the only non-null value the server writes |
| `entry_path` | string | `invite` or `queue` — inferred client-side from whether the room was ever observed in `lobby` status (friend-invite-only path; the ranked-queue path starts directly in `playing`/`countdown`). Advisory, not server-authoritative. |

### `ranked_match_finished`
Fires from the existing `GameRoomStatus.finished` handler, guarded by `_phase != _MatchPhase.finished` (once per match).

| Param | Type | Notes |
|---|---|---|
| `match_type` | string | Same as above |
| `outcome` | string | `win` / `loss` / `draw` (from `rankedMatchOutcomeProvider`) or `aborted` (`room.rankedAborted` — double-abandon, void match, no ELO change) |
| `rounds_played` | int | `_lastQuestionIndex + 1` |

### `ranked_match_abandoned`
Fires from `_confirmQuit`, right after the user confirms the quit dialog (before the forfeit CF call).

| Param | Type | Notes |
|---|---|---|
| `match_type` | string | Same as above |
| `round_when_left` | int | `_lastQuestionIndex` at the moment of leaving |

`(ranked_match_started) - (ranked_match_finished) - (ranked_match_abandoned) ≈` silent drop-offs (app killed, connection lost with no quit confirm) — same reasoning as the `online_match_*` trio below.

## Boosters (1)

### `booster_opened`
Where: `lib/pages/modes/booster/booster_open_page.dart._onSachetTorn`, right after the pack is drawn. Added 2026-07-12.

| Param | Type | Notes |
|---|---|---|
| `tier` | string | `BoosterTier.name` — `bronze` / `silver` / `gold` |
| `card_count` | int | Total cards in the pack |
| `new_flags` | int | Of those cards, how many were genuinely-new `FlagCard`s (excludes already-owned flags) |

## Ranking (1)

### `ranking_session_ended`
Where: `lib/pages/modes/favorite_flags/swipe_flags.dart.FlagEloSwipePageState.dispose()`. Was defined but dead code until 2026-07-12; now wired. Session start + swipe counter are captured in `initState` and read from the cached fields in `dispose` (Riverpod 3 — `ref` is unusable in `dispose`).

| Param | Type | Notes |
|---|---|---|
| `swipe_count` | int | Number of `_vote()` calls (comparisons made) during this page instance |
| `duration_ms` | int | Wall time from `initState` to `dispose` |
| `cards_seen` | int | `_seenPairs.length` — distinct flag pairs shown (a swipe can re-show a pair after the dedup-retry budget is exhausted, so this can be ≤ `swipe_count`) |

Fires on every page exit (including backgrounding-then-killed only if `dispose` runs — an OS force-kill skips it, same caveat as any client-side session-end event).

## Online (3)

### `online_match_started`
Where: `online_game_page.dart._startPlaying` — fires once on the FIRST countdown → playing transition (guarded by `_phase == OnlineGamePhase.countdown`). Subsequent rounds re-enter `_startPlaying` without re-firing.

| Param | Type | Notes |
|---|---|---|
| `room_size` | int | Number of players in the room at start |
| `is_host` | int (0/1) | Whether the local user hosts the room |

### `online_match_finished`
Where: `online_game_page.dart._onGameFinished` — when the room status flips to `finished`.

| Param | Type | Notes |
|---|---|---|
| `room_size` | int | |
| `final_position` | int | 1-based ranking of the local user (1 = winner). Computed as `1 + (players with strictly more rounds_won than me)`. |
| `rounds_played` | int | `room.currentRound.roundNumber` at the end — total rounds in the match |

### `online_match_abandoned`
Where: `online_game_page.dart._confirmQuit` — when the user confirms the quit dialog before the room reaches `finished`.

| Param | Type | Notes |
|---|---|---|
| `room_size` | int | |
| `round_when_left` | int | Round number at the time of leaving |
| `reason` | string | Currently always `user_quit`. Reserved for future expansion (`disconnect`, `host_killed_room`). |

`(online_match_started count) - (online_match_finished count) - (online_match_abandoned count) ≈ silent drop-offs` (app killed by OS, network outage, etc.) — these are interesting but unrecoverable.

## Engagement (2)

### `badge_unlocked`
Where: `lib/providers/achievement_provider.dart` inside `checkAndNotify` — fires for every new unlock.

| Param | Type | Notes |
|---|---|---|
| `badge_id` | string | Achievement ID (e.g., `firstActivity`, `flagSharpeye`) |
| `level` | string | `AchievementCategory.name` — note: NOT the legacy bronze/silver/gold split (that was replaced by single-tier achievements). |

### `language_changed`
Where: `lib/providers/locale_provider.dart.setLocale`.

| Param | Type | Notes |
|---|---|---|
| `from` | string | Previous locale BCP47 tag |
| `to` | string | New locale BCP47 tag |

Side effect: the same call also re-sets the `language` user property so segment filters in GA4 stay accurate after a switch.

## Carnet missions (1)

### `mission_claimed`
Where: `lib/pages/modes/carnet/widgets/active_mission_card.dart._MissionCardContentState._claim` (source=`mission`) and `lib/pages/modes/carnet/widgets/achievement_carnet_card.dart._AchievementCarnetCardState._claim` (source=`achievement`). Added 2026-07-12 — fires right after the claim provider call resolves, before the reward-inbox scroll-to callback.

| Param | Type | Notes |
|---|---|---|
| `source` | string | `mission` (daily/weekly Carnet mission) or `achievement` |
| `reward_kind` | string | Always `boosters` today — both reward shapes (`MissionDefinition.reward`, `AchievementDefinition.reward`) are `List<BoosterTier>`. Kept as a string param so a future non-booster reward doesn't require an event-shape change. |
| `amount` | int (nullable) | Booster count granted; absent when the definition carries no reward |

Claim volume per source = `COUNT(*) GROUP BY source`. Not the same as `badge_unlocked` (that's the achievement becoming claimable, this is the player collecting the reward — there can be a gap between the two).

## Content quality (1)

### `bug_reported`
Where: `lib/providers/bug_report_provider.dart.submit` (triggered by `BugReportButton` → `BugReportSheet` on adventure game pages). The same submission is also written to the Firestore `bug_reports` collection (richer payload incl. uid, app version, OS).

| Param | Type | Values / Notes |
|---|---|---|
| `category` | string | `flag_wrong` / `name_mistranslation` / `capital_wrong` / `shape_wrong` / `coats_wrong` / `landmark_wrong` / `anthem_wrong` / `drawing_zones_wrong` / `map_position_wrong` (see `lib/core/config/bug_report_category.dart`) |
| `country_code` | string | CCA2 of the flagged country |
| `question_type` | string | `GameQuestionType.name` (flag / capital / shape / …) |
| `activity_type` | string | e.g. `capital_typing` |
| `region_id` | string | Adventure region id |
| `language` | string | **In-app locale** (BCP47, e.g. `sr-Latn`) the user was playing in. **Essential for `name_mistranslation`** — tells you which `nom_*` / `capital_*` field to inspect. Do NOT use GA4's `device.language` (OS language, can differ). |

Use this for a prioritised list of content errors to fix: `GROUP BY category, country_code, language`. Mind that a burst from a single `user_pseudo_id` in a short window is usually the dev exercising the feature, not genuine reports.

## User properties

Set once at splash startup (`lib/pages/splash/splash_screen.dart._setUserProperties`). Re-set on relevant changes (`language` on locale switch).

| Property | Type | Source | Notes |
|---|---|---|---|
| `user_id` | string | `FirebaseAuth.currentUser.uid` | Set via `FirebaseAnalytics.setUserId`. Joinable with `user_pseudo_id` but distinct from it. |
| `language` | string | `LocaleNotifier` | BCP47 tag |
| `dataset` | string | `currentDatasetProvider` | `world` / `switzerland` |
| `total_miles_bucket` | string | `AdventureDbService.getAdventureProgress().totalMiles` bucketed | `<100` / `100-500` / `500-2000` / `2000+` |
| `regions_unlocked_bucket` | string | `AdventureDbService.getUnlockedCount()` bucketed | `0` / `1-2` / `3-6` / `7+` |

User properties only refresh on splash (or on explicit triggers like locale change). A user who unlocks several regions in the same session will keep their old `regions_unlocked_bucket` until the next app cold start. For real-time region progression analyses, count `region_unlocked` events directly.

## Events deliberately NOT tracked

For future reference, here's what the spec considered but rejected:
- **`flag_swiped`** (per-swipe in Ranking) — high volume, low ROI; aggregated instead as `ranking_session_ended` (see Ranking section above, wired 2026-07-12)
- **Per-tap / scroll** — privacy + volume noise
- **Typed-answer content** — privacy
- **`leaderboard_viewed`** — covered by `screen_view`
- **`dataset_switched`, `avatar_changed`** — low signal, can be added later
- **`network_offline_event`, `assets_load_failed`** — useful but not yet wired

When adding any of these, follow the rules in the main SKILL.md section 6.

## Other typed methods not yet documented above (index only)

These exist on `FirebaseAnalyticsService` and are wired at their call sites, but don't yet have full param-table entries in this doc — grep the service file for the exact param shape until someone documents them properly. Listed here so a taxonomy sweep doesn't miss them.

- **Auth/Account**: `account_linked`
- **Monetization**: `purchase_started`, `purchase_completed`, `purchase_failed`, `purchase_restored`, `purchase_reconciled`, `shop_viewed`, `paywall_shown`, `ad_shown`, `ad_reward_earned`, `ad_failed`
- **Tickets**: `ticket_earned_daily`, `ticket_spent`
- **Daily login**: `daily_login_reward` (welcome-back popup — streak day, wheel tier/bonus on wheel days)
- **Notifications**: `notification_permission`, `notification_opened`
- **Gamification**: `level_up`
- **App review**: `review_flow_requested`, `store_listing_opened`
- **Errors**: `network_offline_event`, `assets_load_failed` (see "deliberately NOT tracked" above — defined but not yet called from a site)
- **Feedback**: `feedback_submitted`

If you're about to query one of these in BigQuery, read the method's doc comment in `firebase_analytics_service.dart` first (some have non-obvious param semantics, e.g. `purchase_completed.value`/`currency` being omitted for miles-bought consumables).
