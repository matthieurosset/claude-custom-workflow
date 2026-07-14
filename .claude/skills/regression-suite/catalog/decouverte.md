# Catalogue de non-régression visuelle — Découverte

Voir le design : `docs/superpowers/specs/2026-07-07-visual-regression-catalog-design.md`.

**Exécuté bout-en-bout le 2026-07-07 (avec vrai téléchargement Suisse pour
UC-DEC-06) : 6/6 PASS.**

**Bug réel trouvé, à corriger (`mg-debugger`) :** le crédit photo du "Lieu
emblématique" affiche du **HTML brut non échappé** pour au moins le Brésil
et la Guyane (`&lt;a href="//commons.wikimedia.org/..."` littéral à
l'écran au lieu d'un texte propre "Auteur · Licence" comme pour les autres
pays). Root cause probable : attribution scrapée non nettoyée dans
`world.json` pour ces entrées, combinée à l'absence de sanitization HTML
dans le rendu du crédit (`country_detail_sections.dart`). Portée non
mesurée précisément (`grep -c '&lt;a ' assets/world/world.json` donnerait
le nombre exact) — probablement plus large que les 2 pays observés.

Découverte (`lib/pages/modes/discovery/discovery_page.dart`) est un mode de
libre exploration : carte pannable/zoomable + recherche de pays, sans score
ni pression de jeu. Pays de test par défaut : **France (FR)**, comme dans
`aventure.md`, pour sa couverture complète (drapeau, capitale, forme, blason,
lieu emblématique, hymne tous présents).

**Précondition transversale (vérifiée dans le code, pas supposée) :**
`DiscoveryPage.build()` n'a **aucune vérification de déblocage** — pas de
lecture de progression Aventure, pas de test d'achat. Le seul état qui
influence le rendu est la liste des datasets **installés** sur l'appareil
(`DatasetInstallRegistry`, `dataset_versions` en SharedPreferences). Le mode
est donc accessible à l'identique sur les profils `fresh`, `midProgress` et
`allUnlocked` — **aucun des trois ne pré-installe de dataset téléchargeable**
(`TestSeed._seedSharedPreferences` écrit `dataset_versions` = chaîne vide
pour les trois profils), donc le sélecteur de collection n'affichera jamais
que "Monde" tant qu'aucun téléchargement réel n'a eu lieu dans la session de
test — voir UC-DEC-02 et UC-DEC-06.

**Pas de raccourci debug launcher pour ce mode** (confirmé par grep dans
`lib/pages/debug/debug_launcher_page.dart` — aucune section Découverte).
Tous les cas ci-dessous utilisent donc la **navigation réelle** : Home →
scroller jusqu'à la section "Extra" (après "En ce moment" et le récapitulatif
Carnet) → tuile **"Découverte"** (rangée du bas, à gauche de "Ranking",
`testId mgHomeDiscovery`) → `context.router.push(const DiscoveryRoute())`.
`DiscoveryRoute` est déclarée sous les enfants de l'onglet Home
(`lib/core/navigation/router.dart`, scope tab-nested) donc le Back depuis
Découverte revient normalement sur la Home — pas de risque d'écran bleu ici.

**Piège testId (vérifié dans le code, pas supposé) :** `mgDiscoveryDatasetPicker`
est bien posé sur la chip de sélection de collection (`_DatasetChip`, en haut
à droite de l'app bar). **`mgDiscoveryMapLoaded` est défini dans
`lib/core/testing/test_ids.dart` mais n'est posé sur aucun widget** (grep sur
tout `lib/` : seule occurrence = sa propre déclaration) — c'est un testId mort,
ne pas perdre de temps à le chercher dans l'arbre de widgets. Le chargement de
la carte se valide uniquement **visuellement** : absence du
`CircularProgressIndicator` blanc plein écran et présence du contour des
continents dessiné par `DiscoveryMapCanvas` (pas de zone grise/vide).

---

## UC-DEC-01 — Ouverture depuis Home + état initial (carte Monde)

**Précondition (seed) :** profil `allUnlocked` (ou `fresh`/`midProgress` —
comportement identique, voir note transversale ci-dessus).

**Repro :**
1. Depuis la Home, scroller jusqu'à la section "Extra".
2. Taper la tuile **"Découverte"** (rangée du bas, gauche).

**Checkpoint :** deux captures — (a) immédiatement après le tap (avant que
la carte basse résolution ne finisse de charger, si perceptible), (b) une
fois la carte stabilisée (~1s).

**Attendu :**
- (a) Si un état de chargement est visible, c'est un `CircularProgressIndicator`
  blanc centré sur fond sombre — jamais un écran blanc/vide ni une exception.
- (b) **Corrigé après run 2026-07-07 :** la carte s'affiche à l'échelle
  d'un **continent** (Afrique centrée par défaut, silhouettes nettes),
  pannable pour atteindre les autres continents — pas une vue "monde
  entier en un écran". Le zoom minimal est verrouillé au cadrage par
  défaut (`MapViewState.minScale == defaultScale`, `lib/core/geo/map_view_state.dart`),
  il n'existe pas de dézoom au-delà. Semble être un choix délibéré de
  lisibilité, pas une régression — pas de zone grise ou de pays manquants
  en bloc dans tous les cas.
- App bar transparente titrée **"Découverte"** avec, à droite, la chip
  de collection affichant **"Monde"** + chevron.
- Barre de recherche "Rechercher un pays…" épinglée sous l'app bar.
- Onglet de navigation du bas toujours visible en dessous (scope tab-nested,
  pas de route root) — confirmer qu'il n'y a pas de double barre ou de zone
  morte caractéristique d'un bug de scope de navigation.

**Régression connue liée :** aucune régression de chargement initial connue
à ce jour ; ce cas sert de baseline avant les cas suivants.

---

## UC-DEC-02 — Sélecteur de collection avec une seule option (Monde)

**Précondition (seed) :** profil `allUnlocked`, **aucun dataset téléchargeable
installé** (état par défaut du seed — voir note transversale). Ne pas avoir
enchaîné ce cas après UC-DEC-06 sans réinstaller, sinon la Suisse sera déjà
listée et ce cas ne testera plus le cas "option unique".

**Repro :**
1. Depuis Découverte (UC-DEC-01), taper la chip de collection ("Monde" +
   chevron, en haut à droite, `testId mgDiscoveryDatasetPicker`).

**Checkpoint :** capture du bottom sheet ouvert.

**Attendu :**
- Bottom sheet titré **"Choisir une collection"**.
- **Une seule carte** listée : "Monde" / "248 pays du monde entier", icône
  globe, marquée sélectionnée (coche/accent visible).
- Aucune carte pour Suisse/Autriche/Croatie/Italie/États-Unis tant qu'ils ne
  sont pas installés — pas de carte grisée-mais-tapable, pas de crash au tap
  sur un dataset non téléchargé.
- Taper la carte "Monde" (déjà sélectionnée) ferme le sheet sans changement
  d'état visible sur la carte.

**Régression connue liée :** avant le commit `f975b5cd` (`fix(discovery):
filter picker to installed datasets only`), **tous** les datasets figuraient
dans ce picker sans filtrage — taper un dataset non téléchargé produisait un
état vide/erreur silencieuse. Ce cas doit détecter toute régression de ce
filtre (ex. un dataset marqué installé par erreur en DB sans fichiers réels
sur le FS — cf. mémoire `feedback_dataset_bugs_repro_via_real_unlock_download_flow`,
qui met en garde contre exactement ce genre d'état inatteignable par l'UI).

---

## UC-DEC-03 — Recherche et sélection d'un pays à couverture complète (France)

**Précondition (seed) :** profil `allUnlocked`, collection "Monde" active.

**Repro :**
1. Taper la barre de recherche → le clavier s'ouvre, un overlay de résultats
   apparaît sous la barre.
2. Taper "France" lettre par lettre.
3. Taper le résultat "France" dans la liste (drapeau miniature + "France" +
   sous-région à gauche).

**Checkpoint :** deux captures — (a) overlay de résultats après saisie
complète (avant le tap), (b) après le tap, une fois la fiche pays stabilisée
(la caméra vole vers la France puis la bottom sheet s'ouvre automatiquement
à la fin de l'animation).

**Attendu :**
- (a) Un seul résultat "France" (pas de doublons, pas de résultat parasite
  type "Guyane"/"Martinique" qui remonterait sur une recherche "France" à
  cause d'un mauvais matching).
- (b) La caméra a survolé jusqu'au territoire métropolitain français, puis
  une bottom sheet s'ouvre (glissable jusqu'à 92% de hauteur) avec, dans
  l'ordre : section identité (drapeau + "France" + "Paris" + région/sous-
  région), ligne population/superficie, section **"Hymne national"** (lecteur
  compact, pas de lecture automatique), section **"Lieu emblématique"**
  (photo + nom + description + crédit photo discret), section **"Armoiries
  et silhouette"** (blason + silhouette côte à côte), section
  **"Indicateurs"** (liste des autres statistiques disponibles).
- Aucune section vide affichée comme un cadre blanc creux — chaque section
  absente de données doit disparaître entièrement (dégradation gracieuse),
  pas seulement masquer son contenu.
- Aucune image cassée (drapeau, blason, photo du lieu) — la France a une
  couverture 100% sur tous ces champs par construction du dataset `world`.

**Régression connue liée :** la recherche doit matcher sur `country.localizedNom`
et non sur `country.nom` (forme FR de stockage) — `discovery_page.dart` est
explicitement cité comme référence correcte dans la mémoire
`feedback_search_match_localized_name` (bug historique découvert en locale
serbe). En FR les deux formes coïncident donc ce cas ne peut pas détecter une
régression de matching localisé à lui seul — repasser ce même cas en locale
`de`/`es`/`sr-Latn` (Profil → langue) si un doute apparaît ailleurs sur ce
point.

---

## UC-DEC-04 — Recherche d'un micro-État absent de la résolution basse (Vatican)

**Précondition (seed) :** profil `allUnlocked`, collection "Monde" active,
**ne pas avoir déjà zoomé/pan sur l'Italie** dans cette session (pour
garantir que la résolution mid/high n'est pas déjà chargée en cache et que
le chargement à la demande est réellement exercé).

**Repro :**
1. Depuis l'état initial de Découverte (carte dézoomée, résolution basse),
   rechercher "Vatican".
2. Taper le résultat "Cité du Vatican".

**Checkpoint :** capture juste après le tap, pendant/à la fin de l'animation
de vol de caméra.

**Attendu :**
- Pas de gel ni de spinner bloqué : la Cité du Vatican est absente du GeoJSON
  basse résolution (vérifié : `VA` présent dans `world.midRes.geo.json` et
  `world.hiRes.geo.json`, absent de `world.lowRes.geo.json`) — le code doit
  déclencher un chargement à la demande de la résolution mid (`resolveGeoCountry`
  dans `discovery_map_notifier.dart`) avant de pouvoir voler vers la cible.
- La caméra zoome jusqu'à un cadrage centré sur le Vatican (pas un zoom sur
  un point vide au milieu de l'Italie, pas un zoom resté sur la vue monde).
- La bottom sheet s'ouvre ensuite avec drapeau, "Cité du Vatican", section
  Hymne (le Vatican a un hymne dans `world.json`) et section Lieu emblématique
  ("Basilique Saint-Pierre" + photo).

**Régression connue liée :** aucune régression connue précisément sur ce
chemin ; ce cas couvre le chargement à la demande de résolution supérieure
documenté en commentaire dans `discovery_map_notifier.dart` (`resolveGeoCountry`)
et `discovery_map_canvas.dart` (centrage via l'index géo pour les micro-états).

---

## UC-DEC-05 — Tap direct sur un territoire d'outre-mer français (Guyane)

**Précondition (seed) :** profil `allUnlocked`, collection "Monde" active,
vue initiale (dézoomée).

**Repro :**
1. Pincer-zoomer pour cadrer l'Amérique du Sud, repérer la Guyane (petit
   territoire au nord-est du continent, entre Suriname et Brésil).
2. Taper directement sur le territoire de la Guyane (pas sur le Brésil
   voisin).

**Checkpoint :** capture de la bottom sheet ouverte après le tap.

**Attendu :**
- La fiche qui s'ouvre est celle de **"Guyane"** (drapeau/données propres),
  **pas** celle de la France — même à résolution basse, la Guyane doit être
  un feature GeoJSON distinct et cliquable séparément du polygone France.
- Section Hymne **absente** pour la Guyane (`anthem` est vide pour ce
  territoire dans `world.json`) — vérifier que la section disparaît
  proprement (pas de lecteur audio cassé/vide affiché).
- Section Lieu emblématique présente ("Centre Spatial Guyanais" + photo).

**Régression connue liée :** avant le commit `961cdf10` (`fix(discovery):
extract FR overseas territories from France polygon in lowRes/midRes GeoJSON`),
les territoires d'outre-mer français (GF/MQ/GP/RE/YT) étaient fusionnés dans
le polygone France du GeoJSON `iso_a2="-99"` — taper sur la Guyane (ou la
Martinique/Guadeloupe/Réunion/Mayotte) ouvrait la fiche **France**. La Guyane
est le seul de ces territoires extrait dès la résolution basse (les 4 autres
ne sont séparés qu'à partir de la résolution moyenne, donc un zoom plus
poussé serait nécessaire pour les tester individuellement).

---

## UC-DEC-06 — Changement de collection après téléchargement réel d'un dataset (Suisse)

**Précondition (seed) :** profil `allUnlocked`. **Nécessite un téléchargement
réel du dataset Suisse dans la même session** avant ce cas — pas de
raccourci DB, cf. mémoire `feedback_dataset_bugs_repro_via_real_unlock_download_flow`
(forcer un flag "installé" sans le zip réel = état inatteignable par l'UI en
usage normal → faux positif). Flux réel : onglet Aventure → carrousel des
régions → repérer la bannière de téléchargement d'un dataset premium/gratuit
supplémentaire (`DatasetDownloadBanner`, région Suisse) → lancer le
téléchargement → attendre la confirmation d'installation.

**Repro :**
1. Une fois la Suisse installée, retourner sur Home → Découverte.
2. Taper la chip de collection ("Monde" + chevron).
3. Sélectionner "Suisse" dans la liste (désormais 2 cartes : Monde + Suisse).

**Checkpoint :** deux captures — (a) le picker avec les 2 collections
listées avant sélection, (b) la carte après sélection de "Suisse" (cadrage
recentré + drapeaux/silhouettes cantonaux visibles).

**Attendu :**
- (a) "Suisse" apparaît maintenant dans le picker (26 cantons suisses en
  sous-titre), en plus de "Monde".
- (b) La caméra se recentre automatiquement sur le territoire suisse (pas de
  carte vide centrée sur l'ancien cadrage monde) — comportement du fix
  `21dc4318` (`fix(discovery): USA centering, dataset-switch recenter &
  vertical pan room under app bar`).
- Taper un canton ouvre sa fiche avec drapeau/silhouette **chargés depuis le
  filesystem téléchargé**, pas depuis les assets bundlés — vérifier
  qu'aucune image n'est cassée. Avant le fix `88a11148` (`fix(discovery):
  route dataset assets through DatasetSource`), les images des datasets
  téléchargés (Suisse, Italie…) ne s'affichaient pas du tout dans Découverte
  car le code utilisait `Image.asset`/`SvgPicture.asset` (bundle uniquement)
  au lieu de router via `DatasetSource` (FS pour les datasets téléchargés).
- **Corrigé après run 2026-07-07 :** un canton suisse n'a **pas** de
  section Hymne (absente, dégradation propre) — mais **a bien** une
  section Lieu emblématique (photo + nom + description + crédit, vérifié
  sur Bâle-Campagne → "Augusta Raurica"), contrairement à ce que la
  première rédaction affirmait. La section "Armoiries et silhouette"
  n'affiche que la silhouette (pas de blason, `coatsPng` absent pour les
  cantons) — dégradation propre également, pas d'icône cassée.

**Régression connue liée :** voir les deux fixes cités ci-dessus
(`21dc4318`, `88a11148`), tous deux réels et déjà mergés — ce cas est la
garde de non-régression sur ces deux points précis.
