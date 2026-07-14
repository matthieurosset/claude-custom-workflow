#!/usr/bin/env bash
# Mechanical quality gate (charter §11 — hooks, not prompts).
# Blocks a task/handoff (exit 2) if a recently-active worktree with in-flight
# Dart changes fails: flutter analyze, flutter test (lib/test touched),
# or scripts/check_navigation.sh (lib/ touched).
#
# Scoping rule: only worktrees whose git index was modified in the last
# ACTIVE_WINDOW_HOURS are gated — dormant worktrees from paused chantiers
# must not block unrelated work. Escape hatch: MG_SKIP_QUALITY_GATE=1
# (use only with an explicit reason in the task/report).
#
# Exit codes: 0 = pass or nothing to gate ; 2 = gate failed (stderr = feedback).

set -u
ROOT="/home/mrjack/git/mission-geo"
ACTIVE_WINDOW_HOURS="${MG_GATE_ACTIVE_WINDOW_HOURS:-6}"
export PATH="$HOME/flutter/bin:$PATH"

if [ "${MG_SKIP_QUALITY_GATE:-0}" = "1" ]; then
  echo "quality gate: skipped via MG_SKIP_QUALITY_GATE=1"
  exit 0
fi

# Target priority: explicit path arg > --scan-all > hook-stdin cwd inside a worktree.
# NO implicit scan from hooks: parallel sessions each own a worktree, and a hook
# in session A must never block on session B's in-flight red worktree
# (memory feedback_concurrent_inspectors_contaminate_measurements).
targets=()
if [ $# -ge 1 ] && [ "$1" = "--scan-all" ]; then
  now=$(date +%s)
  while IFS= read -r wt; do
    [ "$wt" = "$ROOT" ] && continue            # main checkout stays clean by iron law
    gitdir=$(sed -n 's/^gitdir: //p' "$wt/.git" 2>/dev/null)
    idx="${gitdir:-$wt/.git}/index"
    [ -e "$idx" ] || continue
    age=$(( (now - $(stat -c %Y "$idx")) / 3600 ))
    [ "$age" -lt "$ACTIVE_WINDOW_HOURS" ] && targets+=("$wt")
  done < <(git -C "$ROOT" worktree list --porcelain | sed -n 's/^worktree //p')
elif [ $# -ge 1 ] && [ -d "$1" ]; then
  targets+=("$1")
else
  hook_cwd=$(cat 2>/dev/null | jq -r '.cwd // empty' 2>/dev/null || true)
  if [ -n "$hook_cwd" ] && [[ "$hook_cwd" == "$ROOT/.worktrees/"* ]]; then
    wt_root="$ROOT/.worktrees/$(echo "${hook_cwd#"$ROOT"/.worktrees/}" | cut -d/ -f1)"
    [ -d "$wt_root" ] && targets+=("$wt_root")
  fi
fi

[ ${#targets[@]} -eq 0 ] && { echo "quality gate: no session-scoped worktree (and no --scan-all) — nothing to gate"; exit 0; }

fail=0
for wt in "${targets[@]}"; do
  changed=$( { git -C "$wt" diff --name-only main...HEAD -- '*.dart' 2>/dev/null; \
               git -C "$wt" status --porcelain 2>/dev/null | awk '{print $NF}' | grep '\.dart$'; } | sort -u )
  [ -z "$changed" ] && { echo "quality gate: $wt — no Dart changes, skipped"; continue; }

  echo "quality gate: checking $wt (dart files changed: $(echo "$changed" | wc -l))"

  # The repo baseline carries info- and some warning-level lints on main —
  # only error-level findings block mechanically (agents still owe 0 new warnings).
  out=$(cd "$wt" && flutter analyze --no-pub 2>&1) || true
  if echo "$out" | grep -qE '^[[:space:]]*error •'; then
    echo "$out" | grep -E '^[[:space:]]*error •' | head -10 >&2
    echo "GATE FAILED [$wt]: flutter analyze has errors — fix them before completing this task." >&2
    fail=1
  fi

  if echo "$changed" | grep -qE '^(lib|test)/'; then
    out=$(cd "$wt" && flutter test 2>&1); rc=$?
    echo "$out" | tail -5
    if [ $rc -ne 0 ]; then
      echo "GATE FAILED [$wt]: flutter test — a red test blocks the handoff (mg-builder step 6 / mg-inspector Static)." >&2
      fail=1
    fi
  fi

  if echo "$changed" | grep -q '^lib/' && [ -x "$wt/scripts/check_navigation.sh" ]; then
    if ! (cd "$wt" && bash scripts/check_navigation.sh) ; then
      echo "GATE FAILED [$wt]: check_navigation.sh — a call site bypasses the AppNavigator facade (CLAUDE.md nav scope rules)." >&2
      fail=1
    fi
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "Mechanical quality gate refused completion. Fix the failures above, then retry. (Escape hatch for a justified exception: MG_SKIP_QUALITY_GATE=1)" >&2
  exit 2
fi
echo "quality gate: PASS"
exit 0
