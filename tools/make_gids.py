#!/usr/bin/env python3
"""Gidsen op pasr.nl, uit supabase/catalog/guides.json (dezelfde gids die de app via de catalogus leest; alleen officiële
bronnen, onbekend = weggelaten) en tools/store_catalog.py (naam, kleur, logo, saldo-pagina):
- Cadeaubon-gids: /cadeaubon/ en per cadeaukaart /cadeaubon/<slug>/ (saldo-check, geldigheid, inwisselen, voorwaarden);
- Klantenkaart-gids: /klantenkaart/ en per spaarprogramma /klantenkaart/<slug>/ (zo spaar je, voordelen, programmapagina).
Alleen kaarten met een gids krijgen een pagina. slug() geeft het adres; make_kaarten linkt er vanaf de tegels naartoe.
Wordt aangeroepen door tools/make_website.py (na make_kaarten, dat de logo's in website/assets/kaarten/ zet).
Los: python3 tools/make_gids.py"""
import json
import re
import shutil
import sys
import unicodedata
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import store_catalog as sc
from make_kaarten import esc, fold, is_light, sort_key, APP_STORE, MONTHS

REPO = Path(__file__).resolve().parent.parent
ROOT = REPO / "website"
GUIDES = REPO / "supabase" / "catalog" / "guides.json"

KINDS = {
    "voucher": dict(dir="cadeaubon", label="Cadeaubon-gids", noun="cadeaukaart", nouns="cadeaukaarten",
                    og="https://pasr.nl/og/cadeaubon.png",
                    og_alt="Cadeaukaarten van Nederlandse winkels in hun eigen kleur met logo, naast de tekst: Cadeaubon-gids"),
    "loyalty": dict(dir="klantenkaart", label="Klantenkaart-gids", noun="klantenkaart", nouns="klantenkaarten",
                    og="https://pasr.nl/og/klantenkaart.png",
                    og_alt="Klantenkaarten van Nederlandse winkels in hun eigen kleur met logo, naast de tekst: Klantenkaart-gids"),
}


def slug(card):
    """Leesbaar adres uit de naam: "Action cadeaukaart" -> "action-cadeaukaart", "Albert Heijn" -> "albert-heijn"."""
    t = unicodedata.normalize("NFKD", card["name"]).encode("ascii", "ignore").decode().lower().replace("&", " en ")
    return re.sub(r"[^a-z0-9]+", "-", t).strip("-")[:60] or card["id"]


def guides():
    return json.loads(GUIDES.read_text(encoding="utf-8"))


def load(kind, all_guides=None):
    """Kaarten van deze soort met een gids, op naam gesorteerd: [(card, guide)], met card["slug"] uniek."""
    g = all_guides if all_guides is not None else guides()
    cards = [c for c in sc.all_cards() if c["kind"] == kind and c["id"] in g]
    cards.sort(key=lambda c: (sort_key(c["name"]), c["id"]))
    seen = set()
    for c in cards:
        s = slug(c)
        if s in seen:
            s = f"{s}-{c['id']}"
        seen.add(s)
        c["slug"] = s
    return [(c, g[c["id"]]) for c in cards]


def links():
    """id -> /<map>/<slug>/ voor alle kaarten met een gids (voor de tegels op /kaarten/)."""
    g = guides()
    return {c["id"]: f"/{KINDS[k]['dir']}/{c['slug']}/" for k in KINDS for c, _ in load(k, g)}


def nl_date(iso):
    d = date.fromisoformat(iso)
    return f"{d.day} {MONTHS[d.month - 1]} {d.year}"


def logo_size(domain):
    p = ROOT / "assets" / "kaarten" / f"{domain}.png"
    if not p.exists():
        return None
    from PIL import Image
    with Image.open(p) as im:
        return im.size


def card_face(c, big=False):
    """De kaart zoals in de app: merkkleur met logo (zelfde opmaak als de tegels op /kaarten/)."""
    st = c["style"] or {}
    ink = " ink-dark" if is_light(c["card"]) else ""
    size = logo_size(c["domain"])
    if size:
        cls = "kc-logo" + (" opaque" if st.get("opaque") else "") + (" plate" if st.get("plate") else "")
        plate = f' style="--plate:{st["plate"]}"' if st.get("plate") else ""
        lazy = "" if big else ' loading="lazy"'
        face = (f'<span class="{cls}"{plate}><img src="/assets/kaarten/{esc(c["domain"])}.png" alt="" width="{size[0]}" '
                f'height="{size[1]}"{lazy} decoding="async"></span>')
    else:
        face = f'<span class="kc-word" aria-hidden="true">{esc(c["name"])}</span>'
    return f'<div class="kc-card{ink}{" gd-card" if big else ""}" style="background:{c["card"]}">{face}</div>'


def faq_items(c, g, kind):
    """Vragen en antwoorden uit de gids zelf; alleen waar we iets weten."""
    n, out = c["name"], []
    if kind == "loyalty":
        if g.get("earn"):
            out.append((f"Hoe spaar je met {n}?", g["earn"]))
        if g.get("perks"):
            out.append((f"Wat zijn de voordelen van {n}?", g["perks"]))
        if g.get("how"):
            out.append((f"Hoe kom ik aan de klantenkaart van {n}?", g["how"]))
        out.append((f"Kan ik mijn {n}-kaart in Pasr bewaren?",
                    f"Ja. Kies {n} bij Kaart toevoegen en scan de barcode van je pas of uit de app. Pasr toont de kaart met logo en kleur, "
                    "op je iPhone, Apple Watch en als widget, en zet hem klaar als je bij de winkel bent."))
        return out
    if g.get("validity"):
        out.append((f"Hoe lang is de {n} geldig?",
                    f"{g['validity']}. Bron: de site van de uitgever, gecontroleerd op {nl_date(g['checked'])}." if g.get("checked") else g["validity"] + "."))
    if "online" in g or "store" in g:
        parts = []
        if "online" in g:
            parts.append(f"Online inwisselen: {'ja' if g['online'] else 'nee'}.")
        if "store" in g:
            parts.append(f"In de winkel: {'ja' if g['store'] else 'nee'}.")
        out.append((f"Kan ik de {n} online of in de winkel gebruiken?", " ".join(parts + ([g["how"]] if g.get("how") else []))))
    elif g.get("how"):
        out.append((f"Hoe wissel ik de {n} in?", g["how"]))
    if c.get("balance"):
        out.append((f"Hoe check ik het saldo van de {n}?",
                    "Op de saldo-pagina van de uitgever, met het kaartnummer (en soms een pincode) van je kaart. In Pasr open je die pagina met "
                    "Saldo checken; je kaartnummer staat dan klaar om te plakken."))
    if g.get("shipping"):
        out.append((f"Wat kost het verzenden van een {n}?", g["shipping"]))
    return out


def head(title, desc, url, ld, og_title, k):
    return f'''<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="apple-itunes-app" content="app-id=6829229123">
  <meta name="color-scheme" content="light dark">
  <title>{esc(title)} | Pasr</title>
  <meta name="description" content="{esc(desc)}">
  <link rel="canonical" href="{url}">
  <meta name="robots" content="index, follow, max-image-preview:large">
  <link rel="alternate" hreflang="nl-NL" href="{url}">
  <meta property="og:type" content="article">
  <meta property="og:site_name" content="Pasr">
  <meta property="og:url" content="{url}">
  <meta property="og:title" content="{esc(og_title)}">
  <meta property="og:description" content="{esc(desc)}">
  <meta property="og:image" content="{k["og"]}">
  <meta property="og:image:type" content="image/png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="{k["og_alt"]}">
  <meta property="og:locale" content="nl_NL">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="{esc(og_title)}">
  <meta name="twitter:description" content="{esc(desc)}">
  <meta name="twitter:image" content="{k["og"]}">
  <meta name="twitter:image:alt" content="{k["og_alt"]}">
  <meta name="theme-color" content="#F4F3FF" media="(prefers-color-scheme: light)">
  <meta name="theme-color" content="#111020" media="(prefers-color-scheme: dark)">
  <link rel="manifest" href="/site.webmanifest">
  <link rel="icon" type="image/png" sizes="64x64" href="/assets/favicon.png">
  <link rel="apple-touch-icon" sizes="180x180" href="/assets/apple-touch-icon.png">
  <script src="/assets/consent.js" defer></script>
  <link rel="stylesheet" href="/assets/style.css">
  <link rel="stylesheet" href="/assets/kaarten.css">
  <link rel="stylesheet" href="/assets/gids.css">
  <script>document.documentElement.classList.add('js')</script>
  <script type="application/ld+json">{json.dumps(ld, ensure_ascii=False, separators=(",", ":"))}</script>
</head>'''


def nav(current):
    cur = lambda d: ' aria-current="page"' if current == d else ""
    return f'''  <header class="wrap nav">
    <a class="brand" href="/"><img src="/assets/icon.png" alt="" width="36" height="36"><span>pasr</span></a>
    <nav aria-label="Hoofdmenu">
      <ul>
        <li><a href="/#functies">Functies</a></li>
        <li><a href="/kaarten/">Kaarten</a></li>
        <li><a href="/#delen">Delen</a></li>
        <li><a href="/cadeaubon/"{cur("cadeaubon")}>Cadeaubons</a></li>
        <li class="hide-sm"><a href="/klantenkaart/"{cur("klantenkaart")}>Klantenkaarten</a></li>
        <li><a href="/support/">Support</a></li>
      </ul>
    </nav>
  </header>'''


FOOTER = '''  <footer>
    <div class="wrap">
      <span>&copy; {year} Pasr · Merknamen en logo&rsquo;s zijn van de betreffende winkels en uitgevers; Pasr is niet aan hen verbonden. Klopt er iets niet? Mail <a href="mailto:support@pasr.nl?subject=Gids">support@pasr.nl</a>.</span>
      <nav aria-label="Voettekst">
        <a href="/kaarten/">Alle kaarten</a>
        <a href="/cadeaubon/">Cadeaubon-gids</a>
        <a href="/klantenkaart/">Klantenkaart-gids</a>
        <a href="/privacy/">Privacy</a>
        <a href="/privacy/#cookies" data-consent-open>Cookie-instellingen</a>
        <a href="/support/">Support</a>
      </nav>
    </div>
  </footer>'''

BADGE = (f'<a class="store-badge" href="{APP_STORE}?itscg=30200&amp;itsct=apps_box_badge&amp;mttnsubad=6829229123" rel="noopener">'
         '<img src="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/nl-nl?releaseDate=1794096000" '
         'alt="Download in de App Store" width="246" height="82" loading="lazy"></a>')

I_EXT = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
I_CHECK = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.2 4.2L19 7" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>'
I_GIFT = '<path d="M4 10h16v10H4zM3 7h18v3H3zM12 7v13M12 7c-1.5-3-5-3-5-1s3 1 5 1c2 0 5 1 5-1s-3.5-2-5 1"/>'
I_CARD = '<path d="M3 7a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2zM3 10h18M7 15h4"/>'


def fact(label, value):
    return f'<div class="gd-fact"><dt>{label}</dt><dd>{value}</dd></div>'


def flag(v):
    return f'<span class="gd-flag yes">{I_CHECK}Ja</span>' if v else '<span class="gd-flag no">Nee</span>'


def ext_link(url, text):
    return (f'<a href="{esc(url)}" target="_blank" rel="noopener nofollow">{text}'
            f'<span class="sr-only"> (opent een andere site)</span></a>')


def panel(pid, title, body):
    return f'''      <section class="gd-panel" id="{pid}" aria-labelledby="{pid}-title">
        <h2 id="{pid}-title">{title}</h2>
        {body}
      </section>'''


def faq_block(faqs, title):
    if not faqs:
        return ""
    items = "\n".join(f'        <details id="vraag-{i + 1}"><summary>{esc(q)}</summary><p>{esc(a)}</p></details>' for i, (q, a) in enumerate(faqs))
    return f'''    <section class="wrap faq-wrap" id="vragen" aria-labelledby="faq-title">
      <h2 id="faq-title">{title}</h2>
      <div class="faq">
{items}
      </div>
    </section>'''


def guide_page(c, g, items, kind, year):
    k = KINDS[kind]
    n, url = c["name"], f"https://pasr.nl/{k['dir']}/{c['slug']}/"
    checked = (f'Gecontroleerd op <time datetime="{g["checked"]}">{nl_date(g["checked"])}</time> op de officiële site van de '
               f'{"uitgever" if kind == "voucher" else "winkel"}. ') if g.get("checked") else ""
    panels = []
    if kind == "voucher":
        facts = []
        if g.get("validity"):
            facts.append(fact("Geldigheid", esc(g["validity"])))
        if "online" in g:
            facts.append(fact("Online inwisselen", flag(g["online"])))
        if "store" in g:
            facts.append(fact("In de winkel", flag(g["store"])))
        if g.get("shipping"):
            facts.append(fact("Verzendkosten", esc(g["shipping"])))
        body = (f'<dl class="gd-facts">{"".join(facts)}</dl>' if facts else "") + (f'<p class="gd-how">{esc(g["how"])}</p>' if g.get("how") else "")
        panels.append(panel("kort", "In het kort", body))
        if c.get("balance"):
            saldo = (f'<p>Kijk het tegoed na op de saldo-pagina van de uitgever. Je hebt het kaartnummer nodig, en vaak ook de pincode.</p>'
                     f'<p><a class="btn gd-btn" href="{esc(c["balance"])}" target="_blank" rel="noopener nofollow">{I_EXT}Saldo checken bij {esc(n)}'
                     f'<span class="sr-only"> (opent de site van de uitgever)</span></a></p>'
                     f'<p class="gd-small">In Pasr tik je bij je kaart op <b>Saldo checken</b>: dezelfde pagina gaat open en je kaartnummer staat klaar om te plakken.</p>')
        else:
            saldo = (f'<p>Pasr kent (nog) geen online saldo-pagina voor de {esc(n)}. In Pasr houd je het tegoed zelf bij: '
                     f'na het tonen van de kaart vraagt Pasr wat je uitgaf.</p>')
        panels.append(panel("saldo", "Saldo checken", saldo))
        terms = f'<p>{ext_link(g["terms_url"], "Voorwaarden en uitleg van de uitgever")}</p>' if g.get("terms_url") else ""
        panels.append(panel("voorwaarden", "Voorwaarden", terms + f'<p class="gd-small">{checked}Voorwaarden kunnen veranderen; bij twijfel geldt wat de uitgever zegt. Klopt er iets niet? Mail <a href="mailto:support@pasr.nl?subject=Gids%20{esc(c["id"])}">support@pasr.nl</a>.</p>'))
        app_title = f"Bewaar je {esc(n)} in Pasr"
        ticks = ["Barcode, pincode en vervaldatum bij de hand, ook op je Apple Watch.",
                 "Na het tonen vraagt Pasr wat je uitgaf: je ziet het tegoed afnemen.",
                 "<b>Nieuw in versie 1.0.2:</b> deze gids bij je kaart in de app, en een herinnering als je nog tegoed hebt."]
        title = f"{n}: saldo, geldigheid en inwisselen"
        h1 = esc(n)
        lead = "Saldo checken, hoe lang hij geldig is en waar je hem inwisselt. Uit de officiële informatie van de uitgever."
        bits = []
        if g.get("validity"):
            bits.append(f"geldigheid ({g['validity'].lower()})")
        if "online" in g or "store" in g:
            bits.append("waar je hem inwisselt")
        if c.get("balance"):
            bits.append("de saldo-check")
        desc = f"{n}: {', '.join(bits) if bits else 'zo wissel je hem in'} en de voorwaarden, van de officiële site. Bewaar je cadeaukaart gratis in Pasr."
        if len(desc) > 165:
            desc = f"{n}: geldigheid, inwisselen, saldo-check en voorwaarden, van de officiële site. Bewaar je cadeaukaart gratis in Pasr."
    else:
        body = ""
        if g.get("earn"):
            body += f'<h3 class="gd-sub">Zo spaar je</h3><p class="gd-how">{esc(g["earn"])}</p>'
        if g.get("perks"):
            body += f'<h3 class="gd-sub">Voordelen</h3><p class="gd-how">{esc(g["perks"])}</p>'
        if g.get("how"):
            body += f'<h3 class="gd-sub">Zo kom je aan de kaart</h3><p>{esc(g["how"])}</p>'
        panels.append(panel("kort", "In het kort", body))
        src = ""
        if g.get("program_url"):
            src += f'<p>{ext_link(g["program_url"], f"Het programma op de site van {esc(n)}")}</p>'
        if g.get("terms_url"):
            src += f'<p>{ext_link(g["terms_url"], "Voorwaarden")}</p>'
        panels.append(panel("bron", "Meer weten", src + f'<p class="gd-small">{checked}Acties en voorwaarden veranderen geregeld; kijk voor de actuele stand op de site van {esc(n)}. Klopt er iets niet? Mail <a href="mailto:support@pasr.nl?subject=Gids%20{esc(c["id"])}">support@pasr.nl</a>.</p>'))
        app_title = f"Je {esc(n)}-kaart altijd bij de hand"
        ticks = ["Met logo en kleur in Pasr; één tik en de barcode staat op volle helderheid.",
                 "Op je Apple Watch, als widget en klaar zodra je bij de winkel bent.",
                 "<b>Nieuw in versie 1.0.2:</b> deze gids bij je kaart in de app, en tot 4 foto's per pas met je eigen voorkant."]
        title = f"Haal meer uit je {n}-kaart"
        h1 = f"Haal meer uit je {esc(n)}-kaart"
        lead = "Zo spaar je, dit zijn de voordelen en zo zet je de kaart in Pasr. Uit de officiële informatie van de winkel."
        desc = f"{n}: zo spaar je en dit zijn de voordelen van de klantenkaart, van de officiële site. Bewaar je {n}-kaart gratis in Pasr."
        if len(desc) > 165:
            desc = f"{n}: zo spaar je en de voordelen van de klantenkaart, van de officiële site. Gratis in Pasr."
    faqs = faq_items(c, g, kind)
    idx = next(i for i, (x, _) in enumerate(items) if x["id"] == c["id"])
    others = [items[(idx + j) % len(items)][0] for j in range(1, 7) if len(items) > j]
    others_html = "".join(f'<li><a href="/{k["dir"]}/{o["slug"]}/">{card_face(o)}<span>{esc(o["name"])}</span></a></li>' for o in others)
    ticks_html = "".join(f"<li>{I_CHECK}<span>{t}</span></li>" for t in ticks)

    ld = {"@context": "https://schema.org", "@graph": [
        {"@type": "WebPage", "@id": url + "#page", "url": url, "name": title, "description": desc, "inLanguage": "nl-NL",
         "isPartOf": {"@type": "WebSite", "@id": "https://pasr.nl/#site", "url": "https://pasr.nl/", "name": "Pasr"},
         **({"dateModified": g["checked"], "lastReviewed": g["checked"]} if g.get("checked") else {}),
         "about": {"@type": "Thing", "name": n, **({"sameAs": f"https://{c['domain']}/"} if c["domain"] else {})}},
        {"@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "Pasr", "item": "https://pasr.nl/"},
            {"@type": "ListItem", "position": 2, "name": k["label"], "item": f"https://pasr.nl/{k['dir']}/"},
            {"@type": "ListItem", "position": 3, "name": n, "item": url}]}]}
    if faqs:
        ld["@graph"].append({"@type": "FAQPage", "mainEntity": [
            {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in faqs]})

    return f'''{head(title, desc, url, ld, title, k)}
<body class="cards-page gids-page">
  <a class="skip" href="#inhoud">Naar de gids</a>
{nav(None)}

  <main id="inhoud">
    <nav class="wrap gd-crumbs" aria-label="Kruimelpad">
      <ol><li><a href="/">Pasr</a></li><li><a href="/{k["dir"]}/">{k["label"]}</a></li><li aria-current="page">{esc(n)}</li></ol>
    </nav>
    <div class="wrap gd-hero">
      {card_face(c, big=True)}
      <div>
        <p class="pill{" loy" if kind == "loyalty" else ""}">{k["label"]}</p>
        <h1>{h1}</h1>
        <p class="lead">{lead}</p>
      </div>
    </div>

    <div class="wrap gd-body">
{chr(10).join(panels)}
      <aside class="gd-app" aria-labelledby="app-title">
        <h2 id="app-title">{app_title}</h2>
        <ul class="ticks">{ticks_html}</ul>
        <div class="actions">{BADGE}</div>
        <p class="gd-small">Gratis, zonder reclame en zonder account.</p>
      </aside>
    </div>

{faq_block(faqs, f"Vragen over {esc(n)}")}

    <section class="wrap gd-more" aria-labelledby="meer-title">
      <h2 id="meer-title">Andere {k["nouns"]}</h2>
      <ul class="gd-grid" role="list">{others_html}</ul>
      <p><a class="btn btn-ghost" href="/{k["dir"]}/">Alle {len(items)} gidsen</a></p>
    </section>
  </main>

{FOOTER.format(year=year)}
</body>
</html>
'''


def overview(items, kind, year, today):
    k = KINDS[kind]
    url = f"https://pasr.nl/{k['dir']}/"
    if kind == "voucher":
        title = "Cadeaubon-gids: saldo, geldigheid en inwisselen"
        h1 = "Hoe lang is je cadeaukaart geldig?"
        lead = "Per cadeaukaart: geldigheid, online of in de winkel inwisselen, de saldo-check en de voorwaarden. Rechtstreeks van de uitgever."
        desc = (f"Hoe lang is je cadeaukaart geldig, kun je hem online gebruiken en waar check je het saldo? "
                f"De gids voor {len(items)} cadeaukaarten, uit de officiële voorwaarden van de uitgevers.")
        og_title = "Cadeaubon-gids: hoe lang is je cadeaukaart geldig?"
        other = ('<p class="gd-switch">Op zoek naar spaarprogramma&rsquo;s? Bekijk de <a href="/klantenkaart/">Klantenkaart-gids</a>.</p>')
        box_title, box_text = "Nooit meer tegoed laten verlopen", (
            "Bewaar je cadeaukaarten in Pasr: saldo, pincode en vervaldatum bij de hand, en het tegoed neemt af met elke uitgave. "
            "<b>Nieuw in versie 1.0.2:</b> de gids bij je kaart in de app en een herinnering als je nog tegoed hebt, ook zonder vervaldatum.")
        icon = I_GIFT
        placeholder = "Zoek een cadeaukaart, bijvoorbeeld VVV"
    else:
        title = "Klantenkaart-gids: zo spaar je bij je winkel"
        h1 = "Haal meer uit je klantenkaarten"
        lead = "Per spaarprogramma: zo spaar je, wat het je oplevert en waar je meer leest. Rechtstreeks van de winkel."
        desc = (f"Bonuskaart, Extra's, Lidl Plus, Air Miles en meer: zo spaar je en dit zijn de voordelen van {len(items)} klantenkaarten, "
                f"uit de officiële informatie van de winkels.")
        og_title = "Klantenkaart-gids: haal meer uit je klantenkaarten"
        other = '<p class="gd-switch">Heb je een cadeaukaart? Bekijk de <a href="/cadeaubon/">Cadeaubon-gids</a>.</p>'
        box_title, box_text = "Al je klantenkaarten in één app", (
            "Pasr bewaart je klantenkaarten met logo en kleur, op je iPhone, Apple Watch en als widget. "
            "<b>Nieuw in versie 1.0.2:</b> de gids bij je kaart, kortingscodes, tickets en abonnementen als eigen soort pas, en tot 4 foto's per pas.")
        icon = I_CARD
        placeholder = "Zoek een klantenkaart, bijvoorbeeld Bonus"
    rows = []
    for c, g in items:
        chips = []
        if kind == "voucher":
            if "online" in g:
                chips.append(f'<span class="gd-chip {"yes" if g["online"] else "no"}">Online {"ja" if g["online"] else "nee"}</span>')
            if "store" in g:
                chips.append(f'<span class="gd-chip {"yes" if g["store"] else "no"}">Winkel {"ja" if g["store"] else "nee"}</span>')
            if c.get("balance"):
                chips.append('<span class="gd-chip saldo">Saldo-check</span>')
            sub = esc(g.get("validity") or "Geldigheid: zie de uitgever")
        else:
            sub = esc((g.get("earn") or g.get("perks") or "").split(". ")[0].rstrip(".") + ".") if (g.get("earn") or g.get("perks")) else ""
        q = " ".join(dict.fromkeys(fold(x) for x in [c["name"], *c["aliases"], c["domain"]]))
        chips_html = f'<span class="gd-chips">{"".join(chips)}</span>' if chips else ""
        rows.append(f'          <li class="gd-item" data-q="{esc(q)}"><a href="/{k["dir"]}/{c["slug"]}/">{card_face(c)}<span class="gd-item-t"><b>{esc(c["name"])}</b>'
                    f'<span class="gd-valid">{sub}</span>{chips_html}</span></a></li>')
    faqs = [
        ("Waar komt de informatie in de gids vandaan?",
         f"Alleen van de officiële website van de {'uitgever van de cadeaukaart' if kind == 'voucher' else 'winkel of het spaarprogramma'}. "
         "Bij elke kaart staat wanneer we het hebben gecontroleerd en een link naar de bron. Wat we niet officieel konden vinden, laten we weg."),
        (f"Mijn {k['noun']} staat er niet tussen.",
         f"De gids groeit mee met de kaarten in Pasr. Mis je er een, vraag hem dan aan in de app via + › Kaart toevoegen › Mis je een winkel?, of mail support@pasr.nl."),
        ("Staat de gids ook in de app?",
         f"Ja, vanaf versie 1.0.2 zie je de gids bij je {k['noun']} in Pasr."),
    ]
    ld = {"@context": "https://schema.org", "@graph": [
        {"@type": "CollectionPage", "@id": url + "#page", "url": url, "name": title, "description": desc, "inLanguage": "nl-NL",
         "isPartOf": {"@type": "WebSite", "@id": "https://pasr.nl/#site", "url": "https://pasr.nl/", "name": "Pasr"},
         "dateModified": today,
         "mainEntity": {"@type": "ItemList", "name": k["label"], "numberOfItems": len(items),
                        "itemListElement": [{"@type": "ListItem", "position": i + 1, "name": c["name"], "url": f"{url}{c['slug']}/"}
                                            for i, (c, _) in enumerate(items)]}},
        {"@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "Pasr", "item": "https://pasr.nl/"},
            {"@type": "ListItem", "position": 2, "name": k["label"], "item": url}]},
        {"@type": "FAQPage", "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in faqs]}]}
    return f'''{head(title, desc, url, ld, og_title, k)}
<body class="cards-page gids-page">
  <a class="skip" href="#gidsen">Naar de gidsen</a>
{nav(k["dir"])}

  <main>
    <div class="wrap kh">
      <p class="pill{" loy" if kind == "loyalty" else ""}">{k["label"]}</p>
      <h1>{h1}</h1>
      <p class="lead">{lead}</p>
      <p class="kh-date">{len(items)} {k["nouns"]} · bijgewerkt op <time datetime="{today}">{nl_date(today)}</time></p>
    </div>

    <section class="wrap" id="gidsen" aria-label="{k["label"]}">
      <form class="kf gd-search" role="search" aria-label="Gids zoeken" onsubmit="return false">
        <div class="kf-search">
          <label for="gd-q" class="sr-only">Zoek een {k["noun"]}</label>
          <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M16 16l4.5 4.5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
          <input id="gd-q" type="search" placeholder="{placeholder}" autocomplete="off" autocapitalize="off" spellcheck="false" enterkeyhint="search">
        </div>
        <p class="kf-status" id="gd-status" aria-live="polite"></p>
      </form>
      <ul class="gd-list" role="list">
{chr(10).join(rows)}
      </ul>
      <p class="kg-empty" id="gd-empty" hidden>Geen gids gevonden. Op <a href="/kaarten/">alle kaarten</a> staan ook kaarten zonder gids.</p>
      {other}
    </section>

{faq_block(faqs, "Over de gids")}

    <section class="wrap km" aria-labelledby="km-title">
      <div class="km-box">
        <span class="km-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{icon}</svg></span>
        <div>
          <h2 id="km-title">{box_title}</h2>
          <p>{box_text}</p>
          <div class="actions">{BADGE}</div>
        </div>
      </div>
    </section>
  </main>

{FOOTER.format(year=year)}
  <script>
  (function () {{
    var q = document.getElementById('gd-q'), items = document.querySelectorAll('.gd-item'), status = document.getElementById('gd-status'), empty = document.getElementById('gd-empty');
    function fold(s) {{ return s.normalize('NFKD').replace(/[\\u0300-\\u036f]/g, '').toLowerCase(); }}
    function apply() {{
      var t = fold(q.value.trim()), n = 0;
      for (var i = 0; i < items.length; i++) {{ var hit = !t || items[i].getAttribute('data-q').indexOf(t) !== -1; items[i].hidden = !hit; if (hit) n++; }}
      status.textContent = t ? (n === 1 ? '1 gids' : n + ' gidsen') : '';
      empty.hidden = n !== 0;
    }}
    q.addEventListener('input', apply);
  }})();
  </script>
</body>
</html>
'''


def og_html(items, kind):
    """Bron voor de deelafbeelding /og/<map>.png (tools/og/render.py cadeaubon klantenkaart)."""
    k = KINDS[kind]
    src = (REPO / "tools" / "og" / "kaarten.html").read_text(encoding="utf-8")
    pick = [c for c, _ in items if logo_size(c["domain"])][:18]
    while pick and len(pick) < 18:
        pick = (pick * 2)[:18]
    tiles = "".join(f'<div class="t" style="background:{c["card"]}"><span style=""><img src="../../website/assets/kaarten/{c["domain"]}.png"></span></div>' for c in pick)
    start, end = src.index('<div class="grid">'), src.index('<div class="left">')
    src = src[:start] + f'<div class="grid">{tiles}</div>\n' + src[end:]
    src = src.replace("<h1>Welke kaarten kent Pasr?</h1>", f"<h1>{k['label']}</h1>")
    text = ("Hoe lang is je cadeaukaart geldig, en waar wissel je hem in? Per kaart, van de uitgever." if kind == "voucher"
            else "Zo spaar je en dit levert het op: per klantenkaart, van de winkel zelf.")
    src = src.replace("<p>Klantenkaarten en cadeaukaarten van Nederlandse winkels, met logo en kleur.</p>", f"<p>{text}</p>")
    src = src.replace("pasr.nl/kaarten", f"pasr.nl/{k['dir']}")
    (REPO / "tools" / "og" / f"{k['dir']}.html").write_text(src, encoding="utf-8")


def build():
    all_g = guides()
    year = date.today().year
    out = {}
    for kind, k in KINDS.items():
        items = load(kind, all_g)
        today = max((g["checked"] for _, g in items if g.get("checked")), default=date.today().isoformat())
        d = ROOT / k["dir"]
        keep = {c["slug"] for c, _ in items}
        if d.exists():   # pagina's van kaarten zonder gids (meer) opruimen
            for sub in d.iterdir():
                if sub.is_dir() and sub.name not in keep:
                    shutil.rmtree(sub)
        d.mkdir(parents=True, exist_ok=True)
        (d / "index.html").write_text(overview(items, kind, year, today), encoding="utf-8")
        for c, g in items:
            p = d / c["slug"]
            p.mkdir(exist_ok=True)
            (p / "index.html").write_text(guide_page(c, g, items, kind, year), encoding="utf-8")
        og_html(items, kind)
        out[kind] = items
    return out


if __name__ == "__main__":
    r = build()
    print(f"Wrote website/cadeaubon/ ({len(r['voucher'])} gidsen) en website/klantenkaart/ ({len(r['loyalty'])} gidsen)")
