---
name: mission-geo-analytics
description: Use whenever the user asks anything operational about Mission Geo's product analytics or crash reports — "quels events on suit ?", "quel mode est le plus joué ?", "fais une requête BigQuery", "regarde le taux d'échec sur l'Aventure", "combien d'utilisateurs en allemand", "y a des crashs récents ?", "DebugView", "tracking", "ça track quoi", "GA4", "Firebase Analytics", "regarde dans Crashlytics". Also use when the user asks how to add or change events (so the typed-service convention is respected). Skip this skill ONLY for pure code questions that don't involve the analytics data (e.g., a Riverpod or routing question that happens to touch a file that emits events). When in doubt, use it.
---

# Mission Geo — analytics & Crashlytics operations

This skill is the operational runbook for everything that runs on top of Firebase Analytics + Crashlytics + BigQuery in this project. It covers:

1. How to query the data from this machine
2. What's tracked (events + user properties) and where it's emitted from
3. Reusable SQL templates for the questions the maintainer cares about
4. Consent & privacy notes that affect what's collected
5. Rules for adding or changing events

Code-side architecture (the typed service, the consent flow, the NavigatorObserver) is documented in `CLAUDE.md` under "Firebase → Analytics & Crashlytics" — read that first when working on the Dart side. This skill is for working with the **data**.

## 1. Environment — accessing BigQuery from this machine

GCP project: **`mission-geo`**. Primary CLI account: `missiongeo.app@gmail.com` (auth already configured). A personal Google account is also owner of the Firebase project but the CLI is signed in with the dedicated one.

The `gcloud` SDK is installed at `~/google-cloud-sdk/` but **is not on the default PATH** for non-interactive bash invocations (the user's `~/.bashrc` sources it, but Claude's shells skip that). Two options:

```bash
# Option A — prefix every command
export PATH="$HOME/google-cloud-sdk/bin:$PATH" && bq ls --project_id=mission-geo

# Option B — absolute path
~/google-cloud-sdk/bin/bq ls --project_id=mission-geo
```

Use option A for sequences of commands so `bq`/`gcloud` can find each other.

**ADC + user auth are already done.** Don't run `gcloud auth login` again unless tokens expired (you'll see an "invalid grant" / "reauthentication needed" error first).

### BigQuery datasets

Under project `mission-geo` (location `EU` for all):

| Dataset | Content |
|---|---|
| `analytics_<property_number>` | GA4 export — raw `events_*` tables with one row per event. Daily + streaming export. `<property_number>` is the GA4 property ID; resolve at runtime via `bq ls --project_id=mission-geo`. |
| `firebase_crashlytics` | Crash + breadcrumb data. Streaming enabled. |
| `firebase_sessions` | Firebase Sessions SDK auto-export. Rarely queried directly. |

The Analytics dataset is created **on first event flow after the BigQuery link was made** (mid-May 2026), not at link time. **No historical backfill.** Don't promise data from before that date.

Inside `analytics_<N>`:
- `events_YYYYMMDD` — finalised day, available the next day
- `events_intraday_YYYYMMDD` — current day, populated by streaming export (~1 min latency)

When writing queries that cover today, include both:

```sql
FROM `mission-geo.analytics_<N>.events_*`
WHERE _TABLE_SUFFIX BETWEEN
  FORMAT_DATE("%Y%m%d", DATE_SUB(CURRENT_DATE("UTC"), INTERVAL 7 DAY))
  AND FORMAT_DATE("%Y%m%d", CURRENT_DATE("UTC"))
```

…BigQuery treats `events_intraday_*` as part of the wildcard.

## 2. Event taxonomy

Full reference: `references/event-taxonomy.md`. Quick mental map:

- **Lifecycle** (auto): `app_open`, `first_open`, `session_start`, `screen_view`, `app_exception`
- **Onboarding** (2): `onboarding_step_completed`, `onboarding_finished`
- **Navigation** (1): `mode_entered`
- **Adventure** (7): `region_unlocked`, `activity_started`, `activity_completed`, `recap_quiz_started`, `recap_quiz_completed`, `hint_purchased`
- **Défi** (2): `challenge_started`, `challenge_finished`
- **Daily mission** (1): `daily_mission_completed`
- **Duel local** (1): `duel_finished`
- **Online** (3): `online_match_started`, `online_match_finished`, `online_match_abandoned`
- **Engagement** (2): `badge_unlocked`, `language_changed`

User properties (set at startup, `language` refreshed on change):
- `user_id` — anonymous Firebase Auth UID (also surfaces as `user_pseudo_id`)
- `language` — BCP47 tag (`fr`, `en`, `de`, `sr-Latn`)
- `dataset` — `world` or `switzerland`
- `total_miles_bucket` — `<100` / `100-500` / `500-2000` / `2000+`
- `regions_unlocked_bucket` — `0` / `1-2` / `3-6` / `7+`

**Read `references/event-taxonomy.md` whenever you need a param list, when interpreting a result, or when checking whether a question can be answered with the current taxonomy.**

## 3. Query templates

See `references/query-templates.md` for ready-to-run SQL covering the maintainer's common questions:
- Top events / mode popularity / region popularity
- Activity success & duration breakdown by country
- Funnel analysis (mode_entered → activity_completed)
- Online match drop-off
- Language and dataset distribution
- Crash rate per session
- Retention (D1 / D7) via `user_pseudo_id` first_seen

The templates use `analytics_<N>` as a placeholder. Resolve `<N>` at the start of a session with one `bq ls --project_id=mission-geo` call.

## 4. Consent & privacy gating — what the data actually represents

- **Events only flow if the user accepted analytics consent** at the onboarding step (or flipped the toggle on later in Profile → Données et confidentialité). Refused users emit zero events.
- `user_pseudo_id` and `user_id` are both pseudonymous and reset on app uninstall. A new install on the same device gets a fresh ID.
- Retention is 14 months for GA4 events. BigQuery tables persist unless a partition-expiration is set.
- The in-app privacy policy (`t.policy.*`, displayed via `lib/pages/legal/policy_page.dart`) declares the full surface. **If you add tracking, you must update `t.policy.section1Body` in all four locales accordingly** — RGPD requires the user to know what's collected before consenting.

Practical consequences for analysis:
- Counts undercount real usage by the consent-refusal rate. Don't extrapolate "X% played mode Y" without acknowledging that.
- A user who refused at onboarding then accepts in Profile starts emitting from that moment — their earlier sessions are gone.
- Debug builds **DO** emit Analytics events (only Crashlytics is gated by `kDebugMode`). When the maintainer is testing locally, those events also show up in the GA4 property. Filter them in SQL via `app_info.id` patterns or by excluding sessions matching a known dev `user_pseudo_id`.

## 5. Live debugging — DebugView

For verifying that a new or modified event is being emitted correctly, the DebugView shows events one-by-one in near-real-time with all their parameters:

```bash
# Enable for the app (Android — adapt for iOS via Xcode env var)
# Property is per-flavor: dev app.missiongeo.dev, prod app.missiongeo
adb shell setprop debug.firebase.analytics.app app.missiongeo.dev    # dev flavor
adb shell setprop debug.firebase.analytics.app app.missiongeo       # prod flavor

# Then watch Firebase console → Analytics → DebugView

# Disable when done
adb shell setprop debug.firebase.analytics.app .none.
```

DebugView is decoupled from the BigQuery export — events appear regardless of whether streaming export is on.

## 6. Adding or changing events

The typed service at `lib/core/services/firebase/firebase_analytics_service.dart` is the **only** entry point for events. Adding a new event means:

1. Add a typed method on `FirebaseAnalyticsService` (e.g., `logXxx(...)` with named parameters)
2. Use `_log(name, params)` inside the method — it handles the GA4 send, the Crashlytics breadcrumb, and the debug print
3. Wire the call at the natural site (page lifecycle, provider mutation, etc.) — never inside a `build()` method
4. Add the row to `references/event-taxonomy.md` so this skill stays current
5. If the event collects new categories of data, update `t.policy.section1Body` in all four locales (`lib/i18n/{fr,en,de,sr-Latn}.i18n.json`) and run `dart run slang`
6. Mention the addition in the next commit message so the BigQuery downstream user (Claude querying) knows about it

Things to **not** do:
- Don't call `FirebaseAnalytics.instance.logEvent(...)` directly anywhere outside the service. The typed service is what prevents name drift.
- Don't add high-volume events like per-keystroke or per-swipe — they explode the BigQuery bill and bury the signal. Aggregate at the session/round level. Existing example: `ranking_session_ended` (planned but not yet wired) reports `swipe_count` rather than logging each swipe.
- Don't put PII or user-typed content in event params (no usernames, no typed answers, no city-level location). The current taxonomy is clean — keep it that way.
- Don't change the name of an existing event without a clear deprecation path. GA4 treats renamed events as new ones, so dashboards and saved queries silently break.

## 7. Crashes

Crashlytics is its own concern but lives next door.

- Dashboard: Firebase console → **Crashlytics**
- Breadcrumbs in each crash report = the recent analytics events (the `_log` helper mirrors every event into `FirebaseCrashlytics.log()`)
- Test crash button is rendered in Profile **only in debug builds** (`kDebugMode`) — used to verify the upload pipeline on a fresh deploy
- BigQuery dataset `firebase_crashlytics` has `crashlytics_<bundle_id>_ANDROID` and `_IOS` tables — query for crash count per app version, per OS version, per fatal/non-fatal

To compare crashes vs engagement (e.g., "is mode X crashing more than mode Y?"), join the two datasets via `user_pseudo_id`. The pattern is in `references/query-templates.md`.

## 8. When data isn't there

Common reasons a query returns 0 rows or an unexpected result:

| Symptom | Likely cause |
|---|---|
| `analytics_*` dataset doesn't exist | First event flow hasn't propagated yet (up to 24h after link, usually under 2h). Confirm with `bq ls --project_id=mission-geo`. |
| `events_<date>` missing for a recent day | Daily export hasn't run yet — use `events_intraday_<date>` for today, or wait until the next day. |
| Today's events not visible | Streaming has ~1 min latency. Refresh, or check Realtime in Firebase console. |
| Event count much lower than expected | Consent refusal rate matters; also check that debug builds aren't dominating (they shouldn't, but possible during early days post-launch). |
| Param value is NULL when you expect a value | The event was logged without that param. The typed service uses `Map.from(...)` to filter nulls, so a missing key means the call site didn't pass it. Grep the typed method to check. |

## 9. Quota & cost

- BigQuery usage for this project: ~12 MB/day estimate at 1k DAU. Negligible.
- A Cloud Billing budget alert is set at **5 EUR/month** on BigQuery usage. The maintainer receives the email; if you hit a threshold, surface it.
- `bq query --maximum_bytes_billed=1073741824 ...` (1 GB cap) is a safe guardrail when running an unfamiliar query on a wildcard table to avoid scanning every partition by accident.
