#!/usr/bin/env python3
"""Zet alle PNG's in een map om naar RGB zonder alfakanaal (eis van App Store Connect) en comprimeert ze.

python3 zakelijk/appstore/source/flatten.py <map>
"""
import sys
from pathlib import Path

from PIL import Image

root = Path(sys.argv[1])
for f in sorted(root.rglob("*.png")):
    im = Image.open(f)
    if im.mode != "RGB":
        bg = Image.new("RGB", im.size, (10, 11, 16))
        bg.paste(im, mask=im.convert("RGBA").split()[3])
        im = bg
    im.save(f, optimize=True)
print("klaar")
