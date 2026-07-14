# claude-custom-workflow

A **multi-agent orchestration workflow for [Claude Code](https://claude.com/claude-code)**: one lead agent as the user's sole interlocutor, six specialist subagents, hard guardrails, mechanical quality gates enforced by hooks, and a self-improving process loop.

This is the generic version of a workflow battle-tested daily on a production Flutter/Firebase mobile game by a solo developer. Everything project-specific has been replaced by `<placeholders>` and `TEMPLATE` notes; the architecture, contracts, and hard-won rules are intact. (The original as-deployed snapshot, Flutter specifics included, is the first commit of this repo's history.)

## The idea

The user talks to **one agent only**: the lead. The lead never edits code itself. It routes every demand to the right chain of specialists, batches their questions back to the user, and owns the outcome end-to-end:

| Role | Mission |
|---|---|
| **lead** | Sole user contact (bootstrapped by `CLAUDE.md` + `.claude/lead-charter.md`). Routes, synthesises, guarantees. |
| **scout** | Repo reconnaissance → structured brief + `QUESTIONS_FOR_USER:` block. Read-only. |
| **architect** | Brief + answers → concrete implementation plan. Read-only. |
| **builder** | Creates a git worktree, writes the code, applies the project's convention skills, commits. |
| **inspector** | Quality gate: static analysis, tests, visual validation, security checks, code review. |
| **debugger** | Root-cause analysis via a mandatory 4-step systematic loop; small fixes directly, big ones handed to builder. |
| **shipper** | Merge → push → (store/production deploys only on explicit user order) → post-release KPI check. |

Routing is graduated by demand size — typo → builder direct; big ambiguous feature → full scout → architect → builder → inspector → shipper chain — because every handoff loses context and multi-agent costs 3–10× in tokens (`lead-charter.md` §2).

## Mechanisms worth stealing

- **Trust charter with explicit guardrails** (§3): everything is auto-OK by default; the lead stops only on ~6 enumerated cases (production deploys, force push, product ambiguity, scope exit…). The mechanism matters more than the list: enumerate what must never be inferred, let everything else flow.
- **Persistent agents within a feature** (§6): agents stay alive for the whole workflow and talk to each other through the lead via `SendMessage` (requires the experimental Agent Teams flag, enabled in `.claude/settings.json`). At delivery, the lead stops messaging and the platform GCs them — never reuse an agent across features.
- **Minimal lead state** (§5): the lead keeps agent IDs and a worktree path; briefs/plans/verdicts live in the specialists' own contexts, and a gitignored `claude-progress.json` in the worktree makes interrupted work resumable across sessions.
- **Mechanical quality gates as hooks, not prompts** (`.claude/settings.json` + `scripts/check_quality_gates.sh`): static analysis + tests + convention checks run automatically on task completion and builder/debugger handoff, and can block the handoff (exit 2). Prompts drift; hooks don't.
- **Worktree iron law** (`.claude/skills/git-workflow-branch-worktree/`): no change lands on `main` directly, ever — plus the accumulated worktree gotchas (gitignored files not inherited, three-dot diffs, cwd traps).
- **Self-improving process** (§11): every specialist reports `## Process friction`; the lead triages each friction into exactly one home (memory, skill, or agent contract), under size budgets, with eval scenarios (`.claude/evals/`) replayed before non-trivial process edits, plus a convention-drift check on every shipped merge.
- **Exclusive-resource claiming** (§10): parallel agents claim emulators/test servers atomically (`flock`) instead of assuming the default instance is free — the #1 source of inter-agent conflicts.

## Layout

```
CLAUDE.md.template         # Paste at the top of your CLAUDE.md — bootstraps the lead role
.claude/
├── lead-charter.md        # The orchestration contract — start here
├── settings.json          # Agent Teams flag + quality-gate hooks
├── agents/                # The six specialist subagent contracts
│   ├── scout.md · architect.md · builder.md
│   └── inspector.md · debugger.md · shipper.md
├── evals/                 # Protocol + scenario templates replayed before process edits
└── skills/
    └── git-workflow-branch-worktree/   # Worktree-per-change iron law
scripts/
└── check_quality_gates.sh # Hook-driven gate — adapt 3 functions to your stack
```

## Adopting it

1. **Copy** `.claude/` and `scripts/` into your repo; paste `CLAUDE.md.template`'s section at the top of your `CLAUDE.md`.
2. **Search for `<angle brackets>` and `TEMPLATE` notes** — each marks a decision: your repo root, your stack's analysis/test commands (3 functions in `check_quality_gates.sh`), your project skills (`<your-design-system-skill>`, `<your-visual-validation-skill>`, …). Drop references to skills you don't have; the workflow degrades gracefully.
3. **Fill the scout's repo cheat-sheet** (`.claude/agents/scout.md`) — 5-10 bullets pointing at your load-bearing directories.
4. **Gitignore** `.worktrees/` and `claude-progress.json`.
5. **Rewrite the eval scenarios** (`.claude/evals/scenarios.md`) against your real codebase — the shipped ones are shapes, not runnable evals.
6. Restart the session so the Agent Teams flag is picked up. Without it, `SendMessage` is unavailable and subagents are one-shot — the charter documents the fallback (§6).
7. Optional but recommended: the [superpowers](https://github.com/obra/superpowers) skill pack — the debugger and the worktree skill reference `superpowers:systematic-debugging` and `superpowers:using-git-worktrees` when installed.

Model choices in the agent frontmatter (`haiku` scout, `opus` architect/debugger, `sonnet` builder/inspector/shipper) are sensible defaults — adjust to taste and budget.

## Philosophy

- The split follows **context needs, not job titles**: whoever implements also writes their tests; the inspector verifies a posteriori, never co-constructs.
- **Evidence over prompts**: gates are shell scripts with exit codes, process lessons are mechanical checkable rules with a one-line trigger trace, evals are replayed before/after process edits.
- **One home per rule**: a rule lives in the charter, OR a skill, OR an agent contract — elsewhere it is referenced by name. Duplicated rules drift.
- **Size budgets force consolidation**: agent file ≤200 lines, skill ≤250, charter ≤300. Over budget, appending is forbidden.

## License

MIT — see [LICENSE](LICENSE).
