#!/usr/bin/env python3
"""Maakt de macOS-iconen van Pasr Zakelijk uit het goedgekeurde iOS-icoon (AppIcon-1024.png).

macOS maskeert iconen niet zelf: het icoon krijgt de afgeronde vorm van het macOS-raster (824 px op 1024,
hoekstraal 185) met een zachte schaduw, en alle maten voor de Mac (16 t/m 512 @1x/@2x) in AppIcon.appiconset.

python3 zakelijk/apple/tools/make_mac_icon.py
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SET = Path(__file__).resolve().parent.parent / "PasrZakelijk/Assets.xcassets/AppIcon.appiconset"
SIZES = [16, 32, 128, 256, 512]


def master():
    canvas = 1024
    body, radius = 824, 185
    offset = (canvas - body) // 2
    art = Image.open(SET / "AppIcon-1024.png").convert("RGBA").resize((body, body), Image.Resampling.LANCZOS)
    mask = Image.new("L", (body, body), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, body - 1, body - 1), radius=radius, fill=255)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    shadow = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((offset, offset + 12, offset + body, offset + body + 12), radius=radius, fill=90)
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    out.paste(Image.new("RGBA", (canvas, canvas), (0, 0, 0, 255)), (0, 0), shadow)
    out.paste(art, (offset, offset), mask)
    return out


def main():
    big = master()
    images = [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}]
    for size in SIZES:
        for scale in (1, 2):
            px = size * scale
            name = f"AppIcon-mac-{size}@{scale}x.png"
            big.resize((px, px), Image.Resampling.LANCZOS).save(SET / name, optimize=True)
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{size}x{size}"})
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (SET / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print("Wrote", len(images) - 1, "macOS icons")


if __name__ == "__main__":
    main()
