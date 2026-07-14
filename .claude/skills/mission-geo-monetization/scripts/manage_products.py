#!/usr/bin/env python3
"""Mission Geo — gestion des produits in-app via la Google Play Monetization API.

L'ancien endpoint `inappproducts` est désactivé pour ce projet ("Please migrate
to the new publishing API") → on utilise la nouvelle API monetization :
`androidpublisher.monetization.onetimeproducts` (et `subscriptions`).

Ce que ce script gère, SANS passer par l'UI Play Console :
  - lister les produits one-time + abos
  - créer / mettre à jour un produit one-time : titres + descriptions (toutes
    langues) + prix (tous pays, via convertRegionPrices depuis une base CHF) +
    activation
  - changer le prix d'un produit existant

Ce qu'il NE gère PAS (limites de l'API) :
  - l'ICÔNE du produit : aucun champ dans l'API → upload manuel dans Play Console
    (1 image/produit, neutre, 512–1080 px, 1:1). Optionnelle.
  - les abonnements en écriture (modèle base-plans/offers très différent) : voir
    `list` pour la lecture ; l'écriture abo est une étape ultérieure dédiée.

Auth : service account fastlane `android/fastlane/play-console-key.json`.
Dépendances : google-api-python-client, google-auth (pip install --user ...).

Usage (depuis la racine du repo) :
  python .claude/skills/mission-geo-monetization/scripts/manage_products.py list
  python .../manage_products.py sync                       # tous les one-time de products.json
  python .../manage_products.py sync --only mg.indices.tier1
  python .../manage_products.py sync --only mg.indices.tier1 --dry-run
  python .../manage_products.py set-price mg.indices.tier1 1.29
"""
import argparse
import json
import os
import sys
import warnings

warnings.filterwarnings("ignore")

try:
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    from googleapiclient.errors import HttpError
except ImportError:
    sys.exit("Dépendances manquantes : pip install --user google-api-python-client google-auth")

SCOPE = "https://www.googleapis.com/auth/androidpublisher"
SKILL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Repo root = remonter depuis .claude/skills/mission-geo-monetization/
REPO_ROOT = os.path.abspath(os.path.join(SKILL_DIR, "..", "..", ".."))
KEY_FILE = os.path.join(REPO_ROOT, "android", "fastlane", "play-console-key.json")
CONFIG_FILE = os.path.join(SKILL_DIR, "products.json")


def svc():
    if not os.path.exists(KEY_FILE):
        sys.exit(f"Service account introuvable : {KEY_FILE}")
    creds = service_account.Credentials.from_service_account_file(KEY_FILE, scopes=[SCOPE])
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def load_config():
    with open(CONFIG_FILE, encoding="utf-8") as f:
        return json.load(f)


def money(currency, price):
    """0.99 -> {currencyCode:<cur>, units:'0', nanos:990000000}."""
    units = int(price)
    nanos = round((price - units) * 1e9)
    return {"currencyCode": currency, "units": str(units), "nanos": nanos}


def chf_money(price):
    return money("CHF", price)


def convert_region_prices(s, package, price_chf):
    """Convertit un prix CHF de base en prix régionaux pour tous les pays."""
    resp = (
        s.monetization()
        .convertRegionPrices(packageName=package, body={"price": chf_money(price_chf)})
        .execute()
    )
    return resp


def build_purchase_option(convert_resp, charm_currencies, price):
    """Purchase option 'base' (achat ferme) avec prix régionaux.

    Pour les devises de `charm_currencies`, on FORCE le prix charm exact (= price,
    ex. 0.99 €) au lieu d'accepter la conversion de Google → marchés clés à prix net.
    Le reste du monde garde la conversion auto (arrondie par Google).
    """
    charm = {c.upper() for c in charm_currencies}
    regional = []
    for region_code, conv in convert_resp.get("convertedRegionPrices", {}).items():
        p = conv["price"]
        cur = p.get("currencyCode")
        if cur in charm:
            p = money(cur, price)  # charm exact (ex. 0.99) sur ce marché
        regional.append(
            {
                "regionCode": conv.get("regionCode", region_code),
                "price": p,
                "availability": "AVAILABLE",
            }
        )
    other = convert_resp.get("convertedOtherRegionsPrice", {})
    po = {
        "purchaseOptionId": "base",
        "state": "ACTIVE",
        # legacyCompatible=True : expose le produit comme un INAPP classique pour la
        # Billing Library / RevenueCat (sinon non récupérable par queryProductDetails).
        "buyOption": {"legacyCompatible": True, "multiQuantityEnabled": False},
        "regionalPricingAndAvailabilityConfigs": regional,
    }
    if other.get("usdPrice") and other.get("eurPrice"):
        po["newRegionsConfig"] = {
            "usdPrice": money("USD", price) if "USD" in charm else other["usdPrice"],
            "eurPrice": money("EUR", price) if "EUR" in charm else other["eurPrice"],
            "availability": "AVAILABLE",
        }
    return po


def build_listings(listings_cfg):
    return [
        {"languageCode": loc, "title": v["title"], "description": v["description"]}
        for loc, v in listings_cfg.items()
    ]


def upsert_one_time(s, package, product, charm_currencies, dry_run=False):
    pid = product["product_id"]
    conv = convert_region_prices(s, package, product["price_chf"])
    region_version = conv.get("regionVersion", {}).get("version")
    body = {
        "packageName": package,
        "productId": pid,
        "listings": build_listings(product["listings"]),
        "purchaseOptions": [build_purchase_option(conv, charm_currencies, product["price_chf"])],
    }
    if dry_run:
        n_regions = len(body["purchaseOptions"][0]["regionalPricingAndAvailabilityConfigs"])
        print(f"  [dry-run] {pid} : {len(body['listings'])} listings, "
              f"{n_regions} régions tarifées, charm={charm_currencies}, regionVersion={region_version}")
        print(json.dumps(body, ensure_ascii=False, indent=2)[:1200] + "\n  ...")
        return
    s.monetization().onetimeproducts().patch(
        packageName=package,
        productId=pid,
        body=body,
        updateMask="listings,purchaseOptions",
        allowMissing=True,
        regionsVersion_version=region_version,
        latencyTolerance="PRODUCT_UPDATE_LATENCY_TOLERANCE_LATENCY_TOLERANT",
    ).execute()
    # La purchase option est créée en DRAFT → l'activer pour rendre le produit
    # achetable. Idempotent : réactiver une option déjà ACTIVE est sans effet.
    activate_purchase_option(s, package, pid, "base")
    print(f"  ✅ {pid} créé/mis à jour + activé ({len(body['listings'])} langues, prix {product['price_chf']} CHF)")


def activate_purchase_option(s, package, product_id, option_id="base"):
    s.monetization().onetimeproducts().purchaseOptions().batchUpdateStates(
        packageName=package,
        productId=product_id,
        body={
            "requests": [
                {
                    "activatePurchaseOptionRequest": {
                        "packageName": package,
                        "productId": product_id,
                        "purchaseOptionId": option_id,
                        "latencyTolerance": "PRODUCT_UPDATE_LATENCY_TOLERANCE_LATENCY_TOLERANT",
                    }
                }
            ]
        },
    ).execute()


def cmd_list(args):
    s = svc()
    cfg = load_config()
    pkg = cfg["package_name"]
    otp = s.monetization().onetimeproducts().list(packageName=pkg).execute()
    items = otp.get("oneTimeProducts", []) or otp.get("onetimeproducts", [])
    print(f"=== One-time products ({len(items)}) ===")
    for p in items:
        pos = p.get("purchaseOptions", [])
        states = ",".join(po.get("state", "?") for po in pos)
        print(f"  - {p.get('productId')} [{states}] · {len(p.get('listings', []))} langues")
    subs = s.monetization().subscriptions().list(packageName=pkg).execute()
    sitems = subs.get("subscriptions", [])
    print(f"=== Subscriptions ({len(sitems)}) ===")
    for p in sitems:
        print(f"  - {p.get('productId')}")


def cmd_sync(args):
    s = svc()
    cfg = load_config()
    pkg = cfg["package_name"]
    only = set(args.only.split(",")) if args.only else None
    targets = [p for p in cfg["one_time_products"] if not only or p["product_id"] in only]
    if not targets:
        sys.exit(f"Aucun produit ne correspond à --only {args.only}")
    charm = cfg.get("charm_currencies", [])
    print(f"Sync {len(targets)} produit(s) one-time" + (" [DRY-RUN]" if args.dry_run else "") + " :")
    for p in targets:
        try:
            upsert_one_time(s, pkg, p, charm, dry_run=args.dry_run)
        except HttpError as e:
            print(f"  ❌ {p['product_id']} : {e.status_code} {e.reason}")
            print("     " + (e.error_details if hasattr(e, "error_details") else str(e)[:500]))


def cmd_set_price(args):
    s = svc()
    cfg = load_config()
    pkg = cfg["package_name"]
    prod = next((p for p in cfg["one_time_products"] if p["product_id"] == args.product_id), None)
    if not prod:
        sys.exit(f"{args.product_id} absent de products.json (ajoute-le d'abord).")
    prod = dict(prod, price_chf=float(args.price_chf))
    print(f"Mise à jour prix {args.product_id} → {args.price_chf} CHF")
    upsert_one_time(s, pkg, prod, cfg.get("charm_currencies", []))
    print("  ℹ️ Pense à refléter ce prix dans products.json si tu veux le garder en source de vérité.")


# ── Abonnements ──────────────────────────────────────────────────────────────

def build_base_plan(s, package, bp, charm_currencies):
    """Un base plan (monthly/annual auto-renew, ou flat prepaid) avec prix régionaux + charm."""
    charm = {c.upper() for c in charm_currencies}
    conv = convert_region_prices(s, package, bp["price_chf"])
    region_version = conv.get("regionVersion", {}).get("version")
    regional = []
    for region_code, c in conv.get("convertedRegionPrices", {}).items():
        p = c["price"]
        cur = p.get("currencyCode")
        if cur in charm:
            p = money(cur, bp["price_chf"])
        regional.append(
            {"regionCode": c.get("regionCode", region_code), "price": p, "newSubscriberAvailability": True}
        )
    other = conv.get("convertedOtherRegionsPrice", {})
    plan = {
        "basePlanId": bp["base_plan_id"],
        "state": "DRAFT",  # activé ensuite via basePlans.activate
        "regionalConfigs": regional,
        "otherRegionsConfig": {
            "usdPrice": money("USD", bp["price_chf"]) if "USD" in charm else other.get("usdPrice"),
            "eurPrice": money("EUR", bp["price_chf"]) if "EUR" in charm else other.get("eurPrice"),
            "newSubscriberAvailability": True,
        },
    }
    if bp["type"] == "auto":
        plan["autoRenewingBasePlanType"] = {
            "billingPeriodDuration": bp["period"],
            "prorationMode": "SUBSCRIPTION_PRORATION_MODE_CHARGE_ON_NEXT_BILLING_DATE",
            "resubscribeState": "RESUBSCRIBE_STATE_ACTIVE",
        }
    else:  # prepaid (mois flat non-renouvelable)
        plan["prepaidBasePlanType"] = {
            "billingPeriodDuration": bp["period"],
            "timeExtension": "TIME_EXTENSION_ACTIVE",
        }
    return plan, region_version


def upsert_subscription(s, package, sub, charm_currencies, dry_run=False):
    pid = sub["product_id"]
    base_plans, region_version = [], None
    for bp in sub["base_plans"]:
        plan, rv = build_base_plan(s, package, bp, charm_currencies)
        base_plans.append(plan)
        region_version = rv or region_version
    listings = [
        {"languageCode": loc, "title": v["title"], "description": v["description"], "benefits": v.get("benefits", [])}
        for loc, v in sub["listings"].items()
    ]
    body = {"packageName": package, "productId": pid, "listings": listings, "basePlans": base_plans}
    if dry_run:
        ids = ", ".join(bp["base_plan_id"] for bp in sub["base_plans"])
        print(f"  [dry-run] {pid} : {len(listings)} listings, base plans [{ids}], regionVersion={region_version}")
        return
    s.monetization().subscriptions().patch(
        packageName=package,
        productId=pid,
        body=body,
        updateMask="listings,basePlans",
        allowMissing=True,
        regionsVersion_version=region_version,
        latencyTolerance="PRODUCT_UPDATE_LATENCY_TOLERANCE_LATENCY_TOLERANT",
    ).execute()
    # Les base plans sont créés en DRAFT → activer chacun.
    for bp in sub["base_plans"]:
        s.monetization().subscriptions().basePlans().activate(
            packageName=package,
            productId=pid,
            basePlanId=bp["base_plan_id"],
            body={
                "packageName": package,
                "productId": pid,
                "basePlanId": bp["base_plan_id"],
                "latencyTolerance": "PRODUCT_UPDATE_LATENCY_TOLERANCE_LATENCY_TOLERANT",
            },
        ).execute()
    print(f"  ✅ {pid} : {len(base_plans)} base plans activés, {len(listings)} langues")


def get_subscription(s, package, product_id):
    return s.monetization().subscriptions().get(packageName=package, productId=product_id).execute()


def update_base_plan_price(s, package, product_id, base_plan_id, price_chf, charm_currencies, dry_run=False):
    """Change le prix d'un base plan EXISTANT (déjà ACTIVE en prod), sans le
    recréer en DRAFT.

    Différent de `upsert_subscription` : celui-ci sert à la création initiale
    (tous les base plans partent en DRAFT puis sont activés) — le rejouer sur
    un abonnement déjà actif écraserait `state` avec la mauvaise valeur (le
    champ est de toute façon output-only sur un patch, mais autant ne pas
    prétendre le contraire). Ici on :
      1. relit le base plan existant (préserve son type/autoRenew/prepaid tel
         quel, ne touche qu'aux prix régionaux) ;
      2. patch la SOUS-LISTE basePlans en renvoyant TOUS les base plans
         actuels (un patch sur un champ répété remplace tout le champ, pas
         seulement l'élément visé) ;
      3. appelle migratePrices sur toutes les régions pour faire transiter
         les abonnés déjà actifs vers le nouveau prix (obligatoire même pour
         une baisse de prix — Google notifie les abonnés existants et
         applique le changement à leur prochaine date de facturation).
    """
    sub = get_subscription(s, package, product_id)
    base_plans = sub.get("basePlans", [])
    target = next((bp for bp in base_plans if bp.get("basePlanId") == base_plan_id), None)
    if target is None:
        sys.exit(f"Base plan '{base_plan_id}' introuvable sur {product_id} (base plans actuels : "
                  f"{[bp.get('basePlanId') for bp in base_plans]})")

    charm = {c.upper() for c in charm_currencies}
    conv = convert_region_prices(s, package, price_chf)
    region_version = conv.get("regionVersion", {}).get("version")
    regional = []
    for region_code, c in conv.get("convertedRegionPrices", {}).items():
        p = c["price"]
        cur = p.get("currencyCode")
        if cur in charm:
            p = money(cur, price_chf)
        regional.append(
            {"regionCode": c.get("regionCode", region_code), "price": p, "newSubscriberAvailability": True}
        )
    other = conv.get("convertedOtherRegionsPrice", {})

    # Ne modifie QUE le prix — préserve le reste du base plan tel quel
    # (autoRenewingBasePlanType/prepaidBasePlanType, offerTags, etc.).
    target["regionalConfigs"] = regional
    target["otherRegionsConfig"] = {
        "usdPrice": money("USD", price_chf) if "USD" in charm else other.get("usdPrice"),
        "eurPrice": money("EUR", price_chf) if "EUR" in charm else other.get("eurPrice"),
        "newSubscriberAvailability": True,
    }

    if dry_run:
        print(f"  [dry-run] {product_id}:{base_plan_id} → {price_chf} CHF "
              f"({len(regional)} régions, regionVersion={region_version})")
        return

    s.monetization().subscriptions().patch(
        packageName=package,
        productId=product_id,
        body={"packageName": package, "productId": product_id, "basePlans": base_plans},
        updateMask="basePlans",
        regionsVersion_version=region_version,
        latencyTolerance="PRODUCT_UPDATE_LATENCY_TOLERANCE_LATENCY_TOLERANT",
    ).execute()

    # Migre les abonnés déjà sur l'ancien prix (cohortes "legacy") vers le
    # nouveau — sans ça, seuls les NOUVEAUX abonnés verraient le nouveau prix,
    # les abonnés existants resteraient facturés à l'ancien indéfiniment.
    # oldestAllowedPriceVersionTime volontairement ancien (2020) pour couvrir
    # toutes les cohortes existantes, quelle que soit leur ancienneté.
    region_codes = [r["regionCode"] for r in regional]
    s.monetization().subscriptions().basePlans().migratePrices(
        packageName=package,
        productId=product_id,
        basePlanId=base_plan_id,
        body={
            "packageName": package,
            "productId": product_id,
            "basePlanId": base_plan_id,
            "regionsVersion": {"version": region_version},
            "regionalPriceMigrations": [
                {"regionCode": rc, "oldestAllowedPriceVersionTime": "2020-01-01T00:00:00Z"}
                for rc in region_codes
            ],
            "latencyTolerance": "PRODUCT_UPDATE_LATENCY_TOLERANCE_LATENCY_TOLERANT",
        },
    ).execute()
    print(f"  ✅ {product_id}:{base_plan_id} → {price_chf} CHF (patché + abonnés existants migrés)")


def deactivate_base_plan(s, package, product_id, base_plan_id, dry_run=False):
    """Désactive un base plan existant : n'accepte plus de nouveaux abonnés,
    mais les abonnés déjà dessus gardent leur abonnement (comportement Google,
    pas une suppression — voir `delete` si une suppression complète est
    voulue plus tard, réservée aux base plans déjà inactifs)."""
    if dry_run:
        print(f"  [dry-run] deactivate {product_id}:{base_plan_id}")
        return
    s.monetization().subscriptions().basePlans().deactivate(
        packageName=package,
        productId=product_id,
        basePlanId=base_plan_id,
        body={
            "packageName": package,
            "productId": product_id,
            "basePlanId": base_plan_id,
            "latencyTolerance": "PRODUCT_UPDATE_LATENCY_TOLERANCE_LATENCY_TOLERANT",
        },
    ).execute()
    print(f"  ✅ {product_id}:{base_plan_id} désactivé (nouveaux abonnés bloqués, existants conservés)")


def cmd_set_sub_price(args):
    s = svc()
    cfg = load_config()
    pkg = cfg["package_name"]
    update_base_plan_price(
        s, pkg, args.product_id, args.base_plan_id, float(args.price_chf),
        cfg.get("charm_currencies", []), dry_run=args.dry_run,
    )


def cmd_deactivate_base_plan(args):
    s = svc()
    cfg = load_config()
    pkg = cfg["package_name"]
    deactivate_base_plan(s, pkg, args.product_id, args.base_plan_id, dry_run=args.dry_run)


def cmd_sync_subs(args):
    s = svc()
    cfg = load_config()
    pkg = cfg["package_name"]
    charm = cfg.get("charm_currencies", [])
    subs = cfg.get("subscriptions", [])
    only = set(args.only.split(",")) if args.only else None
    targets = [x for x in subs if not only or x["product_id"] in only]
    if not targets:
        sys.exit(f"Aucun abo ne correspond" + (f" à --only {args.only}" if args.only else " (products.json vide ?)"))
    print(f"Sync {len(targets)} abo(s)" + (" [DRY-RUN]" if args.dry_run else "") + " :")
    for x in targets:
        try:
            upsert_subscription(s, pkg, x, charm, dry_run=args.dry_run)
        except HttpError as e:
            print(f"  ❌ {x['product_id']} : {e.status_code} {e.reason}")
            print("     " + str(e)[:600])


def main():
    ap = argparse.ArgumentParser(description="Gestion produits in-app Mission Geo (Play Monetization API)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list", help="Lister les produits one-time + abos")
    sp = sub.add_parser("sync", help="Créer/mettre à jour les one-time depuis products.json")
    sp.add_argument("--only", help="IDs séparés par des virgules")
    sp.add_argument("--dry-run", action="store_true", help="Affiche sans écrire dans Play")
    spp = sub.add_parser("set-price", help="Changer le prix d'un produit one-time")
    spp.add_argument("product_id")
    spp.add_argument("price_chf")
    ss = sub.add_parser("sync-subs", help="Créer les abonnements/base plans depuis products.json (1re création uniquement)")
    ss.add_argument("--only", help="IDs séparés par des virgules")
    ss.add_argument("--dry-run", action="store_true", help="Affiche sans écrire dans Play")
    ssp = sub.add_parser("set-sub-price", help="Changer le prix d'un base plan existant (+ migre les abonnés déjà actifs)")
    ssp.add_argument("product_id", help="ex. mg.sub.pro")
    ssp.add_argument("base_plan_id", help="ex. monthly, annual")
    ssp.add_argument("price_chf")
    ssp.add_argument("--dry-run", action="store_true", help="Affiche sans écrire dans Play")
    sdb = sub.add_parser("deactivate-base-plan", help="Désactiver un base plan existant (garde les abonnés déjà dessus)")
    sdb.add_argument("product_id", help="ex. mg.sub.pro")
    sdb.add_argument("base_plan_id", help="ex. flat")
    sdb.add_argument("--dry-run", action="store_true", help="Affiche sans écrire dans Play")
    args = ap.parse_args()
    {
        "list": cmd_list,
        "sync": cmd_sync,
        "set-price": cmd_set_price,
        "sync-subs": cmd_sync_subs,
        "set-sub-price": cmd_set_sub_price,
        "deactivate-base-plan": cmd_deactivate_base_plan,
    }[args.cmd](args)


if __name__ == "__main__":
    main()
