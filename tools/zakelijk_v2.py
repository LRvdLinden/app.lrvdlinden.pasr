"""pasr.nl/zakelijk in de stijl van de nieuwe homepage (november 2026, ontwerp C).

Losse bouwstenen voor make_zakelijk.page(): balk met voordelen, hero met de scan-animatie, "Wat kun je maken?",
"Klanten laten terugkomen", "Aan de toonbank", banners, donker blok en afsluiter. Alleen echte functies van
Pasr Zakelijk; voorbeelden zijn herkenbaar als voorbeeld. Animaties stoppen bij "minder beweging" (zakelijk-v2.css).
"""

TICK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" aria-hidden="true"><path d="M5 12l5 5L20 7"/></svg>'


def usp():
    items = ["Gratis: geen abonnement, geen kosten per stempel", "Geen kassakoppeling: je telefoon is genoeg",
             "iPhone, Android en in je browser"]
    return '<div class="zv-usp"><ul class="wrap">' + "".join(f"<li>{TICK}{t}</li>" for t in items) + "</ul></div>"


def _stamps(n, on, start=0.0):
    return "".join(f'<i class="{"on" if k < on else ""}" style="--d:{start + k * .45:.2f}s"></i>' for k in range(n))


def _bars(cls="zv-bar"):
    return "".join(f'<i class="{cls}" style="height:{h}%;--d:{k * .15:.2f}s"></i>' for k, h in enumerate((40, 62, 48, 80, 66, 92, 74)))


def hero(badges_html, demo):
    checks = ["Stempelkaart in je eigen logo en kleur, in een minuut",
              "Kortingsbonnen, actiecodes en acties met andere zaken",
              "Alleen jij en je medewerkers zetten stempels",
              "Je ziet aantallen, nooit namen of telefoonnummers"]
    lis = "".join(f"<li>{TICK}{c}</li>" for c in checks)
    return f'''    <div class="wrap hero zv-hero" id="top">
      <div>
        <span class="zv-kicker enter" style="--d:0">Pasr Zakelijk · gratis voor ondernemers</span>
        <h1 class="enter" style="--d:0">Van klanten naar vaste klanten</h1>
        <ul class="zv-checks enter" style="--d:1">{lis}</ul>
        <div class="actions enter" style="--d:2">
          <a class="zv-btn" href="/zakelijk/dashboard/#account" data-zk-signup>Gratis aanmelden</a>
          <a class="zv-pill" href="/zakelijk/dashboard/" data-zk-login>Inloggen</a>
        </div>
        <div class="actions zk-badges enter" style="--d:3" aria-label="De app Pasr Zakelijk">
          {badges_html}
        </div>
        <ul class="platforms enter" style="--d:3" aria-label="Werkt op">
          <li><b>iPhone en iPad</b> iOS 17+</li>
          <li><b>Android</b> 8+</li>
          <li><b>Browser</b> dashboard en scanner</li>
        </ul>
      </div>
      <div class="zv-panel enter-stage" aria-hidden="true">
        <div class="zv-stage">
          <div class="zv-float zv-ol zv-stampcard" style="left:0;top:40px;background:{demo["color"]}">
            <b>{demo["business"]}</b>
            <span class="zv-dots">{_stamps(10, 6)}</span>
            <small>{demo["reward"]}</small>
          </div>
          <div class="zv-float zv-or zv-coupon" style="right:0;top:30px;animation-delay:-2s">
            <small>KORTINGSBON · ALLEEN IN PASR</small><b>15% korting</b><span>Eén per klant</span>
          </div>
          <div class="zv-float zv-or zv-code" style="left:3%;bottom:40px;animation-delay:-4s">
            <small>ACTIECODE</small><b>HERFST20</b><span>met limiet en einddatum</span>
          </div>
          <div class="zv-float zv-ol zv-chart" style="right:2%;bottom:30px;animation-delay:-3s">
            <small>STEMPELS PER DAG</small><span class="zv-bars">{_bars()}</span>
          </div>
          <span class="zv-chip">+1 stempel gezet</span>
          <div class="zv-phone"><div class="zv-screen">
            <span class="zv-island"></span>
            <b class="zv-title">Scannen</b>
            <span class="zv-viewfinder"><span class="zv-qr"></span><span class="zv-scan"></span></span>
            <span class="zv-sheet">
              <small>{demo["business"]} · lid …7K3Q</small>
              <span class="zv-stepper"><i>−</i><b>1</b><i>+</i></span>
              <span class="zv-go">1 stempel erbij</span>
            </span>
          </div></div>
        </div>
      </div>
    </div>'''


def steps():
    s = [("Meld je zaak aan", "Gratis Pasr-account; we keuren je zaak met de hand goed, meestal binnen een werkdag."),
         ("Ontwerp je kaart", "Logo en kleur komen van je website. Kies 2 tot 30 stempels en de beloning."),
         ("Hang de QR-code op en scan", "Klanten scannen de flyer; jij scant hun kaart en kiest hoeveel stempels erbij komen.")]
    lis = "".join(f'<li><span class="zv-num">{i + 1}</span><span><b>{a}</b>{b}</span></li>' for i, (a, b) in enumerate(s))
    return f'''    <section class="zv-steps-band" id="zo-werkt-het" aria-labelledby="werkt-title">
      <div class="wrap"><h2 id="werkt-title" class="zv-sr">Zo werkt het</h2><ol class="zv-steps">{lis}</ol></div>
    </section>'''


def _heading(id_, title, colour):
    return f'<div class="zv-heading"><h2 id="{id_}">{title}</h2><span class="zv-underline" style="background:{colour}"></span></div>'


def products():
    items = [
        ("Stempelkaart", "2 tot 30 stempels, jouw beloning, tot 5 kaarten per zaak. Logo en kleur van je website.",
         "STEMPELKAART", "10 = gratis koffie", "In jouw kleuren", "#7B4B2A", "#F6E9DE", "#7B4B2A"),
        ("Kortingsbon", "Procent of bedrag, minimale besteding, één per klant, alleen in Pasr te verzilveren. Pauzeren of aanpassen kan altijd.",
         "KORTINGSBON", "15% korting", "Eén per klant", "#FF6B57", "#FFE9E4", "#B2321D"),
        ("Actiecode", "Een eigen code als HERFST20 die klanten aan de kassa noemen, met limiet en einddatum.",
         "ACTIECODE", "HERFST20", "Tot 31 december", "#4A3CE0", "#EEEBFF", "#4A3CE0"),
        ("Gezamenlijke actie", "Spaar samen met andere zaken in je straat of winkelcentrum; elke zaak beslist zelf of hij meedoet.",
         "SAMEN SPAREN", "3 zaken = cadeau", "Winkelstraatactie", "#087554", "#DDF7EE", "#087554"),
    ]
    cards = "".join(
        f'<a class="zv-product" href="/zakelijk/dashboard/#account" style="--back:{back}">'
        f'<span class="zv-product-art"><span class="zv-product-card" style="background:{col}"><small>{tag}</small><b>{big}</b><span>{small}</span></span></span>'
        f'<span class="zv-product-copy"><b>{name}</b><span>{text}</span></span></a>'
        for name, text, tag, big, small, col, back, _ in items)
    return f'''    <section class="wrap zv-section" id="maken" aria-labelledby="maken-title">
      {_heading("maken-title", "Wat kun je maken?", "#2ED3A6")}
      <div class="zv-products">{cards}</div>
    </section>'''


def retention():
    tiles = [
        ('<span class="zv-mile"><span><b>3 stempels</b><span>Gratis koekje</span></span><span><b>10 stempels</b><span>Gratis koffie</span></span>'
         '<span class="zv-tiers"><em>ZILVER</em><em class="gold">GOUD · VIP-voordeel</em></span></span>',
         "Mijlpalen en VIP-niveaus", "Tot acht beloningen per kaart, plus Zilver en Goud voor je vaste klanten."),
        ('<span class="zv-ref"><i>A</i><span>→</span><i class="b">B</i><em class="zv-chip-sm">+2 bonus</em></span>',
         "Vrienden uitnodigen", "Een klant deelt een uitnodigingslink; jij kiest de bonusstempels en wanneer ze vrijkomen."),
        ('<span class="zv-ret"><small>TERUGKOMERS</small><span class="zv-meter"><i></i></span><small>Wie komt terug, wie lang niet is geweest</small></span>',
         "Terugkom-inzichten", "Zie per kaart wie terugkomt en wie lang niet is geweest, zonder klantgegevens. Berichten alleen met toestemming van de klant."),
        ('<span class="zv-push"><svg class="zv-bell" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M6 8a6 6 0 1112 0c0 7 3 8 3 8H3s3-1 3-8M10 20a2 2 0 004 0"/></svg>'
         '<span><b>Koffiebar De Hoek</b><br>+1 stempel · nog 2 tot je koffie</span></span>',
         "Vindbaar, met een melding bij elke stempel", "Klanten vinden je kaart in Pasr bij In de buurt en krijgen een melding als er een stempel bijkomt."),
    ]
    html = "".join(f'<div class="zv-tile"><span class="zv-tile-art" aria-hidden="true">{art}</span><b>{t}</b><span>{x}</span></div>'
                   for art, t, x in tiles)
    return f'''    <section class="wrap zv-section" id="terugkomen" aria-labelledby="terug-title">
      {_heading("terug-title", "Klanten laten terugkomen", "var(--iris)")}
      <div class="zv-tiles">{html}</div>
    </section>'''


def counter():
    items = [("Scannen en ongedaan maken", "Scan de stempelkaart, kortingsbon of PC-code van je klant, of typ de actiecode. Per ongeluk? Binnen 2 minuten terugdraaien."),
             ("Medewerkers met eigen inlog", "Uitnodigen met een link; medewerkers kunnen alleen scannen. Toegang intrekken kan altijd."),
             ("Afkoeltijd en logboek", "Even geen nieuwe stempel voor dezelfde klant, een maximum per scan, en een logboek dat niemand kan wissen."),
             ("Vestigingen", "Meerdere filialen onder één zaak; je ziet per vestiging waar gescand is.")]
    html = "".join(f'<div class="zv-line"><b>{a}</b><span>{b}</span></div>' for a, b in items)
    return f'''    <section class="wrap zv-section" id="functies" aria-labelledby="toonbank-title">
      {_heading("toonbank-title", "Aan de toonbank", "var(--coral)")}
      <div class="zv-lines" id="toonbank">{html}</div>
    </section>'''


def banners():
    return f'''    <section class="wrap zv-banners" aria-label="Promotie en dashboard">
      <a class="zv-banner zv-yellow" href="/zakelijk/dashboard/#promotie">
        <span class="zv-banner-copy"><b>Promotiemateriaal voor elke actie</b><span>A4-flyer, raamsticker, Instagram-post en Story, WhatsApp-status en websitebanner. In jouw kleuren, licht of donker, als PNG of ZIP.</span><em>Naar je promotiemateriaal ›</em></span>
        <span class="zv-banner-art" aria-hidden="true">
          <span class="zv-story zv-or"><b>SPAAR HIER</b><i class="zv-qr-sm"></i><small>Story · donker</small></span>
          <span class="zv-flyer zv-ol" style="animation-delay:-2s"><b>Spaar met Pasr</b><i class="zv-qr-sm"></i><small>A4-flyer</small></span>
        </span>
      </a>
      <a class="zv-banner zv-lilac" href="/zakelijk/dashboard/">
        <span class="zv-banner-copy"><b>Ook gewoon in je browser</b><span>Kaarten en acties maken, scannen met je laptop, medewerkers, vestigingen, grafieken en het logboek. Hetzelfde account als in de app.</span><em>Inloggen op het dashboard ›</em></span>
        <span class="zv-browser" aria-hidden="true"><small>pasr.nl/zakelijk/dashboard</small><span class="zv-bars">{_bars("zv-bar mint")}</span></span>
      </a>
    </section>'''


def dark_band():
    return '''    <section class="zv-dark" aria-label="Gratis en privacy">
      <div class="wrap zv-dark-grid">
        <div><b class="zv-big">€ 0</b><b>Gratis</b><span>Geen abonnement, geen kosten per stempel of per kaart, geen kassakoppeling.</span></div>
        <div><b class="zv-code-big">PZ••••7K3Q</b><b>Privacy voor je klanten</b><span>Klanten sparen met een anonieme code. Pasr vraagt geen naam, e-mail of telefoonnummer; jij ziet alleen de laatste tekens.</span></div>
        <div><b class="zv-code-big">Papier → Pasr</b><b>Niet kwijt, niet na te maken</b><span>Altijd bij de klant in de app, op de Wallet-pas of in de browser, en alleen jij zet stempels.</span></div>
      </div>
    </section>'''


def closer(badges_html):
    return f'''    <section class="wrap zv-closer" id="download" aria-labelledby="cta-title">
      <div>
        <span><b id="cta-title">Klaar voor je eerste stempel?</b><span>Gratis in de App Store, als download voor Android en in je browser.</span></span>
        <span class="zv-closer-actions"><a class="zv-btn light" href="/zakelijk/dashboard/#account" data-zk-signup>Gratis aanmelden</a><a class="zv-pill light" href="/zakelijk/dashboard/" data-zk-login>Inloggen</a></span>
      </div>
      <div class="actions zv-closer-badges">{badges_html}</div>
    </section>'''
