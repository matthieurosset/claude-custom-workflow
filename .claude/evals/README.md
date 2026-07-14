# Evals — lightweight harness for prompt/skill changes (charter §11)

Goal: measure the effect of an edit to `.claude/agents/*.md`, `.claude/skills/*/SKILL.md` or the charter,
instead of judging it by re-reading. ~8 representative scenarios are enough to see an impact
(Anthropic practice: ~20 for a full research system; this surface is smaller).

## When to replay

- **Mandatory**: any **non-trivial** edit of a process file (>10 lines, or change/removal of an
  existing rule) → replay the scenarios tagged with the touched file, BEFORE and AFTER the edit
  (baseline first — this is the RED of skill-writing TDD).
- **Exempt**: pure factual correction (path, number, skill name) ≤10 lines.

## How to replay a scenario

1. Spawn a **fresh** subagent (type given by the scenario), prompt = the `### Prompt` block verbatim.
   Clean context: no history from the current session, no hint of the expected criteria.
2. Let the agent finish. Collect its output + the observable artifacts (files, commits, commands run).
3. **Single judge, single call** (more consistent than panels for long outputs):
   a distinct subagent receives the output + the artifacts + the scenario's grid, and returns:

```
score: 0.0-1.0 per criterion (mechanical: the criterion is observed or not)
verdict: PASS if all "blocking" criteria = 1.0, otherwise FAIL
evidence: 1 line per criterion — the observed proof (command, file, quote), not an impression
```

4. Result recorded in the task's report (no ever-growing results file — the task's git log
   is the history). An edit that flips a scenario from PASS to FAIL does not merge.

## Anti-contamination

- The evaluated subagent must never see the criteria grid nor know it is being evaluated.
- Scenarios with artifacts (worktree, commits): play them in a throwaway worktree `evals/<scenario-id>`,
  removed after judgment — never in a real task's worktree.
- Exclusive resource required (emulator, test server) → the usual shared claiming mechanism,
  never an eval scenario in parallel with a real validation run.

Scenarios: `scenarios.md` (suggested tags: `git-workflow`, `i18n`, `design-system`, `conventions`, `architect`, `debugger`, `inspector`, `integration`, `scope`).
