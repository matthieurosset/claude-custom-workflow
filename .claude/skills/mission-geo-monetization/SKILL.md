---
name: mission-geo-monetization
description: >
  Gère la monétisation de Mission Geo dans Google Play : créer/mettre à jour les
  produits in-app (consommables, achats uniques, packs pays), changer un prix,
  changer un titre/description dans toutes les langues, activer/désactiver un
  produit — le tout via l'API Google Play Monetization, sans saisie manuelle dans
  Play Console. Utilise ce skill DÈS QUE l'utilisateur parle de prix de produits,
  d'articles de la boutique, de SKU, de packs/abos Play, de changer un tarif, ou
  veut créer/modifier un produit in-app — même s'il ne dit pas « API » ni
  « fastlane ». Couvre aussi : où vivent les IDs/quantités, la limite des icônes
  (manuelles), et la lecture des abonnements.
---

# Mission Geo — Monétisation (produits in-app Play)

Gère les produits in-app du Play Store **par API**, pas à la main. L'UI Play Console
est lente (un titre + une description **par langue × ~20 produits**) ; ce skill fait
tout d'un appel, reproductible et versionné.

## Faits fondateurs (à connaître avant de toucher quoi que ce soit)

- **API : la nouvelle Monetization API**, pas l'ancienne. `inappproducts` est
  **désactivée** pour ce projet (`"Please migrate to the new publishing API"`). On
  utilise `androidpublisher.monetization.onetimeproducts` (et `.subscriptions`).
- **Auth** : service account fastlane `android/fastlane/play-console-key.json`
  (`play-console-release@mission-geo.iam.gserviceaccount.com`) — déjà autorisé.
- **Dépendances Python** : `pip install --user google-api-python-client google-auth`.
- **Source de vérité = `products.json`** (à côté de ce fichier) : par produit, le
  prix de base CHF + titre/description **par locale**. Les **product IDs DOIVENT
  matcher `lib/core/config/shop_catalog.dart`** (sinon RevenueCat ne récupère pas les prix).
- **IDs découplés de la quantité** : `mg.indices.tier1`, pas `mg.indices.25`. L'ID
  Play est **définitif** ; la quantité vit dans `shop_catalog.dart` (`amount`) et le
  nombre apparaît dans le **titre** (modifiable). Ainsi on peut changer « 25 → 30 »
  sans casser l'ID.
- **Création = DRAFT → activation obligatoire.** L'API crée la *purchase option* en
  `DRAFT` ; le script l'**active** ensuite (`purchaseOptions.batchUpdateStates`).
  Sans ça le produit n'est pas achetable.
- **`legacyCompatible: true`** sur la buy option : indispensable pour que la Billing
  Library / RevenueCat voient le produit comme un consommable classique
  (`queryProductDetails`). Ne pas l'enlever.
- **Prix** : on donne UNE base CHF ; `convertRegionPrices` génère les ~170 prix
  régionaux + les prix USD/EUR des régions futures. Pas de saisie pays par pays.
- **Charm pricing hybride** : `charm_currencies` (dans `products.json`, ex.
  `["CHF","EUR","USD","GBP"]`) FORCE le prix charm exact (= `price_chf`, ex. 0.99)
  sur ces devises au lieu d'accepter la conversion de Google → les **marchés clés
  gardent un 0.99 net** (qui convertit mieux), le reste du monde reste auto-converti
  (Google arrondit à des points locaux propres : ¥220, ₹140… pas de prix « sale »).
  Pour épingler un marché de plus : ajoute sa devise à `charm_currencies` + `sync`.
- **Icônes : PAS gérables par API** (aucun champ — le seul « icon » de l'API
  concerne les APK externes). → **upload manuel** dans Play Console, 1 image/produit
  (neutre, 512–1080 px, 1:1, sans texte/branding). Optionnelle.
- **Locales** (6) : in-app `fr/en/de/sr-Latn/es/hr` → Play `fr-FR, en-US, de-DE, sr,
  es-ES, hr`.

## Le script

`scripts/manage_products.py` (lancer depuis la racine du repo) :

```bash
# Lire l'état (one-time + abos)
python .claude/skills/mission-geo-monetization/scripts/manage_products.py list

# Créer / mettre à jour tous les one-time de products.json (listings + prix + activation)
python .../manage_products.py sync

# Cibler quelques produits
python .../manage_products.py sync --only mg.indices.tier1,mg.indices.tier2

# Voir ce qui serait envoyé, sans écrire dans Play
python .../manage_products.py sync --only mg.indices.tier1 --dry-run

# Changer juste un prix (re-génère les prix régionaux + ré-applique)
python .../manage_products.py set-price mg.indices.tier1 1.29
```

`sync` est **idempotent** : il crée si absent (`allowMissing`), met à jour sinon, puis
ré-active. Le relancer ne casse rien.

## Recettes (opérations courantes)

**Changer un prix** → édite `price_chf` dans `products.json` puis `sync --only <id>`
(ou `set-price <id> <chf>` pour un coup ponctuel, mais reflète-le ensuite dans
`products.json` pour garder la source de vérité juste).

**Changer un titre / une description (une ou plusieurs langues)** → édite les
`listings` dans `products.json` puis `sync --only <id>`. Garde **les 6 locales** (un
listing manquant = la langue n'apparaît pas pour ces utilisateurs).

**Ajouter un nouveau produit** → 1) ajoute l'entrée dans `products.json` (id, prix,
listings 6 langues) ; 2) ajoute le **même id** dans `lib/core/config/shop_catalog.dart`
avec son `amount`/kind (le code reste la source de vérité de la quantité) ; 3) `sync
--only <id>`. Puis upload de l'icône à la main si voulu.

**Désactiver un produit** → pas encore câblé dans le script ; utilise
`purchaseOptions.batchUpdateStates` avec `deactivatePurchaseOptionRequest` (même forme
que l'activation). À ajouter au script si le besoin devient récurrent.

## Abonnements (Pro / VIP)

`mg.sub.pro` et `mg.sub.vip` ont chacun **2 base plans auto-renew : `monthly` et
`annual`** (le base plan `flat`, prepaid non-renouvelable, a été retiré le 2026-07-06 —
jamais vendu, boutique jamais shippée : désactivé côté Play, détaché de son entitlement
puis supprimé côté RevenueCat).

```bash
python .../manage_products.py sync-subs                          # 1re création (tous en DRAFT puis activés)
python .../manage_products.py set-sub-price mg.sub.pro monthly 1.99   # change un prix + migre les abonnés existants
python .../manage_products.py deactivate-base-plan mg.sub.pro flat    # bloque les nouveaux abonnés, garde les existants
```

## Limites assumées / à faire

- **Icônes** : manuelles (voir plus haut).
- **Compte testeur** : pour acheter en sandbox sans payer, ajoute ton compte dans Play
  Console → Setup → License testing.

## Red flags — STOP

| Symptôme | Cause probable | Action |
|---|---|---|
| `Please migrate to the new publishing API` | usage de l'ancien `inappproducts` | utiliser `monetization.onetimeproducts` (ce que fait le script) |
| Produit en `DRAFT` après création | activation oubliée | `sync` (qui active) ou `purchaseOptions.batchUpdateStates` |
| RevenueCat ne voit pas le produit / prix vide | `legacyCompatible` absent, OU id ≠ `shop_catalog.dart`, OU produit non actif | vérifier les 3 |
| 403 sur l'appel | service account sans droit sur les produits | vérifier les permissions du compte dans Play Console → API access |
| Écriture dans Play non voulue | `sync`/`set-price` écrivent dans le **vrai** compte | utiliser `--dry-run` pour vérifier d'abord ; c'est une action sortante → OK utilisateur |

## État connu

Créés + ACTIVE côté Play (2026-07-06) : les 14 one-time products (`mg.indices.*`,
`mg.miles.*`, `mg.tickets.*`, `mg.removeads`, `mg.bundle.starter`, et les 4 packs pays
`mg.pack.austria/croatia/italy/usstates`). Abos `mg.sub.pro`/`mg.sub.vip` à 2 base plans
`monthly`/`annual` ACTIVE ; le base plan `flat` existe encore mais est **INACTIVE**
(désactivé, pas supprimé — nouveaux abonnés bloqués, anciens conservés).

Côté RevenueCat (2026-07-06) : 8 entitlements (`pro`, `vip`, `removeads`, `starter`,
`pack_austria`, `pack_croatia`, `pack_italy`, `pack_usa`), 20 produits dont les 4 packs
pays rattachés à leur entitlement respectif. `mg.sub.pro:flat` / `mg.sub.vip:flat`
détachés de `pro`/`vip` (n'accordent plus rien) mais **pas supprimés** — la suppression
RC est une action destructive qui nécessite une confirmation utilisateur directe (pas
via un message d'équipe relayé).
