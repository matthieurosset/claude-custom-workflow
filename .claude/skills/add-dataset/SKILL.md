---
name: add-dataset
description: Use when adding a new country-subdivision dataset (states/provinces/regions of a country, like Switzerland's cantons or Austria's Länder) to the Mission Geo Flutter game — automates boundaries (geoBoundaries), flags (Wikimedia), shapes, geo-index, names/capitals, and the Flutter wiring. Triggers on "ajoute l'Autriche", "add a new dataset", "ajouter les Länder/départements/régions de X", "nouveau dataset pays".
---

# Add a country-subdivision dataset

Adds a new **dataset** (a country's first-level subdivisions — cantons, Länder,
départements, states…) to Mission Geo, modeled on Switzerland (26 cantons) and
Austria (9 Länder).

> ⚠️ **READ "Drawing-game SVGs — hard rules" AND "Flags: the hard-won recipe" BELOW
> BEFORE TOUCHING FLAGS.** Austria took ~17 iterations, Croatia ~6, Italy added the
> true-contour and ADM-level lessons. Every rule is documented with its rationale —
> follow them exactly, do not re-explore.

## What's automated vs. manual

**Automated** (`scripts/dataset/`):
- Boundaries (geoBoundaries ADM1 → normalize → simplify 3 resolutions)
- SVG shapes (per-entity silhouettes from the geojson)
- geo_index.json (repPoint + bbox per entity)
- JSON scaffold (names, capitals, borders via shapely adjacency, generated hints)
- Flags: WebP display + colorable drawing SVG with locked raster coat

**Manual / curated** (you provide):
- The registry entry: code, ISO, names ×4 locales, capital ×4 locales, area, population, Commons flag filename + license
- The choice of Commons flag variant (see flags section)
- Landmark images (optional, not covered)
- **Visual validation — you must look at the renders yourself**

---

## Step 1 — Curate the registry entry

Edit `scripts/dataset/datasets_registry.py`, add one entry to `DATASETS`:

```python
'austria': {
    'id': 'austria',
    'iso3': 'AUT',                 # geoBoundaries ADM1 URL
    'entity_name': 'Land', 'entity_name_plural': 'Länder',
    'region': 'Europe', 'subregion': 'Western Europe',
    'flag_aspect_ratio': '3/2',
    'hires_simplify_tol': 0.0005,  # tune so hiRes geojson < ~800 KB
    'entities': [
        {
            'code': 'AT1',         # UNIQUE, uppercase, 3-char (see uniqueness below)
            'shape_match': ['AT-1', 'Kärnten', 'Carinthia'],  # match geoBoundaries shapeISO OR shapeName
            'nom': 'Burgenland', 'nom_en': 'Burgenland',
            'nom_de': 'Burgenland', 'nom_sr_latn': 'Burgenland',
            'capital': 'Eisenstadt', 'capital_en': 'Eisenstadt',
            'capital_de': 'Eisenstadt', 'capital_sr_latn': 'Ajzenštat',
            'area': 3965, 'population': 301819,
            'commons_flag': 'Flag of Burgenland (state).svg',
            'flag_license': 'Public domain', 'flag_author': '...',
            'flag_source_url': 'https://commons.wikimedia.org/wiki/File:...',
        },
        # ... one per subdivision
    ],
},
```

### Code uniqueness is CRITICAL (this caused real bugs)
Subdivision codes (`cca2` in the JSON) must NEVER equal a world CCA2 (2-letter) NOR
another dataset's code. Switzerland reused 2-letter codes (BE/FR/GE = also Bern/
Fribourg/Geneva == Belgium/France/Georgia) → cache collisions, wrong borders, broken
inter-dataset comparisons (the DB `<id>_` storage prefix does NOT cover those surfaces).
**Use 3-char country-prefixed codes: `AT1`…`AT9`.** Store them **UPPERCASE** in the
JSON `cca2` and `borders` (Swiss convention); asset filenames are lowercase (`at1.svg`)
via the `flagPngPathForCode`/`shapePathForCode` helpers. The build runs
`assert_codes_globally_unique()` and aborts hard on any collision — keep it.

### Curated data sources
- **Names/capitals/area/population**: the country's official statistics office + Wikipedia.
  For `nom_sr_latn`, use the Serbian Wikipedia `sr-el` (latinica) pages — do not
  machine-transliterate without checking.
- Verify every `commons_flag` filename EXISTS on Commons by fetching its `File:` page
  (filenames are easy to guess wrong). Confirm license (Austrian/Swiss official flags
  are Public Domain by law).

---

## Step 2 — Run the data pipeline

```bash
python scripts/dataset/build_dataset.py  --dataset <id>   # geojson, shapes, geo_index, JSON scaffold
python scripts/dataset/fetch_flags.py    --dataset <id>   # download Commons SVG → flags_svg_src/ + WebP display
python scripts/dataset/build_raster_coat.py --dataset <id># drawing SVGs (bands + locked raster coat)  ← FINAL flag step
```

Outputs land under `assets/<id>/`: `<id>.{hiRes,midRes,lowRes}.geo.json`,
`<id>.geo_index.json`, `<id>.json`, `shapes/`, `flags_webp/`, `flags_svg/`,
`flags_svg_src/` (pristine Commons sources, versioned but NOT in pubspec),
`FLAG_SOURCES.json`.

After running, **verify the geojson sizes** (hiRes < ~800 KB — geoBoundaries raw is
over-detailed, e.g. Austria raw 17 MB → 614 KB simplified) and **Read 2-3 WebP files
yourself** (the builder is blind to images).

---

## Drawing-game SVGs — hard rules (learned the hard way)

These rules were distilled across ~17 Austrian iterations and ~6 Croatian rounds.
Violating any one typically causes a multi-round debug spiral. Follow them exactly.

### Rule 1 — Coat = standalone source, NEVER carved from the flag

Download each entity's coat-of-arms SVG to `assets/<ds>/coats_src/<code>_coat.svg`
(Wikimedia CC/PD). `build_raster_coat.py` renders it standalone (Inkscape, no field
background) for the locked `<g id="prefilled">` raster → **exact silhouette, zero
flag-field pixels**.

Carving the coat out of the full-flag render is a dead end:
- Colour-distance detection under-covers shields that share the field palette (e.g.
  a blue shield on a blue-diagonal field — hr12 Brod-Posavina). Only the yellow
  marten was detected; the shield was placed tiny and low.
- Any field fringe around the emblem bakes the wrong colour into the locked raster,
  creating a halo the player cannot colour away.
- The carving shape degrades when the coat overlaps a stripe boundary.

**Standalone source** = none of these problems. One render, clean silhouette, reused
for both the `<image>` raster and the `_coat_ref.png` IoU assertion.

### Rule 2 — Field zones exclude the coat footprint (silhouette carve) — AND the locked raster must follow the emblem's TRUE CONTOUR

**The locked `<image>` must contain ONLY the drawn emblem pixels.** Any flat, contiguous
FIELD region outside the emblem's drawn contour must be transparent (alpha 0) and therefore
colourable — EVEN IF that field colour also appears inside the emblem. Forbidden: a
full-canvas raster, a closed/dilated silhouette mask, or any mask that "grabs everything
around" the emblem (Veneto's gonfalone and Sardinia were the canonical smell of this bug).
Instead: erode the silhouette mask 1–2 px (never close/dilate); strip edge pixels whose
colour is within a small perceptual distance of any field colour.

The goal is double: **zero colour leak** (no field colour baked into the locked layer,
which would reveal part of the answer) AND **maximum colourable field** (the player gets
to colour as much of the flag as is technically possible). A mask that is slightly too
large on the boundary fails both goals simultaneously.

The coat's silhouette mask is also **carved out** of all non-base field zones. Without
this, a field-zone contour that crosses the shield boundary jogs around the detected
coat sub-region — creating the rectangular-notch bug (visible as a blocky indent where
the diagonal stripe passes behind the shield).

The base colour (largest field) is drawn as the full opaque silhouette so it backs the
coat footprint; every other zone is `(nearest-field colour) & ~coat-silhouette`. Since
the opaque coat raster fully covers the footprint, the clean-cut edges are never
visible at runtime.

### Rule 3 — Full-shield footprint recovery for same-palette emblems

When the coat shares the field's palette (blue shield on blue/white field), colour-
distance detection under-covers the shield to only its distinctive sub-content
(the yellow marten/stars). Fix: `_refine_footprint_from_coat` in
`build_raster_coat.py` — it renders the standalone coat alone, measures where its
*distinctive* (far-from-field) content sits within its full silhouette as fractions
(t/b/l/r), then inverts those fractions on the flag's distinctive-content bbox to
recover the full shield rectangle. This is palette-independent and generalises:
when the coat is fully distinctive (green/blue shield, hr03), the fractions are ≈ 0/1
and the result is a near-identity. For hr12, it recovered y=55→253 (was y=171→237).

### Rule 4 — Colour quantisation: one zone per TRUE field colour

After field detection, snap each raster colour to the nearest source-palette hex and
merge duplicates. Anti-aliased renders produce two slightly-different blues where there
is one — without this step you get two zones for one field colour, confusing the player
and failing the `≤ 3 colours` assertion.

### Rule 5 — Contour simplification: clean lines, not pixel staircases

`approxPolyDP` with epsilon ≈ **0.6% of the render dimension** (~6px at 1024-wide
render). The contour is traced pixel-by-pixel so straight/diagonal flag edges come out
as stair-steps. This epsilon collapses near-collinear runs into clean straight segments.

**hr12 was the worst case**: the white diagonal stripe appeared as a staircase of
horizontal steps — visually broken even though the mean colour distance (~6) was below
the 25 threshold. The local metric (Rule in "Validation gate") catches this.

Do not lower the epsilon back to 0.6px: it keeps the pixel staircase without providing
any benefit. Verify the narrow hoist band (hr03: 6% of width, ~60px) still survives —
it does at this epsilon.

### Rule 6 — WebP aspect ratio must be exact

The display WebP (`assets/<ds>/flags_webp/<code>.webp`) must be the entity's exact
official aspect ratio, which equals the dataset's `flagAspectRatio` config value.
The choosing game uses `BoxFit.fill` on a box sized by the flag's viewBox AR — an
off-ratio WebP gets stretched. Normalise to the exact canvas (e.g. 512×256 for 2:1
county flags) using `fetch_flags.py`'s `normalize_webp` step.

### Rule 7 — ≥ 1 large colourable zone, complex coat = locked raster + colourable field

This was established with Austria and still applies. See the existing "IRON RULE"
section below for the fallback chain. The harness asserts ≥ 1 free zone ≥ 5% of
canvas (A7: every colour ≥ 2%).

### Pitfalls / dead ends — do not repeat

1. **Do not carve the coat from the flag render** — see Rule 1.
2. **Do not colour-flood-fill to remove fringe** — it destroys same-colour emblems
   (a solid blue flood fill kills a blue shield on a blue field entirely).
3. **Do not use the zone-count or coat-IoU alone as proof of correctness** — a
   globally-low mean colour distance does NOT mean the flag looks right. A small
   jagged region is diluted across the whole field. Always run the LOCAL metric.
4. **Do not use cairosvg** to judge renders — it is not faithful to the Flutter
   painter. Use the Dart harness only.
5. **Do not use a bbox rectangle for the coat-zone carve** — it creates rectangular
   notches in diagonal stripes (hr12 bug). Use the coat's actual silhouette mask.
6. **Do not re-explore posterized-paths or raw-vector coats** — both failed in Austria
   (see "Pitfalls" in the section below).
7. **Never simplify or redraw an asset to make a complex emblem colourable.** This
   never worked: a simplified emblem is a different emblem, and redrawing is not
   reproducible. Keep the Commons source faithful. If a colour belongs to the emblem
   itself (a shield charge, heraldic field inside the arms), it stays locked in the
   raster. If it belongs to the flag's FIELD (a large background zone outside the
   arms), it must be transparent/colourable. The correct tool is a tighter contour
   mask — or, for a truly irreducible full-canvas design, exclude the entity from
   drawing entirely (see "Excluding a too-complex flag" below).

---

## Flags: the hard-won recipe (DO NOT RE-EXPLORE)

The flag system has **two decoupled outputs from one Commons source**:

| Output | Field | Purpose | How it's made |
|---|---|---|---|
| **WebP** | `flagPng` | display / recognition (flag-typing, choosing) | **rasterized DIRECTLY from the pristine Commons source via Inkscape** |
| **drawing SVG** | `flag` | the coloring game ONLY | bands as colorable `<path>` rects + coat as **locked raster `<image>`** |

### The drawing game's hard constraint
`lib/pages/games/drawing/` paints **1 `<path>` = 1 colorable zone**, palette = unique
colors, win = every NON-locked zone matches its color, painter is always
`PathFillType.nonZero`, and **no reference image is shown** (you color from memory).
A detailed coat-of-arms is fundamentally incompatible with "1 path = 1 zone": the same
color lives at two depths (shield field BEHIND a charge + highlights IN FRONT), so no
path ordering reproduces it — fixing one flag breaks another. **Faithful XOR fillable.**

### The solution (final, robust on all 9 Austrian + 21 Croatian flags)
- **Bands (the field)** = `<path>` rects covering the flag background → the ONLY zones the
  player colors. Grey until colored.
- **Coat** = a LOCKED raster `<image>` (base64 PNG, transparent outside the shield
  silhouette) inside `<g id="prefilled">` → **pixel-identical to the WebP, sharp,
  robust**. Pre-painted, not clickable, excluded from palette and win condition.

`build_raster_coat.py` produces this: Inkscape renders the source → diff vs a "pure
bands" image gives the shield silhouette mask (closing + fill-holes) → keep only masked
pixels, transparent elsewhere, crop to bbox → base64 `<image>` at the shield bbox.
Read its module docstring before editing.

### IRON RULE: ≥ 1 large colourable zone — never 0 bands (enforced by build_raster_coat.py)

**Every entity in a drawing-game dataset MUST have at least one colourable zone whose
area is ≥ 5% of the canvas.** "Colourable" = a free `<path>` NOT inside `<g id="prefilled">`.

This rule was discovered with Croatia: county flags whose entire surface is a complex
coat of arms (e.g. Zagreb County) initially produced 0 colourable zones.

**The solution** — `build_raster_coat.py` implements a fallback chain:

1. **Source-first** (`_parse_bands_from_source`): always try the pristine Commons source
   SVG first. It extracts `<rect>` elements and simple rectangular `<path>` elements
   whose bounding box overlaps the viewBox substantially (≥ 5% area, within 15% margin).
   This produces the true background field rectangles (e.g. Zagreb County's 5 green/white
   bands that picosvg missed).

2. **Intermediate fallback**: if source extraction fails (SVG uses transforms or other
   coordinate systems), use the picosvg-vectorized intermediate SVG. BUT: if the smallest
   band in the intermediate is < 3% of the viewBox, it's likely a coat-detail path smuggled
   through `_rect_bbox`, not a real background band → discard and proceed to step 3.

3. **Dominant border colour**: if both above fail, compute the dominant colour along the
   top/bottom 10% of the rendered PNG → synthesise a full-background `<path>` rect.
   This guarantees ≥ 1 zone even for a flag that is 100% complex vector geometry.

**For a "blason sur champ uni" flag** (coat on plain field, no background bands in the
intermediate SVG): the FIELD is the colourable zone. Even if that field is white, the
player colours it. The coat is the prefilled raster. One zone is enough.

**Check after every run**: `minFreePct` in the render harness summary must be ≥ 5%
for every entity. A `NO_BANDS` or `SMALL` result = re-run `build_raster_coat.py` and
diagnose why the fallback did not produce a large band.

### The locked-zone mechanism (already in the codebase, dataset-agnostic)
A `<g id="prefilled">` marks its children as `FlagZone.locked=true` — pre-painted, not
hit-tested, not in palette, not in the win check. A `<image>` under it becomes a
`FlagImageLayer` (decoded `ui.Image`, cached, drawn over the bands). Files:
`flag_parser.dart`, `models/flag_data.dart` (`FlagImageLayer`), `painter/flag_painter.dart`,
`state/drawing_game_{state,provider}.dart`. **Inactive without the marker → world/Swiss
flags unchanged.**

### Pitfalls that cost us ~17 iterations — DO NOT repeat
1. **Never rasterize the WebP from the drawing SVG.** It mangles coats (Styria went all-
   black, Burgenland's eagle washed out). WebP = pristine Commons source, always.
2. **Never reproduce the coat as posterized paths** (KMeans → blurry blobs) **nor as
   raw source vectors** (layer-order masks charges → Salzburg's lion vanished). Use the
   raster `<image>` layer.
3. **Never mask the coat by its bounding box** — a rectangle leaks the band colors around
   the shield (reveals the answer). Mask to the **shield silhouette** (diff vs pure-bands
   + fill-holes).
4. The painter **ignores `stroke`** (fills only) — irrelevant now (raster), but it's why
   vector coats lost their outlines.
5. **cairosvg is NOT faithful to the Flutter painter.** Judge renders ONLY with the real-
   painter harness (below), never cairosvg.
6. If flags share a civil design (Austria: Tyrol=Upper-Austria, Salzburg=Vienna=Vorarlberg),
   use the **coat-of-arms variant** (`Flag of X (state).svg`) so each is distinct.

### Excluding a too-complex flag from the drawing game

When an emblem is an irreducible full-canvas heraldic scene that adds nothing as a
colouring exercise (e.g. a complete gonfalone where the entire flag surface is a painted
scene — Veneto is the canonical case), **exclude just that entity from the `flagDrawing`
activity** rather than forcing a bad experience.

How: set that entity's `flag` field (the drawing-SVG path) to `null` or absent in the
dataset JSON. `hasRequiredResourceForActivity(ActivityType.flagDrawing)` in
`lib/providers/adventure_provider.dart` checks `country.flag != null && isNotEmpty`, so
the entity is silently skipped in the drawing game while remaining **fully playable in all
other activities** (flag-typing, choosing, capital, shape, map placement). Keep its WebP,
shape, and all other JSON fields intact.

Also remove that entity's code from the dataset's render-test `codes` list in
`test/<dataset>_flag_render_test.dart` — there is no SVG to render.

Important: every OTHER drawing flag must still keep ≥ 1 colourable zone ≥ 5% (Rule 7 /
IRON RULE). Exclusion is not a blanket escape hatch — it is reserved for the rare case
where the flag is an irreducible scene and the colourable field adds zero value.

### Dead scripts (superseded — for reference only, don't use)
`simplify_flag_svg.py`, `vectorize_flag_svg.py`, `build_iso_svg.py` were failed flag-coat
attempts. The canonical flag step is **`build_raster_coat.py`**. (Safe to delete in a
future cleanup.)

---

## The render harness — the authoritative way to judge flags

### Validation gate (mandatory — no exceptions)

The harness uses the **real Flutter painter** (PictureRecorder → PNG, same path as
the live drawing game), never cairosvg. Every assertion is quantitative:

| Assertion | What it catches |
|---|---|
| `coat bbox ≤ 50%` OR `transparent ≤ 10%` | Whole-flag raster baked into locked layer |
| `coat bbox < 85%` | Coat covers essentially the whole flag |
| `coat IoU ≥ 0.80` vs `_coat_ref.png` | Coat was carved from flag (field pixels baked in) |
| `≥ 1 free zone`, `≥ 1 distinct free colour` | Drawing game is playable |
| `≤ maxFreeColors` distinct colourable colours | Coat colours leaking into field zones |
| Every colour has a tappable zone `≥ 2%` of canvas | Sub-pixel zones that can't be tapped |
| Magenta-probe residual background `< 2%` | Gaps in the field coverage |
| **Painted-vs-WebP field mean colour distance `< 25`** | Field colour is wrong or coat covers wrong area |
| **Worst 16×16 tile mean error `< 95`** | **Localised damage: stair-stepped edges, misplaced coat hole** |
| **High-error pixel fraction `< 5%`** | **Large jagged / misaligned region** |

The last two (worst-tile + high-error-fraction) are the most important and were added
after hr12 (stair-stepped diagonals + misplaced coat) slipped through with a global
mean of ~6 (≪ 25). A small broken region is diluted in a global mean — the local
metric catches it. **Pre-fix hr12: worstTile 187, highErrFrac 6.9% → FAIL. Fixed: 14
/ 0.09% → pass.**

The harness also writes snapshot PNGs to `/tmp/flag_render_<dataset>/`:
- `<code>_compare.png` — painted-correct at the canonical WebP canvas; compare to the
  WebP mentally. **You must visually review every `_compare.png`** — no agent verdict
  substitutes for your own eyes. This is the final sign-off gate.
- `<code>_initial.png` — **MANDATORY REVIEW.** Initial game state: grey unpainted field
  plus the locked coat. Look at this plate for every entity. Around AND behind the emblem
  there must be **grey only** — never a ring or patch of a field colour. Any coloured zone
  in the initial state means something is locked that should be colourable — the answer is
  being revealed to the player before they start. The harness thresholds can pass while
  the flag is visually broken (a small colour leak is diluted in aggregate metrics). Do
  NOT relax `worstTile`/`highErrFrac`/`meanDist` to force a pass on a broken plate; the
  `_initial.png` and `_compare.png` plates reviewed by human eyes are the authoritative
  gate, not the numeric thresholds.
- `<code>_correct.png` — all zones painted at correct colour + coat.
- `<code>_zones.png` — zone coverage map (categorical colours, no coat).

A sub-agent once fabricated a visual verdict on a plate that didn't exist —
**Read the file yourself with the `Read` tool; never trust "it's OK".**

### Reusable harness (one-liner wrapper per dataset)

The harness logic lives in `test/support/dataset_flag_render_harness.dart`.  Every
new dataset's test is a **~15-line wrapper**:

```dart
// test/france_flag_render_test.dart
import 'support/dataset_flag_render_harness.dart';

// Resolve the env override here (String.fromEnvironment requires a literal key).
const _svgDir = String.fromEnvironment(
  'FRANCE_SVG_DIR',
  defaultValue: 'assets/france/flags_svg',
);

void main() => runDatasetFlagRenderHarness(
  datasetId: 'france',
  codes: const ['fr01', 'fr02', /* … */],
  cmpW: 512, cmpH: 256,  // dataset's canonical WebP size
  svgDir: _svgDir,
);
```

Override to prove failure on broken assets:
```bash
flutter test test/france_flag_render_test.dart \
  --dart-define=FRANCE_SVG_DIR=/tmp/france_svg_backup
```

Tune optional parameters if the dataset needs them:
- `maxFreeColors: 4` — for datasets with 4-colour field patterns.
- `meanDistThreshold: 30.0` — if the flag's field colour is a precise shade that
  anti-aliases differently from the WebP (rare; check the compare PNGs first).
- `worstTileThreshold` / `highErrFracThreshold` — do not relax these without a
  documented reason; the defaults were calibrated on 21 Croatian counties.

The `test/austria_flag_render_test.dart` is an older **generator-only** harness (no
assertions, always passes). It remains as-is; migrating it would require regenerating
Austria's SVGs with the new pipeline and fixing any latent bugs, which is a separate
task (see "Austria implication" note at the end of this skill).

---

## Step 3 — Wire into Flutter (8 touch-points, additive)

1. **`lib/core/config/game_dataset.dart`** — enum value + `_<id>Layout` constant (copy
   `_switzerlandLayout`: no coats/anthem; set `flagAspectRatio`)
2. **`lib/core/config/adventure_regions_config.dart`** — `_RegionDefinition(id:'<id>_states',
   orderIndex: 10X, subregions: const [], dataset:'<id>')`
3. **`lib/core/i18n/region_i18n.dart`** — region label case + 4 `GameDataset.<id>` cases
   (displayName/description/entityName/entityNamePlural)
4. **3 adventure pages** — region→SVG map entry (`starting_region_selector_page`,
   `unlock_selector_page`, `widgets/region_carousel`). Use the generic
   `getDatasetForRegion(region.id).localizedEntityNamePlural(t)` for the entity label —
   do NOT hardcode `t.dataset.switzerland.entityNamePlural` (that bug showed "cantons"
   for every dataset).
5. **`lib/pages/modes/discovery/discovery_page.dart`** — `_datasetMeta` + `_datasetLabel` cases
6. **`pubspec.yaml`** — register `assets/<id>/`, `flags_webp/`, `flags_svg/`, `shapes/`
   (NOT `flags_svg_src/` — keep sources versioned but unbundled)
7. **i18n ×4 (iron rule)** — `lib/i18n/{fr,en,de,sr-Latn}.i18n.json`: dataset section +
   region label + discovery labels, in ALL FOUR files (a missing key → `extends_non_class`
   compile error or silent FR fallback)
8. **codegen** — `dart run slang` then `dart run build_runner build --delete-conflicting-outputs`

---

## Step 4 — Validate (with evidence)

- `flutter analyze` → 0 errors / 0 warnings (delta vs baseline).
- Flag renders: run the harness, **look at the plate yourself** — COMPLETED == WebP,
  INITIAL = coat-on-grey, no leak. Check the tricky coats (lion/eagle/panther).
- Codes: build aborted on no collision; `grep` confirms `<id>` codes appear nowhere else.
- Device (dev flavor, on green light): Adventure → region unlockable & playable
  (flag/capital typing, **drawing = color bands around the locked coat**, map placement
  of all entities, shape typing); Discovery → collection shows the entities; walk DE +
  sr-Latn (no FR leak). On a fresh profile the region is locked (high orderIndex) — to
  test in-game, unlock it (edit the local DB: `regions.is_unlocked=1` +
  `adventure_progress.total_miles`).

---

## Reference: data sources

- **Boundaries**: geoBoundaries gbOpen — the API URL is
  `https://www.geoboundaries.org/api/current/gbOpen/<ISO3>/ADM1/` (replace `ADM1` with
  the actual level), returns JSON with `gjDownloadURL` → the geojson (redirects to
  media.githubusercontent; urllib follows it).

  **⚠️ ADM level caveat:** a country's first-level subdivisions are NOT always at ADM1 in
  geoBoundaries. Italy's 20 regions, for example, are at **ADM2** (ITA/ADM1 = 5 NUTS-1
  macro-areas). Always verify the correct level on the geoBoundaries page for the ISO3
  before running the pipeline. The registry `adm_level` field (default `'ADM1'`) selects it:
  ```python
  'italy': { 'adm_level': 'ADM2', ... }
  ```
  Also: the `shapeISO` column may be **empty** for many entries in the source GeoJSON
  (Italy had no `shapeISO` values at ADM2). In that case, `shape_match` must fall back
  to matching on `shapeName` (verbatim region name). Watch for hyphens and apostrophes
  that differ between sources (e.g. `"Valle d'Aosta"` vs `"Vallée d'Aoste"`).

- **Flags**: Wikimedia Commons — `Special:FilePath/<filename>` for the raw SVG, or the
  imageinfo API for the original URL. Pick the with-arms variant when civil flags repeat.
- **Names/capitals**: official statistics office + Wikipedia (sr-el pages for sr-Latn).
- **Stats**: not auto here — reuse `scripts/fetch_country_statistics.py` patterns if needed.

## Landmarks (the `landmarkTyping` activity)

The advanced layer includes `ActivityType.landmarkTyping` (see the layout in step 1).
Entities whose `landmarkImage` is absent are silently skipped by
`hasRequiredResourceForActivity` in `lib/providers/adventure_provider.dart`, so a
partially-covered dataset merely shows fewer questions — it does NOT break region
completion. **Aim for full coverage, but partial is shippable.**

### Graceful without landmarks — MANDATORY

If landmarks are not yet curated, **do not leave `landmarkTyping` in `difficultyLayout`
without disabling it** — an empty activity list navigates to a blank page. Instead:

```dart
// In GameDataset enum value for the new dataset:
disabledActivities: const ['landmark_typing'],  // re-enable after curation
```

Remove this line once `assets/<id>/landmarks/` is populated and all i18n fields are
written. To intentionally skip one entity: remove all `landmark*` keys from that entity in
`<ds>.json` and delete its `<code>.webp`. Do NOT set `disabledActivities` for a single
entity — that kills the activity dataset-wide.

---

### Two-phase landmark curation runbook

The tooling lives in `scripts/landmarks_improved/`. It is a small Flask web app driven by:

```bash
python3 scripts/landmarks_improved/run.py {phase1|phase2|status} \
    --dataset <id> --port <port>
```

**Port note**: 8080 is taken by Gradle. Use a free port, e.g. 8082 for the first dataset,
8083 for a second concurrent session. Kill a server with `fuser -k <port>/tcp`. Do NOT
use `pgrep -f run.py` to find the process — it matches itself and causes auto-kill.

---

#### Phase 0 — Candidate generation (input to Phase 1)

Before launching Phase 1 you need a curated candidates file. Create or edit:

```
scripts/landmarks_improved/data/landmark_candidates_<dataset>.json
```

Structure (one entry per entity):

```json
{
  "HR07": {
    "entity": "Comté de Sisak-Moslavina",
    "current": null,
    "candidates": [
      {
        "name_fr": "Rupnica — orgues volcaniques",
        "type": "géologie",
        "why": "Seules colonnes volcaniques de Croatie, patrimoine géologique unique.",
        "originality": "high",
        "image_hint": "basalt columns Croatia Rupnica"
      },
      { ... }
    ]
  },
  "AT1": {
    "entity": "Burgenland",
    "current": "Lac de Neusiedl",
    "candidates": [ ... ]
  }
}
```

Fields per candidate:
- `name_fr` — display name in French (used in Phase 1 card)
- `type` — short category label shown as a badge (e.g. `géologie`, `architecture`, `nature`)
- `why` — one sentence explaining the editorial interest
- `originality` — `high` | `medium` | `safe` (badge colour in the UI)
- `image_hint` — English search hint for the Phase 2 image tool

**Editorial rule — originality and diversity are the whole point.** Do not produce a list
of castles and cathedrals. Prefer: natural wonders (caves, volcanic features, lakes,
gorges), industrial heritage (cable cars, salt mines, watermills), bold modern architecture,
UNESCO sites, genuinely surprising or quirky places. Vary categories across the whole
dataset. No more than one or two of the same type in the full set.

Reference anchors of what "good" looks like:
- Croatia: Rupnica volcanic organs, Đurđevac sand dunes, Rastoke watermills, Podgarić
  war monument, world's shortest funicular (Zagreb), Imotski Red Lake — six distinct
  categories.
- Austria: steppe-lake lighthouse (Neusiedl), wooden observation tower, UNESCO railway
  viaduct, lakeside village (Hallstatt), ice cave (Eisriesenwelt), "friendly alien" art
  museum (Kunsthaus Graz), Golden Roof (Innsbruck), floating opera stage (Bregenz), Prater
  Ferris wheel — nine categories, zero redundant castle.

Provide ~4–5 candidates per entity. Web-verify each one exists before including it — a
fabricated subject wastes the user's Phase 1 session.

---

#### Phase 1 — Subject selection

```bash
python3 scripts/landmarks_improved/run.py phase1 --dataset <id> --port 8082
# Open http://localhost:8082 in browser
```

The UI shows each entity as a card with its candidates (name, type badge, why, originality
badge, image hint) plus a "current" option and a free-text override. The user picks one
subject per entity, then clicks **Export**. Output:

```
scripts/landmarks_improved/data/landmarks_validated_<dataset>.json
```

Each entry gains `name` (the chosen FR subject), `search_query` (initially equal to
`name` — **must be updated manually for native-language terms**, see Phase 2 below), and
`alternatives` (the unchosen candidates, for reference).

---

#### Phase 2 — Image selection

```bash
python3 scripts/landmarks_improved/run.py phase2 --dataset <id> --port 8082
# Open http://localhost:8082 in browser
```

The UI searches for photos per subject and lets the user pick one per entity.

**Sources active without API keys**: Wikimedia Commons + Openverse.
Unsplash / Pixabay / Pexels require keys and are optional.

##### Native-language resolution (critical for quality)

Commons categories are named in the local language (e.g. `Đurđevački pijesci`, not "Dunes
of Đurđevac"; `Bregenz Seebühne`, not "Bregenz floating stage"). A French or English search
term usually misses the relevant category entirely.

Two settings control this:

1. **`DATASETS` map in `scripts/landmarks_improved/shared/json_utils.py`** — add an entry
   for the new dataset:
   ```python
   DATASETS = {
       'croatia':     {'lang': 'hr', ...},
       'austria':     {'lang': 'de', ...},
       'switzerland': {'lang': 'de', ...},
       'world':       {'lang': None, ...},
   }
   ```

2. **`WikipediaArticleImageClient.LANG_BASES` in `shared/api_clients.py`** — add the
   Wikipedia base URL for the language:
   ```python
   LANG_BASES = {
       'hr': 'https://hr.wikipedia.org',
       'de': 'https://de.wikipedia.org',
       ...
   }
   ```

With `local_lang` set, the engine follows Wikipedia **interlanguage links** from the
French/English article title to the native title, then queries Commons using that native
title. This greatly improves recall for niche subjects where the Commons category name is
a compound native noun.

##### Curated `search_query` per subject

The most important tuning step. After Phase 1 exports `landmarks_validated_<ds>.json`,
verify the `search_query` for each subject against the **Commons File-namespace API**:

```
https://commons.wikimedia.org/w/api.php?action=query&list=search
  &srsearch=<native_term>&srnamespace=6&srlimit=5&format=json
```

Check that the top file titles in the response depict the intended subject. Refine until
they do, then write the winning native term into `search_query` in
`landmarks_validated_<ds>.json`. The `/api/search_images` endpoint in Phase 2 uses the
precedence: `?q=` URL param > `search_query` > validated `name`.

Example refinement: Croatia's sand dunes respond to `"Đurđevački pijesci"` but not to
`"Đurđevac dunes"` or to the city name alone.

##### Manual `?q=` override box

Available in the Phase 2 UI for subjects that need a one-off search term. Pre-filled with
the current `search_query`. Type a new term and press search — does not persist to the
JSON; to persist, update `search_query` directly.

##### Direct-link shortcut (fastest for a known Commons file)

When you already know the exact Commons file, bypass the gallery entirely:

1. Get the direct URL + license from the Commons API:
   ```
   https://commons.wikimedia.org/w/api.php?action=query
     &titles=File:<exact_filename>&prop=imageinfo
     &iiprop=url|extmetadata&format=json
   ```
   Read `imageinfo[0].url` (the direct download URL) and confirm the license from
   `extmetadata.LicenseShortName`.

2. POST directly to the backend:
   ```bash
   curl -s -X POST http://localhost:8082/api/download_image \
     -H 'Content-Type: application/json' \
     -d '{
       "cca2": "HR07",
       "image_url": "https://upload.wikimedia.org/wikipedia/commons/...",
       "is_review": false,
       "metadata": {
         "source": "wikimedia_commons",
         "title": "Rupnica columns.jpg",
         "photographer": "Author Name",
         "license": "CC BY-SA 4.0",
         "source_url": "https://commons.wikimedia.org/wiki/File:...",
         "creator_url": "https://commons.wikimedia.org/wiki/User:..."
       }
     }'
   ```

3. **⚠️ The WebP converter does NOT downscale.** Large source files (> ~2 MB) must be
   re-encoded after download:
   ```bash
   convert assets/<ds>/landmarks/<code>.webp \
     -resize 1600x\> -quality 80 assets/<ds>/landmarks/<code>.webp
   ```
   Target: ~150–400 KB per file (run `scripts/compress_landmarks.py [--apply]` as a
   batch check). Always prefer **landscape** orientation — the card is displayed
   `BoxFit.cover` in a horizontal ratio.

4. **Always view the resulting `.webp` yourself** with the `Read` tool. The builder is
   blind to image content; a wrong subject, a blurry crop, or a portrait-only composition
   will only be caught by human eyes.

5. **Anti-collision**: do not POST a direct-link assignment for an entity while the user is
   selecting an image for the same entity in the Phase 2 gallery tab — the double-write
   silently clobbers whichever finishes last.

##### License rule (Play Store)

Accept: **Public Domain / CC0 / CC-BY / CC-BY-SA** only.
Reject: CC-BY-NC, CC-BY-ND, "All rights reserved".
Always confirm via the `imageinfo` API — do not rely on text on the Commons page (it can
be outdated). Credits go into `landmarkImageCredits` and surface in the in-app credits page.

---

#### Step 5 — i18n finalisation (iron rule, easy to forget)

**The tool writes ONLY the French `landmarkName` when it downloads an image.** It does
not write `landmarkDesc`, nor any `_en`, `_de`, or `_sr_latn` variants. After finalising
all subjects you must fill in, for each entity in `assets/<ds>/<ds>.json`:

- `landmarkDesc` (FR base) — ~100 chars max; mention a striking fact or year; do NOT
  repeat the landmark name in the sentence.
- `landmarkName_en`, `landmarkName_de`, `landmarkName_sr_latn`
- `landmarkDesc_en`, `landmarkDesc_de`, `landmarkDesc_sr_latn`

Audit: compare `landmarkName` vs `landmarkName_en` vs `landmarkDesc` for each entity — a
mismatch (e.g. EN still says "Hallstatt" after you switched to "Dachstein") means the
fields are stale from a previous subject choice.

Iron rule: all four locales, every entity that has a landmark, in the same commit.
Use `scripts/merge_landmark_translations.py` (merges from a keyed JSON) or write the
`_xx` fields directly into the dataset JSON.

After editing the dataset JSON, run `flutter analyze` — the `Country.fromJson` parser
ignores unknown keys silently, so you will not get a compile error from a typo, but
`flutter analyze` will catch any Dart-level regressions introduced in the same diff.

---

### Data model (per entity, in the dataset JSON)

Same schema as world / Switzerland (`lib/models/country.dart`, `Country.fromJson`):

```json
"landmarkImage":    "assets/<id>/landmarks/<code>.webp",
"landmarkName":     "Orgues volcaniques de Rupnica",
"landmarkName_en":  "Rupnica Volcanic Columns",
"landmarkName_de":  "Vulkanische Orgeln von Rupnica",
"landmarkName_sr_latn": "Vulkanske orgulje Rupnice",
"landmarkDesc":     "Jedine bazaltne kolonade u Hrvatskoj, nastale erupcijom prije 30 mj. god.",
"landmarkDesc_en":  "Croatia's only basalt colonnade, formed by a volcanic eruption 30 Ma ago.",
"landmarkDesc_de":  "Kroatiens einzige Basaltsäulen, entstanden vor 30 Mio. Jahren.",
"landmarkDesc_sr_latn": "Jedine bazaltne kolonade u Hrvatskoj, nastale erupcijom pre 30 mil. god.",
"landmarkImageCredits": {
  "source": "wikimedia_commons",
  "source_url": "https://commons.wikimedia.org/wiki/File:...",
  "photographer": "Photographer Name",
  "license": "CC BY-SA 4.0"
}
```

### Wiring delta for landmarks

- `pubspec.yaml`: add `- assets/<id>/landmarks/` under `flutter: assets:`.
- The `_<id>Layout` already lists `landmarkTyping` → nothing else to wire.
  Remove `disabledActivities: const ['landmark_typing']` once coverage is complete.

### Validate landmarks

- Assemble a plate of the N landmark WebPs (labelled by entity name) and **look at it
  yourself**: striking and diverse? No two images of the same category in a row? Re-pick
  if dull or repetitive.
- Each has `landmarkImageCredits` with a free license + author.
- Check file sizes: `du -sh assets/<id>/landmarks/*.webp | sort -h` — outliers above ~500 KB
  should be re-encoded with `compress_landmarks.py`.
- Device (on green light): adventure advanced level shows "Lieux célèbres", image + zoom
  work, reveal shows the localized name/desc; Discovery sheet shows the credit line; DE +
  sr-Latn locale shows the translated strings without FR fallback leak.

### Scripts reference

| Script | Purpose |
|---|---|
| `scripts/compress_landmarks.py [--apply]` | Batch downscale to ≤ 1600px longest side + WebP m6 (dataset-agnostic) |
| `scripts/merge_landmark_translations.py` | Merge EN/DE/SR-Latn name/desc from `landmark_translations.json` keyed by code |
| `scripts/generate_landmark_descriptions.py` | Claude-API FR description generation (optional) |
| `scripts/install_canton_landmark.py` | **Switzerland-only** download helper (hardcoded paths) |

For a new dataset, use the Phase 2 tool's direct-assign POST or write landmark fields
directly into the dataset JSON. `install_canton_landmark.py` is not yet generalized.

## Austria implication (latent bugs not yet fixed)

`test/austria_flag_render_test.dart` is a generator-only harness (no assertions,
always passes). Running Austria's SVGs through the new asserting harness
(`runDatasetFlagRenderHarness`) would likely FAIL on the same class of issues fixed
for Croatia:

- `build_raster_coat.py` previously used an older pipeline (approxPolyDP epsilon 0.6px,
  rectangular coat carving, no `_refine_footprint_from_coat`). The Austria SVGs were
  generated before those fixes.
- The new harness would catch stair-stepped edges (especially any Länder with angled
  boundaries) and potentially the mean/local colour-distance assertions.

**These are NOT fixed in this branch.** To fix Austria: re-run
`python scripts/dataset/build_raster_coat.py --dataset austria` (the generator is now
fully generic) and create a proper assertion test using the `runDatasetFlagRenderHarness`
wrapper. Until done, Austria's drawing game may have visual quality issues similar to
what hr12 had.

## Notes

- World keeps unprefixed CCA2; other datasets prefix storage codes (`<id>_<code>`) for
  the DB — `GameDataset.getStorageCode`/`extractCode`.
- Nothing is merged/pushed by the pipeline — the user merges themselves; re-run codegen +
  `flutter analyze` after any merge before pushing.
