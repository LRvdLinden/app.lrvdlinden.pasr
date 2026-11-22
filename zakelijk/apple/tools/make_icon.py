#!/usr/bin/env python3
"""Maakt het icoon van Pasr Zakelijk: het Pasr-icoon (App/Assets.xcassets) met een mintgroene stempel rechtsonder.

python3 zakelijk/apple/tools/make_icon.py  (vanuit de repo-root of waar dan ook)
"""
from pathlib import Path
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SRC = REPO / "App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
ASSETS = HERE.parent / "PasrZakelijk/Assets.xcassets"

S = 4  # supersampling
MINT, MINT_DARK, INK = (46, 211, 166), (18, 167, 126), (10, 11, 16)


def badge(size):
    big = size * S
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy, r = big * 0.745, big * 0.745, big * 0.205
    d.ellipse([cx - r - big * 0.018, cy - r - big * 0.018, cx + r + big * 0.018, cy + r + big * 0.018], fill=INK + (255,))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=MINT + (255,))
    ri = r * 0.80
    d.ellipse([cx - ri, cy - ri, cx + ri, cy + ri], outline=(255, 255, 255, 235), width=int(big * 0.013))
    w = int(big * 0.034)
    pts = [(cx - r * 0.42, cy + r * 0.02), (cx - r * 0.10, cy + r * 0.34), (cx + r * 0.46, cy - r * 0.30)]
    d.line(pts, fill=(255, 255, 255, 255), width=w, joint="curve")
    for p in (pts[0], pts[2]):
        d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=(255, 255, 255, 255))
    return img.resize((size, size), Image.LANCZOS)


def main():
    base = Image.open(SRC).convert("RGBA").resize((1024, 1024))
    icon = Image.alpha_composite(base, badge(1024)).convert("RGB")
    (ASSETS / "AppIcon.appiconset").mkdir(parents=True, exist_ok=True)
    (ASSETS / "AppIconDisplay.imageset").mkdir(parents=True, exist_ok=True)
    icon.save(ASSETS / "AppIcon.appiconset/AppIcon-1024.png")
    icon.resize((256, 256), Image.LANCZOS).save(ASSETS / "AppIconDisplay.imageset/icon.png")
    (ASSETS / "AppIcon.appiconset/Contents.json").write_text(
        '{\n  "images": [\n    {\n      "filename": "AppIcon-1024.png",\n      "idiom": "universal",\n'
        '      "platform": "ios",\n      "size": "1024x1024"\n    }\n  ],\n  "info": {\n    "author": "xcode",\n    "version": 1\n  }\n}\n')
    (ASSETS / "AppIconDisplay.imageset/Contents.json").write_text(
        '{\n  "images": [\n    {\n      "filename": "icon.png",\n      "idiom": "universal"\n    }\n  ],\n'
        '  "info": {\n    "author": "xcode",\n    "version": 1\n  }\n}\n')
    print("Icoon geschreven in", ASSETS)


if __name__ == "__main__":
    main()
