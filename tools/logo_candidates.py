#!/usr/bin/env python3
"""Contact sheets of logo candidates from Wikimedia Commons, to pick the right brand logo by hand.
python3 tools/logo_candidates.py "ah.nl=Albert Heijn; kruidvat.nl=Kruidvat; ..."
Writes tools/candidates/sheet-N.png (each tile on a light and a dark half, numbered) and candidates.json."""
import io, json, sys
from pathlib import Path
import requests
from PIL import Image, ImageDraw, ImageFont

UA = {"User-Agent": "PasrLogoFetcher/1.0 (https://pasr.nl; support@pasr.nl)"}
OUT = Path(__file__).resolve().parent / "candidates"
API = "https://commons.wikimedia.org/w/api.php"
PER = 6
TW, TH = 220, 120


def search(q):
    r = requests.get(API, headers=UA, timeout=20, params={
        "action": "query", "format": "json", "generator": "search", "gsrnamespace": 6,
        "gsrsearch": f'intitle:"{q}" logo', "gsrlimit": 12,
        "prop": "imageinfo", "iiprop": "url|size|mime", "iiurlwidth": 400}).json()
    pages = sorted((r.get("query") or {}).get("pages", {}).values(), key=lambda p: p.get("index", 99))
    out = []
    for p in pages:
        ii = (p.get("imageinfo") or [{}])[0]
        if ii.get("mime", "").startswith("image/") and ii.get("thumburl"):
            out.append({"title": p["title"], "thumb": ii["thumburl"], "mime": ii["mime"]})
    return out[:PER]


def main():
    OUT.mkdir(exist_ok=True)
    brands = [a.strip().split("=", 1) for a in " ".join(sys.argv[1:]).split(";") if "=" in a]
    result, rows = {}, []
    for domain, name in brands:
        cands = search(name)
        if cands or domain not in result:
            result[domain] = [c["title"] for c in cands]
        imgs = []
        for c in cands:
            try:
                imgs.append(Image.open(io.BytesIO(requests.get(c["thumb"], headers=UA, timeout=20).content)).convert("RGBA"))
            except Exception:
                imgs.append(None)
        rows.append((domain, name, imgs))
        print(domain, result[domain], flush=True)
    font = ImageFont.load_default()
    for s in range(0, len(rows), 12):
        chunk = rows[s:s + 12]
        sheet = Image.new("RGB", (160 + PER * (TW + 8), len(chunk) * (TH + 8)), (200, 200, 205))
        d = ImageDraw.Draw(sheet)
        for r, (domain, name, imgs) in enumerate(chunk):
            y = r * (TH + 8)
            d.text((6, y + TH // 2 - 6), domain, fill=(0, 0, 0), font=font)
            for i, im in enumerate(imgs):
                x = 160 + i * (TW + 8)
                d.rectangle((x, y, x + TW // 2, y + TH), fill=(255, 255, 255))
                d.rectangle((x + TW // 2, y, x + TW, y + TH), fill=(30, 30, 34))
                if im is not None:
                    t = im.copy(); t.thumbnail((TW - 16, TH - 22))
                    sheet.paste(t, (x + (TW - t.width) // 2, y + 4 + (TH - 22 - t.height) // 2), t)
                d.rectangle((x, y + TH - 16, x + 22, y + TH), fill=(255, 220, 0))
                d.text((x + 6, y + TH - 14), str(i), fill=(0, 0, 0), font=font)
        sheet.save(OUT / f"sheet-{s // 12}.png")
    (OUT / "candidates.json").write_text(json.dumps(result, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
