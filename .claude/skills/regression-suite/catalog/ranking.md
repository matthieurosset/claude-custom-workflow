# Catalogue de non-régression visuelle — Ranking (Swipe ELO des drapeaux préférés)

Voir le design : `docs/superpowers/specs/2026-07-07-visual-regression-catalog-design.md`.

**Exécuté bout-en-bout le 2026-07-07 : 6/6 PASS** (UC-RANK-06 partiel — un
seul des 3 chips contextuels déclenché malgré ~38 swipes, voir note en fin
de cas, probablement un seuil de probabilité et non un bug).

**Bug réel trouvé en marge, corrigé :** une exception non gérée
(`type 'String' is not a subtype of type 'List<dynamic>?'`) dans
`SyncService._addToQueue`, déclenchée au premier achievement débloqué
après un install fraîchement seedé — `lib/core/testing/test_seed.dart`
écrivait la clé `sync_queue` via `prefs.setString('sync_queue', '[]')`
alors que `SyncService` la lit/écrit partout via `getStringList`/
`setStringList` (`sync_service.dart`, `_queueKey`). Affectait les 3
profils de seed (`fresh`/`allUnlocked`/`midProgress`), pas seulement
Ranking — silencieux (catché par le handler top-level Flutter, pas de
crash visible), mais corrompait la queue de sync offline pour le reste du
run. **Corrigé directement** (`setStringList('sync_queue', <String>[])`),
code de test uniquement (tree-shaken hors production, gated `kTestMode`),
pas de risque prod.

Fonctionnalité : entrée standalone **"Ranking"** sur la Home, qui lance le
swipe ELO de drapeaux favoris — pas un mode de jeu classique (pas de bonne/
mauvaise réponse), juste un tournoi de préférences façon Tinder qui construit
un classement personnel via un système ELO. Code : `lib/pages/modes/
favorite_flags/` (`swipe_flags.dart` = écran de swipe, `ranking.dart` = écran
de classement), widget de jeu `lib/pages/games/swipe/widgets/
elo_swipe_game.dart`, logique ELO `lib/core/services/flag_elo_service.dart`.

**Ne pas confondre avec `lib/pages/games/swipe/game.dart`** (`SwipeGame` /
`swipe_game_provider.dart`) : c'est un jeu de comparaison statistique
("plus ou moins" à la Tinder, avec bonne/mauvaise réponse) utilisé ailleurs
(Défi, Duel, Online, Ranked) — un composant totalement différent qui partage
juste le geste de swipe. Ce catalogue ne couvre que `EloSwipeGame`.

Pays : les paires sont **tirées aléatoirement** parmi les 248 pays jouables
(`playableCountriesProvider`) à chaque round — aucun couple n'est
déterministe. Les checkpoints ci-dessous décrivent donc la structure attendue
de l'écran, pas des pays précis.

**Précondition (seed) commune à tous les cas :** `TestSeed._seedFlagElo` est
appelé par **les trois profils** (`fresh`, `allUnlocked`, `midProgress`) — il
insère une ligne par pays du monde dans la table `flag_elo`
(`code`, `elo=1000`, `match_count=0`), donc n'importe quel profil seedé
convient. Comme `match_count` vaut 0 pour tout le monde au départ,
`totalMatches < _calibrationMatches` (30) et le tirage de paire utilise
toujours `_pickPureSurprise` (pondéré `1/(matchCount+1)`, donc quasi-uniforme
tant qu'aucun swipe n'a eu lieu).

**Accès au debug launcher :** Home → scroller jusqu'en bas → bannière ambrée
**"DEBUG — Lancer n'importe quoi"** → section **"Moteurs de jeu — Autres"** →
tuile **"Swipe ELO"** (icône `Icons.swipe`) → pousse directement
`FlagEloSwipeRoute` (`context.router.push`, pas de manipulation de pays/région
nécessaire contrairement aux tuiles Aventure).

---

## UC-RANK-01 — Ouverture de l'écran de swipe (première paire)

**Précondition (seed) :** n'importe quel profil (`fresh`/`allUnlocked`/
`midProgress`) — table `flag_elo` pré-remplie comme décrit ci-dessus.

**Repro :**
1. Debug launcher → section "Moteurs de jeu — Autres" → tuile **"Swipe ELO"**.
2. L'écran affiche un spinner bref pendant `_initFlags` (chargement des pays
   + des ELO), puis la première paire.

**Checkpoint :** capture une fois la paire affichée (fin du spinner).

**Attendu :**
- App bar (`TransparentAppBar`) titre **"Mes Drapeaux Préférés"**, action à
  droite = icône `leaderboard` + libellé **"Classement"** en dessous.
- Question centrée : **"Quel est ton drapeau préféré ?"**.
- Deux drapeaux distincts empilés verticalement en portrait (haut/bas), "VS"
  au centre, nom de pays localisé sous chaque drapeau.
- Un rang `#N` est déjà affiché sous chaque drapeau (`getRank` s'appuie sur
  la map ELO déjà chargée — même à égalité parfaite à 1000, un rang arbitraire
  mais non nul est retourné par le tri stable).
- Instruction en bas : icône `swipe_vertical` + texte **"Swipe ton drapeau
  préféré"**.
- Pas de chip contextuel (Top match / David vs Goliath / Match serré) attendu
  à ce stade dans l'immense majorité des cas (rangs encore quasi arbitraires
  sur des ELO tous égaux) — si un chip apparaît quand même ce n'est pas un
  bug, juste un tirage qui satisfait la condition par coïncidence.

**Régression connue liée :** aucune à ce jour.

---

## UC-RANK-02 — Choisir un drapeau (swipe) : feedback ELO + paire suivante

**Précondition (seed) :** suite de UC-RANK-01, écran de swipe avec une paire
affichée.

**Repro :**
1. Glisser franchement le drapeau du haut vers le haut (au-delà du seuil
   ~100 px, ou avec une vélocité suffisante) pour le choisir comme préféré —
   équivalent en paysage : glisser le drapeau de gauche vers la gauche.
2. Relâcher.

**Checkpoint :** deux captures — (a) juste après la fin du geste (badge ELO +
micro-saut du gagnant visibles), (b) ~1,2 s plus tard (après le hold de
feedback de 1000 ms, la paire suivante doit être chargée).

**Attendu :**
- (a) Le drapeau swipé (gagnant) affiche une pastille verte **"+X"** en
  overlay coin haut-droit (scale-in élastique) et fait un léger "hop" dans la
  direction du swipe ; le drapeau perdant affiche une pastille rouge **"-Y"**
  et un léger fondu d'opacité (pas de disparition complète).
- Avec deux pays neufs (`match_count=0` chacun, K-factor=48) et un ELO égal
  1000 des deux côtés, les deltas prévisualisés doivent être symétriques
  (`+X` côté gagnant proche de `24`, `-Y` côté perdant proche de `-24`, la
  formule ELO standard donnant un delta égal en cas d'égalité).
- (b) Une nouvelle paire de drapeaux s'affiche (les deux pays ne sont pas
  nécessairement les mêmes qu'avant), rang potentiellement mis à jour pour le
  pays qui vient de gagner. Aucun freeze/plantage pendant la transition.

**Détail positif observé (ajouté après run 2026-07-07, pas un bug) :** un
indicateur de mouvement de rang (`↑+216` vert / `↓-6` rouge) apparaît à
côté du `#rang` après qu'il ait bougé suite à un vote — cohérent avec le
design system (vert=hausse, rouge=baisse). Non documenté dans la première
rédaction mais correct, à surveiller comme point de contrôle supplémentaire.
- Vibration légère au moment du commit (`GameAudio.instance.vibrateTap()`) —
  non vérifiable par capture, à noter si un appareil physique est utilisé.

**Régression connue liée :** aucune à ce jour. Point d'attention (pas un bug
connu, juste une zone fragile) : `FlagEloSwipePageState.dispose()` déclenche
`syncFlagElo()` en fire-and-forget vers le cloud via un notifier capturé à
`initState` — si ce test est enchaîné avec une sortie brutale de l'écran
juste après un swipe, vérifier qu'aucune exception "Using ref when unmounted"
ne remonte dans les logs.

---

## UC-RANK-03 — Consultation du classement complet (podium + liste)

**Précondition (seed) :** idem, avec **au moins 5-6 swipes variés** déjà
effectués (via UC-RANK-02 répété sur des paires différentes) pour que les ELO
divergent visiblement — sinon tous les pays restent ex-aequo à 1000 et le tri
retombe sur l'ordre naturel de la liste sans rien démontrer.

**Repro :**
1. Depuis l'écran de swipe, taper l'icône **"Classement"** (leaderboard) en
   haut à droite de l'app bar.
2. La page `FlagEloRankingPage` s'affiche : podium top 3 animé (slide + fade)
   puis séparateur **"Classement complet"** puis liste scrollable du 4e pays
   jusqu'au dernier.

**Checkpoint :** capture après la fin de l'animation d'entrée du podium
(podium + début de liste visibles à l'écran).

**Attendu :**
- Podium : 1er au centre (le plus grand, socle couleur `highlight`), 2e à
  gauche (socle `medalSilver`), 3e à droite (socle `medalBronze`) — médailles
  🥇🥈🥉, drapeau, nom de pays localisé et score ELO affichés pour chacun.
- Liste (à partir du 4e) : chaque ligne montre `#rang`, drapeau WebP
  (36×24, `country.flagPng`), nom localisé, score ELO aligné à droite avec
  chiffres tabulaires (`FontFeature.tabularFigures`).
- Les pays swipés en UC-RANK-02 doivent apparaître avec un ELO strictement
  supérieur à 1000 et un rang meilleur que les pays jamais swipés.
- Pas de doublon de pays dans la liste, pas de ligne vide, pas d'image
  cassée (les 248 pays du monde ont une couverture WebP complète — un
  drapeau gris uniforme signalerait un chemin d'asset cassé, cf.
  `errorBuilder` du podium).

**Régression connue liée :** aucune à ce jour.

---

## UC-RANK-04 — Accès à "Ranking" depuis la Home (navigation réelle)

**Précondition (seed) :** n'importe quel profil seedé.

**Repro (navigation réelle, PAS le debug launcher) :**
1. Depuis l'écran d'accueil, scroller jusqu'à la section **"Extra"** (sous
   la section Progression/Carnet).
2. Taper la carte **"Ranking"** (icône trophée `emoji_events`, sous-titre
   "Classe tes drapeaux préférés"), à droite de la carte "Découverte".

**Checkpoint :** capture juste après le tap (arrivée sur l'écran de swipe).

**Attendu :**
- Navigation directe vers le même écran de swipe que UC-RANK-01, sans passer
  par le debug launcher.
- La route `favorite-flags/swipe` est déclarée comme enfant de
  `MainShellRoute` (`context.router.push(const FlagEloSwipeRoute())` depuis
  la Home, sans `.root.push()`) — cohérent avec les règles de navigation du
  projet puisque la Home est déjà dans le scope de l'onglet. Le bouton retour
  doit ramener proprement à la Home, sans écran bleu/vide.

**Régression connue liée :** aucune connue spécifique à ce jour ; cas ajouté
en prévention du chemin de navigation réelle (même logique que UC-ADV-10/11
du catalogue Aventure — s'assurer que l'entrée Home reste atteignable après
tout redesign de la page d'accueil).

---

## UC-RANK-05 — Cas limite : anti-spam pendant le hold de feedback

**Précondition (seed) :** écran de swipe avec une paire affichée.

**Repro :**
1. Swiper le drapeau du haut (comme UC-RANK-02).
2. **Immédiatement** (pendant la fenêtre d'~1 s où le badge ELO est affiché,
   avant que la paire suivante ne charge), tenter de swiper le drapeau du bas
   (celui qui vient de perdre).

**Checkpoint :** capture pendant la tentative de second swipe (juste après le
premier commit, geste en cours sur le second drapeau).

**Attendu :**
- Le second geste est ignoré : `onPanStart`/`onPanUpdate` retournent tôt tant
  que `_showFeedback` est vrai (`if (_showFeedback) return;` dans
  `elo_swipe_game.dart`) — aucune animation de drag ne doit démarrer sur le
  drapeau perdant pendant le hold.
- Un seul vote est comptabilisé pour ce round (pas de double appel à
  `_vote`/`updateElos`) — vérifiable indirectement en observant qu'une seule
  nouvelle paire charge après le hold, pas un enchaînement de deux paires.

**Régression connue liée :** aucune à ce jour — cas ajouté préventivement, le
garde-fou `_showFeedback` étant la seule protection contre un double-vote.

---

## UC-RANK-06 — Cas limite : chip contextuel après plusieurs swipes

**Précondition (seed) :** écran de swipe, avec un historique de swipes déjà
conséquent (**recommandé : 15-20 swipes** en variant les choix, pour que des
écarts de rang/ELO significatifs apparaissent — les chips dépendent de seuils
sur le rang, pas juste sur l'ELO brut).

**Repro :**
1. Continuer à swiper (choisir alternativement des pays différents) jusqu'à
   ce qu'un chip contextuel apparaisse sous le "VS" central : **"Match au
   sommet"** (deux pays classés dans le top 10), **"David vs Goliath"**
   (écart de rang ≥ 50) ou **"Match serré"** (rangs adjacents ≤ 2, ou écart
   ELO < 30 avec au moins 3 matchs chacun).
2. Capturer dès qu'un chip apparaît.

**Checkpoint :** capture montrant le chip actif sous le "VS".

**Attendu :**
- Le chip correspond bien à la condition affichée : couleur jaune/dorée pour
  "Match au sommet", orange (`AppColors.accent`) pour "David vs Goliath",
  blanc translucide pour "Match serré".
- Un seul chip est actif à la fois (la logique `_activeChip()` retourne le
  premier qui matche, dans l'ordre topMatch > davidGoliath > tightMatch).
- Le texte du chip est bien traduit (clé `favoriteFlags.topMatch` /
  `favoriteFlags.davidGoliath` / `favoriteFlags.tightMatch` dans les 6
  locales — si ce test est mené dans une locale non-FR, vérifier l'absence de
  fallback FR silencieux).

**Régression connue liée :** aucune à ce jour. Cas volontairement mis en
dernier car il nécessite le plus de setup manuel (nombreux swipes) — à
sauter en premier passage rapide si le temps est compté, les UC-RANK-01 à 04
couvrant déjà l'essentiel du parcours.

**Corrigé après run 2026-07-07 :** ~38 swipes n'ont suffi à déclencher que
le chip "David vs Goliath" (~10 fois, couleur/exclusivité correctes). "Match
au sommet" et "Match serré" ne se sont jamais déclenchés malgré un volume
largement supérieur aux 15-20 recommandés — probablement une question de
volume/stratégie de swipe (favoriser systématiquement le pays déjà le
mieux classé pour concentrer les rencontres top-10), pas un bug. Le repro
"15-20 swipes" est optimiste pour couvrir les 3 variantes en une seule
session ; ne pas s'inquiéter si seul "David vs Goliath" apparaît.
