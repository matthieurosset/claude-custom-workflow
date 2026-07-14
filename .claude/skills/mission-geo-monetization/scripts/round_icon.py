#!/usr/bin/env python3
"""Transforme une image carrée d'icône en vraie icône : coins arrondis + fond
transparent autour (RGBA). Utilisable dans l'app ET comme icône produit Play.

Pas de fal — traitement local (Pillow). Anti-aliasing par supersampling du masque.

Usage :
  python round_icon.py <in.png> <out.png> [radius_pct]
  # radius_pct = rayon des coins en % du côté (défaut 0.20 ≈ look app-icon)

Exemple :
  python round_icon.py out/product_icons/trials/miles_tier2_v3.png \
                        out/product_icons/mg.miles.tier1.png
"""
import sys
from PIL import Image, ImageDraw


def round_icon(src, dst, radius_pct=0.20, supersample=4, size=None):
    im = Image.open(src).convert("RGBA")
    if size:
        im = im.resize((size, size), Image.LANCZOS)
    w, h = im.size
    s = supersample
    mask = Image.new("L", (w * s, h * s), 0)
    d = ImageDraw.Draw(mask)
    r = int(min(w, h) * radius_pct * s)
    d.rounded_rectangle([0, 0, w * s - 1, h * s - 1], radius=r, fill=255)
    mask = mask.resize((w, h), Image.LANCZOS)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    out.save(dst)
    print(f"  ✅ {dst} ({w}x{h}, coins arrondis {radius_pct:.0%}, fond transparent)")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("Usage: round_icon.py <in.png> <out.png> [radius_pct]")
    rp = float(sys.argv[3]) if len(sys.argv) > 3 else 0.20
    round_icon(sys.argv[1], sys.argv[2], radius_pct=rp)
