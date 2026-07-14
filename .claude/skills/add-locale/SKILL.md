---
name: add-locale
description: Use when the user asks to add a new language or locale to the Mission Geo Flutter app (e.g. "ajoute l'italien", "add Spanish translations", "support pt-BR locale").
---

# Add a new locale

## Overview

Mission Geo ships French (base, `fr`) plus English (`en`), German (`de`), and
Serbian Latin (`sr-Latn`) — 4 locales total, driven by the **slang** package.

Adding the Nth locale (`XX`) is a structured checklist with two classes of work:
- **Automatable** (scripts loop over the registry — run them once):
  country names, world capitals, canton capitals, landmark merge.
- **Manual / agent** (look up or author directly):
  canton names (traditional forms), 3 unofficial territories, 4 sub-national
  datasets, landmark descriptions, UI strings, Dart model + 4 AppLocale switches.

The single entry point is `scripts/locales_config.py` — add one descriptor there
and the scripts generate all locale-parametric JSON fields automatically.

Current datasets: 6 total — world (248 countries), switzerland (26 cantons),
austria (9 Länder), croatia (21 counties), italy (20 regions), usa (51 states).
Total entities: 375.

**Iron rule on proper nouns**: NEVER invent or machine-translate a country, canton,
or capital name. Always look it up in an authoritative source. Landmark NAMES are
proper nouns (same rule). Landmark DESCRIPTIONS (1 short prose sentence) the agent
authors directly.

## When to apply

- User says "ajoute l'espagnol", "add Portuguese", "support Italian", "new locale XX".
- Before any code change, confirm the 5 inputs below.

## Pre-flight (mandatory)

**REQUIRED SUB-SKILL: `git-workflow-branch-worktree`** — create branch
`feat/i18n-XX` in `.worktrees/i18n-XX` before the first edit.

## Inputs to confirm

Collect before starting. If any is missing, ask once, then proceed:

| Input | Example |
|---|---|
| Locale tag (BCP 47) | `pt`, `it`, `es`, `nl`, `pt-BR` |
| Flag emoji for the picker | `🇵🇹` |
| Native language name | `Português` |
| Name in FR / EN / DE / sr-Latn | `Portugais` / `Portuguese` / `Portugiesisch` / `Portugalski` |
| Keyboard layout for typing game | Run the **keyboard sufficiency check** (Step 5c) — reuse an existing layout, or add the locale's real national layout. |

## Step 1 — Add the locale to `scripts/locales_config.py`

This is the single source of truth. Add an entry to `LOCALES`:

```python
LocaleDescriptor(
    tag="pt",
    json_suffix="pt",           # snake_case suffix for JSON keys: nom_pt, capital_pt, ...
    dart_field_camel="Pt",      # CamelCase suffix for Dart fields: nomPt, capitalsPt, ...
    language_codes=["pt"],      # Dart switch case value(s)
    name_strategy=NameStrategy.WORLD_JSON_INLINE,   # 'translations.por.common' already in world.json
    rest_translation_code="por",                    # key inside world.json translations dict
    name_transform=None,
    wikidata_sparql_lang="pt",
    wikidata_post_transform=None,
    wikidata_capital_fallback_lang=None,
    has_landmark_translations=True,
)
```

**NameStrategy guide:**

| Strategy | When | Example |
|---|---|---|
| `REST_TOP_LEVEL` | English: `name.common` from REST Countries API | en |
| `REST_TRANSLATION` | Any language in REST Countries `translations.<code>.common` without transform | de (deu) |
| `REST_TRANSLATION_TRANSLITERATED` | API translation + character transform | sr-Latn (srp + cyr->lat) |
| `WORLD_JSON_INLINE` | Translation already in world.json `translations` field — zero network. Supported codes: ara bre ces cym deu est fin fra hrv hun ita jpn kor nld per pol por rus slk spa srp swe tur urd zho | pt (por), it (ita), es (spa), nl (nld) |

**Script-tag locales** (e.g. `sr-Latn`):
- `json_suffix` = `sr_latn` (hyphen becomes underscore)
- `dart_field_camel` = `SrLatn`
- `language_codes` = `["sr", "sr-Latn"]` — dual-case, both matched in Dart switches

## Step 2 — Run the automatable pipeline

```bash
python scripts/add_locale.py <tag>
# For a new wikidata_sparql_lang not yet in the cache:
python scripts/add_locale.py <tag> --refresh
```

This orchestrates (in order):
1. **Country names** (`add_country_translations.py`): writes `nom_<json_suffix>` to
   `assets/world/world.json` for all 248 entries. WORLD_JSON_INLINE = zero network.
2. **World capitals** (`add_capital_translations.py`): writes `capital_<json_suffix>`
   arrays using the Wikidata cache (`scripts/cache/capitals_wikidata.json`).
3. **Canton capitals** (`add_canton_capital_translations.py`): same for 26 cantons.
4. **Landmark merge** (`merge_landmark_translations.py`): reads
   `scripts/landmark_translations.json` and inserts `landmarkName_<json_suffix>` /
   `landmarkDesc_<json_suffix>` into world.json after the FR anchors.

After step 2, `git diff --stat assets/world/world.json assets/switzerland/switzerland.json`
shows the newly added fields. The existing locales remain byte-identical.

**Tooling guarantees (verify after running):**
- **Isolated, zero-drift**: the driver passes `--only <tag>` to
  `add_country_translations.py`, so an inline locale adds ONLY `nom_<suffix>` and
  never re-fetches REST for the existing locales. Confirm with a parsed compare:
  the only added keys should be `nom_<suffix>` / `capital_<suffix>`; drift on
  existing `nom_*` / `capital_*` must be **0**.
- **Format preserved**: all scripts use `write_json_like` (in `locales_config.py`),
  which keeps world.json **minified** and switzerland/dataset JSONs **indented**.
  If `wc -l assets/world/world.json` jumps from 0 to thousands, a writer was not
  using the helper — fix it (un-minifying world.json is a ~700k-line noise diff).
- **Capital `--refresh` drift**: refreshing the Wikidata cache to fetch the new
  language can also change a few EXISTING capital values (Wikidata mutated since the
  cache was built — e.g. an exonym replaced by an endonym). After a `--refresh`,
  parsed-compare the existing `capital_*` fields against HEAD; **restore any drifted
  existing values** (keep only the new `capital_<suffix>`), or pin them in
  `SPECIFIC_OVERRIDES` so future refreshes stay stable.

The script prints a full manual checklist at the end — use it.

## Step 3 — MANUAL data (agent writes directly)

These cannot be automated. Write them directly, then run the relevant script.

### 3a. Canton names (26 Swiss cantons)

Edit `CANTON_TRANSLATIONS` in `scripts/add_canton_translations.py`. Add the
`"<json_suffix>"` column to every entry (26 rows).

**Authoritative sources (in order):**
1. Swiss Federal Statistical Office (BFS/OFS):
   https://www.bfs.admin.ch/bfs/en/home/basics/political-divisions.html
2. Wikipedia "Cantons of Switzerland" in the target language.

**Tricky cantons** — these have traditional translated forms that differ from French/German:

| Canton | FR | DE | Note (check in target lang) |
|---|---|---|---|
| Aargau | Argovie | Aargau | IT: Argovia; PT: Argovia |
| Appenzell IR | Appenzell Rhodes-Int. | Appenzell Innerrhoden | IT: Appenzello Interno |
| Appenzell AR | Appenzell Rhodes-Ext. | Appenzell Ausserrhoden | IT: Appenzello Esterno |
| Geneva | Geneve | Genf | IT/ES: Ginebra/Ginevra; PT: Genebra |
| Grisons | Grisons | Graubuenden | IT: Grigioni; PT: Grisoens |
| Lucerne | Lucerne | Luzern | IT: Lucerna; PT: Lucerna |
| Neuchatel | Neuchatel | Neuenburg | IT keeps FR form |
| Schaffhausen | Schaffhouse | Schaffhausen | IT: Sciaffusa |
| Schwyz | Schwyz | Schwyz | IT: Svitto |
| Solothurn | Soleure | Solothurn | IT: Soletta |
| Ticino | Tessin | Tessin | IT/PT: Ticino |
| Valais | Valais | Wallis | IT: Vallese; PT: Valais |
| Vaud | Vaud | Waadt | IT/PT: Vaud |
| Zurich | Zurich | Zurich | IT: Zurigo; PT: Zurique |

Then run: `python scripts/add_canton_translations.py`

### 3b. 3 territories not in REST Countries (MF, XS, XC)

Edit `MANUAL_TRANSLATIONS` in `scripts/add_country_translations.py`.
Add the `"<json_suffix>"` key to the MF, XS, XC entries:

```python
"MF": {"en": "Saint Martin", "de": "Saint-Martin", "sr_latn": "Sveti Martin", "pt": "Sao Martinho"},
"XS": {"en": "Somaliland",   "de": "Somaliland",   "sr_latn": "Somaliland",   "pt": "Somalandia"},
"XC": {"en": "Northern Cyprus","de": "Nordzypern", "sr_latn": "Severni Kipar","pt": "Chipre do Norte"},
```

Look up the official/common forms in the target-language Wikipedia article.
Then re-run step 2.

### 3c. Sub-national dataset entities (4 datasets)

Edit `scripts/dataset/datasets_registry.py`. For EVERY entity in all 4 datasets
(Austria 9, Croatia 21, Italy 20, USA 51), add:
```python
'nom_<json_suffix>':     '<name in target language>',
'capital_<json_suffix>': '<capital name in target language>',
```

Sources: Wikipedia in the target language (search "Bundeslaender Oesterreich" etc.),
official state/regional government websites.

Note: `switzerland.json` does NOT carry landmark fields — this asymmetry is
intentional and must be preserved.

### 3d. Landmark names + descriptions (248 world entries)

For each of the 248 countries in `scripts/landmark_translations.json`, add:
```json
"landmarkName_<json_suffix>": "<official name in target language>",
"landmarkDesc_<json_suffix>": "<one prose sentence authored by the agent>"
```

**Iron rule:**
- `landmarkName_*` is a proper noun — look it up. Never invent. Acceptable sources:
  the target-language Wikipedia article for the landmark, official tourism sites.
- `landmarkDesc_*` is a short prose sentence (~80 chars, present tense, factual).
  The agent authors it directly — this is NOT a translation of the FR description.

Then run: `python scripts/merge_landmark_translations.py`

### 3e. Capital overrides (if Wikidata coverage is thin)

Check the Step 2 output for WARNING lines about capitals falling back.
For each reported capital, add an entry to `MANUAL_OVERRIDES` or
`SPECIFIC_OVERRIDES` in `scripts/add_capital_translations.py`, using
`"<json_suffix>"` as the key alongside the existing "fr", "en", "de", "sr_latn" keys.

## Step 4 — UI strings

```
lib/i18n/fr.i18n.json   ->  copy to  lib/i18n/<tag>.i18n.json
```

1. Translate every value from FR. Keep every key and every `{placeholder}` unchanged.
2. Add `language.<native_key>: "<NativeName>"` to ALL 4 existing locale files
   (fr, en, de, sr-Latn). The new key must be in all four — missing = silently falls back to FR.
3. Flag for the user any string where you were uncertain (idiom, game name like
   "Plus ou Moins", wordplay). List them in your output, do not guess silently.
4. Run: `dart run slang`
5. Confirm `lib/i18n/strings.g.dart` contains `AppLocale.<generatedName>` and
   `lib/i18n/strings_<sanitized_tag>.g.dart` exists.

**JSON format trap:** never close a `"..."` string value with a `'` ASCII quote or
mismatched delimiter. This breaks slang silently while `flutter analyze` passes on
stale .g.dart. After every i18n edit: run `dart run slang`, then grep the new key
in `strings_fr.g.dart` to confirm the file was regenerated.

## Step 5 — Dart edits

### 5a. `lib/models/country.dart`

Four families of additions (one field + one switch case per family):

```dart
// Freezed fields (in the @freezed factory):
String? nom<Camel>,             // e.g. nomPt
List<String>? capitals<Camel>,  // e.g. capitalsPt
String? landmarkName<Camel>,    // e.g. landmarkNamePt
String? landmarkDesc<Camel>,    // e.g. landmarkDescPt

// localizedName switch:
'pt' => (nomPt?.isNotEmpty ?? false) ? nomPt! : nom,

// capitalsForLanguage switch:
'pt' => capitalsPt,

// landmarkNameForLanguage switch:
'pt' => landmarkNamePt,

// landmarkDescForLanguage switch:
'pt' => landmarkDescPt,

// fromJson parsing:
final nomPt = json['nom_pt'] as String?;
final capitalsPtList = json['capital_pt'] as List<dynamic>?;
final capitalsPt = capitalsPtList?.map((e) => e as String).toList();
final landmarkNamePt = json['landmarkName_pt'] as String?;
final landmarkDescPt = json['landmarkDesc_pt'] as String?;

// Country(...) constructor call — add all 4:
nomPt: nomPt,
capitalsPt: capitalsPt,
landmarkNamePt: landmarkNamePt,
landmarkDescPt: landmarkDescPt,
```

For script-tagged locales (e.g. `sr-Latn`): the switch case uses the dual pattern
`'sr' || 'sr-Latn' =>` — see existing sr-Latn implementation for reference.
JSON key: `nom_sr_latn`, Dart field: `nomSrLatn`.

Run: `dart run build_runner build --delete-conflicting-outputs`

### 5b. 4 compile-blocking AppLocale switches

All 4 are Dart exhaustive switches — omitting the new locale = build break.

**1. `lib/pages/widgets/components/language_button.dart`**
  - `_flagFor(AppLocale)` (around L17): add `case AppLocale.<name>: return '<flag>';`
  - `_LanguageDialog.build()` (around L112): add a `_LanguageOption(...)` entry.
    Move `isLast: true` from the current last entry to the new one.

**2. `lib/pages/onboarding/onboarding_page.dart`** (around L207):
  ```dart
  AppLocale.<name> => ('<flag>', t.language.<nativeKey>),
  ```

**3. `lib/pages/profile/profile_page.dart`** (around L388):
  ```dart
  AppLocale.<name> => ('<flag>', t.language.<nativeKey>),
  ```

**4. `lib/providers/keyboard_layout_provider.dart`** (around L94, `defaultForLocale`):
  ```dart
  AppLocale.<name> => KeyboardLayout.<layout>,
  ```

Pick the layout that matches the locale's physical keyboard convention:
qwerty (EN/PT/ES/NL), qwertz (DE/AT/CH), azerty (FR/BE), yuLatinica (SR/HR/BS),
abcd (universal fallback).

The generated `AppLocale.<name>` follows slang's camelCase rule:
`sr-Latn` becomes `AppLocale.srLatn`, `pt-BR` becomes `AppLocale.ptBr`,
`it` becomes `AppLocale.it`. Verify in `lib/i18n/strings.g.dart` after `dart run slang`.

Run: `flutter analyze` — must be zero errors before proceeding.

### 5c. Keyboard sufficiency check (mandatory — the typing game must be playable)

The typing games use an **on-screen, letters-only keyboard** (no number row, no
symbols, no dead keys). Decide whether the new locale needs its OWN layout.

**The rule — add a layout ONLY for missing LETTERS, never for accents:**

1. Answer matching is **accent-insensitive** (`removeDiacritics` in
   `lib/pages/games/typing/state/typing_game_provider.dart`). Typing "espana"
   matches "España". So accented vowels (á é í ó ú, ä ö ü, à è …) need **no key** —
   the player types the base letter and it still matches.
2. Therefore you add a new `KeyboardLayout` **only when the locale's alphabet has a
   distinct LETTER absent from existing layouts** — e.g. Spanish **Ñ** (a separate
   letter, not "N with an accent"), Serbian **Š Đ Č Ć Ž**. If every letter of the
   locale's alphabet already exists on qwerty/qwertz/azerty, **reuse one** — no new
   layout.
3. **The layout MUST be a real, standardized national layout** — never an invented
   key arrangement. Name the enum after it (`yuLatinica` = JUS Srpska latinica;
   `spanishQwerty` = teclado español QWERTY ISO, Ñ right of L). Reproduce the
   **letters-only subset** of that real layout.

**If a NEW layout is required, edit `lib/providers/keyboard_layout_provider.dart`:**
- Add the enum value with `id`, `label` (the real layout's name, e.g. `'Español (QWERTY)'`),
  and `rows` (letters-only subset of the real layout). Keep `maxRowLength ≤ 12`.
- Add the `AppLocale.<name> => KeyboardLayout.<new>` case in `defaultForLocale`.

Then **two more compile-blocking switches / keys** (easy to miss):
- `lib/pages/profile/widgets/keyboard_layout_picker.dart` → `_layoutHint(KeyboardLayout)`
  is exhaustive: add `case KeyboardLayout.<new>: return t.profile.keyboardLayout<New>Hint;`.
- Add `profile.keyboardLayout<New>` + `profile.keyboardLayout<New>Hint` to ALL i18n
  locale files (Step 4), then re-run `dart run slang`.

If you REUSE an existing layout: just set the `defaultForLocale` case (5b #4) to it.

## Validation gate (mandatory)

**REQUIRED SUB-SKILL: `visual-validation-android`** — install on the emulator and walk:

1. Home -> tap flag -> switch to XX -> home tiles render in XX.
2. Aventure -> region detail -> tap a country (proves `localizedName` resolves).
3. Defi -> Plus ou Moins (proves stat labels + "Personal record" + "Commencer").
4. Profil -> tap a badge (proves badge name/description + "Fermer").
5. Typing game -> check keyboard layout is correct for XX.
6. Switch back to FR — confirm round-trip.

Any string still in French = key missing from `XX.i18n.json`. Add it, re-run slang.

## Commit gate

Single commit on `feat/i18n-XX`:
```
feat(i18n): add <NativeName> (<tag>) locale
```
**Do NOT merge to main without explicit user OK.**

## Rationalizations to Reject

| Excuse | Reality |
|---|---|
| "I know Italian, I can write canton names from memory" | You will mis-spell at least one. Look them up from BFS + per-language Wikipedia. |
| "Country names are obvious, I'll translate them" | "Cote d'Ivoire" -> IT: "Costa d'Avorio". "Korea, Republic of" -> official PT form differs. Always use source data. |
| "WORLD_JSON_INLINE means no network at all" | True for country names. Capitals still need Wikidata (cache first, --refresh for new lang). |
| "I shipped the UI translation, idioms can be fixed later" | Flag 3-5 uncertain strings in your output for the user to review in one pass. |
| "I forgot to patch a script's per-locale column" | Re-running the script later silently overwrites the field with an empty string. Patch MANUAL_TRANSLATIONS / CANTON_TRANSLATIONS / MANUAL_OVERRIDES in the SAME commit as locales_config.py. |
| "flutter analyze is green, I'm done" | Missing translations fall back to French silently. Only the emulator catches them. |
| "I can merge since the diff is mechanical" | Validation gate is non-negotiable — wait for the user. |

## Red Flags — STOP

- About to write a canton or country name from memory -> STOP, look it up.
- About to mark done without launching the emulator -> STOP, run visual-validation-android.
- Step B capital script prints many WARNING lines -> add entries to MANUAL_OVERRIDES.
- `dart run slang` prints FormatException -> invalid JSON (often mismatched quote); fix the JSON, re-run.
- One of the 4 AppLocale switches is missing the new case -> build break; fix before committing.
- About to merge before user OK -> STOP.

## Common Mistakes

1. **Forgot a locale in one i18n file** — all 4 existing files need `language.<native>` added.
2. **Forgot one of the 4 AppLocale switches** — each is exhaustive; omission = build break.
3. **Forgot to patch a script's per-locale column** — re-running the script drops the field.
4. **switzerland.json has no landmark fields** — `landmarkName_XX` / `landmarkDesc_XX` only exist in world.json. Do not add them to switzerland.json.
5. **Script-tag vs language-code** — locale file is `sr-Latn.i18n.json`, JSON suffix is `sr_latn`, Dart switch case is `'sr' || 'sr-Latn'`, AppLocale enum is `AppLocale.srLatn`.
6. **Coupling with add-dataset** — a new dataset must populate all current locales in `datasets_registry.py`; a new locale must backfill all 4 existing sub-national datasets.
7. **248 not 246** — world.json has 248 countries (193 UN members + 2 observers + Kosovo + Taiwan + 51 territories).
8. **Keyboard: added a layout for an accent** — accents are stripped by matching; only add a layout for a missing LETTER (Ñ, Š…), and only as a REAL national layout (Step 5c). Adding a layout also touches `_layoutHint` (2nd KeyboardLayout switch) + two i18n hint keys.
9. **Un-minified world.json** — every asset-JSON writer must use `write_json_like`; world.json is minified on disk.

## Quick reference

```bash
# After editing locales_config.py + the manual data dicts:
python scripts/add_locale.py <tag>             # automatable pipeline
python scripts/add_canton_translations.py      # after filling CANTON_TRANSLATIONS
python scripts/merge_landmark_translations.py  # after filling landmark_translations.json

dart run slang
dart run build_runner build --delete-conflicting-outputs
flutter analyze

# Visual validation: invoke visual-validation-android skill
```
