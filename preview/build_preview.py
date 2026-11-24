#!/usr/bin/env python3
"""Produce a separate, non-indexed Pasr preview at /test/.
The five existing live pages are COPIED, never modified or deleted. We add
a concept hero/navigation on top, and leave all original HTML and animations
below it. This script runs after make_website.py in the normal website workflow.
"""
from __future__ import annotations

import html
import re
import shutil
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "website"
OUT = SITE / "test"
ASSETS = ROOT / "preview"

PAGES = [
    ("home", "", "Homepage", SITE / "index.html"),
    ("kaarten", "kaarten", "Kaartenhub", SITE / "kaarten" / "index.html"),
    ("cadeau", "cadeaubon", "Cadeaukaarten", SITE / "cadeaubon" / "index.html"),
    ("korting", "kortingsbonnen", "Kortingsbonnen", SITE / "kortingsbonnen" / "index.html"),
    ("zakelijk", "zakelijk", "Pasr Zakelijk", SITE / "zakelijk" / "index.html"),
]

def nav(current: str) -> str:
    items = []
    for key, slug, name, _ in PAGES:
        path = "/test/" + (slug + "/" if slug else "")
        attr = ' aria-current="page"' if current == key else ""
        items.append(f'<a href="{path}"{attr}>{html.escape(name)}</a>')
    return '<nav class="pv-tabs" aria-label="Bekijk de nieuwe Pasr-pagina’s">' + "".join(items) + '</nav>'

def cards_visual() -> str:
    return """<div class="pv-cards" aria-label="Voorbeeldkaarten met beweging bij aanwijzen">
      <div class="pv-card c1"><small>KLANTENKAART</small><img loading="lazy" src="/assets/logos/hema.nl.png" alt="HEMA"><span>Alles bij de hand</span></div>
      <div class="pv-card c2"><small>CADEAUKAART</small><img loading="lazy" src="/assets/logos/ah.nl.png" alt="Albert Heijn"><span>Bewaar je kaart</span></div>
      <div class="pv-card c3"><small>PASR</small><b>Al je kaarten</b><span>In één app</span></div>
    </div>"""

def stamps_visual() -> str:
    stamps = "".join('<span class="pv-stamp-dot" aria-hidden="true"></span>' for _ in range(10))
    return f"""<div class="pv-cards">
      <div class="pv-stamp" aria-label="Interactief demonstratievoorbeeld van een digitale stempelkaart">
        <div class="pv-stamp-head">Koffiebar De Hoek <span>Stempelkaart</span></div>
        <div class="pv-stamp-dots" id="pv-stamps">{stamps}</div>
        <div class="pv-stamp-bottom" id="pv-stamp-status" aria-live="polite">6 van 10 stempels · 4 te gaan</div>
      </div>
      <button id="pv-add-stamp" type="button" class="pv-btn pv-stamp-control">Probeer +1 stempel</button>
    </div>"""


def business_platform_visual() -> str:
    """Show loyalty AND coupons AND VIP, with real Pasr stamp artwork and interactions."""
    stamps = "".join('<span class="pv-stamp-dot" aria-hidden="true"></span>' for _ in range(10))
    return f"""<div class="pv-business-demo" aria-label="Interactieve voorbeelden Pasr Zakelijk">
      <div class="pv-demo-switch" role="group" aria-label="Kies een functievoorbeeld">
        <button class="pv-demo-tab" type="button" data-pv-demo="stempel" aria-pressed="true">Stempelkaart</button>
        <button class="pv-demo-tab" type="button" data-pv-demo="coupon" aria-pressed="false">Kortingscoupon</button>
        <button class="pv-demo-tab" type="button" data-pv-demo="vip" aria-pressed="false">VIP &amp; voordeel</button>
      </div>
      <div class="pv-demo-panel" data-pv-panel="stempel">
        <div class="pv-stamp" aria-label="Digitale stempelkaartdemonstratie">
          <div class="pv-stamp-head">Koffiebar De Hoek <span>Stempelkaart</span></div>
          <div class="pv-stamp-dots" id="pv-stamps">{stamps}</div>
          <div class="pv-stamp-bottom" id="pv-stamp-status" aria-live="polite">6 van 10 stempels · 4 te gaan</div>
        </div>
        <button id="pv-add-stamp" type="button" class="pv-btn pv-demo-action">Probeer +1 stempel</button>
      </div>
      <div class="pv-demo-panel" data-pv-panel="coupon" hidden>
        <div class="pv-coupon-visual pv-merchant-coupon">
          <span class="pv-demo-label">VOORBEELD · NIET INWISSELBAAR</span>
          <p>Pasr Zakelijk · eigen kortingscoupon</p>
          <b id="pv-coupon-value">10% korting</b>
          <div class="pv-dash"></div><span class="pv-soft">QR of barcode bij de kassa · beperkt geldig</span>
        </div>
        <button id="pv-change-coupon" type="button" class="pv-btn pv-demo-action">Bekijk een € 5-coupon</button>
      </div>
      <div class="pv-demo-panel" data-pv-panel="vip" hidden>
        <div class="pv-vip-card">
          <span class="pv-demo-label">VOORBEELD · KLANTENBINDING</span>
          <span class="pv-vip-crown" aria-hidden="true">✦</span>
          <strong>VIP Goud</strong>
          <p>25 bezoeken · exclusieve beloning en tijdelijke acties</p>
          <span>Stel voordelen per klantniveau in</span>
        </div>
        <a class="pv-btn pv-demo-action" href="/zakelijk/dashboard/">Bekijk het ondernemersdashboard</a>
      </div>
      <p class="pv-demo-footnote">Interactie is een demonstratie. Er worden geen echte stempels, coupons of VIP-voordelen aangemaakt.</p>
    </div>"""

def business_feature_grid() -> str:
    features = [
        ("Digitale stempelkaarten", "Maak kaarten met eigen kleuren, meerdere beloningen en de officiële Pasr-stempel.", "Stempelkaarten"),
        ("Kortingscoupons", "Stel een vast kortingsbedrag of percentage in, met unieke QR- of barcode.", "Coupons"),
        ("Tijdelijke acties", "Plan dubbele stempels en aanbiedingen met een begin- en einddatum.", "Acties"),
        ("VIP &amp; referrals", "Beloon vaste klanten en geef vriendenbonussen na een geldige aankoop.", "VIP"),
        ("Marketingkalender", "Plan acties en download promotiemateriaal voor je winkel.", "Marketing"),
        ("Vestigingen &amp; medewerkers", "Beheer meerdere locaties en toegang voor je team.", "Beheer"),
        ("Inzichten", "Bekijk stempels, beloningen en terugkerende bezoeken.", "Statistieken"),
        ("Samenwerkingen", "Maak gezamenlijke acties met andere deelnemende ondernemers.", "Samen"),
    ]
    items = "".join(
        '<article class="pv-feature"><small>' + label + '</small><h3>' + title +
        '</h3><p>' + text + '</p></article>'
        for title, text, label in features
    )
    return ('<section class="pv-business-features" id="pv-business-features" aria-label="Alles wat ondernemers met Pasr kunnen doen">'
            '<div class="pv-feature-heading"><div><span class="pv-business-eyebrow">ÉÉN ONDERNEMERSPLATFORM</span>'
            '<h2>Veel meer dan alleen stempelkaarten.</h2></div>'
            '<a href="/zakelijk/dashboard/" class="pv-feature-link">Naar het bestaande dashboard</a></div>'
            '<div class="pv-feature-grid">' + items + '</div></section>')

def coupon_visual() -> str:
    return """<div class="pv-cards"><div class="pv-coupon-visual">
      <span class="pv-show">Voorbeeld, geen echte aanbieding</span>
      <p>Een aanbieding van een deelnemende ondernemer</p>
      <b>10% korting</b><div class="pv-dash"></div>
      <span class="pv-soft">Bewaar de bon in Pasr en toon hem bij de kassa.</span>
    </div></div>"""

def concept(key: str) -> str:
    configs = {
        "home": ("DE NIEUWE PASR-ERVARING", "Al je kaarten.<br>Al je voordeel.",
                 "Ontdek klantenkaarten, cadeaukaarten, stempelkaarten en kortingsbonnen op één overzichtelijke plek. "
                 "Je kassabonnen en alle bestaande appfuncties blijven natuurlijk bestaan.",
                 '<form action="/test/kaarten/" method="get" role="search" data-preview-search>'
                 '<label class="sr-only" for="pv-home-q">Zoek een kaart of winkel</label>'
                 '<input id="pv-home-q" name="q" type="search" placeholder="Zoek Action, HEMA, Albert Heijn…">'
                 '<button class="pv-btn" type="submit">Zoeken</button></form>',
                 cards_visual()),
        "kaarten": ("NIEUWE KAARTENHUB", "Alle kaarten.<br>Eén zoekplek.",
                    "Blader op type kaart of zoek een winkel. De complete Pasr-catalogus en bestaande filters werken hieronder gewoon door.",
                    '<form action="/test/kaarten/" method="get" role="search" data-preview-search>'
                    '<label class="sr-only" for="pv-cards-q">Kaarten zoeken</label>'
                    '<input id="pv-cards-q" name="q" type="search" placeholder="Welk merk of welke kaart zoek je?">'
                    '<button class="pv-btn" type="submit">Zoek kaarten</button></form>',
                    cards_visual()),
        "cadeau": ("CADEAUKAARTEN & SALDO", "Weet wat je kaart<br>nog waard is.",
                   "Doorzoek de bestaande cadeaukaartgids, vind de officiële saldo-checker, geldigheid en inwisselmogelijkheden per uitgever.",
                   '<form action="/test/cadeaubon/" method="get" role="search" data-preview-search>'
                   '<label class="sr-only" for="pv-gift-q">Cadeaukaart zoeken</label>'
                   '<input id="pv-gift-q" name="q" type="search" placeholder="Zoek bijvoorbeeld VVV, bol of Action…">'
                   '<button class="pv-btn" type="submit">Zoek cadeaukaart</button></form>',
                   cards_visual()),
        "korting": ("KORTINGEN & STEMPels".upper(), "Meer voordeel.<br>Minder zoeken.",
                    "Ontdek beschikbare kortingsbonnen en acties van Pasr-ondernemers. "
                    "De echte aanbiedingen en persoonlijke QR-codes blijven afkomstig uit de bestaande backend.",
                    '<a class="pv-btn" href="#pz2Public">Bekijk actuele kortingsbonnen</a>'
                    '<a class="pv-btn alt" href="/test/zakelijk/">Zelf een actie maken</a>',
                    coupon_visual()),
        "zakelijk": ("PASR ZAKELIJK · KLANTENBINDING", "Klantenbinding.<br>Alle tools in één.",
                    "Maak digitale stempelkaarten én kortingscoupons, stel VIP-beloningen en vriendenacties in, "
                    "plan campagnes en ontdek je resultaten. Eén platform voor jouw onderneming.",
                    '<a class="pv-btn" href="/zakelijk/dashboard/#account">Gratis beginnen</a>'
                    '<a class="pv-btn alt" href="#pv-business-features">Ontdek alle functies</a>',
                    business_platform_visual()),
    }
    kicker, heading, description, actions, visual = configs[key]
    extra = {
        "home": [("Kaarten ontdekken","/test/kaarten/"), ("Cadeaukaart-saldo","/test/cadeaubon/"),
                 ("Kortingsbonnen","/test/kortingsbonnen/"),("Voor ondernemers","/test/zakelijk/")],
        "kaarten": [("Klantenkaarten","#lijst"),("Cadeaukaarten","/test/cadeaubon/"),
                    ("Stempelkaarten","#stempelkaarten"),("Kortingsbonnen","/test/kortingsbonnen/")],
        "cadeau": [("Saldo-checkers","#gidsen"),("Alle kaarten","/test/kaarten/"),
                    ("Kortingsbonnen","/test/kortingsbonnen/")],
        "korting": [("Alle kortingsbonnen","#pz2Public"),("Kaartenhub","/test/kaarten/"),
                    ("Voor ondernemers","/test/zakelijk/")],
        "zakelijk": [("Kortingscoupons","#pv-business-features"),("Stempelkaarten","#pv-business-features"),
                    ("VIP & referrals","#pv-business-features"),("Marketing","#pv-business-features"),
                    ("Samenwerkingen","#pv-business-features"),("Dashboard","/zakelijk/dashboard/")],
    }
    pills = "".join(f'<a href="{html.escape(h,quote=True)}">{html.escape(t)}</a>' for t, h in extra[key])
    return f"""<div class="pv-stage" id="preview">
      {nav(key)}
      <section class="pv-shell" aria-label="Nieuwe Pasr-conceptpagina">
        <div class="pv-grid">
          <div class="pv-copy"><span class="pv-kicker">{kicker}</span>
            <h2>{heading}</h2><p>{html.escape(description)}</p>
            <div class="pv-actions">{actions}</div>
          </div>{visual}
        </div>
      </section>
      <p class="pv-note">Interactief concept · de bestaande kaartanimaties, flips, stempels,
      zoekfilters, apps en zakelijke functies staan verderop ongewijzigd op deze pagina.
      De voorbeelden hierboven zijn demonstraties en worden niet opgeslagen.</p>
      {business_feature_grid() if key == "zakelijk" else ""}
      <div class="pv-under"><h3>Wat wil je ontdekken?</h3><div class="pv-pills">{pills}</div></div>
      <div class="pv-original"><strong>Alle bestaande Pasr-functies en animaties</strong>
        <p>Hieronder staat de huidige volledige pagina. Niets is weggehaald of vervangen.</p>
      </div>
    </div>"""

def rewrite_preview_links(document: str) -> str:
    """Only top-level design routes move to /test/; store, support and dashboard
    links preserve their original destination, so there are no broken actions."""
    route_paths = {"/", "/kaarten/", "/cadeaubon/", "/kortingsbonnen/", "/zakelijk/"}
    def replace(match):
        attr, url = match.group(1), match.group(2)
        parts = urlsplit(url)
        if parts.path in route_paths:
            return f'{attr}="/test{url}"'
        return match.group(0)
    return re.sub(r'\b(href)="(/[^"]*)"', replace, document)

def build() -> list[Path]:
    out_files = []
    (OUT / "assets").mkdir(parents=True, exist_ok=True)
    for name in ("pasr-preview.css", "pasr-preview.js"):
        shutil.copy2(ASSETS / name, OUT / "assets" / name)
    for key, slug, _, source in PAGES:
        if not source.is_file():
            raise FileNotFoundError(f"Preview source was not generated: {source}")
        document = source.read_text(encoding="utf-8")
        if '<header' not in document or '</header>' not in document:
            raise RuntimeError(f"No main navigation header found in {source}")
        document = rewrite_preview_links(document)
        # Noindex the preview to prevent duplicate content in search results.
        document = document.replace("</head>", '''
<meta name="robots" content="noindex,nofollow,noarchive">
<link rel="stylesheet" href="/test/assets/pasr-preview.css">
</head>''', 1)
        document = re.sub(r'<body(?=[\s>])', '<body data-pasr-preview="true"', document, count=1)
        notice = ('''<div class="pv-banner" role="status">PASR TESTOMGEVING · Dit is een ontwerpvoorbeeld,
          niet de huidige live website. Bestaande download- en dashboardknoppen openen de echte site.
          <a href="/">Terug naar huidige Pasr</a></div>''')
        document = document.replace('</header>', '</header>\n' + notice + '\n' + concept(key), 1)
        document = document.replace('</body>', '<script defer src="/test/assets/pasr-preview.js"></script>\n</body>', 1)
        target = OUT / slug / "index.html" if slug else OUT / "index.html"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(document, encoding="utf-8")
        out_files.append(target)
        print(f"Pasr concept generated: {target.relative_to(SITE)} ({len(document)} bytes)")
    robots = OUT / "robots.txt"
    robots.write_text("User-agent: *\nDisallow: /\n", encoding="utf-8")
    return out_files

def verify() -> None:
    for key, slug, _, _ in PAGES:
        file = OUT / slug / "index.html" if slug else OUT / "index.html"
        document = file.read_text(encoding="utf-8")
        assert 'name="robots" content="noindex,nofollow,noarchive"' in document, str(file)
        assert 'data-pasr-preview="true"' in document, str(file)
        assert 'pv-stage' in document and 'pv-original' in document, str(file)
        assert document.count('class="pv-tabs"') == 1, str(file)
        assert '/test/assets/pasr-preview.css' in document, str(file)
        assert '/test/assets/pasr-preview.js' in document, str(file)
        assert '/assets/style.css' in document, "Original styling missing"
        assert "data-pasr-preview" in document
        if key == "home":
            assert 'fv-flip' in document or 'marquee-track' in document, "Original animations missing"
        if key == "zakelijk":
            assert "zv-designer" in document or "zv-scan" in document, "Original business demo missing"
            assert '/zakelijk/dashboard/' in document, "Actual dashboard link lost"
            for feature in ("Kortingscoupons", "Digitale stempelkaarten", "VIP", "Marketingkalender",
                            "Vestigingen", "Inzichten", "Samenwerkingen"):
                assert feature in document, "Business preview missing " + feature
            for mode in ("stempel", "coupon", "vip"):
                assert 'data-pv-demo="' + mode + '"' in document, "Missing merchant demo " + mode
        if key == "kaarten":
            assert 'id="kf-q"' in document, "Original catalog filters missing"
        if key == "cadeau":
            assert 'id="gd-q"' in document, "Original gift card search missing"
        if key == "korting":
            assert 'id="pz2Public"' in document, "Public coupon content missing"
    for p in ("pasr-preview.css", "pasr-preview.js"):
        assert (OUT / "assets" / p).stat().st_size > 200
    print("PASR PREVIEW VALIDATION PASSED: five isolated pages; all original interactive content preserved")

if __name__ == "__main__":
    build()
    verify()
