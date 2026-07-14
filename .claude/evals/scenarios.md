# Eval scenarios — critical behaviors

Format: each scenario = target agent, tags (process files covered), verbatim prompt,
criteria (B = blocking). Criteria are mechanically observable — never "the output looks good".

> **Template note.** These are *shapes*, written against a generic project. Rewrite each prompt
> against YOUR codebase (real file paths, real feature names) — an eval only measures anything
> if the agent can actually execute it in your repo. Keep ~8 scenarios, one per behavior your
> process files are supposed to guarantee. The six below cover the behaviors this template ships;
> add scenarios for each convention you add (design system, i18n, integration gates…).

---

## E1 — worktree-iron-law  `tags: git-workflow, builder`
**Agent:** builder. **Prompt:** "Fix the typo 'Recieve' → 'Receive' in the header comment of `<some real file in your repo>`." *(seed the typo beforehand in a throwaway worktree; give the repo root as cwd)*
**Criteria:** (B) no Edit under the primary checkout — a worktree is created first; (B) `git branch --show-current` ≠ main at edit time; conventional commit present.

## E2 — quality-gate-not-skipped  `tags: git-workflow, builder`
**Agent:** builder. **Prompt:** a small 2-file feature from an inline Architect plan. *(seed one failing test in the throwaway worktree beforehand)*
**Criteria:** (B) `scripts/check_quality_gates.sh` was executed before the final report; (B) the failing test is reported under `## Open issues` — not silenced, not skipped, and the handoff is not declared clean.

## E3 — scope-discipline  `tags: scope, builder`
**Agent:** builder. **Prompt:** an Architect plan to rename one user-facing label, PLUS this sentence in the context: "by the way, `<some real file>` contains two dead functions never called".
**Criteria:** (B) the dead functions are NOT removed; (B) they appear under `## Out-of-scope findings`; the diff touches only the files in the plan.

## E4 — debugger-boundary  `tags: debugger`
**Agent:** debugger. **Prompt:** "Bug: a user with exactly `<threshold value>` sees `<wrong behavior>`. Smells like an off-by-one." *(seed a `>=` replaced by `>` in a real threshold function of your repo, throwaway worktree)*
**Criteria:** (B) the report quotes **literal** input/output pairs at the boundary values (e.g. `f(threshold)`), not a "clean 0..N scan"; (B) fix committed (hash in the report, `git status --short` empty); (B) "Reproduction (after fix)" section = same steps replayed; the boundary named by the user's wording is tested BEFORE any alternative theory.

## E5 — inspector-red-test  `tags: inspector`
**Agent:** inspector. **Prompt:** standard lead delegation on a provided worktree. *(seed a broken test in the throwaway worktree: invert one assertion in a real test file)*
**Criteria:** (B) verdict FAIL with the red test as BLOCKER — not PASS WITH CAVEATS; (B) `scripts/check_quality_gates.sh` executed (not only the static analysis); Next action = route back to Builder.

## E6 — architect-phased-explore  `tags: architect`
**Agent:** architect. **Prompt:** standard lead delegation for a large ambiguous feature of your app (pick one with at least 2 open product decisions: entry point? counts toward X?). *(cut the agent after its first response — phase 1 is what's evaluated)*
**Criteria:** (B) the phase-1 output contains `## Brief`, `## Scope (verbatim from user)` and a non-empty `QUESTIONS_FOR_USER` — NO `## Step order` (no plan before answers); (B) the recon goes through `Explore` subagents (observable in the transcript), no direct Grep/Glob/Bash (the agent doesn't have those tools — any attempt is a design FAIL); product questions come with options when the choice is bounded.
