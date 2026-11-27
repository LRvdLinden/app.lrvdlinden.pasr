"""Maakt de HTML-sjablonen voor de deelafbeeldingen van pasr.nl (/og/home.png) en pasr.nl/zakelijk (/og/zakelijk.png).

De passen komen uit tools/zakelijk_v2.py en de stijlen uit website/assets (style.css, zakelijk.css, zakelijk-v2.css),
dus de afbeelding ziet er precies zo uit als de site. Lettertypen: Bricolage Grotesque en Figtree uit tools/og/fonts.
Wordt aangeroepen door tools/og/render.py; los draaien mag ook: python3 tools/og/build_og_html.py
"""
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE.parent))
import zakelijk_v2 as zv  # noqa: E402

ASSETS = "../../website/assets"

HEAD = f'''<!doctype html><html lang="nl"><head><meta charset="utf-8">
<link rel="stylesheet" href="{ASSETS}/style.css">
<link rel="stylesheet" href="{ASSETS}/zakelijk.css">
<link rel="stylesheet" href="{ASSETS}/zakelijk-v2.css">
<style>
@font-face{{font-family:"Bricolage Grotesque";src:url(fonts/BricolageGrotesque.ttf);font-weight:200 800}}
@font-face{{font-family:"Figtree";src:url(fonts/Figtree.ttf);font-weight:300 900}}
html,body{{margin:0;width:1200px;height:630px;overflow:hidden;background:#F4F3FF;color:#17162A;font-family:"Figtree",sans-serif}}
*{{animation:none!important;transition:none!important}}
.glow{{position:absolute;inset:0;background:radial-gradient(ellipse 620px 420px at 930px 330px,#E4DFFF 0,rgba(244,243,255,0) 70%)}}
.left{{position:absolute;left:72px;top:64px;width:530px}}
.brand{{display:flex;align-items:center;gap:16px;font:800 44px "Bricolage Grotesque";letter-spacing:-1.5px}}
.brand img{{width:76px;height:76px;border-radius:18px;box-shadow:0 12px 26px -14px rgba(23,22,42,.6)}}
.tag{{font:800 18px "Figtree";letter-spacing:2px;color:#fff;background:#087554;border-radius:10px;padding:7px 12px;margin-left:2px}}
h1{{font:800 66px/1.0 "Bricolage Grotesque";letter-spacing:-2.6px;margin:38px 0 22px}}
h1 em{{font-style:normal;color:#6A5CFF}}
p.sub{{font-size:25px;line-height:1.35;color:#4B4966;margin:0}}
.foot{{position:absolute;left:72px;bottom:52px;font:700 24px "Figtree";color:#4A3CE0}}
.stage{{position:absolute;right:40px;top:0;width:560px;height:630px}}
.stage>div{{position:absolute}}
.stage .sc{{width:350px}}
/* de officiële Pasr-stempel (zakelijk.css gebruikt /assets/..., dat bestaat niet als file://) */
.sc .sc-stamp.on::before{{-webkit-mask-image:url({ASSETS}/pasr-stamp.svg)!important;mask-image:url({ASSETS}/pasr-stamp.svg)!important}}
</style></head><body><div class="glow"></div>
'''


def gift_card():
    """Cadeaukaart zoals in Pasr: kaartkleur, logo-tegel, CADEAUKAART, tegoed en geldigheid."""
    return ('<div class="zm" style="--c:#E3051B;width:320px">'
            f'<div class="zm-head"><span class="zm-logo" style="background:#fff;padding:5px;box-sizing:border-box"><img src="{ASSETS}/kaarten/hema.nl.png" alt="" style="width:100%;height:100%;object-fit:contain"></span>'
            '<span class="zm-t"><b>HEMA cadeaukaart</b><small>Geldig t/m 31 dec 2027</small></span><em>Cadeaukaart</em></div>'
            '<span style="font:800 40px/1 \'Bricolage Grotesque\';letter-spacing:-1px;margin:6px 0 2px">€ 25,00</span>'
            '<span class="zm-chip">Tegoed bijgewerkt vandaag</span></div>')


def loyalty_card():
    """Klantenkaart met barcode zoals in Pasr."""
    return ('<div class="zm" style="--c:#00A0E2;width:320px">'
            f'<div class="zm-head"><span class="zm-logo" style="background:none;padding:0;box-sizing:border-box"><img src="{ASSETS}/kaarten/ah.nl.png" alt="" style="width:100%;height:100%;object-fit:contain"></span>'
            '<span class="zm-t"><b>Albert Heijn Bonuskaart</b><small>Klantenkaart</small></span><em>Klantenkaart</em></div>'
            f'<span class="zm-bar">{zv.barcode(seed=11)}<small>2620 0418 3317</small></span></div>')


def home():
    return HEAD + f'''<div class="stage">
  <div style="left:250px;top:44px;z-index:1"><div class="zn-tilt" style="--r:7deg;filter:drop-shadow(0 22px 26px rgba(10,60,60,.28))">{zv.ticket()}</div></div>
  <div style="left:0;top:110px;z-index:2"><div class="zn-tilt" style="--r:-7deg">{gift_card()}</div></div>
  <div style="left:56px;top:350px;z-index:3"><div class="zn-tilt" style="--r:-2deg">{loyalty_card()}</div></div>
</div>
<div class="left">
  <div class="brand"><img src="{ASSETS}/icon.png" alt="">pasr</div>
  <h1>Klantenkaarten, cadeaukaarten en tickets <em>in één app</em></h1>
  <p class="sub">Gratis en zonder reclame. Voor iPhone, iPad, Apple Watch, Mac en Android.</p>
</div>
<div class="foot">pasr.nl</div>
</body></html>
'''


def zakelijk():
    stamp = zv.stamp_card("Koffiekaart", "Bakkerij de Korenschoof", "Apeldoorn", "#E8590C", 10, 6, "10 = gratis koffie")
    return HEAD + f'''<div class="stage">
  <div style="left:0;top:52px;z-index:1"><div class="zn-tilt" style="--r:-8deg">{zv.member_card()}</div></div>
  <div style="left:286px;top:40px;z-index:2"><div class="zn-tilt" style="--r:6deg;filter:drop-shadow(0 22px 26px rgba(10,60,60,.28))">{zv.ticket()}</div></div>
  <div style="left:10px;top:300px;z-index:3">{stamp}</div>
  <div style="left:250px;top:276px;z-index:4"><span class="zn-chip zn-chip-stamp" style="position:static">+1 stempel</span></div>
  <div style="left:330px;top:520px;z-index:4"><span class="zn-chip zn-chip-ok" style="position:static">{zv.TICK}Ticket geldig</span></div>
</div>
<div class="left">
  <div class="brand"><img src="{ASSETS}/pasr-zakelijk-touch-icon.png" alt="">pasr <span class="tag">ZAKELIJK</span></div>
  <h1>Alles om klanten <em>terug te laten komen</em></h1>
  <p class="sub">Stempelkaarten, klantenkaarten en tickets voor je zaak. Gratis, met één scanner.</p>
</div>
<div class="foot">pasr.nl/zakelijk</div>
</body></html>
'''


def build():
    (HERE / "home.html").write_text(home(), encoding="utf-8")
    (HERE / "zakelijk.html").write_text(zakelijk(), encoding="utf-8")


if __name__ == "__main__":
    build()
    print("tools/og/home.html en tools/og/zakelijk.html bijgewerkt")
