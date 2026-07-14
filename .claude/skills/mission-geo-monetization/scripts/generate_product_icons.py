#!/usr/bin/env python3
"""Génère les icônes des produits in-app Mission Geo via fal.ai (fal-ai/nano-banana-2).

Les icônes produit Play : PNG 1:1, 512–1080 px, sans texte/branding, 1 image
distincte par produit (apparaît sur la fiche + pendant l'achat). Elles ne sont
PAS uploadables par API → ce script produit les fichiers, l'upload reste manuel
dans Play Console (Monetize → Products → <produit> → Icon).

Modèle + auth = même convention que les autres scripts fal du repo
(`scripts/generate_home_icons.py`). Clé via env FAL_KEY.

Usage :
    FAL_KEY=<key> python3 .claude/skills/mission-geo-monetization/scripts/generate_product_icons.py
    FAL_KEY=<key> python3 .../generate_product_icons.py --only mg.indices.tier1

Sortie : out/product_icons/<product_id>.png  (1024×1024 PNG)
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

FAL_KEY = os.environ.get("FAL_KEY") or os.environ.get("FAL_API_KEY")
if not FAL_KEY:
    sys.exit("ERROR: FAL_KEY non défini.")

FAL_ENDPOINT = "https://fal.run/fal-ai/nano-banana-2"
ROOT = Path(__file__).resolve().parents[4]  # .claude/skills/<skill>/scripts/ -> repo root
OUT_DIR = ROOT / "out" / "product_icons"

# Style commun : icône de store soignée, fond complet (PAS de transparence — les
# icônes produit s'affichent sur fond clair du store), sans aucun texte.
STYLE = (
    "A polished glossy 3D mobile game store icon, vibrant and premium, soft studio "
    "lighting, smooth rounded shapes, depicting {subject}, centered with generous "
    "margin on a smooth blue radial gradient background, modern app-icon aesthetic, "
    "high-quality 3D render. ABSOLUTELY no text, no letters, no numbers, no words, "
    "no logo, no watermark. Single clear centered subject."
)

# 1 sujet distinct par produit (la quantité se lit visuellement : 1 / quelques / beaucoup).
SUBJECTS = {
    "mg.indices.tier1": "a single glowing golden lightbulb representing a hint, emitting a soft warm glow",
    "mg.indices.tier2": "a small cluster of three glowing golden lightbulbs representing hints",
    "mg.indices.tier3": "a large shining heap of many glowing golden lightbulbs representing hints",
    "mg.miles.tier1": "a small neat stack of shiny golden coins",
    "mg.miles.tier2": "a big overflowing pile of shiny golden coins",
    "mg.tickets.tier1": "a few colorful event tickets held together",
    "mg.tickets.tier2": "a fanned spread of several colorful event tickets",
    "mg.tickets.tier3": "a thick bundle of many colorful event tickets",
    "mg.removeads": "a plain glossy shield (smooth surface, NO emblem, NO crest, NO letters) with a simple megaphone crossed out by a red prohibition slash on it, and a few small BLANK empty colorful pop-up bubbles (completely empty, NO letters, NO words, NO 'AD' text) being deflected around it, representing an ad-free experience",
    "mg.bundle.starter": "an open treasure chest overflowing with a generous mix of golden coins, colorful event tickets and glowing lightbulbs, a welcome starter bundle",
}

try:
    import requests as _rq
    _HAS_RQ = True
except ImportError:
    _HAS_RQ = False


def _headers():
    return {"Authorization": f"Key {FAL_KEY}", "Content-Type": "application/json"}


def _post(url, payload):
    if _HAS_RQ:
        r = _rq.post(url, json=payload, headers=_headers(), timeout=180)
        return r.status_code, r.json()
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers=_headers(), method="POST")
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


def _get(url):
    if _HAS_RQ:
        r = _rq.get(url, headers=_headers(), timeout=60)
        return r.status_code, r.json()
    req = urllib.request.Request(url, headers=_headers(), method="GET")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


def _download(url, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    if _HAS_RQ:
        r = _rq.get(url, timeout=180)
        r.raise_for_status()
        dest.write_bytes(r.content)
    else:
        with urllib.request.urlopen(url, timeout=180) as resp:
            dest.write_bytes(resp.read())


def _extract_urls(result):
    imgs = result.get("images")
    out = []
    if isinstance(imgs, list):
        for it in imgs:
            if isinstance(it, dict) and "url" in it:
                out.append(it["url"])
            elif isinstance(it, str):
                out.append(it)
    return out


def generate(prompt, dest):
    payload = {"prompt": prompt, "num_images": 1, "output_format": "png",
               "aspect_ratio": "1:1", "resolution": "1K"}
    status, body = _post(FAL_ENDPOINT, payload)
    if status == 200:
        urls = _extract_urls(body)
        if urls:
            _download(urls[0], dest)
            return True
    if status in (200, 202):
        rid = body.get("request_id")
        status_url = body.get("status_url") or (f"https://queue.fal.run/fal-ai/nano-banana-2/requests/{rid}/status" if rid else None)
        response_url = body.get("response_url") or (f"https://queue.fal.run/fal-ai/nano-banana-2/requests/{rid}" if rid else None)
        if status_url:
            for _ in range(60):
                time.sleep(5)
                _, pb = _get(status_url)
                st = pb.get("status", "")
                if st == "COMPLETED":
                    _, rb = _get(response_url)
                    urls = _extract_urls(rb)
                    if urls:
                        _download(urls[0], dest)
                        return True
                    return False
                if st in ("FAILED", "CANCELLED"):
                    print(f"  job {st}: {json.dumps(pb)[:300]}")
                    return False
            return False
    print(f"  ERROR {status}: {json.dumps(body)[:400]}")
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="un seul product_id")
    args = ap.parse_args()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    targets = [args.only] if args.only else list(SUBJECTS)
    made = []
    for pid in targets:
        if pid not in SUBJECTS:
            print(f"  ? {pid} inconnu"); continue
        dest = OUT_DIR / f"{pid}.png"
        print(f"[{pid}] génération...")
        if generate(STYLE.format(subject=SUBJECTS[pid]), dest):
            print(f"  ✅ {dest}")
            made.append(pid)
        else:
            print(f"  ❌ {pid}")
    print(f"\n{len(made)}/{len(targets)} icônes générées dans {OUT_DIR}")


if __name__ == "__main__":
    main()
