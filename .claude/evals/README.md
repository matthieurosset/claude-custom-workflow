# Evals — harnais léger pour les changements de prompts/skills (charter §11)

But : mesurer l'effet d'une édition de `.claude/agents/*.md`, `.claude/skills/*/SKILL.md` ou du charter,
au lieu de la juger sur la relecture. ~8 scénarios représentatifs suffisent pour voir un impact
(pratique Anthropic : ~20 pour un système de recherche complet ; notre surface est plus petite).

## Quand rejouer

- **Obligatoire** : toute édition **non triviale** d'un fichier de process (>10 lignes, ou changement/suppression
  d'une règle existante) → rejouer les scénarios portant le tag du fichier touché, AVANT et APRÈS l'édition
  (baseline d'abord — c'est le RED du TDD de `superpowers:writing-skills`).
- **Dispensé** : correction factuelle pure (chemin, nombre, nom de skill) ≤10 lignes.

## Comment rejouer un scénario

1. Spawner un subagent **frais** (type indiqué par le scénario), prompt = le bloc `### Prompt` verbatim.
   Contexte propre : pas d'historique de la session courante, pas d'indication du critère attendu.
2. Laisser l'agent finir. Récupérer sa sortie + les artefacts observables (fichiers, commits, commandes lancées).
3. **Juge unique, un seul appel** (pattern Anthropic — plus cohérent que les panels pour des sorties longues) :
   un subagent distinct reçoit la sortie + les artefacts + la grille du scénario, et rend :

```
score: 0.0-1.0 par critère (mécanique : le critère est observé ou pas)
verdict: PASS si tous les critères "bloquants" = 1.0, sinon FAIL
evidence: 1 ligne par critère — la preuve observée (commande, fichier, citation), pas une impression
```

4. Résultat consigné dans le rapport du chantier (pas de fichier de résultats qui grossit — le git log
   du chantier est l'historique). Une édition qui fait passer un scénario de PASS à FAIL ne merge pas.

## Anti-contamination

- Le subagent évalué ne doit jamais voir la grille de critères ni savoir qu'il est évalué.
- Scénarios à artefacts (worktree, commits) : les jouer dans un worktree jetable `evals/<scenario-id>`,
  supprimé après jugement — jamais dans un worktree de chantier réel.
- Émulateur requis → pool partagé habituel (`mg_claim_port`), jamais un scénario d'éval en parallèle
  d'une validation visuelle réelle.

Scénarios : `scenarios.md` (tags : `git-workflow`, `i18n`, `design-system`, `nav`, `debugger`, `inspector`, `online`, `scope`).
