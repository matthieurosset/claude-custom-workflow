# Catalogue de non-régression visuelle — Aventure

Voir le design : `docs/superpowers/specs/2026-07-07-visual-regression-catalog-design.md`.

**Validé par un run bout-en-bout réel le 2026-07-07 : 10/10 PASS, aucune
régression produit trouvée.** Ce fichier a été corrigé après ce run pour
refléter le comportement réel observé (voir les notes "corrigé après run
2026-07-07" sur chaque point qui différait de la première rédaction).

Pays de test par défaut : **France (FR)**, région **europe**. Choisi arbitrairement
pour sa couverture complète (drapeau, capitale, forme, blason, landmark, hymne
tous présents) — changer de pays si un cas révèle un problème spécifique à FR
pour isoler si c'est un bug général ou un problème de données pour ce pays précis.

Tous les cas UC-ADV-01 à 09 utilisent le **debug launcher** pour sauter
directement dans l'état voulu — rapide, fiable, contourne la navigation
normale. UC-ADV-10 est volontairement en **navigation réelle** (barre
d'onglets) car c'est le seul moyen de couvrir le vrai parcours de déblocage.

**Accès au debug launcher (corrigé après run 2026-07-07) :** Home → scroller
jusqu'en bas → bannière ambrée **"DEBUG — Lancer n'importe quoi"**. Pas de
route directe testée. La position de scroll de la Home se réinitialise en
haut après un retour depuis un jeu — rescroller à chaque fois.

**Piège clavier (corrigé après run 2026-07-07) :** `adb input text` ne
fonctionne PAS sur les jeux de saisie Aventure — ils utilisent un clavier
Flutter custom in-app. Il faut taper touche par touche + utiliser la puce
d'autocomplétion qui apparaît.

**Note debug launcher :** la tuile "Typing · map_placement" est un sous-produit
non canonique de la boucle de génération des tuiles — ne pas l'utiliser,
utiliser la tuile dédiée "Searching" à la place (voir UC-ADV-08).

---

## UC-ADV-01 — Bonne réponse, Typing · Drapeau (flag_typing)

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher (voir accès ci-dessus).
2. Section Aventure : région `europe`, code pays `FR`.
3. Taper la tuile **"Typing · flag_typing"**.
4. Le jeu affiche le drapeau français ; taper "France" (clavier in-app,
   touche par touche + puce d'autocomplétion) et valider.

**Checkpoint :** capture juste après validation de la réponse (bulle de
feedback visible).

**Attendu :**
- Bulle de feedback **verte**, message **"Bravo !"** (corrigé après run
  2026-07-07 — pas d'icône `check_circle` ni de texte "Correct", c'est une
  bulle simple verte + texte "Bravo !").
- Le score/compteur de bonnes réponses de la session s'incrémente
  (visible dans le HUD du jeu).
- Pas d'inversion de couleur (vert = correct, jamais rouge sur une bonne
  réponse).

**Régression connue liée :** bulle de feedback aux couleurs inversées entre
succès et échec, introduite puis corrigée dans la même session le 2026-07-06
(commits `8fdf49c8`/`b2aa2cb2`, fichier `lib/pages/games/common/feedback_overlay.dart`).
Ce cas doit être le premier à détecter une régression de ce type.

---

## UC-ADV-02 — Bonne réponse, Typing · Capitale (capital_typing)

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → Aventure → région `europe`, code pays `FR`.
2. Tuile **"Typing · capital_typing"**.
3. **Important :** la capitale affichée ("Paris") est le PROMPT, pas la
   réponse attendue — taper le nom du PAYS ("France"), pas la capitale.
   (cf. mémoire `feedback_capital_is_prompt_not_typed_answer` — un agent qui
   tape "Paris" produira un faux FAIL. Confirmé correctement géré au run
   2026-07-07.)
4. Valider.

**Checkpoint :** capture après validation.

**Attendu :** identique à UC-ADV-01 (bulle verte "Bravo !", score
incrémenté). Vérifier aussi que "Paris" est bien affiché comme la question et
non comme un champ pré-rempli.

---

## UC-ADV-03 — Bonne réponse, Typing · Forme (shape_typing)

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → Aventure → région `europe`, code pays `FR`.
2. Tuile **"Typing · shape_typing"**.
3. Le jeu affiche la silhouette du pays ; taper "France" et valider.

**Checkpoint :** capture après validation.

**Attendu :** identique à UC-ADV-01. Vérifier en plus que la silhouette
affichée est bien reconnaissable (pas de path SVG cassé/vide — cf. mémoire
`feedback_flag_svg_no_transform`, zéro transform attendu sur les SVG).

---

## UC-ADV-04 — Bonne réponse, Typing · Blason (coats_typing)

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → Aventure → région `europe`, code pays `FR`.
2. Tuile **"Typing · coats_typing"**.
3. Le jeu affiche le blason (WebP, pas de variante SVG) ; taper "France" et
   valider.

**Checkpoint :** capture après validation.

**Attendu :** identique à UC-ADV-01. Vérifier que l'image de blason est le
bon pays (pas de décalage d'index vs le pays demandé).

---

## UC-ADV-05 — Bonne réponse, Typing · Lieu emblématique (landmark_typing)

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → Aventure → région `europe`, code pays `FR`.
2. Tuile **"Typing · landmark_typing"**.
3. Le jeu affiche une photo de lieu emblématique (Tour Eiffel pour FR) ;
   taper "France" et valider.

**Checkpoint :** capture après validation.

**Attendu :** identique à UC-ADV-01. Vérifier que la photo se charge (pas de
placeholder cassé) et correspond bien à un lieu du pays demandé.

---

## UC-ADV-06 — Bonne réponse, Typing · Hymne (anthem_typing)

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → Aventure → région `europe`, code pays `FR`.
2. Tuile **"Typing · anthem_typing"**.
3. L'hymne se **lance automatiquement** à l'entrée sur l'écran (corrigé
   après run 2026-07-07 — pas de tap manuel sur play nécessaire). Taper
   "France" et valider.

**Checkpoint :** deux captures — (a) juste après l'entrée sur l'écran
(indicateur de lecture en cours visible), (b) après validation de la
réponse.

**Attendu :**
- (a) L'indicateur de lecture montre bien un état "en cours" (pas un bouton
  figé qui ne réagit jamais).
- (b) identique à UC-ADV-01.

---

## UC-ADV-07 — Bonne réponse, Drawing (flag_drawing)

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → Aventure → région `europe`, code pays `FR`.
2. Tuile **"Drawing"**.
3. Colorier chaque zone du drapeau français avec la couleur attendue (une
   zone = une couleur, palette affichée en bas de l'écran).
4. Taper le bouton **"Valider"** une fois toutes les zones coloriées
   (corrigé après run 2026-07-07 — ce n'est PAS automatique, il y a bien un
   bouton "Valider" qui s'active une fois toutes les zones remplies).

**Checkpoint :** capture après le tap "Valider" (écran de fin/feedback).

**Attendu :**
- Chaque zone tapée se remplit immédiatement de la couleur sélectionnée.
- Le bouton "Valider" ne s'active qu'une fois toutes les zones correctement
  coloriées.
- Aucune fuite visuelle d'un champ image (le raster ne doit jamais laisser
  transparaître un fragment d'une autre image/texture — cf. mémoire
  `feedback_drawing_coat_no_field_leak`).

---

## UC-ADV-08 — Bonne réponse, Searching (map_placement)

**Précondition (seed) :** profil `allUnlocked`.

**Repro :**
1. Debug launcher → Aventure → région `europe`, code pays `FR`.
2. Tuile **"Searching"** (PAS "Typing · map_placement", voir note en tête de
   fichier).
3. Une carte s'affiche ; taper sur le territoire de la France sur la carte.
   **Attention (corrigé après run 2026-07-07) :** la carte est pannable —
   un tap peut la faire glisser plutôt que sélectionner un pays si le point
   de contact tombe entre deux gestes ; viser un tap franc et net au centre
   du territoire.

**Checkpoint :** capture après le tap (surbrillance persistante attendue).

**Attendu :** surbrillance **verte persistante** sur le bon pays (corrigé
après run 2026-07-07 — pas une bulle "Bravo !" flottante comme les autres
activités, un highlight qui reste affiché sur la carte) ; la carte doit être
chargée entièrement (pas de zone grise/vide à l'écran — régression déjà vue
par le passé sur des soucis de chargement GeoJSON).

---

## UC-ADV-09 — Utilisation d'un indice pendant une activité

**Précondition (seed) :** profil `allUnlocked` (solde d'indices par défaut :
5, `MilesEconomy.initialHintsBalance` appliqué à la création de la DB — pas
de manipulation supplémentaire nécessaire).

**Repro :**
1. Debug launcher → Aventure → région `europe`, code pays `FR`.
2. Tuile **"Typing · flag_typing"** (ou toute activité typing).
3. Taper le bouton indice (`HintButton`, cercle bleu primaire avec icône
   ampoule dorée, 56px, en bas de l'écran de jeu) avant de répondre.

**Checkpoint :** deux captures — (a) juste avant le tap (solde d'indices
visible), (b) juste après (solde décrémenté + indice révélé).

**Attendu :**
- Le solde d'indices affiché décroît de 1 entre (a) et (b) — confirmé
  5 → 4 au run 2026-07-07.
- Un indice concret apparaît : lettre(s) du nom du pays révélée(s) +
  puce d'autocomplétion.
- Si le solde tombe à 0 pendant le test (cas limite, pas ce scénario par
  défaut) : la modale "à court d'indices" doit s'afficher proprement
  (proposer pub récompensée / boutique), jamais un crash silencieux.

---

## UC-ADV-10 — Déblocage d'un continent (navigation réelle)

**Précondition (seed) :** profil `fresh`. **Nécessite un rebuild/reinstall
avec `MG_TEST_SEED_PROFILE=fresh`** si l'APK installée est encore sur le
profil `allUnlocked` — voir le design doc, section "Exécution & rapport".

**⚠️ Économie corrigée après run 2026-07-07 :** sur le profil `fresh`, le
joueur a **0 miles** et le premier continent (Europe) est affiché
**"Première région gratuite"** — sans prix, sans overlay verrouillé, jouable
immédiatement. Il n'y a donc RIEN à débloquer via un paiement dans l'état
`fresh` par défaut : ce cas ne peut PAS vérifier "le solde de miles diminue
du prix affiché" tel que rédigé initialement. Le déblocage payant est
couvert séparément par **UC-ADV-11** ci-dessous, sur le profil `midProgress`
(désormais un vrai profil dédié, plus un alias de `allUnlocked`).

**Repro (navigation réelle, PAS le debug launcher — c'est le point du test) :**
1. Depuis l'écran d'accueil, taper l'onglet **"Aventure"** dans la barre de
   navigation du bas (`BottomNavBar`, 2e icône).
2. La page Aventure affiche le carrousel des régions.

**Checkpoint :** une capture du carrousel après navigation vers l'onglet
Aventure.

**Attendu (réduit à ce qui est réellement testable avec `fresh`) :**
- L'onglet Aventure est atteignable directement depuis la barre du bas —
  **ceci est le vrai objet du test** : régression de navigation préventive
  suite à la découverte du redesign de la Home (2026-07-07, cartes
  Aventure/Multi/Défis disparues de la Home ; la barre d'onglets reste le
  chemin canonique).
- Europe s'affiche "Première région gratuite", jouable sans paiement.

**Régression connue liée :** aucune à ce jour côté déblocage lui-même : ce
cas est un test de non-régression *préventif* sur le chemin de navigation,
ajouté suite à la découverte du redesign de la Home (2026-07-07).

---

## UC-ADV-11 — Déblocage payant d'un 2e continent (navigation réelle)

**Précondition (seed) :** profil `midProgress` — Europe débloquée (niveau 1,
slot gratuit déjà utilisé), **1000 miles** en solde. Le 2e déblocage coûte
800 (`MilesEconomy.secondRegionUnlock`), laissant 200 après paiement — chiffre
choisi pour être facilement vérifiable sur une capture. **Nécessite un
rebuild/reinstall avec `MG_TEST_SEED_PROFILE=midProgress`.**

**Repro (navigation réelle) :**
1. Onglet **"Aventure"** dans la barre de navigation du bas.
2. Le carrousel affiche Europe débloquée + les 4 autres continents
   verrouillés avec un prix affiché.
3. Noter le solde de miles affiché dans le header (attendu : 1000).
4. Taper "Débloquer" sur un continent verrouillé (le moins cher affiché,
   normalement 800 pour le 2e — vérifier que c'est bien le prix montré).
5. Confirmer si une modale de confirmation apparaît.

**Checkpoint :** trois captures — (a) carrousel avant déblocage (prix +
solde miles visibles), (b) juste après le tap "Débloquer"
(chargement/confirmation), (c) après déblocage (continent accessible +
nouveau solde).

**Attendu :**
- (a) Prix affiché sur le continent verrouillé = 800 ; solde header = 1000.
- (c) Le continent devient jouable (overlay verrouillé disparu) ; le solde
  de miles affiché passe de 1000 à 200 (1000 − 800, exactement le prix
  affiché en (a) — **c'est le cœur du test**, contrairement à UC-ADV-10 qui
  ne pouvait pas vérifier cette soustraction).

**Régression connue liée :** aucune à ce jour — cas ajouté le 2026-07-07
pour combler le trou identifié dans UC-ADV-10 (impossible de tester un
déblocage payant avec le profil `fresh`).
