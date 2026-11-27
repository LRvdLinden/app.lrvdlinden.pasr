#!/usr/bin/env python3
"""De knop "Voeg toe aan Pasr" (variant A): kaartenstapel uit het app-icoon + twee regels tekst.

Maakt (reproduceerbaar, tekst als paden, dus overal exact hetzelfde):
  website/badge/nl/{zwart,wit,nachtblauw}{,-compact}.svg
  website/badge/nl/{…}{,@2x,@3x}.png                       (PNG voor drukwerk en mails)
  zakelijk/apple/PasrZakelijk/Assets.xcassets/PasrBadge-*.imageset   (Pasr Zakelijk iOS: voorbeeld in "Knop voor je website")
  android/zakelijk/app/src/main/res/drawable-nodpi/pasr_badge_*.png  (Pasr Zakelijk Android)

Alleen Nederlands ("Voeg toe aan / Pasr"), op verzoek van Léon. Geen Apple-logo of Wallet-merk.
Lettertypen: tools/og/fonts (Figtree 600 voor de kleine regel, Bricolage Grotesque 800 voor "Pasr").

Nodig: pip install fonttools uharfbuzz playwright && playwright install chromium
Draaien:  python3 tools/make_badges.py          (alles)
          python3 tools/make_badges.py --svg    (alleen de SVG's, zonder browser)
"""
import io
import json
import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
import uharfbuzz as hb

REPO = Path(__file__).resolve().parent.parent
FONTS = REPO / "tools" / "og" / "fonts"
OUT = REPO / "website" / "badge" / "nl"
XCASSETS = REPO / "zakelijk" / "apple" / "PasrZakelijk" / "Assets.xcassets"
DRAWABLE = REPO / "android" / "zakelijk" / "app" / "src" / "main" / "res" / "drawable-nodpi"

THEMES = ("zwart", "wit", "nachtblauw")
SMALL, BIG = "Voeg toe aan", "Pasr"


def _instance(path, axes):
    font = instancer.instantiateVariableFont(TTFont(path), axes)
    buf = io.BytesIO()
    font.save(buf)
    return font, buf.getvalue()


FIGTREE = _instance(FONTS / "Figtree.ttf", {"wght": 600})
BRICOLAGE = _instance(FONTS / "BricolageGrotesque.ttf", {"wght": 800, "opsz": 24, "wdth": 100})


def text_path(text, font, size, x, baseline, tracking=0.0):
    """Tekst als één SVG-pad (met kerning via HarfBuzz). Geeft (pad, breedte in px)."""
    tt, data = font
    upem = tt["head"].unitsPerEm
    hbfont = hb.Font(hb.Face(data))
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(hbfont, buf, {"kern": True, "liga": True})
    glyphs = tt.getGlyphSet()
    order = tt.getGlyphOrder()
    scale = size / upem
    pen = SVGPathPen(glyphs, ntos=lambda v: f"{v:.2f}".rstrip("0").rstrip("."))
    cx = 0.0
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        name = order[info.codepoint]
        t = TransformPen(pen, (scale, 0, 0, -scale, x + (cx + pos.x_offset) * scale, baseline - pos.y_offset * scale))
        glyphs[name].draw(t)
        cx += pos.x_advance + tracking * upem / size
    return pen.getCommands(), cx * scale


def stack(size, x, y, uid):
    """Kaartenstapel uit het app-icoon: groen achter, paars midden, koraal (verloop) voor met streepjescode."""
    bars = "".join(
        f'<rect x="{17.2 + i * 1.7:.2f}" y="18.8" width="{0.6 if i % 2 else 1.0}" height="{5.4 if i % 3 else 6}" rx=".25" fill="#fff" opacity=".95"/>'
        for i in range(11))
    s = size / 40
    return (f'<g transform="translate({x:.2f} {y:.2f}) scale({s:.4f})">'
            f'<g transform="rotate(-18 11 26)"><rect x="0.5" y="18" width="21" height="15" rx="3" fill="#50D7B3"/>'
            f'<rect x="2.9" y="20.3" width="6" height="1.7" rx=".85" fill="#fff" opacity=".5"/></g>'
            f'<g transform="rotate(-9 16 22)"><rect x="5" y="14" width="22" height="15" rx="3" fill="#8075FA"/>'
            f'<rect x="7.4" y="16.3" width="6" height="1.7" rx=".85" fill="#fff" opacity=".5"/></g>'
            f'<g transform="rotate(5 27 16)"><rect x="14" y="7" width="25" height="17.5" rx="3.4" fill="url(#{uid}c)"/>'
            f'<rect x="17" y="10" width="8.5" height="2" rx="1" fill="#fff" opacity=".55"/>{bars}</g></g>')


def badge(theme, compact=False):
    """De knop als SVG-tekst plus (breedte, hoogte)."""
    uid = f"p{theme[0]}{'c' if compact else 'g'}"
    ink = "#000" if theme == "wit" else "#fff"
    if compact:
        h, icon, left, gap, right = 38, 26, 9, 10, 14
        small_path, sw = text_path(SMALL, FIGTREE, 12.5, 0, 0)
        big_path, bw = text_path(BIG, BRICOLAGE, 18, 0, 0, tracking=-0.3)
        tx = left + icon + gap
        base = 25.2
        sp, _ = text_path(SMALL, FIGTREE, 12.5, tx, base)
        bp, _ = text_path(BIG, BRICOLAGE, 18, tx + sw + 5, base, tracking=-0.3)
        w = tx + sw + 5 + bw + right
    else:
        h, icon, left, gap, right = 52, 38, 12, 10, 18
        _, sw = text_path(SMALL, FIGTREE, 12, 0, 0)
        _, bw = text_path(BIG, BRICOLAGE, 24, 0, 0, tracking=-0.4)
        tx = left + icon + gap
        sp, _ = text_path(SMALL, FIGTREE, 12, tx, 20.2)
        bp, _ = text_path(BIG, BRICOLAGE, 24, tx, 41.2, tracking=-0.4)
        w = tx + max(sw, bw) + right
    w = round(w)
    r = 12 if not compact else 10
    defs = (f'<linearGradient id="{uid}c" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#F6836F"/>'
            f'<stop offset="1" stop-color="#C95646"/></linearGradient>')
    if theme == "zwart":
        bg = f'<rect width="{w}" height="{h}" rx="{r}" fill="#000"/>'
    elif theme == "wit":
        bg = f'<rect x=".75" y=".75" width="{w - 1.5}" height="{h - 1.5}" rx="{r - .75}" fill="#fff" stroke="#000" stroke-width="1.5"/>'
    else:
        defs += (f'<radialGradient id="{uid}n" gradientUnits="userSpaceOnUse" cx="{w * .2:.1f}" cy="{h * .9:.1f}" r="{w * 1.2:.1f}" '
                 f'gradientTransform="translate({w * .2:.1f} {h * .9:.1f}) scale(1 {1.4 * h / (1.2 * w):.4f}) translate({-w * .2:.1f} {-h * .9:.1f})">'
                 f'<stop offset="0" stop-color="#2A2463"/><stop offset=".6" stop-color="#171925"/><stop offset="1" stop-color="#171925"/></radialGradient>')
        bg = (f'<rect width="{w}" height="{h}" rx="{r}" fill="url(#{uid}n)"/>'
              f'<rect x=".5" y=".5" width="{w - 1}" height="{h - 1}" rx="{r - .5}" fill="none" stroke="#2A2463"/>'
              f'<rect x="1.5" y="1.5" width="{w - 3}" height="{h - 3}" rx="{r - 1.5}" fill="none" stroke="#8075FA" stroke-opacity=".35"/>')
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="Voeg toe aan Pasr">'
           f'<title>Voeg toe aan Pasr</title><defs>{defs}</defs>{bg}'
           f'{stack(icon, left, (h - icon) / 2, uid)}'
           f'<path fill="{ink}" d="{sp}"/><path fill="{ink}" d="{bp}"/></svg>\n')
    return svg, w, h


def names():
    for theme in THEMES:
        for compact in (False, True):
            yield theme, compact, theme + ("-compact" if compact else "")


def write_svgs():
    OUT.mkdir(parents=True, exist_ok=True)
    sizes = {}
    for theme, compact, name in names():
        svg, w, h = badge(theme, compact)
        (OUT / f"{name}.svg").write_text(svg, encoding="utf-8")
        sizes[name] = [w, h]
    (OUT / "sizes.json").write_text(json.dumps(sizes, indent=1) + "\n", encoding="utf-8")
    print("SVG:", ", ".join(f"{k} {v[0]}x{v[1]}" for k, v in sizes.items()))
    return sizes


def write_pngs(sizes):
    import asyncio
    from playwright.async_api import async_playwright

    async def run():
        async with async_playwright() as p:
            browser = await p.chromium.launch()
            for scale in (1, 2, 3):
                page = await browser.new_page(device_scale_factor=scale)
                for theme, compact, name in names():
                    w, h = sizes[name]
                    svg = (OUT / f"{name}.svg").read_text(encoding="utf-8")
                    await page.set_viewport_size({"width": w, "height": h})
                    await page.set_content(f'<html><body style="margin:0;background:transparent">{svg}</body></html>')
                    suffix = "" if scale == 1 else f"@{scale}x"
                    await page.locator("svg").screenshot(path=str(OUT / f"{name}{suffix}.png"), omit_background=True)
                await page.close()
            await browser.close()
    asyncio.run(run())
    print("PNG @1x/@2x/@3x in", OUT.relative_to(REPO))


def write_app_assets():
    """Voorbeeld in Pasr Zakelijk (iOS asset catalog en Android drawable), uit dezelfde PNG's."""
    import shutil
    DRAWABLE.mkdir(parents=True, exist_ok=True)
    for theme, compact, name in names():
        asset = "PasrBadge-" + name
        d = XCASSETS / f"{asset}.imageset"
        d.mkdir(parents=True, exist_ok=True)
        shutil.copy2(OUT / f"{name}@2x.png", d / f"{asset}@2x.png")
        shutil.copy2(OUT / f"{name}@3x.png", d / f"{asset}@3x.png")
        (d / "Contents.json").write_text(json.dumps({
            "images": [{"idiom": "universal", "scale": "1x"},
                       {"filename": f"{asset}@2x.png", "idiom": "universal", "scale": "2x"},
                       {"filename": f"{asset}@3x.png", "idiom": "universal", "scale": "3x"}],
            "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
        shutil.copy2(OUT / f"{name}@3x.png", DRAWABLE / f"pasr_badge_{name.replace('-', '_')}.png")
    print("App-voorbeelden in", XCASSETS.relative_to(REPO), "en", DRAWABLE.relative_to(REPO))


if __name__ == "__main__":
    s = write_svgs()
    if "--svg" not in sys.argv:
        write_pngs(s)
        write_app_assets()
