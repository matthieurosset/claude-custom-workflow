# Catalogue de non-régression visuelle — Carnet de bord

Voir le design : `docs/superpowers/specs/2026-07-07-visual-regression-catalog-design.md`.
Gabarit et niveau de détail attendu : voir `aventure.md` (référence — déjà
validé par un run réel 10/10 PASS le 2026-07-07).

**Exécuté bout-en-bout le 2026-07-07 : 5/6 PASS (avec corrections), 1
UNCLEAR (UC-CARNET-04, limite d'outillage — pas un bug confirmé).** Aucun
bug produit trouvé — uniquement des corrections d'hypothèses de baseline
dans la première rédaction (voir notes "corrigé après run 2026-07-07").

**Notes opérationnelles du run (méthodologie, pas des bugs produit) :**
1. **Un force-stop + relaunch de l'app réapplique intégralement le seed**,
   effaçant toute progression de la session en cours (succès réclamés,
   boosters ouverts, missions hebdo forcées, streak daily-login). Éviter
   tout relaunch inutile en plein milieu d'un repro multi-étapes, ou en
   tenir compte explicitement.
2. **Le tap par coordonnées recalculées depuis un screenshot downscalé
   n'est pas fiable** sur certains éléments (ex. bannière debug launcher —
   6+ échecs constatés). `adb shell uiautomator dump` + parsing des
   `bounds`/`content-desc` pour des coordonnées physiques exactes a
   fonctionné du premier coup — préférer cette méthode pour ce type
   d'élément.

Le Carnet (`lib/pages/modes/carnet/carnet_page.dart`, route `CarnetRoute`)
est **tab-nested sous l'onglet Accueil** (`home/carnet` dans `router.dart`),
pas une route root. `AppNavigator.goToCarnet(context)` y navigue via
`context.router.root.navigate(const CarnetRoute())` — `.navigate`, pas
`.push`, ce qui résout correctement le chemin imbriqué. Un test de non-
régression implicite dans chaque cas ci-dessous : le bouton retour depuis le
Carnet doit ramener sur l'onglet Accueil sans écran bleu (cf. règle de
navigation du CLAUDE.md — violation type = `push`/`root.push` direct au lieu
de la façade).

Trois sections dans l'ordre d'affichage, chacune avec un titre + badge rouge
numéroté (`_SectionTitle`, visible seulement si le compte est > 0) :
**Récompenses** (`sectionInbox` — boosters non ouverts dans l'inbox),
**Missions actives** (`sectionMissions` — quotidienne + hebdo), **Succès**
(`sectionAchievements` — succès révélés non réclamés). Au-dessus des trois
sections : bouton pleine largeur "Mon album des nations" (accès Panini) avec
son propre badge "non-vus" (drapeaux jamais vus) et un compteur `X / 248
pays`.

**Précondition (seed) — vérifiée dans le code :** profil `allUnlocked`
convient à tous les cas. Le seed `allUnlocked` (`test_seed.dart`) ne peuple
**ni l'inbox de récompenses, ni aucune mission complétée** — mais il
débloque les 5 continents au niveau 1 avec **50 000 miles**, ce qui
dépasse déjà la cible de 5 000 miles du succès de maîtrise autonome
**"Globe-trotter"** (`globetrotter`). **Corrigé après run 2026-07-07 :**
contrairement à ce que la première rédaction affirmait, `allUnlocked`
fraîchement installé n'est PAS "zéro badge partout" — la section Succès
affiche déjà le badge **"1"** (Globe-trotter réclamable) et la Home affiche
déjà la pastille rouge, sans aucune action de seed supplémentaire. Seules
les sections Récompenses et Missions actives partent réellement à zéro.

**Accès au debug launcher :** Home → scroller jusqu'en bas → bannière ambrée
**"DEBUG — Lancer n'importe quoi"** (identique à Aventure/Défi — voir
`aventure.md` pour le détail du piège de scroll). Le bouton de seed dédié
Carnet, **"Carnet : remplir (boosters + succès)"** (`ElevatedButton` bleu
primaire, icône `card_giftcard`), est dans cette page (`debug_launcher_page.dart`
ligne ~318, juste sous "Débloquer TOUT"). Son `onTap` fait exactement :
1. `rewardInboxProvider.notifier.grantBoosters([gold, silver, bronze, gold,
   silver, bronze])` — dépose **6 boosters dans l'inbox : 2 or, 2 argent,
   2 bronze**.
2. `adventureNotifierProvider.notifier.debugUnlockEverything()` — monte les
   5 continents au niveau max + ajoute 999 999 miles. **Corrigé après run
   2026-07-07 :** ce bouton ne rend PAS "Conquérant régional"
   (`region_conqueror`, 1 région à 100 %) réclamable — monter une région au
   niveau max n'équivaut pas à 100 % de complétion par pays (qui nécessite
   une vraie progression par activité/pays, absente de ce seed). Le succès
   reste à `0/1`. Le seul succès affecté est **"Globe-trotter"**
   (`globetrotter`, 5 000 miles cumulés) — et il était déjà réclamable
   *avant* même ce bouton (voir note de précondition plus haut, seuil
   dépassé par le seed `allUnlocked` lui-même).
3. Un `SnackBar` confirme "Carnet rempli : 6 boosters + succès réclamables".

Ce seed **ne touche pas** aux missions quotidienne/hebdo (sections
"Missions actives" restent à 0 après ce bouton).

---

## UC-CARNET-01 — Ouverture réelle du Carnet depuis la Home + rendu de base

**Précondition (seed) :** profil `allUnlocked`, **sans** le bouton debug
"Carnet : remplir" (état par défaut, aucune section à réclamer).

**Repro (navigation réelle, PAS le debug launcher — c'est le point du test) :**
1. Depuis l'écran d'accueil, repérer le bloc **"Progression"** (2e section de
   la page, juste sous le bandeau "En ce moment"). Pas besoin de scroller
   loin — la carte est tout de suite après le bandeau de reprise d'Aventure.
2. Taper la carte bleue **"Carnet de bord"** (dégradé bleu, icône carnet,
   sous-titre "Missions, récompenses & succès" via `t.carnet.subtitle`).

**Checkpoint :** capture après navigation vers le Carnet (page stabilisée,
plus de spinner de chargement).

**Attendu :**
- `TransparentAppBar` avec le titre **"Carnet de bord"**.
- Bouton pleine largeur **"Mon album des nations"** en haut, avec le
  compteur `X / 248 pays` centré dessous (X = drapeaux déjà collectés).
- Section **"Récompenses"** : aucun badge numéroté sur le titre (0 booster en
  inbox) ; `InboxSummaryCard` affiche 3 tuiles (or/argent/bronze) **estompées
  (opacité ~0.35)**, chacune `×0`, non tappables.
- Section **"Missions actives"** : aucun badge ; au moins une
  `ActiveMissionCard` visible (mission du jour, label "Mission quotidienne"),
  barre de progression à 0, pas de bouton "Réclamer".
- Section **"Succès"** : **badge "1" déjà présent** (corrigé après run
  2026-07-07 — voir note de précondition : "Globe-trotter" est déjà
  réclamable sur `allUnlocked` fraîchement installé, sans seed
  supplémentaire). La carte "Globe-trotter" est en tête de liste, barre
  pleine, bouton **"Réclamer"** visible. Le reste : une **liste de cartes**
  correspondant au 1ᵉʳ cran de chaque autre chaîne toujours révélée dès le
  départ (succès "découverte" swipe + 6 chaînes Défi + 8 chaînes par
  activité + chaîne album + "Conquérant régional" à 0/1 — une vingtaine de
  cartes au total), chacune avec une barre de progression (généralement à 0
  ou proche de 0), sans bouton "Réclamer".
- Retour arrière (bouton système ou geste) ramène sur l'onglet Accueil, sans
  écran bleu/vide.

**Régression connue liée :** aucune à ce jour — cas de non-régression
préventif sur le chemin de navigation réelle Home → Carnet (route
tab-nested), à l'image de UC-ADV-10 pour Aventure.

---

## UC-CARNET-02 — Seed debug "Carnet : remplir" + état juste après

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher (scroller en bas de la Home → bannière ambrée).
2. Taper **"Carnet : remplir (boosters + succès)"**.
3. Attendre le `SnackBar` de confirmation ("Carnet rempli : 6 boosters +
   succès réclamables").
4. Naviguer vers le Carnet (`AppNavigator.goToCarnet`, ou via la carte Home).

**Checkpoint :** capture juste après l'ouverture du Carnet (page stabilisée).

**Attendu :**
- Section **"Récompenses"** : badge rouge **"6"** sur le titre.
  `InboxSummaryCard` : 3 tuiles pleinement opaques, **`×2`** sur chacune des
  3 (or/argent/bronze), tappables.
- Section **"Missions actives"** : aucun badge (le seed ne touche pas les
  missions) — inchangé par rapport à UC-CARNET-01.
- Section **"Succès"** : badge rouge **"1"** sur le titre (corrigé après run
  2026-07-07 — pas "2", voir note de précondition : le bouton ne rend QUE
  "Globe-trotter" réclamable, "Conquérant régional" reste à 0/1). En tête de
  la liste (les succès réclamables remontent en premier, cf.
  `revealedUnclaimedAchievementsProvider`) : la carte **"Globe-trotter"**,
  barre de progression **pleine** (couleur `AppColors.accent`, orange) et un
  bouton **`AccentButton` "Réclamer"** (icône cadeau) en haut à droite de la
  carte. Les autres cartes (dont "Conquérant régional") restent avec leur
  barre partielle/à 0 et sans bouton.

**Régression connue liée :** aucune à ce jour.

---

## UC-CARNET-03 — Réclamer un succès prêt (Globe-trotter)

**Corrigé après run 2026-07-07 :** un seul succès est réellement
claimable après le seed (Globe-trotter — voir correction UC-CARNET-02),
pas deux. Le sous-test "les autres boutons Réclamer sont désactivés
pendant le cooldown" n'est donc **pas exerçable** avec l'état actuel du
seed (il n'y a qu'un bouton "Réclamer" à l'écran) — retiré ci-dessous.
Pour re-tester ce sous-cas un jour, il faudrait un seed produisant 2
succès claimables simultanément (ex. compléter une région à 100 % via de
vraies lignes de progression par pays, pas juste `debugUnlockEverything()`).

**Précondition (seed) :** profil `allUnlocked` + bouton debug "Carnet :
remplir" (voir UC-CARNET-02) — garantit Globe-trotter claimable (déjà
claimable même sans ce bouton, voir note de précondition en tête de
fichier).

**Repro :**
1. Depuis le Carnet (section Succès avec badge "1"), taper le bouton
   **"Réclamer"** sur la carte **"Globe-trotter"**.

**Checkpoint :** deux captures — (a) juste après le tap (bouton en état
`loading`, spinner), (b) ~1 s après (animation de réorganisation de liste
terminée).

**Attendu :**
- (a) Le bouton "Réclamer" tapé passe en état chargement.
- (b) La carte "Globe-trotter" **disparaît** de la section Succès (animée :
  fondu + léger glissement, `AnimatedSize`). Le badge du titre "Succès"
  passe de **1 à 0** (disparaît complètement, plus aucun succès claimable).
  La tuile de tier correspondant à la récompense du succès dans
  l'`InboxSummaryCard` (section Récompenses) **rebondit** (scale
  1 → 1.35 → 1, `elasticOut`) sous une **salve de confettis** et son
  compteur s'incrémente de 1. Le badge du titre "Récompenses" s'incrémente
  d'autant.

**Régression connue liée :** aucune à ce jour — vérifie la chaîne complète
réclamation succès → crédit inbox → réaction visuelle de l'`InboxSummaryCard`
(rebond/confettis), un chemin de code partagé avec les récompenses de
missions et de paliers.

---

## UC-CARNET-04 — Ouvrir un booster depuis la vitrine "Récompenses"

**Exécuté le 2026-07-07 : UNCLEAR — pas un bug confirmé, limite
d'outillage.** La navigation vers `BoosterOpenRoute` et l'animation
d'ouverture (tier or) sont confirmées correctes. Mais le geste de
"déchirure" (swipe-tear) custom de l'écran d'ouverture n'a pas pu être
complété via `adb input swipe`/`draganddrop` (le geste reste bloqué
mi-parcours) — même famille de limite que le drag-and-drop de Classement
dans `defi.md`. Pendant que le geste était bloqué, la touche Back système
n'a rien fait (pas de retour au Carnet) ; **impossible de déterminer** si
c'est un comportement intentionnel (UX "engagement" une fois le tear
commencé) ou un vrai trou, faute d'avoir pu terminer/annuler proprement le
geste. **À refaire avec un outillage de geste plus fiable** (swipes
chaînés courts avec pauses, ou mobile-mcp si disponible) avant de conclure
sur le retour arrière.

**Précondition (seed) :** profil `allUnlocked` + bouton debug "Carnet :
remplir" (inbox non vide garantie, ≥ 2 boosters par tier).

**Repro :**
1. Depuis le Carnet (section "Récompenses" visible, tuiles pleinement
   opaques), taper la tuile **or** de l'`InboxSummaryCard`.

**Checkpoint :** capture juste après le tap (nouvel écran affiché).

**Attendu :**
- Navigation vers l'écran d'ouverture de booster (`BoosterOpenRoute`, route
  **root** — `AppNavigator.openBoosterOpen` fait `context.router.root.push`,
  cohérent avec la règle de navigation du CLAUDE.md : `BoosterOpenRoute` est
  une route root, jamais tab-nested).
- L'écran affiche l'animation d'ouverture du booster **or** correspondant à
  la première entrée de l'inbox de ce tier (`inboxEntryId:
  ofTier.first.id`).
- Retour arrière depuis cet écran ramène proprement sur le Carnet (pas
  d'écran bleu — la règle root-scope existe précisément pour éviter ce bug
  sur ce genre d'écran fullscreen lancé depuis un onglet).

**Régression connue liée :** famille "écran bleu au Back" documentée en
mémoire (`feedback_overlay_router_navigate_not_push_nested_route`,
`feedback_fullscreen_game_route_must_be_root_not_tab_child`) — ce cas est un
candidat direct si `openBoosterOpen` régresse vers un `push` non-root.

---

## UC-CARNET-05 — Badge (pastille) de l'entrée Carnet sur la Home

**Précondition (seed) :** profil `allUnlocked`.

**Repro — partie A (avant seed) :**
1. Depuis la Home, observer la carte **"Carnet de bord"** (bloc
   "Progression") : icône carnet blanche à gauche du titre.

**Checkpoint A :** capture de la carte Home, zoom sur l'icône carnet.

**Attendu A (corrigé après run 2026-07-07) :** **la pastille rouge est déjà
visible** sur l'icône même avant tout seed — Globe-trotter est réclamable
dès l'installation `allUnlocked` (voir note de précondition en tête de
fichier). Le badge Home est un simple point rouge de 13 px avec liseré
blanc (`hasClaimable`, pas un chiffre — cf. `_CarnetSummaryCard` dans
`lib/pages/home/page.dart`). Pas de panneau "vitrine boosters" sous la
carte à ce stade (n'apparaît que si l'inbox n'est pas vide — elle l'est
encore avant le seed debug).

**Repro — partie B (après le seed debug "Carnet : remplir") :**
2. Debug launcher → **"Carnet : remplir (boosters + succès)"**.
3. Revenir/rafraîchir la Home (la carte est reconstruite par les providers
   Riverpod, pas besoin de relancer l'app).

**Checkpoint B :** capture de la carte Home après le seed.

**Attendu B :**
- **Pastille rouge visible** sur l'icône carnet — car
  `carnetBadgeCountProvider` (6 boosters + 2 succès réclamables = 8) moins
  `inbox.length` (6) = **2 > 0** (des succès sont réclamables, pas seulement
  des boosters non ouverts).
- Un **panneau "vitrine"** apparaît sous le titre de la carte, à liseré doré,
  montrant les 3 icônes de tier avec leurs comptes (`2x` sur chacune) — la
  jauge d'album (`_AlbumRing`, roue de progression à droite) reste
  inchangée, ce n'est pas un indicateur de réclamation.

**Repro — partie C (après réclamation des 2 succès, cf. UC-CARNET-03) :**
4. Dans le Carnet, réclamer "Conquérant régional" **et** "Globe-trotter"
   (badge Succès repasse à 0).
5. Revenir sur la Home.

**Checkpoint C :** capture de la carte Home.

**Attendu C :** la **pastille rouge disparaît** (badge global = inbox.length
+ 0 succès claimable + 0 mission claimable, donc `hasClaimable` redevient
faux) — même si l'inbox contient maintenant 8 boosters non ouverts (6 + 2 de
récompense), car la pastille est **volontairement réservée aux éléments
"à réclamer"**, pas aux boosters "déjà en poche mais pas encore ouverts" (ces
derniers ont leur propre affordance : le panneau vitrine + le bouton
"Ouvrir" dans le Carnet). Le panneau vitrine, lui, reste affiché avec les
comptes à jour (`2x` or devient `3x` après la réclamation de "Conquérant
régional" en UC-CARNET-03, par exemple).

**Régression connue liée :** aucune à ce jour — ce cas encode explicitement
la distinction "pastille = réclamable" vs "vitrine = inbox non ouverte", un
piège de lecture facile pour un futur refactor de `carnetBadgeCountProvider`
ou de `_CarnetSummaryCard` (les deux compteurs sont proches mais pas
identiques, cf. commentaire "HORS boosters" dans le code).

---

## UC-CARNET-06 — Mission hebdo forcée apparaît dans "Missions actives"

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → section dédiée aux missions (chips `FilterChip`, un par
   `MissionCatalog.weekly`, sous le bouton "Carnet : remplir").
2. Sélectionner un chip de mission hebdo non déjà active (le chip passe à
   l'état sélectionné, fond orange `AppColors.accent`).
3. Naviguer vers le Carnet.

**Checkpoint :** capture de la section "Missions actives" du Carnet.

**Attendu :**
- Une `ActiveMissionCard` supplémentaire apparaît, avec le badge
  **"Mission hebdo"** (`t.carnet.missionWeekly`, pastille bleue) en haut à
  gauche de la carte, titre/description résolus via `missionTitle`/
  `missionDescription` (pas de clé i18n brute affichée type `d_defi5`).
- Barre de progression à 0 (ou à la valeur déjà accumulée si des events de
  jeu pertinents ont eu lieu depuis le lancement), pas de bouton "Réclamer"
  tant que la cible n'est pas atteinte.
- Aucun crash ni doublon si le même chip est désélectionné puis resélectionné
  (le set forcé est en mémoire seulement, effacé au hot-restart — ne pas
  confondre avec une régression si une mission "disparaît" après un
  hot-restart pendant un run de test).

**Régression connue liée :** aucune à ce jour — cas de couverture pour le
rendu de la section "Missions actives" au-delà de la seule mission
quotidienne par défaut (UC-CARNET-01 n'exerçait qu'un seul type de carte).
