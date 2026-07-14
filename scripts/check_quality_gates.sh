#!/usr/bin/env bash
# Mechanical quality gate (charter §11 — hooks, not prompts).
# Blocks a task/handoff (exit 2) if a recently-active worktree with in-flight
# changes fails: static analysis, the test suite, or the project's convention checks.
#
# ── TEMPLATE ─────────────────────────────────────────────────────────────────
# The worktree-scoping machinery below is generic — keep it. Adapt only:
#   1. ROOT           — your repo's absolute path (or keep the auto-detect)
#   2. SOURCE_GLOB    — which changed files trigger the gate ('*.dart', '*.ts', …)
#   3. run_analysis / run_tests / run_convention_checks — your stack's commands
# ─────────────────────────────────────────────────────────────────────────────
#
# Scoping rule: only worktrees whose git index was modified in the last
# ACTIVE_WINDOW_HOURS are gated — dormant worktrees from paused tasks
# must not block unrelated work. Escape hatch: SKIP_QUALITY_GATE=1
# (use only with an explicit reason in the task/report).
#
# Exit codes: 0 = pass or nothing to gate ; 2 = gate failed (stderr = feedback).

set -u
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SOURCE_GLOB='*.*'                 # ADAPT: e.g. '*.dart' or '*.ts'
SOURCE_DIRS_RE='^(src|lib|test)/' # ADAPT: dirs whose changes require running the tests
ACTIVE_WINDOW_HOURS="${GATE_ACTIVE_WINDOW_HOURS:-6}"

if [ "${SKIP_QUALITY_GATE:-0}" = "1" ]; then
  echo "quality gate: skipped via SKIP_QUALITY_GATE=1"
  exit 0
fi

# ── ADAPT: your stack's three checks ─────────────────────────────────────────
run_analysis() {              # print findings; return non-zero on ERROR-level findings only
  # Example (Flutter): flutter analyze --no-pub 2>&1 | grep -E '^[[:space:]]*error •' && return 1
  # Example (TS):      npx tsc --noEmit && npx eslint . --quiet
  echo "quality gate: run_analysis not configured — adapt scripts/check_quality_gates.sh" >&2
  return 0
}
run_tests() {                 # return non-zero if the suite is red
  # Example (Flutter): flutter test
  # Example (Node):    npm test --silent
  echo "quality gate: run_tests not configured — adapt scripts/check_quality_gates.sh" >&2
  return 0
}
run_convention_checks() {     # project-specific greps/scripts (naming, architecture facades…)
  # Example: bash "$1/scripts/check_navigation.sh"   # "$1" = the worktree being gated
  return 0
}
# ─────────────────────────────────────────────────────────────────────────────

# Target priority: explicit path arg > --scan-all > hook-stdin cwd inside a worktree.
# NO implicit scan from hooks: parallel sessions each own a worktree, and a hook
# in session A must never block on session B's in-flight red worktree.
targets=()
if [ $# -ge 1 ] && [ "$1" = "--scan-all" ]; then
  now=$(date +%s)
  while IFS= read -r wt; do
    [ "$wt" = "$ROOT" ] && continue            # primary checkout stays clean by iron law
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
  changed=$( { git -C "$wt" diff --name-only main...HEAD -- "$SOURCE_GLOB" 2>/dev/null; \
               git -C "$wt" status --porcelain 2>/dev/null | awk '{print $NF}'; } | sort -u )
  [ -z "$changed" ] && { echo "quality gate: $wt — no source changes, skipped"; continue; }

  echo "quality gate: checking $wt (files changed: $(echo "$changed" | wc -l))"

  if ! (cd "$wt" && run_analysis); then
    echo "GATE FAILED [$wt]: static analysis has errors — fix them before completing this task." >&2
    fail=1
  fi

  if echo "$changed" | grep -qE "$SOURCE_DIRS_RE"; then
    if ! (cd "$wt" && run_tests); then
      echo "GATE FAILED [$wt]: test suite — a red test blocks the handoff (builder step 6 / inspector Static)." >&2
      fail=1
    fi
  fi

  if ! (cd "$wt" && run_convention_checks "$wt"); then
    echo "GATE FAILED [$wt]: convention checks — see output above." >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "Mechanical quality gate refused completion. Fix the failures above, then retry. (Escape hatch for a justified exception: SKIP_QUALITY_GATE=1)" >&2
  exit 2
fi
echo "quality gate: PASS"
exit 0
