#!/usr/bin/env python3
"""Bouwt pasr.nl/zakelijk: de landingspagina voor ondernemers (in de stijl van de home) en de app-pagina's
(dashboard, scanner, kaart, flyer, uitnodiging) met dezelfde kop en voet. Zet ook de kop van /zakelijk/download/ gelijk.

Wordt aangeroepen door tools/make_website.py (de Website-workflow bouwt de site bij elke deploy en elk uur opnieuw).
Los draaien kan ook: python3 tools/make_zakelijk.py

Een functie toevoegen aan de landingspagina: zet een regel in FEATURES (icoon, kleur, titel, tekst, breedte, beeld).
- breedte: 2, 3 of 4 van de 6 kolommen. Elke rij telt op tot 6; volgt op een rij 4+2 een rij 2+4, dan sluit ook het
  tablet-raster. check_layout() waarschuwt bij het bouwen als het niet sluit (de pagina wordt toch gebouwd).
- beeld: een sleutel uit VISUALS (bewegend plaatje boven in de kaart) of None voor een kaart zonder beeld.
- icoon: een sleutel uit ICONS. Nieuwe iconen: 24x24, lijnen (stroke), zoals de bestaande.
Voorbeelddata is altijd verzonnen en neutraal (Koffiebar De Hoek, jouwzaak.nl); nooit echte zaken.
"""
import json
import re
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "website"
ZK = ROOT / "zakelijk"

APP_ID = "6837907454"                       # Pasr Zakelijk in de App Store
APP_URL = f"https://apps.apple.com/nl/app/pasrzakelijk/id{APP_ID}"
PASR_APP_ID = "6829229123"                  # Pasr (voor klanten), alleen op de kaartpagina van de klant
BADGE_IMG = "https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/nl-nl?releaseDate=1794096000"

# Voorbeeldzaak op de pagina (verzonnen)
DEMO = dict(business="Koffiebar De Hoek", city="Apeldoorn", card="Koffiekaart", color="#7B4B2A", total=10,
            reward="1 gratis koffie", site="jouwzaak.nl")

ICONS = {
    "stamp": '<circle cx="7" cy="8" r="2.4"/><circle cx="12" cy="8" r="2.4"/><circle cx="17" cy="8" r="2.4"/><circle cx="7" cy="15" r="2.4"/><path d="M10.3 15.2l1.4 1.4 2.8-2.8M18.5 13v4h-3"/><rect x="2.5" y="4" width="19" height="16" rx="3"/>',
    "palette": '<path d="M12 3a9 9 0 1 0 0 18c1.2 0 1.8-.9 1.5-1.9-.3-1 .3-2.1 1.5-2.1H17a4 4 0 0 0 4-4c0-5.5-4-10-9-10z"/><circle cx="7.5" cy="11" r="1.2"/><circle cx="10" cy="7" r="1.2"/><circle cx="14.5" cy="7" r="1.2"/>',
    "scan": '<path d="M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3M8 8h3v3H8zM13 13h3v3h-3zM13 8h3M8 16h3"/>',
    "chart": '<path d="M4 4v16h16"/><path d="M7 15c2-4 3.5-6 5-4s3 3 4.5-1 2-4 2.5-5"/>',
    "users": '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.6 3.4-5.5 6.5-5.5s5.7 1.9 6.5 5.5M16 4.8a3.5 3.5 0 0 1 0 6.4M18.5 14.8c1.6.9 2.6 2.6 3 5.2"/>',
    "shield": '<path d="M12 3l7 3v5c0 4.5-3 8.3-7 10-4-1.7-7-5.5-7-10V6z"/><path d="M9 12l2 2 4-4"/>',
    "search": '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>',
    "bell": '<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20a2 2 0 0 0 4 0"/>',
    "print": '<path d="M7 9V3h10v6M7 18H4v-7h16v7h-3M7 14h10v7H7z"/>',
    "free": '<path d="M20 12v8H4v-8M2 7h20v5H2zM12 22V7M12 7c-1.5-3-5-3-5-1s3 1 5 1c2 0 5 1 5-1s-3.5-2-5 1"/>',
    "lock": '<path d="M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3M12 15v2"/>',
    "web": '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18M7 6.5h.01M10 6.5h.01"/>',
    "check": '<path d="M5 12.5l4.2 4.2L19 7"/>',
}


def icon(name, cls=""):
    c = f' class="{cls}"' if cls else ""
    return (f'<svg{c} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" '
            f'stroke-linejoin="round" aria-hidden="true">{ICONS[name]}</svg>')


def anchor(text):
    """Leesbaar #-adres: "Kost Pasr Zakelijk geld?" -> "kost-pasr-zakelijk-geld"."""
    t = unicodedata.normalize("NFKD", re.sub(r"<[^>]+>", "", text)).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", t).strip("-")[:60]


def mix(hex_colour, to, part):
    """Kleur mengen met wit (to=255) of zwart (to=0), zoals mixHex in zakelijk.js."""
    out = "#"
    for i in (1, 3, 5):
        v = round(int(hex_colour[i:i + 2], 16) * (1 - part) + to * part)
        out += f"{v:02x}"
    return out


CUP = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" '
       'stroke-linejoin="round" aria-hidden="true"><path d="M4 9h12v5a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5zM16 10h1.5a2.5 2.5 0 0 1 0 5H16M8 3v3M12 3v3"/></svg>')
TICK = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" '
        'stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5 10 17 19 7"/></svg>')
GIFT = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" '
        'stroke-linejoin="round" aria-hidden="true"><rect x="3" y="8" width="18" height="13" rx="2"/><path d="M12 8v13M3 12h18M12 8S10.5 3 7.5 4.5 9 8 12 8zm0 0s1.5-5 4.5-3.5S15 8 12 8z"/></svg>')


def stamp_card(on, total=DEMO["total"], new=(), cls=""):
    """De stempelkaart zoals in zakelijk.js (stampCard), met `on` gezette stempels; `new` = stempels die erbij ploppen."""
    c = DEMO["color"]
    bg = f"linear-gradient(135deg, {mix(c, 255, .16)}, {c} 55%, {mix(c, 0, .22)})"
    stamps = ""
    for i in range(total):
        is_on, is_new, last = i < on, i in new, i == total - 1
        k = "sc-stamp" + (" on" if is_on else "") + (" zk-new" if is_new else "") + (" gift" if last and not is_on and not is_new else "")
        inner = TICK if (is_on or is_new) else (GIFT if last else "")
        stamps += f'<span class="{k}" style="--i:{i}">{inner}</span>'
    cols = 5 if total <= 10 else 6
    return (f'<div class="sc {cls}" style="--c:{c};background:{bg};--cols:{cols}">'
            f'<div class="sc-head"><span class="sc-logo">{CUP}</span><span class="sc-title"><span class="sc-name">{DEMO["card"]}</span>'
            f'<span class="sc-biz">{DEMO["business"]} · {DEMO["city"]}</span></span><span class="sc-kind">Stempelkaart</span></div>'
            f'<div class="sc-stamps">{stamps}</div>'
            f'<div class="sc-reward"><span>{DEMO["reward"]}</span><span>{total - on} te gaan</span></div></div>')


# ---------------------------------------------------------------------------------------------------- functies
# (icoon, kleur, titel, tekst, breedte in kolommen van 6, beeld). Zie de uitleg bovenaan.
FEATURES = [
    ("stamp", "#6A5CFF", "Je stempelkaart in een minuut",
     "Kies een naam, hoeveel stempels er op de kaart gaan (2 tot 30) en wat je klant ervoor krijgt, zoals een gratis koffie. "
     "Je ziet meteen hoe de kaart eruitziet: leeg, half vol en vol. Tot 5 kaarten per zaak.", 4, "designer"),
    ("palette", "#FF6B57", "Huisstijl van je website",
     "Vul je website in en Pasr neemt je logo en kleur over. Klopt iets niet? Je past alles zelf aan.", 2, "brand"),
    ("scan", "#12A77E", "Scannen met je telefoon",
     "Scan de code van je klant met Pasr Zakelijk of in de browser. Je kiest zelf hoeveel stempels erbij komen. "
     "Per ongeluk? Binnen 2 minuten maak je het ongedaan.", 2, "scan"),
    ("chart", "#6A5CFF", "Overzicht met grafieken",
     "Stempels, beloningen en nieuwe leden per week, maand, kwartaal of jaar, en vergelijk met de periode ervoor. "
     "Per kaart zie je hoeveel leden je hebt.", 4, "insights"),
    ("users", "#0A84FF", "Medewerkers met een eigen inlog",
     "Nodig je team uit met een link. Medewerkers kunnen alleen scannen; kaarten, instellingen en het logboek blijven van jou. "
     "Toegang intrekken kan altijd.", 3, "staff"),
    ("shield", "#17162A", "Afkoeltijd en logboek tegen misbruik",
     "Na een stempel krijgt dezelfde klant even geen nieuwe, en je kiest het maximum per scan. Elke stempel staat in een "
     "logboek met wie, wat en wanneer. Wissen kan niemand, ook jij niet.", 3, "guard"),
    ("search", "#FF6B57", "Vindbaar in Pasr",
     "Klanten zoeken in de app Pasr op naam of plaats en zien je stempelkaart bij In de buurt. Ze voegen hem toe met één tik. "
     "Liever niet in de lijst? Zet het uit.", 4, "findable"),
    ("bell", "#12A77E", "Een melding bij elke stempel",
     "Heeft je klant de app Pasr, dan komt de stempel er meteen bij, ook op de Wallet-pas, met een melding.", 2, "push"),
    ("print", "#E2683C", "Printbare flyer",
     "Een A4 met je kaart en QR-code voor op de toonbank of het raam. Printen of bewaren als PDF.", 2, "flyer"),
    ("free", "#12A77E", "Gratis",
     "Geen abonnement, geen kosten per stempel en geen kassakoppeling. Je telefoon is genoeg.", 2, "free"),
    ("lock", "#6A5CFF", "Privacy voor je klanten",
     "Klanten sparen met een anonieme klantcode. Pasr vraagt geen naam, e-mailadres of telefoonnummer; jij ziet alleen "
     "de laatste tekens van de code en de stempels.", 2, "privacy"),
]


def v_designer():
    return ('<div class="fv zv-designer" aria-hidden="true"><div class="zv-form">'
            '<span class="zv-field"><small>Naam</small><b class="zv-type">Koffiekaart</b></span>'
            '<span class="zv-field"><small>Beloning</small><b>1 gratis koffie</b></span>'
            '<span class="zv-slider"><small>Stempels</small><i><em></em></i><b>10</b></span></div>'
            f'<div class="zv-preview">{stamp_card(0, new=tuple(range(9)), cls="zv-mini")}</div></div>')


def v_brand():
    return ('<div class="fv zv-brand" aria-hidden="true"><span class="zv-url">' + icon("web") + DEMO["site"] + '</span>'
            '<span class="zv-arrow"></span><span class="zv-result"><span class="zv-logo">' + CUP + '</span>'
            '<span class="zv-sw"><i style="background:#7B4B2A"></i>#7B4B2A</span></span></div>')


def v_scan():
    return ('<div class="fv zv-scan" aria-hidden="true"><span class="zv-step"><b>−</b><span><i>1</i><i>2</i><i>3</i></span><b>+</b></span>'
            '<span class="zv-go">' + TICK + '<span>3 stempels erbij</span></span>'
            '<span class="zv-undo">Ongedaan maken · 1:59</span></div>')


def v_insights():
    # vloeiende lijn met verloopvlak en gestippeld raster, zoals Homey Insights (en het web-dashboard)
    pts = [4, 6, 5, 9, 7, 11, 10, 14, 12, 17, 15, 19, 18, 22]
    w, h = 300, 110
    xy = [(round(i * w / (len(pts) - 1), 1), round(h - v * h / 25, 1)) for i, v in enumerate(pts)]
    d = f"M{xy[0][0]} {xy[0][1]}"
    for i in range(1, len(xy)):
        p0, p1 = xy[i - 1], xy[i]
        cx = round((p0[0] + p1[0]) / 2, 1)
        d += f" C{cx} {p0[1]} {cx} {p1[1]} {p1[0]} {p1[1]}"
    grid = "".join(f'<line x1="0" x2="{w}" y1="{y}" y2="{y}"/>' for y in (22, 55, 88))
    sel = xy[10]
    return ('<div class="fv zv-insights" aria-hidden="true"><div class="zv-ihead"><span class="zv-pill">' + icon("stamp") + 'Stempels</span>'
            '<span class="zv-total"><b>184</b> stempels</span></div>'
            f'<svg class="zv-chart" viewBox="0 0 {w} {h}" preserveAspectRatio="none"><defs><linearGradient id="zvg" x1="0" x2="0" y1="0" y2="1">'
            '<stop offset="0" stop-color="#2ED3A6" stop-opacity=".38"/><stop offset="1" stop-color="#2ED3A6" stop-opacity="0"/></linearGradient></defs>'
            f'<g class="zv-grid">{grid}</g><path class="zv-area" d="{d} L{w} {h} L0 {h} Z" fill="url(#zvg)"/>'
            f'<path class="zv-line" d="{d}" pathLength="1"/><line class="zv-rule" x1="{sel[0]}" x2="{sel[0]}" y1="0" y2="{h}"/>'
            "</svg>"
            '<span class="zv-seg"><i>W</i><i class="on">M</i><i>K</i><i>J</i></span></div>')


def v_staff():
    rows = [("S", "#6A5CFF", "Sanne", "Eigenaar", "own"), ("T", "#0A84FF", "Tim", "Medewerker", "ok"),
            ("A", "#FF6B57", "Aïsha", "Uitnodiging open", "wait")]
    items = "".join(f'<li style="--i:{i}"><span class="av" style="background:{c}">{a}</span><b>{n}</b><em class="{k}">{r}</em></li>'
                    for i, (a, c, n, r, k) in enumerate(rows))
    return f'<div class="fv zv-staff" aria-hidden="true"><ul>{items}</ul></div>'


def v_guard():
    rows = [("10:42", "2 stempels", "Tim"), ("10:39", "Beloning", "Sanne"), ("10:31", "1 stempel", "Tim")]
    items = "".join(f'<li style="--i:{i}"><time>{t}</time><b>{w}</b><span>{p}</span></li>' for i, (t, w, p) in enumerate(rows))
    return ('<div class="fv zv-guard" aria-hidden="true"><span class="zv-cool">' + icon("shield") + 'Afkoeltijd <b>4:59</b></span>'
            f'<ul>{items}</ul></div>')


def v_findable():
    rows = [("#7B4B2A", "Koffiebar De Hoek", "Koffiekaart · 350 m"), ("#E2683C", "Bakkerij Het Plein", "Broodkaart · 1,2 km")]
    items = "".join(f'<li style="--i:{i}"><span class="lg" style="background:{c}"></span><span class="t"><b>{n}</b>{s}</span><i>+</i></li>'
                    for i, (c, n, s) in enumerate(rows))
    return ('<div class="fv zv-find" aria-hidden="true"><span class="zv-search">' + icon("search") + '<span class="zv-q">koffie</span></span>'
            f'<span class="zv-near">In de buurt</span><ul>{items}</ul></div>')


def v_push():
    return ('<div class="fv zv-push" aria-hidden="true"><span class="nt"><img src="/assets/icon.png" alt="">'
            f'<span><b>{DEMO["business"]}</b>+1 stempel · nog 2 tot {DEMO["reward"]}</span></span></div>')


def v_flyer():
    qr = "".join(f'<i style="grid-area:{1 + k // 7}/{1 + k % 7}"></i>' for k in range(49)
                 if (k in (0, 1, 2, 7, 9, 14, 15, 16, 4, 5, 6, 11, 13, 18, 19, 20, 28, 29, 30, 35, 37, 42, 43, 44)) or (k * 5 + k // 4) % 3 == 0)
    return ('<div class="fv zv-flyer" aria-hidden="true"><span class="zv-a4"><small>Spaar bij</small><b>De Hoek</b>'
            f'<span class="zv-qr">{qr}</span><em>Scan met je camera</em></span></div>')


def v_free():
    return '<div class="fv zv-free" aria-hidden="true"><b>€ 0</b><span>per maand · per stempel · per kaart</span></div>'


def v_privacy():
    return ('<div class="fv zv-privacy" aria-hidden="true"><span class="zv-code">PZ<i>••••••••••</i>7K3Q</span>'
            '<span class="zv-chips"><s>Naam</s><s>E-mail</s><s>Telefoon</s></span></div>')


VISUALS = {"designer": v_designer, "brand": v_brand, "scan": v_scan, "insights": v_insights, "staff": v_staff,
           "guard": v_guard, "findable": v_findable, "push": v_push, "flyer": v_flyer, "free": v_free, "privacy": v_privacy}


def feature_card(name, color, title, text, span, visual):
    dark = " dark" if color == "#17162A" else ""
    vis = VISUALS[visual]() if visual in VISUALS else ""
    return (f'''      <article class="feature span{span}{dark}{" has-visual" if vis else ""}" id="{anchor(title)}">
        {vis}
        <div class="chip" style="--c:{color}">{icon(name)}</div>
        <h3>{title}</h3>
        <p>{text}</p>
      </article>''')


def check_layout(features):
    """Waarschuwt als het bento-raster gaten krijgt (desktop: 6 kolommen, tablet: 2). Bouwt de pagina toch."""
    problems, row = [], 0
    for _, _, title, _, span, _ in features:
        if span not in (2, 3, 4):
            problems.append(f"'{title}': breedte {span} (kies 2, 3 of 4)")
        row += span
        if row > 6:
            problems.append(f"'{title}' past niet meer in de rij (samen {row} van 6)")
            row = span
        elif row == 6:
            row = 0
    if row:
        problems.append(f"de laatste rij telt {row} van 6 kolommen")
    tablet = 0
    for f in features:
        w = 2 if f[4] == 4 else 1
        if tablet == 1 and w == 2:
            problems.append(f"op een tablet blijft een gat voor '{f[2]}' (zet hem na een kaart met dezelfde breedte)")
            tablet = 0
        tablet = (tablet + w) % 2
    if tablet:
        problems.append("op een tablet blijft de laatste rij half leeg")
    for p in problems:
        print("LET OP (make_zakelijk FEATURES):", p)
    return not problems


# ---------------------------------------------------------------------------------------------------- vergelijking
COMPARE = [  # (papier, pasr)
    ("Kwijt of vergeten", "Het papiertje zit in een andere jas, of in de wasmachine.",
     "Altijd bij de hand", "In de app Pasr, op de Wallet-pas of in de browser van je klant."),
    ("Na te maken", "Een stempel of een pen is zo gekocht.",
     "Alleen jij zet stempels", "Jij en je medewerkers, met afkoeltijd, een maximum per scan en een logboek."),
    ("Geen idee wat het oplevert", "Hoeveel klanten sparen er eigenlijk?",
     "Je ziet het terug", "Leden, stempels en beloningen per dag, in grafieken."),
    ("Drukwerk bijbestellen", "En opnieuw als je de beloning verandert.",
     "Gratis en meteen aangepast", "Pas je kaart aan wanneer je wilt; je klanten zien het meteen."),
]
TABLE_COLS = ["Pasr Zakelijk", "Papieren kaart"]
TABLE = [
    ("Gratis", "y", "Drukwerk"),
    ("Geen kassakoppeling nodig", "y", "y"),
    ("Je eigen logo en kleur", "y", "y"),
    ("Klant heeft hem altijd bij zich", "y", "n"),
    ("Werkt ook zonder app, in de browser", "y", "-"),
    ("Niet na te maken", "y", "n"),
    ("Afkoeltijd en maximum per scan", "y", "n"),
    ("Logboek: wie gaf welke stempel", "y", "n"),
    ("Medewerkers met een eigen inlog", "y", "-"),
    ("Stempel ongedaan maken", "y", "n"),
    ("Overzicht met grafieken", "y", "n"),
    ("Melding bij je klant na een stempel", "y", "n"),
    ("Vindbaar voor nieuwe klanten", "y", "n"),
]


def feature_table():
    yes = '<span class="ft-y" aria-label="Ja"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.2 4.2L19 7" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg></span>'
    no = '<span class="ft-n" aria-label="Nee"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 7l10 10M17 7L7 17" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/></svg></span>'

    def cell(v):
        return {"y": yes, "n": no, "-": '<span class="ft-d" aria-label="Niet van toepassing">–</span>'}.get(v, f'<span class="ft-s">{v}</span>')
    head = "".join(f'<th scope="col"{" class=\"ft-pasr\"" if i == 0 else ""}>{c}</th>' for i, c in enumerate(TABLE_COLS))
    rows = "\n".join(f'            <tr style="--r:{i}"><th scope="row">{r[0]}</th>'
                     + "".join(f'<td{" class=\"ft-pasr\"" if k == 0 else ""}>{cell(v)}</td>' for k, v in enumerate(r[1:])) + "</tr>"
                     for i, r in enumerate(TABLE))
    return f'''        <div class="ft-wrap zk-ft" id="vergelijking">
          <h3 class="ft-title">Naast elkaar</h3>
          <table class="ft">
            <thead><tr><th scope="col"><span class="sr-only">Functie</span></th>{head}</tr></thead>
            <tbody>
{rows}
            </tbody>
          </table>
          <p class="ft-note">– betekent niet van toepassing.</p>
        </div>'''


# ---------------------------------------------------------------------------------------------------- vragen
FAQ = [
    ("Wat kost Pasr Zakelijk?", "Niets. Pasr Zakelijk is gratis: geen abonnement, geen kosten per stempel of per klant en geen reclame op je kaart."),
    ("Heb ik een kassakoppeling of apparaat nodig?", "Nee. Je scant de code van je klant met de app Pasr Zakelijk op je iPhone, iPad of Android-telefoon, of met de scanner op pasr.nl in elke browser met een camera."),
    ("Moeten mijn klanten de app Pasr hebben?", "Nee. Met de gratis app Pasr (iPhone, Android) staat de kaart in de app en op hun Wallet-pas en krijgen ze een melding bij een stempel. Zonder app werkt de kaart in de browser: je klant scant de QR-code bij de toonbank en bewaart de kaart in zijn browser."),
    ("Hoe voorkom ik dat iemand zelf stempels zet?", "Alleen jij en je medewerkers zetten stempels, nooit de klant. Met de afkoeltijd krijgt dezelfde klant na een stempel een tijdje geen nieuwe, en je kiest het maximum per scan. Elke stempel staat met wie, wat en wanneer in een logboek dat niemand kan wissen."),
    ("Kan ik een stempel terugdraaien?", "Ja. Binnen 2 minuten maak je de laatste stempel of inwisseling ongedaan. Het staat daarna doorgestreept in het logboek."),
    ("Wat gebeurt er als een kaart vol is?", "Dan wissel je bij de volgende scan de beloning in. Kwamen er meer stempels bij dan er op de kaart passen, dan blijven die staan voor de volgende ronde."),
    ("Kan ik mijn zaak ook in de browser beheren?", "Ja. Log in op pasr.nl/zakelijk met hetzelfde Pasr-account als in de app. Je maakt en bewerkt er kaarten, scant, nodigt medewerkers uit, past je instellingen aan en bekijkt je overzicht en logboek."),
    ("Welke gegevens van mijn klanten zie ik?", "Alleen de laatste tekens van hun anonieme klantcode, hun stempels en beloningen. Pasr vraagt je klanten geen naam, e-mailadres of telefoonnummer."),
    ("Hoe lang duurt het aanmelden?", "Een account maken en je zaak aanmelden kost een paar minuten. We keuren elke zaak met de hand goed, meestal binnen een werkdag. In de tussentijd ontwerp je je kaart al."),
    ("Kan ik meerdere zaken beheren?", "Met één Pasr-account ben je eigenaar van één zaak, met tot 5 stempelkaarten. Daarnaast kun je medewerker zijn bij andere zaken. In het dashboard en in de app wissel je bovenin van zaak."),
    ("Op welke apparaten werkt Pasr Zakelijk?", "De app Pasr Zakelijk werkt op iPhone en iPad met iOS 17 of nieuwer en op Android 8 of nieuwer (download op pasr.nl/zakelijk/download). Het dashboard en de scanner werken in elke moderne browser."),
]


# ---------------------------------------------------------------------------------------------------- kop en voet
def header(active=""):
    """Kop van alle /zakelijk-pagina's: Inloggen en Aanmelden altijd zichtbaar, ook op een telefoon."""
    links = [("functies", "/zakelijk/#functies", "Functies"), ("werkt", "/zakelijk/#zo-werkt-het", "Zo werkt het"),
             ("faq", "/zakelijk/#faq", "Vragen"), ("klanten", "/", "Pasr voor klanten")]
    li = "".join(f'<li class="zk-l"><a href="{h}">{t}</a></li>' for _, h, t in links)
    cur = ' aria-current="page"' if active == "dashboard" else ""
    return f'''  <header class="wrap nav zk-nav">
    <a class="brand" href="/zakelijk/" aria-label="Pasr Zakelijk"><img src="/assets/icon.png" alt="" width="36" height="36"><span>pasr</span><em class="zk-tag">Zakelijk</em></a>
    <nav aria-label="Hoofdmenu">
      <ul>
        {li}
        <li><a class="nav-btn ghost" href="/zakelijk/dashboard/" data-zk-login{cur}>Inloggen</a></li>
        <li><a class="nav-btn" href="/zakelijk/dashboard/#account" data-zk-signup>Aanmelden</a></li>
      </ul>
    </nav>
  </header>'''


FOOTER = '''  <footer>
    <div class="wrap">
      <span>&copy; 2026 Pasr</span>
      <nav aria-label="Voettekst">
        <a href="/zakelijk/">Voor ondernemers</a>
        <a href="/zakelijk/dashboard/">Inloggen</a>
        <a href="/zakelijk/download/">Pasr Zakelijk voor Android</a>
        <a href="/">Pasr voor klanten</a>
        <a href="/privacy/#stempelkaarten-van-ondernemers">Privacy</a>
        <a href="/privacy/#cookies" data-consent-open>Cookie-instellingen</a>
        <a href="/support/">Support</a>
      </nav>
    </div>
  </footer>'''

ANDROID_SVG = '<svg viewBox="0 0 24 24" aria-hidden="true"><g fill="#2ED3A6"><path d="M6.2 9.3a5.8 5.8 0 0 1 11.6 0z"/><path d="M8.3 4.4 7 2.4M15.7 4.4 17 2.4" stroke="#2ED3A6" stroke-width=".9" stroke-linecap="round"/><path d="M6.2 10h11.6v7.6a1.4 1.4 0 0 1-1.4 1.4H7.6a1.4 1.4 0 0 1-1.4-1.4z"/><rect x="3.4" y="10" width="2.1" height="6.6" rx="1.05"/><rect x="18.5" y="10" width="2.1" height="6.6" rx="1.05"/><rect x="8.4" y="17.6" width="2.1" height="4.4" rx="1.05"/><rect x="13.5" y="17.6" width="2.1" height="4.4" rx="1.05"/></g><circle cx="9.4" cy="7.1" r=".65" fill="#000"/><circle cx="14.6" cy="7.1" r=".65" fill="#000"/></svg>'


def badges(lazy=False):
    """App Store-badge (Pasr Zakelijk) en de Android-badge (naar /zakelijk/download/), even groot naast elkaar."""
    ld = ' loading="lazy"' if lazy else ""
    return (f'<a class="store-badge" href="{APP_URL}?itscg=30200&amp;itsct=apps_box_badge&amp;mttnsubad={APP_ID}" rel="noopener">'
            f'<img src="{BADGE_IMG}" alt="Pasr Zakelijk: download in de App Store" width="246" height="82"{ld}></a>'
            f'<a class="android-badge" href="/zakelijk/download/" aria-label="Download Pasr Zakelijk voor Android">{ANDROID_SVG}'
            '<span><small>Download for</small>Android</span></a>')


def head(title, desc, url, *, app_id=APP_ID, robots="noindex, nofollow", og_title=None, og_image="https://pasr.nl/og/home.png",
         extra="", referrer=True):
    return f'''<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="apple-itunes-app" content="app-id={app_id}">
  <title>{title}</title>
  <meta name="description" content="{desc}">
  <meta name="robots" content="{robots}">
{'  <meta name="referrer" content="no-referrer">' + chr(10) if referrer else ''}  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Pasr">
  <meta property="og:url" content="{url}">
  <meta property="og:title" content="{og_title or title}">
  <meta property="og:description" content="{desc}">
  <meta property="og:image" content="{og_image}">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:locale" content="nl_NL">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:image" content="{og_image}">
  <meta name="theme-color" content="#F4F3FF">
  <link rel="icon" type="image/png" href="/assets/favicon.png">
  <link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
  <link rel="manifest" href="/site.webmanifest">
  <script src="/assets/consent.js" defer></script>
  <link rel="stylesheet" href="/assets/style.css">
  <link rel="stylesheet" href="/assets/zakelijk.css">
{extra}</head>'''


# App-pagina's: (map, titel, beschrijving, og-titel, data-page, main, scripts, app-id, actief)
SCRIPTS = '''  <script src="/assets/account-config.js"></script>
  <script src="/assets/vendor/qrcode.js"></script>
{jsqr}  <script src="/assets/zakelijk.js"></script>'''
JSQR = '  <script src="/assets/vendor/jsqr.min.js"></script>\n'
APP_PAGES = [
    ("dashboard", "Dashboard | Pasr voor ondernemers", "Beheer de stempelkaarten van je zaak.", "Dashboard", "zk-dashboard",
     '<main class="wrap zk-dash" id="zk-app" aria-live="polite"><p class="zk-empty">Laden…</p></main>', True, APP_ID, "dashboard"),
    ("scan", "Scanner | Pasr voor ondernemers", "Scan de stempelkaart van je klant.", "Scanner", "zk-scan",
     '<main class="wrap zk-scan" id="zk-scan" aria-live="polite"><p class="zk-empty">Laden…</p></main>', True, APP_ID, ""),
    ("kaart", "Stempelkaart | Pasr", "Spaar stempels bij deze zaak met Pasr of in je browser.", "Stempelkaart", "zk-join",
     '<main class="wrap zk-join" id="zk-join" aria-live="polite"><p class="zk-empty">Laden…</p></main>', False, PASR_APP_ID, ""),
    ("flyer", "Flyer | Pasr voor ondernemers", "Printbare flyer met de QR-code van je stempelkaart.", "Flyer", "zk-flyer",
     '<main class="wrap" id="zk-flyer"><p class="zk-empty">Laden…</p></main>', False, APP_ID, ""),
    ("uitnodiging", "Uitnodiging | Pasr Zakelijk", "Je bent uitgenodigd om stempels te geven met Pasr Zakelijk.", "Uitnodiging", "zk-invite",
     '<main class="wrap zk-dash" id="zk-app" aria-live="polite"><p class="zk-empty">Laden…</p></main>', False, APP_ID, ""),
]


def app_page(folder, title, desc, og_title, data_page, main, jsqr, app_id, active):
    return (head(title, desc, f"https://pasr.nl/zakelijk/{folder}/", app_id=app_id, og_title=og_title)
            + f'\n<body data-page="{data_page}">\n{header(active)}\n  {main}\n{FOOTER}\n'
            + SCRIPTS.format(jsqr=JSQR if jsqr else "") + "\n</body>\n</html>\n")


# ---------------------------------------------------------------------------------------------------- landingspagina
def hero_phone():
    """De app Pasr Zakelijk na een scan: twee stempels erbij, melding, en Ongedaan maken loopt af."""
    return f'''        <div class="phone zk-phone" aria-label="Voorbeeld: de app Pasr Zakelijk na het scannen van een klant">
          <div class="screen">
            <div class="statusbar" aria-hidden="true"><span>9:41</span><span>●●●</span></div>
            <div class="island" aria-hidden="true"></div>
            <div class="zp" aria-hidden="true">
              <div class="zp-top"><b>Scannen</b><span>{DEMO["business"]}</span></div>
              {stamp_card(7, new=(7, 8), cls="zp-card")}
              <p class="zp-count"><span class="a">7</span><span class="b">9</span> van {DEMO["total"]} stempels</p>
              <div class="zp-step"><b>−</b><span>2</span><b>+</b></div>
              <div class="zp-btn">{TICK}2 stempels erbij</div>
              <div class="zp-undo">Ongedaan maken · <span>1:59</span></div>
              <div class="zp-toast">{TICK}2 stempels gezet</div>
            </div>
          </div>
        </div>
        <div class="zk-note" aria-hidden="true"><img src="/assets/icon.png" alt=""><span><b>{DEMO["business"]}</b>+2 stempels · nog 1 tot {DEMO["reward"]}</span></div>'''


def web_section():
    """Het web-dashboard in een browservenster: alles wat de app kan, ook op pasr.nl."""
    tabs = "".join(f'<i class="{"on" if i == 0 else ""}">{t}</i>' for i, t in enumerate(["Overzicht", "Kaarten", "Scannen", "Medewerkers", "Instellingen"]))
    bars = [3, 5, 4, 7, 6, 9, 8, 11, 9, 12, 10, 14]
    pts = " ".join(f"{round(i * 100 / (len(bars) - 1), 1)},{round(60 - v * 4, 1)}" for i, v in enumerate(bars))
    ticks = "".join(f"<li>{icon('check')}<span>{t}</span></li>" for t in [
        "Kaarten maken, bewerken en online zetten, met QR-code, link en flyer",
        "Scannen met de camera van je laptop of telefoon, of de code typen",
        "Medewerkers uitnodigen en toegang intrekken",
        "Afkoeltijd, maximum per scan, adres en Vindbaar in Pasr instellen",
        "Grafieken, leden en het logboek bekijken"])
    return f'''    <section class="wrap zk-web" id="in-je-browser" aria-labelledby="web-title">
      <div class="zk-web-grid">
        <div>
          <div class="section-head">
            <h2 id="web-title">Ook gewoon in je browser</h2>
            <p>Achter de toonbank met de app, op kantoor op je laptop. Log in op pasr.nl/zakelijk met hetzelfde account en beheer je zaak volledig.</p>
          </div>
          <ul class="ticks zk-ticks">{ticks}</ul>
          <div class="actions"><a class="btn btn-primary" href="/zakelijk/dashboard/">Inloggen</a><a class="btn btn-ghost" href="/zakelijk/dashboard/#account">Gratis aanmelden</a></div>
        </div>
        <div class="zk-browser" aria-hidden="true">
          <div class="zb-bar"><span></span><span></span><span></span><em>pasr.nl/zakelijk/dashboard</em></div>
          <div class="zb-body">
            <div class="zb-head"><span class="zb-logo">{CUP}</span><b>{DEMO["business"]}</b><em>Goedgekeurd</em></div>
            <div class="zb-tabs">{tabs}</div>
            <div class="zb-kpis"><span><small>Stempels</small><b>184</b></span><span><small>Beloningen</small><b>17</b></span><span><small>Leden</small><b>62</b></span></div>
            <div class="zb-chart"><svg viewBox="0 0 100 60" preserveAspectRatio="none"><polyline points="0,60 {pts} 100,60" class="a"/><polyline points="{pts}" class="l"/></svg></div>
          </div>
        </div>
      </div>
    </section>'''


def page():
    check_layout(FEATURES)
    features = "\n".join(feature_card(*f) for f in FEATURES)
    compare = "\n".join(f'          <div><strong>{a}</strong>{b}</div>\n          <div><strong>{c}</strong>{d}</div>' for a, b, c, d in COMPARE)
    faq = "\n".join(f'''      <details id="{anchor(q)}">
        <summary>{q}</summary>
        <p>{a}</p>
      </details>''' for q, a in FAQ)
    faq_ld = ",".join('{"@type":"Question","name":%s,"acceptedAnswer":{"@type":"Answer","text":%s}}' % (json.dumps(q), json.dumps(a)) for q, a in FAQ)
    desc = ("Gratis digitale stempelkaart voor je zaak. Stempelen met de app Pasr Zakelijk op iPhone, iPad of Android, "
            "of gewoon in je browser. Klanten sparen in Pasr of hun browser.")
    og_alt = "Twee digitale stempelkaarten van een koffiebar en een bakkerij, naast de tekst: Gratis digitale stempelkaart voor je zaak"
    feature_list = json.dumps([re.sub(r"<[^>]+>", "", f[2]) for f in FEATURES], ensure_ascii=False)
    steps = [("Meld je zaak aan", "Maak een gratis Pasr-account en meld je zaak aan. We keuren hem met de hand goed, meestal binnen een werkdag."),
             ("Ontwerp je kaart", "Logo en kleur komen van je website. Kies het aantal stempels en de beloning, en zet de kaart online."),
             ("Hang de QR-code op en scan", "Klanten scannen de QR-code of de flyer bij de toonbank. Jij scant hun kaart en kiest hoeveel stempels erbij komen.")]
    steps_html = "".join(f"<li><h3>{a}</h3><p>{b}</p></li>" for a, b in steps)
    return f'''<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="apple-itunes-app" content="app-id={APP_ID}">
  <title>Pasr voor ondernemers: gratis digitale stempelkaart | Pasr</title>
  <meta name="description" content="{desc}">
  <meta name="keywords" content="digitale stempelkaart, stempelkaart app, spaarkaart voor je zaak, klantenkaart maken, loyaliteitskaart horeca, stempelkaart zonder kassakoppeling, gratis stempelkaart, Pasr Zakelijk">
  <meta name="robots" content="index, follow, max-image-preview:large">
  <link rel="canonical" href="https://pasr.nl/zakelijk/">
  <link rel="alternate" hreflang="nl-NL" href="https://pasr.nl/zakelijk/">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Pasr">
  <meta property="og:url" content="https://pasr.nl/zakelijk/">
  <meta property="og:title" content="Pasr voor ondernemers: gratis digitale stempelkaart">
  <meta property="og:description" content="{desc}">
  <meta property="og:image" content="https://pasr.nl/og/zakelijk.png">
  <meta property="og:image:type" content="image/png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="{og_alt}">
  <meta property="og:locale" content="nl_NL">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="Pasr voor ondernemers: gratis digitale stempelkaart">
  <meta name="twitter:description" content="{desc}">
  <meta name="twitter:image" content="https://pasr.nl/og/zakelijk.png">
  <meta name="twitter:image:alt" content="{og_alt}">
  <script type="application/ld+json">{{"@context":"https://schema.org","@type":"BreadcrumbList","itemListElement":[{{"@type":"ListItem","position":1,"name":"Pasr","item":"https://pasr.nl/"}},{{"@type":"ListItem","position":2,"name":"Pasr voor ondernemers","item":"https://pasr.nl/zakelijk/"}}]}}</script>
  <script type="application/ld+json">{{"@context":"https://schema.org","@type":"MobileApplication","name":"Pasr Zakelijk","operatingSystem":"iOS 17, iPadOS 17, Android 8, webbrowser","applicationCategory":"BusinessApplication","url":"{APP_URL}","description":"Digitale stempelkaart voor je zaak: stempels zetten met je telefoon, klanten sparen in Pasr.","featureList":{feature_list},"offers":{{"@type":"Offer","price":"0","priceCurrency":"EUR"}},"publisher":{{"@type":"Organization","name":"Pasr","url":"https://pasr.nl/"}}}}</script>
  <script type="application/ld+json">{{"@context":"https://schema.org","@type":"FAQPage","mainEntity":[{faq_ld}]}}</script>
  <meta name="theme-color" content="#F4F3FF">
  <link rel="icon" type="image/png" href="/assets/favicon.png">
  <link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
  <link rel="manifest" href="/site.webmanifest">
  <script src="/assets/consent.js" defer></script>
  <link rel="stylesheet" href="/assets/style.css">
  <link rel="stylesheet" href="/assets/zakelijk.css">
  <script>document.documentElement.classList.add('js')</script>
</head>
<body data-page="zk-home">
{header()}

  <main class="zk-home">
    <div class="wrap hero zk-hero2" id="top">
      <div>
        <span class="zk-kicker enter" style="--d:0">Pasr Zakelijk · gratis voor ondernemers</span>
        <h1 class="enter" style="--d:0"><span>Je stempelkaart.</span> <span>Digitaal, in een minuut.</span></h1>
        <p class="lead enter" style="--d:1">Maak gratis een digitale stempelkaart met het logo en de kleur van je zaak. Klanten sparen in Pasr of in hun browser, jij zet de stempels met je telefoon. Zonder papier en zonder kassakoppeling.</p>
        <div class="actions enter" style="--d:2">
          <a class="btn btn-primary" href="/zakelijk/dashboard/#account">Gratis aanmelden</a>
          <a class="btn btn-ghost" href="/zakelijk/dashboard/">Inloggen</a>
        </div>
        <div class="actions zk-badges enter" style="--d:3" aria-label="De app Pasr Zakelijk">
          {badges()}
        </div>
        <ul class="platforms enter" style="--d:3" aria-label="Werkt op">
          <li><b>iPhone en iPad</b> iOS 17+</li>
          <li><b>Android</b> 8+</li>
          <li><b>Browser</b> dashboard en scanner</li>
        </ul>
      </div>
      <div class="stage enter-stage zk-stage">
{hero_phone()}
      </div>
    </div>

    <section class="wrap" id="zo-werkt-het" aria-labelledby="werkt-title">
      <div class="section-head">
        <h2 id="werkt-title">Zo werkt het</h2>
        <p>Van aanmelden tot de eerste stempel: meestal ben je dezelfde dag klaar.</p>
      </div>
      <ol class="steps">{steps_html}</ol>
    </section>

    <div class="wrap">
      <section class="why" id="waarom" aria-labelledby="why-title">
        <div class="section-head">
          <h2 id="why-title">Papier raakt kwijt. Pasr niet.</h2>
          <p>Een papieren stempelkaart is makkelijk, maar je klant vergeet hem, en je weet nooit wat hij oplevert.</p>
        </div>
        <div class="compare">
          <div class="compare-head">Papieren stempelkaart</div>
          <div class="compare-head" style="color:#fff">Pasr Zakelijk</div>
{compare}
        </div>
{feature_table()}
      </section>
    </div>

    <section class="wrap" id="functies" aria-labelledby="functies-title">
      <div class="section-head">
        <h2 id="functies-title">Alles wat je aan de toonbank nodig hebt</h2>
        <p>Gemaakt voor de koffiebar, de bakker, de kapper en de lunchroom: snel bij de kassa, en niets wat je niet nodig hebt.</p>
      </div>
      <div class="features">
{features}
      </div>
    </section>

{web_section()}

    <section class="wrap" id="faq" aria-labelledby="faq-title">
      <div class="section-head"><h2 id="faq-title">Vragen</h2></div>
      <div class="faq">
{faq}
      </div>
    </section>

    <section class="wrap cta" id="download" aria-labelledby="cta-title">
      <h2 id="cta-title">Klaar voor je eerste stempel?</h2>
      <p>Pasr Zakelijk is gratis: in de App Store voor iPhone en iPad, als download voor Android, en in je browser.</p>
      <div class="actions">
        {badges(lazy=True)}
      </div>
      <p class="zk-cta-web"><a class="btn btn-primary" href="/zakelijk/dashboard/#account">Gratis aanmelden</a> <a class="btn btn-ghost" href="/zakelijk/dashboard/">Inloggen</a></p>
    </section>
  </main>

{FOOTER}
  <script src="/assets/site.js" defer></script>
  <script src="/assets/account-config.js"></script>
  <script src="/assets/vendor/qrcode.js"></script>
  <script src="/assets/zakelijk.js"></script>
</body>
</html>
'''


def patch_download():
    """/zakelijk/download/ wordt elders gemaakt (Android); zet alleen dezelfde kop erin."""
    f = ZK / "download" / "index.html"
    if not f.exists():
        return False
    html = f.read_text(encoding="utf-8")
    new = re.sub(r'  <header class="wrap nav[^"]*">.*?</header>', header(), html, count=1, flags=re.S)
    if 'zakelijk.css' not in new:
        new = re.sub(r'(<link rel="stylesheet" href="/assets/style\.css[^"]*">)', r'\1\n  <link rel="stylesheet" href="/assets/zakelijk.css">', new, count=1)
    if "/assets/account-config.js" not in new:   # knop Inloggen wordt Dashboard als je al bent ingelogd
        new = new.replace("</body>", '  <script src="/assets/account-config.js"></script>\n  <script src="/assets/zakelijk.js"></script>\n</body>', 1)
    if new != html:
        f.write_text(new, encoding="utf-8")
    return True


def build():
    ZK.mkdir(parents=True, exist_ok=True)
    (ZK / "index.html").write_text(page(), encoding="utf-8")
    written = [ZK / "index.html"]
    for p in APP_PAGES:
        out = ZK / p[0]
        out.mkdir(parents=True, exist_ok=True)
        (out / "index.html").write_text(app_page(*p), encoding="utf-8")
        written.append(out / "index.html")
    if patch_download():
        written.append(ZK / "download" / "index.html")
    return written


if __name__ == "__main__":
    for w in build():
        print("Wrote", w)
