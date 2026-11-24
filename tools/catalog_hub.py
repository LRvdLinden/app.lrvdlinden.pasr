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
    """Shared consumer navigation; highlight the active destination."""
    links = (
        ("kaarten", "/kaarten/", "Klantenkaarten"),
        ("cadeaubon", "/cadeaubon/", "Cadeaukaarten"),
        ("stempelkaarten", "/stempelkaarten/", "Stempelkaarten"),
        ("kortingsbonnen", "/kortingsbonnen/", "Kortingsbonnen"),
        ("saldo-checken", "/saldo-checken/", "Saldo checken"),
    )
    items = ''.join(
        f'<li><a href="{url}"' +
        (' aria-current="page"' if active == key else '') +
        f'>{escape(label)}</a></li>'
        for key, url, label in links
    )
    return f'''<header class="wrap nav ch-site-nav">
  <a class="brand" href="/" aria-label="Pasr homepage"><img src="/assets/icon.png" width="36" height="36" alt=""><span>pasr</span></a>
  <nav aria-label="Hoofdmenu"><ul>
    {items}
    <li><a class="ch-business-link" href="/zakelijk/">Voor ondernemers</a></li>
  </ul></nav>
</header>'''

def section_nav(active="kaarten"):
    links = []
    for value, href, title, _ in SECTIONS:
        attrs = ' aria-current="page"' if active == value else ""
        links.append(f'<a href="{href}"{attrs}>{escape(title)}</a>')
    return ('<nav class="wrap ch-sections" aria-label="Soorten kaarten en voordelen">'
            + ''.join(links) + '</nav>')

def hero(active="kaarten", count=None):
    """Gedeelde hero met een directe cataloguszoekactie en herkenbare kaartcategorieën."""
    title = {
        "kaarten": "Al je kaarten &amp; voordelen op één plek",
        "klantenkaart": "Vind jouw klantenkaart",
        "cadeaubon": "Ontdek cadeaukaarten en check je saldo",
        "kortingsbonnen": "Ontdek tijdelijke kortingsbonnen",
        "stempelkaarten": "Spaar bij jouw favoriete ondernemers",
        "saldo-checken": "Hoeveel staat er op jouw cadeaukaart?",
    }.get(active, "Kaarten &amp; voordelen")
    subtitle = {
        "kaarten": "Zoek in de kaartencatalogus van Pasr en ontdek actuele acties van ondernemers.",
        "klantenkaart": "Zoek een winkel en ontdek hoe je spaart en welke voordelen er zijn.",
        "cadeaubon": "Bekijk kaartinformatie, geldigheid en de officiële saldo-checker van de uitgever.",
        "kortingsbonnen": "Bewaar een persoonlijke kortingsbon en laat de unieke code bij de ondernemer scannen.",
        "stempelkaarten": "Ontdek digitale stempelkaarten, lokale winkels en de beloningen die je kunt sparen.",
        "saldo-checken": "Vind de officiële saldo checker van je cadeaukaart. Je voert je kaartnummer uitsluitend bij de uitgever in.",
    }.get(active, "")
    return f'''<section class="wrap ch-hero" aria-label="Kaarten en voordelen">
      <div class="ch-hero-copy">
        <span class="ch-eyebrow">Pasr · Kaarten &amp; Voordelen</span>
        <h1>{title}</h1><p>{subtitle}</p>
        <form action="/kaarten/" method="get" role="search" class="ch-global-search">
          <label class="sr-only" for="ch-search">Zoek een winkel, kaart of voordeel</label>
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
      <div class="ch-hero-art" aria-hidden="true">
        <div class="ch-card ch-card-one"><span>pasr</span><strong>KLANTENKAART</strong><i></i><i></i><i></i></div>
        <div class="ch-card ch-card-two"><span>pasr</span><strong>CADEAUKAART</strong><b>€ 50</b></div>
        <div class="ch-card ch-card-three"><span>pasr</span><strong>KORTINGSBON</strong><b>%</b></div>
      </div>
    </section>'''


def assets():
    return '<link rel="stylesheet" href="/assets/catalog-hub.css">'

def strip(active="kaarten"):
    return f'''<div class="ch-intro wrap"><span class="ch-eyebrow">Pasr · Kaarten &amp; Voordelen</span>
    <p>Ontdek kaarten, bekijk saldo-informatie en vind acties van deelnemende ondernemers.
    Je bewaart je eigen kaarten veilig in Pasr.</p></div>{section_nav(active)}'''
