#!/usr/bin/env bash
# check_navigation.sh — navigation scope regression guard
#
# Detects violations that cause the "blue screen on Back" bug:
#
#   TYPE A — Root route pushed/replaced without .root.push()/.root.replace()
#     Root canvases (game pages, booster album, etc.) are declared at the
#     AppRouter top level, outside MainShellRoute.children. Pushing them via a
#     tab-nested context.router.push() triggers auto_route's buildPathTo, which
#     reconstructs the full path and stacks a second MainShellRoute → corrupt
#     stack → empty scaffold visible on Back. Same failure class for a bare
#     .replace() (single-route call, same argument shape as .push()/.navigate()).
#     FIX: always use context.router.root.push()/.replace() or AppNavigator.*.
#     Note: .replaceAll() is deliberately NOT covered here — it takes a
#     List<PageRouteInfo> (`.replaceAll([Route()])`), so a route name never sits
#     directly after the opening paren and this check's argument-position regex
#     would not match it. No current call site needs it; revisit with a
#     list-aware regex (or the planned custom_lint AST check, Lot 3) if one
#     appears.
#
#   TYPE A′ — Root route reached without .root.navigate()
#     Same failure class as TYPE A but via .navigate() instead of .push().
#     FIX: always use context.router.root.navigate() (or AppNavigator.*).
#
#   TYPE B — Tab route pushed/replaced via .root.push()/.root.replace()/.root.replaceAll()
#     Tab-nested routes (HintShop, Carnet, RegionDetail, etc.) belong inside a
#     tab's StackRouter. Reaching them via .root.push()/.replace()/.replaceAll()
#     bypasses the tab shell → route lands on the root stack with no bottom bar
#     and pops back to nothing.
#     FIX: always use AppNavigator.* for cross-scope tab navigation.
#
#   TYPE B′ — Tab route pushed via the ROOT router's bare .push()
#     A tab route pushed on the router instance obtained from routerProvider
#     (a RootStackRouter) is root-level even without an explicit ".root." —
#     this is the exact shape of the original double-MainShellRoute blue-screen
#     bug (e.g. `ref.read(routerProvider).push(const CarnetRoute())`). Shape 2
#     (a local var bound to routerProvider, used later in the file) also checks
#     .navigate()/.replace()/.replaceAll() — same root-level exposure, any verb.
#     FIX: use AppNavigator.* (it resolves the correct tab's StackRouter).
#     Known gap (pre-existing, not introduced by the verb extension above):
#     shape 2 matches against a per-file, comment-stripped-but-NOT-joined view
#     (unlike TYPE A/A′/B′-shape-1, it doesn't consult JOINED_CACHE), so a
#     variable declaration or call chain split mid-statement across physical
#     lines (e.g. `final r = ref\n.read(routerProvider);`) is not recognised.
#     Confirmed present in the original .push()-only version too — candidate
#     for the Lot 3 custom_lint AST rewrite rather than a grep patch here.
#
#   TYPE C — Manual MainShellRoute(children: […]) construction outside the facade
#     Rebuilding the whole shell tree by hand (`replaceAll([MainShellRoute(
#     children: [...])])`) duplicates the exact logic AppNavigator.* centralises
#     and is the shape every past "double MainShellRoute" bug traces back to.
#     `const MainShellRoute()` with NO children (full app reset — splash,
#     onboarding, notifications deep-link) stays legal from anywhere; only the
#     children-bearing constructor is restricted.
#     FIX: use AppNavigator.rebuildShellOnTab() (or another AppNavigator.*
#     method) instead of constructing MainShellRoute(children: …) by hand.
#
# Usage:
#   bash scripts/check_navigation.sh         # exits 0 (clean) or 1 (violations)
#   bash scripts/check_navigation.sh --quiet # suppress clean confirmation
#
# Files excluded from scanning (they contain the canonical patterns):
#   lib/core/navigation/app_navigator.dart
#   lib/core/navigation/game_over_nav.dart
#   lib/core/navigation/router.dart
#   lib/core/navigation/router.gr.dart
#
# Implementation note: every check below operates on a `//`-comment-stripped
# view of the source (see SOURCE_CACHE) — a code comment that happens to
# mention "root.push(SomeRootRoute)" must never trip the guard. Each check also
# scans a line-joined view (see JOINED_CACHE) so a chain auto-formatted across
# several physical lines (e.g. `ref\n.read(routerProvider)\n.push(Route())`)
# is still matched.

set -euo pipefail

QUIET="${1:-}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$REPO_ROOT/lib"

# Routes declared at AppRouter top level (outside MainShellRoute.children).
# These MUST be reached via .root.push()/.root.navigate() or AppNavigator.* —
# never bare .push()/.navigate().
ROOT_ROUTES_ERE="(BoosterAlbumRoute|BoosterOpenRoute|CarnetPeekRoute|AdventureTypingGameRoute|AdventureDrawingGameRoute|AdventureSearchingGameRoute|EndlessQuizGameRoute|PlusOuMoinsGameRoute|ClassementGameRoute|ArcadeGameRoute|GeohunterGameRoute|DailyCountryRoute|WeeklyGeohunterGameRoute|WeeklyClassementGameRoute|WeeklyPlusOuMoinsGameRoute|DailyClassementGameRoute|DailyPlusOuMoinsGameRoute|DailyGeohunterGameRoute|DailyEndlessQuizGameRoute|DailyArcadeGameRoute|OnlineGameRoute|RankedMatchRoute|OnboardingRoute)"

# Routes declared inside MainShellRoute.children (tab-nested).
# These MUST NOT be reached via .root.push() or via the bare root router — they
# belong in a tab StackRouter. (HintShopRoute removed — the old hint shop page
# no longer exists, superseded by ShopRoute.)
TAB_ROUTES_ERE="(CarnetRoute|ShopRoute|RegionDetailRoute|ActivityCountryListRoute|AdventureHomeRoute|HomeRoute|DefiHomeRoute|EndlessQuizHomeRoute|PlusOuMoinsHomeRoute|ClassementHomeRoute|ArcadeHomeRoute|GeohunterHomeRoute|WeeklyChallengeRoute|DailyChallengeRoute|DiscoveryRoute|FlagEloSwipeRoute|FlagEloRankingRoute|RankedHomeRoute|RankedSearchingRoute|CustomGameRoute|DuelSetupRoute|CreateRoomRoute|OnlineLobbyRoute|ProfileRoute|AvatarComposerRoute|CreditsRoute|PolicyRoute|FeedbackRoute|EndlessQuizGameOverRoute|PlusOuMoinsGameOverRoute|ClassementGameOverRoute|ArcadeGameOverRoute|GeohunterGameOverRoute|DebugLauncherRoute|DebugGameWrapperRoute)"

# Files that legitimately contain the patterns — excluded from the scan.
EXCLUDE_ERE="app_navigator\.dart|game_over_nav\.dart|router\.dart|router\.gr\.dart"

# Narrower exclusion for TYPE C: only the two facade files are allowed to
# construct MainShellRoute(children: …) by hand — router.dart/router.gr.dart
# never do (they only declare the class), so there's no need to exempt them,
# but excluding only the facade keeps the intent explicit at the call site.
FACADE_EXCLUDE_ERE="app_navigator\.dart|game_over_nav\.dart"

violations=0

# ── Build a //-comment-stripped, file:line-tagged view of every lib/**/*.dart
#    file once, so every grep-based check below is immune to matches inside
#    comments. Format per line: "<absolute-path>:<line-number>:<code-only>".
SOURCE_CACHE="$(mktemp)"
JOINED_CACHE="$(mktemp)"
trap 'rm -f "$SOURCE_CACHE" "$JOINED_CACHE"' EXIT

while IFS= read -r -d '' f; do
  sed -E 's|//.*$||' "$f" | awk -v f="$f" '{print f ":" NR ":" $0}' >> "$SOURCE_CACHE"
done < <(find "$LIB_DIR" -name "*.dart" -print0)

# ── Multi-line method-chain view (TYPE A′/B′ fix) ────────────────────────────
# auto-format can wrap a chain like `ref.read(routerProvider).push(Route())`
# across several physical lines (one call per line). SOURCE_CACHE is strictly
# line-based, so a pattern spanning a line break never matches it — this was
# the actual gap that let `ref\n.read(routerProvider)\n.push(const
# PolicyRoute())` (a TYPE B′ violation) through undetected. Build a second
# cache where every continuation line (one whose stripped content starts with
# `.`, i.e. a chained call) is merged into the line above it, tagged with the
# starting line number, before matching.
while IFS= read -r -d '' f; do
  sed -E 's|//.*$||' "$f" | awk -v f="$f" '
    { raw[NR] = $0 }
    END {
      n = NR
      buf = ""; startln = 0
      for (i = 1; i <= n; i++) {
        line = raw[i]
        # Strip leading indentation from continuation lines only, so
        # `.push(` glues directly onto the previous token (e.g. `)`) with no
        # gap — the regexes below match adjacency, not whitespace-separated
        # tokens. The first line of a buffered chain keeps its own
        # indentation (irrelevant to matching, harmless either way).
        if (buf != "") { gsub(/^[ \t]+/, "", line) }
        if (buf == "") { startln = i; buf = line } else { buf = buf line }
        nxt = (i + 1 <= n) ? raw[i + 1] : ""
        gsub(/^[ \t]+/, "", nxt)
        if (nxt ~ /^\./) continue
        print f ":" startln ":" buf
        buf = ""
      }
    }
  ' >> "$JOINED_CACHE"
done < <(find "$LIB_DIR" -name "*.dart" -print0)

# ── TYPE A: root route pushed/replaced without .root ─────────────────────────
#
# Verbs covered: push, replace (both take a single route argument directly
# after the opening paren — same shape). replaceAll is deliberately excluded,
# see the doc comment at the top of this file.

type_a=$(
  grep -hE "\.(push|replace)\([[:space:]]*(const[[:space:]]+)?${ROOT_ROUTES_ERE}" "$SOURCE_CACHE" "$JOINED_CACHE" \
  | grep -Ev "$EXCLUDE_ERE" \
  | grep -v "\.root\." \
  | sort -u \
  || true
)

if [[ -n "$type_a" ]]; then
  echo ""
  echo "TYPE A — Root route pushed/replaced without .root.push()/.root.replace() (will corrupt nav stack):"
  echo "$type_a"
  violations=1
fi

# ── TYPE A′: root route reached without .root.navigate() ────────────────────

type_a_prime=$(
  grep -hE "\.navigate\([[:space:]]*(const[[:space:]]+)?${ROOT_ROUTES_ERE}" "$SOURCE_CACHE" "$JOINED_CACHE" \
  | grep -Ev "$EXCLUDE_ERE" \
  | grep -v "\.root\." \
  | sort -u \
  || true
)

if [[ -n "$type_a_prime" ]]; then
  echo ""
  echo "TYPE A′ — Root route reached without .root.navigate() (will corrupt nav stack):"
  echo "$type_a_prime"
  violations=1
fi

# ── TYPE B: tab route pushed/replaced via .root.* ─────────────────────────────
#
# Grep for .root.(push|replace|replaceAll)(<TabRoute> — a tab route wrongly
# reached at the root level via any of the three root-stack mutation verbs.

type_b=$(
  grep -hE "\.root\.(push|replace|replaceAll)\(.*${TAB_ROUTES_ERE}" "$SOURCE_CACHE" "$JOINED_CACHE" \
  | grep -Ev "$EXCLUDE_ERE" \
  | sort -u \
  || true
)

if [[ -n "$type_b" ]]; then
  echo ""
  echo "TYPE B — Tab route pushed/replaced via .root.* (bypasses tab shell):"
  echo "$type_b"
  violations=1
fi

# ── TYPE B′: tab route pushed via the ROOT router's bare .push() ────────────
#
# Shape 1 — direct chain: ref.read(routerProvider).push(<TabRoute>...)
# (routerProvider yields an AppRouter, a RootStackRouter — .push() on it is
# root-level even without an explicit ".root.").

type_b_prime_1=$(
  grep -hE "routerProvider\)\.push\([[:space:]]*(const[[:space:]]+)?${TAB_ROUTES_ERE}" "$SOURCE_CACHE" "$JOINED_CACHE" \
  | grep -Ev "$EXCLUDE_ERE" \
  | sort -u \
  || true
)

# Shape 2 — a local variable bound to ref.read/watch(routerProvider) then used
# as `<var>.push(<TabRoute>)` (or .navigate/.replace/.replaceAll — same
# root-level exposure regardless of verb) later in the same file (the
# notifications / overlay shape — e.g. `final router =
# ref.read(routerProvider); ... router.push(const CarnetRoute());`).

type_b_prime_2=""
while IFS= read -r -d '' f; do
  if [[ "$f" =~ $EXCLUDE_ERE ]]; then
    continue
  fi
  stripped="$(sed -E 's|//.*$||' "$f")"
  root_router_vars=$(
    printf '%s\n' "$stripped" \
      | grep -oE '\b[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*ref\.(read|watch)\(routerProvider\)' \
      | sed -E 's/[[:space:]]*=.*//' \
      | sort -u \
      || true
  )
  for v in $root_router_vars; do
    hits=$(
      printf '%s\n' "$stripped" \
        | grep -nE "\b${v}\.(push|navigate|replace|replaceAll)\([[:space:]]*(const[[:space:]]+)?${TAB_ROUTES_ERE}" \
        || true
    )
    if [[ -n "$hits" ]]; then
      while IFS= read -r line; do
        type_b_prime_2+="$f:$line"$'\n'
      done <<< "$hits"
    fi
  done
done < <(find "$LIB_DIR" -name "*.dart" -print0)

type_b_prime="${type_b_prime_1}${type_b_prime_2}"

if [[ -n "$(printf '%s' "$type_b_prime" | tr -d '[:space:]')" ]]; then
  echo ""
  echo "TYPE B′ — Tab route pushed via the root router's bare .push() (bypasses tab shell):"
  [[ -n "$type_b_prime_1" ]] && echo "$type_b_prime_1"
  [[ -n "$type_b_prime_2" ]] && printf '%s' "$type_b_prime_2"
  violations=1
fi

# ── TYPE C: manual MainShellRoute(children: …) construction outside the facade

type_c=$(
  grep -hE "MainShellRoute\([[:space:]]*children[[:space:]]*:" "$SOURCE_CACHE" "$JOINED_CACHE" \
  | grep -Ev "$FACADE_EXCLUDE_ERE" \
  | sort -u \
  || true
)

if [[ -n "$type_c" ]]; then
  echo ""
  echo "TYPE C — Manual MainShellRoute(children: …) construction outside the facade:"
  echo "$type_c"
  violations=1
fi

# ── Result ───────────────────────────────────────────────────────────────────

if [[ $violations -eq 0 ]]; then
  [[ "$QUIET" != "--quiet" ]] && echo "check_navigation: OK — no navigation scope violations found."
  exit 0
else
  echo ""
  echo "check_navigation: FAIL — fix violations above before merging."
  echo "  Use AppNavigator.* (lib/core/navigation/app_navigator.dart) instead of"
  echo "  raw context.router.push() / .root.push() / ref.read(routerProvider) for"
  echo "  cross-scope navigation."
  exit 1
fi
