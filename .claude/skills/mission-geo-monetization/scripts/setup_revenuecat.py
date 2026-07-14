#!/usr/bin/env python3
"""Mission Geo — configuration RevenueCat via l'API v2.

Scripte la partie automatisable de RevenueCat : app Play (shell), entitlements,
produits, offering + packages, rattachements. La SEULE étape NON scriptable
(API) = connecter les credentials Play (service account) à l'app RC et récupérer
la clé SDK publique (goog_…) → à faire dans le dashboard RevenueCat (sensible :
donne à RC l'accès de validation au compte Play).

Auth : clé secrète API v2 RevenueCat via env REVENUECAT_API_KEY (ou RC_KEY).
Stockée dans .claude/settings.local.json (gitignoré), comme FAL_KEY.

Mapping (cf entitlement_mapper.dart) :
  mg.sub.pro.*     -> entitlement 'pro' (inclut tous les packs pays, géré côté app)
  mg.sub.vip.*     -> entitlement 'vip' (idem)
  mg.removeads     -> entitlement 'removeads'
  mg.bundle.starter -> entitlement 'starter'
  mg.pack.austria  -> entitlement 'pack_austria'
  mg.pack.croatia  -> entitlement 'pack_croatia'
  mg.pack.italy    -> entitlement 'pack_italy'
  mg.pack.usstates -> entitlement 'pack_usa' (datasetId = 'usa', pas 'usstates')
  mg.pack.switzerland -> entitlement 'pack_switzerland'
  consommables     -> AUCUN entitlement (crédités côté app)

Usage :
  python .../setup_revenuecat.py info
  python .../setup_revenuecat.py ensure-entitlements
  python .../setup_revenuecat.py ensure-app
  python .../setup_revenuecat.py products      # APRÈS connexion des credentials Play
"""
import argparse
import json
import os
import sys
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("pip install --user requests")

KEY = os.environ.get("REVENUECAT_API_KEY") or os.environ.get("RC_KEY")
if not KEY:
    sys.exit("REVENUECAT_API_KEY (ou RC_KEY) non défini.")

BASE = "https://api.revenuecat.com/v2"
H = {"Authorization": f"Bearer {KEY}", "Accept": "application/json", "Content-Type": "application/json"}
SKILL_DIR = Path(__file__).resolve().parents[1]
CONFIG = json.loads((SKILL_DIR / "products.json").read_text(encoding="utf-8"))
PACKAGE = CONFIG["package_name"]

ENTITLEMENTS = [
    ("pro", "Abonnement Pro"),
    ("vip", "Abonnement VIP"),
    ("removeads", "Sans publicités"),
    ("starter", "Starter pack"),
    ("pack_austria", "Pack Autriche"),
    ("pack_croatia", "Pack Croatie"),
    ("pack_italy", "Pack Italie"),
    ("pack_usa", "Pack États-Unis"),
    ("pack_switzerland", "Pack Suisse"),
]


def _get(path):
    r = requests.get(BASE + path, headers=H, timeout=30)
    r.raise_for_status()
    return r.json()


def _post(path, body):
    r = requests.post(BASE + path, headers=H, json=body, timeout=30)
    return r.status_code, (r.json() if r.text else {})


def project_id():
    items = _get("/projects").get("items", [])
    if not items:
        sys.exit("Aucun projet RevenueCat.")
    # un seul projet attendu (Mission Géo)
    return items[0]["id"]


def list_all(pid, coll):
    return _get(f"/projects/{pid}/{coll}").get("items", [])


def play_app_id(pid):
    for a in list_all(pid, "apps"):
        if a.get("type") == "play_store":
            return a["id"]
    return None


def cmd_info(_):
    pid = project_id()
    print(f"project: {pid}")
    for coll in ("apps", "entitlements", "products", "offerings"):
        items = list_all(pid, coll)
        print(f"=== {coll} ({len(items)}) ===")
        for it in items:
            print(f"  {it.get('id')} | {it.get('lookup_key') or it.get('display_name') or it.get('type')} "
                  f"| {it.get('store') or it.get('store_identifier') or it.get('type') or ''}")


def cmd_ensure_entitlements(_):
    pid = project_id()
    existing = {e["lookup_key"] for e in list_all(pid, "entitlements")}
    for lk, name in ENTITLEMENTS:
        if lk in existing:
            print(f"  = {lk} (déjà présent)")
            continue
        st, body = _post(f"/projects/{pid}/entitlements", {"lookup_key": lk, "display_name": name})
        print(f"  {'✅' if st in (200, 201) else '❌'} {lk} ({st})"
              + ("" if st in (200, 201) else f" {json.dumps(body)[:200]}"))


def cmd_ensure_app(_):
    pid = project_id()
    if play_app_id(pid):
        print("  = app Play déjà présente")
        return
    st, body = _post(f"/projects/{pid}/apps",
                     {"name": "Mission Geo (Android)", "type": "play_store",
                      "play_store": {"package_name": PACKAGE}})
    if st in (200, 201):
        print(f"  ✅ app Play créée : {body.get('id')} ({PACKAGE})")
        print("  ⚠️ ÉTAPE MANUELLE : dashboard RevenueCat → cette app → connecter les")
        print("     credentials Play (service account) + copier la clé SDK publique (goog_…).")
    else:
        print(f"  ❌ création app ({st}): {json.dumps(body)[:300]}")


# Produits non-consommables (achetés une fois) vs consommables (re-crédités).
NON_CONSUMABLE = {
    "mg.removeads", "mg.bundle.starter",
    "mg.pack.austria", "mg.pack.croatia", "mg.pack.italy", "mg.pack.usstates",
    "mg.pack.switzerland",
}
# Rattachement produit -> entitlement (durable). Les consommables purs = aucun.
ENTITLEMENT_FOR = {
    "mg.removeads": "removeads",
    "mg.bundle.starter": "starter",
    "mg.pack.austria": "pack_austria",
    "mg.pack.croatia": "pack_croatia",
    "mg.pack.italy": "pack_italy",
    "mg.pack.usstates": "pack_usa",  # datasetId = 'usa', entitlement = 'pack_usa'
    "mg.pack.switzerland": "pack_switzerland",
}  # subs (pro/vip) gérés dynamiquement plus bas dans cmd_products


def cmd_products(_):
    pid = project_id()
    app = play_app_id(pid)
    if not app:
        sys.exit("Pas d'app Play — lance d'abord ensure-app.")
    existing = {p["store_identifier"]: p["id"] for p in list_all(pid, "products")}
    ent = {e["lookup_key"]: e["id"] for e in list_all(pid, "entitlements")}

    # (store_identifier, rc_type, display_name, entitlement_lookup|None)
    desired = []
    for p in CONFIG["one_time_products"]:
        sid = p["product_id"]
        rc_type = "non_consumable" if sid in NON_CONSUMABLE else "consumable"
        desired.append((sid, rc_type, p["listings"]["en-US"]["title"], ENTITLEMENT_FOR.get(sid)))
    for s in CONFIG["subscriptions"]:
        base = s["product_id"]
        ent_lk = "pro" if base.endswith(".pro") else "vip" if base.endswith(".vip") else None
        for bp in s["base_plans"]:
            sid = f"{base}:{bp['base_plan_id']}"
            desired.append((sid, "subscription", f"{s['listings']['en-US']['title']} {bp['base_plan_id']}", ent_lk))

    to_attach = {}  # ent_id -> [product_id]
    for sid, rc_type, name, ent_lk in desired:
        if sid in existing:
            pidp = existing[sid]
            print(f"  = {sid}")
        else:
            st, body = _post(f"/projects/{pid}/products",
                             {"display_name": name, "type": rc_type, "app_id": app, "store_identifier": sid})
            if st in (200, 201):
                pidp = body["id"]
                print(f"  ✅ {sid} ({rc_type})")
            else:
                print(f"  ❌ {sid}: {st} {json.dumps(body)[:200]}")
                continue
        if ent_lk and ent_lk in ent:
            to_attach.setdefault(ent[ent_lk], []).append(pidp)

    print("=== rattachement aux entitlements ===")
    for eid, pids in to_attach.items():
        st, body = _post(f"/projects/{pid}/entitlements/{eid}/actions/attach_products", {"product_ids": pids})
        ok = st in (200, 201)
        print(f"  {'✅' if ok else '⚠️'} entitlement {eid} <- {len(pids)} produits ({st})"
              + ("" if ok else f" {json.dumps(body)[:200]}"))


def main():
    ap = argparse.ArgumentParser(description="Setup RevenueCat (API v2) pour Mission Geo")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("info")
    sub.add_parser("ensure-entitlements")
    sub.add_parser("ensure-app")
    sub.add_parser("products")
    args = ap.parse_args()
    {"info": cmd_info, "ensure-entitlements": cmd_ensure_entitlements,
     "ensure-app": cmd_ensure_app, "products": cmd_products}[args.cmd](args)


if __name__ == "__main__":
    main()
