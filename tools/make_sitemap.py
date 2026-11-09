#!/usr/bin/env python3
"""Maakt website/sitemap.xml uit de pagina's zelf: alleen indexeerbare pagina's met een canonical-adres.
lastmod = datum van de laatste git-commit die de pagina veranderde (geen datum van vandaag op alles).
Gebruik: python3 tools/make_sitemap.py"""
import glob, os, re, subprocess, html
from xml.sax.saxutils import escape

ROOT = os.path.join(os.path.dirname(__file__), "..", "website")
entries = []
for f in sorted(glob.glob(os.path.join(ROOT, "**", "index.html"), recursive=True)):
    t = open(f, encoding="utf-8").read()
    robots = re.search(r'<meta name="robots" content="([^"]*)"', t)
    if robots and "noindex" in robots.group(1):
        continue
    can = re.search(r'<link rel="canonical" href="([^"]+)"', t)
    if not can:
        continue
    rel = os.path.relpath(f, os.path.join(ROOT, ".."))
    try:
        day = subprocess.run(["git", "log", "-1", "--format=%cs", "--", rel], cwd=os.path.join(ROOT, ".."),
                             capture_output=True, text=True).stdout.strip()
    except Exception:
        day = ""
    og = re.search(r'<meta property="og:image" content="([^"]+)"', t)
    entries.append((html.unescape(can.group(1)), day, og.group(1) if og else None))

entries.sort(key=lambda e: (e[0] != "https://pasr.nl/", e[0]))
out = ['<?xml version="1.0" encoding="UTF-8"?>',
       '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">']
for url, day, img in entries:
    out.append("  <url>")
    out.append(f"    <loc>{escape(url)}</loc>")
    if day:
        out.append(f"    <lastmod>{day}</lastmod>")
    if img:
        out.append(f"    <image:image><image:loc>{escape(img)}</image:loc></image:image>")
    out.append("  </url>")
out.append("</urlset>")
open(os.path.join(ROOT, "sitemap.xml"), "w", encoding="utf-8").write("\n".join(out) + "\n")
print(f"sitemap.xml: {len(entries)} pagina's")
