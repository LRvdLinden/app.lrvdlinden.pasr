#!/usr/bin/env python3
"""Maakt supabase/catalog/covers.json ({store_id: base64 JPEG}) uit de kaartafbeeldingen van cadeaubon.nl.

Gebruik: python3 tools/make_covers.py <map met <id>.png> [--only id,id]
Alleen winkels die in Pasr een cadeaukaart (kind voucher) zijn: uit supabase/catalog/*.json en de inserts in
supabase/schema.sql. Elke afbeelding wordt bijgesneden tot de ISO-kaartverhouding 1,586:1 (zonder doorzichtige
randen of afgeronde hoeken van de mockup), verkleind tot 640 px breed en opgeslagen als JPEG (kwaliteit 80).
Een staande kaart (Xbox) komt gecentreerd op zijn eigen achtergrondkleur.
"""
import base64, io, json, re, sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "supabase" / "catalog"
OUT = CATALOG / "covers.json"
W, RATIO, QUALITY, MAX_B64 = 640, 1.586, 80, 200_000


def voucher_ids():
    ids = set()
    for p in CATALOG.glob("*.json"):
        if p.name.startswith(("guides", "balance", "covers")):
            continue
        data = json.loads(p.read_text())
        if isinstance(data, list):
            ids |= {r["id"] for r in data if isinstance(r, dict) and r.get("kind") == "voucher"}
    sql = (ROOT / "supabase" / "schema.sql").read_text()
    ids |= set(re.findall(r"\('([a-z0-9-]+)', '[^']*', '[^']*', '[^']*', '#[0-9A-Fa-f]{6}', '[a-z0-9]+', 'voucher'", sql))
    return ids


def edge_colour(im):
    """Mediaan van de dekkende pixels langs de rand: vult wat na het bijsnijden nog doorzichtig is."""
    px = im.load()
    w, h = im.size
    samples = []
    for x in range(0, w, 4):
        for y in (3, h // 2, h - 4):
            if px[x, y][3] > 250:
                samples.append(px[x, y][:3])
    for y in range(0, h, 4):
        for x in (3, w - 4):
            if px[x, y][3] > 250:
                samples.append(px[x, y][:3])
    if not samples:
        return (255, 255, 255)
    return tuple(sorted(c[i] for c in samples)[len(samples) // 2] for i in range(3))


def cover(path):
    im = Image.open(path).convert("RGBA")
    # 1. doorzichtige rand (mockup/afgeronde hoeken) weg
    alpha = im.getchannel("A").point(lambda a: 255 if a > 200 else 0)
    box = alpha.getbbox() or (0, 0, *im.size)
    im = im.crop(box)
    transparent = im.getchannel("A").getextrema()[0] < 250
    if transparent:
        # afgeronde hoeken: een fractie naar binnen snijden, wat overblijft vullen met de randkleur
        dx, dy = round(im.width * 0.012), round(im.height * 0.012)
        im = im.crop((dx, dy, im.width - dx, im.height - dy))
    bg = Image.new("RGBA", im.size, edge_colour(im) + (255,))
    bg.alpha_composite(im)
    im = bg.convert("RGB")
    w, h = im.size
    if w / h < 1.2:
        # staande kaart: gecentreerd op zijn eigen achtergrondkleur
        H = round(W / RATIO)
        art = im.copy()
        art.thumbnail((W, H - 16), Image.LANCZOS)
        canvas = Image.new("RGB", (W, H), edge_colour(im.convert("RGBA")))
        canvas.paste(art, ((W - art.width) // 2, (H - art.height) // 2))
        im = canvas
    else:
        # 2. midden uitsnijden op 1,586:1
        if w / h > RATIO:
            nw = round(h * RATIO)
            im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
        else:
            nh = round(w / RATIO)
            im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
        im = im.resize((W, round(W / RATIO)), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=QUALITY, optimize=True, progressive=True)
    return base64.b64encode(buf.getvalue()).decode()


def main():
    src = Path(sys.argv[1])
    only = set(sys.argv[sys.argv.index("--only") + 1].split(",")) if "--only" in sys.argv else None
    allowed = voucher_ids()
    covers = json.loads(OUT.read_text()) if OUT.exists() and only else {}
    skipped = []
    for p in sorted(src.glob("*.png")):
        sid = p.stem
        if only and sid not in only:
            continue
        if sid not in allowed:
            skipped.append(sid)
            continue
        b64 = cover(p)
        assert len(b64) <= MAX_B64, f"{sid}: te groot ({len(b64)})"
        covers[sid] = b64
    OUT.write_text(json.dumps(dict(sorted(covers.items())), indent=0) + "\n")
    total = sum(len(v) for v in covers.values())
    print(f"{len(covers)} covers in {OUT.relative_to(ROOT)} ({total // 1024} kB base64); overgeslagen (geen Pasr-cadeaukaart): {', '.join(skipped) or '-'}")


if __name__ == "__main__":
    main()
