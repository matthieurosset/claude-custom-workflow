# Common Mistakes — extra rows

Overflow from the Common Mistakes table in `visual-validation-android/SKILL.md`. These two are layout/positioning gotchas rather than emulator-ops or command-transcript pitfalls, so they didn't fit the other two reference files — kept here instead of a fourth micro-file.

| Symptom | Cause | Fix |
|---|---|---|
| Page title clipped under the AppBar | `extendBodyBehindAppBar: true` + insufficient top padding | Either remove `extendBodyBehindAppBar`, OR pad top by `TransparentAppBar.preferredSize.height` (80) |
| FAB overlaps AppBar / collides with back button | Orphan `Positioned(top: ~40, right: ~30)` | Move into `TransparentAppBar(actions: [...])` slot |
