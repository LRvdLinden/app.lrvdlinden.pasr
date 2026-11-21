#!/usr/bin/env python3
"""Zet alle winkels uit de app (Shared/Model/StoreTemplates.swift + App/StoreLogos + StoreLogoStyles) om naar
supabase/catalog/stores.json, voor de eenmalige vulling van het beheer (pasr_stores). Sinds versie 1.0.2 is het
beheer leidend: daar pas je daarna namen, kleuren en logo's aan; de lijst in de app is alleen nog de reserve.

Het logo wordt kant-en-klaar gemaakt voor de kaartkleur (zoals StoreLogoMark het tekende): eenkleurig gemaakt
(tint), op een plaatje (plate) of met afgeronde hoeken (opaque). Zo hoeft de app er geen stijl meer op te zetten.

python3 tools/build_catalog.py
"""
import base64, io, json, re
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = ROOT / "Shared" / "Model" / "StoreTemplates.swift"
STYLES = ROOT / "Shared" / "Model" / "StoreLogoStyles.swift"
LOGOS = ROOT / "App" / "StoreLogos"
OUT = ROOT / "supabase" / "catalog" / "stores.json"
MAX = 256          # langste zijde van het logo in px
# Winkels die uit de lijst zijn gehaald (in het beheer: niet gepubliceerd). Bestaande kaarten blijven werken.
REMOVED = {
    "perrysport": "Perry Sport", "sportdirect": "Sports Direct", "firezone": "Firezone", "aktiesport": "Aktiesport",
    "blushy": "Blushy", "coop": "Coop", "janlinders": "Jan Linders", "fitforfree": "Fit For Free",
    "fun": "Fun Speelgoed", "jumper": "Jumper", "euroscoop": "Euroscoop", "deen": "Deen", "ako": "AKO",
    "hobbydos": "Hobbydos", "boerenbond": "Boerenbond", "vanhaaren2": "Schoenenreus", "intratuincadeau": "Tuinbon",
}


def templates():
    src = TEMPLATES.read_text()
    body = src[src.index("static let builtIn"):]
    out = []
    for m in re.finditer(r'\.init\((id: "[^\n]*)\),?\s*$', body, re.M):
        line = m.group(1)
        def get(key, default=None):
            mm = re.search(key + r': "([^"]*)"', line)
            return mm.group(1) if mm else default
        fmt = re.search(r'format: \.(\w+)', line)
        kind = re.search(r'kind: \.(\w+)', line)
        al = re.search(r'aliases: \[([^\]]*)\]', line)
        out.append({
            "id": get("id"), "name": get("name"), "domain": get("domain", ""), "category": get("category", "Overig"),
            "colorHex": get("colorHex", "#2B2F3A"), "format": fmt.group(1) if fmt else "code128",
            "kind": kind.group(1) if kind else "loyalty",
            "aliases": [a.lower() for a in re.findall(r'"([^"]+)"', al.group(1))] if al else [],
        })
    return out


def styles():
    st = {}
    for m in re.finditer(r'"([^"]+)": \.init\(card: "([^"]+)", tint: (nil|"[^"]+"), plate: (nil|"[^"]+"), opaque: (true|false)\)',
                         STYLES.read_text()):
        q = lambda v: None if v == "nil" else v.strip('"')
        st[m.group(1)] = {"card": m.group(2), "tint": q(m.group(3)), "plate": q(m.group(4)), "opaque": m.group(5) == "true"}
    return st


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def finish(path, style):
    im = Image.open(path).convert("RGBA")
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    im.thumbnail((MAX, MAX), Image.LANCZOS)
    if style and style["opaque"]:
        r = int(min(im.size) * 0.22)
        mask = Image.new("L", im.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.size[0] - 1, im.size[1] - 1], r, fill=255)
        im.putalpha(Image.composite(im.getchannel("A"), mask, mask))
    elif style:
        if style["tint"]:
            solid = Image.new("RGBA", im.size, rgb(style["tint"]) + (255,))
            solid.putalpha(im.getchannel("A"))
            im = solid
        if style["plate"]:
            w, h = im.size
            px, py = int(h * 0.22), int(h * 0.14)
            plate = Image.new("RGBA", (w + 2 * px, h + 2 * py), (0, 0, 0, 0))
            ImageDraw.Draw(plate).rounded_rectangle([0, 0, plate.size[0] - 1, plate.size[1] - 1], int((h + 2 * py) * 0.24),
                                                    fill=rgb(style["plate"]) + (255,))
            plate.alpha_composite(im, (px, py))
            im = plate
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return base64.b64encode(buf.getvalue()).decode()


def main():
    st = styles()
    rows, missing = [], []
    for t in templates():
        style = st.get(t["domain"])
        card = (style or {}).get("card") or t["colorHex"]
        logo_path = LOGOS / f"{t['domain']}.png"
        logo = finish(logo_path, style) if t["domain"] and logo_path.exists() else None
        if not logo:
            missing.append(t["id"])
        rows.append({"id": t["id"].lower(), "name": t["name"], "domain": t["domain"], "category": t["category"],
                     "card_hex": card.upper(), "format": t["format"], "kind": t["kind"], "aliases": t["aliases"],
                     "logo": logo, "published": True})
    ids = {r["id"] for r in rows}
    for rid, name in REMOVED.items():
        if rid not in ids:
            rows.append({"id": rid, "name": name, "domain": "", "category": "Overig", "card_hex": "#2B2F3A",
                         "format": "code128", "kind": "loyalty", "aliases": [], "logo": None, "published": False})
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(rows, ensure_ascii=False, separators=(",", ":")))
    size = OUT.stat().st_size / 1e6
    print(f"{len(rows)} winkels ({sum(r['published'] for r in rows)} gepubliceerd), {size:.1f} MB; zonder logo: {missing}")


if __name__ == "__main__":
    main()
