# Design-system colour violations — to fix later

> Generated from the 2026-05-24 colour/contrast audit. **Documentation only — no code changes here.** Each entry: file:line · what's wrong · recommended fix. Grouped by the rule it breaks. Line numbers verified against live code on 2026-05-24.

## A. Exotic like/dislike colours → standard semantics

| Location | Current | Wrong because | Fix |
|---|---|---|---|
| `lib/pages/games/swipe/game.dart:355` | `(isFirst ? Colors.orange : Colors.cyan)` glow | Exotic non-semantic; orange collides with the CTA reserve | `(isFirst ? AppColors.success : AppColors.error)` glow |
| `lib/pages/games/swipe/widgets/swipeable_flag_card.dart:189` | `(widget.isLeft ? Colors.orange : Colors.cyan)` indicator | same | `success` / `error` |
| `lib/pages/games/swipe/widgets/elo_swipe_game.dart:663-664` | `Colors.greenAccent` / `Colors.redAccent` rank delta | Raw Material where semantic is success/error | `AppColors.success` / `AppColors.error` |

## B. Raw amber/yellow → `highlight` / `highlightContrast`

| Location | Current | Fix |
|---|---|---|
| `lib/pages/games/swipe/widgets/elo_swipe_game.dart:579` | winner glow `Colors.amber.withValues(...)` | `AppColors.highlight.withValues(...)` |
| `lib/pages/games/swipe/widgets/elo_swipe_game.dart:653` | rank `Colors.amber[300]` | `AppColors.highlight` |
| `lib/pages/modes/adventure/widgets/activity_grid.dart:193,202` | completed chip `Colors.amber` fill + `Colors.amber` icon | `AppColors.highlight` fill/icon |
| `lib/pages/modes/adventure/widgets/activity_grid.dart:210` | completed chip text `Colors.brown` | `AppColors.highlightContrast` |
| `lib/pages/games/common/score.dart:148-149` | static glow `Colors.amber.withValues(...)` (RadialGradient) | `AppColors.highlight.withValues(...)` — the glow only; the score number stays amberAccent (see B-OPTIONAL) |

### B-OPTIONAL — score number unification (NOT recommended, opt-in only)

The canonical `ScoreWidget` (`lib/pages/games/common/score.dart:103`) renders the score number with `Colors.amberAccent` + orange shadow. This is the **documented convention** and is correct as-is. If a future redesign wants the whole amber family unified onto `AppColors.highlight`, the change would be `score.dart:103` `Colors.amberAccent → AppColors.highlight` and the shadows retuned. Treat as optional polish, not a violation.

## C. Activity-type colours → promote to named `AppColors` tokens

All eight are raw hex in `lib/pages/modes/adventure/region_detail_page.dart`. They are a parallel (Flat-UI) palette, undocumented and unrelated to the `tier*` set. Promote to one named set in `app_theme.dart`, mirror in `design.md` §2, then replace the hexes.

| Location | Current (raw hex) | Activity | Proposed token |
|---|---|---|---|
| `region_detail_page.dart:194` | `#3498DB` | flagTyping | `AppColors.activityFlag` |
| `region_detail_page.dart:200` | `#2ECC71` | capitalTyping | `AppColors.activityCapital` |
| `region_detail_page.dart:206` | `#E67E22` | mapPlacement | `AppColors.activityMap` |
| `region_detail_page.dart:212` | `#9B59B6` | flagDrawing | `AppColors.activityDrawing` |
| `region_detail_page.dart:218` | `#E74C3C` | shapeTyping | `AppColors.activityShape` |
| `region_detail_page.dart:224` | `#F39C12` | coatsTyping | `AppColors.activityCoats` |
| `region_detail_page.dart:230` | `#1ABC9C` | landmarkTyping | `AppColors.activityLandmark` |
| `region_detail_page.dart:236` | `#8E44AD` | anthemTyping | `AppColors.activityAnthem` |

## D. Raw hex that should map to existing tokens / be documented gradients

| Location | Current | Fix |
|---|---|---|
| `lib/pages/modes/adventure/widgets/miles_banner.dart:126` | `Color(0xFF2C3E50)` bg (dark slate) | map to `surface` / `surfaceSwatch.shade700`, or add a dedicated token |
| `lib/pages/modes/adventure/widgets/miles_banner.dart:139` | plane icon `Color(0xFFF39C12)` | should be `AppColors.accent` (miles = accent semantics) |
| `lib/pages/modes/adventure/hint_shop_page.dart:471-473` | pack gradients raw hex (`#10B981/#059669`, `#3B82F6/#1D4ED8`, `#BB6BD9/#9B51E0`) | now documented as mode-card-family gradients in SKILL.md; optionally pull from shared gradient constants |

## E. Contrast pairing risks — manual visual recheck needed (not confirmed failures)

| Location | Risk |
|---|---|
| any `PickerOptionCard` call site | confirm content text uses dark (`black`/`black87`), not `AppColors.textPrimary` (white) |
| `lib/pages/games/swipe/widgets/elo_swipe_game.dart:603` | `Colors.grey[800]` placeholder block — verify legibility on sky |
| `lib/pages/games/swipe/widgets/elo_swipe_game.dart:608` | `Colors.white54` spinner — acceptable (white family) but verify on light flag fallback |

## F. i18n `*Upper` keys surfacing in coloured chips (cross-cuts the CTA sentence-case rule)

| Location | Current | Fix |
|---|---|---|
| `lib/pages/modes/adventure/widgets/activity_grid.dart:207` | `t.adventure.completedUpper` | rename to a sentence-case key, update all 4 locale files, run `dart run slang` |
