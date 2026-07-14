---
name: git-workflow-branch-worktree
description: Use before making any code or file change in this project, or when the user mentions branches, commits, merges, push, PRs, or any git operation. Triggers BEFORE the first Edit/Write of the session.
---

# Git Workflow: Branch + Worktree First

## Overview

**Iron Law:** No file change in this project lands directly on `main`. Every task — feature, bugfix, refactor, doc tweak, config edit, asset addition — starts on its own branch in its own worktree. Only after the user explicitly validates does it merge to `main` and get pushed.

The user has stated this is project policy and does not want to repeat it. Treat it as binding, not a suggestion.

## When to Apply

**Apply BEFORE the first `Edit` / `Write` / `MultiEdit` / `NotebookEdit` of the session:**
- New feature ("add X", "implement Y")
- Bug fix ("fix", "the rendering is broken")
- Refactor, cleanup, simplification
- Documentation edits (`CLAUDE.md`, README, files under `.claude/skills/`)
- Config or dependency changes (manifest/lockfiles, build config, asset additions)
- Anything modifying a tracked file

**Skip for:**
- Read-only inspection: `Read`, `Grep`, `Glob`, `git status`, `git log`, static analysis
- Files under the scratch/temp directory or outside the repo (e.g. `~/.bashrc`)
- Building/installing without committing (builds, screenshots)

## Project Convention

- Worktrees live at `.worktrees/<slug>/` (make sure that path is gitignored)
- Branch prefixes: `feat/<slug>`, `fix/<slug>`, `refactor/<slug>`, `docs/<slug>`, `chore/<slug>`
- `<slug>` is kebab-case, descriptive: `feat/swipe-header`, `fix/leaderboard-perms`, `docs/validation-skill`

## The Workflow

```
1. Branch + Worktree → 2. Implement → 3. User validates → 4. Merge to main → 5. Push → 6. Cleanup
```

Never collapse steps. Never skip step 3. Never `git push` before step 3.

### Step 1 — Branch + Worktree (MANDATORY first action)

```bash
cd <repo root>
git worktree add -b <prefix>/<slug> .worktrees/<slug> main
cd .worktrees/<slug>
```

Then announce to the user: *"Working on branch `<prefix>/<slug>` in `.worktrees/<slug>`."*

For non-trivial features, if the `superpowers` skill pack is installed, **`superpowers:using-git-worktrees`** handles edge cases (uncommitted main changes, branch already exists, dirty state) and runs safety verification.

All subsequent edits, builds, screenshots, MUST happen inside the worktree.

Right after creation, echo the full absolute worktree path and use ONLY that prefix for every subsequent `Edit` — the primary directory shares identical relative paths, so a path-prefix typo silently edits the wrong tree. Check: before committing, `git status` inside the worktree MUST show your edit; if it doesn't, you edited the primary directory — revert there (scoped to your file only) and redo in the worktree.

### Step 2 — Implement

Standard work loop. Commit progressively on the feature branch with descriptive messages. No `--no-verify`, no amending pushed commits, no hook bypassing. Stay on the feature branch.

If visual changes: validate the rendering (your project's visual-validation skill, if any) before declaring complete.

### Step 3 — Validation Gate (MANDATORY)

Before merging, the user must say something equivalent to:
- "OK, it works"
- "Approved"
- "You can merge"
- "Push"

**If the user has NOT explicitly validated, STOP.** Show them the diff, the screenshots if visual, the test output, and wait. Never assume validation from silence or from "ok continue".

### Step 4 — Merge to main

Only after explicit validation:
```bash
cd <repo root>                                   # back to the primary checkout
git checkout main
git pull --ff-only origin main                   # ensure main is up to date
git merge --no-ff <prefix>/<slug>                # preserve branch history
```

Resolve conflicts properly. Never `-X ours/theirs` blindly, never discard branch changes without asking.

Never assume the primary directory can `git checkout main` — it may sit on another branch with another agent's uncommitted work. If merge-base(main, branch) equals main's tip, fast-forward via `git update-ref refs/heads/main <sha>` (no checkout needed). If real divergence, create a dedicated temporary worktree for `main` and merge there — never switch the primary directory's branch. If a `main`-tracking worktree already exists (e.g. `.worktrees/ship-main`), reuse it INSTEAD of creating a new one only if `git status --short` there is clean and it's already at `origin/main`'s tip — and never `git worktree remove` it afterward, since you didn't create it.

### Step 5 — Push

```bash
git push origin main
```
No force push. No pushing other branches unless explicitly asked.

### Step 6 — Cleanup

```bash
git worktree remove .worktrees/<slug>
git branch -d <prefix>/<slug>                    # not -D unless user asks
```

Run `git branch -d` from a worktree whose HEAD is already on `main` (e.g. `.worktrees/ship-main`) — from the primary checkout sitting on another branch, `-d` reports the target branch as "not fully merged" even when it is.

For PR-based flows or when discussion is needed, use a structured finishing flow instead (e.g. `superpowers:finishing-a-development-branch` if installed) — it offers merge/PR/keep-open options.

## Bash Hygiene & Fresh-Worktree Setup

- Bash cwd resets between tool calls — prefix EVERY git/bash command with `cd <absolute worktree path> &&`, including read-only-seeming introspection (`git status`, `git log`, `git stash`).
- A fresh worktree never inherits **gitignored** files. If your builds need gitignored secrets/config (signing keys, local tokens, `.env`), symlink them from the primary checkout right after creation — the symptom of forgetting is an auth/attestation error that reads like a network/env bug, not a missing file. List your project's required files here:
  - `ln -s <repo root>/<path-to-gitignored-file> <same relative path>` (one per file)
- In a freshly created worktree, run your dependency install first (`npm ci`, `pub get`, `pip install`…). If the test suite then fails on tests unrelated to your diff, clean the build cache and retest — and check whether it also fails on `main` — before calling it "pre-existing".
- Before merging, evaluate a branch's real file scope with `git diff main...branch` (merge-base, three-dot) — `git diff main..branch` (two-dot) lists misleading files when the branch forked from an older `main`.
- `cd` OUT of a worktree (e.g. back to the primary directory) before running `git worktree remove` on it — removing the directory your shell is currently inside breaks its cwd and every chained command after.

## Rationalizations to Reject

| Excuse | Reality |
|---|---|
| "It's just a one-line doc fix" | Still branch. The rule has no size threshold. |
| "I'm already on main, I'll branch after" | `git stash`, branch+worktree, `git stash pop` into the worktree. Don't keep working on main. |
| "The user said 'just fix X'" | They want it in the repo. Branch first; merge after validation. |
| "We're in a hurry" | Worktree creation = 5 seconds. The rule exists because shortcuts cost more later. |
| "Tiny refactor before the real work" | If it's a file change, it's a branch. |
| "Main only has my changes anyway" | That's the bug. `main` must be clean and equal to `origin/main` until validated merge. |
| "I'll merge without waiting since it's obviously correct" | Validation gate is non-negotiable. Wait. |
| "The user said push earlier in the conversation" | Authorization is per-task, not session-wide. Re-confirm for each task. |

## Red Flags — STOP

**Before any `Edit` / `Write`:**
- `pwd` shows the repo root (the primary checkout)?
- `git branch --show-current` returns `main`?

→ If yes to either, STOP. Branch + worktree first. Then proceed in the worktree.

**Before `git merge` / `git push`:**
- Did the user explicitly OK this specific change in this conversation?

→ If unsure, STOP and ask.

## Quick Reference

```bash
# START a task
cd <repo root>
git worktree add -b feat/my-feature .worktrees/my-feature main
cd .worktrees/my-feature

# DURING work — commits on the feature branch
git add <files> && git commit -m "feat: ..."

# FINISH (only after explicit user validation)
cd <repo root>
git checkout main && git pull --ff-only
git merge --no-ff feat/my-feature
git push origin main
git worktree remove .worktrees/my-feature
git branch -d feat/my-feature
```

## Recovery: I Already Edited main by Mistake

If the rule was violated and uncommitted changes exist on `main`:
```bash
cd <repo root>
git stash --include-untracked            # save the work
git worktree add -b <prefix>/<slug> .worktrees/<slug> main
cd .worktrees/<slug>
git stash pop                            # bring the work into the worktree
```
Verify `main` is now clean (`git status` in the primary checkout) before continuing.
