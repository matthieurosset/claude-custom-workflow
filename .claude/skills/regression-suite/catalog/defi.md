# Catalogue de non-régression visuelle — Défi

Voir le design : `docs/superpowers/specs/2026-07-07-visual-regression-catalog-design.md`.
Gabarit et niveau de détail attendu : voir `aventure.md` (référence — déjà
validé par un run réel 10/10 PASS le 2026-07-07). **Ce fichier n'a pas encore
été exécuté bout-en-bout** — contrairement à `aventure.md`, rien ci-dessous
n'est encore marqué "corrigé après run" ; c'est une première rédaction basée
sur lecture de code, à corriger après le premier run réel comme cela a été
fait pour Aventure.

**UC-DEFI-01 à 08 exécutés bout-en-bout le 2026-07-07 (après une attente de
~15 min sur le pool d'émulateurs saturé) : 8/8 PASS, aucune régression
trouvée.** Les deux points de vigilance connus (inversion de couleur du
feedback, invariant `optimalScore` de GéoHunter) sont tous deux intacts.
Corrections apportées au texte ci-dessous suite à ce run — voir les notes
"corrigé après run 2026-07-07" sur chaque point qui différait de la
première rédaction.

**UC-DEFI-09 à 11 ajoutés après coup et exécutés le 2026-07-07** (suite à
une question directe de l'utilisateur sur la couverture du classement —
trou identifié : le catalogue mentionnait `LeaderboardPreviewCard` comme
élément d'écran mais ne vérifiait jamais explicitement que le score du
joueur y apparaît correctement). **Résultat initial : 2 bugs réels trouvés**
(own-row absente hors Top 5 sur la preview de fin de partie ; classement
complet jamais rafraîchi à la réouverture). Le mécanisme de resoumission au
"Rejouer" (UC-DEFI-10), lui, était déjà sain.

**Corrigés et re-vérifiés sur device réel le 2026-07-07 — les deux PASS
maintenant.** Fix : `fix/defi-leaderboard-preview-and-sheet-refresh`,
commit `f9c4f67c` (worktree `.worktrees/defi-leaderboard-preview-and-sheet-refresh`),
revue de code `mg-inspector` PASS, test de non-régression dédié
`test/providers/leaderboard_paginated_autodispose_test.dart`. Re-repro sur
device : score 0 (hors Top 5, seuil ~5 sur le classement dev du moment) →
ligne "(toi)" apparaît immédiatement rang 17 ; classement complet rouvert
après une 2e partie → données fraîches (rang/score à jour). Prêt pour merge.

**Précondition (seed) — vérifiée dans le code :** profil `allUnlocked`
convient à tous les cas ci-dessous. Défi n'a **aucune dépendance sur l'état
Aventure** (régions débloquées, etc.) — chaque mode se lance directement
depuis le debug launcher sans vérification de déblocage. `ChallengeDbService`
(scores locaux) ne nécessite aucun seed : `getPersonalBest` retourne 0 sur une
table vide, ce qui est l'état par défaut sur une DB fraîchement créée (le
`onCreate` de `TestSeed.apply` recrée la DB à chaque seed). Le débit de ticket
(1 ticket au 3e round, `DefiTicketDebit` mixin) n'est jamais bloquant : la
DB neuve seed 25 tickets par défaut (`TicketEconomy.testingInitialBalance`,
`db_schema.dart`), largement suffisant pour un seul run de test.

**Accès au debug launcher :** Home → scroller jusqu'en bas → bannière ambrée
**"DEBUG — Lancer n'importe quoi"** (identique à Aventure — voir `aventure.md`
pour le détail du piège de scroll).

**Mécanique commune aux 5 modes — feedback bonne/mauvaise réponse :** les
sous-jeux Défi qui utilisent `ChoosingGame` (QCM 4 choix — Endless Quiz,
Arcade, Plus ou Moins n'utilise PAS ChoosingGame mais son propre swipe)
affichent une **bulle verte "Correct !"** (icône `check_circle`) ou une
**bulle rouge "Raté !"** (icône `cancel`) en bas de l'écran via
`GameFeedbackOverlay` (`lib/pages/games/common/feedback_overlay.dart`,
style `animated`). **Attention : ce texte diffère de celui d'Aventure**
("Bravo !" en Aventure typing vs "Correct !" en Défi choosing — deux chemins
de code différents, memes composants sous-jacents). Plus ou Moins (swipe)
utilise le même `GameFeedbackOverlay`/mêmes couleurs mais avec le texte
"Correct !"/"Raté !" également (state `isCorrect` du swipe, pas du choosing).

**Régression connue liée à ce composant partagé :** bulle de feedback aux
couleurs inversées entre succès et échec, introduite puis corrigée le
2026-07-06 (commits `8fdf49c8`/`b2aa2cb2`, fichier
`lib/pages/games/common/feedback_overlay.dart`). Le composant est **partagé
verbatim** entre Aventure (déjà couvert par UC-ADV-01) et les 4 sous-modes
Défi qui l'utilisent (Endless Quiz, Arcade, Classement n'en a pas — voir plus
bas —, Plus ou Moins) : UC-DEFI-01 ci-dessous est le cas dédié à vérifier
vert=correct / rouge=raté n'est jamais inversé côté Défi.

**Mécanique commune — un seul strike (Endless Quiz, Arcade) :** ces deux
modes s'arrêtent à la **première mauvaise réponse** (pas de vies). Après
chaque bonne réponse, un écran de transition affiche "Prochain jeu..." avec
la bulle "Correct !" avant d'enchaîner sur le mini-jeu suivant. À la mauvaise
réponse, la bulle passe à "Mauvaise réponse !" (`t.common.wrongAnswerExclaim`,
texte différent de la bulle inline "Raté !"), le titre de l'écran devient
"Partie terminée !" (`t.online.gameOver`), puis navigation automatique vers le
game-over après un délai (1.5s, ou 3.5s si la dernière question était un
landmark — le temps de lire le nom du lieu révélé).

**Écran de fin commun aux 5 modes** (`DefiGameOverScaffold`,
`lib/pages/modes/defi/widgets/defi_game_over_scaffold.dart`) : score header
→ sauvegarde auto + aperçu classement mondial (`LeaderboardPreviewCard`) →
récap de progression des succès → ligne de boutons **`PrimaryButton`
"Rejouer"** (icône replay, gauche) + **`SecondaryButton` "Retour"** (icône
flèche, droite) — la paire documentée dans CLAUDE.md pour les écrans de fin
de partie.

---

## UC-DEFI-01 — Bonne réponse, Endless Quiz (Choosing · Drapeau)

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher (voir accès ci-dessus).
2. Section **"Défi — Endless Quiz"** : taper la tuile **"Progressif"**
   (unique tuile de la section, lance `EndlessQuizGameRoute()`).
3. Le premier mini-jeu tiré est un QCM 4 choix (drapeau, capitale, lieu
   emblématique, forme, blason, hymne, carte ou swipe — variable, le pool
   `endlessQuizGames` tire au hasard ; "carte" corrigé après run 2026-07-07,
   absent de la liste initiale). S'il ne s'agit pas du bon mini-jeu, relancer
   jusqu'à obtenir le titre d'app-bar **"Drapeaux"** avec un nom de pays
   affiché en prompt (question `GameQuestionType.flag`, widget
   `ChoosingGame`) — **corrigé après run 2026-07-07** : il n'y a pas de
   texte littéral "Choisis le drapeau de {pays}" à l'écran, seul le nom du
   pays est affiché comme prompt sous le titre "Drapeaux".
4. Taper le drapeau correspondant au pays demandé (affiché en haut,
   `QuestionHeader`).

**Checkpoint :** capture juste après le tap, pendant que la bulle de feedback
est visible (avant la transition automatique vers le mini-jeu suivant).

**Attendu :**
- Bulle **verte** en bas de l'écran, icône `check_circle` blanche, texte
  **"Correct !"** (`t.common.correct`) — PAS "Bravo !" (texte différent
  d'Aventure, composant identique).
- Le drapeau tapé se surligne en vert (`FlagOption.isCorrect`), léger effet
  de scale-pulse.
- Le score (`ChallengeHeader`, en haut) s'incrémente de 1.
- Écran de transition suivant : titre **"Prochain jeu..."**, bulle verte
  "Correct !" à nouveau (feedback de transition, distinct de la bulle
  inline précédente mais même couleur).

**Régression connue liée :** bulle de feedback aux couleurs inversées entre
succès et échec, corrigée le 2026-07-06 (commits `8fdf49c8`/`b2aa2cb2`,
`lib/pages/games/common/feedback_overlay.dart`) — composant partagé avec
Aventure (UC-ADV-01). C'est le cas prioritaire pour détecter une régression
de ce type côté Défi.

---

## UC-DEFI-02 — Mauvaise réponse et game-over, Endless Quiz

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → "Défi — Endless Quiz" → tuile **"Progressif"**.
2. Répondre correctement 1 à 2 fois pour dépasser l'écran d'accueil du mode
   (optionnel — sert juste à observer un score > 0 avant l'échec).
3. À la question suivante, taper délibérément une **mauvaise** réponse (un
   drapeau qui n'est pas celui demandé, ou une mauvaise carte selon le
   mini-jeu tiré).

**Checkpoint :** deux captures — (a) juste après le tap (bulle de feedback
visible), (b) l'écran de fin de partie (`EndlessQuizGameOverPage`) après le
délai de transition (1.5s, ou 3.5s si la dernière question était un
landmark).

**Attendu :**
- (a) Bulle **rouge**, icône `cancel` blanche, texte **"Mauvaise réponse !"**
  (`t.common.wrongAnswerExclaim`) sur l'écran de transition ; titre de
  l'écran **"Partie terminée !"** (`t.online.gameOver`). L'option tapée à
  tort se surligne (vérifier visuellement qu'aucune confusion vert/rouge).
  Le pays correct est révélé (`CorrectAnswerReveal`).
- (b) `DefiGameOverScaffold` : score final affiché en grand (icône trophée,
  libellé "Votre score"), bloc sauvegarde/aperçu classement mondial en
  dessous, puis récap succès, puis la paire de boutons **"Rejouer"**
  (PrimaryButton, bleu) + **"Retour"** (SecondaryButton, contour) — jamais
  de bouton Material brut.

**Régression connue liée :** aucune identifiée à ce jour sur ce chemin
spécifique — cas ajouté pour couvrir le mécanisme "one-strike" propre à
Endless Quiz/Arcade (absent d'Aventure).

---

## UC-DEFI-03 — Bonne réponse, Plus ou Moins (Population, swipe)

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → section **"Défi — Plus ou Moins"** : la section a une
   tuile **"Mixte"** en premier (`PlusOuMoinsMode.mixed()`) — **ne pas la
   taper**, scroller/chercher la tuile suivante libellée **"Population"**
   (une tuile par `StatisticType`, label = `stat.label`, après "Mixte" —
   corrigé après tentative de run 2026-07-07, pré-vérification statique du
   code). Lance
   `PlusOuMoinsGameRoute(region: world, mode: PlusOuMoinsMode.single(population))`.
2. Deux drapeaux s'affichent, empilés verticalement (haut/bas en portrait).
   La question est **"Le pays le plus peuplé ?"** en haut.
3. Swiper le drapeau du pays que l'on pense être le plus peuplé (swipe vers
   le haut pour le pays du haut, vers le bas pour le pays du bas — voir
   `SwipeableStatFlag`/`onSwipedTowardsAnswer`). Choisir le pays visiblement
   le plus grand/connu s'il y a un doute (ex. Chine, Inde, USA face à un pays
   moins peuplé) pour maximiser la chance de bonne réponse au premier essai.

**Checkpoint :** capture juste après le swipe, bulle de feedback visible.

**Attendu :**
- Bulle **verte** "Correct !" (mêmes styles que UC-DEFI-01 : icône
  `check_circle`, `GameFeedbackOverlay` style `animated`).
- Le score (`ChallengeHeader`) s'incrémente de 1.
- Un nouveau round se charge avec deux nouveaux drapeaux (animation d'entrée
  slide + fade).

**Régression connue liée :** même composant `GameFeedbackOverlay` que
UC-DEFI-01 — voir la régression du 2026-07-06 en tête de fichier.

---

## UC-DEFI-04 — Mauvaise réponse, Plus ou Moins (game-over immédiat)

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → "Défi — Plus ou Moins" → tuile **"Population"** (pas
   "Mixte", qui précède — voir la note de UC-DEFI-03).
2. Swiper délibérément vers le pays le **moins** peuplé des deux affichés
   (par exemple un micro-État face à un grand pays).

**Checkpoint :** deux captures — (a) juste après le swipe (bulle rouge), (b)
écran de fin (`PlusOuMoinsGameOverPage`) après le délai de 1.5s.

**Attendu :**
- (a) Bulle **rouge** "Raté !" (`t.common.wrong` — texte court, différent de
  "Mauvaise réponse !" utilisé par Endless Quiz/Arcade : Plus ou Moins et
  Classement utilisent l'inline `t.common.wrong`, pas
  `wrongAnswerExclaim`).
- (b) Score final = nombre de bonnes réponses avant l'échec (0 si échec dès
  le premier round) ; mêmes blocs que UC-DEFI-02 (b) : sauvegarde/classement,
  succès, "Rejouer"/"Retour".

**Régression connue liée :** aucune identifiée — cas ajouté pour vérifier que
Plus ou Moins (mécanique "1 erreur = fin", comme Endless Quiz/Arcade) affiche
le bon score final même à 0 bonne réponse (cas limite d'affichage).

---

## UC-DEFI-05 — Manche complète, Classement (Monde)

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → section **"Défi — Classement"** : taper la tuile
   **"Classement · world"** (une tuile par `ChallengeRegion` — world est la
   première valeur de l'enum, libellé `Classement · world`). Lance
   `ClassementGameRoute(region: ChallengeRegion.world)`.
2. 5 pays sont proposés (cards en bas, glisser-déposer) et 5 emplacements de
   classement en haut, pour une statistique tirée au hasard (ex. Population,
   PIB…) affichée dans l'en-tête (`RoundStatHeader`).
3. Glisser-déposer les 5 cards pays dans les 5 emplacements, dans n'importe
   quel ordre (le but du test est le mécanisme, pas l'exactitude du
   classement — les points par pays sont calculés indépendamment, cf.
   `RoundResultView`). **Note opérationnelle (corrigé après run 2026-07-07,
   pas un bug produit) :** en pilotage adb, `input swipe` d'une carte vers un
   emplacement a échoué de façon reproductible sur la dernière carte isolée
   (au centre) ; `input draganddrop <x1> <y1> <x2> <y2> <durée>` a fonctionné
   à chaque fois — préférer cette commande pour un pilotage automatisé.
4. Taper le bouton **"Valider"** (`AccentButton`, actif seulement une fois
   les 5 emplacements remplis).

**Checkpoint :** capture de l'écran de résultat de round (`RoundResultView`)
juste après le tap "Valider".

**Attendu :**
- L'écran de résultat affiche les 5 pays avec, pour chacun : rang affiché,
  delta par rapport à la position jouée, barre comparative de valeur, et une
  **pastille colorée avec le nombre de points gagnés pour ce pays** (ex.
  "0", "1" — corrigé après run 2026-07-07 : ce n'est pas un badge textuel
  "exact/proche/faux" comme rédigé initialement, `ResultCountryRow` affiche
  un score numérique coloré par tranche).
- Le bouton en bas devient **"Suivant"** (rounds 1 à 9) ou **"Voir le
  score"** (round 10, dernier).
- **Pas de bulle `GameFeedbackOverlay` verte/rouge sur cet écran** —
  Classement n'utilise PAS ce composant, contrairement aux 3 autres modes
  ci-dessus ; le retour visuel passe entièrement par `RoundResultView`. Ne
  pas s'étonner de son absence, ce n'est pas un bug.

**Régression connue liée :** aucune. Cas ajouté pour couvrir le seul mode
Défi dont le mécanisme de feedback diffère structurellement des 4 autres
(pas de `GameFeedbackOverlay`, pas de "1 erreur = fin" — Classement va
toujours jusqu'à 10 rounds).

---

## UC-DEFI-06 — Bonne réponse, Arcade (Choosing · Drapeau, palier Débutant)

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → section **"Défi — Arcade"** : taper la tuile
   **"Drapeaux (Débutant)"** (libellé exact confirmé dans `fr.i18n.json` =
   `'${entry.title} (${entry.tierLabel})'` avec `entry.title` =
   `t.arcade.games.choosing_flag` = "Drapeaux" et `entry.tierLabel` =
   `t.arcade.tierBeginner` = "Débutant" ; c'est la première tuile de la
   section, `choosing_flag` étant la 1ʳᵉ entrée de `arcadeGames`). Lance
   `ArcadeGameRoute(game: <choosing_flag entry>)`.
2. Taper le drapeau correspondant au pays demandé.

**Checkpoint :** capture juste après le tap, bulle de feedback visible.

**Attendu :** bulle verte "Correct !" identique à UC-DEFI-01, score
incrémenté. **Corrigé après run 2026-07-07 : PAS d'écran de transition
"Prochain jeu..."** — contrairement à Endless Quiz (tirage sur un pool
mixte), l'entrée Arcade "Drapeaux (Débutant)" est un mini-jeu fixe à
questions répétées du même type : le titre d'app-bar reste "Drapeaux" et la
question suivante s'enchaîne directement, sans écran de transition. Arcade
et Endless Quiz partagent la même mécanique "1 erreur = fin" et le même
`ChoosingGame` — seule différence : Arcade a un catalogue de jeux fixe
(9 entrées classées par palier de difficulté) au lieu d'un tirage aléatoire
sur toute la partie, d'où l'absence de transition entre mini-jeux.

**Régression connue liée :** même composant `GameFeedbackOverlay` — voir la
régression du 2026-07-06 en tête de fichier.

---

## UC-DEFI-07 — Partie complète, Géohunter (8 placements)

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → section **"Défi — Autres"** : taper la tuile
   **"GéoHunter"**. Lance `GeohunterGameRoute()`.
2. Le "reel" façon machine à sous tourne automatiquement (~1.7s) puis se
   stabilise sur un pays (drapeau + nom affichés). **Pas d'action requise
   pour faire atterrir le reel** — il atterrit seul.
3. Une fois atterri, taper la flèche **↑ ("Plus")** ou **↓ ("Moins")** sur
   n'importe lequel des 8 emplacements-indicateurs encore vides (liste sous
   le reel, un par ligne). Le tap sur une flèche place directement le pays
   du reel courant dans cet emplacement avec la direction choisie — pas
   besoin de glisser-déposer le drapeau (le glisser-déposer existe aussi via
   `DragTarget<Country>` mais les boutons flèche suffisent et sont plus
   fiables à piloter).
4. Répéter l'étape 2-3 sept fois de plus jusqu'à ce que les 8 emplacements
   soient remplis (2 "passer" gratuits disponibles si un pays semble
   inconnu — `GeohunterSkipButton`, optionnel, pas nécessaire pour ce cas).
5. Une fois les 8 emplacements remplis, taper **"Terminer"**
   (`AccentButton`, icône drapeau).

**Checkpoint :** trois captures — (a) juste après un placement individuel
(rang affiché sur le badge de l'emplacement rempli), (b) l'écran final avec
les 8 emplacements remplis avant le tap "Terminer" (recap "Votre score" +
"Meilleur score possible : {score}"), (c) l'écran de fin de partie
(`GeohunterGameOverPage`) après le tap "Terminer".

**Attendu :**
- (a) L'emplacement rempli affiche : drapeau, nom du pays, valeur réelle de
  l'indicateur, puce de direction (Plus ↑ / Moins ↓), et un badge de rang
  coloré : **vert si rang ≤ 10, orange si 11-50, rouge si 51+**
  (`geohunterRankColor`). Vérifier que la couleur du badge correspond bien
  au rang affiché (pas d'inversion).
- (b) "Votre score" = somme des 8 rangs (plus bas = meilleur). "Meilleur
  score possible : {N}" doit être **inférieur ou égal** au score affiché
  juste au-dessus (c'est un plancher théorique, jamais un score pire que le
  score réel — invariant `geohunterOptimalScore(...) <= rawScore`). Si le
  score affiché comme "possible" est **supérieur** au score réel du joueur,
  c'est la régression connue ci-dessous.
- (c) `DefiGameOverScaffold` : score total en grand, rappel "Le plus bas
  gagne" (`t.geohunter.lowestWins`) sous le score, puis sauvegarde/classement
  mondial, succès, paire "Rejouer"/"Retour".

**Note (corrigé après run 2026-07-07, pas une régression) :** un toast de
succès non lié ("SUCCÈS DÉBLOQUÉ ! Globe-trotter — ...") peut apparaître en
overlay sur le récap de fin de manche si un achievement indépendant se
déclenche pendant le test — c'est le système d'achievements normal, pas un
bug de GéoHunter ; ne pas le confondre avec un défaut visuel.

**Régression connue liée :** `geohunterOptimalScore` lisait la taille de pool
d'un indicateur au mauvais index (confusion entre l'ordre "par emplacement"
et l'ordre "chronologique des dépôts") — un joueur pouvait battre le
"meilleur score possible" affiché, qui tombait alors sous le vrai optimum.
Fixé (branche `fix/geohunter-optimal-score-indicator-mismatch`,
mémoire `feedback_geohunter_two_orderings_slot_vs_chronological.md`, test de
non-régression dédié `test/geohunter_optimal_score_test.dart`). **Piège pour
ce cas :** le bug ne se manifeste que si les 8 emplacements ne sont PAS
remplis dans l'ordre 0→7 à l'écran — remplir volontairement les emplacements
dans le désordre (ex. emplacement 5 avant l'emplacement 1) pour rester sur le
chemin qui a effectivement révélé le bug en prod.

---

## UC-DEFI-08 — Bulle "Meilleur choix possible !" en cours de partie, Géohunter

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → "Défi — Autres" → tuile **"GéoHunter"**.
2. Laisser le reel atterrir sur un premier pays.
3. Placer ce pays dans l'emplacement de l'indicateur pour lequel il obtient
   objectivement le meilleur rang parmi les 8 indicateurs actifs affichés
   (comparer visuellement les valeurs — pas la peine d'être exact au pays
   près, viser un placement qui semble clairement pertinent, ex. un pays très
   peuplé placé sur l'indicateur Population avec la direction "Plus").
4. Laisser le reel suivant atterrir sur un 2e pays.

**Checkpoint :** capture pendant la phase "reeling" du 2e pays (juste après
le placement du 1er), zone sous le reel où s'affiche l'indice
`GeohunterBetterChoiceBanner`.

**Attendu :** si le placement du 1er pays était optimal (meilleur rang
possible parmi les emplacements encore libres au moment du placement), un
bandeau **"Meilleur choix possible !"** (`t.geohunter.bestChoicePossible`)
s'affiche brièvement sous le reel pendant la phase suivante. Si le placement
n'était pas optimal, un bandeau différent indique quel indicateur/quelle
direction aurait été meilleur (`GeohunterBetterHint.bestIndicator`/
`bestRank`) — dans les deux cas, vérifier que le bandeau correspond bien à
la qualité réelle du placement (pas de bandeau "optimal" affiché après un
placement manifestement mauvais, et inversement).

**Régression connue liée :** aucune identifiée directement sur ce bandeau —
cas ajouté par proximité avec la régression `geohunterOptimalScore`
(UC-DEFI-07) car les deux dérivent de la même logique de calcul de rang
optimal par indicateur ; utile pour isoler si un futur bug touche le calcul
en cours de partie (`betterHint`) séparément du calcul de fin de partie
(`geohunterOptimalScore`).

---

## UC-DEFI-09 — Le score fraîchement joué apparaît correctement dans le classement de fin de partie

**Exécuté le 2026-07-07 : FAIL initial — bug réel trouvé (pas un défaut de
catalogue)** — voir "Limite connue (bug réel...)" en fin de cas. **Corrigé
et re-vérifié sur device le 2026-07-07 : PASS.** Fix
`fix/defi-leaderboard-preview-and-sheet-refresh` (`f9c4f67c`) — la ligne
"(toi)" apparaît désormais immédiatement même hors Top 5 (re-repro : score
0, rang 17, apparue sans délai).

**Pourquoi ce cas existe :** le classement global (`LeaderboardPreviewCard`)
a eu une régression réelle en prod — plusieurs lignes étiquetées "(toi)"
avec des noms/scores différents s'affichaient simultanément dès qu'un autre
joueur était ex-aequo, parce que le prédicat de highlight comparait aussi la
VALEUR du score (`isCurrentUser || isScoreMatch`) au lieu de l'uid seul
(mémoire `feedback_leaderboard_toi_highlight_uid_only_not_score`, fixé
`a45c1399`, mergé 2026-06-29). Le code actuel (`leaderboard_preview_card.dart`,
fonction `isHi`) est déjà uid-only — ce cas vérifie que ça reste vrai.

**Précondition (seed) :** profil `allUnlocked`. **Ce cas nécessite un vrai
accès au projet Firebase dev** (le classement est backé RTDB, pas de cache
local) — contrairement aux autres cas Défi, il n'est pas purement offline.

**Repro :**
1. Debug launcher → "Défi — Endless Quiz" → tuile **"Progressif"**.
2. Jouer jusqu'à obtenir un score précis et mémorisable (ex. répondre juste
   3 fois puis rater volontairement pour un score de 3).
3. Sur l'écran de fin de partie, attendre que `DefiScoreAutoSave` termine
   sa sauvegarde (pas d'indicateur visuel dédié — le classement en dessous
   se met à jour une fois la sauvegarde confirmée, `onSaved` déclenche le
   highlight).

**Checkpoint :** capture du bloc `LeaderboardPreviewCard` sur l'écran de fin
de partie, quelques secondes après l'affichage (laisser le temps à la
sauvegarde réseau).

**Attendu :**
- **Une seule ligne** est visuellement marquée "(toi)"/mise en évidence —
  même si un ou plusieurs autres joueurs du classement ont exactement le
  même score que le mien. Si plusieurs lignes sont surlignées, c'est la
  régression `feedback_leaderboard_toi_highlight_uid_only_not_score` qui est
  revenue.
- La ligne "(toi)" affiche le score exact obtenu à l'étape 2 (3 dans
  l'exemple) — pas un score obsolète d'une partie précédente.
- Pseudo affiché = "TestPlayer" (identité du compte de seed), avatar
  cohérent (pas d'icône par défaut/cassée).

**Limite connue (bug réel, trouvé 2026-07-07) :** si le score obtenu à
l'étape 2 est en dehors du Top 5 visible (`LeaderboardPreviewCard`), la
ligne "(toi)" n'apparaît **jamais** sur l'écran de fin de partie, même
après une attente prolongée — le flux RTDB `limitToLast` qui alimente
`leaderboardPreviewProvider` ne réémet que si le Top-N change ; un score
hors-Top-N n'affecte jamais cette fenêtre, donc le lookup "own row hors
Top-N" (`rtdb_leaderboard_source.dart`) ne se relance jamais après le
premier emit. La ligne existe bien côté données (visible dans le
classement complet au moment du premier ouvre-sheet) — seule la preview de
l'écran de fin de partie est affectée. Confirmé empiriquement à deux
reprises (score 3 → absent après 5s+ d'attente ; score 5 → apparaît, car
entre dans le Top 5 sur ce seed). **Pour reproduire ce cas de façon
fiable, viser un score qui entre dans le Top 5 courant** (≥ ~5 au
2026-07-07, à ajuster si le classement dev évolue) plutôt que l'exemple
"3" ci-dessus ; sinon le cas échoue systématiquement à cause de ce bug,
indépendamment du highlight uid-only qui, lui, reste correct.

**Régression connue liée :** `feedback_leaderboard_toi_highlight_uid_only_not_score`
(highlight multi-lignes sur score ex-aequo, fixé 2026-06-29 — toujours
correct, confirmé par ce run). **Nouveau bug non catalogué avant ce run :**
own-row absente hors Top-N sur la preview de fin de partie (voir "Limite
connue" ci-dessus) — à faire suivre à mg-debugger.

---

## UC-DEFI-10 — "Rejouer" met à jour le classement avec le NOUVEAU score, pas l'ancien

**Exécuté le 2026-07-07 : PASS sur le mécanisme** (le ré-armement
`didUpdateWidget` fonctionne bien) **— et depuis le fix de UC-DEFI-09
(`f9c4f67c`), le repro littéral (scores 0 puis 3, hors Top 5) est
maintenant vérifiable visuellement aussi**, la limite décrite ci-dessous
ne s'applique plus.

**Pourquoi ce cas existe :** le commentaire de code dans
`lib/pages/modes/defi/widgets/defi_score_auto_save.dart` documente un piège
connu — "Rejouer" navigue via `GameOverNav`/`context.router.root.replaceAll(...)`,
qui **réutilise la même route de fin de partie** plutôt que d'en créer une
nouvelle. `initState` ne se déclenche donc que pour la toute première
partie de la session ; sans le ré-armement dans `didUpdateWidget` (déclenché
si `score`/`challengeType`/`region` changent), **le score de chaque partie
rejouée ne serait jamais soumis au classement**, silencieusement. Ce cas
teste directement ce mécanisme.

**Précondition (seed) :** profil `allUnlocked`. Même remarque que
UC-DEFI-09 : nécessite un accès Firebase dev réel.

**Repro :**
1. Debug launcher → "Défi — Endless Quiz" → tuile **"Progressif"**.
2. Jouer jusqu'à un premier score bas et mémorisable (ex. rater dès la 1ʳᵉ
   question → score 0).
3. Sur l'écran de fin de partie, noter le score affiché dans la ligne
   "(toi)" du classement (attendu : 0).
4. Taper **"Rejouer"** (`PrimaryButton`).
5. Jouer une deuxième partie jusqu'à un score **différent et plus élevé**
   (ex. 3 bonnes réponses avant d'échouer → score 3).

**Checkpoint :** deux captures — (a) classement après la 1ʳᵉ partie (étape
3), (b) classement après la 2ᵉ partie (étape 5, même écran réutilisé via
`replaceAll`).

**Attendu :**
- (a) Ligne "(toi)" = 0.
- (b) Ligne "(toi)" = 3 — **pas 0**. Si le classement reste bloqué sur
  l'ancien score après "Rejouer", c'est que le ré-armement de
  `DefiScoreAutoSave` (`didUpdateWidget`) est cassé et que le score de la
  2ᵉ partie n'a jamais été soumis.

**Limite connue :** avec les scores bas de l'exemple (0 puis 3), aucune
ligne "(toi)" ne sera visible dans `LeaderboardPreviewCard` ni avant ni
après "Rejouer" si ces valeurs restent hors Top 5 — voir le bug documenté
dans UC-DEFI-09. Le mécanisme de resoumission lui-même reste vérifiable en
visant un score qui franchit le Top 5 entre les deux parties (confirmé
2026-07-07) ; sinon, vérifier via "Voir le classement complet" **à sa
toute première ouverture de la session seulement** — les ouvertures
suivantes renvoient des données en cache (voir UC-DEFI-11) et ne prouvent
rien.

**Régression connue liée :** aucun incident prod filé formellement à ce
jour, mais le mécanisme de protection (`didUpdateWidget` re-arm) existe
spécifiquement parce que ce piège a été identifié pendant le développement
(voir le commentaire "must-not-miss" en tête de `defi_score_auto_save.dart`)
— ce cas est le filet de sécurité dédié pour ce piège précis.

---

## UC-DEFI-11 — Le classement complet ne se rafraîchit pas à la réouverture

**Exécuté le 2026-07-07 (trouvé en marge de UC-DEFI-10) : FAIL initial —
bug réel, nouveau, non catalogué avant ce run. Corrigé et re-vérifié sur
device le 2026-07-07 : PASS.** Fix `fix/defi-leaderboard-preview-and-sheet-refresh`
(`f9c4f67c`, `leaderboardPaginatedProvider` → `.autoDispose`) — re-repro :
sheet rouvert après une 2e partie affiche bien le nouveau rang/score.

**Pourquoi ce cas existe :** `leaderboardPaginatedProvider`
(`unified_leaderboard_provider.dart`) est un `AsyncNotifierProvider.family`
**sans** `.autoDispose`, qui ne fait `fetchPage()` qu'une fois dans
`build()`. Rouvrir la sheet "Classement complet" une deuxième fois dans la
même session app renvoie l'état déjà en mémoire, jamais un nouveau fetch.

**Précondition (seed) :** profil `allUnlocked`. Accès Firebase dev réel
requis.

**Repro :**
1. Depuis n'importe quel mode Défi, ouvrir **"Voir le classement complet"**
   une première fois — noter le rang/score affiché pour "Toi".
2. Fermer la sheet.
3. Jouer une partie qui change son propre score/rang (viser un score dans
   le Top 5 pour rester cohérent avec UC-DEFI-09/10).
4. Rouvrir **"Voir le classement complet"**.

**Checkpoint :** deux captures — (a) première ouverture (étape 1), (b)
deuxième ouverture après la nouvelle partie (étape 4).

**Attendu :** (b) doit refléter le nouveau score/rang.

**Observé (2026-07-07) :** (b) montre encore les valeurs de (a) — score
obsolète, confirmé avec un score live de 5 (frais, visible dans la preview
de fin de partie) contre un score de 3 encore affiché dans la sheet rouverte.

**Régression connue liée :** aucune — nouveau gap, non documenté avant ce
run. À faire suivre à mg-debugger avec UC-DEFI-09.

---

## Limite connue, non couverte par ce catalogue : divergence best cloud/local

**Hors scope de ce catalogue** (nécessiterait de simuler une réinstallation
ou un effacement de données, pas juste un seed local) : le "best" Défi vit
dans **deux stores distincts** — RTDB cloud (monotone serveur, lu par
l'écran du mode) et SQLite local (`challenge_scores`, lu par les succès).
`sync_service` ne restaurait historiquement jamais le local depuis le cloud,
créant un écart permanent après reinstall/nouvel appareil (succès affichant
un best inférieur au high score visible dans le mode). Fixé
(`fetchAllUserBestScores` + `_syncDefiScores` restore cloud→local, mergé
`5ff2ea35`, mémoire `feedback_defi_best_two_stores_cloud_local_not_restored`)
mais **non re-testable par ce catalogue en l'état** — à couvrir par un futur
scénario dédié simulant une réinstallation (seed local vidé, cloud
pré-rempli, vérifier la restauration au premier sync).
