# Catalogue de non-régression visuelle — Pays du jour

Voir le design : `docs/superpowers/specs/2026-07-07-visual-regression-catalog-design.md`.

**Exécuté bout-en-bout le 2026-07-07 : 6/6 PASS, aucun bug produit trouvé.**
Corrections ci-dessous issues de ce run (mécanisme de soumission de
l'hymne, méthode de soumission Geordle, timing de capture du jalon).

**Note de nommage importante :** "Pays du jour" (route `DailyCountryRoute`, page
`lib/pages/modes/daily_country/daily_country_page.dart`) est **différent** de
"Défi du jour" (`DailyChallengeRoute`, couvert par un autre catalogue). Dans le
debug launcher, la tuile s'appelle trompeusement **"Mission du jour"** mais
pointe bien vers `DailyCountryRoute` — c'est cette fonctionnalité-ci. Ne pas
confondre les deux dans les captures ni dans les rapports.

**Mécanique du mode (résumé, lu dans `daily_country_page.dart` /
`daily_country_provider.dart` / `daily_country_progress.dart`) :** chaque jour
calendaire (frontière Europe/Zurich), l'app tire un pays mystère unique et
propose **8 manches fixes, dans cet ordre** :
1. `geordle` — jeu façon Wordle : le pays est **inconnu**, le joueur tape des
   noms de pays et reçoit un feedback par critère (région, population, etc.)
   jusqu'à trouver le bon nom. Pas de limite de tentatives (jamais de "perdu").
2. `capital` — question "inversée" : le pays est maintenant **connu** (révélé
   à l'étape 1), le prompt est `Quelle est la capitale de {pays} ?`, 4 options
   à choix (QCM).
3. `flag` — idem, `Quel est le drapeau de {pays} ?`.
4. `shape` — idem, `Quelle est la forme de {pays} ?`.
5. `search` — carte interactive : taper le territoire du pays sur la carte
   (comme Aventure Searching).
6. `coats` — idem QCM, `Quelles sont les armoiries de {pays} ?`.
7. `landmark` — idem QCM, `Quel monument se trouve en {pays} ?` (+ un panneau
   de révélation nom/description après la réponse).
8. `anthem` — idem QCM mais 4 lecteurs audio partagés (un seul hymne joue à la
   fois), révélation du pays derrière chacune des 4 options après réponse.

Une fois les 8 manches finalisées, l'écran bascule sur un récap
(`DailyCountryRecap`) : étoiles par manche, score `X / 8`, récompense (booster
Panini bronze/argent/or selon le score), et incrémentation de la série
("streak", `dailyCountryStreakProvider`).

**Précondition (seed) :** profil `allUnlocked` suffit — aucune graine
spécifique au Pays du jour n'existe dans `TestSeed`/`SeedProfile` (vérifié
dans `lib/core/testing/test_seed.dart`). La table `daily_mission_progress`
(via `DailyCountryDbService`) et le cycle picker (`DailyMissionCycleDbService`)
démarrent naturellement à vide sur une DB fraîchement seedée, donc la
première ouverture du jour crée toujours une ligne de progression neuve, quel
que soit le profil.

**Accès au debug launcher :** Home → scroller jusqu'en bas → bannière ambrée
**"DEBUG — Lancer n'importe quoi"** → section **"Défi — Autres"** → tuile
**"Mission du jour"** (icône `Icons.today`, PAS "Défi du jour" juste en
dessous — icône différente `Icons.today_outlined`).

**Piège clavier :** comme pour Aventure, `adb input text` ne fonctionne pas
sur le clavier in-app Flutter des jeux de saisie (ici, l'étape 1 `geordle`
utilise le même clavier custom que le Typing d'Aventure) — taper touche par
touche.

**Absence de tuile reset (vérifié dans `debug_launcher_page.dart`) :**
contrairement à "Défi du jour" qui a deux tuiles dédiées ("Défi du jour :
changer" et "Défi du jour : reset score", lignes ~412-450, appelant
`dailyChallengeDbServiceProvider.deleteChallengeForTesting`), **il n'existe
aucune tuile équivalente pour le Pays du jour.** `DailyCountryDbService`
n'expose pas de méthode "for testing" pour effacer la progression du jour. Le
seul moyen de revoir l'état "déjà joué aujourd'hui" est de terminer les 8
manches une première fois dans la même session de test, puis de rouvrir
l'écran (voir UC-PDJ-06) — pas de raccourci DB/debug disponible.

---

## UC-PDJ-01 — Ouverture de l'écran, étape 1 (Geordle)

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher (voir accès ci-dessus) → section "Défi — Autres" → tuile
   **"Mission du jour"**.
2. L'écran s'ouvre directement sur l'étape 1 (Geordle) si la mission du jour
   n'a pas encore été commencée.

**Checkpoint :** capture juste après l'entrée sur l'écran.

**Attendu :**
- Titre d'app bar **"Pays du jour"** (`t.dailyMission.title`).
- Barre de progression à 8 segments en haut de l'écran (`_StepHeader`) : le
  1er segment en orange accent (étape courante), les 7 suivants gris clair
  translucide (`pending`).
- Zone de contenu : soit la carte "Comment jouer" (`DefiRulesCard`,
  `t.geordleGame.howToPlay`) si aucune tentative n'a encore été faite, soit
  le clavier + champ de saisie du jeu Geordle.
- Pas de nom de pays affiché nulle part sur cette étape (le pays est encore
  inconnu du joueur à ce stade — seule l'étape 1 le cache).

**Régression connue liée :** aucune à ce jour — premier passage de ce cas.

---

## UC-PDJ-02 — Résolution de l'étape 1 (Geordle) et transition vers l'étape 2

**Précondition (seed) :** profil `allUnlocked`, écran Pays du jour ouvert
(suite UC-PDJ-01).

**Repro :**
1. Taper un nom de pays au hasard (ex. "Portugal") dans le clavier in-app et
   valider — observer la ligne de feedback par critère qui apparaît dans
   l'historique des tentatives. **Piège de soumission (corrigé après run
   2026-07-07) :** la tentative se soumet **exclusivement** en tapant la
   puce/carrousel d'autocomplétion (`FlagTypingCarousel`) qui apparaît
   juste au-dessus du clavier dès que la saisie correspond à au moins un
   pays — ni la touche "retour" du clavier custom, ni `adb shell input
   keyevent 66` (Entrée système), ni un tap sur le champ de texte ne
   soumettent quoi que ce soit. Cette puce n'a pas de `bounds` accessibles
   via `uiautomator dump` (simple `GestureDetector` sans sémantique
   Flutter) — la localiser visuellement sur un screenshot frais après
   chaque lettre tapée, pas via un dump.
2. Répéter avec d'autres noms en s'aidant du feedback jusqu'à taper le nom
   correct du pays mystère (pas de limite de tentatives — le mode ne peut pas
   être "perdu").
3. Valider la bonne réponse.

**Checkpoint :** deux captures — (a) juste après une tentative incorrecte
(ligne de feedback visible dans l'historique), (b) ~2s après la tentative
correcte (message "Bravo"/victoire, avant la transition automatique).

**Attendu :**
- (a) Chaque tentative ajoute une ligne dans l'historique (`GuessHistoryItem`)
  avec un code couleur par critère (région, population, etc.) — pas de ligne
  vide ou de crash sur une tentative fausse.
- (b) Dès `gameWon`, un délai de 2000ms (`Future.delayed`, voir
  `daily_country_page.dart` ligne ~258) précède l'avance à l'étape suivante —
  le joueur doit voir le drapeau/la dernière tentative correcte affichée
  pendant ce délai, pas un écran vide.
- Après le délai : la barre de progression passe le 1er segment en vert
  (`won`), le 2e segment devient orange accent (nouvelle étape courante), et
  l'écran bascule sur l'étape 2 (`capital`, QCM) avec le prompt
  `Quelle est la capitale de {pays} ?` — le nom du pays est maintenant révélé
  et affiché comme titre de la question.

**Régression connue liée :** aucune à ce jour — cas ajouté pour couvrir la
transition étape 1 → étape 2, point de bascule "pays inconnu → pays connu"
propre à ce mode.

---

## UC-PDJ-03 — Bonne réponse sur une manche QCM inversée (capital / flag / shape / coats)

**Précondition (seed) :** profil `allUnlocked`, étape Geordle déjà résolue
(suite UC-PDJ-02), sur une des étapes 2-4 ou 6 (`capital`, `flag`, `shape`,
`coats`).

**Repro :**
1. Lire le prompt (ex. `Quelle est la capitale de France ?`).
2. Taper sur la tuile QCM correcte parmi les 4 options affichées en grille
   2×2.

**Checkpoint :** capture juste après le tap (avant la transition, ~900ms
plus tard).

**Attendu :**
- La tuile tapée se met en surbrillance **verte** (bordure `AppColors.success`,
  3px) si correcte ; les 3 autres tuiles passent en opacité réduite (0.4,
  "muted").
- Un son de succès joue (`GameAudio.playSuccess`).
- Après ~900ms, transition automatique vers l'étape suivante — segment vert
  dans la barre de progression, pas de bouton "Valider" à taper (contrairement
  au Drawing d'Aventure).
- Pour `coats` et `flag` : l'image affichée dans chaque tuile est bien celle
  du pays-option correspondant (pas de décalage d'index).
- Pour `shape` : la silhouette SVG doit remplir la tuile (pas un point de
  quelques pixels — `SizedBox.expand` force les contraintes, cf. code).

**Régression connue liée :** aucune à ce jour.

---

## UC-PDJ-04 — Manche Landmark et manche Anthem (comportements spéciaux)

**Précondition (seed) :** profil `allUnlocked`, progression amenée jusqu'à
l'étape 7 (`landmark`) puis 8 (`anthem`) — enchaîner les étapes précédentes
normalement.

**Repro (landmark, étape 7) :**
1. Lire le prompt `Quel monument se trouve en {pays} ?`.
2. Taper la tuile correcte (photo de monument).

**Repro (anthem, étape 8) :**
3. Passer à l'étape 8 : le layout QCM standard est remplacé par
   `AnthemChoiceOptions` — 4 lecteurs audio partagés (un seul hymne joue à la
   fois).
4. **Corrigé après run 2026-07-07 :** taper une tuile ne soumet PAS
   directement la réponse (contrairement aux autres manches QCM) — le tap
   ne fait que **sélectionner/lancer la lecture** de cette tuile (icône
   d'onde sonore + contour orange). Le bouton **"Valider"** (pill orange,
   pleine largeur, en bas de l'écran) passe alors d'un état désactivé
   (rouge-brun, texte pâle) à actif (orange plein) — taper ensuite
   explicitement "Valider" pour soumettre la réponse jugée correcte (au
   son, ou au hasard pour le test).

**Checkpoint :** trois captures — (a) landmark juste après le tap correct
(panneau de révélation nom+description visible), (b) écran anthem avant toute
sélection (4 lecteurs visibles, aucun nom de pays affiché), (c) anthem juste
après le tap (révélation du pays derrière chacune des 4 options).

**Attendu :**
- (a) Un panneau `LandmarkRevealPanel` apparaît sous la grille avec le nom et
  la description du monument — délai avant transition allongé à **5000ms**
  (`daily_country_page.dart`/`inverted_choosing_game.dart`, cas spécial pour
  laisser le temps de lire).
- (b) Aucune image ni nom de pays visible sur les tuiles avant réponse (les
  hymnes ne révèlent le pays qu'après la réponse — contrairement aux autres
  manches QCM où les images/textes sont visibles dès l'affichage).
- (c) Après le tap, chaque tuile révèle le pays associé à son hymne — délai
  de transition **4000ms** (plus long que les 900ms standards, pour laisser
  le temps de tout lire).
- **Corrigé après run 2026-07-07 :** un bouton "Valider" (pill orange,
  pleine largeur, en bas) est requis pour soumettre la réponse sur cette
  manche uniquement — contrairement à toutes les autres manches QCM
  inversées du Pays du jour qui valident au premier tap sur une tuile (voir
  repro corrigé ci-dessus).

**Régression connue liée :** aucune à ce jour — cas ajouté pour couvrir les
deux seules manches à comportement de délai/reveal différent du standard
(900ms sans reveal).

---

## UC-PDJ-05 — Manche Search (carte) et complétion de la mission (8/8)

**Précondition (seed) :** profil `allUnlocked`, progression amenée jusqu'à
l'étape 5 (`search`), puis poursuivre jusqu'à la 8e et dernière manche
(`anthem`) pour observer la complétion complète.

**Repro (search, étape 5) :**
1. Lire l'écran (pas de texte de prompt sur cette étape, juste la carte).
2. Taper sur le territoire du pays mystère sur la carte (tap franc et net au
   centre du territoire — la carte est pannable, comme en Aventure).

**Repro (complétion, après la 8e manche) :**
3. Terminer la dernière manche (`anthem`) avec la bonne réponse pour arriver
   à 8/8 (score parfait) — ou volontairement se tromper sur une/plusieurs
   manches en amont pour tester un score non-parfait (ex. 6/8 ou 7/8).

**Checkpoint :** trois captures — (a) carte après le tap sur le pays
(surbrillance persistante), (b) écran récap juste après la 8e manche, (c)
même écran récap ~1s plus tard (bannière de complétion + reward).

**Attendu :**
- (a) Surbrillance **verte persistante** sur le bon pays (identique à
  UC-ADV-08 d'Aventure) ; après ~2500ms, transition automatique vers l'étape 6
  (délai plus long que le QCM standard pour laisser voir l'animation de
  zoom/reveal de la carte).
- (b) `DailyCountryRecap` : drapeau du pays révélé en haut, nom localisé,
  ligne de 8 étoiles (pleines en orange accent pour les manches gagnées,
  contour blanc translucide pour les perdues), score `X / 8`.
  - Si 8/8 : texte `t.dailyMission.perfect` ("Sans-faute !") en orange accent.
  - Si 7/8 : texte `t.dailyMission.almostPerfect` ("Presque parfait !").
  - Sinon (≤6/8) : ni l'un ni l'autre, directement la section récompense.
- Section "Récompense" (carte blanche `AppColors.surface`) : titre "Récompense"
  + `RewardChip` d'un booster — **or** si 8/8, **argent** si 7/8, **bronze**
  sinon (`dailyCountryBooster()`).
- (c) Une bannière de jalon (`MilestoneNotification`) doit apparaître en haut
  avec le texte "Mission quotidienne accomplie !" (`t.milestones.dailyMissionCompleted`)
  et le nom du pays en titre — déclenchée via `postFrameCallback`, donc visible
  quelques centaines de ms après le rendu du récap, pas immédiatement.
  **Timing de capture (corrigé après run 2026-07-07) :** capturer **moins
  d'1s** après la transition depuis la dernière manche — la bannière a une
  durée de visibilité par défaut de 3500ms (`achievement_unlock_toast.dart`)
  et peut s'être déjà auto-masquée sur une capture tardive (observé : DB
  confirmant `milesAwarded=1` et le bon score malgré une bannière manquée
  au screenshot — le mécanisme fonctionnait, seule la capture était trop
  tardive).
- Le texte `t.dailyMission.comeBackTomorrow` ("Revenez demain pour un nouveau
  pays.") est visible en bas de l'écran.

**Régression connue liée :** aucune à ce jour — cas le plus complet du
catalogue, couvre la chaîne complète manche→récompense→jalon.

---

## UC-PDJ-06 — Réouverture après complétion ("déjà joué aujourd'hui")

**Précondition (seed) :** profil `allUnlocked`, mission du jour déjà
terminée dans la même session de test (suite UC-PDJ-05). **Il n'existe aucune
tuile de reset pour ce mode** (voir note en tête de fichier) — ce cas ne peut
être testé qu'en enchaînant après une complétion réelle dans le même run, pas
en isolation.

**Repro :**
1. Depuis le debug launcher, retaper la tuile **"Mission du jour"** une
   seconde fois (ou naviguer ailleurs puis y revenir).

**Checkpoint :** capture juste après la (ré)ouverture de l'écran.

**Attendu :**
- L'écran affiche **directement** le récap `DailyCountryRecap` (8 étoiles déjà
  figées, score déjà affiché) — **pas** un retour à l'étape 1 ni un nouveau
  Geordle. `dailyCountryProgressProvider` retourne la ligne existante
  (`getProgressForDate` non-null → retour anticipé, pas de nouvelle
  progression créée).
- La bannière de jalon "Mission quotidienne accomplie !" ne doit **pas**
  réapparaître une seconde fois (`_maybeClaimReward` est gardé par
  `milesAwarded > 0`, sentinelle de "déjà réclamé" — cf.
  `markRewardClaimed()`) — pas de double-attribution du booster.
- Le pays affiché est identique à celui de la session précédente (verrouillé
  par `countryCode` en base, pas retiré au hasard).

**Régression connue liée :** aucune à ce jour — cas ajouté pour couvrir
l'idempotence de la récompense (`milesAwarded` comme sentinelle booléenne),
point sensible identifié dans le code (`markRewardClaimed` doc : "no re-award
on re-opening the recap").
