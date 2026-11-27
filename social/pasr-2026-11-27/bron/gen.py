"""Genereert de HTML-bronnen voor de social banners van Pasr en Pasr Zakelijk (campagne 2026-11-27).
De passen (stempelkaart .sc, klantenkaart .zm, ticket .zt) komen letterlijk uit de hero van pasr.nl/zakelijk
(tools/zakelijk_v2.py) en gebruiken de CSS van de site (http://localhost:8765 = website/)."""
import os, re, sys

B = os.path.dirname(os.path.abspath(__file__)) + "/build"
SITE = "http://localhost:8765"
hero = open(B + "/hero_panel.html").read()

def piece(cls):
    i = hero.find('<div class="zn-h ' + cls)
    j = hero.find('<div class="zn-h ', i + 10)
    if j < 0:
        j = hero.find('<span class="zn-chip', i)
    return hero[i:j]

MEMBER = piece("zn-h-member")
TICKET = piece("zn-h-ticket")
STAMP = piece("zn-h-stamp")
COUPON = piece("zn-h-coupon")
CODE = piece("zn-h-code")
CHIPS = hero[hero.find('<span class="zn-chip zn-chip-stamp'):]
CHIPS = CHIPS[:CHIPS.find('</div>')]
HERO_CANVAS = MEMBER + TICKET + STAMP + COUPON + CODE + CHIPS

# Barcode-svg van de klantenkaart hergebruiken voor de cadeaukaart.
BAR = re.search(r'<span class="zm-bar">.*?</span>', MEMBER, re.S).group(0)
CHECK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5 10 17 19 7"/></svg>'
GIFT = ('<div class="zn-h" style="left:30px;top:4px"><div class="zn-tilt" style="--r:-14deg"><div class="zm" style="--c:#7A3FD1;width:290px">'
        '<div class="zm-head"><span class="zm-logo">B</span><span class="zm-t"><b>Boekhuis De Linde</b><small>Cadeaukaart</small></span><em>Cadeaukaart</em></div>'
        '<span class="zm-chip">Saldo € 25,00 · t/m 2027</span>' + BAR.replace('FP-0048 2219', 'BL-7310 4482') + '</div></div></div>')
# Consumentenscène: cadeaukaart + klantenkaart + ticket + stempelkaart, met Wallet-chip.
CONSUMER_CANVAS = (GIFT + MEMBER.replace('class="zn-h zn-h-member zc-ol"', 'class="zn-h zn-h-member" style="top:84px"') + TICKET + STAMP +
                   '<span class="zn-chip zn-chip-stamp">+1 stempel</span>'
                   '<span class="zn-chip zn-chip-ok" style="background:#17162A;top:506px">' + CHECK + 'Ook in Apple Wallet</span>')

ANDROID_SVG = ('<svg viewBox="0 0 24 24" aria-hidden="true"><g fill="#2ED3A6"><path d="M6.2 9.3a5.8 5.8 0 0 1 11.6 0z"/><path d="M8.3 4.4 7 2.4M15.7 4.4 17 2.4" stroke="#2ED3A6" stroke-width=".9" stroke-linecap="round"/>'
               '<path d="M6.2 10h11.6v7.6a1.4 1.4 0 0 1-1.4 1.4H7.6a1.4 1.4 0 0 1-1.4-1.4z"/><rect x="3.4" y="10" width="2.1" height="6.6" rx="1.05"/><rect x="18.5" y="10" width="2.1" height="6.6" rx="1.05"/>'
               '<rect x="8.4" y="17.6" width="2.1" height="4.4" rx="1.05"/><rect x="13.5" y="17.6" width="2.1" height="4.4" rx="1.05"/></g>'
               '<circle cx="9.4" cy="7.1" r=".65" fill="#000"/><circle cx="14.6" cy="7.1" r=".65" fill="#000"/></svg>')

SETS = {
    "pasr": dict(
        theme="dark", icon="pasr-icon.png", tag="",
        kicker="Gratis · zonder reclame",
        head='Al je kaarten in <em>één app</em>', head_stack='Al je kaarten<br>in <em>één app</em>',
        sub="Klantenkaarten, cadeaukaarten, stempelkaarten en tickets. Ook in Apple Wallet.",
        sub_short="Klantenkaarten, cadeaukaarten, stempelkaarten en tickets.",
        url="pasr.nl", canvas=CONSUMER_CANVAS, fw=600, fh=560,
    ),
    "zakelijk": dict(
        theme="light", icon="zakelijk-icon.png", tag='<i class="tag">Zakelijk</i>',
        kicker="Gratis voor ondernemers",
        head='Laat je klanten <em>terugkomen</em>', head_stack='Laat je klanten<br><em>terugkomen</em>',
        sub="Stempelkaart, klantenkaart, tickets, kortingsbonnen en actiecodes. Eén scanner, één dashboard.",
        sub_short="Stempelkaarten, klantenkaarten, tickets en kortingsbonnen. Eén scanner.",
        url="pasr.nl/zakelijk", canvas=HERO_CANVAS, fw=600, fh=560,
        platforms="iPhone · Android · Mac · web",
    ),
}

# Per formaat: maten (px) van de bouwstenen.
FORMATS = {
    "instagram-post-1080x1080": dict(w=1080, h=1080, lay="stack", pad=72, logo=64, h1=84, sub=32, scene=560, badge=74, url=36, gap=26),
    "instagram-post-1080x1350": dict(w=1080, h=1350, lay="stack", pad=80, logo=72, h1=96, sub=36, scene=760, badge=82, url=40, gap=32),
    "story-1080x1920": dict(w=1080, h=1920, lay="stack", pad=80, top=250, bottom=250, logo=80, h1=110, sub=40, scene=900, badge=92, url=44, gap=40),
    "linkedin-post-1200x627": dict(w=1200, h=627, lay="side", pad=72, logo=52, h1=66, sub=26, scene=560, badge=60, url=30, gap=20, textw=560),
    "facebook-cover-1640x624": dict(w=1640, h=624, lay="side", pad=200, logo=54, h1=72, sub=28, scene=590, badge=64, url=32, gap=22, textw=640),
    "linkedin-cover-1584x396": dict(w=1584, h=396, lay="cover", pad=420, logo=44, h1=56, sub=24, scene=470, badge=0, url=30, gap=14, textw=620),
}

def css(s, f):
    dark = s["theme"] == "dark"
    bg = ("radial-gradient(ellipse at 50% -10%, rgba(106,92,255,.55), transparent 55%),"
          "radial-gradient(ellipse at 100% 105%, rgba(255,107,87,.28), transparent 45%),"
          "radial-gradient(ellipse at 0% 100%, rgba(46,211,166,.16), transparent 45%), #0E0D1A") if dark else \
         ("radial-gradient(ellipse at 95% 0%, rgba(106,92,255,.30), transparent 50%),"
          "radial-gradient(ellipse at 90% 100%, rgba(46,211,166,.30), transparent 55%),"
          "radial-gradient(ellipse at 0% 0%, rgba(46,211,166,.12), transparent 40%), #F4F3FF")
    ink = "#FFFFFF" if dark else "#17162A"
    ink2 = "#C9C6E8" if dark else "#4B4966"
    accent = "linear-gradient(90deg,#A79BFF,#FF8A78)" if dark else "linear-gradient(90deg,#4A3CE0,#0E8A62)"
    kick_bg = "rgba(255,255,255,.10)" if dark else "#DDF5EC"
    kick_ink = "#D9D4FF" if dark else "#0B6E4F"
    bh = f["badge"]
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
html,body{{margin:0;width:{f['w']}px;height:{f['h']}px;overflow:hidden}}
body{{background:{bg};color:{ink};font-family:"Figtree",system-ui,sans-serif;position:relative}}
.sb-brand{{display:flex;align-items:center;gap:{f['logo']*0.28:.0f}px}}
.sb-brand img{{width:{f['logo']}px;height:{f['logo']}px;border-radius:{f['logo']*0.225:.0f}px;box-shadow:0 8px 24px rgba(0,0,0,.28)}}
.sb-brand b{{font:800 {f['logo']*0.82:.0f}px "Bricolage Grotesque";letter-spacing:-.03em;color:{ink}}}
.sb-brand .tag{{font:700 {f['logo']*0.30:.0f}px "Figtree";font-style:normal;letter-spacing:.05em;text-transform:uppercase;color:#fff;
  background:linear-gradient(135deg,#12A77E,#0E8A62);border-radius:{f['logo']*0.14:.0f}px;padding:{f['logo']*0.07:.0f}px {f['logo']*0.16:.0f}px}}
.kicker{{display:inline-block;font:800 {f['sub']*0.62:.0f}px "Figtree";letter-spacing:.09em;text-transform:uppercase;color:{kick_ink};
  background:{kick_bg};border-radius:999px;padding:{f['sub']*0.28:.0f}px {f['sub']*0.6:.0f}px}}
h1{{margin:0;font:800 {f['h1']}px/1.0 "Bricolage Grotesque";letter-spacing:-.035em;color:{ink}}}
h1 em{{font-style:normal;background:{accent};-webkit-background-clip:text;background-clip:text;color:transparent}}
p.sub{{text-wrap:balance;margin:0;font:500 {f['sub']}px/1.32 "Figtree";color:{ink2}}}
.sb-platforms{{font:600 {f['sub']*0.72:.0f}px "Figtree";color:{ink2};letter-spacing:.01em}}
.sb-cta{{display:flex;align-items:center;gap:{bh*0.24:.0f}px}}
.sb-cta img.apple{{height:{bh}px;width:auto;display:block}}
.android{{display:inline-flex;align-items:center;justify-content:center;gap:{bh*0.16:.0f}px;box-sizing:border-box;height:{bh}px;width:{bh*2.99:.0f}px;
  padding:0 {bh*0.18:.0f}px;border-radius:{bh*0.17:.0f}px;background:#000;border:{max(1,bh/50):.1f}px solid #A6A6A6;color:#fff;line-height:1.05}}
.android svg{{width:{bh*0.56:.0f}px;height:{bh*0.56:.0f}px;flex:none}}
.android span{{display:flex;flex-direction:column;font:500 {bh*0.36:.0f}px "Figtree";letter-spacing:-.01em}}
.android small{{font-size:{bh*0.18:.0f}px;margin-bottom:{bh*0.03:.0f}px}}
.url{{font:800 {f['url']}px "Bricolage Grotesque";letter-spacing:-.02em;color:{ink}}}
.scene{{width:{f['scene']}px;flex:none}}
.slot{{position:relative;overflow:visible}}
.slot .fitbox{{position:absolute;left:0;top:0;width:{s['fw']}px;transform-origin:0 0}}
.slot .zn-fit{{max-width:none;margin:0;overflow:visible}}
.sc .sc-stamp.on::before{{-webkit-mask-image:url(pasr-stamp.svg)!important;mask-image:url(pasr-stamp.svg)!important}}
.scene .zn-fit{{overflow:visible}}
"""

def badges(f):
    return (f'<div class="sb-cta"><img class="apple" src="appstore-nl-zwart.svg" alt="Download in de App Store">'
            f'<span class="android">{ANDROID_SVG}<span><small>Download voor</small>Android</span></span></div>')

def scene(s, f, style=""):
    return (f'<div class="slot" style="{style}"><div class="fitbox"><div class="zn-fit" style="--fw:{s["fw"]};--fh:{s["fh"]}"><div class="zn-canvas">'
            f'{s["canvas"]}</div></div></div></div>')

FIT_JS = '''<script>
document.fonts.ready.then(()=>requestAnimationFrame(()=>{
 document.querySelectorAll('.slot').forEach(sl=>{
  const fb=sl.querySelector('.fitbox'); const sr=sl.getBoundingClientRect();
  let x0=1e9,y0=1e9,x1=-1e9,y1=-1e9;
  fb.querySelectorAll('.zn-canvas *').forEach(e=>{const r=e.getBoundingClientRect(); if(!r.width||!r.height)return;
   x0=Math.min(x0,r.left);y0=Math.min(y0,r.top);x1=Math.max(x1,r.right);y1=Math.max(y1,r.bottom);});
  const uw=x1-x0, uh=y1-y0, k=Math.min(sr.width/uw, sr.height/uh);
  const ox=(x0-sr.left), oy=(y0-sr.top);
  const tx=(sr.width-uw*k)/2 - ox*k, ty=(sr.height-uh*k)/2 - oy*k;
  fb.style.transform=`translate(${tx}px,${ty}px) scale(${k})`;
 }); window.__fit=true;}));
</script>'''

def body(s, f):
    brand = f'<div class="sb-brand"><img src="{s["icon"]}" alt=""><b>pasr</b>{s["tag"]}</div>'
    plat = f'<div class="sb-platforms">{s["platforms"]}</div>' if s.get("platforms") else ""
    if f["lay"] == "stack":
        top = f.get("top", f["pad"]); bot = f.get("bottom", f["pad"])
        return f"""<div style="position:absolute;inset:{top}px {f['pad']}px {bot}px;display:flex;flex-direction:column;align-items:center;text-align:center;gap:{f['gap']}px">
  {brand}
  <h1>{s['head_stack']}</h1>
  <p class="sub" style="max-width:{f['w']-2*f['pad']-40}px">{s['sub']}</p>
  {scene(s, f, f"flex:1;min-height:0;width:{f['scene']}px;margin:{f['gap']*0.4:.0f}px 0")}
  <div style="display:flex;flex-direction:column;align-items:center;gap:{f['gap']*0.6:.0f}px">{badges(f)}<div class="url">{s['url']}</div></div>
</div>"""
    if f["lay"] == "side":
        return f"""<div style="position:absolute;inset:0 {f['pad']}px;display:flex;align-items:center;justify-content:space-between;gap:30px">
  <div style="width:{f['textw']}px;display:flex;flex-direction:column;align-items:flex-start;gap:{f['gap']}px">
    {brand}
    <h1>{s['head_stack']}</h1>
    <p class="sub">{s['sub']}</p>
    {badges(f)}
    <div class="url">{s['url']}</div>
  </div>
  {scene(s, f, f"width:{f['scene']}px;height:{f['h']-2*f.get('vpad',60)}px;flex:none")}
</div>"""
    # cover: LinkedIn (profielfoto/logo linksonder; tekst in het midden, scène rechts)
    return f"""<div style="position:absolute;inset:0 90px 0 {f['pad']}px;display:flex;align-items:center;justify-content:space-between;gap:30px">
  <div style="width:{f['textw']}px;display:flex;flex-direction:column;align-items:flex-start;gap:{f['gap']}px">
    {brand}
    <h1>{s['head_stack']}</h1>
    <p class="sub">{s['sub_short']}</p>
    <div class="url">{s['url']}</div>
  </div>
  {scene(s, f, f"width:{f['scene']}px;height:{f['h']-2*f.get('vpad',40)}px;flex:none")}
</div>"""

def page(key, fname):
    s, f = SETS[key], FORMATS[fname]
    return f"""<!doctype html><html lang="nl"><head><meta charset="utf-8">
<link rel="stylesheet" href="{SITE}/assets/style.css"><link rel="stylesheet" href="{SITE}/assets/zakelijk.css">
<link rel="stylesheet" href="{SITE}/assets/zakelijk-v2.css">
<style>{css(s, f)}</style></head><body>{body(s, f)}{FIT_JS}</body></html>"""

if __name__ == "__main__":
    for key in SETS:
        for fname in FORMATS:
            open(f"{B}/{key}-{fname}.html", "w").write(page(key, fname))
    print("ok")
