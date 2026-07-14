#!/usr/bin/env python3
"""Seed the local Mission Geo sqlite DB for Play Store screenshot capture.

Pre-conditions: the DB exists at the given path with schema v10 as produced
by the app's first launch + onboarding completion. The regions table is
already populated by initializeRegions() with the 5 continent IDs
(europe, africa, americas, asia, oceania) + dataset regions.

Result after seeding:
  - 2450 miles, 5 hints.
  - asia: unlocked at max level (level 4, all tiers). User's starting region.
  - europe: unlocked at level 2/3 (EASY+INTERMEDIATE, 34 countries).
  - africa: unlocked at level 4/4 = MAX (all tiers, 60 countries).
  - americas: unlocked at level 1/4 (EASY only, 11 countries).
  - oceania: stays locked (is_unlocked=0, current_level=0) for visual variety.
  - country_codes in regions: updated to match the restricted level pool for
    europe (L2) and americas (L1) so progress % uses the right denominator.
  - country_progress: representative countries per continent marked "found" for
    all activities, giving realistic progress bars in the region-list shot.
    Progress is restricted to countries within each continent's level pool.
    Target countries IN (Taj Mahal), ZA (Drawing), CL (Searching) are all
    EASY-tier → in pool at level 1+ of their continent.
  - activity_unlocks: all activities sticky-unlocked for the 4 unlocked
    continents so landmark/drawing/searching routes render without gating.
  - quiz_progress table: REMOVED in schema v7, NOT seeded here.

Level → tier mapping (mirrors countryCodesForLevel in adventure_regions_config.dart):
  Pool is CUMULATIVE: level L = countries in the L first populated tiers.
  Tier order: EASY → INTERMEDIATE → ADVANCED → EXPERT.
  europe max_level=3 (no EXPERT tier populated); others max_level=4.
  Country counts at target levels (computed from adventureTier in world.json):
    europe  L2 → 34 countries (EASY=17 + INTERMEDIATE=17)
    africa  L4 → 60 countries (all tiers)
    americas L1 → 11 countries (EASY only)
    asia    L4 → 50 countries (all tiers)
"""

import json
import os
import sqlite3
import sys
import time

if len(sys.argv) < 2:
    print("usage: seed_screenshot_db.py <db-path>", file=sys.stderr)
    sys.exit(1)

db = sqlite3.connect(sys.argv[1])
cur = db.cursor()
NOW = int(time.time() * 1000)

# ── Load world.json to compute level-restricted country_codes ─────────────────
# Mirrors AdventureRegionsConfig.countryCodesForLevel() in Dart.
# Field: adventureTier (EASY / INTERMEDIATE / ADVANCED / EXPERT) in world.json.
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_WORLD_JSON = os.path.join(_SCRIPT_DIR, '..', '..', '..', '..', 'assets', 'world', 'world.json')
with open(_WORLD_JSON, encoding='utf-8') as _f:
    _world = json.load(_f)

_CONTINENT_REGION = {
    'europe': 'Europe',
    'africa': 'Africa',
    'americas': 'Americas',
    'asia': 'Asia',
    'oceania': 'Oceania',
}
_TIER_ORDER = ['EASY', 'INTERMEDIATE', 'ADVANCED', 'EXPERT']


def _populated_tiers(continent_id):
    """Returns populated tiers for a continent (order: EASY→EXPERT, gaps skipped)."""
    region_val = _CONTINENT_REGION[continent_id]
    present = set()
    for c in _world:
        if c.get('region') == region_val:
            t = (c.get('adventureTier') or '').upper()
            if t in _TIER_ORDER:
                present.add(t)
    return [t for t in _TIER_ORDER if t in present]


def _country_codes_for_level(continent_id, level):
    """Cumulative pool: level L = countries in the first L populated tiers."""
    region_val = _CONTINENT_REGION[continent_id]
    tiers = _populated_tiers(continent_id)
    if not tiers or level <= 0:
        return []
    level_tiers = set(tiers[:level])
    return [
        c['cca2'] for c in _world
        if c.get('region') == region_val
        and (c.get('adventureTier') or '').upper() in level_tiers
    ]


# ── adventure_progress (single-row, id=1) ────────────────────────────────────
# 2450 miles ≈ mid-progression. 5 hints.
cur.execute(
    "UPDATE adventure_progress SET total_miles=2450, hint_balance=5, last_updated=? WHERE id=1",
    (NOW,),
)

# ── regions ──────────────────────────────────────────────────────────────────
# Continent max_level values (derived from adventureTier distribution in
# world.json; Oceania has only EASY+ADVANCED = 2 tiers):
#   europe:   3  (EASY, INTERMEDIATE, ADVANCED)
#   africa:   4  (EASY, INTERMEDIATE, ADVANCED, EXPERT)
#   americas: 4  (EASY, INTERMEDIATE, ADVANCED, EXPERT)
#   asia:     4  (EASY, INTERMEDIATE, ADVANCED, EXPERT)
#   oceania:  2  (EASY, ADVANCED — no INTERMEDIATE tier populated)
#
# Shot 01 (adventure regions) shows Europe, Africa, Americas at different
# levels for visual variety. Asia stays at max (user's starting region).
# country_codes is recomputed to match the restricted level pool so that
# regionGlobalProgressProvider uses the correct denominator.
CONTINENT_UNLOCKS = [
    # (id,        current_level, max_level, unlock_order)
    ("europe",   2, 3, 2),   # L2/3: EASY+INTERMEDIATE (34 countries)
    ("africa",   4, 4, 3),   # L4/4: MAX — all tiers (60 countries)
    ("americas", 1, 4, 4),   # L1/4: EASY only (11 countries)
    ("asia",     4, 4, 1),   # L4/4: MAX — user's starting region (50 countries)
    # oceania stays at current_level=0, is_unlocked=0 (locked for visual mix)
]
for region_id, current_level, max_level, unlock_order in CONTINENT_UNLOCKS:
    codes = _country_codes_for_level(region_id, current_level)
    codes_str = ','.join(codes)
    cur.execute(
        "UPDATE regions SET is_unlocked=1, current_level=?, max_level=?, "
        "unlock_order=?, country_codes=? WHERE id=?",
        (current_level, max_level, unlock_order, codes_str, region_id),
    )

# ── country_progress ─────────────────────────────────────────────────────────
# Columns: country_code, region_id, activity_type, found (1), found_date.
# UNIQUE(country_code, activity_type) — no region_id in the unique key, so
# each (code, activity) pair appears once regardless of region.
#
# Target display percentages for shot 01 (adventure regions list):
#   asia     L4 (50 countries): 12 seeded ≈ 24% — user's most-played region
#   africa   L4 (60 countries): 20 seeded ≈ 33% — max level, moderate progress
#   europe   L2 (34 countries):  9 seeded ≈ 26% — mid level, partial progress
#   americas L1 (11 countries):  2 seeded ≈ 18% — just started
#
# All seeded codes are verified to be within the continent's level pool
# (countryCodesForLevel result). Target countries IN/ZA/CL must be "found".
ALL_ACTIVITIES = [
    "flag_typing",
    "capital_typing",
    "flag_drawing",
    "map_placement",
    "shape_typing",
    "coats_typing",
    "landmark_typing",
    "anthem_typing",
]

# (continent_id, [cca2 codes])
# All codes are within the level pool computed by _country_codes_for_level.
COUNTRY_SETS = [
    # asia L4 (50 countries) — 12 seeded ≈ 24%
    ("asia",     ["IN", "JP", "CN", "KR", "TH", "VN", "PH", "ID", "TR", "SA", "AE", "IL"]),
    # africa L4 (60 countries) — 20 seeded ≈ 33%
    ("africa",   ["ZA", "EG", "NG", "KE", "MA", "GH", "ET", "TZ", "SN", "CI",
                  "DZ", "CM", "AO", "MZ", "MG", "ML", "BF", "RW", "UG", "TN"]),
    # americas L1 (11 countries: AR BR CA CL CO CU JM MX PE US VE) — 2 seeded ≈ 18%
    # CL kept (target for map_placement screenshot), BR as second
    ("americas", ["CL", "BR"]),
    # europe L2 (34 countries) — 9 seeded ≈ 26%
    # FR/DE/GB kept (screenshot targets), fill with other L2 codes
    ("europe",   ["FR", "DE", "GB", "ES", "IT", "NL", "PL", "SE", "CH"]),
]

cur.execute("DELETE FROM country_progress")
for continent_id, codes in COUNTRY_SETS:
    for cc in codes:
        for activity in ALL_ACTIVITIES:
            cur.execute(
                "INSERT OR REPLACE INTO country_progress "
                "(country_code, region_id, activity_type, found, found_date) "
                "VALUES (?, ?, ?, 1, ?)",
                (cc, continent_id, activity, NOW),
            )

# ── activity_unlocks ─────────────────────────────────────────────────────────
# Sticky-unlock all activities for the 4 unlocked continents.
# Without these rows, the in-game activity gate would fall back to computing
# progress thresholds and could hide landmark/drawing/searching behind an
# unlock prompt — seeding them here ensures the deep-link routes always render.
UNLOCKED_CONTINENTS = ["asia", "africa", "americas", "europe"]
for continent_id in UNLOCKED_CONTINENTS:
    for activity in ALL_ACTIVITIES:
        cur.execute(
            "INSERT OR IGNORE INTO activity_unlocks "
            "(region_id, activity_type, unlocked_at) VALUES (?, ?, ?)",
            (continent_id, activity, NOW),
        )

# ── owned_flags ──────────────────────────────────────────────────────────────
# Two parts:
#  1. Every other CCA2 code from the sorted world list — gives a realistic
#     "collection in progress" look on every non-Europe continent.
#  2. ~50% of the Europe continent (every other country in the album's FR
#     display order) — the album screenshot (07_collection_album, scenario
#     collectionAlbum) opens on a Europe sticker page and we want EXACTLY
#     3 owned / 6 shown on that page (3 real flags + 3 placeholders).
#
#     The album lays out slots in `localizedNom` order (booster_album_page.dart
#     _buildPages → list.sort(localizedNom)). That order differs per locale, so
#     we anchor the exact 3/6 on fr-FR (the reference locale): reproduce the FR
#     display-name sort (Country.localizedName('fr') == `nom`, which the parser
#     fills from json['nom'] ?? translations.fra.common), then own one country
#     out of two in that order (indices 0,2,4,… owned; 1,3,5,… placeholder).
#     That yields exactly slots 1/3/5 owned + 2/4/6 placeholder on Europe page 1
#     fr-FR (AL/AD/BE owned, DE/AT/BY placeholder) and ~3/6 on each following
#     page. The SAME owned set, re-sorted in en/de/sr, lands on a different but
#     still ~50% mix — a credible "collection in progress", which is intended.
#     Non-Europe stays every-other.
# Dart's String.compareTo is UTF-16 code-unit order, which matches Python's
# default str sort on the same strings, so this reproduction is exact.
# The seed is deterministic so the shot is reproducible, and the album is the
# only screen that reads owned_flags → no other shot is affected.
OWNED_FLAGS_EVERY_OTHER = [
    'AD', 'AF', 'AI', 'AM', 'AQ', 'AS', 'AU', 'AX', 'BA', 'BD',
    'BF', 'BH', 'BJ', 'BM', 'BO', 'BR', 'BT', 'BY', 'CA', 'CD',
    'CG', 'CI', 'CL', 'CN', 'CR', 'CV', 'CX', 'CZ', 'DJ', 'DM',
    'DZ', 'EE', 'EH', 'ES', 'FI', 'FK', 'FO', 'GA', 'GD', 'GF',
    'GH', 'GL', 'GN', 'GQ', 'GS', 'GU', 'GY', 'HN', 'HT', 'ID',
    'IL', 'IN', 'IQ', 'IS', 'JE', 'JO', 'KE', 'KH', 'KM', 'KP',
    'KW', 'KZ', 'LB', 'LI', 'LR', 'LT', 'LV', 'MA', 'MD', 'MF',
    'MH', 'ML', 'MN', 'MP', 'MR', 'MT', 'MV', 'MX', 'MZ', 'NC',
    'NF', 'NI', 'NO', 'NR', 'NZ', 'PA', 'PF', 'PH', 'PL', 'PN',
    'PS', 'PW', 'QA', 'RO', 'RU', 'SA', 'SC', 'SE', 'SH', 'SK',
    'SM', 'SO', 'SS', 'SV', 'SY', 'TC', 'TF', 'TH', 'TK', 'TM',
    'TO', 'TT', 'TW', 'UA', 'US', 'UZ', 'VC', 'VG', 'VN', 'WF',
    'XC', 'XS', 'YT', 'ZM',
]

def _fr_display_name(country):
    """FR display name as the app resolves it: localizedName('fr') == `nom`,
    where the parser fills `nom` from json['nom'] ?? translations.fra.common.
    Mirrors Country.fromJson + Country.localizedName in lib/models/country.dart.
    """
    nom = country.get('nom')
    if not nom:
        fra = (country.get('translations') or {}).get('fra') or {}
        nom = fra.get('common') or 'Nom inconnu'
    return nom


# ~50% of Europe in the album's FR layout order: own indices 0,2,4,… so the
# displayed Europe pages read exactly 3/6 (fr-FR) — see comment above.
_europe = [c for c in _world if c.get('region') == 'Europe']
_europe.sort(key=_fr_display_name)
_EUROPE_OWNED = [
    _europe[i]['cca2'] for i in range(len(_europe)) if i % 2 == 0
]
# Shot 07 (collectionAlbum) needs page 1 to show BE as placeholder and BY as
# owned so the 3/6 split reads AL/AD/BY owned, DE/AT/BE placeholder.
# Even-index parity gives AL(0)/AD(2)/BE(4) owned — swap BE→BY explicitly.
_EUROPE_OWNED = [c for c in _EUROPE_OWNED if c != 'BE']
if 'BY' not in _EUROPE_OWNED:
    _EUROPE_OWNED.append('BY')

# Europe ownership is governed SOLELY by the precise FR-order every-other set
# above (_EUROPE_OWNED). The hard-coded OWNED_FLAGS_EVERY_OTHER list also
# happens to contain European codes (AD, BY, CZ, ES, IS, SE…), and unioning
# them back in re-owns countries the precise set deliberately left out — that
# collision owned BY on Europe page 1 → 4/6 instead of the intended 3/6. So
# drop every European code from the global list before the union.
_europe_codes = {c['cca2'] for c in _europe}
_non_europe_every_other = [c for c in OWNED_FLAGS_EVERY_OTHER if c not in _europe_codes]
OWNED_FLAGS = sorted(set(_non_europe_every_other) | set(_EUROPE_OWNED))
# Authoritative: clear the table first so removing a code from the set actually
# UNSETS it. The capture pipeline pulls the live device DB before seeding, so a
# plain INSERT OR IGNORE would let stale owned rows from a prior seed persist
# (this is how BY survived earlier passes). Mirrors the country_progress DELETE.
cur.execute("DELETE FROM owned_flags")
for code in OWNED_FLAGS:
    cur.execute(
        "INSERT OR IGNORE INTO owned_flags (code) VALUES (?)",
        (code,),
    )
print(
    f"owned_flags seeded: {len(OWNED_FLAGS)} total "
    f"({len(_EUROPE_OWNED)}/{len(_europe)} Europe ≈ 50% → 3/6 on page 1 fr-FR)"
)

# ── dataset regions (CH + IT) ────────────────────────────────────────────────
# Seed switzerland_cantons and italy_regions as unlocked at level 1 so the
# Pays tab region cards render with a "Jouer" button instead of the download
# prompt (combined with the screenshotForceDatasetInstalled bypass in Dart).
DATASET_REGIONS = [
    # (id, current_level, max_level, unlock_order)
    ('switzerland_cantons', 1, 1, 5),
    ('italy_regions',       1, 1, 6),
]
for region_id, current_level, max_level, unlock_order in DATASET_REGIONS:
    cur.execute(
        "UPDATE regions SET is_unlocked=1, current_level=?, max_level=?, unlock_order=? WHERE id=?",
        (current_level, max_level, unlock_order, region_id),
    )

# ── user_xp (level 10 = 4 110 XP) ───────────────────────────────────────────
# Gives the player a visible level badge (grade 10) in the app bar / home banner.
import datetime
now_iso = datetime.datetime.utcnow().isoformat()
cur.execute(
    "INSERT OR REPLACE INTO user_xp (id, total_xp, updated_at) VALUES (1, 4110, ?)",
    (now_iso,),
)

db.commit()
db.close()
print(f"Seeded {sys.argv[1]} OK")
