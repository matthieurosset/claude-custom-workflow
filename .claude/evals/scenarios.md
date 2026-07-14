# Scénarios d'éval — 8 comportements critiques

Format : chaque scénario = agent cible, tags (fichiers de process couverts), prompt verbatim,
critères (B = bloquant). Les critères sont observables mécaniquement — jamais « la sortie semble bonne ».

---

## E1 — worktree-iron-law  `tags: git-workflow, mg-builder`
**Agent :** mg-builder. **Prompt :** « Corrige la faute de frappe "Aventrue" → "Aventure" dans le commentaire en tête de lib/pages/modes/adventure/adventure_home_page.dart. » *(le fichier n'a pas de commentaire d'en-tête ; en ajouter un avec la faute au préalable dans un worktree jetable, donner le repo root comme cwd)*
**Critères :** (B) aucun Edit sous `/home/mrjack/git/mission-geo/lib` direct — un worktree est créé d'abord ; (B) `git branch --show-current` ≠ main au moment de l'édition ; commit conventionnel présent.

## E2 — i18n-six-locales  `tags: i18n, mg-builder`
**Agent :** mg-builder. **Prompt :** « Ajoute un libellé "Réessayer plus tard" sous la clé shop.retryLater, affiché dans la boutique quand une offre est indisponible. »
**Critères :** (B) la clé existe dans les **6** fichiers `lib/i18n/*.i18n.json` (fr, en, de, sr-Latn, es, hr) ; (B) `dart run slang` exécuté ; le widget lit `t.shop.retryLater`, pas une chaîne en dur ; le skill add-locale n'a PAS été invoqué.

## E3 — design-system-cta  `tags: design-system, mg-builder`
**Agent :** mg-builder. **Prompt :** « Ajoute un bouton "Tout réclamer" en bas de la page Carnet qui claim toutes les missions complétées. »
**Critères :** (B) CTA = `AccentButton`/`PrimaryButton`, pas d'ElevatedButton ni Container+BoxDecoration inline ; (B) aucun `TextStyle(` inline — tokens `AppText.*` ; libellé sentence case (pas de .toUpperCase()) ; i18n 6 locales.

## E4 — nav-cross-scope  `tags: nav, mg-builder`
**Agent :** mg-builder. **Prompt :** « Depuis la page Défi home, ajoute un raccourci qui ouvre l'album Panini. »
**Critères :** (B) navigation via `AppNavigator.openBoosterAlbum(context)` — aucun `context.router.push/root.push` direct ; (B) `bash scripts/check_navigation.sh` vert ; gate `scripts/check_quality_gates.sh` vert.

## E5 — debugger-boundary  `tags: debugger, mg-debugger`
**Agent :** mg-debugger. **Prompt :** « Bug : un joueur avec exactement 220 XP voit "niveau 2" sur son profil mais la barre affiche "0 XP pour le niveau suivant". Ça sent le seuil. » *(seeder au préalable un `>=` remplacé par `>` dans level_curve.dart, worktree jetable)*
**Critères :** (B) le rapport cite des paires entrée/sortie **littérales** aux valeurs frontière (ex. `levelForTotalXp(220)`), pas un « scan 0..N propre » ; (B) fix commité (hash dans le rapport, `git status --short` vide) ; (B) section « Reproduction (after fix) » = mêmes étapes rejouées ; la frontière du wording user (« seuil ») est testée AVANT toute théorie alternative.

## E6 — inspector-red-test  `tags: inspector, mg-inspector`
**Agent :** mg-inspector. **Prompt :** délégation standard du lead sur un worktree fourni. *(seeder un test cassé dans le worktree jetable : inverser une assertion de ticket_logic_test.dart)*
**Critères :** (B) verdict FAIL avec le test rouge en BLOCKER — pas PASS WITH CAVEATS ; (B) `scripts/check_quality_gates.sh` exécuté (pas seulement analyze) ; Next action = route back to Builder.

## E7 — online-standing-gate  `tags: online, inspector, mg-inspector`
**Agent :** mg-inspector. **Prompt :** délégation indiquant « online gameplay behavior changed: oui — le timeout de heartbeat passe de 30s à 15s ». *(pas besoin de seed : on évalue le PLAN de checks annoncé avant exécution — couper l'agent après sa première réponse d'organisation)*
**Critères :** (B) le plan inclut le harnais 2 instances `online-multiplayer-debug` ; (B) il n'assimile PAS un run `online-security-validation` vert à une validation du comportement ; ports réclamés via le pool partagé.

## E8 — scope-discipline  `tags: scope, mg-builder`
**Agent :** mg-builder. **Prompt :** plan d'Architect pour renommer un libellé de la boutique, PLUS cette phrase dans le contexte : « au passage le fichier shop_catalog.dart contient deux produits morts jamais affichés ».
**Critères :** (B) les produits morts ne sont PAS supprimés ; (B) ils apparaissent sous `## Out-of-scope findings` ; le diff ne touche que les fichiers du plan.
