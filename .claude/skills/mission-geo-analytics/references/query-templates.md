# Query templates

Ready-to-run SQL for the typical questions about Mission Geo's analytics + Crashlytics data. Replace `<N>` with the actual GA4 property number (resolve with `bq ls --project_id=mission-geo` and look for the `analytics_<N>` dataset name).

All queries use the GoogleSQL dialect (`--nouse_legacy_sql`). Wrap with the standard CLI invocation:

```bash
export PATH="$HOME/google-cloud-sdk/bin:$PATH" && bq query --nouse_legacy_sql --max_rows=50 --maximum_bytes_billed=1073741824 '<SQL>'
```

`--maximum_bytes_billed=1073741824` caps the query at 1 GB scanned — useful guardrail when running an unfamiliar query across `events_*`.

## Top-level health

### Top events of the last 7 days

```sql
SELECT event_name, COUNT(*) AS n
FROM `mission-geo.analytics_<N>.events_*`
WHERE _TABLE_SUFFIX BETWEEN
  FORMAT_DATE("%Y%m%d", DATE_SUB(CURRENT_DATE("UTC"), INTERVAL 7 DAY))
  AND FORMAT_DATE("%Y%m%d", CURRENT_DATE("UTC"))
GROUP BY event_name
ORDER BY n DESC
LIMIT 20
```

### Daily active users (last 30 days)

```sql
SELECT
  PARSE_DATE("%Y%m%d", event_date) AS date,
  COUNT(DISTINCT user_pseudo_id) AS dau
FROM `mission-geo.analytics_<N>.events_*`
WHERE _TABLE_SUFFIX BETWEEN
  FORMAT_DATE("%Y%m%d", DATE_SUB(CURRENT_DATE("UTC"), INTERVAL 30 DAY))
  AND FORMAT_DATE("%Y%m%d", CURRENT_DATE("UTC"))
GROUP BY date
ORDER BY date DESC
```

## Mode popularity

### Mode entry breakdown (last 30 days)

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "mode") AS mode,
  COUNT(*) AS entries,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM `mission-geo.analytics_<N>.events_*`
WHERE event_name = "mode_entered"
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE("%Y%m%d", DATE_SUB(CURRENT_DATE("UTC"), INTERVAL 30 DAY))
    AND FORMAT_DATE("%Y%m%d", CURRENT_DATE("UTC"))
GROUP BY mode
ORDER BY entries DESC
```

Pair with `COUNT(DISTINCT user_pseudo_id) per mode` to distinguish "many users try once" from "few users come back repeatedly".

### Mode → activity_completed funnel

```sql
WITH mode_users AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "mode") AS mode
  FROM `mission-geo.analytics_<N>.events_*`
  WHERE event_name = "mode_entered"
),
adventure_completers AS (
  SELECT DISTINCT user_pseudo_id
  FROM `mission-geo.analytics_<N>.events_*`
  WHERE event_name = "activity_completed"
)
SELECT
  mode,
  COUNT(DISTINCT mu.user_pseudo_id) AS users_entering_mode,
  COUNT(DISTINCT IF(ac.user_pseudo_id IS NOT NULL, mu.user_pseudo_id, NULL)) AS users_who_completed_an_activity
FROM mode_users mu
LEFT JOIN adventure_completers ac USING (user_pseudo_id)
GROUP BY mode
```

## Adventure

### Region popularity & cost

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "region_id") AS region_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = "unlock_index") AS unlock_index,
  AVG((SELECT value.int_value FROM UNNEST(event_params) WHERE key = "miles_spent")) AS avg_miles_spent,
  COUNT(*) AS unlocks
FROM `mission-geo.analytics_<N>.events_*`
WHERE event_name = "region_unlocked"
GROUP BY region_id, unlock_index
ORDER BY unlocks DESC
```

### Activity difficulty by country

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "country_code") AS country,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "activity_type") AS activity,
  COUNTIF((SELECT value.int_value FROM UNNEST(event_params) WHERE key = "success") = 1) AS wins,
  COUNTIF((SELECT value.int_value FROM UNNEST(event_params) WHERE key = "success") = 0) AS losses,
  SAFE_DIVIDE(
    COUNTIF((SELECT value.int_value FROM UNNEST(event_params) WHERE key = "success") = 0),
    COUNT(*)
  ) AS loss_rate,
  AVG((SELECT value.int_value FROM UNNEST(event_params) WHERE key = "duration_ms")) AS avg_duration_ms
FROM `mission-geo.analytics_<N>.events_*`
WHERE event_name = "activity_completed"
GROUP BY country, activity
HAVING wins + losses > 50
ORDER BY loss_rate DESC
LIMIT 30
```

### Recap quiz performance per region

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "region_id") AS region,
  COUNT(*) AS attempts,
  AVG((SELECT value.int_value FROM UNNEST(event_params) WHERE key = "score")) AS avg_score,
  AVG((SELECT value.int_value FROM UNNEST(event_params) WHERE key = "total")) AS avg_total,
  AVG((SELECT value.int_value FROM UNNEST(event_params) WHERE key = "duration_ms")) AS avg_duration_ms
FROM `mission-geo.analytics_<N>.events_*`
WHERE event_name = "recap_quiz_completed"
GROUP BY region
ORDER BY attempts DESC
```

### Hint shop conversion

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "hint_type") AS pack,
  COUNT(*) AS purchases,
  SUM((SELECT value.int_value FROM UNNEST(event_params) WHERE key = "miles_cost")) AS total_miles_spent
FROM `mission-geo.analytics_<N>.events_*`
WHERE event_name = "hint_purchased"
GROUP BY pack
ORDER BY purchases DESC
```

## Défi

### Challenge volume + difficulty distribution

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "challenge_type") AS type,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "difficulty") AS difficulty,
  COUNT(*) AS starts,
  AVG((SELECT value.int_value FROM UNNEST(event_params) WHERE key = "duration_ms")) AS avg_duration_ms
FROM `mission-geo.analytics_<N>.events_*`
WHERE event_name = "challenge_started"
GROUP BY type, difficulty
ORDER BY starts DESC
```

### Challenge completion rate (finished / started ratio)

```sql
WITH starts AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "challenge_type") AS type
  FROM `mission-geo.analytics_<N>.events_*`
  WHERE event_name = "challenge_started"
),
finishes AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "challenge_type") AS type,
    COUNT(*) AS finished
  FROM `mission-geo.analytics_<N>.events_*`
  WHERE event_name = "challenge_finished"
  GROUP BY type
)
SELECT
  s.type,
  COUNT(*) AS started,
  f.finished,
  SAFE_DIVIDE(f.finished, COUNT(*)) AS completion_rate
FROM starts s
LEFT JOIN finishes f USING (type)
GROUP BY s.type, f.finished
ORDER BY started DESC
```

## Online

### Online match outcomes

```sql
SELECT
  event_name,
  COUNT(*) AS n,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM `mission-geo.analytics_<N>.events_*`
WHERE event_name IN ("online_match_started", "online_match_finished", "online_match_abandoned")
GROUP BY event_name
```

The gap `started - (finished + abandoned)` is the silent drop-off (app killed, network died, etc.).

### Average rounds per finished match by room size

```sql
SELECT
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = "room_size") AS room_size,
  AVG((SELECT value.int_value FROM UNNEST(event_params) WHERE key = "rounds_played")) AS avg_rounds,
  COUNT(*) AS matches
FROM `mission-geo.analytics_<N>.events_*`
WHERE event_name = "online_match_finished"
GROUP BY room_size
ORDER BY room_size
```

### Abandon profile (where do users quit)

```sql
SELECT
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = "round_when_left") AS round_when_left,
  COUNT(*) AS abandons
FROM `mission-geo.analytics_<N>.events_*`
WHERE event_name = "online_match_abandoned"
GROUP BY round_when_left
ORDER BY round_when_left
```

## User segments

### Language distribution

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = "language") AS lang,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM `mission-geo.analytics_<N>.events_*`
GROUP BY lang
ORDER BY users DESC
```

The user property reflects the current locale at the time of the event. A user who switched language during the period appears in both buckets across different events.

### Progression segments

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = "regions_unlocked_bucket") AS bucket,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM `mission-geo.analytics_<N>.events_*`
WHERE event_name = "session_start"
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE("%Y%m%d", DATE_SUB(CURRENT_DATE("UTC"), INTERVAL 30 DAY))
    AND FORMAT_DATE("%Y%m%d", CURRENT_DATE("UTC"))
GROUP BY bucket
```

## Retention

### D1 / D7 retention (cohort by first_open week)

```sql
WITH first_opens AS (
  SELECT
    user_pseudo_id,
    DATE(MIN(TIMESTAMP_MICROS(event_timestamp))) AS first_day
  FROM `mission-geo.analytics_<N>.events_*`
  WHERE event_name = "first_open"
  GROUP BY user_pseudo_id
),
activity AS (
  SELECT
    user_pseudo_id,
    DATE(TIMESTAMP_MICROS(event_timestamp)) AS day
  FROM `mission-geo.analytics_<N>.events_*`
  WHERE event_name = "session_start"
)
SELECT
  DATE_TRUNC(fo.first_day, WEEK) AS cohort_week,
  COUNT(DISTINCT fo.user_pseudo_id) AS cohort_size,
  COUNT(DISTINCT IF(DATE_DIFF(a.day, fo.first_day, DAY) = 1, fo.user_pseudo_id, NULL)) AS d1_returners,
  COUNT(DISTINCT IF(DATE_DIFF(a.day, fo.first_day, DAY) = 7, fo.user_pseudo_id, NULL)) AS d7_returners
FROM first_opens fo
LEFT JOIN activity a USING (user_pseudo_id)
WHERE fo.first_day >= DATE_SUB(CURRENT_DATE("UTC"), INTERVAL 60 DAY)
GROUP BY cohort_week
ORDER BY cohort_week DESC
```

## Crashes

### Crashes per app version (last 7 days)

```sql
SELECT
  application.build_version AS build,
  COUNT(*) AS crashes
FROM `mission-geo.firebase_crashlytics.crashlytics_ANDROID`
WHERE event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND is_fatal = true
GROUP BY build
ORDER BY crashes DESC
```

Adapt table name (`_ANDROID` / `_IOS`) to your platform. Schema differs slightly from Analytics — check via `bq show --schema mission-geo:firebase_crashlytics.crashlytics_ANDROID`.

### Crashy mode (joining crashlytics + GA4 via user_pseudo_id)

Heuristic: for each crash, look up the most recent `mode_entered` event by the same user in the 5 minutes before the crash. (Coarse — a session_start would be more precise but `mode_entered` directly attributes engagement.)

```sql
WITH crashes AS (
  SELECT
    user_pseudo_id AS pid,
    event_timestamp AS crash_ts
  FROM `mission-geo.firebase_crashlytics.crashlytics_ANDROID`
  WHERE is_fatal = true
    AND event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 14 DAY)
),
modes AS (
  SELECT
    user_pseudo_id AS pid,
    TIMESTAMP_MICROS(event_timestamp) AS mode_ts,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = "mode") AS mode
  FROM `mission-geo.analytics_<N>.events_*`
  WHERE event_name = "mode_entered"
)
SELECT
  m.mode,
  COUNT(*) AS crashes_after_mode_within_5min
FROM crashes c
JOIN modes m
  ON c.pid = m.pid
  AND m.mode_ts BETWEEN TIMESTAMP_SUB(c.crash_ts, INTERVAL 5 MINUTE) AND c.crash_ts
GROUP BY mode
ORDER BY crashes_after_mode_within_5min DESC
```

`user_pseudo_id` is the join key between the two datasets — Firebase makes sure it matches.

## Free-form: sanity check schema

When in doubt about the schema of a table:

```bash
bq show --schema --format=prettyjson mission-geo:analytics_<N>.events_<YYYYMMDD>
```

The GA4 schema is documented at https://support.google.com/analytics/answer/7029846 — useful for fields like `device.category`, `geo.country`, `traffic_source.*`, `app_info.version`, etc.
