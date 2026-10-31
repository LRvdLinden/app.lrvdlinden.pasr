#!/usr/bin/env python3
"""Builds website/index.html with real EAN-13 bars for the demo cards. Run after editing the copy here."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import verify_barcodes as v

ROOT = Path(__file__).resolve().parent.parent / "website"

def bars(digits12):
    bits = v.ean13(digits12)
    number = digits12 + str(v.check(digits12))
    d, i = "", 0
    while i < len(bits):
        if bits[i] == "1":
            j = i
            while j < len(bits) and bits[j] == "1":
                j += 1
            d += f"M{10+i} 0h{j-i}v1h-{j-i}z"
            i = j
        else:
            i += 1
    svg = f'<svg viewBox="0 0 115 1" preserveAspectRatio="none" aria-hidden="true"><path fill="#000" d="{d}"/></svg>'
    return number, svg

CARDS = [
    ("Bakkerij De Hoek", "BH", "#E2683C", "Klantenkaart", "871932700441", False),
    ("Boekhandel Lint", "BL", "#6A5CFF", "Klantenkaart", "210123456789", False),
    ("Tuincentrum Groenhof", "TG", "#1F9E6A", "Klantenkaart", "871200004567", False),
    ("Cadeaukaart Stad", "CS", "#FFC233", "Voucher", "400638133393", True),
]

def pass_html(i, card):
    name, mono, color, kind, digits, dark = card
    number, svg = bars(digits)
    grouped = " ".join(number[k:k+4] for k in range(0, 13, 4))
    cls = "pass ink-dark" if dark else "pass"
    bg = f"background: linear-gradient(135deg, color-mix(in srgb, {color}, #fff 16%), {color} 55%, color-mix(in srgb, {color}, #000 22%));"
    extra = '<span class="num">€ 25,00 · geldig tot 31 dec</span>' if kind == "Voucher" else f'<span class="num">{grouped}</span>'
    return f'''        <button class="{cls}" style="top:{i*58}px; z-index:{i}" aria-label="{name}: toon de barcode">
          <span class="side front" style="{bg}">
            <span class="head"><span class="mono">{mono}</span>{name}<span class="kind">{kind}</span></span>
            {extra}
          </span>
          <span class="side back" style="{bg}">
            <span class="head"><span class="mono">{mono}</span>{name}</span>
            <span class="code">{svg}<small>{grouped}</small></span>
          </span>
        </button>'''

ICONS = {
    "flip": '<path d="M7 7h10a3 3 0 0 1 3 3v4M17 17H7a3 3 0 0 1-3-3v-4M17 4l3 3-3 3M7 20l-3-3 3-3"/>',
    "scan": '<path d="M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3M7 9v6M10 9v6M13 9v6M17 9v6"/>',
    "gift": '<path d="M4 10h16v10H4zM3 7h18v3H3zM12 7v13M12 7c-1.5-3-5-3-5-1s3 1 5 1c2 0 5 1 5-1s-3.5-2-5 1"/>',
    "logo": '<path d="M4 6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2zM8 15l3-3 2 2 3-4 2 3"/>',
    "lock": '<path d="M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3M12 15v2"/>',
    "watch": '<path d="M8 6h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2zM9 6l1-3h4l1 3M9 18l1 3h4l1-3"/>',
    "widget": '<path d="M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z"/>',
    "cloud": '<path d="M7 18a4 4 0 0 1-.6-8A6 6 0 0 1 18 9a4.5 4.5 0 0 1-.5 9z"/>',
    "share": '<path d="M12 4v11M8 8l4-4 4 4M5 13v5a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-5"/>',
    "store": '<path d="M4 9l1.5-5h13L20 9M4 9h16v11H4zM4 9a2.7 2.7 0 0 0 5.3 0 2.7 2.7 0 0 0 5.4 0 2.7 2.7 0 0 0 5.3 0M10 20v-5h4v5"/>',
}

def icon(name):
    return f'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{ICONS[name]}</svg>'

FEATURES = [
    ("flip", "#6A5CFF", "Kaarten die omdraaien", "Tik op een kaart: hij komt naar voren, draait om en toont de barcode of QR-code. Je scherm gaat vanzelf op volle helderheid."),
    ("scan", "#FF6B57", "Toevoegen in seconden", "Kies je winkel en scan de barcode met de camera. Een foto of screenshot van je pas werkt ook."),
    ("gift", "#E2683C", "Cadeaukaarten met saldo", "Bewaar het saldo, de pincode en de vervaldatum, zodat je een cadeaukaart nooit meer vergeet."),
    ("logo", "#1F9E6A", "Met het logo van je winkel", "Pasr haalt het icoon op van de website van de winkel. Of knip zelf een logo uit een foto van je pas."),
    ("lock", "#17162A", "Beveiligd met Face ID", "Vergrendel heel Pasr, of scherm alleen de code van een cadeaukaart af tot jij het bent."),
    ("watch", "#2ED3A6", "Op je pols en je beginscherm", "Je kaarten staan als pasjes op je Apple Watch. Met de widgets heb je je favorieten, of één kaart met barcode, direct op je beginscherm."),
    ("cloud", "#0A84FF", "Via je eigen iCloud", "Je kaarten staan op je iPhone, iPad, Mac en Watch tegelijk. Geen account, geen server van ons."),
    ("share", "#FF375F", "Kaarten delen", "Stuur een kaart naar je partner of huisgenoot. Die opent hem met één tik in zijn eigen Pasr, of scant de QR-code."),
    ("store", "#AF52DE", "Meer dan 100 Nederlandse winkels", "Van supermarkt tot tankstation en van drogist tot bioscoop: kies je winkel en de kleur en het soort barcode staan goed."),
]

FAQ = [
    ("Kost Pasr geld?", "Nee. Pasr is gratis, zonder reclame en zonder abonnement."),
    ("Moet ik een account aanmaken?", "Nee. Je kaarten staan op je eigen apparaten en in je eigen iCloud. Wij hebben geen server waar je kaarten op staan en we kunnen ze niet zien."),
    ("Kan ik mijn kaarten uit Klarna of Stocard overzetten?", "Ja. Maak in Klarna van elke kaart een screenshot met de barcode en kies die screenshots in Pasr, tot 50 tegelijk. Pasr leest de barcode en herkent de winkel, op je eigen telefoon."),
    ("Werkt een gescande kaart echt aan de kassa?", "Ja. Pasr tekent de barcode opnieuw in hetzelfde formaat als op je pas, zoals EAN-13, Code 128 of een QR-code, en zet je scherm op volle helderheid."),
    ("Op welke apparaten werkt Pasr?", "Op iPhone en iPad met iOS en iPadOS 26 of nieuwer, op de Mac met macOS 26 of nieuwer en op de Apple Watch met watchOS 26 of nieuwer."),
    ("Mijn winkel staat er niet tussen. Kan ik die kaart toch toevoegen?", "Ja. Kies Andere winkel, geef hem een naam en een kleur, en scan de barcode. Een logo kun je uitknippen uit een foto van je pas."),
    ("Waar komen de logo's vandaan?", "Pasr levert zelf geen logo's mee. Je iPhone haalt het icoon op dat de winkel zelf op zijn website zet. Dat kun je uitzetten in de instellingen."),
    ("Wat gebeurt er als ik mijn telefoon kwijtraak?", "Je kaarten staan in je iCloud. Log op je nieuwe iPhone in met hetzelfde Apple-account en open Pasr: je kaarten komen vanzelf terug."),
    ("Kan ik een kaart delen met mijn partner?", "Ja. Tik op Deel bij een kaart en stuur de link, of laat de ander de QR-code scannen. Wie Pasr heeft, voegt de kaart met één tik toe. Wie Pasr nog niet heeft, ziet de kaart met barcode gewoon in de browser."),
    ("Is Pasr ook in België te gebruiken?", "Pasr is gemaakt voor Nederland. De app is Nederlandstalig en de winkellijst bestaat uit Nederlandse winkels."),
]

APPLE = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.4 12.6c0-2.4 2-3.6 2.1-3.7-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9-.8 0-1.9-.9-3.2-.8-1.6 0-3.2 1-4 2.5-1.7 3-.4 7.4 1.2 9.8.8 1.2 1.8 2.5 3 2.4 1.2 0 1.7-.8 3.1-.8s1.9.8 3.2.7c1.3 0 2.1-1.2 2.9-2.4.9-1.3 1.3-2.7 1.3-2.7s-2.4-1-2.4-4zM14 5.4c.7-.8 1.1-1.9 1-3-1 0-2.1.7-2.8 1.5-.6.7-1.2 1.8-1 2.9 1 .1 2.1-.6 2.8-1.4z"/></svg>'

def page():
    passes = "\n".join(pass_html(i, c) for i, c in enumerate(CARDS))
    _, watch_svg = bars(CARDS[0][4])
    watch_num = CARDS[0][4] + str(v.check(CARDS[0][4]))
    features = "\n".join(f'''      <article class="feature">
        <div class="swatch" style="background:{color}">{icon(name)}</div>
        <h3>{title}</h3>
        <p>{text}</p>
      </article>''' for name, color, title, text in FEATURES)
    faq = "\n".join(f'''      <details>
        <summary>{q}</summary>
        <p>{a}</p>
      </details>''' for q, a in FAQ)
    faq_ld = ",".join('{"@type":"Question","name":%s,"acceptedAnswer":{"@type":"Answer","text":%s}}' % (__import__("json").dumps(q), __import__("json").dumps(a)) for q, a in FAQ)
    return f'''<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Pasr: klantenkaarten app voor iPhone en Apple Watch | Gratis Stocard-alternatief</title>
  <meta name="description" content="Pasr bewaart al je klantenkaarten en cadeaukaarten op iPhone, iPad, Mac en Apple Watch. Gratis, zonder account en zonder reclame. Zet je kaarten in een paar minuten over uit Klarna of Stocard.">
  <meta name="keywords" content="klantenkaarten app, klantenkaart app iPhone, Stocard alternatief, Klarna klantenkaarten overzetten, klantenkaarten Apple Watch, cadeaukaarten app, bonuskaart op telefoon, wallet app Nederland, gratis klantenkaarten app">
  <meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1">
  <meta name="author" content="Pasr">
  <meta name="application-name" content="Pasr">
  <meta name="apple-mobile-web-app-title" content="Pasr">
  <meta name="format-detection" content="telephone=no">
  <link rel="canonical" href="https://pasr.nl/">
  <link rel="alternate" hreflang="nl-NL" href="https://pasr.nl/">
  <link rel="alternate" hreflang="x-default" href="https://pasr.nl/">
  <link rel="manifest" href="/site.webmanifest">
  <meta name="theme-color" content="#F4F3FF">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Pasr">
  <meta property="og:url" content="https://pasr.nl/">
  <meta property="og:title" content="Pasr: al je pasjes. Zonder gedoe.">
  <meta property="og:description" content="Klantenkaarten en cadeaukaarten op iPhone, iPad, Mac en Apple Watch. Gratis en zonder account.">
  <meta property="og:image" content="https://pasr.nl/assets/og.png">
  <meta property="og:image:type" content="image/png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="Drie klantenkaarten in Pasr, met een barcode op de voorste kaart">
  <meta property="og:locale" content="nl_NL">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="Pasr: al je pasjes. Zonder gedoe.">
  <meta name="twitter:description" content="Klantenkaarten en cadeaukaarten op iPhone, iPad, Mac en Apple Watch. Gratis en zonder account.">
  <meta name="twitter:image" content="https://pasr.nl/assets/og.png">
  <meta name="twitter:image:alt" content="Drie klantenkaarten in Pasr, met een barcode op de voorste kaart">
  <link rel="icon" type="image/png" sizes="64x64" href="/assets/favicon.png">
  <link rel="apple-touch-icon" sizes="180x180" href="/assets/apple-touch-icon.png">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800&family=Figtree:wght@400;500;600&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="/assets/style.css">
  <script type="application/ld+json">{{"@context":"https://schema.org","@graph":[
    {{"@type":"Organization","@id":"https://pasr.nl/#org","name":"Pasr","url":"https://pasr.nl/","logo":"https://pasr.nl/assets/icon-512.png","email":"support@pasr.nl"}},
    {{"@type":"WebSite","@id":"https://pasr.nl/#site","url":"https://pasr.nl/","name":"Pasr","inLanguage":"nl-NL","publisher":{{"@id":"https://pasr.nl/#org"}}}},
    {{"@type":"MobileApplication","name":"Pasr","operatingSystem":"iOS 26, iPadOS 26, macOS 26, watchOS 26","applicationCategory":"LifestyleApplication","inLanguage":"nl-NL","countriesSupported":"NL","url":"https://pasr.nl/","image":"https://pasr.nl/assets/icon-512.png","screenshot":"https://pasr.nl/assets/og.png","description":"Klantenkaarten en cadeaukaarten op iPhone, iPad, Mac en Apple Watch. Gratis, zonder account en zonder reclame.","featureList":["Klantenkaarten en cadeaukaarten bewaren","Barcode scannen met de camera","Kaarten overzetten uit Klarna of Stocard via screenshots","Apple Watch-app","Widgets","Synchroniseren via iCloud","Beveiligen met Face ID","Kaarten delen"],"offers":{{"@type":"Offer","price":"0","priceCurrency":"EUR"}},"publisher":{{"@id":"https://pasr.nl/#org"}}}}
  ]}}</script>
  <script type="application/ld+json">{{"@context":"https://schema.org","@type":"FAQPage","mainEntity":[{faq_ld}]}}</script>
</head>
<body>
  <header class="wrap nav">
    <a class="brand" href="/"><img src="/assets/icon.png" alt="" width="36" height="36"><span>pasr</span></a>
    <nav aria-label="Hoofdmenu">
      <ul>
        <li><a href="#functies">Functies</a></li>
        <li><a href="#overstappen">Overstappen</a></li>
        <li><a href="#faq">Vragen</a></li>
        <li><a href="/support/">Support</a></li>
      </ul>
    </nav>
  </header>

  <main>
    <div class="wrap hero">
      <div>
        <h1>Al je pasjes. Zonder gedoe.</h1>
        <p class="lead">Pasr bewaart je klantenkaarten en cadeaukaarten op iPhone, iPad, Mac en Apple Watch. Geen account, geen reclame, geen betaalapp eromheen.</p>
        <div class="actions">
          <a class="btn btn-primary" aria-disabled="true" role="link">{APPLE}Binnenkort in de App Store</a>
          <a class="btn btn-ghost" href="#functies">Bekijk wat Pasr kan</a>
        </div>
        <ul class="platforms" aria-label="Geschikt voor">
          <li><b>iPhone</b> iOS 26+</li>
          <li><b>iPad</b> iPadOS 26+</li>
          <li><b>Mac</b> macOS 26+</li>
          <li><b>Apple Watch</b> watchOS 26+</li>
        </ul>
      </div>

      <div class="stage">
        <div class="phone" aria-label="Voorbeeld van de app">
          <div class="screen">
            <div class="statusbar" aria-hidden="true"><span>9:41</span><span>●●●</span></div>
            <div class="island" aria-hidden="true"></div>
            <h2>Kaarten</h2>
            <div class="stack" id="stack">
{passes}
            </div>
            <p class="hint" id="hint">Tik op een kaart</p>
          </div>
        </div>
        <div class="watch" aria-hidden="true">
          <div class="face"><b>{CARDS[0][0]}</b>{watch_svg}<small>{watch_num}</small></div>
        </div>
      </div>
    </div>

    <div class="wrap">
      <section class="why" aria-labelledby="why-title">
        <div class="section-head">
          <h2 id="why-title">Een kaartenapp die alleen een kaartenapp is</h2>
          <p>Stocard is gestopt en je kaarten moesten naar een betaalapp. Pasr doet het andersom: alleen je kaarten, snel bij de kassa.</p>
        </div>
        <div class="compare">
          <div class="compare-head">Wat je vaak ziet</div>
          <div class="compare-head" style="color:#fff">Pasr</div>
          <div><strong>Account verplicht</strong>Telefoonnummer en e-mailadres voordat je je eigen kaarten ziet.</div>
          <div><strong>Geen account</strong>Open de app en je kaarten staan er. Ze reizen mee via je eigen iCloud.</div>
          <div><strong>Aanbiedingen en betalen</strong>Kaarten tussen deals, leningen en betaaldiensten.</div>
          <div><strong>Alleen je kaarten</strong>Geen reclame, geen deals, geen betaalfuncties.</div>
          <div><strong>Gegevens verzamelen</strong>Inzicht in waar en wat je koopt.</div>
          <div><strong>Niets verzameld</strong>Geen tracking en geen analyse. Wat je bewaart, blijft van jou.</div>
        </div>
      </section>
    </div>

    <section class="wrap" id="functies" aria-labelledby="functies-title">
      <div class="section-head">
        <h2 id="functies-title">Alles wat je aan de kassa nodig hebt</h2>
        <p>Pasr is gemaakt zoals Apple Wallet: je kaarten op een stapel, en één tik om de code te tonen.</p>
      </div>
      <div class="features">
{features}
      </div>
    </section>

    <section class="wrap" id="overstappen" aria-labelledby="overstappen-title">
      <div class="section-head">
        <h2 id="overstappen-title">Overstappen uit Klarna of Stocard</h2>
        <p>Een export van je kaarten bestaat daar niet. Met screenshots ben je in een paar minuten klaar.</p>
      </div>
      <ol class="steps">
        <li><h3>Maak screenshots</h3><p>Open in Klarna elke kaart en maak een screenshot waarop de barcode staat.</p></li>
        <li><h3>Kies ze in Pasr</h3><p>Tik op Screenshots importeren en kies ze allemaal tegelijk, tot 50 per keer.</p></li>
        <li><h3>Controleer en klaar</h3><p>Pasr vindt de barcode en de winkel. Kijk de lijst na, pas aan wat niet klopt en importeer.</p></li>
      </ol>
    </section>

    <section class="wrap" id="faq" aria-labelledby="faq-title">
      <div class="section-head"><h2 id="faq-title">Vragen</h2></div>
      <div class="faq">
{faq}
      </div>
    </section>

    <section class="wrap cta" aria-labelledby="cta-title">
      <h2 id="cta-title">Je portemonnee wordt een stuk dunner</h2>
      <p>Pasr komt binnenkort gratis in de App Store.</p>
      <div class="actions">
        <a class="btn btn-primary" aria-disabled="true" role="link">{APPLE}Binnenkort in de App Store</a>
      </div>
    </section>
  </main>

  <footer>
    <div class="wrap">
      <span>&copy; 2026 Pasr</span>
      <nav aria-label="Voettekst">
        <a href="/privacy/">Privacy</a>
        <a href="/support/">Support</a>
      </nav>
    </div>
  </footer>
  <script src="/assets/site.js" defer></script>
</body>
</html>
'''

if __name__ == "__main__":
    (ROOT / "index.html").write_text(page())
    print("Wrote", ROOT / "index.html")
