"""pasr.nl/zakelijk: het brede platform (november 2026, ontwerp D, goedgekeurd door Léon).

Bouwstenen voor make_zakelijk.page(): balk met voordelen, hero met de zwevende passen, "Wat kun je maken" (zes
producten), "Voeg toe aan Pasr" voor je eigen site, één scanner voor alles, het dashboard, de wallet van je klanten,
drie stappen, vragen en afsluiter. Styling in website/assets/zakelijk-v2.css.

De passen zijn zo dicht mogelijk bij de echte weergave:
- stempelkaart: dezelfde opmaak als stampCard() in website/assets/zakelijk.js (.sc), met de officiële Pasr-stempel
  (/assets/pasr-stamp.svg als masker in zakelijk.css);
- klantenkaart: zoals in Pasr (kleur, logo-tegel, korting-chip, barcode op wit);
- ticket: zoals EventTicketViews.swift (gekleurde kop, logo-tegel, ZAAKNAAM, TICKET, eventnaam, soort-pil,
  DATUM/TOEGANG, LOCATIE, golfrand met inkepingen, witte voet met QR in afgeronde rand, code, Route/Informatie).
Elke pas staat op een vast "canvas" dat met CSS (.zn-fit) precies in zijn tegel wordt geschaald: nooit afgesneden.
Voorbeelddata is verzonnen (Bakkerij de Korenschoof, Fietsplus, Cafe Centraal); nooit echte zaken.
Alle beweging stopt bij "minder beweging".
"""
import html
import random

TICK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5 10 17 19 7"/></svg>'
GIFT = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" '
        'stroke-linejoin="round" aria-hidden="true"><rect x="3" y="8" width="18" height="13" rx="2"/><path d="M12 8v13M3 12h18M12 8S10.5 3 7.5 4.5 9 8 12 8zm0 0s1.5-5 4.5-3.5S15 8 12 8z"/></svg>')
I_TICKET = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" aria-hidden="true"><path d="M3 8.5V6a1 1 0 0 1 1-1h16a1 1 0 0 1 1 1v2.5a2.5 2.5 0 0 0 0 5V18a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-4.5a2.5 2.5 0 0 0 0-5zM9 5v14" stroke-dasharray="2 2.2"/></svg>'
I_MAP = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M9 4 3 6.2v13.6l6-2.2 6 2.2 6-2.2V4l-6 2.2zm0 2.1 6 2.2v9.6l-6-2.2z"/></svg>'
I_INFO = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 15h-2v-6h2zm0-8h-2V7h2z"/></svg>'

SIGNUP = "/zakelijk/dashboard/#account"
LOGIN = "/zakelijk/dashboard/"


def esc(s):
    return html.escape(str(s), quote=True)


# ---------------------------------------------------------------------------------------------- de echte passen
def _mix(hex_colour, to, part):
    out = "#"
    for i in (1, 3, 5):
        out += f"{round(int(hex_colour[i:i + 2], 16) * (1 - part) + to * part):02x}"
    return out


def stamp_card(name, business, city, color, total, on, reward, cls=""):
    """Python-versie van stampCard() uit website/assets/zakelijk.js: zelfde klassen (.sc), monogram als logo,
    cadeautje op het laatste vakje en de officiële Pasr-stempel (zakelijk.css maskeert /assets/pasr-stamp.svg)."""
    cols = total if total <= 5 else 5 if total <= 10 else 6 if total <= 12 else 7 if total <= 21 else 8
    mono = "".join(w[0] for w in name.split(" ")[:2]).upper()
    stamps = ""
    for i in range(total):
        is_on, last = i < on, i == total - 1
        stamps += (f'<span class="sc-stamp{" on" if is_on else ""}{" gift" if last and not is_on else ""}" style="--i:{i}">'
                   f'{GIFT if last and not is_on else ""}</span>')
    bg = f"linear-gradient(135deg, {_mix(color, 255, .16)}, {color} 55%, {_mix(color, 0, .22)})"
    return (f'<div class="sc demo{(" " + cls) if cls else ""}" style="--c:{color};background:{bg};--cols:{cols}">'
            f'<div class="sc-head"><span class="sc-logo">{esc(mono)}</span><span class="sc-title"><span class="sc-name">{esc(name)}</span>'
            f'<span class="sc-biz">{esc(business)} · {esc(city)}</span></span><span class="sc-kind">Stempelkaart</span></div>'
            f'<div class="sc-stamps">{stamps}</div>'
            f'<div class="sc-reward"><span>{esc(reward)}</span><span>{total - on} te gaan</span></div></div>')


def barcode(w=232, h=46, seed=3):
    r = random.Random(seed)
    x, bars = 0.0, []
    while x < w - 4:
        bw = r.choice([1.4, 1.4, 2.8, 4.2])
        if r.random() < .62:
            bars.append(f'<rect x="{x:.1f}" y="0" width="{bw}" height="{h}"/>')
        x += bw + r.choice([1.4, 2.8])
    return f'<svg class="zm-code" viewBox="0 0 {w} {h}" preserveAspectRatio="none" aria-hidden="true"><g fill="#17162A">{"".join(bars)}</g></svg>'


def qr(seed=7, n=25):
    """Nep-QR (voorbeeld, niet scanbaar als echt ticket) met de drie vaste hoekblokken."""
    r = random.Random(seed)
    cells = []
    for y in range(n):
        for x in range(n):
            corner = (x < 7 and y < 7) or (x >= n - 7 and y < 7) or (x < 7 and y >= n - 7)
            if corner:
                lx, ly = x if x < 7 else x - (n - 7), y if y < 7 else y - (n - 7)
                on = lx in (0, 6) or ly in (0, 6) or (2 <= lx <= 4 and 2 <= ly <= 4)
            elif (x == 7 and y < 8) or (y == 7 and x < 8) or (x == n - 8 and y < 8) or (y == 7 and x >= n - 8) or (x == 7 and y >= n - 8) or (y == n - 8 and x < 8):
                on = False
            else:
                on = r.random() < .5
            if on:
                cells.append(f"M{x} {y}h1v1h-1z")
    return f'<svg class="zn-qr" viewBox="0 0 {n} {n}" shape-rendering="crispEdges" aria-hidden="true"><path fill="#111" d="{"".join(cells)}"/></svg>'


def member_card(cls=""):
    """Klantenkaart met barcode zoals in Pasr: kaartkleur, logo-tegel, KLANTENKAART, korting die nu geldt, barcode op wit."""
    return (f'<div class="zm{(" " + cls) if cls else ""}" style="--c:#2F6FDE">'
            '<div class="zm-head"><span class="zm-logo">F</span><span class="zm-t"><b>Fietsplus Klantenkaart</b><small>Lid sinds 2026</small></span>'
            '<em>Klantenkaart</em></div>'
            '<span class="zm-chip">Nu 15% korting · t/m 15 dec</span>'
            f'<span class="zm-bar">{barcode()}<small>FP-0048 2219</small></span></div>')


def _wave(w=300, n=12, h=12):
    """Golfrand onder de gekleurde kop van het ticket (EventTicketViews.swift)."""
    p = w / n
    d = f"M0 0H{w}V{h / 2:.1f}"
    x = w
    for _ in range(n):
        d += f"Q{x - p / 4:.2f} {h} {x - p / 2:.2f} {h / 2:.1f}T{x - p:.2f} {h / 2:.1f}"
        x -= p
    return f'<svg class="zt-wave" viewBox="0 0 {w} {h}" preserveAspectRatio="none" aria-hidden="true"><path d="{d}Z"/></svg>'


def ticket(cls="", scan=False):
    """Het ticket zoals in de app Pasr (EventTicketViews.swift)."""
    scanline = '<span class="zc-scan"></span>' if scan else ""
    return (f'<div class="zt{(" " + cls) if cls else ""}" style="--tc:#22B5A8">'
            '<div class="zt-top">'
            f'<div class="zt-head"><span class="zt-logo">K</span><b>KORENSCHOOF</b><em>{I_TICKET}TICKET</em></div>'
            '<b class="zt-name">Winterborrel</b>'
            '<span class="zt-type"><b>Toegang</b><span>vanaf 18 jaar</span></span>'
            '<span class="zt-grid"><span><small>DATUM</small><b>19 dec 2026</b></span><span><small>TOEGANG</small><b>16:00 – 19:00</b></span></span>'
            '<span class="zt-loc"><small>LOCATIE</small><b>Hoofdstraat 12, Apeldoorn</b></span>'
            f'</div>{_wave()}'
            f'<div class="zt-foot"><span class="zt-qr">{qr()}{scanline}<small>K7QX-2M9P-HD4W</small></span>'
            f'<span class="zt-btns"><i>{I_MAP}Route</i><i>{I_INFO}Informatie</i></span></div></div>')


def coupon():
    return ('<div class="zn-coupon"><small>KORTINGSBON</small><b>15% korting</b><span>op taarten · t/m 31 dec</span></div>')


def action_code():
    return '<div class="zn-codepill"><small>ACTIECODE</small><b>HERFST20</b></div>'


def fit(inner, w, h, cls=""):
    """Vast canvas van w x h px dat CSS (.zn-fit) precies in zijn vak schaalt, zodat niets wordt afgesneden."""
    return (f'<div class="zn-fit{(" " + cls) if cls else ""}" style="--fw:{w};--fh:{h}" aria-hidden="true">'
            f'<div class="zn-canvas">{inner}</div></div>')


def _ul(items, colour="var(--zn-green)"):
    return '<ul class="zn-ticks" style="--tick:' + colour + '">' + "".join(f"<li>{TICK}<span>{t}</span></li>" for t in items) + "</ul>"


# ---------------------------------------------------------------------------------------------- secties
def usp():
    items = ["Gratis: geen abonnement, geen kosten per klant", "Geen kassakoppeling: je telefoon is genoeg",
             "iPhone, Android en in je browser"]
    return '<div class="zc-usp"><ul class="wrap">' + "".join(f"<li>{TICK}{t}</li>" for t in items) + "</ul></div>"


def hero(badges_html):
    """badges_html: de officiële App Store-badge (NL) en Android-badge van pasr.nl, uit make_zakelijk.badges()."""
    stage = (
        f'<div class="zn-h zn-h-member zc-ol"><div class="zn-tilt" style="--r:-8deg">{member_card()}</div></div>'
        f'<div class="zn-h zn-h-ticket zc-or" style="animation-delay:-2s"><div class="zn-tilt" style="--r:6deg">{ticket(scan=True)}</div></div>'
        f'<div class="zn-h zn-h-stamp">{stamp_card("Koffiekaart", "Bakkerij de Korenschoof", "Apeldoorn", "#E8590C", 10, 6, "10 = gratis koffie")}</div>'
        f'<div class="zn-h zn-h-coupon zc-ol" style="animation-delay:-4s">{coupon()}</div>'
        f'<div class="zn-h zn-h-code">{action_code()}</div>'
        f'<span class="zn-chip zn-chip-stamp">+1 stempel</span>'
        f'<span class="zn-chip zn-chip-ok">{TICK}Ticket geldig · 86/120 binnen</span>')
    checks = ["Alles in je eigen logo en kleur, in een paar minuten",
              "Klanten bewaren het in Pasr, Apple Wallet of Google Wallet",
              "Jij en je medewerkers scannen met de telefoon",
              "Je ziet cijfers; persoonsgegevens alleen waar het moet (tickets)"]
    return f'''    <div class="wrap zn-hero zc-hero" id="top">
      <div class="zn-hero-copy">
        <span class="zn-kicker enter" style="--d:0">Pasr Zakelijk · gratis voor ondernemers</span>
        <h1 class="enter" style="--d:0">Alles om klanten terug te laten komen</h1>
        <p class="zn-lead enter" style="--d:1">Stempelkaarten, klantenkaarten met korting, gratis tickets voor je events, kortingsbonnen, actiecodes en acties met andere zaken. In één gratis app, met één scanner.</p>
        <div class="enter" style="--d:1">{_ul(checks, "var(--ink)")}</div>
        <div class="zn-actions enter" style="--d:2">
          <a class="zc-btn" href="{SIGNUP}" data-zk-signup>Gratis aanmelden</a>
        </div>
        <div class="actions zn-hero-badges enter" style="--d:2">{badges_html}</div>
        <p class="zn-login enter" style="--d:3">Al een account? <a href="{LOGIN}" data-zk-login>Log in op het dashboard</a></p>
      </div>
      <div class="zn-hero-panel enter-stage">{fit(stage, 600, 560, "zn-stage")}</div>
    </div>'''


def _product(id_, tag, tag_cls, title, text, bullets, visual, vis_cls):
    pid = f' id="{id_}"' if id_ else ""
    return (f'<div class="zn-prod"{pid}>{fit(visual, 340, 220, "zn-vis " + vis_cls)}'
            f'<span class="zn-tag {tag_cls}">{tag}</span><h3>{title}</h3><p>{text}</p>{_ul(bullets)}</div>')


def products():
    group = "".join(f'<span style="background:{c};--i:{i}">{l}</span>' for i, (c, l) in enumerate(
        [("#E8590C", "K"), ("#0B7285", "C"), ("#7048E8", "B"), ("#2B8A3E", "+")]))
    items = [
        _product("", "Stempelkaart", "t-orange", "Stempelkaart", "Sparen per bezoek, met jouw beloning.",
                 ["2 tot 30 stempels, tot 5 kaarten", "Tussentijdse beloningen"],
                 f'<div class="zn-center" style="--s:.86">{stamp_card("Koffiekaart", "Bakkerij de Korenschoof", "Apeldoorn", "#E8590C", 10, 6, "10 = gratis koffie")}</div>', "v-orange"),
        _product("klantenkaart", "Nieuw · klantenkaart", "t-blue", "Klantenkaart met barcode",
                 "Een eigen ledenkaart. Kies het doel: herkenning, sparen, vaste korting of korting in een periode.",
                 ["QR, Code 128 of EAN-13", "Happy hour of decemberkorting plannen"],
                 f'<div class="zn-center" style="--s:.86">{member_card()}</div>', "v-blue"),
        _product("tickets", "Nieuw · tickets", "t-violet", "Tickets voor gratis events",
                 "Borrel, workshop of open dag: aanmelden met naam, e-mail en geboortedatum, scannen aan de deur.",
                 ["Plekken, wachtlijst en max per persoon", "In Pasr en Apple/Google Wallet"],
                 f'<div class="zn-center" style="--s:.45">{ticket()}</div>', "v-violet"),
        _product("", "Kortingsbon", "t-iris", "Kortingsbon", "Procent of bedrag, minimale besteding, één per klant.",
                 ["Pauzeren of aanpassen kan altijd", "Alleen in Pasr te verzilveren"],
                 f'<div class="zn-center" style="--s:1">{coupon()}</div>', "v-iris"),
        _product("", "Actiecode", "t-green", "Actiecode", "Een eigen code als HERFST20 die klanten aan de kassa noemen.",
                 ["Met limiet en einddatum", "Zie hoe vaak hij gebruikt is"],
                 f'<div class="zn-center" style="--s:1.3">{action_code()}</div>', "v-green"),
        _product("", "Samen", "t-teal", "Gezamenlijke actie", "Spaar samen met andere zaken in je straat of winkelcentrum.",
                 ["Op uitnodiging, jij kiest wie meedoet", "Start pas als genoeg zaken meedoen"],
                 f'<div class="zn-center" style="--s:1"><div class="zn-group">{group}</div></div>', "v-teal"),
    ]
    return f'''    <section class="wrap zn-section" id="maken" aria-labelledby="maken-title">
      <span class="zn-eyebrow">Wat kun je maken</span>
      <h2 id="maken-title" class="zn-h2">Zes manieren om klanten te binden</h2>
      <p class="zn-sub">Begin met één, voeg later toe wat past. Alles komt in hetzelfde dashboard en dezelfde scanner.</p>
      <div class="zn-prods">{"".join(items)}</div>
    </section>'''


def add_button():
    snippet = esc('<a href="https://pasr.nl/add/k/…">\n  <img src="https://pasr.nl/badge/nl/zwart.svg"\n       alt="Voeg toe aan Pasr" height="52">\n</a>')
    return f'''    <section class="wrap zn-addband" id="voeg-toe" aria-labelledby="add-title">
      <div class="zn-add">
        <div class="zn-add-copy">
          <span class="zn-eyebrow light">Nieuw · voor je eigen website</span>
          <h2 id="add-title" class="zn-h2">“Voeg toe aan Pasr” op je site</h2>
          <p>Zet de knop bij je stempelkaart, klantenkaart, event of kortingsbon. Klanten tikken erop, Pasr opent en het staat erin. Ook als QR-code voor op de toonbank en de kassabon.</p>
          <div class="zn-badges"><img src="/badge/nl/wit.svg" alt="Voeg toe aan Pasr (wit)" width="150" height="52"><img src="/badge/nl/nachtblauw.svg" alt="Voeg toe aan Pasr (nachtblauw)" width="150" height="52"></div>
        </div>
        <div class="zn-snippet">
          <pre><code>{snippet}</code></pre>
          <div class="zn-snippet-qr"><span>{qr(11, 21)}</span><span>Of download de QR-code en PNG in je dashboard.</span></div>
        </div>
      </div>
    </section>'''


def _phone(bg, title, sub, extra):
    return (f'<div class="zn-phone"><div class="zn-screen"><span class="zn-island"></span>'
            f'<div class="zn-res" style="background:{bg}"><span class="zn-res-ic">{TICK}</span><b>{title}</b><span>{sub}</span>{extra}</div></div></div>')


def scanner():
    items = ["Stempelkaart: +1 stempel of beloning inwisselen", "Klantenkaart: de korting die nu geldt en de spaarstand",
             "Ticket: groen of rood, met teller wie er binnen is", "Kortingsbon en actiecode: geldig of niet, in één tik",
             "Medewerkers scannen mee; alleen jij beheert"]
    count = '<em class="zn-count"><span class="a">85</span><span class="b">86</span> / 120 binnen</em>'
    phones = [
        _phone("#0A8A5F", "Ticket geldig", "Anna de Vries · Toegang<br>Winterborrel", count),
        _phone("#1B4CB0", "15% korting", "Fietsplus Klantenkaart<br>geldig t/m 15 dec", "<em>Spaarstand 6 / 10</em>"),
        _phone("#D9480F", "+1 stempel", "Koffiekaart · 7 van 10", "<em>Nog 3 tot gratis koffie</em>"),
    ]
    cells = "".join(fit(p, 220, 440, "zn-phonecell") for p in phones)
    return f'''    <section class="zn-band zn-band-green" id="scanner" aria-labelledby="scan-title">
      <div class="wrap zn-scan">
        <div>
          <span class="zn-eyebrow">Aan de toonbank en de deur</span>
          <h2 id="scan-title" class="zn-h2">Eén scanner voor alles</h2>
          <p class="zn-sub">Pasr Zakelijk herkent zelf wat je scant en laat groot zien wat je moet doen.</p>
          {_ul(items)}
        </div>
        <div class="zn-phones">{cells}</div>
      </div>
    </section>'''


_DI = {
    'home': '<path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
    'card': '<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M3 10h18"/>',
    'ticket': '<path d="M3 9.5a2 2 0 0 0 0 4V17a1 1 0 0 0 1 1h16a1 1 0 0 0 1-1v-3.5a2 2 0 0 1 0-4V6a1 1 0 0 0-1-1H4a1 1 0 0 0-1 1z"/>',
    'tag': '<path d="M3 12V4h8l10 10-8 8z"/><circle cx="7.5" cy="8.5" r="1.5"/>',
    'code': '<path d="M8 8l-4 4 4 4M16 8l4 4-4 4"/>',
    'users': '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.6 3.4-5.5 6.5-5.5s5.7 1.9 6.5 5.5"/><circle cx="17" cy="9" r="2.6"/><path d="M17 14.5c2.4 0 4 1.5 4.6 4"/>',
    'chart': '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
    'cal': '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4"/>',
    'pin': '<path d="M12 21s7-6 7-12a7 7 0 0 0-14 0c0 6 7 12 7 12z"/><circle cx="12" cy="9" r="2.5"/>',
    'team': '<circle cx="12" cy="8" r="4"/><path d="M4 21c1-4.5 4.2-7 8-7s7 2.5 8 7"/>',
    'scan': '<path d="M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3M4 12h16"/>',
    'bell': '<path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4z"/><path d="M10 20a2 2 0 0 0 4 0"/>',
    'search': '<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>',
    'down': '<path d="M6 9l6 6 6-6"/>',
}


def _di(n):
    return f'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{_DI[n]}</svg>'


def dashboard(stack_icon):
    groups = [(None, [("home", "Vandaag", True)]),
              ("Klantenbinding", [("card", "Stempelkaarten", False), ("card", "Klantenkaarten", False), ("ticket", "Tickets", False),
                                  ("tag", "Kortingsbonnen", False), ("code", "Actiecodes", False), ("users", "Gezamenlijke acties", False)]),
              ("Groei", [("chart", "Inzichten", False), ("cal", "Marketingkalender", False)]),
              ("Je zaak", [("pin", "Vestigingen", False), ("team", "Medewerkers", False)])]
    side = ""
    for g, items in groups:
        if g:
            side += f"<small>{g}</small>"
        side += "".join(f'<span class="{"on" if on else ""}">{_di(i)}{l}</span>' for i, l, on in items)
    kpis = "".join(f'<span class="znb-kpi"><small>{a}</small><b>{b}</b><em>▲ {c} t.o.v. vorige week</em></span>' for a, b, c in [
        ("Stempels deze week", "412", "+18%"), ("Beloningen", "37", "+6%"), ("Nieuwe leden", "29", "+11%"), ("Terugkerend (90 d)", "64%", "+3 pt")])
    todo = "".join(f'<span class="znb-row"><span class="znb-ic" style="--bg:{bg};--fg:{fg}">{_di(i)}</span><span class="znb-rt"><span>{t}</span><small>{s}</small></span><i>{b}</i></span>'
                   for bg, fg, i, t, s, b in [
                       ("#FFE9DD", "#E8590C", "users", "Uitnodiging: <b>Winterwandeling Hoofdstraat</b>", "Cafe Centraal nodigt je uit · 3 zaken doen mee", "Bekijken"),
                       ("#EFEDFF", "#6A5CFF", "card", "<b>Broodkaart</b> staat nog in concept", "Zet hem online zodat klanten hem kunnen toevoegen", "Online zetten"),
                       ("#E6F8F1", "#087554", "ticket", "<b>Winterborrel</b> morgen: 98/120 aangemeld", "Herinnering gaat vanochtend naar alle gasten", "Bekijken")])
    bars = "".join(f'<i class="zc-bar{" last" if k == 13 else ""}" style="height:{h}%;--d:{k * .08:.2f}s"></i>'
                   for k, h in enumerate((38, 52, 44, 60, 48, 70, 56, 64, 58, 76, 62, 82, 70, 92)))
    mock = f'''<div class="znb">
  <div class="znb-top"><span class="znb-brand"><span class="znb-logo">{stack_icon}</span>pasr<em>Zakelijk</em></span>
    <span class="znb-biz"><span>K</span><span><b>Bakkerij de Korenschoof</b><small>Apeldoorn · 2 vestigingen</small></span>{_di("down")}</span>
    <span class="znb-search">{_di("search")}Zoek een klant, kaart of code…<em>⌘K</em></span>
    <span class="znb-acts"><span class="znb-scanbtn">{_di("scan")}Scannen</span><span class="znb-bell">{_di("bell")}</span><span class="znb-me">L</span></span></div>
  <div class="znb-body"><div class="znb-side">{side}</div>
    <div class="znb-main"><span class="znb-hi"><small>Vrijdag 18 december</small><b>Goedemorgen</b></span>
      <div class="znb-kpis">{kpis}</div>
      <div class="znb-cols"><div class="znb-card"><b class="znb-h">Te doen <em>3</em></b>{todo}</div>
        <div class="znb-card"><b class="znb-h">Stempels <span class="znb-seg"><i>7 d</i><i class="on">30 d</i><i>Jaar</i></span></b><span class="zc-bars znb-bars">{bars}</span><span class="znb-axis"><small>1 nov</small><small>15 nov</small><small>27 nov</small></span></div></div>
    </div></div></div>'''
    return f'''    <section class="wrap zn-section" id="dashboard" aria-labelledby="dash-title">
      <span class="zn-eyebrow">Je dashboard</span>
      <h2 id="dash-title" class="zn-h2">Alles op één plek, ook op je telefoon</h2>
      <p class="zn-sub">Zie elke ochtend wat er speelt: wat er te doen is, hoeveel klanten terugkwamen en wie er voor je event is aangemeld. In de browser, op iPhone, iPad en Android.</p>
      <div class="zn-dashwrap">{fit(mock, 1080, 560, "zn-dash")}</div>
      <p class="zn-dashlink"><a class="zc-pill" href="{LOGIN}" data-zk-login>Inloggen op het dashboard</a></p>
    </section>'''


def wallet():
    stage = (f'<div class="zn-w zn-w-ticket"><div class="zn-tilt" style="--r:-6deg">{ticket()}</div></div>'
             f'<div class="zn-w zn-w-member"><div class="zn-tilt" style="--r:3deg">{member_card()}</div></div>'
             f'<div class="zn-w zn-w-stamp"><div class="zn-tilt" style="--r:-2deg">{stamp_card("Koffiekaart", "Bakkerij de Korenschoof", "Apeldoorn", "#E8590C", 10, 6, "10 = gratis koffie")}</div></div>')
    items = ["Gratis, zonder reclame, voor iPhone en Android", "Tickets van hetzelfde event naast elkaar",
             "Geen app? Sparen en tickets werken ook in de browser"]
    return f'''    <section class="zn-band zn-band-iris" id="wallet" aria-labelledby="wallet-title">
      <div class="wrap zn-wallet">
        {fit(stage, 600, 570, "zn-wstage")}
        <div>
          <span class="zn-eyebrow iris">Voor je klanten</span>
          <h2 id="wallet-title" class="zn-h2">Alles in één wallet</h2>
          <p class="zn-sub">Je klanten bewaren je stempelkaart, klantenkaart, tickets en bonnen in de gratis app Pasr, of in Apple Wallet en Google Wallet. Ze krijgen een herinnering voor je event en een melding als je korting begint, alleen als ze dat willen.</p>
          {_ul(items, "var(--iris-deep)")}
        </div>
      </div>
    </section>'''


def steps():
    s = [("Meld je zaak aan", "Gratis, in een paar minuten. We keuren je zaak meestal binnen een werkdag goed."),
         ("Maak wat je nodig hebt", "Stempelkaart, klantenkaart, event, bon of code, in je eigen logo en kleur."),
         ("Laat klanten het toevoegen", "Zet de knop op je site, de QR-code op de toonbank en scan met Pasr Zakelijk.")]
    lis = "".join(f'<li><span class="zc-num">{i + 1}</span><h3>{a}</h3><p>{b}</p></li>' for i, (a, b) in enumerate(s))
    return f'''    <section class="wrap zn-section" id="zo-werkt-het" aria-labelledby="werkt-title">
      <span class="zn-eyebrow">Zo werkt het</span>
      <h2 id="werkt-title" class="zn-h2">In drie stappen live</h2>
      <ol class="zn-steps">{lis}</ol>
    </section>'''


def faq(items, anchor):
    cards = "".join(f'<div class="zn-q" id="{anchor(q)}"><h3>{q}</h3><p>{a}</p></div>' for q, a in items)
    return f'''    <section class="wrap zn-section" id="faq" aria-labelledby="faq-title">
      <span class="zn-eyebrow">Vragen</span>
      <h2 id="faq-title" class="zn-h2">Veelgestelde vragen</h2>
      <div class="zn-faq">{cards}</div>
    </section>'''


def closer(badges_html):
    return f'''    <section class="wrap zc-closer" id="download" aria-labelledby="cta-title">
      <div>
        <span><h2 id="cta-title">Begin vandaag, gratis</h2><span>Stempelkaart, klantenkaart, tickets en acties. Voor elke zaak.</span></span>
        <span class="zc-closer-actions"><a class="zc-btn light" href="{SIGNUP}" data-zk-signup>Gratis aanmelden</a><a class="zc-pill light" href="{LOGIN}" data-zk-login>Inloggen</a></span>
      </div>
      <div class="actions zc-closer-badges">{badges_html}</div>
    </section>'''


# Schaal voor .zn-fit in browsers zonder tan(atan2()) in CSS (ouder dan 2023): zelfde uitkomst met een paar regels JS.
FIT_FALLBACK = '''  <script>(function(){try{if(CSS.supports("width","calc(tan(atan2(1px, 1px)) * 1px)"))return}catch(e){}
function run(){var els=document.querySelectorAll(".zn-fit");function set(){els.forEach(function(el){var c=el.firstElementChild,w=parseFloat(getComputedStyle(el).getPropertyValue("--fw"))||1;c.style.setProperty("--zs",el.clientWidth/w)})}
set();addEventListener("resize",set)}if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",run);else run()})();</script>'''
