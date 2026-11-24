"""Herbruikbare navigatie voor alle Pasr kaarten, cadeaukaarten en kortingsbonnen.
Houdt de bestaande bestemmingen, zoekindex en canonical-URL's intact."""
from html import escape

SECTIONS = (
    ("kaarten", "/kaarten/", "Alle kaarten", "layers"),
    ("klantenkaart", "/klantenkaart/", "Klantenkaarten", "credit-card"),
    ("cadeaubon", "/cadeaubon/", "Cadeaukaarten", "gift"),
    ("stempelkaarten", "/stempelkaarten/", "Stempelkaarten", "stamp"),
    ("saldo-checken", "/saldo-checken/", "Saldo checken", "wallet"),
    ("kortingsbonnen", "/kortingsbonnen/", "Kortingsbonnen", "ticket"),
)

def site_nav(active="kaarten"):
    links = [
        ("home", "/#ontdekken", "Ontdekken"),
        ("kaarten", "/kaarten/", "Klantenkaarten"),
        ("cadeaubon", "/cadeaubon/", "Cadeaukaarten"),
        ("stempelkaarten", "/stempelkaarten/", "Stempelkaarten"),
        ("kortingsbonnen", "/kortingsbonnen/", "Kortingsbonnen"),
        ("saldo-checken", "/saldo-checken/", "Saldo checken"),
        ("functies", "/#functies", "Functies"),
        ("overstappen", "/#overstappen", "Overstappen"),
        ("support", "/support/", "Support"),
        ("zakelijk", "/zakelijk/", "Voor ondernemers"),
    ]
    items = []
    for key, href, label in links:
        current = ' aria-current="page"' if key == active and key != "home" else ""
        cls = ' class="ch-business-link"' if key == "zakelijk" else ""
        items.append(f'<li><a href="{href}"{current}{cls}>{label}</a></li>')
    return f'''<header class="wrap nav ch-site-nav">
  <a class="brand" href="/" aria-label="Pasr homepage"><img src="/assets/icon.png" width="36" height="36" alt=""><span>pasr</span></a>
  <details class="ch-menu"><summary aria-label="Hoofdmenu openen of sluiten"><svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path class="ch-hamburger" d="M4 6h16M4 12h16M4 18h16"/><path class="ch-close" d="m6 6 12 12M18 6 6 18"/></svg><span>Menu</span></summary>
  <nav aria-label="Mobiel hoofdmenu"><ul>{''.join(items)}</ul></nav></details>
  <nav class="ch-desktop-nav" aria-label="Hoofdmenu"><ul>{''.join(items)}</ul></nav>
</header>'''

def section_nav(active="kaarten"):
    links = []
    for value, href, title, _ in SECTIONS:
        attrs = ' aria-current="page"' if active == value else ""
        links.append(f'<a href="{href}"{attrs}>{escape(title)}</a>')
    return ('<nav class="wrap ch-sections" aria-label="Soorten kaarten en voordelen">'
            + ''.join(links) + '</nav>')


def real_card_art(active):
    """Public catalog artwork only; never use a consumer's card number or balance."""
    import store_catalog as sc
    from make_gids import card_face
    from make_kaarten import stamp_tile
    if active == "kortingsbonnen":
        # The public coupon renderer supplies the actual currently published offer.
        return '<div class="ch-live-coupon" id="ch-live-coupon" aria-live="polite"><img src="/assets/icon.png" alt="" width="48" height="48"><strong>Actuele acties</strong><small>Ontdek aanbiedingen van deelnemende ondernemers</small></div>'
    if active == "stempelkaarten":
        stamps = sc.stamp_cards()[:2]
        if not stamps:
            return '<div class="ch-empty-art"><img src="/assets/pasr-stamp.svg" alt="" width="72" height="72"><strong>Spaar lokaal met Pasr</strong><small>Bekijk de gepubliceerde stempelkaarten hieronder.</small></div>'
        return ''.join(f'<div class="ch-real-face ch-real-{i+1}"><ul class="ch-stamp-art">{stamp_tile(b)}</ul></div>' for i,b in enumerate(stamps))
    kind = "voucher" if active in ("cadeaubon", "saldo-checken") else "loyalty"
    cards = [c for c in sc.all_cards() if c["kind"] == kind and (active != "saldo-checken" or c.get("balance"))]
    wanted = ("hema", "bol") if kind == "voucher" else ("jumbo", "albert heijn")
    picked = []
    for brand in wanted:
        candidates = [c for c in cards if brand in c["name"].casefold() or brand in (c.get("domain") or "").casefold()]
        if candidates:
            picked.append(candidates[0])
    for c in cards:
        if len(picked) >= 2:
            break
        if c not in picked:
            picked.append(c)
    art = ''.join(f'<div class="ch-real-face ch-real-{i+1}">{card_face(c, big=True)}</div>' for i,c in enumerate(picked))
    if kind == "voucher" and picked:
        art += '<div class="ch-balance-demo"><small>Voorbeeld van tegoed</small><strong>€ 50,00</strong></div>'
    return art or '<div class="ch-empty-art"><strong>Ontdek je kaarten</strong></div>'

def hero(active="kaarten", count=None):
    """Gedeelde hero met een directe cataloguszoekactie en herkenbare kaartcategorieën."""
    title = {
        "kaarten": "Al je kaarten &amp; voordelen op één plek",
        "klantenkaart": "Vind jouw klantenkaart",
        "cadeaubon": "Alles over jouw cadeaukaart.",
        "kortingsbonnen": "Ontdek tijdelijke kortingsbonnen",
        "stempelkaarten": "Spaar bij jouw favoriete ondernemers",
        "saldo-checken": "Hoeveel staat er op jouw cadeaukaart?",
    }.get(active, "Kaarten &amp; voordelen")
    subtitle = {
        "kaarten": "Zoek in de kaartencatalogus van Pasr en ontdek actuele acties van ondernemers.",
        "klantenkaart": "Zoek een winkel en ontdek hoe je spaart en welke voordelen er zijn.",
        "cadeaubon": "Controleer je saldo, ontdek waar je jouw kaart kunt besteden en voorkom dat je tegoed verloopt.",
        "kortingsbonnen": "Bewaar een persoonlijke kortingsbon en laat de unieke code bij de ondernemer scannen.",
        "stempelkaarten": "Ontdek digitale stempelkaarten, lokale winkels en de beloningen die je kunt sparen.",
        "saldo-checken": "Vind de officiële saldo checker van je cadeaukaart. Je voert je kaartnummer uitsluitend bij de uitgever in.",
    }.get(active, "")
    search_path = {"saldo-checken": "/saldo-checken/", "stempelkaarten": "/stempelkaarten/", "cadeaubon": "/cadeaubon/", "klantenkaart": "/klantenkaart/"}.get(active, "/kaarten/")
    search_kind = '<input type="hidden" name="soort" value="kortingsbonnen">' if active == "kortingsbonnen" else ""
    return f'''<div class="wrap ch-crumb"><a href="/">Home</a> / <span>{escape(next((title for key, _, title, _ in SECTIONS if key == active), "Kaarten"))}</span></div><section class="wrap ch-hero ch-hero-{active}" aria-label="Kaarten en voordelen">
      <div class="ch-hero-copy">
        <span class="ch-eyebrow">Pasr · Kaarten &amp; Voordelen</span>
        <h1>{title}</h1><p>{subtitle}</p>
        <form action="{search_path}" method="get" role="search" class="ch-global-search">
          {search_kind}<label class="sr-only" for="ch-search">Zoek een winkel, kaart of voordeel</label>
          <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.8" cy="10.8" r="6.7" fill="none" stroke="currentColor" stroke-width="2"/><path d="m16 16 4.5 4.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
          <input id="ch-search" type="search" name="q" placeholder="Zoek een winkel, kaart of aanbieding…" autocomplete="off">
          <button type="submit">Zoeken</button>
        </form>
        <div class="ch-hero-tags">
          <a href="/kaarten/?soort=klantenkaarten">Klantenkaarten</a>
          <a href="/kaarten/?soort=cadeaukaarten">Cadeaukaarten</a>
          <a href="/stempelkaarten/">Stempelkaarten</a>
          <a href="/kortingsbonnen/">Kortingsbonnen</a>
        </div>
      </div>
      <div class="ch-hero-art ch-real-art" aria-label="Voorbeelden uit de Pasr-catalogus">{real_card_art(active)}</div>
    </section>'''


def assets():
    return '<link rel="stylesheet" href="/assets/catalog-hub.css">'

def strip(active="kaarten"):
    return f'''<div class="ch-intro wrap"><span class="ch-eyebrow">Pasr · Kaarten &amp; Voordelen</span>
    <p>Ontdek kaarten, bekijk saldo-informatie en vind acties van deelnemende ondernemers.
    Je bewaart je eigen kaarten veilig in Pasr.</p></div>{section_nav(active)}'''


def footer_links():
    return '''<a href="/kaarten/">Klantenkaarten</a><a href="/cadeaubon/">Cadeaukaarten</a><a href="/stempelkaarten/">Stempelkaarten</a><a href="/kortingsbonnen/">Kortingsbonnen</a><a href="/saldo-checken/">Saldo checken</a><a href="/zakelijk/">Voor ondernemers</a><a href="/privacy/">Privacy</a><a href="/privacy/#cookies" data-consent-open>Cookie-instellingen</a><a href="/support/">Support</a>'''
