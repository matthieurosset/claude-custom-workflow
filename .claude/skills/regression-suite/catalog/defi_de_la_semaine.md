# Catalogue de non-régression visuelle — Défi de la semaine

Voir le design : `docs/superpowers/specs/2026-07-07-visual-regression-catalog-design.md`.
Gabarit et niveau de détail attendu : voir `aventure.md` (référence — déjà
validé par un run réel 10/10 PASS le 2026-07-07).

**Exécuté le 2026-07-07 : UC-DEFISEM-01 à 04 PASS, UC-DEFISEM-05 BLOQUÉ**
(nécessite une écriture admin Firestore sans outillage existant — refusé
plutôt que forcé, conforme à la consigne). Un défi hebdo existait déjà
côté serveur pour la semaine ISO courante (`2026-W28`, type geohunter),
vérifié en lecture seule avant de commencer — aucun état n'a été semé pour
ce run.

**⚠️ Piste de bug trouvée en marge, non confirmée (flaky, auto-résolue
sur retry) :** au tout début du run, la page ET la tuile Home ont affiché
l'état vide ("Pas d'épreuve cette semaine") alors qu'un admin read
confirmait au même moment que le document existait bien côté serveur. Un
redémarrage à froid complet a immédiatement corrigé l'affichage. Aucune
exception en logcat dans les deux cas — attendu, puisque
`FirebaseWeeklyChallengeService.fetchForWeek` avale **toute** erreur en
`null` (`lib/core/services/firebase/firebase_weekly_challenge_service.dart:17-28`),
rendant un échec réseau transitoire indiscernable d'une vraie absence de
défi configuré. Un seul occurrence, non reproduite une seconde fois dans
ce run — pas assez de signal pour un correctif ciblé (pas de root cause
isolable sans repro fiable), mais le risque de conception (erreur muette)
est réel et mérite un suivi si le symptôme réapparaît en prod (surtout un
lundi matin si l'admin n'a pas encore relancé `set_weekly_challenge.js`).

Ce fichier couvre uniquement l'**orchestration hebdomadaire**
(`lib/pages/modes/defi/weekly/`, `weeklyChallengeProvider`,
`FirebaseWeeklyChallengeService`, `FirebaseWeeklyRewardService`) — pas les
mécaniques internes des jeux sous-jacents (Classement, Plus ou Moins,
GéoHunter), déjà couvertes par `defi.md`, ni le fonctionnement générique de
la carte `LeaderboardPreviewCard` (Top 5 + ligne "Toi" — cf. mémoire projet
`feedback_leaderboard_toi_highlight_uid_only_not_score`, déjà un risque connu
et hors périmètre de ce fichier). Ne pas dupliquer les cas de `defi.md`.

**Différence structurante avec Défi du jour (`defi_du_jour.md`) : tout est
cloud, rien n'est local.** Défi du jour résout et persiste son défi en
SQLite au premier accès (idempotent, hors-ligne après la 1ère résolution).
Défi hebdo, lui, lit **exclusivement** `weekly_challenges/{weekId}` sur
Firestore à chaque ouverture de page (`FirebaseWeeklyChallengeService.fetchForWeek`,
pas de cache local, pas de fallback) — sans réseau ou sans document
existant pour la semaine ISO courante, la page affiche l'état vide, jamais
une erreur. **Corollaire : tous les cas ci-dessous, sauf mention contraire,
nécessitent un émulateur avec accès réseau réel au projet Firebase
`mission-geo-dev`** (flavor dev) — voir mémoire
`feedback_emulator_suite_must_boot_dev_project`. Aucun seed SQLite
(`TestSeed.apply`, tous profils) ne touche à quoi que ce soit lié au défi
hebdo — profil `allUnlocked` convient partout, il ne fait ni bien ni mal ici.

**Aucune tuile debug dédiée reroll/reset pour Défi hebdo** (contrairement à
Défi du jour, section "Défi — Autres" du debug launcher, qui a "changer" et
"reset score"). Le seul levier pour changer le contenu du défi hebdo côté
serveur est le script admin `scripts/set_weekly_challenge.js` (Node,
firebase-admin, ADC), qui **remplace intégralement** (`merge: false`) le
document `weekly_challenges/{weekId}` — jamais un outil in-app. Exemple pour
préparer un cas déterministe :
```bash
cd functions && npm install   # une fois
cd .. && node scripts/set_weekly_challenge.js --project dev \
  --type classement --region World \
  --indicators population,area,gdp,gdpPerCapita,density,lifeExpectancy,happiness,borderCount
```
`--week-id` par défaut = semaine ISO courante (Europe/Zurich) ; passer une
valeur explicite pour préparer par avance une semaine future sans perturber
celle en cours.

**Accès au debug launcher :** Home → scroller jusqu'en bas → bannière ambrée
**"DEBUG — Lancer n'importe quoi"** → section **"Défi — Autres"** → tuile
**"Défi hebdo"** (`Icons.calendar_today`, `lib/pages/debug/debug_launcher_page.dart:397-401`)
→ `context.router.push(const WeeklyChallengeRoute())` — push tab-scopé
(conforme aux règles de navigation, `WeeklyChallengePage` n'est pas un
canvas de jeu).

**Entrée en navigation réelle (hors debug launcher) :** tuile "Défi de la
semaine" sur la Home (`_WeeklyTile`, zone "En ce moment", `lib/pages/home/page.dart`)
— pousse la même `WeeklyChallengeRoute`. Contrairement à Défi du jour, cette
tuile Home affiche en plus, en hero central, **le rang actuel de
l'utilisateur** dans le classement hebdo (`# X` ou "Non classé" si jamais
participé cette semaine) via `userGlobalRankProvider` — une lecture RTDB
live indépendante de celle de la page dédiée. Bon point de contrôle croisé.

**Récompense : payée au niveau du RANG final, pas d'un score-cible — et
livrée uniquement à la clôture de la semaine (fonction planifiée
`_weeklyBoostersForRank` dans `functions/index.js`, doc
`weekly_rewards/{uid}`), jamais pendant que la semaine est en cours.**
Barème : rang 1 → 3× booster or, rang 2 → 1× or, rang 3 → 1× argent, rang 4+
→ 1× bronze (affiché tel quel dans le tableau de récompenses en bas de
`WeeklyChallengePage`, `_RewardLine`). Le client lit et crédite ce doc au
lancement de l'app (`SplashScreen` → `fetchAndCreditWeeklyRewards`), jamais
pendant une session de jeu — voir UC-DEFISEM-05.

---

## UC-DEFISEM-01 — Lancement et framing du défi hebdo

**Précondition (seed) :** profil `allUnlocked`. **Précondition réseau :** un
document `weekly_challenges/{semaine ISO courante}` doit exister sur
Firestore dev — vérifier au besoin avec `set_weekly_challenge.js` (voir
commande ci-dessus) avant de commencer, sinon ce cas retombe sur l'état vide
de UC-DEFISEM-04 au lieu du contenu attendu ici.

**Repro :**
1. Debug launcher → section "Défi — Autres" → tuile **"Défi hebdo"**.
2. La page `WeeklyChallengePage` s'affiche (`TransparentAppBar`, titre
   "Défi de la semaine").

**Checkpoint :** capture de la page une fois le `FutureProvider`
(`weeklyChallengeProvider`) résolu (pas de spinner visible).

**Attendu :**
- Carte de règles (`_RulesCard`) : descripteur "`{type} · {région}`" (ex.
  "Classement · Monde") — jamais de texte vide/`null`. Sous le descripteur,
  une phrase de mécanique cohérente avec le type tiré (`t.weekly.mechanicGeohunter`
  / `mechanicClassement` / `mechanicPlusOuMoinsSingle` / `mechanicPlusOuMoinsMixed`),
  puis un chip indicateur(s) — **corrigé après run 2026-07-07 : ce chip
  n'est affiché QUE pour `classement`/`plus_ou_moins`**
  (`weekly_challenge_page.dart:182-231`) — **absent pour `geohunter`**, ce
  n'est pas un défaut si aucun chip n'apparaît sur ce type.
- Tableau de récompenses (`_RewardLine`) sous la carte de règles : 4
  colonnes — 🥇 (3× booster or empilés avec badge "×3"), 🥈 (1× or), 🥉
  (1× argent), "Autres" (1× bronze) — les icônes de tier correspondent
  visuellement à celles utilisées dans l'inbox récompenses/l'album Panini
  (pas d'icône générique/placeholder).
- Bouton **"Jouer"** (`TicketGatedStartButton`, orange, solde de tickets
  affiché au-dessus, coût de lancement 1 ticket, même gate que les autres
  modes Défi). **Corrigé après run 2026-07-07 :** ne pas attendre
  exactement 25 — un dialog de connexion quotidienne ("Content de te
  revoir !") peut créditer des tickets bonus avant cet écran (observé 30 =
  25 + 5) ; vérifier la cohérence des variations plutôt qu'un chiffre figé.
- `WeekCountdown` (forme complète, préfixe "Se termine dans …") affiche une
  durée positive et plausible (entre 0 et 7 jours) — jamais de valeur
  négative, "NaN", ou figée à zéro pendant que l'horloge tourne.
- Carte `LeaderboardPreviewCard` en bas — Top 5 + éventuellement la ligne
  "Toi" hors podium ; peut être vide/quasi-vide en tout début de semaine
  (aucune régression à en déduire, juste un état légitime).
- **Corrigé après run 2026-07-07 :** la tuile Home (`_WeeklyTile`,
  `lib/pages/home/page.dart:705-768`) n'affiche **jamais** de descripteur
  type/région — seulement titre, rang (hero central) et countdown
  compact. Il n'y a donc rien à comparer avec la carte de règles sur ce
  point ; le seul contrôle croisé valide entre page dédiée et tuile Home
  est le **rang** (couvert par UC-DEFISEM-02).

**Régression connue liée :** aucune à ce jour — premier cas de ce fichier,
sert de référence pour tous les cas suivants.

---

## UC-DEFISEM-02 — Jouer une partie : soumission du score et mise à jour du rang

**Précondition (seed) :** profil `allUnlocked`, UC-DEFISEM-01 exécuté juste
avant (même run, défi hebdo déjà affiché et son type noté).

**Repro :**
1. Depuis `WeeklyChallengePage`, noter le rang affiché sur la tuile Home
   AVANT de jouer (probablement "Non classé" si première participation de la
   semaine).
2. Taper **"Jouer"** — route vers l'un des 3 jeux hebdo
   (`WeeklyClassementGamePage` / `WeeklyGeohunterGamePage` /
   `WeeklyPlusOuMoinsGamePage`, selon le type tiré à l'étape UC-DEFISEM-01).
   Chacun délègue entièrement au jeu Défi standard correspondant (mécaniques
   déjà couvertes par `defi.md`, ne pas re-décrire ici) avec une
   `WeeklyLeaderboardBinding` qui route la soumission de score vers
   `(challengeType: "weekly", region: <semaine ISO>)`.
3. Jouer jusqu'au game-over.
4. Sur l'écran de fin, observer la carte `LeaderboardPreviewCard` (mêmes
   mécaniques que `defi.md` — pas de carte de résultat hebdo dédiée
   contrairement à Défi du jour, il n'y a pas de notion de "meilleur score
   du jour"/cible à atteindre ici, juste un classement continu).
5. Retour à `WeeklyChallengePage` (ou Home), rafraîchir/rouvrir la page.

**Checkpoint :** deux captures — (a) écran de fin avec l'aperçu classement
juste après soumission, (b) tuile Home "Défi de la semaine" après retour,
rang mis à jour.

**Attendu :**
- (a) Le score vient d'être soumis sans erreur silencieuse (pas de blocage
  ni de carte de classement restée en `loading` indéfiniment).
- (b) Le rang affiché sur la tuile Home passe de "Non classé" à `# X` (ou
  reste `# X` avec une valeur cohérente si ce n'était pas la première
  partie de la semaine) — preuve que l'écriture RTDB de la partie a bien
  été prise en compte par la lecture `userGlobalRankProvider`, sans
  redémarrage de l'app.
- La carte de règles de `WeeklyChallengePage` reste strictement identique
  avant/après (même type, même région/variante) — jouer une partie ne
  reroule jamais le défi de la semaine (contrairement au "changer" de Défi
  du jour, qui n'a pas d'équivalent ici de toute façon).

**Régression connue liée :** aucune à ce jour — cas ajouté pour vérifier
spécifiquement le binding `WeeklyLeaderboardBinding` (soumission sous la
bonne paire `challengeType`/`region`) et la lecture croisée
page-dédiée/tuile Home du rang, jamais exercés par `defi.md`.

---

## UC-DEFISEM-03 — Sanité du countdown (`WeekCountdown`, formes complète et compacte)

**Précondition (seed) :** profil `allUnlocked`. Précondition réseau :
identique à UC-DEFISEM-01 (un défi doit être configuré pour éviter l'état
vide, qui n'affiche pas le countdown sur la tuile Home — voir UC-DEFISEM-04).

**Repro :**
1. Ouvrir `WeeklyChallengePage` (debug launcher → "Défi hebdo").
2. Noter la valeur du countdown affichée (forme complète, "Se termine dans
   Xj YYh" si > 24h restantes, sinon "H:MM:SS").
3. Attendre ~5 secondes sans quitter l'écran, noter à nouveau la valeur.
4. Retour Home, comparer avec la forme compacte de la tuile "Défi de la
   semaine" (`WeekCountdown(compact: true)`, pas de préfixe "Se termine
   dans", juste l'icône horloge + la durée).

**Checkpoint :** deux captures — (a) `WeekCountdown` sur la page dédiée à
l'instant T, (b) la tuile Home au même instant (± quelques secondes).

**Attendu :**
- La valeur décroît entre les deux lectures de l'étape 3 (le timer
  `Timer.periodic(1s)` tourne réellement, pas figé). **Corrigé après run
  2026-07-07 :** `_formatDuration` (`week_countdown.dart:68-77`) n'a une
  granularité jour+heure que si > 24h restent — avec plusieurs jours
  restants (cas courant), une attente de 5s ne fait apparaître **aucun**
  changement visible même si le timer interne tourne réellement (vérifié
  par lecture de code, pas par observation runtime, faute de fenêtre
  d'une heure disponible pendant ce run). Le repro doit soit attendre un
  changement d'heure pleine, soit accepter qu'un libellé statique sur 5s
  n'est PAS une preuve de timer figé dans cette plage.
- Jamais de valeur négative, de format cassé ("--:--", "NaN", texte vide)
  même si l'exécution du test tombe pile autour d'un lundi 00:00
  Europe/Zurich (garde explicite dans `_timeUntilNextMonday` pour ce cas
  limite — improbable à observer en pratique mais la garde existe).
- Les deux formes (complète et compacte) restent cohérentes entre elles à
  quelques secondes près (même ordre de grandeur de jours/heures restants) —
  pas de dérive de fuseau horaire entre les deux affichages.

**Régression connue liée :** aucune à ce jour — cas préventif, le calcul de
date dépend d'un fuseau horaire explicite (`Europe/Zurich` via le package
`timezone`) qui a déjà été une source de bugs de "minuit" ailleurs dans le
projet (cf. mémoire `feedback_daily_data_midnight_stale_warm_process`, même
famille de risque bien que ce cas précis n'ait jamais été signalé sur le
countdown hebdo).

---

## UC-DEFISEM-04 — État vide (aucun défi configuré pour la semaine)

**Précondition (seed) :** profil `allUnlocked`. **Précondition réseau :** le
document `weekly_challenges/{semaine ISO courante}` doit être **absent** sur
Firestore dev pour ce cas — nécessite un accès admin Firestore (console ou
`firebase-admin`) pour le supprimer temporairement, ou tester sur une
semaine ISO future jamais configurée en passant un `--week-id` qui n'existe
pas encore (mais alors `currentWeekIdProvider` ne correspondra pas — ce
n'est testable qu'en supprimant réellement le doc de la semaine courante, ou
en interceptant tôt en début de déploiement avant la première exécution de
`set_weekly_challenge.js` de la semaine). **Cas le plus lourd à mettre en
place de ce fichier — à exécuter en dernier, et seulement si le temps le
permet ; ne bloque pas la validation des autres cas.**

**Repro :**
1. Confirmer l'absence du doc (lecture console Firebase ou script one-off).
2. Debug launcher → "Défi hebdo".
3. Retour Home, observer la tuile "Défi de la semaine".

**Checkpoint :** deux captures — (a) `WeeklyChallengePage` en état vide, (b)
tuile Home en état vide.

**Attendu :**
- (a) Icône `calendar_today_outlined` 64px + titre "Pas d'épreuve cette
  semaine" (`t.weekly.emptyTitle`) + corps "Reviens bientôt : une nouvelle
  épreuve hebdomadaire arrive." (`t.weekly.emptyBody`) — pas de bouton
  "Jouer", pas de carte de règles, pas de crash/écran blanc.
- (b) La tuile Home affiche seulement "Pas d'épreuve cette semaine" centré,
  sans countdown ni rang — jamais une tuile à moitié peuplée (ex. countdown
  affiché sans descripteur).
- Aucune exception non interceptée dans les logs malgré l'absence du
  document (le service catch et retourne `null`, jamais de throw à l'UI —
  vérifiable aussi en coupant le réseau de l'émulateur au lieu de supprimer
  le doc, comportement attendu identique : état vide, pas de crash).

**Régression connue liée :** aucune à ce jour — cas ajouté car
`FirebaseWeeklyChallengeService.fetchForWeek` n'a aucun cache local ni
fallback (contrairement à Défi du jour, résolu et persisté en SQLite dès la
première lecture) : toute panne réseau ou document manquant reproduit
exactement cet état, potentiellement chaque lundi matin si l'admin oublie de
lancer `set_weekly_challenge.js` pour la nouvelle semaine avant que des
joueurs n'ouvrent l'app.

---

## UC-DEFISEM-05 — Parcours de réclamation de récompense (dialog de célébration au lancement)

**Précondition (seed) :** profil `allUnlocked`. **Précondition réseau/admin
lourde — ce cas ne peut PAS être piloté par une partie jouée en direct** :
la récompense n'est écrite dans `weekly_rewards/{uid}` que par la fonction
planifiée serveur à la clôture réelle de la semaine (lundi 00:00
Europe/Zurich), qu'on ne peut pas déclencher à la demande depuis le client.
Pour valider ce chemin sans attendre une vraie clôture de semaine, un accès
admin Firestore (console ou `firebase-admin` ad hoc, pas de script fourni
dans `scripts/` pour ça — à écrire au besoin sur le modèle de
`set_weekly_challenge.js`) est nécessaire pour écrire manuellement un
document `weekly_rewards/{uid}` avec la forme attendue par
`FirebaseWeeklyRewardService.fetchPendingRewards` (un ou plusieurs
`{weekId, rank, boosters}`) sur le compte de test dev. **C'est précisément
la zone qui a eu un vrai incident de production le 2026-07-06** (race
delete-avant-credit + popup fragile — voir mémoire
`project_weekly_reward_delivery_bug_2026_07_06`) : le chemin de crédit
lui-même a été prouvé sain séparément, ce cas-ci couvre seulement le
parcours UI visible, pas la fenêtre de course de ~18ms qui n'est pas
testable manuellement.

**Repro :**
1. (Préparation admin, hors app) Écrire un document `weekly_rewards/{uid du
   compte de test dev}` avec au moins une entrée `{weekId: "<semaine
   passée>", rank: 1, boosters: ["gold", "gold", "gold"]}` (rang 1 pour
   déclencher le titre "gagné", cf. Attendu).
2. Forcer un cold start de l'app (force-stop puis relancer) pour repasser
   par `SplashScreen`.
3. Attendre la fin du splash — navigation vers Home.

**Checkpoint :** capture du dialog de célébration dès son apparition
(post-frame callback après montage de `HomeRoute`, donc juste après l'écran
Home visible, éventuellement après le dialog "welcome back" du login
quotidien s'il apparaît aussi — les deux sont séquencés, pas empilés).

**Attendu :**
- Dialog `StandardDialog` (canonique, jamais un `AlertDialog`) avec titre
  "Tu as gagné l'épreuve de la semaine !" (`t.weekly.rewardWonTitle`) pour
  rang 1, ou "Récompense de l'épreuve de la semaine !"
  (`t.weekly.rewardParticipationTitle`) pour tout autre rang testé.
- Corps : burst de confettis + les boosters gagnés affichés (mêmes icônes
  de tier que `_RewardLine` sur la page dédiée — 3 boosters or dans ce
  repro).
- Bouton unique "Continuer" (pas de bouton d'annulation — `showCancel:
  false`).
- Après fermeture du dialog, le(s) booster(s) sont visibles dans l'inbox
  récompenses (badge Carnet, ou ouverture directe si le flux d'inbox le
  permet) — vérifier qu'ils sont bien crédités, pas juste affichés puis
  perdus.
- **Idempotence** : un second cold start (force-stop + relance) juste après
  ne doit **pas** réafficher le même dialog — le doc distant a été supprimé
  après crédit confirmé en local (`processed_weekly_rewards`), tout comme
  l'inbox ne doit pas avoir été re-créditée une deuxième fois (pas de
  doublon de boosters).

**Régression connue liée :** l'incident du 2026-07-06 documenté dans
`project_weekly_reward_delivery_bug_2026_07_06` (mémoire projet) portait sur
une race delete-avant-credit et un popup fragile dans ce chemin exact — la
cause profonde (course ~18ms) n'est pas reproductible ici, mais ce cas
couvre la régression la plus probable si une régression *visible*
réapparaissait : dialog qui ne s'affiche jamais, s'affiche en double, ou
crédite les boosters sans jamais montrer le dialog (désynchronisation
crédit/affichage).
