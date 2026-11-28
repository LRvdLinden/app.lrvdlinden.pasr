#!/usr/bin/env python3
"""Zet de schermafbeeldingen uit build/raw/ (PNG, deviceScaleFactor 2) om naar img/<naam>.jpg (JPEG kwaliteit 85,
hoogstens 2400 px breed), alleen de afbeeldingen die handboek.html gebruikt. Daarna: node render.cjs."""
import re
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
RAW = HERE / "build" / "raw"
html = (HERE / "handboek.html").read_text(encoding="utf-8")
used = sorted(set(re.findall(r'src="img/([a-z0-9-]+)\.jpg"', html)))
missing = []
for name in used:
    src = RAW / f"{name}.png"
    if not src.exists():
        missing.append(name)
        continue
    im = Image.open(src)
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        bg = Image.new("RGB", im.size, "white")
        bg.paste(im, mask=im.split()[-1])
        im = bg
    else:
        im = im.convert("RGB")
    if im.width > 2400:
        im = im.resize((2400, round(im.height * 2400 / im.width)), Image.LANCZOS)
    im.save(HERE / "img" / f"{name}.jpg", "JPEG", quality=85, optimize=True, progressive=True)
print(f"{len(used) - len(missing)} afbeeldingen omgezet")
if missing:
    sys.exit("Ontbreekt in build/raw (eerst shots/web.cjs en shots/app.cjs): " + ", ".join(missing))
