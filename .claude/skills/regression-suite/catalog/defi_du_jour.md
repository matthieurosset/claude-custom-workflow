# Catalogue de non-régression visuelle — Défi du jour

Voir le design : `docs/superpowers/specs/2026-07-07-visual-regression-catalog-design.md`.
Gabarit et niveau de détail attendu : voir `aventure.md` (référence — déjà
validé par un run réel 10/10 PASS le 2026-07-07).

**Exécuté bout-en-bout le 2026-07-07 : 5/5 PASS, aucun bug fonctionnel
trouvé.** La synchronisation entre écran de fin de partie, page dédiée et
tuile Home a tenu à travers reroll et reset, sans redémarrage d'app —
zone habituellement fragile dans ce projet, confirmée saine ici.

Ce fichier couvre uniquement l'**orchestration quotidienne** (`lib/pages/modes/defi/daily/`,
`DailyChallengeDbService`, `DailyChallengeCycleService`, `dailyChallengeProvider`) —
pas les mécaniques internes des 5 jeux sous-jacents (Classement, Plus ou
Moins, GéoHunter, Endless Quiz, Arcade), déjà couvertes par `defi.md`. Ne pas
dupliquer les cas de `defi.md` (bulle verte/rouge, écran de fin commun, etc.)
— jouer la partie sous-jacente en suivant `defi.md` quand un cas ci-dessous
demande d'aller jusqu'au game-over.

**Précondition (seed) — vérifiée dans le code :** profil `allUnlocked`
convient à tous les cas ci-dessous. La table `daily_challenge_progress`
(v14, clé primaire `period_key`) n'est **pas pré-remplie** par `TestSeed.apply`
— elle est vide sur une DB fraîche quel que soit le profil, exactement comme
pour `ChallengeDbService`. La première ouverture de `dailyChallengeProvider`
(`lib/providers/daily_challenge_provider.dart`) résout et persiste le défi du
jour à la volée (`DailyChallengeCycleService.resolveDaily` + `createChallenge`,
`INSERT OR IGNORE` donc idempotent). Le lancement d'une partie coûte **1
ticket** (`TicketGatedStartButton`, même gate que les autres modes Défi) — la
DB neuve seed 25 tickets par défaut (`TicketEconomy.testingInitialBalance`),
largement suffisant. **Corrigé après run 2026-07-07 :** le solde
réellement observé à l'écran peut différer de 25 (ex. 30, si le bonus de
connexion quotidienne +5 a déjà été crédité avant d'atteindre cet écran) —
ne pas figer une valeur exacte, vérifier plutôt la cohérence (−1 ticket
par lancement de partie) plutôt qu'un chiffre précis.

**Accès au debug launcher :** Home → scroller jusqu'en bas → bannière ambrée
**"DEBUG — Lancer n'importe quoi"** (identique à Aventure/Défi). Section
**"Défi — Autres"**, 3 tuiles pertinentes :
- **"Défi du jour"** (`Icons.today_outlined`) → `context.router.push(const DailyChallengeRoute())`
  — push tab-scopé (conforme aux règles de navigation : `DailyChallengeRoute`
  n'est pas un canvas de jeu, contrairement aux 5 routes `Daily*GameRoute`
  qui sont poussées en root via `AppNavigator.playDailyChallenge*`).
- **"Défi du jour : changer"** (`Icons.casino`) → supprime la ligne DB du jour
  (`DailyChallengeDbService.deleteChallengeForTesting`) **et** efface tout le
  sac mélangé (`DailyChallengeCycleService.resetCycleForTesting`, clé
  SharedPreferences `daily_challenge_cycle_v1`), puis invalide
  `dailyChallengeProvider`/`dailyChallengeProgressProvider` — la prochaine
  lecture retire un nouveau défi **au hasard parmi les 5 modes** (pas de
  garde anti-répétition inter-appel ici, contrairement au cas de
  ré-mélange interne du sac — une répétition du même mode par pur hasard
  ~1/5 est possible, voir UC-DEFIJOUR-04).
- **"Défi du jour : reset score"** (`Icons.restart_alt`) → supprime **seulement**
  la ligne DB (donc `best_score`/`completed_at` repartent à zéro) **sans**
  toucher au sac mélangé — le commentaire du code est explicite : la garde
  d'idempotence de `resolveDaily` reconstruit alors **le même** défi
  (même mode + même variante) pour la même clé de période, contrairement à
  "changer" ci-dessus. C'est le contraste exact que UC-DEFIJOUR-05 doit
  vérifier.

**Entrée en navigation réelle (hors debug launcher) :** la Home affiche aussi
une tuile "Défi du jour" (`lib/pages/home/page.dart`, `_DailyChallengeTileContent`)
qui pousse la même `DailyChallengeRoute` et lit les deux mêmes providers —
un bon point de contrôle croisé pour une régression de provider figé (cf.
mémoire `feedback_flush_at_layout_dirty_provider_during_layout_build` /
`feedback_riverpod_invalidate_listenerless_kills`) : après un "changer" ou un
"reset score" côté debug launcher, la tuile Home doit refléter le même état
que la page dédiée sans nécessiter de redémarrage de l'app.

**Récompense :** toujours exactement 1x `BoosterTier.silver`, créditée dans
l'inbox récompenses (`rewardInboxProvider`) au moment précis où la cible est
atteinte pour la première fois du jour (`DailyChallengeResultCard._tryRecord`,
idempotent — ne recrédite jamais sur une relecture de l'écran de fin après
victoire déjà enregistrée).

---

## UC-DEFIJOUR-01 — Lancement et framing du défi du jour

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → section "Défi — Autres" → tuile **"Défi du jour"**.
2. La page `DailyChallengePage` s'affiche (app bar `TransparentAppBar`,
   titre "Défi du jour").

**Checkpoint :** capture de la page juste après chargement (une seule
capture suffit, tout est synchrone après résolution du provider).

**Attendu :**
- Une carte de règles affiche un des 5 libellés de mode
  (`dailyChallengeTypeLabel` → "Classement" / "Plus ou Moins" / "Géohunter" /
  "Endless Quiz" / "Arcade") — jamais de texte vide/`null`/`Object`.
- Une phrase d'objectif cohérente avec le mode (`t.daily.targetClassement`
  "Atteins 110 points sur 150.", `targetPlusOuMoins`/`targetEndlessQuiz`
  "Enchaîne 20 bonnes réponses d'affilée.", `targetGeohunter` "Termine avec
  un score total sous 250.", ou `targetArcade` "Atteins N bonnes réponses."
  avec N dépendant du jeu Arcade tiré).
- Un chip de variante : soit un continent (icône + libellé région), soit une
  statistique (icône + libellé stat) pour Classement/Plus ou
  Moins/Endless Quiz ; les 8 chips de statistiques pour Géohunter ; le chip
  du mini-jeu Arcade tiré pour Arcade.
- Une ligne "Récompense" avec l'icône du booster argent (`BoosterTier.silver`).
- Un bouton **"Jouer"** (`TicketGatedStartButton`, orange, avec le solde de
  tickets affiché au-dessus). **Corrigé après run 2026-07-07 :** ne pas
  attendre exactement 25 — le solde observé en pratique était 30 (bonus de
  connexion quotidienne déjà crédité) ; vérifier la cohérence des
  variations plutôt qu'une valeur figée (voir note de précondition).
- La tuile "Défi du jour" de la Home (retour à Home) affiche le **même**
  libellé de mode que la carte de règles — pas de désynchronisation entre
  les deux points d'entrée.

**Régression connue liée :** aucune à ce jour — premier cas de ce fichier,
sert de référence pour tous les cas suivants.

---

## UC-DEFIJOUR-02 — Jouer une partie et vérifier la persistance du score (sans victoire)

**Précondition (seed) :** profil `allUnlocked`, défi du jour déjà résolu
(UC-DEFIJOUR-01 exécuté juste avant, même run).

**Repro :**
1. Depuis `DailyChallengePage`, taper **"Jouer"**.
2. Jouer la partie du mode sous-jacent tiré jusqu'au game-over, en visant
   délibérément **de ne pas atteindre la cible** (répondre juste au moins
   une fois correctement puis se tromper — mécaniques déjà couvertes par
   `defi.md`, ne pas re-décrire ici).
3. Sur l'écran de fin (`DefiGameOverScaffold`), noter le score affiché dans
   la carte **`DailyChallengeResultCard`** en bas de l'écran ("Ton meilleur
   score" / "Objectif").
4. Taper **"Rejouer"** (bouton visible car pas encore gagné) et refaire une
   partie avec un score strictement inférieur à celui de l'étape 2.

**Checkpoint :** deux captures — (a) carte de résultat après la 1ère partie
(score X), (b) carte de résultat après la 2e partie (score Y < X).

**Attendu :**
- (a) "Ton meilleur score" = score de session (X). Pas de bandeau
  "Défi réussi" (cible non atteinte).
- (b) "Ton meilleur score" reste **X** (le max des deux tentatives), même si
  la session 2 a produit un score Y < X — preuve que `best_score` est bien
  lu depuis `daily_challenge_progress` et pas juste ré-affiché depuis le
  score de session courante. (Pour un mode "plus bas = mieux" comme Géohunter
  — `DailyChallengeType.geohunter` — inverser le raisonnement : le meilleur
  score affiché doit être le plus **petit** des deux, cf. `lowerIsBetter`.)
- Le bouton "Rejouer" reste visible après les deux parties (pas encore gagné
  → `dailyLocked` doit être `false`).

**Régression connue liée :** aucune à ce jour — cas ajouté pour couvrir
spécifiquement `_mergeBest`/`recordAttempt`, jamais exercé par `defi.md`
(qui ne connaît pas la notion de "meilleur score du jour").

---

## UC-DEFIJOUR-03 — Atteindre la cible : état "gagné" et blocage du replay

**Précondition (seed) :** profil `allUnlocked`. Utiliser au besoin la tuile
debug **"Défi du jour : changer"** pour retomber sur une variante à cible
basse et réaliste à atteindre en une session courte (ex. Arcade
`choosing_anthem`, cible 5 — voir `kArcadeDailyTargets` dans
`daily_challenge_cycle_service.dart` ; les cibles Classement/Plus ou
Moins/Endless Quiz, 110/20/20, peuvent demander plusieurs tentatives).

**Repro :**
1. Depuis `DailyChallengePage`, taper "Jouer".
2. Jouer jusqu'à atteindre (ou dépasser, selon le sens de comparaison) la
   cible affichée.
3. Sur l'écran de fin, observer la carte de résultat.

**Checkpoint :** deux captures — (a) écran de fin juste après la victoire,
(b) retour sur `DailyChallengePage` (bouton back) ou tuile Home "Défi du
jour".

**Attendu :**
- (a) La carte de résultat bascule sur le variant "gagné" :
  icône `emoji_events` + titre **"Bravo, défi réussi !"** (`t.daily.wonTitle`)
  + corps **"Tu as gagné un booster argent."** (`t.daily.wonBody`). Le
  bouton **"Rejouer" a disparu** de la ligne de boutons du bas — seul
  "Retour" reste (`dailyLocked == true` dans `DefiGameOverScaffold`, voir le
  code : `if (!dailyLocked) [...PrimaryButton Rejouer...]`).
- Un booster argent apparaît dans l'inbox récompenses (badge Carnet /
  notification de récompense — cf. `rewardInboxProvider`).
- (b) `DailyChallengePage` affiche désormais la carte **`_AlreadyWonCard`** :
  icône trophée + **"Défi du jour réussi !"** (`t.daily.alreadyWonTitle`) +
  **"Reviens demain pour un nouveau défi."** — le bouton "Jouer" a disparu.
- La tuile Home "Défi du jour" affiche aussi l'icône `check_circle` +
  "Défi du jour réussi !" (même état reflété aux deux points d'entrée).

**Régression connue liée :** aucune à ce jour, mais c'est le point le plus
sensible de ce fichier vis-à-vis des mémoires projet sur les providers figés
au build (`feedback_flush_at_layout_dirty_provider_during_layout_build`,
`feedback_riverpod_invalidate_listenerless_kills`) — trois lectures du même
état (`dailyChallengeProgressProvider`) sur trois écrans différents
(game-over, page dédiée, tuile Home) doivent converger sans nécessiter de
hot-restart. Un désaccord entre l'un des trois est le signal à chercher en
priorité si ce cas échoue.

---

## UC-DEFIJOUR-04 — "Défi du jour : changer" reroule vers un autre jeu

**Précondition (seed) :** profil `allUnlocked`, défi du jour déjà résolu
(peu importe l'état gagné ou non — le reroll fonctionne dans les deux cas).

**Repro :**
1. Ouvrir `DailyChallengePage`, noter le libellé de mode + le chip de
   variante affichés (ex. "Classement · Europe").
2. Retour au debug launcher, taper **"Défi du jour : changer"**. Un
   SnackBar **"Défi du jour changé"** doit s'afficher.
3. Rouvrir "Défi du jour".

**Checkpoint :** deux captures — (a) `DailyChallengePage` avant le "changer"
(état noté à l'étape 1), (b) `DailyChallengePage` après.

**Attendu :**
- (b) Le libellé de mode et/ou le chip de variante **diffèrent** de (a) — au
  minimum la combinaison mode+variante doit changer (un reroll peut par pur
  hasard retomber sur le même mode, ~1/5, mais la variante à l'intérieur du
  mode change alors presque toujours — 27/28 chances pour
  Classement/Plus ou Moins, 8/9 pour Arcade). Si mode ET variante sont
  identiques après un "changer", relancer le reroll une fois avant de
  conclure à un bug (coïncidence statistique plausible) ; un **3e** reroll
  identique consécutif serait, lui, suspect.
- Si le défi précédent avait été gagné (UC-DEFIJOUR-03 exécuté juste avant),
  le nouveau défi tiré repart **non gagné** : bouton "Jouer" visible, pas de
  `_AlreadyWonCard` — le reroll doit aussi remettre `completed_at` à `null`
  pour la nouvelle ligne (nouvelle clé `period_key` inchangée mais nouvelle
  ligne réinsérée vierge).
- La tuile Home reflète elle aussi le nouveau libellé sans redémarrage.

**Régression connue liée :** aucune à ce jour — cas dédié à détecter un
provider Riverpod resté "sale"/périmé après le double `ref.invalidate` du
handler (`dailyChallengeProvider` + `dailyChallengeProgressProvider(periodKey)`) :
un bug ici afficherait l'**ancien** jeu malgré le SnackBar de confirmation.

---

## UC-DEFIJOUR-05 — "Défi du jour : reset score" rejoue le MÊME défi (pas de reroll)

**Précondition (seed) :** profil `allUnlocked`, défi du jour **gagné**
(enchaîner directement après UC-DEFIJOUR-03, sans passer par "changer" —
c'est le contraste à vérifier avec UC-DEFIJOUR-04).

**Repro :**
1. Sur `DailyChallengePage` (état gagné, `_AlreadyWonCard` visible), noter
   précisément le mode + la variante du défi gagné.
2. Retour au debug launcher, taper **"Défi du jour : reset score"**. Un
   SnackBar **"Score du défi du jour réinitialisé"** doit s'afficher.
3. Rouvrir "Défi du jour".

**Checkpoint :** deux captures — (a) `DailyChallengePage` juste avant le
reset (état gagné, mode/variante notés), (b) juste après.

**Attendu :**
- (b) Mode + variante **strictement identiques** à (a) (même libellé, même
  chip, même phrase d'objectif/cible) — contrairement à UC-DEFIJOUR-04. Seul
  l'état de complétion change.
- Le bouton **"Jouer" est réapparu** (`_AlreadyWonCard` a disparu) — la
  partie est rejouable.
- Rejouer jusqu'au game-over (sans forcément regagner) : la carte de
  résultat affiche "Ton meilleur score" reparti de zéro pour cette session
  (pas de résidu de l'ancien `best_score` d'avant le reset) et le bouton
  "Rejouer" est de nouveau visible sur l'écran de fin (`dailyLocked ==
  false`).
- La tuile Home revient à l'affichage "libellé de mode" (perd son
  `check_circle`).

**Régression connue liée :** aucune à ce jour — le commentaire du handler
dans `debug_launcher_page.dart` documente explicitement ce contrat
("Delete-without-reset-cycle … unlike 'changer' above, this does not reroll
to a different game"). Une régression plausible ici serait que "reset
score" reroule accidentellement (fusion de comportement avec "changer"), ou
à l'inverse qu'il ne réinitialise pas vraiment `completed_at` (le bouton
"Jouer" resterait caché malgré le SnackBar de confirmation).
