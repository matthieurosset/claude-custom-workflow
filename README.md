# claude-custom-workflow

A real-world, battle-tested **multi-agent orchestration workflow for [Claude Code](https://claude.com/claude-code)**, snapshotted as-is from a production Flutter/Firebase mobile game project (Mission Geo, July 2026).

This is not a template built in the abstract — it is the exact set of process files a solo developer uses daily to run Claude Code as a **lead agent orchestrating six specialist subagents**, with hard guardrails, mechanical quality gates, self-improving process loops, and project skills. Names are project-specific (`mg-*`); the architecture is not.

## The idea

The user talks to **one agent only**: the lead. The lead never edits code itself. It routes every demand to the right chain of specialists, batches their questions back to the user, and owns the outcome end-to-end:

| Role | Mission |
|---|---|
| **mg-lead** | Sole user contact (defined by `CLAUDE.md` + `.claude/lead-charter.md`). Routes, synthesises, guarantees. |
| **mg-scout** | Repo reconnaissance → structured brief + `QUESTIONS_FOR_USER:` block. Read-only. |
| **mg-architect** | Brief + answers → concrete implementation plan. Read-only. |
| **mg-builder** | Creates a git worktree, writes the code, applies design-system/i18n skills, commits. |
| **mg-inspector** | Quality gate: static analysis, tests, visual validation on emulator, security checks, code review. |
| **mg-debugger** | Root-cause analysis via systematic debugging; small fixes directly, big ones handed to builder. |
| **mg-shipper** | Merge → push → (store deploys only on explicit user order) → post-release KPI check. |

Routing is graduated by demand size (typo → builder direct; big ambiguous feature → full scout→architect→builder→inspector→shipper chain), because every handoff loses context and multi-agent costs 3–10× in tokens. See `.claude/lead-charter.md` §2.

Key mechanisms worth stealing:

- **Trust charter with explicit guardrails** (`lead-charter.md` §3): everything is auto-OK by default; the lead stops only on 6 enumerated cases (store deploys, force push, product ambiguity, …).
- **Persistent agents within a feature** (§6): agents stay alive for the whole workflow and talk to each other through the lead via `SendMessage` (requires the experimental Agent Teams flag, enabled in `.claude/settings.json`).
- **Minimal lead state** (§5): the lead keeps agent IDs and a worktree path — briefs/plans/verdicts live in the specialists' own contexts.
- **Mechanical quality gates as hooks, not prompts** (`.claude/settings.json` + `scripts/check_quality_gates.sh`): `flutter analyze` + tests + a navigation-convention check run automatically on task completion and builder/debugger handoff, and can block the handoff (exit 2).
- **Self-improving process** (§11): every specialist reports `## Process friction`; the lead triages frictions into exactly one home (memory, skill, or agent contract), under size budgets, with eval scenarios (`.claude/evals/`) replayed before non-trivial process edits.
- **Shared emulator pool** (`.claude/skills/shared/emulator-pool.sh`): `flock`-based port claiming so parallel agents never fight over Android emulators.

## Layout

```
.claude/
├── lead-charter.md        # The orchestration contract — start here
├── settings.json          # Agent Teams flag + quality-gate hooks
├── agents/                # The six specialist subagent definitions
├── evals/                 # Tagged scenarios replayed before process edits
└── skills/                # Project skills the agents invoke
    ├── git-workflow-branch-worktree/   # Worktree-per-change iron law
    ├── mission-geo-design-system/      # UI conventions gate
    ├── visual-validation-android/      # Emulator-based visual verification
    ├── online-multiplayer-debug/       # 2-instance online validation gate
    ├── online-security-validation/     # Firebase emulator security tests
    ├── regression-suite/               # Deterministic smoke/full suite
    ├── android-releaser/               # Play Console release pipeline
    ├── mission-geo-analytics/          # BigQuery/GA4 runbook
    ├── mission-geo-monetization/       # Play in-app products via API
    ├── add-dataset/ · add-locale/      # Content-pipeline automations
    └── shared/                         # Emulator pool (flock port claiming)
scripts/
├── check_quality_gates.sh # Hook: analyze + test + navigation check per active worktree
└── check_navigation.sh    # Convention check invoked by the gate
docs/
└── CLAUDE-md-lead-section.md  # The CLAUDE.md excerpt that bootstraps the lead role
```

## Reusing it

This is a **snapshot**, published as-is for reference — expect project-specific content:

1. **Paths are hardcoded** to `/home/mrjack/git/mission-geo` in `settings.json`, `scripts/`, and several skills. Search-and-replace with your repo root.
2. **Skills are Flutter/Firebase/Android-specific.** Keep the *shape* (SKILL.md + references/ + scripts/, invoked by agents at defined moments), replace the content with your stack's equivalents. The most transferable pieces are `git-workflow-branch-worktree` and `shared/emulator-pool.sh`.
3. **The charter and agent contracts transfer almost directly** — swap the skill names, the quality-gate command, and the guardrail list for yours.
4. **Agent Teams** (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) is experimental and token-hungry; without it the workflow degrades to one-shot subagents (the charter documents the fallback in §6).
5. The workflow assumes Claude Code's **auto-memory** for user/project rules; the charter's §7 governs when the lead saves them.

## Provenance

Extracted 2026-07-14 from a private repository. Secrets, local settings (`settings.local.json`), credentials, and worktree state were excluded; references to gitignored key files describe where secrets live, not their content.

## License

MIT — see [LICENSE](LICENSE).
