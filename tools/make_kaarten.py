#!/usr/bin/env python3
"""Maakt website/kaarten/index.html: alle kaarten die Pasr kent, om te bekijken en te doorzoeken.
De lijst en de aantallen komen uit de repo (tools/store_catalog.py). In de browser vraagt de pagina daarna de live
lijst op (pasr_store_index, zonder logo's; logo's van nieuwe of gewijzigde winkels los via pasr_store_logos, kaartontwerpen
van cadeaukaarten via pasr_store_covers): winkels die
in het beheer zijn bijgekomen verschijnen erbij, catalogus-winkels die (nog) niet gepubliceerd zijn verdwijnen.
Kaarten met een gids (tools/make_gids.py) linken naar hun gidspagina. Lukt dat niet, dan blijft de gegenereerde lijst staan.
Logo's worden verkleind naar website/assets/kaarten/<domain>.png; kaartontwerpen (supabase/catalog/covers.json) komen in
website/assets/covers/<id>.jpg en vullen de hele kaart.
Wordt aangeroepen door tools/make_website.py; los: python3 tools/make_kaarten.py"""
import html
import io
import json
import re
import sys
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import store_catalog as sc

REPO = Path(__file__).resolve().parent.parent
ROOT = REPO / "website"
LOGO_OUT = ROOT / "assets" / "kaarten"
URL = "https://pasr.nl/kaarten/"
APP_STORE = "https://apps.apple.com/nl/app/pasr-klantenkaarten/id6829229123"
MONTHS = ["januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus", "september", "oktober", "november", "december"]

KIND_LABEL = {"loyalty": ("klantenkaart", "klantenkaarten", "Klantenkaarten"),
              "voucher": ("cadeaukaart of voucher", "cadeaukaarten en vouchers", "Cadeaukaarten en vouchers")}


def esc(s):
    return html.escape(str(s), quote=True)


def fold(s):
    """Voor zoeken en sorteren: kleine letters, zonder accenten."""
    return unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()


def sort_key(name):
    return re.sub(r"[^a-z0-9 ]+", "", fold(name)).strip()


def is_light(hex_colour):
    r, g, b = (int(hex_colour[i:i + 2], 16) for i in (1, 3, 5))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b > 160


def account_config():
    """De openbare adres en publishable key van de Pasr-database (staan ook in de app en op /account/)."""
    src = (REPO / "App" / "Account" / "AccountService.swift").read_text(encoding="utf-8")
    url = re.search(r'static let url = "([^"]*)"', src)
    key = re.search(r'static let publishableKey = "([^"]*)"', src)
    return (url.group(1) if url else ""), (key.group(1) if key else "")


def web_logos(cards):
    """Verkleint de logo's (in een vak van 240 x 112 px, vierkante iconen 112 x 112) en geeft domain -> (w, h)."""
    from PIL import Image
    LOGO_OUT.mkdir(parents=True, exist_ok=True)
    sizes, done = {}, set()
    for c in cards:
        d = c["domain"]
        if c["logo"] is None or d in done:
            continue
        done.add(d)
        data = c["logo"].read_bytes() if isinstance(c["logo"], Path) else c["logo"]
        img = Image.open(io.BytesIO(data))
        img = img.convert("RGBA")
        opaque = bool(c["style"] and c["style"]["opaque"])
        box = (112, 112) if opaque else (240, 112)
        img.thumbnail(box, Image.LANCZOS)
        out = io.BytesIO()
        img.save(out, "PNG", optimize=True)
        small = io.BytesIO()   # 256 kleuren (met alfa): ongeveer een derde van de grootte
        img.quantize(colors=256, method=Image.FASTOCTREE).save(small, "PNG", optimize=True)
        if len(small.getvalue()) < len(out.getvalue()):
            out = small
        target = LOGO_OUT / f"{d}.png"
        if not target.exists() or target.read_bytes() != out.getvalue():
            target.write_bytes(out.getvalue())
        sizes[d] = img.size
    # logo's van winkels die er niet meer in staan opruimen
    for f in LOGO_OUT.glob("*.png"):
        if f.stem not in done:
            f.unlink()
    return sizes


COVERS = REPO / "supabase" / "catalog" / "covers.json"
COVER_OUT = ROOT / "assets" / "covers"


def load_covers():
    """Alle kaartontwerpen: covers.json plus covers_<deel>.json in dezelfde map (eerste bestand wint)."""
    data = {}
    for path in sorted(COVERS.parent.glob("covers*.json")):
        for k, v in json.loads(path.read_text(encoding="utf-8")).items():
            data.setdefault(k, v)
    live = sc.live_catalog()
    if live:   # kaartontwerpen uit het beheer gaan voor
        data.update({k: v for k, v in (live.get("covers") or {}).items() if isinstance(v, str) and v})
    return data


def web_covers():
    """Kaartontwerpen van cadeaukaarten (supabase/catalog/covers*.json, gemaakt met tools/make_covers.py) als
    website/assets/covers/<id>.jpg (of .png). Geeft id -> bestandsnaam. Ontwerpen die er niet meer in staan gaan weg."""
    import base64
    data = load_covers()
    COVER_OUT.mkdir(parents=True, exist_ok=True)
    names = {}
    for sid, b64 in data.items():
        if not re.fullmatch(r"[a-z0-9-]{2,40}", sid):
            continue
        raw = base64.b64decode(b64)
        name = f"{sid}.png" if raw[:4] == b"\x89PNG" else f"{sid}.jpg"
        target = COVER_OUT / name
        if not target.exists() or target.read_bytes() != raw:
            target.write_bytes(raw)
        names[sid] = name
    for f in COVER_OUT.iterdir():
        if f.name not in names.values():
            f.unlink()
    return names


def cover_names():
    """id -> bestandsnaam van de kaartontwerpen die al in website/assets/covers/ staan (zonder iets te schrijven)."""
    data = load_covers()
    return {sid: (f"{sid}.png" if b64.startswith("iVBOR") else f"{sid}.jpg") for sid, b64 in data.items()}


def cover_img(c, lazy=True):
    """<img> met het kaartontwerp (vult de hele kaart); leeg als deze cadeaukaart er (in de repo) geen heeft."""
    name = cover_names().get(c["id"]) if c["kind"] == "voucher" else None
    if not name:
        return ""
    lazy_attr = ' loading="lazy"' if lazy else ""
    return (f'<img class="kc-cover" src="/assets/covers/{esc(name)}" alt="" width="640" height="404"'
            f'{lazy_attr} decoding="async">')


GIFT = ('<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 10h16v10H4zM3 7h18v3H3zM12 7v13M12 7c-1.5-3-5-3-5-1s3 1 5 1c2 0 5 1 5-1s-3.5-2-5 1" '
        'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>')


def tile(c, sizes, guide_links=None):
    st = c["style"] or {}
    ink = " ink-dark" if is_light(c["card"]) else ""
    q = " ".join(dict.fromkeys(fold(x) for x in [c["name"], *c["aliases"], c["domain"]]))
    if c["domain"] in sizes:
        w, h = sizes[c["domain"]]
        cls = "kc-logo" + (" opaque" if st.get("opaque") else "") + (" plate" if st.get("plate") else "")
        plate = f' style="--plate:{st["plate"]}"' if st.get("plate") else ""
        face = (f'<span class="{cls}"{plate}><img src="/assets/kaarten/{esc(c["domain"])}.png" alt="" width="{w}" height="{h}" '
                f'loading="lazy" decoding="async"></span>')
    else:
        face = f'<span class="kc-word" aria-hidden="true">{esc(c["name"])}</span>'
    saldo = ""
    if c["kind"] == "voucher" and c["balance"]:
        saldo = (f'<a class="kc-saldo" href="{esc(c["balance"])}" target="_blank" rel="noopener nofollow" '
                 f'aria-label="Saldo-check van {esc(c["name"])} (opent de site van de uitgever)">{GIFT}Saldo-check</a>')
    src = ' data-src="catalogus"' if c["source"] == "catalogus" else ""
    cover = cover_img(c)
    return (f'<li class="kc" data-id="{esc(c["id"])}"{src} data-c="{esc(c["category"])}" data-q="{esc(q)}">'
            f'<div class="kc-card{ink}{" has-cover" if cover else ""}" style="background:{c["card"]}">{cover}{face}{saldo}</div>'
            + (f'<a class="kc-name" href="{guide_links[c["id"]]}" aria-label="Gids: {esc(c["name"])}">{esc(c["name"])}<span class="kc-gids" aria-hidden="true"> · gids</span></a></li>'
               if guide_links and c["id"] in guide_links else f'<span class="kc-name">{esc(c["name"])}</span></li>'))


def build(write=True):
    cards = sc.all_cards()
    n = sc.counts(cards)
    sizes = web_logos(cards) if write else {}
    if write:
        web_covers()
    now = datetime.now(timezone.utc).replace(microsecond=0)
    day = f"{now.day} {MONTHS[now.month - 1]} {now.year}"
    url, key = account_config()
    import make_gids   # hier: make_gids gebruikt zelf hulpjes uit dit bestand
    guide_links = make_gids.links()
    lists, cat_opts = {}, {}
    for kind in ("loyalty", "voucher"):
        items = sorted((c for c in cards if c["kind"] == kind), key=lambda c: (sort_key(c["name"]), c["id"]))
        lists[kind] = "\n".join("          " + tile(c, sizes, guide_links) for c in items)
        cats = sorted({c["category"] for c in items}, key=fold)
        cat_opts[kind] = cats
    all_cats = sorted({c["category"] for c in cards}, key=fold)
    options = "".join(f'<option value="{esc(c)}">{esc(c)}</option>' for c in all_cats)
    # kaartontwerpen die als bestand op de site staan (ook voor winkels die pas live in de lijst komen)
    config = {"url": url, "key": key, "cats": cat_opts, "built": now.isoformat(), "covers": cover_names()}

    title = "Alle klantenkaarten en cadeaukaarten in Pasr"
    desc = (f"Zoek je winkel: Pasr kent {n['loyalty']} klantenkaarten en {n['voucher']} cadeaukaarten en vouchers, "
            f"met logo en kleur. Mis je er een? Vraag hem aan in de app.")
    og_alt = "Kaarten van Nederlandse winkels in hun eigen kleur met logo, naast de tekst: Welke kaarten kent Pasr?"
    ld = {"@context": "https://schema.org", "@graph": [
        {"@type": "CollectionPage", "@id": URL + "#page", "url": URL, "name": title, "description": desc, "inLanguage": "nl-NL",
         "isPartOf": {"@type": "WebSite", "@id": "https://pasr.nl/#site", "url": "https://pasr.nl/", "name": "Pasr"},
         "dateModified": now.date().isoformat(),
         "about": {"@type": "MobileApplication", "name": "Pasr", "operatingSystem": "iOS 17, iPadOS 17, watchOS 10",
                   "applicationCategory": "LifestyleApplication", "url": "https://pasr.nl/",
                   "offers": {"@type": "Offer", "price": "0", "priceCurrency": "EUR"}},
         "mainEntity": {"@type": "ItemList", "name": "Kaarten in Pasr", "numberOfItems": n["total"], "itemListOrder": "https://schema.org/ItemListOrderAscending"}},
        {"@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "Pasr", "item": "https://pasr.nl/"},
            {"@type": "ListItem", "position": 2, "name": "Alle kaarten", "item": URL}]}]}

    badge = (f'<a class="store-badge" href="{APP_STORE}?itscg=30200&amp;itsct=apps_box_badge&amp;mttnsubad=6829229123" rel="noopener">'
             '<img src="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/nl-nl?releaseDate=1794096000" '
             'alt="Download in de App Store" width="246" height="82" loading="lazy"></a>'
             ' <a class="android-badge" href="/android/" aria-label="Download voor Android"><svg viewBox="0 0 24 24" aria-hidden="true">'
             '<rect x="6" y="2.5" width="12" height="19" rx="2.6" fill="none" stroke="currentColor" stroke-width="1.7"/>'
             '<path d="M12 7v7m-3-3 3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>'
             '<path d="M10.5 18.2h3" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>'
             '<span><small>Download voor</small>Android</span></a>')
    store_icon = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
                  '<path d="M4 9l1.5-5h13L20 9M4 9h16v11H4zM4 9a2.7 2.7 0 0 0 5.3 0 2.7 2.7 0 0 0 5.4 0 2.7 2.7 0 0 0 5.3 0M10 20v-5h4v5"/></svg>')

    page = f'''<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="apple-itunes-app" content="app-id=6829229123">
  <meta name="color-scheme" content="light dark">
  <title>{title} | Pasr</title>
  <meta name="description" content="{esc(desc)}">
  <link rel="canonical" href="{URL}">
  <meta name="robots" content="index, follow, max-image-preview:large">
  <link rel="alternate" hreflang="nl-NL" href="{URL}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Pasr">
  <meta property="og:url" content="{URL}">
  <meta property="og:title" content="Welke kaarten kent Pasr?">
  <meta property="og:description" content="{esc(desc)}">
  <meta property="og:image" content="https://pasr.nl/og/kaarten.png">
  <meta property="og:image:type" content="image/png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="{og_alt}">
  <meta property="og:locale" content="nl_NL">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="Welke kaarten kent Pasr?">
  <meta name="twitter:description" content="{esc(desc)}">
  <meta name="twitter:image" content="https://pasr.nl/og/kaarten.png">
  <meta name="twitter:image:alt" content="{og_alt}">
  <meta name="theme-color" content="#F4F3FF" media="(prefers-color-scheme: light)">
  <meta name="theme-color" content="#111020" media="(prefers-color-scheme: dark)">
  <link rel="manifest" href="/site.webmanifest">
  <link rel="icon" type="image/png" sizes="64x64" href="/assets/favicon.png">
  <link rel="apple-touch-icon" sizes="180x180" href="/assets/apple-touch-icon.png">
  <link rel="preconnect" href="{esc(url)}" crossorigin>
  <script src="/assets/consent.js" defer></script>
  <link rel="stylesheet" href="/assets/style.css">
  <link rel="stylesheet" href="/assets/kaarten.css">
  <script>document.documentElement.classList.add('js')</script>
  <script type="application/ld+json">{json.dumps(ld, ensure_ascii=False, separators=(",", ":"))}</script>
</head>
<body class="cards-page">
  <a class="skip" href="#lijst">Naar de kaarten</a>
  <header class="wrap nav">
    <a class="brand" href="/"><img src="/assets/icon.png" alt="" width="36" height="36"><span>pasr</span></a>
    <nav aria-label="Hoofdmenu">
      <ul>
        <li><a href="/#functies">Functies</a></li>
        <li><a href="/kaarten/" aria-current="page">Kaarten</a></li>
        <li><a href="/#delen">Delen</a></li>
        <li><a href="/cadeaubon/">Cadeaubons</a></li>
        <li class="hide-sm"><a href="/#faq">Vragen</a></li>
        <li><a href="/support/">Support</a></li>
      </ul>
    </nav>
  </header>

  <main>
    <div class="wrap kh">
      <p class="pill">Alle kaarten</p>
      <h1>Welke kaarten kent Pasr?</h1>
      <p class="lead">Zoek je winkel. Elke kaart staat in Pasr met het eigen logo en de eigen kleur, klaar om te scannen.</p>
      <dl class="kh-stats">
        <div><dt>Klantenkaarten</dt><dd data-count="loyalty">{n["loyalty"]}</dd></div>
        <div><dt>Cadeaukaarten en vouchers</dt><dd data-count="voucher">{n["voucher"]}</dd></div>
      </dl>
      <p class="kh-date">Bijgewerkt op <time datetime="{now.date().isoformat()}">{day}</time>. Nieuwe winkels komen erbij zonder app-update.</p>
    </div>

    <section class="wrap kl" id="lijst" aria-label="Kaarten">
      <form class="kf" role="search" aria-label="Kaarten zoeken en filteren" onsubmit="return false">
        <div class="kf-search">
          <label for="kf-q" class="sr-only">Zoek een winkel</label>
          <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M16 16l4.5 4.5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
          <input id="kf-q" type="search" placeholder="Zoek een winkel, bijvoorbeeld bonuskaart" autocomplete="off" autocapitalize="off" spellcheck="false" enterkeyhint="search">
        </div>
        <div class="kf-row">
          <fieldset class="kf-kind">
            <legend class="sr-only">Soort kaart</legend>
            <input type="radio" name="kind" id="kf-loyalty" value="loyalty" checked><label for="kf-loyalty">Klantenkaarten</label>
            <input type="radio" name="kind" id="kf-voucher" value="voucher"><label for="kf-voucher">Cadeaukaarten<span class="kf-long"> en vouchers</span></label>
          </fieldset>
          <div class="kf-cat">
            <label for="kf-cat">Categorie</label>
            <select id="kf-cat"><option value="">Alle categorieën</option>{options}</select>
          </div>
        </div>
        <p class="kf-status" id="kf-status" aria-live="polite"></p>
        <button type="button" class="kf-other" id="kf-other" hidden></button>
      </form>

      <div class="kg-block" data-kind="loyalty">
        <h2 class="kg-title">Klantenkaarten <span>({n["loyalty"]})</span></h2>
        <p class="kg-note">Bij de bekendste spaarprogramma&rsquo;s staat een gids: tik op een naam met <b>gids</b>, of bekijk de <a href="/klantenkaart/">Klantenkaart-gids</a>.</p>
        <ul class="kg" role="list">
{lists["loyalty"]}
        </ul>
      </div>
      <div class="kg-block" data-kind="voucher">
        <h2 class="kg-title">Cadeaukaarten en vouchers <span>({n["voucher"]})</span></h2>
        <p class="kg-note">Met <b>Saldo-check</b> kijk je het tegoed na op de site van de uitgever; in Pasr staat je kaartnummer dan klaar om te plakken. Tik op de naam voor de <a href="/cadeaubon/">Cadeaubon-gids</a>: geldigheid, inwisselen en voorwaarden.</p>
        <ul class="kg" role="list">
{lists["voucher"]}
        </ul>
      </div>
      <p class="kg-empty" id="kg-empty" hidden>Geen kaart gevonden. Je kunt hem in Pasr toch toevoegen met <b>Andere winkel</b>, of hem aanvragen.</p>
    </section>

    <section class="wrap km" id="mis-je-een-winkel" aria-labelledby="km-title">
      <div class="km-box">
        <span class="km-icon">{store_icon}</span>
        <div>
          <h2 id="km-title">Mis je een winkel?</h2>
          <p>Vraag hem aan in de app: tik op <b>+</b> › <b>Kaart toevoegen</b> › <b>Mis je een winkel?</b> (met een gratis Pasr-account). Dat kan ook voor cadeaukaarten en vouchers. Wij maken de kaart met het juiste logo en de juiste kleur en zetten hem erbij zonder app-update; je krijgt een melding zodra hij erin staat.</p>
          <p>Tot die tijd voeg je je kaart gewoon toe met <b>Andere winkel</b>: geef hem een naam en een kleur en scan de barcode.</p>
          <div class="actions">{badge}</div>
        </div>
      </div>
    </section>
  </main>

  <footer>
    <div class="wrap">
      <span>&copy; {now.year} Pasr · Merknamen en logo&rsquo;s zijn van de betreffende winkels; Pasr is niet aan hen verbonden. Winkel en wil je je logo anders of niet in Pasr? Mail <a href="mailto:support@pasr.nl?subject=Logo%20in%20Pasr">support@pasr.nl</a>.</span>
      <nav aria-label="Voettekst">
        <a href="/cadeaubon/">Cadeaubon-gids</a>
        <a href="/klantenkaart/">Klantenkaart-gids</a>
        <a href="/privacy/">Privacy</a>
        <a href="/privacy/#cookies" data-consent-open>Cookie-instellingen</a>
        <a href="/support/">Support</a>
      </nav>
    </div>
  </footer>
  <script type="application/json" id="kaarten-config">{json.dumps(config, ensure_ascii=False)}</script>
  <script src="/assets/kaarten.js" defer></script>
</body>
</html>
'''
    if write:
        out = ROOT / "kaarten"
        out.mkdir(parents=True, exist_ok=True)
        (out / "index.html").write_text(page, encoding="utf-8")
    return n


if __name__ == "__main__":
    n = build()
    print(f"Wrote website/kaarten/index.html: {n['loyalty']} klantenkaarten, {n['voucher']} cadeaukaarten/vouchers")
