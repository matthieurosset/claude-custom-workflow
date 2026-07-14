---
name: mission-geo-design-system
description: Use when creating or modifying any UI in this Mission Geo Flutter app — building a new screen, adding a widget, picking colors/fonts/spacing, styling a button/card/dialog/app bar, sizing a layout for phone / 7" / 10" tablet (responsive 3-tier), or before claiming any visual change is "consistent with the rest of the app". Triggers BEFORE the first widget edit of a UI task.
---

# Mission Geo Design System

## Overview

Mission Geo is a **kid-friendly geography game** with a recognisable look:

- **Royal-blue "sky" theme** (no light mode anywhere — palette retuned 2026-05 to a deeper royal blue, see `AppColors`)
- **Rounded everything** (radii 12 / 16 / 20 / 25)
- **Glass / blur** app bars and overlays
- **Two-font system** : **DynaPuff** for display (titres, scores, CTAs) + **Quicksand** for body — accessed via `AppText.*` tokens, never hard-coded
- **Orange accent** (`#f26c0d`) reserved for highlights, CTAs and "special" states
- **Contrast is a hard rule, not a preference.** `accent` is a fill with white content (or a small check/icon on a *light* surface) — **never orange text/icons on the blue background or surface**. Text on a white/light card is `Colors.black`/`black87`, never the white `AppColors.textPrimary`. Full pairing matrix in §"Colour usage & contrast".
- **Heavy reuse of a small set of canonical components — never invent a parallel one.** Section §Components below lists the closed set. If your need doesn't fit one, the answer is to extend an existing component, not create a new one inline.
- **3-tier responsive (phone / 7" / 10" — portrait only).** Every UI must work on `WindowSizeClass.compact` (< 600 dp) **and** `medium` (7" tablet, 600–839 dp) **and** `expanded` (10" tablet, ≥ 840 dp). Phones own the design — tablets adapt *from* the phone layout, never the reverse. See §Responsive layout.

> **Iron rule.** Before placing a colour, font size, radius, button, app bar, dialog, or card on screen, check whether a token in `AppColors`, a typography token in `AppText` (see `lib/core/theme/typography.dart`), or an existing widget under `lib/pages/widgets/components/` already covers it. If it does, use it. Inventing a new value or duplicating a component breaks visual unity and is the #1 baseline failure.
>
> **For text, NEVER write `TextStyle(fontSize: ..., fontWeight: ...)` inline.** Use `AppText.X` and adjust deviations via `.copyWith(...)`. If no token fits, add a new one to `typography.dart` instead of branching off locally.

## When to Use

- Creating a new `@RoutePage()` screen, dialog, bottom sheet, or shared widget
- Restyling an existing widget (changing colours, padding, radius, font)
- Reviewing a UI diff for "does this match the rest of the app?"
- A user reports the app "doesn't look like Mission Geo here"
- Before claiming any visual change is complete

**Skip for:** pure-logic changes (providers, services, models, scripts, tests) where no widget is touched.

## Sources of truth (read these, don't paraphrase them)

| File | What's in it |
|---|---|
| `lib/core/theme/app_theme.dart` | `AppColors` (palette + swatches), `kDisplayFontFamily` (DynaPuff), `kBodyFontFamily` (Quicksand), `getMissionGeoTheme()` |
| `lib/core/theme/typography.dart` | **`AppText.*` semantic typography tokens — use these in every `Text` widget, never hard-code `fontSize`/`fontWeight`** |
| `lib/core/theme/responsive.dart` | **3-tier `WindowSizeClass` (Compact / Medium / Expanded) + `context.windowSizeValue(...)` helper + `AdaptivePageBody` wrapper.** Plus legacy `Layout` / `layoutProvider` / `FontSizes` / `LayoutRowColumn` (kept for orientation-aware widgets but not the primary path). See "Responsive layout" section below. |
| `lib/core/theme/standard_dialog.dart` | `StandardDialog` — surface card with `PrimaryButton` (confirm, blue) + `SecondaryButton` (cancel, outlined). The only dialog shape allowed. |
| `lib/pages/widgets/components/buttons.dart` | **`PrimaryButton`, `AccentButton`, `AccentCircleButton`, `SecondaryButton`, `MenuButton`** — the canonical button set |
| `lib/pages/widgets/components/picker_option_card.dart` | `PickerOptionCard` — white card for bottom-sheet pickers |
| `lib/pages/widgets/components/app_bar.dart` | `TransparentAppBar`, `MissionGeoAppBar`, `GameBackButton`, `kAppBarHeight` |
| `lib/pages/widgets/components/cloud_background.dart` | `CloudBackground`, `AnimatedCloudBackground` |
| `lib/pages/widgets/components/language_button.dart` | Locale picker — example of the picker dialog pattern |
| `lib/pages/widgets/badge_unlock_sheet.dart` | Reference celebratory bottom sheet |
| `lib/pages/games/common/feedback_overlay.dart` | `GameFeedbackOverlay` (3 styles for correct/wrong feedback) |
| `lib/pages/games/common/score.dart` | `ScoreWidget` — the canonical confetti/score animation |
| `design.md` | High-level brief (palette, vibe, tone) — the version shown to AI design generators |

If something here looks wrong, **fix the source of truth** (and update this skill + `design.md`), don't bypass it locally.

## Colour palette

All colours come from `AppColors` (`lib/core/theme/app_theme.dart`). **Never hard-code a hex value** unless you're authoring a brand-new gradient pair (see "Mode-card gradients" below). Swatches `xxxSwatch.shade100..800` exist for primary / surface / accent / success / error if you need a tint.

### Core palette

| Token | Hex | Use |
|---|---|---|
| `AppColors.background` | `#1F4DA0` | `Scaffold.backgroundColor` (already set globally — usually you don't touch it) |
| `AppColors.surface` | `#2C5FB5` | Card / chip / list-tile background. The default "raised on the sky" surface. Also the `StandardDialog` body color. |
| `AppColors.surfaceLight` | `#3568BD` | Slightly lighter surface variant — rare |
| `AppColors.primary` | `#3F75CB` | Main brand. `PrimaryButton`, active state, focus ring, recap quiz |
| `AppColors.accent` | `#f26c0d` | **Reserved.** `AccentButton` (orange CTAs), Miles indicator, selected check, FAB. Don't sprinkle. |
| `AppColors.success` | `#10b981` | Correct answer, miles icon, gain |
| `AppColors.error` | `#ef4444` | Wrong answer, validation error, in-game red feedback |
| `AppColors.destructive` | `#C24430` | Irreversible user actions (delete account, danger-zone titles/icons). Pure `error` is the optical complement of royal-blue and vibrates — use this warm brick on any "destructive" UI sitting on a blue surface. |
| `AppColors.textPrimary` | `Colors.white` | Body text on dark surfaces |
| `AppColors.textSecondary` | `#a7c8f4` | Subtitles, captions, muted text on dark |
| `AppColors.textDisabled` | `#94a3b8` | Disabled / hint text |

### Semantic tokens (since 2026-05 consolidation)

| Token | Hex | Use |
|---|---|---|
| `AppColors.medalSilver` | `#C0C0C0` | 2nd place podium |
| `AppColors.medalBronze` | `#CD7F32` | 3rd place podium |
| `AppColors.tierEasy` | `#4CAF50` (vert) | DifficultyLevel.beginner, HintPack.small |
| `AppColors.tierMedium` | `#2196F3` (bleu) | DifficultyLevel.intermediate, HintPack.medium |
| `AppColors.tierHard` | `#9C27B0` (violet) | DifficultyLevel.advanced, HintPack.large |
| `AppColors.tierExpert` | `#E91E63` (rose) | DifficultyLevel.expert |
| `AppColors.highlight` | `#FFC107` (ambre) | Compteurs (badge d'indices), étoiles/sparkles, 1ère place podium |
| `AppColors.highlightContrast` | `#795548` (brun) | Texte/icône sur fond `highlight` |

The 1st-place podium uses `highlight` rather than a separate "medalGold" — pure-gold #FFD700 isn't currently needed anywhere.

### Mode-card gradients

The home page and Défi page use bespoke 2-stop linear gradients per "mode card". They're the **only** place hard-coded hexes are tolerated, and they always come in pairs:

| Mode | Stop 1 | Stop 2 |
|---|---|---|
| Aventure | `AppColors.primarySwatch.shade500` | `AppColors.primarySwatch.shade600` |
| Multijoueur | `AppColors.accentSwatch.shade400` | `AppColors.accent` |
| Défi (purple) | `#BB6BD9` | `#9B51E0` |
| Ranking / Online (teal) | `#1FC1A1` | `#1FC1A1` |
| Plus ou Moins (pink) | `#EC4899` | `#DB2777` |
| Classement (green) | `#10B981` | `#059669` |
| Disabled / coming soon | `#6B7280` | `#4B5563` |
| Hint pack — Aventurier (blue) | `#3B82F6` | `#1D4ED8` (matches hint shop `_PackGradient`) |

When adding a new mode/challenge card, pick a fresh pair from the same family (saturated mid-tone → 1 step darker, top-left to bottom-right). Don't rotate through these colours for non-mode UI. Hint-shop pack cards (`hint_shop_page.dart`) reuse the gradient family — small `#10B981/#059669`, medium `#3B82F6/#1D4ED8`, large `#BB6BD9/#9B51E0` — these count as mode-card gradients. The Défi sub-mode card gradients already in the table are the verified stops: purple `#BB6BD9/#9B51E0` (endless quiz), pink `#EC4899/#DB2777` (plus ou moins), green `#10B981/#059669` (classement/ranking).

## Colour usage & contrast (read before painting anything)

> The #1 generated-UI failure in this app is **low-contrast colour pairing** — orange/coloured text or icons on the blue surface, white tokens on a light card, accent used as a fill *and* as text. The palette is correct; the pairings drift. This section is the rule.

### The one rule that prevents 90% of drift

**`accent` (#f26c0d) is a FILL with WHITE content, OR a small icon/check on a WHITE/light surface. It is NEVER text or a large icon drawn directly on the blue `background`/`surface`.** Orange-on-blue is the exact pairing the hand-tuned screens eliminated — don't reintroduce it. A "Jouer" word in orange on a blue card is wrong; the orange goes on the `AccentButton` fill, the word stays white.

### Foreground × background pairing matrix

Pick the foreground from the row that matches your background. Anything marked FORBIDDEN fails contrast or muddies the brand.

| Background | OK foreground | FORBIDDEN foreground | Why |
|---|---|---|---|
| `background` #1F4DA0 (sky) | white / `textSecondary` #a7c8f4 / white icons | `accent` text, `primary` text, any dark text | orange/blue & blue/blue vibrate or vanish |
| `surface` #2C5FB5 (card) | white / `textSecondary` / white icons / `success`+`error` icons (feedback only) | `accent` as **text/large icon**, `textDisabled` for primary text | accent-on-surface is the drift the user removed |
| white / light card (`PickerOptionCard`) | `Colors.black`/`black87`, muted `Colors.black.withValues(alpha:.6)` or `Colors.grey.shade600`, `accent` for the selected check-circle only | `AppColors.textPrimary` (=white → invisible), `textSecondary` | textPrimary is white; it disappears on white |
| `accent` #f26c0d fill (button/chip) | white text, white icon | `accent`-adjacent oranges, black text | white is the only legible content on accent |
| `highlight` #FFC107 fill (amber chip) | `highlightContrast` #795548 (brun) | white, black, `accent` | amber needs the brown token, nothing else |
| `success`/`error`/`tier*` fills | white | the tier colour itself as text | coloured fill ⇒ white foreground, always |

### Derived rules (each maps to a real past mistake)

- **Text on a white/light surface is dark, never a Mission-Geo light token.** Use `Colors.black`, `Colors.black87`, or muted `Colors.black.withValues(alpha: 0.6)` / `Colors.grey.shade600`. `AppColors.textPrimary` is **white** — putting it on a white `PickerOptionCard` makes it vanish. (This is *not* covered by the existing "use AppColors" rule — here the correct answer is literally `Colors.black`.)
- **Coloured fill ⇒ white foreground.** Any `success`/`error`/`tier*`/`accent` used as a background means the text/icon on top is white. The single exception is `highlight`, whose on-colour is `highlightContrast` (#795548).
- **Loading spinners are white on the dark theme — never `accent`.** `CircularProgressIndicator(color: Colors.white)` (or default). An orange spinner on blue is low-contrast and off-brand.
- **Tinted icon "medallion" = ICON only, never text.** The `accent.withValues(alpha: 0.20)` square holds a full-strength `accent` *icon*. Don't put an accent **label** inside it or beside it on the blue surface.
- **Badge / chip foreground follows its fill:** transparent/surface chip ⇒ white or `textSecondary`; coloured-fill chip ⇒ white; amber chip ⇒ `highlightContrast`.
- **Two competing "primary" colours on one screen is a smell.** `accent` is reserved for the single CTA / miles / selected state. If two things are orange, one of them is decoration and is wrong — demote it to `primary` or `surface`.

### Amber family: `highlight` vs the score widget

The amber family splits into two documented uses — don't mix them up:

- **`AppColors.highlight` (#FFC107)** — hint counters, sparkles/stars, **1st-place podium**, and amber chips. Its on-colour is **`AppColors.highlightContrast`** (#795548 brun), never white/black.
- **The hero score** (`ScoreWidget`, `lib/pages/games/common/score.dart`) uses **`Colors.amberAccent`** for the number with an **orange shadow/glow** — that is the canonical score convention, NOT `highlight`. Match it when you render a big game score.

Rules:
- **Never write `Colors.amber`, `Colors.amber[300]`, or `Colors.yellow` for counters/sparkles/podium** — map those to `AppColors.highlight` (fill/icon) + `AppColors.highlightContrast` (text on it).
- The confetti palette (`[Colors.amber, Colors.orange, Colors.yellow, Colors.white, AppColors.accent]`) is the **one tolerated** raw-amber use — it's a particle spray, not a foreground/background pairing.

### Swipe / like-dislike colours = standard semantics

Positive (like) and negative (dislike) feedback use **standard, recognisable semantic colours**, not exotic ones:

- **Positive / like / gain / "up"** → `AppColors.success` (#10b981 vert).
- **Negative / dislike / loss / "down"** → `AppColors.error` (#ef4444 rouge).
- **Never** `Colors.orange`/`Colors.cyan` for like/dislike direction, and **never** raw `Colors.greenAccent`/`Colors.redAccent` where the semantic is success/error — use the tokens.
- For a soft *glow* (not a flat fill) you may use the token with `.withValues(alpha: …)`; the hue still comes from `success`/`error`.

### Activity-type colours = one named, documented set

The 8 Adventure activity types each carry a fixed accent colour (flag / capital / map / drawing / shape / coats / landmark / anthem). They form **one coherent named set** — treat them like the mode-card gradients: a closed, documented family, not per-file hexes. These will be promoted to `AppColors.activityFlag/Capital/Map/Drawing/Shape/Coats/Landmark/Anthem` tokens (tracked in `AUDIT-violations.md`); **until then they remain raw hex in `region_detail_page.dart` — do not copy that pattern into new code.** When you need an activity colour, reference it through the upcoming tokens; never invent a 9th or hard-code a fresh hex.

### Before you call a screen "consistent" (colour self-critique)

Screenshot the screen. For each coloured element ask: (1) is the foreground legible on its background per the matrix? (2) is `accent` a fill, not floating text on blue? (3) is every colour an `AppColors` token (or a documented gradient/confetti/score exception)? If any answer is "no", fix before declaring done. (Mirrors the visual self-critique reflex.)

## Typography

**Two fonts, two roles.**

- **DynaPuff** (`kDisplayFontFamily`) — display : titres, scores, CTAs, en-têtes de carte. La police "ballon".
- **Quicksand** (`kBodyFontFamily`) — body : paragraphes, sous-titres, chiffres inline, badges. **Réglée comme police par défaut du thème**, donc les styles body n'ont pas à répéter `fontFamily`.

Polices `Jungle Adventurer` et `Luckiest Guy` réservées splash / branding moments — pas d'utilisation body.

### `AppText.*` tokens — la source unique

**Tout `Text(...)` lit un token de `lib/core/theme/typography.dart`.** Jamais de `TextStyle(fontSize: X, fontWeight: Y)` inline. Si le token n'expose pas un attribut (color, height, shadows), passer par `.copyWith(...)`.

```dart
// ✅ Bien
Text('Bonjour', style: AppText.hero.copyWith(color: AppColors.textPrimary))
Text('Jouer',   style: AppText.ctaLabel.copyWith(color: Colors.white))
Text('26 %',    style: AppText.stat.copyWith(color: AppColors.accent))

// ❌ Mal
Text('Bonjour', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white))
```

| Token | Police | Taille / poids | Quand |
|---|---|---|---|
| `AppText.hero` | DynaPuff | 28 bold | Salutation, intro hero de page accueil |
| `AppText.pageTitle` | DynaPuff | 32 bold | Gros titre dans le body (« Mes régions ») |
| `AppText.section` | DynaPuff | 22 bold | En-tête de section (« Défis permanents ») |
| `AppText.cardTitle` | DynaPuff | 20 bold | Titre de carte mode / défi / région |
| `AppText.cardTitleSmall` | DynaPuff | 18 bold | Carte compacte / longs noms (« Europe de l'Ouest et du Nord ») |
| `AppText.cardTitleInline` | DynaPuff | 16 bold | Petit titre inline |
| `AppText.appBarTitle` | DynaPuff | 16 w600 | Titre AppBar — responsive: `appBarTitle.copyWith(fontSize: layout.fontSize.subtitle)` |
| `AppText.ctaLabel` | DynaPuff | 20 w600 ls0.5 | Label `PrimaryButton` |
| `AppText.ctaLabelMedium` | DynaPuff | 16 w600 ls0.5 | Bouton secondaire (« Débloquer », « Réessayer ») |
| `AppText.ctaLabelSmall` | DynaPuff | 14 bold ls0.5 | Pill inline / `AccentButton` par défaut |
| `AppText.score` | DynaPuff | 48 bold | `ScoreWidget`, gros chiffres |
| `AppText.feedback` | DynaPuff | 22 bold | « Bravo ! », « +10 », « Perdu » |
| `AppText.dialogTitle` | DynaPuff | 20 bold | Titre `StandardDialog` |
| `AppText.body` | Quicksand | 16 r | Paragraphes |
| `AppText.bodyBold` | Quicksand | 16 b | Emphase dans un paragraphe |
| `AppText.subtitle` | Quicksand | 13 r | Sous-titre sous un `cardTitle` |
| `AppText.subtitleBold` | Quicksand | 13 w600 | Sous-titre étiquette |
| `AppText.caption` | Quicksand | 12 r | Footer, mention, légende |
| `AppText.captionBold` | Quicksand | 12 w600 | Petit label |
| `AppText.stat` | Quicksand | 14 w600 | Chiffre inline (« 26 % », « 1500 mi ») |
| `AppText.statLarge` | Quicksand | 26 bold | Stat valeur dans une tile |
| `AppText.badge` | Quicksand | 11 w600 ls1.1 | Chip / pill (« EN COURS ») — letter-spacing 1.1 conçu pour all-caps |
| `AppText.placeholder` | Quicksand | 14 r | Placeholder de champ |

**Si aucun token ne colle**, ne pas improviser inline → **ajoute un nouveau token dans `typography.dart`** et documente-le ici.

## Responsive layout (3-tier — phone / 7" / 10")

The app ships on phones **and tablets** (portrait only). Since 2026-05 the design system is built around three **window size classes** (Material 3 width-based breakpoints) — not "phone vs tablet binary". Every UI you author must work on all three tiers.

### The 3 tiers

| Class | Width (dp) | Target device | Layout intent |
|---|---|---|---|
| `WindowSizeClass.compact` | < 600 | Phones | Original phone layout — the source of truth; **never regress** to fix tablets |
| `WindowSizeClass.medium` | 600 – 839 | 7" tablets (portrait) | Same shape as phone, slightly larger; **clamp content to ~520 dp** so cards don't pancake-stretch |
| `WindowSizeClass.expanded` | ≥ 840 | 10" tablets (portrait), large foldables | Re-architect: 2-col grids, asymmetric hero rows, clamp content to ~640–720 dp |

Phones own the design — tablets adapt **from** the phone layout, not the other way around.

### The two primitives

Both live in `lib/core/theme/responsive.dart`.

#### 1. `context.windowSizeValue<T>(compact:, medium:, expanded:)` — per-widget scaling

```dart
final flagSize = context.windowSizeValue<double>(
  compact: 180,
  medium: 240,
  expanded: 320,
);

final keyboard = context.windowSizeValue(
  compact: _phone, medium: _tabletMedium, expanded: _tabletExpanded);
```

- `medium` is optional — if omitted, Medium falls back to `expanded`. Provide it whenever the value should sit between phone and 10" (it almost always should).
- **The widget reads its own context** — do NOT pass `iconSize:` / `padding:` overrides from call sites. The card / button / keyboard scales itself in its `build`. See `_GameModeCard` (`lib/pages/home/page.dart:617`) and `_KeyboardSizes.of()` (`lib/pages/games/typing/widgets/keyboard.dart:64`) as the reference patterns.
- Also available as discrete booleans: `context.isCompactWindow` / `context.isMediumWindow` / `context.isExpandedWindow`. Use these for layout *shape* switches (a row vs a grid), not for picking sizes — sizes go through `windowSizeValue` for ternary clarity.

#### 2. `AdaptivePageBody` — page-level width clamp

Wrap the body of every menu / setup / list page in this. Phones get raw width, tablets get centred clamped width.

```dart
body: SafeArea(
  child: SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
    child: AdaptivePageBody(
      expandedMaxWidth: 900,                                   // override 720 default if needed
      expandedBuilder: (context) => _buildExpandedLayout(...), // optional: bespoke 10" layout
      child: _buildCompactLayout(...),                          // fallback for Compact + Medium
    ),
  ),
),
```

Defaults: `mediumMaxWidth: 520`, `expandedMaxWidth: 720`. Override only when the page hosts a specific layout (e.g. Home hero uses 900). If the Expanded layout is fundamentally different (2×2 grid vs vertical column), pass `expandedBuilder:` — otherwise the same `child` is just centred and clamped.

**Currently wired into:** home, all 5 mode menu pages (Multijoueur / Défi / Online / Profile / hint shop), all 3 défi setup pages, duel setup, create room, online lobby. Audit `grep -rn "AdaptivePageBody(" lib/pages/` before adding a new menu page.

### Rules

1. **Phone (Compact) is the baseline — never regress phone to gain tablet.** Capture a phone screenshot **before** you start, capture after every change. If phone moves, you went too far.
2. **Scale is read from `context`, not passed from the call site.** A widget that needs different sizes on tablet computes them inside its `build` via `windowSizeValue`. Call sites stay clean (`_GameModeCard(title: ..., subtitle: ...)`, not `_GameModeCard(title: ..., iconSize: 72)`).
3. **`medium` is between phone and expanded — not a phone duplicate, not an expanded duplicate.** Picking `compact: 180, medium: 240, expanded: 320` should give a continuous progression. If you find yourself writing `medium: 180` or `medium: 320`, either the breakpoint is wrong for that widget (drop to 2 tiers) or you're missing a useful intermediate.
4. **Reposition, don't invent.** When 10" leaves a vertical void, the answer is NOT to add a new "stats strip" or filler content. Re-architect the existing material into a 2-column grid, an asymmetric hero, or a wider clamp. **The 7"/10" layout must show the same information as phone**, just better arranged.
5. **One row, not pancake-stretch.** A row of 3 thumbnails on phone usually becomes a row of 5 on tablet (e.g. classement game), not 3 stretched to 1200 dp. A `Center` + `ConstrainedBox(maxWidth: 640)` is almost always the right answer for game canvases on Expanded.
6. **For game canvases, keep the cap shared across phases.** If `playing` and `result` views render at different widths the user sees a horizontal jump on validate. Put the `Center + ConstrainedBox` *above* the phase switch (see `classement_game_page.dart:137`).
7. **Test on all three tiers before shipping.** AVDs `mission_geo_phone` (Pixel 7), `mission_geo_tablet7` (Nexus 7 2013, ~600 dp), `mission_geo_tablet10` (Pixel C, ~900 dp). The `visual-validation-android` skill covers the workflow — claim one pool port and swap AVDs on it (`mg_swap_avd`) to walk the three tiers.

### What scales (reference values used in the 3-tier rollout)

These are the values picked during the 2026-05 tablet rollout — use them as the calibration anchor, don't re-invent ratios per widget.

| Widget / surface | Compact | Medium (7") | Expanded (10") | File |
|---|---|---|---|---|
| `AdaptivePageBody` clamp | raw | 520 dp | 720 dp (or page-specific) | `responsive.dart` |
| Game canvas cap (typing) | full | 460 | 520 | `typing/game.dart` |
| Game canvas cap (drawing) | full | 480 | 560 | `drawing/game.dart` |
| Game canvas cap (choosing / inverted) | full | 540 | 640 | `choosing/game.dart` |
| Game canvas cap (classement) | full | 540 | 640 | `classement_game_page.dart` |
| Plus ou Moins flag size | 180 | 240 | 320 | `plus_ou_moins_game_page.dart` |
| ELO swipe flag (portrait) | 160 | 220 | 280 | `swipe/game.dart` |
| Typing keyboard key (W × H, font) | 36×46 / 20 | 50×62 / 25 | 64×76 / 30 | `typing/widgets/keyboard.dart` |
| Typing chips carousel height / padding / radius | 44 | 52 | 60 | `typing/widgets/carousel.dart` |
| Classement ranking slot height | 64 | 76 | 88 | `classement/widgets/ranking_slot.dart` |
| Classement number cell | 36 | 46 | 56 | same |
| Classement inner flag | 40 | 52 | 60 | same |
| Country card flag | 60 | 72 | 88 | `classement/widgets/country_card.dart` |
| Round-stat header label / subtitle / padding | 22 / 12 / 12 | 27 / 14 / 14 | 32 / 16 / 16 | `classement/widgets/round_stat_header.dart` |
| Choosing question header media upper bound | 220 | 290 | 360 | `choosing/widgets/question_header.dart` |
| Flag ELO podium socles (h1/h2/h3) | 130/100/80 | 170/130/100 | 210/160/130 | `favorite_flags/ranking.dart` |
| Flag ELO podium flags (rank 1) | 100 | 130 | 160 | same |
| Flag ELO podium medals | 48 / 36 | 60 / 48 | 72 / 56 | same |
| Flag ELO list horizontal padding | 48 | 60 | 130 | same |
| Home `_GameModeCard` icon | 56 | 64 | 72 | `home/page.dart` |
| Home `_GameModeCard` padding | 16 | 20 | 24 | same |
| Home `_GameModeCard` `cardTitle` font | 20 | 22 | 26 | same |
| Home `_GameModeCard` height | 180 | 210 | 240 | same |

If the widget you're touching isn't in the table, pick values that interpolate smoothly between the closest two analogous rows.

### Layout-shape switches (Expanded only)

These re-architect content, they don't just resize it. Each lives behind `context.isExpandedWindow`:

- **Home**: asymmetric Aventure hero (intro + EN COURS resume side by side) + 3-col row Multi/Défis/Ranking. `home/page.dart:114` (`_buildExpandedLayout`).
- **Région detail**: 4 difficulty sections in a 2×2 grid via `IntrinsicHeight + Row(Expanded, Expanded)`. `region_detail_page.dart:156`.
- **Aventure home — Mes régions**: 2-col grid via `SliverGridDelegateWithMaxCrossAxisExtent`, unlock card in-grid. `widgets/region_carousel.dart`.
- **Activity flag grid**: 2/3/4 cols via `SliverGridDelegateWithMaxCrossAxisExtent` (not a `windowSizeValue` ternary — the delegate already adapts).
- **Classement game**: unplaced cards single row of 5 (instead of 3+2) on **both** Medium and Expanded — required to avoid vertical overflow on 7".

Use `context.isExpandedWindow` for the *shape switch*, then continue scaling sizes inside each branch with `windowSizeValue`. Don't branch on `isExpandedWindow` for things that should just be larger — that's what `windowSizeValue` is for.

### Legacy responsive helpers (still valid)

`Layout` / `layoutProvider` / `LayoutRowColumn` / `LayoutVisibility` / `FontSizes` continue to work for orientation-aware switches (the few places where landscape behaviour differs). For new tablet work, **always prefer `WindowSizeClass`** — the `Layout` enum collapses 7" and 10" into the same `tabletPortrait` bucket and can't express the 3-tier progression.

## Spacing & radius (the canonical values)

- **Padding :** `EdgeInsets.all(16)`, `all(20)`, `all(24)`, `all(12)`. Symmetric : `symmetric(horizontal: 16, vertical: 12)`, `symmetric(horizontal: 12, vertical: 6)` pour chips.
- **Inter-element gap :** `SizedBox(height/width: 8 / 12 / 16 / 24)`. `4` pour rows serrées, `32`/`40` entre sections top-level.
- **Border radius :**
  - **`8`** — Material inputs/small buttons (theme defaults). Rarement utilisé hors thème.
  - **`12`** — Inputs, chips, "tinted icon medallions".
  - **`14`** — `PickerOptionCard`.
  - **`16`** — Default cards & `PrimaryButton` / `SecondaryButton` / `AccentButton` quand radius personnalisé.
  - **`20`** — Hero cards (mode cards, dialogs, badge sheet).
  - **`25`** — `AccentButton` par défaut (pill).
- **Hero card height :** `180` square mode cards, `120` row challenge, `260` region carousel.
- **Avatar size :** `48` (app bar), `120` (profile), `64` (badge).
- **Icon sizes :** `20` (`AccentButton` default), `22` (badges), `24` (default), `26` (PickerOptionCard), `28` (`PrimaryButton`), `32` (hero card), `56` (very large card).
- **Tinted icon "medallion"** (carré coloré avec icon) : bg `accent.withValues(alpha: 0.20)`, icon `accent` pleine, radius 12, padding 8–10.

## Components — the closed canonical set

> Before building a custom widget, scan `lib/pages/widgets/components/`, `lib/pages/games/common/`, and `lib/pages/modes/<mode>/widgets/`. The most common reason a screen "feels off" is that it's reimplementing a component that already exists.

### App bars

- **`MissionGeoAppBar`** — glass app bar avec backdrop blur. Pour game / mode pages. Combine avec `extendBodyBehindAppBar: true` et padde le body par `kAppBarHeight + topInset + 20`.
- **`TransparentAppBar`** — version legacy avec `MilesBanner` action par défaut. Aventure home, profile, Défi home, Multijoueur menu. Pass `actions: const []` pour drop le miles banner; pass `hideBackButton: true` sur top-level pages.
- **`GameBackButton`** — floating circular glass back button pour fullscreen game canvases (drawing, searching). Pin dans un `Stack`, jamais au-dessus d'un app bar.

Never instantiate a bare `AppBar()` in a feature screen.

### Buttons — 4 canonical components

The button surface is closed. **Every primary CTA must use one of these.** Inline `Container` with `boxShadow` for a button is a design-system violation.

#### 1. `PrimaryButton` — primary blue CTA

- Pill (radius 16), `AppColors.primary` fill, soft black shadow (blur 8).
- Icon **leading** (size 28, white), label `AppText.ctaLabel` (white), padding 16 all.
- Optional `color:` override (e.g. drawing game "Pass" uses `PrimaryButton(color: AppColors.primary)` for the canonical blue, but the param accepts variants).
- `enabled: false` → fill alpha 0.5 + no shadow + non-tappable.
- **Used as the bottom CTA of a screen.**

#### 2. `AccentButton` — orange CTA with depth shadow

- Default pill (radius 25), `AppColors.accent` fill, **hard depth shadow** (`blurRadius: 0`, `offset: Offset(0, 4)`, color `AppColors.accentSwatch.shade700`). The neubrutalism recipe.
- **Icon leading by default** (`iconLeading: true`), size 20, white.
- Label `AppText.ctaLabelSmall` by default (override via `labelStyle:`).
- Convention: **sentence case label** ("Jouer", "Valider", "Débloquer pour 1500"), NEVER uppercase.
- Params : `enabled`, `loading` (replaces icon with spinner), `fullWidth`, `borderRadius` (override 25 → 16 for wide cards), `padding`, `iconColor`, `semanticLabel`, `disabledStyle` (`surface` default vs `dimmed` for opacity-based disable).
- **Used for every primary orange CTA** : "Jouer" région, "Commencer" défi, "Débloquer avec une pub", "Copier le lien", "Continuer" online, "Prêt !" duel, "Rejouer" partout, etc.

#### 3. `AccentCircleButton` — round variant

- Circle (default size 56), same `accent` fill + hard depth shadow.
- Arbitrary `child` Widget (typically `Icon`).
- Used for the in-game hint FAB and the anthem play/pause button.

#### 4. `SecondaryButton` — outlined ghost

- Same dimensions as `PrimaryButton` (padding all(16), radius 16, icon 28, label `ctaLabel`).
- Transparent fill, 1.5 px border `AppColors.textSecondary`, white text.
- Optional leading icon.
- **Used as the secondary action paired with `PrimaryButton`** (e.g. game-over `[Rejouer (Main)] + [Retour (Secondary)]`, online lobby `[Créer une partie] + [Rejoindre par code]`).

#### 5. `MenuButton` — list nav

- Full-width rounded rectangle (radius 16), `AppColors.surface` fill.
- **Left vertical accent bar** 6px wide in `AppColors.primary` (or `AppColors.accent` if `isSpecial: true`).
- Icon left, title (`AppText.ctaLabel`), optional subtitle (`AppText.caption`), chevron-right.
- **Used in vertical lists on menu pages** (Multijoueur menu, etc.).

### Closed: Material buttons fallback

Material `ElevatedButton`, `OutlinedButton`, `TextButton` are tolerated **only** when wrapped inside something already pre-styled (e.g. some legacy contexts inside a TextField label, the `_LanguageDialog`). They are **NEVER** the right choice for a primary CTA, a secondary action, or a list nav. Use `PrimaryButton`/`SecondaryButton`/`AccentButton`/`MenuButton` instead.

### CTA conventions (mandatory)

- **Icon position: always leading** (left). Default for `AccentButton`. Default order in `PrimaryButton` and `SecondaryButton` and `MenuButton`. Don't put the icon trailing unless you have an extremely specific narrative reason.
- **Label casing: always sentence case** (or natural sentence punctuation). "Jouer", "Débloquer avec une pub", "Prêt !", "Choisir cette région". **Never** uppercase ("JOUER", "PRÊT !"). DynaPuff already gives display weight without screaming.
  - Exception: chip/badge labels using `AppText.badge` (letter-spacing 1.1) **stay** uppercase (`EN COURS`, `TERMINÉ`, `PUBLIC`, `HÔTE DE SESSION`). The letter-spacing is designed for caps.

When you migrate a button: if the i18n key is named `*Upper` (e.g. `playUpper`, `backUpper`), rename to a sentence-case key, update all 4 locale files, run `dart run slang`.

### Cards

- **Surface card** — radius 16, fill `AppColors.surface`, padding 16, shadow `0 2px 8px rgba(0,0,0,0.08)`.
- **Gradient mode card** — radius 20, gradient fill (§Mode-card gradients), shadow `0 4px 16px rgba(0,0,0,0.3)`. Pattern : icon top-left + title + subtitle. Used on home (`_AdventureCardShell`, `_GameModeCard`), Défi home (`_ChallengeCard`), daily mission banner, hint shop pack cards. **No shared widget for this yet** — each call site reimplements the gradient + radius + shadow combo; if you add a new mode card, copy from the closest existing pattern. Foreground is always **white**: icon white (32–56), title `AppText.cardTitle` white, subtitle `AppText.subtitle` white at alpha 0.9. Never tint the title/icon to the gradient hue — white-on-gradient is the contract.
- **`PickerOptionCard`** — `lib/pages/widgets/components/picker_option_card.dart`. White card pour bottom-sheet pickers. `Row` icon leading + title + (optional subtitle) + check-circle accent quand selected. Param `dense: true` pour padding plus serré (12/8) + icon 22 (vs 14/12 + 26 par défaut). Animated container + soft black shadow.

### Dialogs

- **`StandardDialog` (confirm / message)** — surface card (`AppColors.surface`), radius 20.
  - Title `AppText.dialogTitle` (white, centered).
  - Body : `Text` or custom widget. Default text color `AppColors.textPrimary`.
  - Footer : two side-by-side buttons. **Confirm** = `PrimaryButton` (blue, `icon: null` for a label-only fill button). **Cancel** = `SecondaryButton` (outlined ghost). Same canonical pair as game-over screens. Order in the Row : confirm left, cancel right.
  - Params: `title`, `content`, `cancelText`, `confirmText`, `onCancel`, `onConfirm`, `confirmEnabled` (dims the confirm button when content is incomplete — e.g. 6-digit code not yet typed).
  - Helpers : `StandardDialog.show(...)` (texte), `StandardDialog.showWithWidget(...)` (custom content).
- **Picker dialog (langues, avatars)** — same surface card, vertical list with divider, selected row marked by `Icons.check_circle` in `AppColors.accent`. See `_LanguageDialog` in `language_button.dart`.
- **Picker bottom sheet** (e.g. difficulty, statistic) — `showModalBottomSheet` with `backgroundColor: AppColors.background`, `showDragHandle: true`, title `AppText.section`. Each option is a **`PickerOptionCard`**. Use `DraggableScrollableSheet` for content scrolling.
- **Celebration / achievement bottom sheet** — modal from bottom, dark `AppColors.background` body, coloured border + glow matching the level, gradient header. Mimic `BadgeUnlockSheet`.

Never instantiate a bare `AlertDialog`.

### Backgrounds

The scaffold is `AppColors.background`. For "marquee" pages (home, mode menus) wrap content in `CloudBackground` (or `AnimatedCloudBackground` for splash / hero screens). Always pass `IgnorePointer`-friendly content and don't add a second background colour underneath.

### Game scaffolds

For any screen that *is* a game: use `GameScaffold` (`pages/games/common/game_scaffold.dart`) which wraps `GameWrapper` (blocks Android back) and a centered `CircularProgressIndicator` loading view. Score appears via `ScoreWidget` in a `Stack` (top: 8, right: 16). Right/wrong feedback uses `GameFeedbackOverlay` with one of the three `FeedbackStyle` variants. `GameScaffold` already wraps its bottom content in `SystemBottomSafeArea` (`lib/core/theme/system_insets.dart`, pads only for a tappable 3-button nav bar). Any new root fullscreen page built outside `GameScaffold` must wrap its own bottom content in `SystemBottomSafeArea`.

### Locale-aware text

Every user-visible string goes through `t.namespace.key` from `lib/i18n/strings.g.dart` (see CLAUDE.md "Internationalisation"). Country names always go through `country.localizedNom`. Hard-coding French strings in a widget is a design-system violation as much as a translation one.

## Layout patterns

### Standard "menu" page

```
Scaffold (extendBodyBehindAppBar: true, scaffoldBackgroundColor inherited)
└── appBar: TransparentAppBar(title: t.x.title, actions: const [])  // or MissionGeoAppBar
└── body: SingleChildScrollView OR GridView.builder
    padding: EdgeInsets.only(
      left: 20, right: 20,
      top: kAppBarHeight + MediaQuery.of(context).padding.top + 20,
      bottom: 20,
    )
    child: Column(crossAxisAlignment: .start, children: [
      Text(sectionHeader, AppText.section)
      SizedBox(height: 12)
      ...cards
      SizedBox(height: 32)   // between sections
    ])
```

The `top` padding includes `kAppBarHeight + topInset + 20` because `extendBodyBehindAppBar` lets the body slide under the blur. **Forgetting this is the #1 cause of "title clipped under the AppBar"**.

### Game-over page (recurring pattern)

A primary action paired with a secondary on the same row, full-width Expandeds:

```dart
Row(children: [
  Expanded(child: PrimaryButton(text: t.common.replay, icon: Icons.replay, onTap: ...)),
  const SizedBox(width: 16),
  Expanded(child: SecondaryButton(text: t.common.back, icon: Icons.arrow_back, onTap: ...)),
])
```

### Animations

- **Reveal / score / feedback :** `TweenSequence` `easeOut → elasticOut`, total ~600 ms.
- **Counter pulse :** Scale `1.0 → 1.2 → 1.0` over 500 ms `Curves.easeInOut`.
- **Switch / number change :** `AnimatedSwitcher(duration: 300ms)` fade + slide-up `Offset(0, 0.5) → Offset.zero`.
- **Cloud drift :** linear curve, reverse-repeating, ~4 s.
- **Confetti :** `ConfettiController` star path, palette `[amber, orange, yellow, white, AppColors.accent]`. Real wins only.

## Quick reference — the cheat sheet

| Need | Use |
|---|---|
| Page background | Already `AppColors.background` via theme — don't override |
| Top app bar | `MissionGeoAppBar` (game/mode page) or `TransparentAppBar` (menu page) |
| Primary blue CTA | `PrimaryButton` |
| Primary orange CTA | `AccentButton` (depth shadow) |
| Round orange button | `AccentCircleButton` |
| Secondary action (paired with Main/Accent) | `SecondaryButton` |
| List of nav options | `MenuButton` |
| Picker bottom sheet option | `PickerOptionCard` (set `dense:true` in grids) |
| Confirm/message dialog | `StandardDialog.show(...)` |
| Custom-body dialog | `StandardDialog(...)` direct (use `confirmEnabled:` for validation gating) |
| Picker dialog | Mimic `_LanguageDialog` |
| Celebration bottom sheet | Mimic `BadgeUnlockSheet` |
| Hero / mode tile | Gradient `Container`, radius 20, shadow 0.3 (see `_GameModeCard` in `home/page.dart`) |
| Surface card | `Container` color `AppColors.surface`, radius 16, shadow 0.08 black |
| Loading | Centred `CircularProgressIndicator` (white on dark) |
| Page title (body) | `AppText.pageTitle.copyWith(color: Colors.white)` |
| Section header | `AppText.section.copyWith(color: AppColors.textPrimary)` |
| Card title | `AppText.cardTitle` (`cardTitleSmall` si carte étroite) |
| CTA label | `AppText.ctaLabel` / `ctaLabelMedium` / `ctaLabelSmall` |
| Score / chiffre hero | `AppText.score.copyWith(color: Colors.amberAccent, shadows: [black blur16, orange blur8])` — per the canonical `ScoreWidget`. **Not** `highlight` — `highlight` is for counters/sparkles/podium, see below |
| Counter / sparkle / podium 1st (amber) | `AppColors.highlight` (fill/icon) + `AppColors.highlightContrast` (text on it) |
| Body text | `AppText.body` (Quicksand) ou simplement `Text('...')` |
| Subtitle on dark | `AppText.subtitle.copyWith(color: AppColors.textSecondary)` |
| Stat inline | `AppText.stat.copyWith(color: ...)` |
| Badge / chip | `AppText.badge.copyWith(color: ...)` (letter-spacing 1.1, can stay uppercase) |
| Icon on dark | `color: AppColors.textPrimary, size: 24` |
| Spacing | `SizedBox(height: 8 / 12 / 16 / 24)`, sections `32 / 40` |
| Padding inside card | `EdgeInsets.all(16)` (or 20 for hero) |
| Strings | `t.namespace.key` (or `country.localizedNom`) — never hard-code FR |
| Podium 1st / 2e / 3e | `highlight` / `medalSilver` / `medalBronze` |
| Difficulty/tier colour | `tierEasy` / `tierMedium` / `tierHard` / `tierExpert` |
| Per-widget tablet scaling | `context.windowSizeValue<T>(compact:, medium:, expanded:)` — read inside the widget's `build` |
| Layout-shape switch on 10" | `context.isExpandedWindow` (use for grid-vs-column, not for sizes) |
| Clamp page body on tablet | Wrap body in `AdaptivePageBody(child: ...)` (defaults: 520 dp Medium, 720 dp Expanded) |
| Bespoke 10" layout | `AdaptivePageBody(expandedBuilder: (ctx) => ..., child: phoneLayout)` |
| Game canvas cap | `Center + ConstrainedBox(maxWidth: context.windowSizeValue(compact: infinity, medium: 540, expanded: 640))` — placed **above** the phase switch |

## Common mistakes

| Symptom | Cause | Fix |
|---|---|---|
| Page suddenly looks Material 3 default | Imported defaults, didn't import `AppColors` | Add `AppColors` import + re-derive colours from the palette |
| Inline `Container` orange + soft black shadow for a CTA | Reinvented `AccentButton` | Replace with `AccentButton` |
| Inline `Container` blue + soft shadow for a CTA | Reinvented `PrimaryButton` | Replace with `PrimaryButton` |
| `OutlinedButton.icon` for a "secondary action" | Reinvented `SecondaryButton` | Replace with `SecondaryButton` |
| `ElevatedButton` for "back to home" / "join" | Should use canonical pair | `PrimaryButton` (primary) + `SecondaryButton` (secondary) |
| `.toUpperCase()` on a CTA label | Skipped the sentence-case convention | Drop `.toUpperCase()`, rename i18n key from `*Upper` if applicable |
| Icon trailing on a button | Default is leading | Set `iconLeading: true` (it's the default), or remove the explicit `false` |
| Texte qui devrait crier rendu en Quicksand fine | Inline `TextStyle` sans family | Use `AppText.hero/section/cardTitle/ctaLabel/score` |
| Texte body apparemment DynaPuff | Used display token where body needed | Switch to `AppText.body/subtitle/caption/stat` |
| Page title clipped under blur app bar | Missing top padding | Pad body top by `kAppBarHeight + topInset + 20` |
| Bare `AlertDialog` | Skipped `StandardDialog` | Replace with `StandardDialog.show(...)` |
| Two competing "primary" colours on one screen | Painted something orange that isn't a CTA | Reserve `accent` for CTAs / miles / selected. Use `primary` for normal actions |
| Hard-coded `Color(0xFF...)` outside mode-card gradient | Bypassed `AppColors` | Map to closest token; if none fits, add new token first |
| `Colors.green` / `Colors.red` direct | Should be semantic | `AppColors.success` / `AppColors.error` |
| `Colors.amber` for hint counter / podium 1st / sparkle | Should be the semantic token | `AppColors.highlight` |
| `accent` text or large icon on a blue surface/background | Used the CTA colour as foreground | `accent` is a fill (white content) or a small check on a light card. Keep the word white |
| `AppColors.textPrimary` (white) text on a white `PickerOptionCard` | Used the dark-theme text token on a light surface | Use `Colors.black`/`black87` or muted `Colors.black.withValues(alpha:.6)` |
| `CircularProgressIndicator(color: AppColors.accent)` | Orange spinner on blue | White spinner: `color: Colors.white` (or default) |
| `Colors.orange`/`Colors.cyan` for swipe like/dislike | Exotic non-semantic colours | `AppColors.success` (like) / `AppColors.error` (dislike) |
| `Colors.greenAccent`/`Colors.redAccent` for up/down delta | Raw Material where semantic is success/error | `AppColors.success` / `AppColors.error` |
| `Colors.amber` + `Colors.brown` for a "completed" chip | Ad-hoc reimplementation of the highlight pair | `AppColors.highlight` fill/icon + `AppColors.highlightContrast` text |
| Raw hex for an Adventure activity colour | Bypassed the activity-colour set | Reference the activity tokens (see §"Colour usage & contrast"); never a fresh hex |
| Hard-coded French in `Text(...)` | Skipped i18n | Add key to 4 `.i18n.json` + use `t.namespace.key` |
| Picker bottom sheet replicating white card + check inline | Reinvented `PickerOptionCard` | Use `PickerOptionCard` |
| `Colors.black.withValues(alpha: 0.5)` shadow | Arbitrary value | Surface cards: `0.08`. Hero gradient cards: `0.3` |
| Two FABs with same `heroTag` crash | Forgot to set distinct `heroTag` | Each FAB needs unique `heroTag` (`'back-button'` is reserved) |
| Animation feels "static" | Stopped at one curve, no overshoot | `TweenSequence` `easeOut → elasticOut`, ~600 ms |
| Cards pancake-stretched to 1700 dp on 10" tablet | Page body has no width clamp | Wrap body in `AdaptivePageBody` (or `Center + ConstrainedBox(maxWidth: 640)`) |
| Phone layout regressed to fix tablet | Used `windowSizeValue` to change compact value | **Compact stays untouched.** Re-derive only `medium:` and `expanded:` |
| Added a filler "stats strip" to fill 10" void | Inventing new content instead of repositioning | Re-architect: 2-col grid, asymmetric hero, single-row of N. The Expanded layout shows the **same** information |
| Tablet sizes set per call site (`_GameModeCard(iconSize: 72)`) | Bypassed the in-widget scaling pattern | Move the `windowSizeValue` ternary **inside** the widget's `build`. Call sites stay free of responsive params |
| Horizontal jump between game phases on validate | `Center + ConstrainedBox` is inside each phase branch | Lift the clamp **above** the phase switch so both phases share the same width (see `classement_game_page.dart`) |
| 7" tablet falls through to phone layout | Used only `compact:` + `expanded:` and forgot `medium:` | Provide an explicit `medium:` value (interpolated between phone and 10") |
| Using `Layout.tabletPortrait` for new tablet work | `Layout` enum collapses 7" and 10" into one bucket | Use `WindowSizeClass` / `context.windowSizeValue` instead |

## Red flags — STOP and reconcile with the design system

- "I'll just hard-code this colour for now" → **no.** Pick from `AppColors`, or talk to user about adding a token.
- "It's a one-off dialog so `AlertDialog` is fine" → **no.** Use `StandardDialog`.
- "I need a different font for this title" → **no.** Use an `AppText.*` token.
- "I'll inline a `TextStyle(fontSize: 24)` just for this widget" → **no.** Add a token in `typography.dart`.
- "I'll just use Material's `FilledButton`" → **no** for any primary CTA. Use `PrimaryButton`/`AccentButton`/`SecondaryButton`/`MenuButton`.
- "This orange container with a soft shadow is just a quick button" → **no.** Use `AccentButton`.
- "This orange label/icon on the blue card looks fine" → **no.** Orange is a fill with white content, or a check on a *light* surface. The word stays white. (The exact drift the hand-tuned screens removed.)
- "White text is the app default so it's fine here" → **check the surface.** On a white `PickerOptionCard` white text vanishes — use `Colors.black`/`black87`.
- "I'll use `Colors.amber`/`Colors.greenAccent`/`Colors.cyan`, close enough" → **no.** Map to `AppColors.highlight` / `success` / `error`. Raw Material colours are how the parallel palette crept in. (Score number is the one documented `Colors.amberAccent` exception.)
- "The label looks better in UPPERCASE" → **no.** Sentence case. DynaPuff already gives weight.
- "This is the first screen of its kind so there's no precedent" → look harder. The home / Aventure home / Défi home / Profile / Multijoueur menu cover ~95% of layout patterns.
- "I'll just check it on the phone emulator, it should be fine on tablet" → **no.** Capture all three tiers (phone + 7" + 10"). 7"/10" reveal stretch / void / scaling bugs phone alone hides.
- "I'll pass `iconSize: 72` from the parent on tablet" → **no.** Move the `windowSizeValue` ternary inside the widget. Call sites stay free of responsive params.
- "I'll regress this padding on phone to fix the 10" overflow" → **no.** Phone is the baseline. Only `medium:` / `expanded:` may change.
- About to commit a UI change without comparing to a sibling page → invoke the `visual-validation-android` skill and screenshot side-by-side.

## Check before you ship a UI change

1. Did I import `AppColors` and use tokens (not raw hex) for every colour I touched?
2. **Contrast check:** for every coloured element — is `accent` only ever a fill-with-white (or a check on a light card), never orange-on-blue? Is text on any light/white surface dark (`black`/`black87`), not white? Are like/dislike `success`/`error`, and counters/sparkles/podium `highlight`/`highlightContrast` — no raw `Colors.amber/cyan/greenAccent`? Is every spinner white? (Score number is the documented `Colors.amberAccent` exception.)
3. **Did I use one of the 4 canonical buttons** (`PrimaryButton`, `AccentButton`, `SecondaryButton`, `MenuButton`) — and NOT an inline `Container` + `boxShadow`?
4. Did I reuse `MissionGeoAppBar` / `TransparentAppBar` / `StandardDialog` / `PickerOptionCard` / `CloudBackground` instead of building parallel widgets?
5. Are my radii from `{8, 12, 14, 16, 20, 25}` and paddings multiples of 4 within `{8, 12, 16, 20, 24}`?
6. Did every CTA label go through `t.*` in **sentence case** (no `.toUpperCase()`, no `*Upper` i18n keys)?
7. Did every visible string go through `t.*` (and country names through `country.localizedNom`)?
8. Did every `Text(...)` use an `AppText.*` token (no inline `TextStyle(fontSize:...)`)?
9. **For any menu / setup / list page I added: did I wrap the body in `AdaptivePageBody` so it clamps on tablets?**
10. **For any widget whose size should change on tablet: did I push the `windowSizeValue` ternary inside the widget's `build`, with explicit `compact:` / `medium:` / `expanded:` values — not just `compact:` and `expanded:`?**
11. **Did I capture the page on all three AVDs (`mission_geo_phone`, `mission_geo_tablet7`, `mission_geo_tablet10`) and confirm phone hasn't regressed?**
12. Did I render the page on the emulator (see `visual-validation-android`) and compare with a neighbouring page?

If any answer is "no", fix it before committing.
