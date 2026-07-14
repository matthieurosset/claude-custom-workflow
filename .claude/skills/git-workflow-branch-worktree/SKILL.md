---
name: git-workflow-branch-worktree
description: Use before making any code or file change in this Mission Geo project, or when the user mentions branches, commits, merges, push, PRs, or any git operation. Triggers BEFORE the first Edit/Write of the session.
---

# Git Workflow: Branch + Worktree First

## Overview

**Iron Law:** No file change in this project lands directly on `main`. Every task — feature, bugfix, refactor, doc tweak, config edit, asset addition — starts on its own branch in its own worktree. Only after the user explicitly validates does it merge to `main` and get pushed.

The user has stated this is project policy and does not want to repeat it. Treat it as binding, not a suggestion.

## When to Apply

**Apply BEFORE the first `Edit` / `Write` / `MultiEdit` / `NotebookEdit` of the session:**
- New feature ("ajoute X", "implemente Y")
- Bug fix ("corrige", "le rendu est cassé")
- Refactor, cleanup, simplification
- Documentation edits (`CLAUDE.md`, README, files under `.claude/skills/`)
- Config or dependency changes (`pubspec.yaml`, `*.gradle*`, asset additions)
- Anything modifying a tracked file

**Skip for:**
- Read-only inspection: `Read`, `Grep`, `Glob`, `git status`, `git log`, `flutter analyze`
- Files under `/tmp/` or outside the repo (e.g. `~/.bashrc`, `~/.android/avd/`)
- Building/installing without committing (`flutter build`, screenshots)

## Project Convention

- Worktrees live at `.worktrees/<slug>/` (already gitignored)
- Branch prefixes: `feat/<slug>`, `fix/<slug>`, `refactor/<slug>`, `docs/<slug>`, `chore/<slug>`
- `<slug>` is kebab-case, descriptive: `feat/swipe-elo-header`, `fix/firebase-leaderboard-perms`, `docs/visual-validation-skill`

## The Workflow

```
1. Branch + Worktree → 2. Implement → 3. User validates → 4. Merge to main → 5. Push → 6. Cleanup
```

Never collapse steps. Never skip step 3. Never `git push` before step 3.

### Step 1 — Branch + Worktree (MANDATORY first action)

```bash
cd /home/mrjack/git/mission-geo
git worktree add -b <prefix>/<slug> .worktrees/<slug> main
cd .worktrees/<slug>
```

Then announce to the user: *"Je travaille sur la branche `<prefix>/<slug>` dans `.worktrees/<slug>`."*

For non-trivial features, **REQUIRED SUB-SKILL: superpowers:using-git-worktrees** — it handles edge cases (uncommitted main changes, branch already exists, dirty state) and runs safety verification.

All subsequent edits, builds, screenshots, MUST happen inside the worktree.

Right after creation, echo the full absolute worktree path and use ONLY that prefix for every subsequent `Edit` — the primary directory shares identical relative paths, so a path-prefix typo silently edits the wrong tree. Check: before committing, `git status` inside the worktree MUST show your edit; if it doesn't, you edited the primary directory — revert there (scoped to your file only) and redo in the worktree. <!-- trigger: builder path-typo + busy primary dir during skill-note merge, 2026-07-11 -->

### Step 2 — Implement

Standard work loop. Commit progressively on the feature branch with descriptive messages. No `--no-verify`, no amending pushed commits, no hook bypassing. Stay on the feature branch.

If visual changes: invoke `visual-validation-android` to validate before declaring complete.

### Step 3 — Validation Gate (MANDATORY)

Before merging, the user must say something equivalent to:
- "OK, ça marche"
- "Valide"
- "Tu peux merger"
- "Push"
- "C'est bon, on merge"

**If the user has NOT explicitly validated, STOP.** Show them the diff, the screenshots if visual, the test output, and wait. Never assume validation from silence or from "ok continue".

### Step 4 — Merge to main

Only after explicit validation:
```bash
cd /home/mrjack/git/mission-geo                  # back to main worktree
git checkout main
git pull --ff-only origin main                   # ensure main is up to date
git merge --no-ff <prefix>/<slug>                # preserve branch history
```

Resolve conflicts properly. Never `-X ours/theirs` blindly, never discard branch changes without asking.

Never assume the primary directory can `git checkout main` — it may sit on another branch with another agent's uncommitted work. If merge-base(main, branch) equals main's tip, fast-forward via `git update-ref refs/heads/main <sha>` (no checkout needed). If real divergence, create a dedicated temporary worktree for `main` and merge there — never switch the primary directory's branch. If a `main`-tracking worktree already exists (e.g. `.worktrees/ship-main`), reuse it INSTEAD of creating a new one only if `git status --short` there is clean and it's already at `origin/main`'s tip — and never `git worktree remove` it afterward, since you didn't create it. <!-- trigger: builder path-typo + busy primary dir during skill-note merge, 2026-07-11 -->

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

Run `git branch -d` from a worktree whose HEAD is already on `main` (e.g. `.worktrees/ship-main`) — from the primary checkout sitting on another branch, `-d` reports the target branch as "not fully merged" even when it is. <!-- trigger: shipper false alarm, 2026-07-11 -->

For PR-based flows or when discussion is needed, use **`superpowers:finishing-a-development-branch`** instead — it offers structured options (merge/PR/keep open).

## Bash Hygiene & Fresh-Worktree Setup

- Bash cwd resets between tool calls — prefix EVERY git/bash command with `cd <absolute worktree path> &&`, including read-only-seeming introspection (`git status`, `git log`, `git stash`). <!-- trigger: stash -u exécuté dans le checkout principal, a saisi les modifs d'une autre session, 2026-07-10 -->
- Any dev/prod-flavor **device build** from a fresh worktree needs the gitignored App Check/signing files copied over first, not just "auth/signing" tasks — a worktree never inherits gitignored files. Right after creation: `ln -s /home/mrjack/git/mission-geo/android/key.properties android/key.properties`, `ln -s /home/mrjack/git/mission-geo/android/firebase_debug_token.dev.properties android/firebase_debug_token.dev.properties`, and `ln -s /home/mrjack/git/mission-geo/android/firebase_debug_token.prod.properties android/firebase_debug_token.prod.properties` if a prod-flavor build is also needed. Symptom if skipped: App Check 403 "App attestation failed" → "Something went wrong" on any authenticated flow (e.g. onboarding account creation) — reads like a network/env bug, not a missing file. <!-- trigger: fresh worktree → App Check broken → PERMISSION_DENIED blocked on-device purchase/auth repro, debugger, 2026-07-11; inspector lost hours on missing token in fresh worktree, onboarding overlay fixes, 2026-07-13 -->
- In a freshly created worktree, run `flutter pub get` first. If `flutter test` then fails on tests unrelated to your diff (e.g. an `ink_sparkle.frag` SkSL/Vulkan shader crash), run `flutter clean && flutter pub get` and retest — and check whether it also fails on `main` — before calling it "pre-existing". <!-- trigger: 4 faux échecs "préexistants" dus au cache de build du worktree, 2026-07-10 -->
- Before merging, evaluate a branch's real file scope with `git diff main...branch` (merge-base, three-dot) — `git diff main..branch` (two-dot) lists misleading files when the branch forked from an older `main`. <!-- trigger: Shipper misread branch scope pre-merge via two-dot diff, 2026-07-10 -->
- `cd` OUT of a worktree (e.g. back to the primary directory) before running `git worktree remove` on it — removing the directory your shell is currently inside breaks its cwd and every chained command after. <!-- trigger: chantier username-moderation, 2026-07-11 -->

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
- `pwd` shows `/home/mrjack/git/mission-geo` (the main worktree)?
- `git branch --show-current` returns `main`?

→ If yes to either, STOP. Branch + worktree first. Then proceed in the worktree.

**Before `git merge` / `git push`:**
- Did the user explicitly OK this specific change in this conversation?

→ If unsure, STOP and ask.

## Quick Reference

```bash
# START a task
cd /home/mrjack/git/mission-geo
git worktree add -b feat/my-feature .worktrees/my-feature main
cd .worktrees/my-feature

# DURING work — commits on the feature branch
git add <files> && git commit -m "feat: ..."

# FINISH (only after explicit user validation)
cd /home/mrjack/git/mission-geo
git checkout main && git pull --ff-only
git merge --no-ff feat/my-feature
git push origin main
git worktree remove .worktrees/my-feature
git branch -d feat/my-feature
```

## Recovery: I Already Edited main by Mistake

If the rule was violated and uncommitted changes exist on `main`:
```bash
cd /home/mrjack/git/mission-geo
git stash --include-untracked            # save the work
git worktree add -b <prefix>/<slug> .worktrees/<slug> main
cd .worktrees/<slug>
git stash pop                            # bring the work into the worktree
```
Verify `main` is now clean (`git status` in the main worktree) before continuing.
