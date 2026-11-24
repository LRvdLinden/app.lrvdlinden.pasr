"""Herbruikbare navigatie voor alle Pasr kaarten, cadeaukaarten en kortingsbonnen.
Houdt de bestaande bestemmingen, zoekindex en canonical-URL's intact."""
from html import escape

SECTIONS = (
    ("kaarten", "/kaarten/", "Alle kaarten", "layers"),
    ("klantenkaart", "/klantenkaart/", "Klantenkaarten", "credit-card"),
    ("cadeaubon", "/cadeaubon/", "Cadeaukaarten", "gift"),
    ("kortingsbonnen", "/kortingsbonnen/", "Kortingsbonnen", "ticket"),
)

def site_nav(active="kaarten"):
    return f'''<header class="wrap nav ch-site-nav">
  <a class="brand" href="/"><img src="/assets/icon.png" width="36" height="36" alt=""><span>pasr</span></a>
  <nav aria-label="Hoofdmenu"><ul>
    <li><a href="/#functies">Functies</a></li>
    <li><a href="/kaarten/"{' aria-current="page"' if active in ("kaarten", "klantenkaart", "cadeaubon", "kortingsbonnen") else ""}>Kaarten &amp; voordelen</a></li>
    <li class="hide-sm"><a href="/zakelijk/">Voor ondernemers</a></li>
    <li><a href="/support/">Support</a></li>
  </ul></nav>
</header>'''

def section_nav(active="kaarten"):
    links = []
    for value, href, title, _ in SECTIONS:
        attrs = ' aria-current="page"' if active == value else ""
        links.append(f'<a href="{href}"{attrs}>{escape(title)}</a>')
    return ('<nav class="wrap ch-sections" aria-label="Soorten kaarten en voordelen">'
            + ''.join(links) + '</nav>')

def assets():
    return '<link rel="stylesheet" href="/assets/catalog-hub.css">'

def strip(active="kaarten"):
    return f'''<div class="ch-intro wrap"><span class="ch-eyebrow">Pasr · Kaarten &amp; Voordelen</span>
    <p>Ontdek kaarten, bekijk saldo-informatie en vind acties van deelnemende ondernemers.
    Je bewaart je eigen kaarten veilig in Pasr.</p></div>{section_nav(active)}'''
