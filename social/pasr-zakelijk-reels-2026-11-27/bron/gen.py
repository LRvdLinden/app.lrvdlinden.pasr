"""Genereert de HTML-bronnen voor de Instagram Reels van Pasr en Pasr Zakelijk (campagne 2026-11-27, Nederlands).

Elke reel is één HTML-pagina van 1080x1920 met een tijdlijn in JavaScript: window.setT(t) zet alle elementen
op hun stand op tijdstip t (seconden). Er draait geen echte CSS-animatie; render.py roept setT per frame aan.
De passen (klantenkaart .zm, ticket .zt, stempelkaart .sc, kortingsbon, actiecode, dashboard .znb) komen
letterlijk uit de hero en het dashboard van pasr.nl/zakelijk (tools/zakelijk_v2.py) en gebruiken de CSS van
de site (SITE = de map website/ via een lokale webserver op poort 8765).

Gebruik: python3 gen.py <buildmap>   (de buildmap bevat hero_panel.html, dash_panel.html, fonts/, iconen en badge)
"""
import json, os, re, sys

B = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__)) + "/build")
SITE = "http://localhost:8765"
W, H = 1080, 1920
hero = open(B + "/hero_panel.html").read()
dash = open(B + "/dash_panel.html").read().replace('src="/assets/', f'src="{SITE}/assets/')


def piece(cls):
    i = hero.find('<div class="zn-h ' + cls)
    j = hero.find('<div class="zn-h ', i + 10)
    if j < 0:
        j = hero.find('<span class="zn-chip', i)
    return hero[i:j]


MEMBER, TICKET, STAMP, COUPON, CODE = (piece(c) for c in ("zn-h-member", "zn-h-ticket", "zn-h-stamp", "zn-h-coupon", "zn-h-code"))
BAR = re.search(r'<span class="zm-bar">.*?</small></span>', MEMBER, re.S).group(0)
QR = re.search(r'<svg class="zn-qr".*?</svg>', TICKET, re.S).group(0)
CHECK = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" '
         'stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5 10 17 19 7"/></svg>')
ANDROID_SVG = ('<svg viewBox="0 0 24 24" aria-hidden="true"><g fill="#2ED3A6"><path d="M6.2 9.3a5.8 5.8 0 0 1 11.6 0z"/><path d="M8.3 4.4 7 2.4M15.7 4.4 17 2.4" stroke="#2ED3A6" stroke-width=".9" stroke-linecap="round"/>'
               '<path d="M6.2 10h11.6v7.6a1.4 1.4 0 0 1-1.4 1.4H7.6a1.4 1.4 0 0 1-1.4-1.4z"/><rect x="3.4" y="10" width="2.1" height="6.6" rx="1.05"/><rect x="18.5" y="10" width="2.1" height="6.6" rx="1.05"/>'
               '<rect x="8.4" y="17.6" width="2.1" height="4.4" rx="1.05"/><rect x="13.5" y="17.6" width="2.1" height="4.4" rx="1.05"/></g>'
               '<circle cx="9.4" cy="7.1" r=".65" fill="#000"/><circle cx="14.6" cy="7.1" r=".65" fill="#000"/></svg>')


def member(name, kind, sub, chip, color, logo, code):
    """Neutrale voorbeeld-klantenkaart in de stijl van de app (geen merken van derden)."""
    bar = BAR.replace("FP-0048 2219", code)
    chip = f'<span class="zm-chip">{chip}</span>' if chip else ""
    return (f'<div class="zm" style="--c:{color};width:290px"><div class="zm-head"><span class="zm-logo">{logo}</span>'
            f'<span class="zm-t"><b>{name}</b><small>{sub}</small></span><em>{kind}</em></div>{chip}{bar}</div>')


def stamp_card():
    # Stempelkaart uit de hero, maar met alle stempels leeg: ze springen er in de reel één voor één in.
    s = STAMP.replace(' sc-stamp on"', ' sc-stamp"').replace('class="sc demo"', 'class="sc"')
    s = s.replace("<span>4 te gaan</span>", '<span class="togo">10 te gaan</span>')
    return s


def wrap(id_, inner, z=1, extra=""):
    return f'<div class="el" id="{id_}" style="z-index:{z};{extra}"><div class="zn-canvas pc">{inner}</div></div>'


def chip(id_, html, cls="ok", z=20):
    return f'<div class="el" id="{id_}" style="z-index:{z}"><span class="rchip {cls}">{html}</span></div>'


def badges():
    return (f'<div class="sb-cta"><img class="apple" src="appstore-nl-zwart.svg" alt="Download in de App Store">'
            f'<span class="android">{ANDROID_SVG}<span><small>Download voor</small>Android</span></span></div>')


def caption(id_, lines, y, size=112, z=30):
    """Tekst per woord, zodat de woorden los kunnen opkomen. lines = lijst van strings; <em>…</em> = accent."""
    out, k = [], 0
    for ln in lines:
        words = []
        for wd in re.findall(r'<em>.*?</em>|\S+', ln):
            if wd.startswith("<em>"):
                for w2 in wd[4:-5].split():
                    words.append(f'<span class="w" data-k="{k}"><em>{w2}</em></span>'); k += 1
            else:
                words.append(f'<span class="w" data-k="{k}">{wd}</span>'); k += 1
        out.append('<span class="ln">' + " ".join(words) + "</span>")
    return (f'<div class="cap" id="{id_}" data-n="{k}" style="top:{y}px;font-size:{size}px;z-index:{z}">'
            + "".join(out) + "</div>")


def css(theme):
    dark = theme == "dark"
    bg = ("radial-gradient(ellipse at var(--gx) -10%, rgba(106,92,255,.55), transparent 55%),"
          "radial-gradient(ellipse at 100% 105%, rgba(255,107,87,.28), transparent 45%),"
          "radial-gradient(ellipse at 0% var(--gy), rgba(46,211,166,.16), transparent 45%), #0E0D1A") if dark else \
         ("radial-gradient(ellipse at 95% var(--gy), rgba(106,92,255,.30), transparent 50%),"
          "radial-gradient(ellipse at var(--gx) 100%, rgba(46,211,166,.30), transparent 55%),"
          "radial-gradient(ellipse at 0% 0%, rgba(46,211,166,.12), transparent 40%), #F4F3FF")
    ink = "#FFFFFF" if dark else "#17162A"
    ink2 = "#C9C6E8" if dark else "#4B4966"
    accent = "linear-gradient(90deg,#A79BFF,#FF8A78)" if dark else "linear-gradient(90deg,#4A3CE0,#0E8A62)"
    return f"""
@font-face{{font-family:"Bricolage Grotesque";font-weight:600;src:url(fonts/bricolage-grotesque-latin-600-normal.woff2)}}
@font-face{{font-family:"Bricolage Grotesque";font-weight:700;src:url(fonts/bricolage-grotesque-latin-700-normal.woff2)}}
@font-face{{font-family:"Bricolage Grotesque";font-weight:800;src:url(fonts/bricolage-grotesque-latin-800-normal.woff2)}}
@font-face{{font-family:"Figtree";font-weight:400;src:url(fonts/figtree-latin-400-normal.woff2)}}
@font-face{{font-family:"Figtree";font-weight:500;src:url(fonts/figtree-latin-500-normal.woff2)}}
@font-face{{font-family:"Figtree";font-weight:600;src:url(fonts/figtree-latin-600-normal.woff2)}}
@font-face{{font-family:"Figtree";font-weight:700;src:url(fonts/figtree-latin-700-normal.woff2)}}
@font-face{{font-family:"Figtree";font-weight:800;src:url(fonts/figtree-latin-800-normal.woff2)}}
*,*::before,*::after{{animation:none!important;transition:none!important}}
html,body{{margin:0;width:{W}px;height:{H}px;overflow:hidden}}
body{{--gx:50%;--gy:100%;background:{bg};color:{ink};font-family:"Figtree",system-ui,sans-serif;position:relative}}
.el{{position:absolute;left:0;top:0;will-change:transform,opacity;opacity:0}}
.pc{{position:relative!important;width:auto!important;height:auto!important;transform:none!important}}
.pc .zn-h{{position:relative!important;left:auto!important;top:auto!important;right:auto!important}}
.sc .sc-stamp.on::before{{-webkit-mask-image:url(pasr-stamp.svg)!important;mask-image:url(pasr-stamp.svg)!important}}
.cap{{position:absolute;left:60px;right:60px;text-align:center;font-family:"Bricolage Grotesque";font-weight:800;line-height:1.0;
  letter-spacing:-.035em;color:{ink}}}
.cap .ln{{display:block}}
.cap .w{{display:inline-block;will-change:transform,opacity;opacity:0}}
.cap em{{font-style:normal;background:{accent};-webkit-background-clip:text;background-clip:text;color:transparent;padding-bottom:.08em}}
.brand{{display:flex;align-items:center;gap:26px}}
.brand img{{width:var(--ls);height:var(--ls);border-radius:calc(var(--ls)*.225);box-shadow:0 14px 34px rgba(0,0,0,.30)}}
.brand b{{font:800 calc(var(--ls)*.82) "Bricolage Grotesque";letter-spacing:-.03em;color:{ink}}}
.brand .tag{{font:700 calc(var(--ls)*.30) "Figtree";font-style:normal;letter-spacing:.05em;text-transform:uppercase;color:#fff;
  background:linear-gradient(135deg,#12A77E,#0E8A62);border-radius:calc(var(--ls)*.14);padding:calc(var(--ls)*.07) calc(var(--ls)*.16)}}
.rchip{{display:inline-flex;align-items:center;gap:14px;white-space:nowrap;font:800 40px "Figtree";border-radius:999px;padding:20px 32px;line-height:1}}
.rchip svg{{width:40px;height:40px}}
.rchip.ok{{background:#087554;color:#fff;box-shadow:0 20px 44px -18px rgba(8,117,84,.7)}}
.rchip.white{{background:#fff;color:#17162A;box-shadow:0 20px 40px -20px rgba(0,0,0,.5)}}
.rchip.dark{{background:#17162A;color:#fff;box-shadow:0 20px 40px -20px rgba(0,0,0,.5)}}
.rchip.iris{{background:#4A3CE0;color:#fff;box-shadow:0 20px 44px -18px rgba(74,60,224,.6)}}
.sub2{{font:600 46px/1.25 "Figtree";color:{ink2};text-align:center;white-space:nowrap}}
.url{{font:800 76px "Bricolage Grotesque";letter-spacing:-.03em;color:{ink};white-space:nowrap}}
.url em{{font-style:normal;background:{accent};-webkit-background-clip:text;background-clip:text;color:transparent}}
.sb-cta{{display:flex;align-items:center;gap:28px}}
.sb-cta img.apple{{height:112px;width:auto;display:block}}
.android{{display:inline-flex;align-items:center;justify-content:center;gap:18px;box-sizing:border-box;height:112px;width:335px;
  padding:0 20px;border-radius:19px;background:#000;border:2.2px solid #A6A6A6;color:#fff;line-height:1.05}}
.android svg{{width:63px;height:63px;flex:none}}
.android span{{display:flex;flex-direction:column;font:500 40px "Figtree";letter-spacing:-.01em}}
.android small{{font-size:20px;margin-bottom:3px}}
.scanframe{{position:relative;width:560px;height:560px}}
.scanframe i{{position:absolute;width:110px;height:110px;border:12px solid #2ED3A6;border-radius:6px}}
.scanframe i:nth-child(1){{left:0;top:0;border-right:0;border-bottom:0;border-top-left-radius:40px}}
.scanframe i:nth-child(2){{right:0;top:0;border-left:0;border-bottom:0;border-top-right-radius:40px}}
.scanframe i:nth-child(3){{left:0;bottom:0;border-right:0;border-top:0;border-bottom-left-radius:40px}}
.scanframe i:nth-child(4){{right:0;bottom:0;border-left:0;border-top:0;border-bottom-right-radius:40px}}
.scanline{{position:absolute;left:40px;right:40px;height:8px;border-radius:4px;background:#2ED3A6;box-shadow:0 0 30px 6px rgba(46,211,166,.75)}}
.dashwin{{position:relative;width:1000px;height:640px;border-radius:30px;overflow:hidden;background:#fff;border:1px solid rgba(23,22,42,.10);
  box-shadow:0 60px 120px -50px rgba(23,22,42,.55)}}
.dashwin .znb{{position:absolute;left:0;top:0;width:1080px;height:560px;transform-origin:0 0}}
"""


# ---------------------------------------------------------------------------------------------------------------
# Tijdlijn-motor (JS). TR[id] = [[t, {x,y,s,r,o}, ease], ...]; tussen twee sleutels wordt met de ease van de
# volgende sleutel geïnterpoleerd. CAP[id] = [tin, tout, dy]: woorden komen gestaggerd op en gaan samen weg.
ENGINE = r"""
const EZ={lin:t=>t, out:t=>1-Math.pow(1-t,3), io:t=>t<.5?4*t*t*t:1-Math.pow(-2*t+2,3)/2,
  back:t=>{const c1=1.45,c3=c1+1;return 1+c3*Math.pow(t-1,3)+c1*Math.pow(t-1,2)},
  in:t=>t*t*t};
const DEF={x:540,y:960,s:1,r:0,o:1};
function sample(tr,t){
  if(t<=tr[0][0]) return Object.assign({},DEF,tr[0][1]);
  let prev=Object.assign({},DEF,tr[0][1]);
  for(let i=1;i<tr.length;i++){
    const nxt=Object.assign({},prev,tr[i][1]);
    if(t<tr[i][0]){const a=(t-tr[i-1][0])/(tr[i][0]-tr[i-1][0]);const e=EZ[tr[i][2]||'io'](a);
      const o={};for(const k in nxt){o[k]=prev[k]+(nxt[k]-prev[k])*e;}return o;}
    prev=nxt;}
  return prev;
}
function place(el,p){el.style.transform=`translate(${p.x}px,${p.y}px) translate(-50%,-50%) rotate(${p.r}deg) scale(${p.s})`;
  el.style.opacity=Math.max(0,Math.min(1,p.o));}
function capT(id,t){const c=CAP[id];const el=document.getElementById(id);const ws=el.querySelectorAll('.w');
  const [tin,tout,st]=c; const fo=Math.max(0,Math.min(1,(t-tout)/0.35));
  ws.forEach(w=>{const k=+w.dataset.k;const a=Math.max(0,Math.min(1,(t-tin-k*st)/0.5));const e=EZ.out(a);
    const y=(1-e)*70 - EZ.in(fo)*40;w.style.transform=`translateY(${y}px)`;w.style.opacity=Math.min(e,1-fo);});}
window.setT=function(t){
  for(const id in TR){const el=document.getElementById(id); if(el) place(el,sample(TR[id],t));}
  for(const id in CAP) capT(id,t);
  if(window.HOOK) HOOK(t);
};
"""


def page(theme, body, tracks, caps, hook_js):
    return f"""<!doctype html><html lang="nl"><head><meta charset="utf-8">
<link rel="stylesheet" href="{SITE}/assets/style.css"><link rel="stylesheet" href="{SITE}/assets/zakelijk.css">
<link rel="stylesheet" href="{SITE}/assets/zakelijk-v2.css">
<style>{css(theme)}</style></head><body>{body}
<script>const TR={json.dumps(tracks)};const CAP={json.dumps(caps)};{ENGINE}
{hook_js}
document.fonts.ready.then(()=>{{setT(0);window.__ready=true;}});</script></body></html>"""


def K(t, e="io", **p):
    return [t, p, e]


# =============================================================== PASR (klant) ==================================
def pasr():
    T = 19.0
    cards = [
        ("c1", member("Boekhuis De Linde", "Cadeaukaart", "Cadeaukaart", "Saldo € 25,00", "#7A3FD1", "B", "BL-7310 4482")),
        ("c2", member("Fietsplus Klantenkaart", "Klantenkaart", "Lid sinds 2026", "Nu 15% korting · t/m 15 dec", "#2F6FDE", "F", "FP-0048 2219")),
        ("c3", member("Bloemenhuis Vos", "Klantenkaart", "Lid sinds 2025", "", "#D9487A", "V", "BV-2291 0057")),
        ("c4", member("Sportschool Kracht", "Klantenkaart", "Lid sinds 2024", "Ledenpas", "#2D2B46", "S", "SK-5520 1186")),
    ]
    body = []
    body.append('<div class="el" id="brand" style="z-index:40;--ls:96px"><div class="brand"><img src="pasr-icon.png" alt=""><b>pasr</b></div></div>')
    body.append(caption("hook", ["Al je pasjes", "in <em>één app</em>"], 430, 128))
    body.append(caption("cap1", ["Klantenkaarten en", "<em>cadeaukaarten</em>"], 300, 104))
    body.append(caption("cap2", ["Spaar je", "<em>stempels</em>"], 300, 112))
    body.append(caption("cap3", ["Ook je", "<em>tickets</em>"], 300, 112))
    body.append(caption("cap4", ["In <em>Apple Wallet</em>", "en <em>Google Wallet</em>"], 300, 100))
    for i, (cid, html) in enumerate(cards):
        body.append(wrap(cid, html, z=2 + i))
    body.append(wrap("stamp", stamp_card(), z=10))
    body.append(wrap("ticket", TICKET, z=12))
    body.append(chip("plus", "+1 stempel", "white", z=14))
    body.append(chip("aw", CHECK + "Apple Wallet", "white", z=16))
    body.append(chip("gw", CHECK + "Google Wallet", "white", z=16))
    # Eindkaart
    body.append('<div class="el" id="e_icon" style="z-index:50"><img src="pasr-icon.png" alt="" style="width:300px;height:300px;border-radius:68px;box-shadow:0 30px 70px rgba(0,0,0,.45);display:block"></div>')
    body.append('<div class="el" id="e_name" style="z-index:50"><div style="font:800 150px \'Bricolage Grotesque\';letter-spacing:-.04em;line-height:1">pasr</div></div>')
    body.append('<div class="el" id="e_sub" style="z-index:50"><div class="sub2">Al je pasjes in één app</div></div>')
    body.append('<div class="el" id="e_url" style="z-index:50"><div class="url">Gratis · <em>pasr.nl</em></div></div>')
    body.append(f'<div class="el" id="e_badges" style="z-index:50">{badges()}</div>')

    # Waaier: kaarten vliegen van onder in en waaieren uit rond (540, 1130).
    fan = [(-150, 1200, -16), (-50, 1140, -6), (50, 1140, 6), (150, 1200, 16)]
    tr = {}
    for i, (cid, _) in enumerate(cards):
        dx, y, r = fan[i]
        t0 = 1.25 + i * 0.16
        tr[cid] = [K(0, x=540, y=2400, s=1.7, r=r * 2, o=1),
                   K(t0, x=540, y=2400, s=1.7, r=r * 2),
                   K(t0 + 0.9, "out", x=540 + dx, y=y, s=1.8, r=r),
                   K(3.4, x=540 + dx * 1.05, y=y - 10, s=1.8, r=r),
                   # Bij "Klantenkaarten en cadeaukaarten" schuiven ze als in een wallet onder elkaar
                   K(4.15, "io", x=540, y=735 + i * 188, s=1.85, r=0),
                   K(6.5, x=540, y=742 + i * 190, s=1.86, r=0),
                   # Samenschuiven tot een stapel achter de stempelkaart
                   K(7.2, "io", x=430 + i * 14, y=930 + i * 12, s=1.5, r=-8 + i * 1.5),
                   K(10.4, x=430 + i * 14, y=930 + i * 12, s=1.5, r=-8 + i * 1.5),
                   K(11.0, "io", x=360 + i * 10, y=900 + i * 10, s=1.35, r=-9 + i * 1.5),
                   K(13.0, x=360 + i * 10, y=900 + i * 10, s=1.35, r=-9 + i * 1.5),
                   K(13.5, x=390 + i * 10, y=880 + i * 10, s=1.25, r=-9 + i * 1.5),
                   K(15.2, x=390 + i * 10, y=880 + i * 10, s=1.25, r=-9 + i * 1.5, o=1),
                   K(15.8, "in", x=390 + i * 10, y=1000 + i * 10, s=1.0, r=-9 + i * 1.5, o=0)]
    tr["brand"] = [K(0, x=540, y=330, s=.9, o=0), K(.15), K(.7, "out", s=1, o=1), K(3.0, o=1), K(3.4, "in", y=290, o=0)]
    tr["stamp"] = [K(0, x=1600, y=1180, s=2.45, r=10, o=1), K(6.75), K(7.5, "out", x=540, y=1180, s=2.45, r=0),
                   K(10.2, x=540, y=1185, s=2.45, r=0),
                   K(10.9, "io", x=420, y=1250, s=1.75, r=-3),
                   K(13.0, x=420, y=1250, s=1.75, r=-3),
                   K(13.5, x=430, y=1190, s=1.6, r=-3),
                   K(15.2, x=430, y=1190, s=1.6, r=-3, o=1), K(15.8, "in", y=1300, s=1.3, o=0)]
    tr["plus"] = [K(0, x=840, y=920, s=.2, o=0), K(7.75), K(8.05, "back", s=1, o=1), K(10.0, s=1, o=1), K(10.3, "in", s=.6, o=0)]
    tr["ticket"] = [K(0, x=1700, y=1080, s=1.75, r=18, o=1), K(10.45), K(11.35, "out", x=720, y=1080, s=1.75, r=6),
                    K(13.0, x=730, y=1075, s=1.75, r=6),
                    K(13.5, x=720, y=1010, s=1.6, r=6),
                    K(15.2, x=720, y=1010, s=1.6, r=6, o=1), K(15.8, "in", y=1120, s=1.3, o=0)]
    tr["aw"] = [K(0, x=540, y=1420, s=.3, o=0), K(13.45), K(13.8, "back", s=1, o=1), K(15.2), K(15.6, "in", s=.7, o=0)]
    tr["gw"] = [K(0, x=540, y=1520, s=.3, o=0), K(13.7), K(14.05, "back", s=1, o=1), K(15.2), K(15.6, "in", s=.7, o=0)]
    # Eindkaart
    tr["e_icon"] = [K(0, x=540, y=640, s=.4, o=0), K(15.7), K(16.3, "back", s=1, o=1)]
    tr["e_name"] = [K(0, x=540, y=880, s=1, o=0), K(15.9), K(16.45, "out", y=860, o=1)]
    tr["e_name"][0][1]["y"] = 930
    tr["e_sub"] = [K(0, x=540, y=1050, o=0), K(16.05), K(16.6, "out", y=1000, o=1)]
    tr["e_url"] = [K(0, x=540, y=1170, o=0), K(16.2), K(16.75, "out", y=1130, o=1)]
    tr["e_badges"] = [K(0, x=540, y=1360, o=0, s=.9), K(16.35), K(16.9, "out", y=1300, s=1, o=1)]
    caps = {"hook": [0.35, 3.25, 0.13], "cap1": [3.55, 6.6, 0.12], "cap2": [7.0, 10.15, 0.12],
            "cap3": [10.45, 13.0, 0.12], "cap4": [13.25, 15.35, 0.1]}
    hook = r"""
const STS=[...document.querySelectorAll('#stamp .sc-stamp')]; const TOGO=document.querySelector('#stamp .togo');
const PLUS=document.getElementById('plus');
window.HOOK=function(t){
  document.body.style.setProperty('--gx',(50+18*Math.sin(t*0.35))+'%');
  document.body.style.setProperty('--gy',(100-30*Math.sin(t*0.25))+'%');
  let n=0;
  STS.forEach((s,i)=>{ if(s.classList.contains('gift')) return; const t0=7.7+i*0.26; const a=(t-t0)/0.32;
    if(a<=0){s.classList.remove('on');s.style.transform='';}
    else{s.classList.add('on');n++;const e=EZ.back(Math.min(1,a));s.style.transform=`scale(${0.2+0.8*e}) rotate(${(1-Math.min(1,a))*-40}deg)`;}});
  TOGO.textContent=(10-n)+' te gaan';
  // +1-chip springt bij elke nieuwe stempel even op
  const last=7.7+(n-1)*0.26; if(n>0&&t<10.0){const b=Math.max(0,1-(t-last)/0.25);PLUS.style.transform+=` translateY(${-14*b}px)`;}
};"""
    return T, page("dark", "".join(body), tr, caps, hook)


# =============================================================== PASR ZAKELIJK =================================
def zakelijk():
    T = 19.5
    canvas = (MEMBER + TICKET + STAMP.replace('class="sc demo"', 'class="sc"') + COUPON + CODE)
    # De hero-compositie van pasr.nl/zakelijk; elk onderdeel krijgt een id zodat het los kan invliegen.
    for cls, hid in (("zn-h-member", "h_member"), ("zn-h-ticket", "h_ticket"), ("zn-h-stamp", "h_stamp"),
                     ("zn-h-coupon", "h_coupon"), ("zn-h-code", "h_code")):
        canvas = canvas.replace(f'<div class="zn-h {cls}', f'<div id="{hid}" class="zn-h {cls}', 1)
    body = []
    body.append('<div class="el" id="brand" style="z-index:40;--ls:92px"><div class="brand"><img src="zakelijk-icon.png" alt=""><b>pasr</b><i class="tag">Zakelijk</i></div></div>')
    body.append(caption("hook", ["Laat je klanten", "<em>terugkomen</em>"], 430, 124))
    body.append(caption("cap1", ["Stempels, korting", "en <em>tickets</em>"], 300, 108))
    body.append(caption("cap2", ["Eén scan.", "<em>Klaar.</em>"], 300, 124))
    body.append(caption("cap3", ["Zie wat", "<em>werkt</em>"], 300, 124))
    body.append(f'<div class="el" id="hero" style="z-index:5"><div class="zn-fit" style="--fw:600;--fh:560;width:600px;max-width:none;overflow:visible;margin:0">'
                f'<div class="zn-canvas">{canvas}</div></div></div>')
    # Scanmoment: drie losse passen onder een scanner
    body.append(wrap("s_ticket", TICKET, z=10))
    body.append(wrap("s_stamp", STAMP.replace('class="sc demo"', 'class="sc"').replace('<span class="sc-stamp" style="--i:6">', '<span class="sc-stamp newst" style="--i:6">'), z=11))
    body.append(wrap("s_member", MEMBER, z=12))
    body.append('<div class="el" id="scan" style="z-index:20"><div class="scanframe"><i></i><i></i><i></i><i></i><span class="scanline"></span></div></div>')
    body.append(chip("r1", CHECK + '<span>Ticket geldig · <span id="cnt">85</span>/120 binnen</span>', "ok", z=25))
    body.append(chip("r2", "+1 stempel", "white", z=25))
    body.append(chip("r3", CHECK + "15% korting", "iris", z=25))
    body.append(f'<div class="el" id="dash" style="z-index:30"><div class="dashwin">{dash}</div></div>')
    # Eindkaart
    body.append('<div class="el" id="e_icon" style="z-index:50"><img src="zakelijk-icon.png" alt="" style="width:300px;height:300px;border-radius:68px;box-shadow:0 30px 70px rgba(23,22,42,.30);display:block"></div>')
    body.append('<div class="el" id="e_name" style="z-index:50;--ls:150px"><div class="brand" style="gap:30px"><b>pasr</b><i class="tag">Zakelijk</i></div></div>')
    body.append('<div class="el" id="e_sub" style="z-index:50"><div class="sub2">Gratis voor ondernemers</div></div>')
    body.append('<div class="el" id="e_url" style="z-index:50"><div class="url"><em>pasr.nl/zakelijk</em></div></div>')
    body.append(f'<div class="el" id="e_badges" style="z-index:50">{badges()}</div>')

    tr = {}
    tr["brand"] = [K(0, x=540, y=330, s=.9, o=0), K(.15), K(.7, "out", s=1, o=1), K(3.0, o=1), K(3.4, "in", y=290, o=0)]
    tr["hero"] = [K(0, x=540, y=1230, s=1.62, o=1), K(3.4), K(3.9, "io", y=1110, s=1.72), K(6.5, y=1100, s=1.74, o=1),
                  K(7.0, "in", y=1150, s=1.5, o=0)]
    tr["scan"] = [K(0, x=540, y=1165, s=1.0, o=0), K(6.9), K(7.3, "out", s=.86, o=1), K(10.7, s=.86, o=1), K(11.0, "in", s=1.0, o=0)]
    # passen onder de scanner: ticket-QR, stempelkaart, klantenkaart (barcode)
    tr["s_ticket"] = [K(0, x=1700, y=1010, s=1.72, r=12, o=1), K(6.85), K(7.45, "out", x=600, y=1010, s=1.72, r=0),
                      K(8.35, x=600, y=1010), K(8.85, "in", x=-700, r=-12)]
    tr["s_stamp"] = [K(0, x=1700, y=1130, s=2.6, r=12, o=1), K(8.45), K(9.05, "out", x=540, y=1130, r=0),
                     K(9.6), K(10.1, "in", x=-700, r=-12)]
    tr["s_member"] = [K(0, x=1700, y=1130, s=2.6, r=12, o=1), K(9.7), K(10.3, "out", x=540, y=1150, r=0),
                      K(10.75, o=1), K(11.1, "in", x=540, y=1250, s=2.2, o=0)]
    tr["r1"] = [K(0, x=540, y=1500, s=.3, o=0), K(7.75), K(8.05, "back", s=1, o=1), K(8.45), K(8.7, "in", s=.7, o=0)]
    tr["r2"] = [K(0, x=540, y=1520, s=.3, o=0), K(9.25), K(9.55, "back", s=1, o=1), K(9.75), K(10.0, "in", s=.7, o=0)]
    tr["r3"] = [K(0, x=540, y=1520, s=.3, o=0), K(10.45), K(10.75, "back", s=1, o=1), K(10.95), K(11.2, "in", s=.7, o=0)]
    tr["dash"] = [K(0, x=540, y=1200, s=.88, r=0, o=0), K(11.1), K(11.7, "out", y=1020, s=1, o=1),
                  K(14.3, y=1010, s=1, o=1), K(14.8, "in", y=960, s=.94, o=0)]
    tr["e_icon"] = [K(0, x=540, y=640, s=.4, o=0), K(14.85), K(15.45, "back", s=1, o=1)]
    tr["e_name"] = [K(0, x=540, y=930, o=0), K(15.05), K(15.6, "out", y=870, o=1)]
    tr["e_sub"] = [K(0, x=540, y=1050, o=0), K(15.2), K(15.75, "out", y=1010, o=1)]
    tr["e_url"] = [K(0, x=540, y=1170, o=0), K(15.35), K(15.9, "out", y=1130, o=1)]
    tr["e_badges"] = [K(0, x=540, y=1360, o=0, s=.9), K(15.5), K(16.05, "out", y=1300, s=1, o=1)]
    caps = {"hook": [0.35, 3.25, 0.13], "cap1": [3.55, 6.55, 0.12], "cap2": [7.0, 10.75, 0.18], "cap3": [11.2, 14.4, 0.14]}
    # Hero-onderdelen vliegen elk vanuit een andere richting in (relatief binnen het hero-canvas).
    fly = {"h_member": (-520, -80, -14, 1.25), "h_ticket": (520, -120, 14, 1.45), "h_stamp": (-520, 160, -10, 1.65),
           "h_coupon": (520, 200, 12, 1.85), "h_code": (-300, 420, -8, 2.05)}
    hook = "const FLY=" + json.dumps(fly) + r""";
const HE={}; for(const k in FLY) HE[k]=document.getElementById(k);
const ST=[...document.querySelectorAll('#s_stamp .sc-stamp')]; const NEW=document.querySelector('#s_stamp .newst');
const TOGO=document.querySelector('#s_stamp .sc-reward span:last-child');
const LINE=document.querySelector('#scan .scanline'); const CNT=document.getElementById('cnt');
const DZ=document.querySelector('#dash .znb');const KP=[...document.querySelectorAll('#dash .znb-kpi b')]; const KV=KP.map(b=>b.textContent);
window.HOOK=function(t){
  document.body.style.setProperty('--gx',(90-25*Math.sin(t*0.3))+'%');
  document.body.style.setProperty('--gy',(0+30*Math.sin(t*0.25))+'%');
  for(const k in FLY){const [dx,dy,r,t0]=FLY[k];const a=Math.max(0,Math.min(1,(t-t0)/0.8));const e=EZ.out(a);
    HE[k].style.transform=`translate(${dx*(1-e)}px,${dy*(1-e)}px) rotate(${r*(1-e)}deg)`;HE[k].style.opacity=Math.min(1,a*2.5);}
  // scanlijn beweegt op en neer zolang de scanner in beeld is
  LINE.style.top=(40+480*(0.5-0.5*Math.cos(t*Math.PI*1.6)))+'px';
  CNT.textContent=t<7.9?'85':'86';
  // nieuwe stempel op de stempelkaart
  const a=(t-9.25)/0.32; if(a<=0){NEW.classList.remove('on');NEW.style.transform='';TOGO.textContent='4 te gaan';}
  else{NEW.classList.add('on');NEW.style.transform=`scale(${0.2+0.8*EZ.back(Math.min(1,a))})`;TOGO.textContent='3 te gaan';}
  // KPI's tellen op
  const c=EZ.out(Math.max(0,Math.min(1,(t-11.9)/1.3)));
  // dashboard: eerst het hele scherm, dan inzoomen op de cijfers van Vandaag en naar rechts schuiven
  const z0=1000/1080, ty0=(640-560*z0)/2, z1=1.9;
  const zA=EZ.io(Math.max(0,Math.min(1,(t-12.0)/0.8))), pA=EZ.io(Math.max(0,Math.min(1,(t-12.9)/1.2)));
  const z=z0+(z1-z0)*zA; const fx=434+(1060-434)*pA, fy=215;
  let tx=(500-fx*z1)*zA, ty=ty0+((320-fy*z1)-ty0)*zA; tx=Math.max(tx,1000-1080*z); tx=Math.min(tx,0);
  DZ.style.transform=`translate(${tx}px,${ty}px) scale(${z})`;
  KP.forEach((b,i)=>{const v=KV[i];const num=parseFloat(v);const suf=v.replace(/[0-9.]/g,'');b.textContent=Math.round(num*c)+suf;});
};"""
    return T, page("light", "".join(body), tr, caps, hook)


if __name__ == "__main__":
    meta = {}
    for key, fn in (("pasr", pasr), ("zakelijk", zakelijk)):
        T, html = fn()
        open(f"{B}/reel-{key}.html", "w").write(html)
        meta[key] = T
    json.dump(meta, open(f"{B}/reels.json", "w"))
    print("ok", meta)
