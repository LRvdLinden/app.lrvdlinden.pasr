#!/usr/bin/env python3
""""Voeg toe aan Pasr": de terugvalpagina pasr.nl/add/<soort>/<id> (en pasr.nl/toevoegen/) en de knop op eigen pagina's.

Linkformaat (universele link / App Link naar de apps; zonder app opent deze pagina):
    https://pasr.nl/add/<soort>/<id>
    k = stempelkaart/klantenkaart van een zaak (pasr_business_cards.id, uuid)
    c = kortingsbon van een zaak                (pasr_business_coupons.id, uuid)
    a = actiecode van een zaak                  (pasr_business_promo_codes.id, uuid)
    t = ticket uit de catalogus                 (pasr_stores.id, bijv. drakenboot-kids), of een gratis eventticket
        (pasr_tk_tickets.id, uuid) met ?c=<code>: dan toont de pagina het ticket met QR-code (pasr_event_ticket_public)
        en met &afmelden=1 de knop om af te melden (pasr_event_ticket_cancel)
    m = klantenkaart met barcode van een zaak   (pasr_mc_cards.id, uuid; lid worden gaat in de app)
    e = aanmelden voor een gratis event         (pasr_tk_events.id, uuid): eigen pagina /aanmelden/ (aanmeld_page)
    g = cadeaubon/cadeaukaart uit de catalogus  (pasr_stores.id, bijv. bol-cadeaukaart)
    s = winkelkaart uit de catalogus            (pasr_stores.id, bijv. ah)

De server geeft /add/… via .htaccess de pagina /toevoegen/index.html (adres blijft staan); werkt de rewrite niet, dan
stuurt 404.html door naar /toevoegen/#<soort>/<id>. De pagina haalt het item op met dezelfde openbare functies als de
apps (pasr_business_card, pasr_business_coupon_list, pasr_business_promo_public) of uit winkels.json (catalogus).
Wordt aangeroepen door tools/make_website.py.
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import store_catalog as sc
from make_kaarten import esc, APP_STORE
from catalog_hub import site_nav, footer_links

REPO = Path(__file__).resolve().parent.parent
ROOT = REPO / "website"
KINDS = "kcatgsme"
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{0,63}$")
THEMES = ("zwart", "wit", "nachtblauw")


def badge_size(theme="zwart", compact=False):
    sizes = json.loads((ROOT / "badge" / "nl" / "sizes.json").read_text())
    return sizes[theme + ("-compact" if compact else "")]


def add_url(kind, item_id):
    if kind not in KINDS or not ID_RE.match(str(item_id)):
        raise ValueError(f"ongeldig item {kind}/{item_id}")
    return f"https://pasr.nl/add/{kind}/{str(item_id).lower() if kind in 'kcame' else item_id}"


def badge_html(kind, item_id, theme="zwart", compact=False, cls="pasr-add-badge"):
    """De officiële knop als <a><img></a> (SVG met tekst als paden; zelfde als de snippet voor ondernemers)."""
    w, h = badge_size(theme, compact)
    name = theme + ("-compact" if compact else "")
    return (f'<a class="{cls}" href="{add_url(kind, item_id)}"><img src="/badge/nl/{name}.svg" alt="Voeg toe aan Pasr" '
            f'width="{w}" height="{h}" loading="lazy"></a>')


def badge_pair(kind, item_id, compact=False):
    """Zwart in licht thema, wit in donker thema (<picture> met prefers-color-scheme)."""
    w, h = badge_size("zwart", compact)
    sfx = "-compact" if compact else ""
    return (f'<a class="pasr-add-badge" href="{add_url(kind, item_id)}"><picture>'
            f'<source srcset="/badge/nl/wit{sfx}.svg" media="(prefers-color-scheme: dark)">'
            f'<img src="/badge/nl/zwart{sfx}.svg" alt="Voeg toe aan Pasr" width="{w}" height="{h}" loading="lazy"></picture></a>')


def catalog_index():
    """Catalogus voor de terugvalpagina (soort s/g/t): naam, soort, kleur, logo en de gids op pasr.nl."""
    import make_gids
    guides = make_gids.guides()
    slugs = {}
    for kind in ("voucher", "loyalty"):
        for c, _ in make_gids.load(kind, guides):
            slugs[c["id"]] = f"/{make_gids.KINDS[kind]['dir']}/{c['slug']}/"
    out = {}
    for c in sc.all_cards():
        logo = ROOT / "assets" / "kaarten" / f"{c['key']}.png"
        out[c["id"]] = {"n": c["name"], "k": c.get("store_kind") or c["kind"], "c": c.get("card") or "#2B2F3A",
                        **({"l": f"/assets/kaarten/{c['key']}.png"} if logo.exists() else {}),
                        **({"u": slugs[c["id"]]} if c["id"] in slugs else {})}
    return out


ANDROID = ('<a class="android-badge" href="/android/" aria-label="Download for Android"><svg viewBox="0 0 24 24" aria-hidden="true"><g fill="#2ED3A6"><path d="M6.2 9.3a5.8 5.8 0 0 1 11.6 0z"/><path d="M8.3 4.4 7 2.4M15.7 4.4 17 2.4" stroke="#2ED3A6" stroke-width=".9" stroke-linecap="round"/><path d="M6.2 10h11.6v7.6a1.4 1.4 0 0 1-1.4 1.4H7.6a1.4 1.4 0 0 1-1.4-1.4z"/><rect x="3.4" y="10" width="2.1" height="6.6" rx="1.05"/><rect x="18.5" y="10" width="2.1" height="6.6" rx="1.05"/><rect x="8.4" y="17.6" width="2.1" height="4.4" rx="1.05"/><rect x="13.5" y="17.6" width="2.1" height="4.4" rx="1.05"/></g><circle cx="9.4" cy="7.1" r=".65" fill="#000"/><circle cx="14.6" cy="7.1" r=".65" fill="#000"/></svg><span><small>Download for</small>Android</span></a>')
APPLE = (f'<a class="store-badge" href="{APP_STORE}" rel="noopener">'
         '<img src="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/nl-nl?releaseDate=1794096000" '
         'alt="Download in de App Store" width="246" height="82"></a>')


def page():
    return f"""<!doctype html>
<html lang="nl"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>Voeg toe aan Pasr</title>
<meta name="description" content="Zet deze kaart, bon of dit ticket in Pasr: gratis, zonder reclame. Heb je Pasr nog niet? Installeer de app en open deze link opnieuw.">
<meta name="robots" content="noindex,follow">
<meta name="theme-color" content="#F4F3FF" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#111020" media="(prefers-color-scheme: dark)">
<meta property="og:title" content="Voeg toe aan Pasr"><meta property="og:image" content="https://pasr.nl/assets/og-share.png">
<link rel="icon" type="image/png" sizes="64x64" href="/assets/favicon.png">
<link rel="apple-touch-icon" sizes="180x180" href="/assets/apple-touch-icon.png">
<link rel="stylesheet" href="/assets/style.css">
<link rel="stylesheet" href="/assets/catalog-hub.css">
<link rel="stylesheet" href="/assets/toevoegen.css">
<script src="/assets/consent.js" defer></script>
</head><body class="add-page">
<a class="skip" href="#ta-main">Naar het item</a>
{site_nav("")}
<main class="wrap ta" id="ta-main" data-pasr-add>
  <section class="ta-hero" aria-labelledby="ta-title">
    <div class="ta-item" id="ta-item" aria-live="polite"><div class="ta-card ta-loading" aria-hidden="true"></div></div>
    <div class="ta-text">
      <p class="ta-kicker" id="ta-kind">Voeg toe aan Pasr</p>
      <h1 id="ta-title">Even laden…</h1>
      <p class="ta-lead" id="ta-lead">We halen het item op.</p>
      <p class="ta-error" id="ta-error" hidden></p>
      <div class="ta-open" id="ta-open-wrap" hidden>
        <a class="btn btn-primary ta-openbtn" id="ta-open" href="#">Al geïnstalleerd? Open in Pasr</a>
      </div>
    </div>
  </section>
  <section class="ta-get" aria-labelledby="ta-get-title">
    <h2 id="ta-get-title">Nog geen Pasr?</h2>
    <ol class="ta-steps">
      <li><b>Installeer Pasr</b> (gratis, zonder reclame) voor iPhone of Android.<div class="actions ta-badges">{APPLE} {ANDROID}</div></li>
      <li><b>Open deze link daarna opnieuw</b>, bijvoorbeeld door terug te gaan naar deze pagina en op <i>Open in Pasr</i> te tikken. Pasr toont dan meteen <i>Toevoegen aan Pasr?</i>
        <div class="ta-copy"><code id="ta-link">https://pasr.nl/add/</code><button class="btn btn-ghost" type="button" id="ta-copybtn">Kopieer link</button></div>
        <p class="ta-small" id="ta-saved" hidden>We hebben deze link in deze browser onthouden: kom je later terug op pasr.nl/toevoegen, dan staat hij hier weer klaar.</p></li>
    </ol>
    <p class="ta-small">Een app kan na het installeren niet zelf zien welke link je eerder opende; daarom vragen we je de link opnieuw te openen. Pasr bewaart niets over jou op deze pagina.</p>
  </section>
</main>
<footer><div class="wrap"><span>&copy; Pasr · De zaak of uitgever bepaalt de voorwaarden van het item; Pasr bewaart het voor je.</span>
<nav aria-label="Voettekst">{footer_links()}</nav></div></footer>
<script src="/assets/account-config.js"></script>
<script src="/assets/vendor/qrcode.js"></script>
<script src="/assets/toevoegen.js"></script>
</body></html>
"""


def aanmeld_page():
    """pasr.nl/add/e/<event-id>: aanmelden voor een gratis event (pasr_event_public en pasr_event_register, anoniem).
    Header in de kleur van het event, formulier met voornaam, achternaam, e-mail, geboortedatum (verplicht), ticketsoort en
    aantal, daarna de bevestiging met de knop "Voeg toe aan Pasr" en "Open in Pasr". Script: /assets/aanmelden.js (bouwt
    het formulier, met de honeypots "hp_extra" (tekstveld) en "nieuwsbrief_extra" (vinkje), zonder tijdmeting, en een
    lege geboortedatum met max = gisteren)."""
    return f"""<!doctype html>
<html lang="nl"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>Aanmelden | Pasr</title>
<meta name="description" content="Meld je gratis aan voor dit event. Je krijgt je ticket met QR-code per mail en in Pasr.">
<meta name="robots" content="noindex,follow">
<meta name="theme-color" content="#F4F3FF" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#111020" media="(prefers-color-scheme: dark)">
<meta property="og:title" content="Aanmelden voor een event met Pasr"><meta property="og:image" content="https://pasr.nl/assets/og-share.png">
<link rel="icon" type="image/png" sizes="64x64" href="/assets/favicon.png">
<link rel="apple-touch-icon" sizes="180x180" href="/assets/apple-touch-icon.png">
<link rel="stylesheet" href="/assets/style.css">
<link rel="stylesheet" href="/assets/catalog-hub.css">
<link rel="stylesheet" href="/assets/toevoegen.css">
<script src="/assets/consent.js" defer></script>
</head><body class="add-page ev-page">
<a class="skip" href="#ev-main">Naar het aanmelden</a>
{site_nav("")}
<main class="wrap ev" id="ev-main" data-pasr-event>
  <section class="ev-head" id="ev-head" aria-labelledby="ev-title">
    <div class="ev-headin">
      <p class="ev-biz" id="ev-biz"><span class="ev-bizlogo" aria-hidden="true"></span><span>Even laden…</span></p>
      <h1 id="ev-title">Aanmelden</h1>
      <p class="ev-when" id="ev-when"></p>
    </div>
  </section>
  <div class="ev-grid">
    <section class="ev-info" id="ev-info" aria-label="Over het event"><div class="ta-card ta-loading" aria-hidden="true"></div></section>
    <section class="ev-box" id="ev-box" aria-live="polite"></section>
  </div>
  <section class="ta-get ev-get" aria-labelledby="ev-get-title">
    <h2 id="ev-get-title">Je ticket in Pasr</h2>
    <p class="ta-small">Met Pasr (gratis, zonder reclame) heb je je ticket offline bij de hand, met een herinnering de dag ervoor. Na het aanmelden tik je op <i>Voeg toe aan Pasr</i>; je ticket staat ook in de mail.</p>
    <div class="actions ta-badges">{APPLE} {ANDROID}</div>
  </section>
</main>
<footer><div class="wrap"><span>&copy; Pasr · De organisator bepaalt de voorwaarden van het event; Pasr regelt de aanmelding en je ticket.</span>
<nav aria-label="Voettekst">{footer_links()}</nav></div></footer>
<script src="/assets/account-config.js"></script>
<script src="/assets/vendor/qrcode.js"></script>
<script src="/assets/aanmelden.js"></script>
</body></html>
"""


def build():
    out = ROOT / "toevoegen"
    out.mkdir(exist_ok=True)
    (out / "index.html").write_text(page(), encoding="utf-8")
    ev = ROOT / "aanmelden"
    ev.mkdir(exist_ok=True)
    (ev / "index.html").write_text(aanmeld_page(), encoding="utf-8")
    (out / "winkels.json").write_text(json.dumps(catalog_index(), ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return [out / "index.html", out / "winkels.json", ev / "index.html"]


if __name__ == "__main__":
    for p in build():
        print("Wrote", p)
