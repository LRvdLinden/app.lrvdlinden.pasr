#!/usr/bin/env python3
"""Deelpagina per stempelkaart: pasr.nl/zakelijk/kaart/<id>/ met eigen titel, beschrijving, canonical, OG/Twitter-tags,
JSON-LD (LocalBusiness met de beloning als Offer) en een eigen OG-afbeelding /og/zakelijk/<id>.png (1200x630, in de
kaartstijl van de app en pasr.nl). Zo toont WhatsApp, iMessage, Facebook en LinkedIn bij delen de stempelkaart zelf.
De pagina werkt verder net als /zakelijk/kaart/#<id> (zakelijk.js leest de id uit het pad).

Bron: .cache/live-catalog.json (tools/fetch_live_catalog.py):
- share_cards (pasr_business_share_cards via de Management API): alle gepubliceerde kaarten van goedgekeurde zaken.
  Vindbaar (listed) = index + sitemap; niet vindbaar = wel een pagina met OG, maar noindex en niet in de sitemap.
- ontbreekt dat: businesses (pasr_business_directory), alleen de vindbare kaarten. Pagina's van niet-vindbare kaarten
  die er al stonden worden dan niet van de server gehaald (zie .cache/kaart-pages.json, gelezen door de Website-workflow).
- geen live catalogus: er gebeurt niets.
Nooit een pagina voor "Apple Review" (de demo-zaak voor App Review); die link blijft werken via de #-pagina, zonder OG.

OG-afbeeldingen worden alleen opnieuw gemaakt als de kaart veranderd is: .cache/og-zakelijk/<id>.<hash>.png (de
workflow bewaart die map met actions/cache), zodat de uurlijkse build snel blijft.
Gebruik: python3 tools/make_kaart_pages.py [--preview map]  (wordt aangeroepen door tools/make_website.py)"""
import base64
import hashlib
import html
import io
import json
import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SITE = REPO / "website"
PAGES = SITE / "zakelijk" / "kaart"
OG_DIR = SITE / "og" / "zakelijk"
CACHE = REPO / ".cache" / "og-zakelijk"
STATE = REPO / ".cache" / "kaart-pages.json"
LIVE = REPO / ".cache" / "live-catalog.json"
FONTS = Path(__file__).resolve().parent / "og" / "fonts"
ICON = SITE / "assets" / "icon.png"

BASE = "https://pasr.nl"
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")
HIDDEN = re.compile(r"apple\s*review", re.I)
RENDER_VERSION = "2-pasr-zegel"          # ophogen als het ontwerp van de OG-afbeelding verandert: dan worden ze allemaal opnieuw gemaakt
INK = (23, 22, 42)
APP_STORE = "https://apps.apple.com/nl/app/pasr-klantenkaarten/id6829229123"


def esc(s):
    return html.escape(str(s or ""), quote=True)


# ------------------------------------------------------------------------------------------------------------ data
def normalise(b):
    """Een kaart uit share_cards of de directory, of None als hij geen pagina krijgt."""
    if not isinstance(b, dict):
        return None
    cid = str(b.get("card_id") or b.get("id") or "").strip().lower()
    business, name = str(b.get("business_name") or "").strip(), str(b.get("card_name") or b.get("name") or "").strip()
    if not UUID.match(cid) or not business or not name:
        return None
    if any(HIDDEN.search(x) for x in (business, name)):
        return None
    try:
        total = max(2, min(30, int(b.get("stamps_total") or 10)))
    except (TypeError, ValueError):
        total = 10
    color = str(b.get("color") or "")
    text = str(b.get("text_color") or "")
    logo = b.get("logo") if isinstance(b.get("logo"), str) and re.fullmatch(r"(/9j/|iVBORw0KGgo)[A-Za-z0-9+/]+=*", b["logo"]) else None
    site = str(b.get("website") or "").strip()
    if site and not re.match(r"^https?://", site, re.I):
        site = "https://" + site
    if site and not re.fullmatch(r"https?://[A-Za-z0-9.-]+\.[A-Za-z]{2,}(/[^\s\"<>]*)?", site):
        site = ""
    return dict(id=cid, business=business, name=name, city=str(b.get("city") or "").strip(),
                color=color.upper() if HEX.match(color) else "#6A5CFF", text=text.upper() if HEX.match(text) else None,
                total=total, reward=str(b.get("reward") or "").strip(), logo=logo, website=site,
                listed=b.get("listed") is not False, updated_at=b.get("updated_at"))


def load_cards(live=None):
    """(mode, kaarten). mode: 'full' (alle gepubliceerde), 'listed' (alleen vindbare) of None (geen gegevens)."""
    if live is None:
        try:
            live = json.loads(LIVE.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None, []
    if not isinstance(live, dict):
        return None, []
    if isinstance(live.get("share_cards"), list):
        mode, src = "full", live["share_cards"]
    elif isinstance(live.get("businesses"), list):
        mode, src = "listed", [dict(b, listed=True) for b in live["businesses"]]
    else:
        return None, []
    seen, out = set(), []
    for b in src:
        c = normalise(b)
        if c and c["id"] not in seen:
            seen.add(c["id"])
            out.append(c)
    return mode, out


# ------------------------------------------------------------------------------------------------------------ tekst
def title_of(c):
    where = f', {c["city"]}' if c["city"] else ""
    if c["name"].lower() == c["business"].lower():
        return f'Stempelkaart van {c["business"]}{where}'
    return f'{c["name"]} van {c["business"]}{where}'


def description_of(c):
    where = f' in {c["city"]}' if c["city"] else ""
    reward = f'krijg je {c["reward"]}' if c["reward"] else "krijg je een beloning"
    text = f'Spaar digitaal stempels bij {c["business"]}{where}: bij {c["total"]} stempels {reward}.'
    long_tail = text + " Gratis met Pasr op je iPhone, Android of in je browser."
    return long_tail if len(long_tail) <= 160 else text + " Gratis met Pasr."


def alt_of(c):
    return f'Stempelkaart {c["name"]} van {c["business"]}: {c["total"]} stempels' + (f' voor {c["reward"]}' if c["reward"] else "")


# ------------------------------------------------------------------------------------------------------------ pagina
def mix(hex_colour, to, part):
    v = [int(hex_colour[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x * (1 - part) + to * part):02x}" for x in v)


def luminance(hex_colour):
    def ch(x):
        x /= 255
        return x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4
    r, g, b = (int(hex_colour[i:i + 2], 16) for i in (1, 3, 5))
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def is_ink(c):
    """Donkere tekst op de kaart? Tekstkleur van de zaak als die er is, anders op contrast (zoals zakelijk.js)."""
    if c["text"] == "#000000":
        return True
    if c["text"] == "#FFFFFF":
        return False
    return luminance(c["color"]) > 0.45


STAMP_SVG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5 10 17 19 7"/></svg>'
GIFT_SVG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="8" width="18" height="13" rx="2"/><path d="M12 8v13M3 12h18M12 8S10.5 3 7.5 4.5 9 8 12 8zm0 0s1.5-5 4.5-3.5S15 8 12 8z"/></svg>'


def stamp_card_html(c):
    """Dezelfde kaart als stampCard() in zakelijk.js (zonder stempels), zodat de pagina zonder JS al klopt."""
    total = c["total"]
    cols = total if total <= 5 else 5 if total <= 10 else 6 if total <= 12 else 7 if total <= 21 else 8
    mono = "".join((w[:1] for w in c["name"].split()[:2])).upper() or "?"
    stamps = "".join(f'<span class="sc-stamp{" gift" if i == total - 1 else ""}" style="--i:{i}">{GIFT_SVG if i == total - 1 else ""}</span>'
                     for i in range(total))
    bg = f'linear-gradient(135deg, {mix(c["color"], 255, .16)}, {c["color"]} 55%, {mix(c["color"], 0, .22)})'
    logo = (f'<img src="data:image/{"jpeg" if c["logo"].startswith("/9j/") else "png"};base64,{c["logo"]}" alt="">'
            if c["logo"] else esc(mono))
    biz = " · ".join(x for x in (c["business"], c["city"]) if x)
    return (f'<div class="sc{" ink" if is_ink(c) else ""}" style="--c:{c["color"]};background:{bg};--cols:{cols}">'
            f'<div class="sc-head"><span class="sc-logo">{logo}</span><span class="sc-title"><span class="sc-name">{esc(c["name"])}</span>'
            f'<span class="sc-biz">{esc(biz)}</span></span><span class="sc-kind">Stempelkaart</span></div>'
            f'<div class="sc-stamps" role="img" aria-label="0 van {total} stempels">{stamps}</div>'
            f'<div class="sc-reward"><span>{esc(c["reward"])}</span><span>{total} stempels</span></div></div>')


def json_ld(c, url, og):
    biz = {"@type": "LocalBusiness", "@id": url + "#zaak", "name": c["business"], "image": og}
    if c["city"]:
        biz["address"] = {"@type": "PostalAddress", "addressLocality": c["city"], "addressCountry": "NL"}
    if c["website"]:
        biz["url"] = c["website"]
    offer = {"@type": "Offer", "name": c["name"], "url": url,
             "description": f'Digitale stempelkaart: bij {c["total"]} stempels {c["reward"] or "een beloning"}.',
             "offeredBy": {"@id": url + "#zaak"}}
    biz["makesOffer"] = offer
    page = {"@type": "WebPage", "@id": url, "url": url, "name": title_of(c), "description": description_of(c),
            "inLanguage": "nl-NL", "primaryImageOfPage": {"@type": "ImageObject", "url": og, "width": 1200, "height": 630},
            "about": {"@id": url + "#zaak"}, "isPartOf": {"@type": "WebSite", "name": "Pasr", "url": BASE + "/"}}
    data = {"@context": "https://schema.org", "@graph": [page, biz]}
    return json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")


def add_badge(card_id):
    """De knop "Voeg toe aan Pasr" (pasr.nl/add/k/<id>), zwart in licht en wit in donker thema."""
    import make_add
    return make_add.badge_pair("k", card_id)


def page_html(c):
    import make_zakelijk as mz
    url = f'{BASE}/zakelijk/kaart/{c["id"]}/'
    og = f'{BASE}/og/zakelijk/{c["id"]}.png'
    title, desc, alt = esc(title_of(c) + " | Pasr"), esc(description_of(c)), esc(alt_of(c))
    robots = "index, follow" if c["listed"] else "noindex, follow"
    where = f' in {esc(c["city"])}' if c["city"] else ""
    reward = f': {esc(c["reward"])}' if c["reward"] else ""
    return f'''<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="apple-itunes-app" content="app-id={mz.PASR_APP_ID}, app-argument={url}">
  <title>{title}</title>
  <meta name="description" content="{desc}">
  <meta name="robots" content="{robots}">
  <link rel="canonical" href="{url}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Pasr">
  <meta property="og:url" content="{url}">
  <meta property="og:title" content="{esc(title_of(c))}">
  <meta property="og:description" content="{desc}">
  <meta property="og:image" content="{og}">
  <meta property="og:image:secure_url" content="{og}">
  <meta property="og:image:type" content="image/png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="{alt}">
  <meta property="og:locale" content="nl_NL">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="{esc(title_of(c))}">
  <meta name="twitter:description" content="{desc}">
  <meta name="twitter:image" content="{og}">
  <meta name="twitter:image:alt" content="{alt}">
  <meta name="theme-color" content="#F4F3FF">
  <link rel="icon" type="image/png" href="/assets/favicon.png">
  <link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
  <link rel="manifest" href="/site.webmanifest">
  <script type="application/ld+json">{json_ld(c, url, og)}</script>
  <script src="/assets/consent.js" defer></script>
  <link rel="stylesheet" href="/assets/style.css">
  <link rel="stylesheet" href="/assets/zakelijk.css">
  <link rel="stylesheet" href="/assets/catalog-hub.css">
</head>
<body data-page="zk-join">
{mz.header()}
  <main class="wrap zk-join" id="zk-join" data-card="{c["id"]}" aria-live="polite">
    <span class="zk-kicker">Stempelkaart</span>
    <h1>{esc(c["name"])}</h1>
    <p>Spaar stempels bij {esc(c["business"])}{where}. Bij {c["total"]} stempels{reward}.</p>
    {stamp_card_html(c)}
    <div class="actions"><a class="btn btn-primary" href="pasr://zakelijk#{c["id"]}">Open in Pasr</a><a class="btn btn-ghost" href="{APP_STORE}" rel="noopener">Pasr voor iPhone</a><a class="btn btn-ghost" href="/android/">Pasr voor Android</a></div>
  </main>
  <div class="wrap pasr-add-row pasr-add-join">{add_badge(c["id"])}<small>Heb je Pasr al? Met deze knop zet je de stempelkaart meteen in de app.</small></div>
{mz.FOOTER}
  <script src="/assets/account-config.js"></script>
  <script src="/assets/vendor/qrcode.js"></script>
  <script src="/assets/zakelijk.js"></script>
</body>
</html>
'''


# ------------------------------------------------------------------------------------------------------------ OG-afbeelding
def card_hash(c):
    keys = ("id", "business", "name", "city", "color", "text", "total", "reward", "logo")
    raw = json.dumps([RENDER_VERSION] + [c.get(k) for k in keys], ensure_ascii=False)
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


_FONTS = {}


def font(kind, size, weight):
    from PIL import ImageFont
    key = (kind, size, weight)
    if key not in _FONTS:
        if kind == "display":
            f = ImageFont.truetype(str(FONTS / "BricolageGrotesque.ttf"), size)
            f.set_variation_by_axes([min(96, max(12, size // 2)), weight, 100])   # opsz, wght, wdth
        else:
            f = ImageFont.truetype(str(FONTS / "Figtree.ttf"), size)
            f.set_variation_by_axes([weight])
        _FONTS[key] = f
    return _FONTS[key]


def fit(draw, text, f, width):
    """Tekst inkorten met … tot hij past."""
    if draw.textlength(text, font=f) <= width:
        return text
    while text and draw.textlength(text + "…", font=f) > width:
        text = text[:-1]
    return text.rstrip() + "…"


def wrap(draw, text, f, width, lines):
    words, out, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if draw.textlength(t, font=f) <= width or not cur:
            cur = t
        else:
            out.append(cur)
            cur = w
    if cur:
        out.append(cur)
    if len(out) > lines:
        out = out[:lines]
        out[-1] = fit(draw, out[-1] + " …", f, width)
    return [fit(draw, line, f, width) for line in out]


def rgb(hex_colour):
    return tuple(int(hex_colour[i:i + 2], 16) for i in (1, 3, 5))


from functools import lru_cache


@lru_cache(maxsize=32)
def pasr_stamp_mask(size):
    """Rasterize the exact traced Pasr seal from website/assets/pasr-stamp.svg.

    The SVG is also used by the website, iOS and Android. XOR preserves its
    nested holes, so letters and the check show the card's own brand colour.
    """
    from PIL import Image, ImageChops, ImageDraw
    source = (SITE / "assets" / "pasr-stamp.svg").read_text(encoding="utf-8")
    match = re.search(r'<path[^>]* d="([^"]+)"', source)
    if not match:
        raise RuntimeError("Officiële Pasr-stempel ontbreekt")
    aa, w, h = 4, 131, 135
    large = max(4, size * aa)
    mask = Image.new("1", (large, large), 0)
    for contour in re.findall(r"M([^Z]+)Z", match.group(1)):
        points = [(int(x) / w * large, int(y) / h * large)
                  for x, y in re.findall(r"([0-9]+),([0-9]+)", contour)]
        if len(points) < 3:
            continue
        layer = Image.new("1", (large, large), 0)
        ImageDraw.Draw(layer).polygon(points, fill=1)
        mask = ImageChops.logical_xor(mask, layer)
    return mask.convert("L").resize((size, size), Image.Resampling.LANCZOS)


def render_og(c):
    """1200x630 PNG (bytes): de stempelkaart groot links, rechts klein het Pasr-logo met 'Spaar digitaal met Pasr'."""
    from PIL import Image, ImageDraw, ImageFilter
    S = 2                                         # supersampling voor zachte randen
    W, H = 1200 * S, 630 * S
    base = rgb(c["color"])
    paper = (244, 243, 255)
    bg_col = tuple(round(p * 0.9 + b * 0.1) for p, b in zip(paper, base))
    img = Image.new("RGB", (W, H), bg_col)
    d = ImageDraw.Draw(img)
    # zachte cirkel in de kaartkleur achter de kaart
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse((-200 * S, -260 * S, 900 * S, 900 * S), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(120 * S))
    img.paste(Image.new("RGB", (W, H), tuple(round(p * 0.7 + b * 0.3) for p, b in zip(paper, base))), (0, 0), glow)

    # kaart: 780 x 492 (1.586), verticaal in het midden
    cw, ch = 780 * S, 492 * S
    cx, cy = 56 * S, (H - ch) // 2
    r = 40 * S
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((cx + 10 * S, cy + 34 * S, cx + cw - 10 * S, cy + ch + 20 * S), r, fill=120)
    shadow = shadow.filter(ImageFilter.GaussianBlur(26 * S))
    img.paste(Image.new("RGB", (W, H), tuple(round(x * 0.35) for x in base)), (0, 0), shadow)

    light, dark = rgb(mix(c["color"], 255, .16)), rgb(mix(c["color"], 0, .22))
    gw, gh = cw // 8, ch // 8                                  # klein rekenen en vergroten: het verloop is zacht
    grad = Image.new("RGB", (gw, gh))
    gp = grad.load()
    for y in range(gh):
        for x in range(gw):
            t = (x / (gw - 1) + y / (gh - 1)) / 2                 # 135 graden
            if t < .55:
                a, b, k = light, base, t / .55
            else:
                a, b, k = base, dark, (t - .55) / .45
            gp[x, y] = tuple(round(u + (v - u) * k) for u, v in zip(a, b))
    grad = grad.resize((cw, ch), Image.BILINEAR)
    mask = Image.new("L", (cw, ch), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, cw - 1, ch - 1), r, fill=255)
    img.paste(grad, (cx, cy), mask)

    ink = is_ink(c)
    fg = INK if ink else (255, 255, 255)
    soft = tuple(round(f * .8 + b * .2) for f, b in zip(fg, base))
    pad = 40 * S
    # logo of monogram
    ls = 96 * S
    lx, ly = cx + pad, cy + pad
    tile = Image.new("L", (ls, ls), 0)
    ImageDraw.Draw(tile).rounded_rectangle((0, 0, ls - 1, ls - 1), 24 * S, fill=255)
    if c["logo"]:
        try:
            logo = Image.open(io.BytesIO(base64.b64decode(c["logo"]))).convert("RGBA")
            plate = Image.new("RGBA", (ls, ls), (255, 255, 255, 255))
            logo.thumbnail((ls - 12 * S, ls - 12 * S), Image.LANCZOS)
            plate.alpha_composite(logo, ((ls - logo.width) // 2, (ls - logo.height) // 2))
            img.paste(plate.convert("RGB"), (lx, ly), tile)
        except Exception:  # noqa: BLE001 - kapot logo: monogram
            c = dict(c, logo=None)
    if not c["logo"]:
        over = Image.new("RGB", (ls, ls), tuple(round(b * .78 + f * .22) for b, f in zip(base, (255, 255, 255) if not ink else INK)))
        img.paste(over, (lx, ly), tile)
        mono = "".join(w[:1] for w in c["name"].split()[:2]).upper() or "?"
        f = font("display", 40 * S, 800)
        d.text((lx + ls / 2, ly + ls / 2), mono, font=f, fill=fg, anchor="mm")
    # kaartnaam, zaak · plaats, "Stempelkaart"
    kind_f = font("body", 22 * S, 700)
    kind_w = d.textlength("Stempelkaart", font=kind_f)
    tx = lx + ls + 24 * S
    tw = cx + cw - pad - kind_w - 24 * S - tx
    d.text((cx + cw - pad, ly + 8 * S), "Stempelkaart", font=kind_f, fill=soft, anchor="ra")
    for size_name in (46, 42, 38, 34):                      # lange naam: eerst kleiner, pas dan inkorten
        nf = font("display", size_name * S, 700)
        if d.textlength(c["name"], font=nf) <= tw:
            break
    d.text((tx, ly + 6 * S + (46 - size_name) * S // 2), fit(d, c["name"], nf, tw), font=nf, fill=fg)
    biz = " · ".join(x for x in (c["business"], c["city"]) if x)
    d.text((tx, ly + 62 * S), fit(d, biz, font("body", 26 * S, 600), tw + kind_w), font=font("body", 26 * S, 600), fill=soft)
    # vakjes: een paar gevuld als voorbeeld, het laatste vakje met een cadeautje
    total = c["total"]
    cols = total if total <= 5 else 5 if total <= 10 else 6 if total <= 12 else 7 if total <= 21 else 8
    rows = -(-total // cols)
    filled = max(1, min(total - 1, round(total * 0.4)))
    area_top, area_bottom = ly + ls + 26 * S, cy + ch - pad - 50 * S
    gap = 18 * S
    size = min((cw - 2 * pad - (cols - 1) * gap) // cols, (area_bottom - area_top - (rows - 1) * gap) // rows, 82 * S)
    grid_w = cols * size + (cols - 1) * gap
    gx = cx + (cw - grid_w) // 2
    gy = area_top + (area_bottom - area_top - (rows * size + (rows - 1) * gap)) // 2
    on_fill = INK if ink else (255, 255, 255)
    on_mark = (255, 255, 255) if ink else base
    line = tuple(round(b * .45 + f * .55) for b, f in zip(base, fg)) if not ink else tuple(round(b * .65 + f * .35) for b, f in zip(base, INK))
    bw = max(2, round(size * 0.045))
    for i in range(total):
        row, col = divmod(i, cols)
        in_row = min(cols, total - row * cols)               # laatste rij (niet vol) in het midden
        x0 = gx + (cols - in_row) * (size + gap) // 2 + col * (size + gap)
        y0 = gy + row * (size + gap)
        box = (x0, y0, x0 + size, y0 + size)
        if i < filled:
            # Brandkleur komt vanzelf tevoorschijn door de uitsparingen in de zegel.
            img.paste(on_fill, (x0, y0), pasr_stamp_mask(size))
        elif i == total - 1:
            d.ellipse(box, outline=line, width=bw)
            k = size * .55 / 24
            ox, oy = x0 + size * .225, y0 + size * .225
            w2 = max(2, round(size * .05))
            d.rounded_rectangle((ox + 3 * k, oy + 8 * k, ox + 21 * k, oy + 21 * k), radius=2 * k, outline=line, width=w2)
            d.line(((ox + 12 * k, oy + 8 * k), (ox + 12 * k, oy + 21 * k)), fill=line, width=w2)
            d.line(((ox + 3 * k, oy + 12 * k), (ox + 21 * k, oy + 12 * k)), fill=line, width=w2)
            d.arc((ox + 6 * k, oy + 3.5 * k, ox + 12 * k, oy + 8.5 * k), 150, 360, fill=line, width=w2)
            d.arc((ox + 12 * k, oy + 3.5 * k, ox + 18 * k, oy + 8.5 * k), 180, 30, fill=line, width=w2)
        else:   # gestippelde rand, zoals op de kaart
            n = 22
            for s in range(n):
                a0 = s * 360 / n
                d.arc(box, a0, a0 + 360 / n * .55, fill=line, width=bw)
    # beloning en aantal
    rf = font("body", 28 * S, 700)
    right = f"{total} stempels"
    rw = d.textlength(right, font=rf)
    by = cy + ch - pad
    d.text((cx + pad, by), fit(d, c["reward"], rf, cw - 2 * pad - rw - 30 * S), font=rf, fill=fg, anchor="ls")
    d.text((cx + cw - pad, by), right, font=rf, fill=soft, anchor="rs")

    # rechts: Pasr
    px = (56 + 780 + 44) * S
    pw = W - px - 50 * S
    icon = Image.open(ICON).convert("RGBA").resize((84 * S, 84 * S), Image.LANCZOS)
    im = Image.new("L", icon.size, 0)
    ImageDraw.Draw(im).rounded_rectangle((0, 0, icon.width - 1, icon.height - 1), 20 * S, fill=255)
    top = 150 * S
    img.paste(icon.convert("RGB"), (px, top), im)
    d.text((px + 100 * S, top + 42 * S), "pasr", font=font("display", 52 * S, 800), fill=INK, anchor="lm")
    y = top + 124 * S
    for ln in wrap(d, "Spaar digitaal met Pasr", font("display", 38 * S, 800), pw, 3):
        d.text((px, y), ln, font=font("display", 38 * S, 800), fill=INK)
        y += 46 * S
    y += 14 * S
    for ln in wrap(d, "Gratis op je iPhone, Android of in je browser", font("body", 22 * S, 600), pw, 3):
        d.text((px, y), ln, font=font("body", 22 * S, 600), fill=(75, 73, 102))
        y += 30 * S
    d.text((px, H - 150 * S), "pasr.nl", font=font("body", 24 * S, 700), fill=(74, 60, 224))

    out = img.resize((1200, 630), Image.LANCZOS)
    buf = io.BytesIO()
    out.save(buf, "PNG", optimize=True)
    data = buf.getvalue()
    if len(data) > 290_000:   # te groot (foto-logo): naar 256 kleuren
        buf = io.BytesIO()
        out.quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save(buf, "PNG", optimize=True)
        data = buf.getvalue()
    return data


def og_png(c):
    """De OG-afbeelding uit de cache als de kaart niet veranderd is, anders opnieuw maken."""
    h = card_hash(c)
    cached = CACHE / f'{c["id"]}.{h}.png'
    if cached.exists():
        return cached.read_bytes(), False
    data = render_og(c)
    CACHE.mkdir(parents=True, exist_ok=True)
    for old in CACHE.glob(f'{c["id"]}.*.png'):
        old.unlink()
    cached.write_bytes(data)
    return data, True


# ------------------------------------------------------------------------------------------------------------ bouwen
def build(live=None):
    mode, cards = load_cards(live)
    if mode is None:
        print("Deelpagina's stempelkaarten: geen live gegevens, niets veranderd.")
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text(json.dumps({"mode": None}), encoding="utf-8")
        return {"mode": None, "pages": 0}
    OG_DIR.mkdir(parents=True, exist_ok=True)
    keep, rendered = set(), 0
    for c in cards:
        out = PAGES / c["id"]
        out.mkdir(parents=True, exist_ok=True)
        (out / "index.html").write_text(page_html(c), encoding="utf-8")
        data, new = og_png(c)
        (OG_DIR / f'{c["id"]}.png').write_bytes(data)
        rendered += new
        keep.add(c["id"])
    # weg: pagina's en afbeeldingen van kaarten die niet meer gepubliceerd zijn (alleen als we de volledige lijst hebben)
    removed = 0
    if mode == "full":
        for d in PAGES.iterdir():
            if d.is_dir() and UUID.match(d.name) and d.name not in keep:
                shutil.rmtree(d)
                removed += 1
        for f in OG_DIR.glob("*.png"):
            if UUID.match(f.stem) and f.stem not in keep:
                f.unlink()
        for f in CACHE.glob("*.png") if CACHE.exists() else []:
            if f.name.split(".")[0] not in keep:
                f.unlink()
    STATE.write_text(json.dumps({"mode": mode, "pages": len(keep)}), encoding="utf-8")
    listed = sum(1 for c in cards if c["listed"])
    print(f"Deelpagina's stempelkaarten ({mode}): {len(keep)} pagina's ({listed} vindbaar, {len(keep) - listed} noindex), "
          f"{rendered} OG-afbeelding(en) opnieuw gemaakt, {removed} weggehaald.")
    return {"mode": mode, "pages": len(keep), "rendered": rendered, "removed": removed}


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        # python3 tools/make_kaart_pages.py --preview <map> < kaarten.json : alleen PNG's maken, niets in website/
        dest = Path(sys.argv[2])
        dest.mkdir(parents=True, exist_ok=True)
        for b in json.load(sys.stdin):
            c = normalise(b)
            if c:
                (dest / f'kaart-og-{b.get("slug") or c["id"]}.png').write_bytes(render_og(c))
        sys.exit(0)
    build()
