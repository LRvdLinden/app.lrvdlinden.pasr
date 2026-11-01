#!/usr/bin/env python3
"""Fetch the logo of every store in Shared/Model/StoreTemplates.swift and save it as
Shared/StoreLogos/<domain>.png. Runs in GitHub Actions (Actions › Logos),
because that machine can reach the store websites.

Order per store: the store's full logo on Wikidata/Wikimedia Commons (the wordmark, like SuperCards
shows it), then the icon the home page or its web manifest declares (apple-touch-icon first, largest
first), the usual /apple-touch-icon.png, and finally a small site icon via Google's favicon service.
Then each logo is cleaned up like the cards in SuperCards: the icon's background colour is made
transparent and cropped away, leaving the logo itself as a PNG. That background colour (when it is a
real brand colour) becomes the card colour. Shared/Model/StoreLogoStyles.swift gets, per store, the
card colour and whether the logo should be drawn white/black for contrast (generated; don't edit).

Existing files are kept unless --all is given. Writes tools/logos-missing.txt and tools/logo-styles.json.
--styles only regenerates StoreLogoStyles.swift (e.g. after changing template colours).
"""
import colorsys
import concurrent.futures as cf
import io
import json
import statistics
import re
import sys
import urllib.parse
from pathlib import Path

import requests
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Shared" / "StoreLogos"
SIZE = 256
STYLES_JSON = ROOT / "tools" / "logo-styles.json"
# Hand-picked per brand (tools/logo_candidates.py): the Wikimedia Commons file, the colour of the real card
# ("bg" = the logo's own background colour) and optionally the colour to draw the logo in.
OVERRIDES = json.loads((ROOT / "tools" / "brand_overrides.json").read_text()) if (ROOT / "tools" / "brand_overrides.json").exists() else {}
STYLES_SWIFT = ROOT / "Shared" / "Model" / "StoreLogoStyles.swift"
UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
S = requests.Session()
S.headers.update({"User-Agent": UA, "Accept-Language": "nl-NL,nl;q=0.9"})
DEBUG = "--debug" in sys.argv


def templates():
    """{domain: [store names]} from StoreTemplates.swift."""
    src = (ROOT / "Shared/Model/StoreTemplates.swift").read_text()
    out = {}
    for name, domain in re.findall(r'name: "([^"]+)", domain: "([^"]*)"', src):
        if domain:
            out.setdefault(domain, []).append(name)
    return out


def domains():
    return sorted(templates())


WIKI_UA = {"User-Agent": "PasrLogoFetcher/1.0 (https://pasr.nl; support@pasr.nl)"}


def wikidata_logo(domain):
    """The logo on Wikidata for an organisation whose official website is `domain`."""
    base = domain.split(".")[0]
    names = templates().get(domain, []) + [base]
    seen = set()
    for name in names:
        try:
            hits = requests.get("https://www.wikidata.org/w/api.php", headers=WIKI_UA, timeout=15, params={
                "action": "wbsearchentities", "search": name, "language": "nl", "uselang": "nl",
                "limit": 10, "format": "json"}).json().get("search", [])
        except Exception:
            continue
        ids = [h["id"] for h in hits if h["id"] not in seen]
        seen.update(ids)
        if not ids:
            continue
        try:
            ents = requests.get("https://www.wikidata.org/w/api.php", headers=WIKI_UA, timeout=15, params={
                "action": "wbgetentities", "ids": "|".join(ids), "props": "claims", "format": "json"}).json()["entities"]
        except Exception:
            continue
        for qid in ids:
            claims = ents.get(qid, {}).get("claims", {})
            sites = [c["mainsnak"].get("datavalue", {}).get("value", "") for c in claims.get("P856", [])]
            hosts = {urllib.parse.urlparse(u).netloc.lower().removeprefix("www.") for u in sites if u}
            # Same website, or the same brand on another country domain (mcdonalds.com for mcdonalds.nl).
            if domain not in hosts and base not in {h.split(".")[0] for h in hosts}:
                continue
            for c in claims.get("P154", []):
                file = c["mainsnak"].get("datavalue", {}).get("value")
                if not file:
                    continue
                url = "https://commons.wikimedia.org/wiki/Special:FilePath/" + urllib.parse.quote(file) + "?width=480"
                try:
                    r = requests.get(url, headers=WIKI_UA, timeout=20)
                    img = Image.open(io.BytesIO(r.content)).convert("RGBA")
                except Exception:
                    continue
                if DEBUG:
                    print(f"   wikidata {qid} {file} {img.size}")
                return tile(img)
    return None


def tile(img):
    """A wordmark from Wikimedia, trimmed, already transparent."""
    bbox = img.getchannel("A").getbbox()
    if bbox:
        img = img.crop(bbox)
    img.thumbnail((SIZE * 2, SIZE), Image.LANCZOS)
    return img


def manifest_icons(html, base):
    m = re.search(r'<link\b[^>]*rel=["\']?manifest[^>]*>', html, re.I)
    href = m and re.search(r'href=["\']?([^"\'\s>]+)', m.group(0))
    if not href:
        return []
    try:
        url = urllib.parse.urljoin(base, href.group(1).replace("&amp;", "&"))
        icons = S.get(url, timeout=12).json().get("icons", [])
    except Exception:
        return []
    def size(i):
        m = re.match(r"(\d+)", str(i.get("sizes", "")))
        return int(m.group(1)) if m else 0
    return [urllib.parse.urljoin(url, i["src"]) for i in sorted(icons, key=lambda i: -size(i))
            if i.get("src") and not i["src"].lower().endswith(".svg") and "monochrome" not in str(i.get("purpose", ""))]


def icon_links(html, base):
    found = []
    for tag in re.findall(r"<link\b[^>]*>", html, re.I):
        attrs = {k.lower(): (a or b or c) for k, a, b, c in
                 re.findall(r'([a-zA-Z-]+)\s*=\s*(?:"([^"]*)"|\'([^\']*)\'|([^\s>]+))', tag)}
        rel = attrs.get("rel", "").lower()
        href = attrs.get("href", "")
        if "icon" not in rel or "mask" in rel or not href or href.lower().endswith(".svg"):
            continue
        m = re.match(r"(\d+)", attrs.get("sizes", ""))
        score = (10000 if "apple-touch-icon" in rel else 0) + (int(m.group(1)) if m else 0)
        found.append((urllib.parse.urljoin(base, href.replace("&amp;", "&")), score))
    return [u for u, _ in sorted(found, key=lambda x: -x[1])]


def load(url, min_side):
    try:
        r = S.get(url, timeout=12)
        if DEBUG:
            try:
                size = Image.open(io.BytesIO(r.content)).size
            except Exception:
                size = "geen beeld"
            print(f"   {r.status_code} {size} {url[:110]}")
        if r.status_code >= 400 or len(r.content) > 4_000_000:
            return None
        if url.lower().split("?")[0].endswith(".svg") or "svg" in r.headers.get("content-type", ""):
            import cairosvg   # SVG logos (many shops draw their header logo as SVG)
            return Image.open(io.BytesIO(cairosvg.svg2png(bytestring=r.content, output_width=900))).convert("RGBA")
        img = Image.open(io.BytesIO(r.content))
        if getattr(img, "n_frames", 1) > 1 and img.format == "ICO":
            img = max((img.ico.getimage(s) for s in img.ico.sizes()), key=lambda i: i.width)
        img = img.convert("RGBA")
        if min(img.size) < min_side:
            return None
        return img
    except Exception:
        return None


def square(img):
    # Trim fully transparent edges, then centre on a square canvas.
    bbox = img.getchannel("A").getbbox()
    if bbox:
        img = img.crop(bbox)
    side = max(img.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


# Sites whose own icon is not their logo (e.g. a country flag): use the icon services only.
SKIP_SITE = {"aktiesport.nl", "perrysport.nl", "sportsdirect.com"}


# ---- Clean-up: background out, logo cropped ----


def border_colour(img):
    w, h = img.size
    px = []
    for x in range(w):
        px += [img.getpixel((x, 0)), img.getpixel((x, h - 1)), img.getpixel((x, 1)), img.getpixel((x, h - 2))]
    for y in range(h):
        px += [img.getpixel((0, y)), img.getpixel((w - 1, y)), img.getpixel((1, y)), img.getpixel((w - 2, y))]
    opaque = [p for p in px if p[3] > 200]
    if len(opaque) < len(px) * 0.5:
        return None  # mostly transparent border: already a cut-out logo
    med = tuple(int(statistics.median(p[i] for p in opaque)) for i in range(3))
    near = sum(1 for p in opaque if sum(abs(p[i] - med[i]) for i in range(3)) < 45)
    return med if near >= len(opaque) * 0.82 else False   # False = full-bleed artwork

def colour_to_alpha(img, c, lo=28, hi=90):
    out = img.copy()
    data = []
    for r, g, b, a in img.getdata():
        d = max(abs(r - c[0]), abs(g - c[1]), abs(b - c[2]))
        if d <= lo:
            data.append((r, g, b, 0))
        elif d < hi:
            f = (d - lo) / (hi - lo)
            # un-mix the background so edges don't keep a halo
            nr = min(255, max(0, int(c[0] + (r - c[0]) / f)))
            ng = min(255, max(0, int(c[1] + (g - c[1]) / f)))
            nb = min(255, max(0, int(c[2] + (b - c[2]) / f)))
            data.append((nr, ng, nb, int(a * f)))
        else:
            data.append((r, g, b, a))
    out.putdata(data)
    return out

def ink(img):
    """(mono, hex) – whether the visible logo is one colour, and that colour."""
    px = [p for p in img.getdata() if p[3] > 160]
    if not px:
        return False, None
    med = tuple(int(statistics.median(p[i] for p in px)) for i in range(3))
    near = sum(1 for p in px if sum(abs(p[i] - med[i]) for i in range(3)) < 70)
    return near >= len(px) * 0.9, '#%02X%02X%02X' % med

def hexc(c): return '#%02X%02X%02X' % tuple(c)

def process(img):
    img = img.convert('RGBA')
    bg = border_colour(img)
    meta = {}
    if bg is False:
        meta['opaque'] = True
        return img, meta
    if bg:
        img = colour_to_alpha(img, bg)
        meta['bg'] = hexc(bg)
    bbox = img.getchannel('A').point(lambda a: 255 if a > 24 else 0).getbbox()
    if bbox:
        img = img.crop(bbox)
    mono, col = ink(img)
    meta['mono'] = mono
    if col: meta['ink'] = col
    return img, meta


# ---- Card colour and contrast ----

def lum(h):
    r,g,b=[int(h[i:i+2],16)/255 for i in (1,3,5)]
    f=lambda c: c/12.92 if c<=0.03928 else ((c+0.055)/1.055)**2.4
    return 0.2126*f(r)+0.7152*f(g)+0.0722*f(b)
def contrast(a,b):
    la,lb=sorted([lum(a),lum(b)],reverse=True); return (la+0.05)/(lb+0.05)
def chroma(h):
    r,g,b=[int(h[i:i+2],16)/255 for i in (1,3,5)]; _,l,s=colorsys.rgb_to_hls(r,g,b); return s>0.3 and 0.12<l<0.88
def ink_stats(img):
    px=[p for p in img.getdata() if p[3]>200]
    if not px: return 0, None
    med=tuple(int(statistics.median(p[i] for p in px)) for i in range(3))
    near=sum(1 for p in px if sum(abs(p[i]-med[i]) for i in range(3))<90)
    return near/len(px), '#%02X%02X%02X'%med
def style(img, meta, template_hex):
    """(card colour, recolour?, plate colour). Recolour = the logo's main colour is (almost) the card colour,
    so draw it inverted like the real card: main colour white (or black), white details see-through."""
    bg = meta.get('bg')
    card = bg if bg and chroma(bg) else template_hex
    if meta.get('opaque'):
        return card, False, None
    mono, ink = ink_stats(img)
    if ink is None or contrast(ink, card) >= 2.2:
        return card, False, None
    if mono >= 0.5:
        return card, True, None
    return card, False, (bg if bg and bg != card else ('#FFFFFF' if lum(card) < 0.4 else '#1C1C1E'))


def recolour(img, card, on_hex=None):
    """Main colour → white/black, details in that colour → transparent (the card shows through)."""
    _, ink = ink_stats(img)
    if on_hex:
        on = tuple(int(on_hex[i:i + 2], 16) for i in (1, 3, 5))
    else:
        on = (255, 255, 255) if lum(card) < 0.4 else (17, 17, 17)
    ik = tuple(int(ink[i:i + 2], 16) for i in (1, 3, 5))
    dist = lambda p, q: sum(abs(p[i] - q[i]) for i in range(3))
    out = []
    for r, g, b, a in img.getdata():
        if a == 0:
            out.append((r, g, b, a))
        elif dist((r, g, b), ik) < 110:
            out.append(on + (a,))
        elif dist((r, g, b), on) < 120:
            out.append((r, g, b, 0))
        else:
            out.append((r, g, b, a))
    res = img.copy()
    res.putdata(out)
    return res


def template_colours():
    src = (ROOT / "Shared/Model/StoreTemplates.swift").read_text()
    return {d: c for d, c in re.findall(r'domain: "([^"]+)", category: "[^"]*", colorHex: "([^"]+)"', src)}


def write_styles():
    metas = json.loads(STYLES_JSON.read_text()) if STYLES_JSON.exists() else {}
    colours = template_colours()
    rows = []
    for f in sorted(OUT.glob("*.png")):
        d = f.stem
        meta = metas.get(d, {})
        img = Image.open(f).convert("RGBA")
        card, bake, plate = style(img, meta, colours.get(d, "#2B2F3A"))
        if d in OVERRIDES:   # hand-picked: the real card colour, the logo as saved
            want = OVERRIDES[d].get("card", card)
            card, bake, plate = (meta.get("bg") or card) if want == "bg" else want, False, None
        if bake:   # baked into the PNG once; afterwards the contrast is fine and nothing changes
            recolour(img, card).save(f, optimize=True)
        tint = None
        q = lambda v: f'"{v}"' if v else "nil"
        rows.append(f'        "{d}": .init(card: "{card}", tint: {q(tint)}, plate: {q(plate)}, opaque: {str(bool(meta.get("opaque"))).lower()}),')
    STYLES_SWIFT.write_text("""// Generated by tools/fetch_logos.py — don't edit by hand.
// Per store website: the card colour that matches its logo, and how to draw the logo on it.

struct StoreLogoStyle: Equatable, Hashable {
    /// Card / tile colour.
    let card: String
    /// Draw the logo in this single colour (for one-colour logos that would vanish on the card).
    let tint: String?
    /// A small plate behind the logo, for multi-colour logos with too little contrast.
    let plate: String?
    /// The logo is artwork that fills its square (no background to remove): show it as an icon.
    let opaque: Bool
}

enum StoreLogoStyles {
    static func style(for domain: String?) -> StoreLogoStyle? { domain.flatMap { all[$0] } }

    static let all: [String: StoreLogoStyle] = [
""" + "\n".join(rows) + """
    ]
}
""")
    print(f"StoreLogoStyles.swift: {len(rows)} stores")
    write_colour_history()


def write_colour_history():
    """Every card colour Pasr ever gave a store by default. Existing cards still in one of these colours were
    never recoloured by their owner, so the app moves them to the current brand colour (LogoService)."""
    path = ROOT / "tools" / "colour-history.json"
    hist = {k: set(v) for k, v in json.loads(path.read_text()).items()} if path.exists() else {}
    src = (ROOT / "Shared/Model/StoreTemplates.swift").read_text()
    styles = dict(re.findall(r'"([^"]+)": \.init\(card: "([^"]+)"', STYLES_SWIFT.read_text()))
    for tid, domain, colour in re.findall(r'id: "([^"]+)", name: "[^"]+", domain: "([^"]*)", category: "[^"]+", colorHex: "([^"]+)"', src):
        hist.setdefault(tid, set()).add(colour.upper())
        if domain in styles:
            hist[tid].add(styles[domain].upper())
    path.write_text(json.dumps({k: sorted(v) for k, v in sorted(hist.items())}, indent=0) + "\n")
    rows = [f'        "{k}": [{", ".join(chr(34) + c + chr(34) for c in sorted(v))}],' for k, v in sorted(hist.items())]
    (ROOT / "Shared" / "Model" / "StoreColourHistory.swift").write_text("""// Generated by tools/fetch_logos.py — don't edit by hand.
// Every default card colour a store ever had in Pasr. A card still in one of these was never recoloured by its
// owner, so it follows the store's current brand colour.

enum StoreColourHistory {
    static func isDefault(_ hex: String, for templateID: String) -> Bool {
        all[templateID]?.contains(hex.uppercased()) ?? false
    }

    static let all: [String: Set<String>] = [
""" + "\n".join(rows) + """
    ]
}
""")


def save_logo(domain, img, metas):
    o = OVERRIDES.get(domain, {})
    if o.get("file") or o.get("site") or o.get("logo_url"):
        # Hand-picked logos stay as drawn (no background removal): cropped to the artwork, and a logo in a
        # coloured box sits on a card of exactly that colour, so the box blends into the card.
        clean = img.convert("RGBA")
        bbox = clean.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
        if bbox:
            clean = clean.crop(bbox)
        bg = border_colour(clean)
        meta = {"bg": hexc(bg)} if bg else {}
        if bg and o.get("card") == "bg":
            # The card takes the box colour, so the box itself can go: crop to what's drawn inside it.
            w, h = clean.size
            px = clean.load()
            xs, ys = [], []
            for y in range(h):
                for x in range(w):
                    r, g, b, a = px[x, y]
                    if a > 128 and max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2])) > 60:
                        xs.append(x); ys.append(y)
            if xs:
                m = int(max(w, h) * 0.03)
                clean = clean.crop((max(min(xs) - m, 0), max(min(ys) - m, 0), min(max(xs) + m + 1, w), min(max(ys) + m + 1, h)))
        if o.get("recolour"):
            card = o.get("card") if o.get("card") not in (None, "bg") else meta.get("bg", "#000000")
            clean = recolour(clean, card, o["recolour"])
    else:
        clean, meta = process(img)
    clean.thumbnail((SIZE * 2, SIZE), Image.LANCZOS)
    clean.save(OUT / f"{domain}.png", optimize=True)
    metas[domain] = {k: v for k, v in meta.items() if k in ("bg", "opaque")}
    src = o.get("file") or o.get("logo_url") or ("site" if o.get("site") else None)
    if src:
        metas[domain]["src"] = src


def commons_file(title):
    """A Commons file as an 800 px image; retries politely when Wikimedia asks to slow down."""
    import time
    url = "https://commons.wikimedia.org/wiki/Special:FilePath/" + urllib.parse.quote(title.removeprefix("File:")) + "?width=800"
    for attempt in range(5):
        try:
            r = requests.get(url, headers=WIKI_UA, timeout=25)
            if r.status_code == 429 or r.status_code >= 500:
                time.sleep(3 + attempt * 4)
                continue
            return Image.open(io.BytesIO(r.content)).convert("RGBA")
        except Exception:
            time.sleep(2)
    print("   commons failed:", title, flush=True)
    return None


def header_logos(html, base):
    """The logo image(s) in a shop's own page header: <img> whose src, alt, class or id says "logo"."""
    found = []
    for tag in re.findall(r"<img\b[^>]*>", html, re.I):
        if not re.search(r"logo", tag, re.I):
            continue
        m = re.search(r'\s(?:data-src|src)\s*=\s*["\']([^"\']+)', tag, re.I)
        if m and not m.group(1).startswith("data:"):
            found.append(urllib.parse.urljoin(base, m.group(1).replace("&amp;", "&")))
    return found[:4]


def site_logo(domain):
    for home in (f"https://www.{domain}/", f"https://{domain}/"):
        try:
            r = S.get(home, timeout=15)
        except Exception:
            continue
        if not r.ok:
            continue
        for url in header_logos(r.text[:1_500_000], r.url):
            img = load(url, 24)
            if img and max(img.size) >= 120:
                return img
        break
    return None


def fetch(domain):
    o = OVERRIDES.get(domain, {})
    if o.get("logo_url"):
        return load(o["logo_url"], 24)
    if o.get("site"):
        img = site_logo(domain)
        if img:
            return img
    if OVERRIDES.get(domain, {}).get("file"):
        # hand-picked: that file or nothing (never fall back to a different logo)
        return commons_file(OVERRIDES[domain]["file"])
    # 1. The full logo (wordmark) on Wikidata/Wikimedia Commons: sharp and complete, like SuperCards shows it.
    img = None if OVERRIDES.get(domain, {}).get("nowiki") else wikidata_logo(domain)
    if img:
        return img
    # 2. Otherwise the icon the store publishes on its website.
    candidates = []
    for home in () if domain in SKIP_SITE else (f"https://www.{domain}/", f"https://{domain}/"):
        try:
            r = S.get(home, timeout=12)
            if r.ok:
                html = r.text[:800_000]
                candidates += icon_links(html, r.url) + manifest_icons(html, r.url)
                break
        except Exception:
            continue
    if domain not in SKIP_SITE:
        candidates += [f"https://www.{domain}/apple-touch-icon.png", f"https://{domain}/apple-touch-icon.png"]
    seen = set()
    for url in candidates:
        if url in seen:
            continue
        seen.add(url)
        img = load(url, 96)
        if img:
            return square(img)
    # 3. Small site icons as a last resort.
    if domain in SKIP_SITE:
        return None
    for url in (f"https://t1.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL"
                f"&url=https://www.{domain}&size=256",
                f"https://www.google.com/s2/favicons?domain={domain}&sz=256",
                f"https://icons.duckduckgo.com/ip3/{domain}.ico",
                f"https://www.{domain}/favicon.ico"):
        img = load(url, 48)
        if img:
            return square(img)
    return None


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    redo = "--all" in sys.argv
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    metas = json.loads(STYLES_JSON.read_text()) if STYLES_JSON.exists() else {}
    if "--styles" in sys.argv:
        write_styles()
        return
    # new hand-picked logos are fetched again too
    def wanted(o):
        return o.get("file") or o.get("logo_url") or ("site" if o.get("site") else None)
    changed = [d for d, o in OVERRIDES.items() if wanted(o) and metas.get(d, {}).get("src") != wanted(o)]
    todo = only or sorted({d for d in domains() if redo or not (OUT / f"{d}.png").exists()} | set(changed))
    # "manual": the logo file was made by hand (e.g. from the shop's SVG); never fetch over it
    todo = [d for d in todo if not OVERRIDES.get(d, {}).get("manual")]
    if DEBUG:
        for d in todo:
            print(d); fetch(d)
        return
    missing = []

    def work(d):
        img = fetch(d)
        if img:
            save_logo(d, img, metas)
            return d, True
        return d, False

    first = [d for d in todo if d in OVERRIDES and (OVERRIDES[d].get("file") or OVERRIDES[d].get("site") or OVERRIDES[d].get("logo_url"))]
    for d in first:   # Commons one at a time (it rate-limits bursts)
        d, ok = work(d)
        print(("ok      " if ok else "MISSING ") + d, flush=True)
        if not ok:
            missing.append(d)
    with cf.ThreadPoolExecutor(12) as pool:
        for d, ok in pool.map(work, [d for d in todo if d not in first]):
            print(("ok      " if ok else "MISSING ") + d, flush=True)
            if not ok:
                missing.append(d)
    all_missing = sorted(d for d in domains() if not (OUT / f"{d}.png").exists())
    (ROOT / "tools" / "logos-missing.txt").write_text("".join(f"{d}\n" for d in all_missing))
    print(f"\n{len(domains()) - len(all_missing)} logos, {len(all_missing)} missing")
    STYLES_JSON.write_text(json.dumps(dict(sorted(metas.items())), indent=1) + "\n")
    write_styles()


if __name__ == "__main__":
    main()
