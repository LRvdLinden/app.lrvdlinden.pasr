#!/usr/bin/env python3
"""Fetch the logo of every store in Shared/Model/StoreTemplates.swift and save it as
Shared/StoreLogos/<domain>.png (square, 160 px). Runs in GitHub Actions (Actions › Logos),
because that machine can reach the store websites.

Order per store: the icon the home page declares (apple-touch-icon first, largest first),
the usual /apple-touch-icon.png, then the site icon via Google's favicon service.
Existing files are kept unless --all is given. Writes tools/logos-missing.txt.
"""
import concurrent.futures as cf
import io
import re
import sys
import urllib.parse
from pathlib import Path

import requests
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Shared" / "StoreLogos"
SIZE = 160
UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
S = requests.Session()
S.headers.update({"User-Agent": UA, "Accept-Language": "nl-NL,nl;q=0.9"})


def domains():
    src = (ROOT / "Shared/Model/StoreTemplates.swift").read_text()
    return sorted({d for d in re.findall(r'domain: "([^"]+)"', src) if d})


def manifest_icons(html, base):
    m = re.search(r'<link\b[^>]*rel=["\']?manifest[^>]*>', html, re.I)
    href = m and re.search(r'href=["\']?([^"\'\s>]+)', m.group(0))
    if not href:
        return []
    try:
        url = urllib.parse.urljoin(base, href.group(1).replace("&amp;", "&"))
        icons = S.get(url, timeout=12).json().get("icons", [])
    except Exception:
        return []
    def size(i):
        m = re.match(r"(\d+)", str(i.get("sizes", "")))
        return int(m.group(1)) if m else 0
    return [urllib.parse.urljoin(url, i["src"]) for i in sorted(icons, key=lambda i: -size(i))
            if i.get("src") and not i["src"].lower().endswith(".svg") and "monochrome" not in str(i.get("purpose", ""))]


def icon_links(html, base):
    found = []
    for tag in re.findall(r"<link\b[^>]*>", html, re.I):
        attrs = {k.lower(): (a or b or c) for k, a, b, c in
                 re.findall(r'([a-zA-Z-]+)\s*=\s*(?:"([^"]*)"|\'([^\']*)\'|([^\s>]+))', tag)}
        rel = attrs.get("rel", "").lower()
        href = attrs.get("href", "")
        if "icon" not in rel or "mask" in rel or not href or href.lower().endswith(".svg"):
            continue
        m = re.match(r"(\d+)", attrs.get("sizes", ""))
        score = (10000 if "apple-touch-icon" in rel else 0) + (int(m.group(1)) if m else 0)
        found.append((urllib.parse.urljoin(base, href.replace("&amp;", "&")), score))
    return [u for u, _ in sorted(found, key=lambda x: -x[1])]


def load(url, min_side):
    try:
        r = S.get(url, timeout=12)
        if r.status_code >= 400 or len(r.content) > 4_000_000:
            return None
        img = Image.open(io.BytesIO(r.content))
        if getattr(img, "n_frames", 1) > 1 and img.format == "ICO":
            img = max((img.ico.getimage(s) for s in img.ico.sizes()), key=lambda i: i.width)
        img = img.convert("RGBA")
        if min(img.size) < min_side:
            return None
        return img
    except Exception:
        return None


def square(img):
    # Trim fully transparent edges, then centre on a square canvas.
    bbox = img.getchannel("A").getbbox()
    if bbox:
        img = img.crop(bbox)
    side = max(img.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


# Sites whose own icon is not their logo (e.g. a country flag): use the icon services only.
SKIP_SITE = {"aktiesport.nl", "perrysport.nl", "sportsdirect.com"}


def fetch(domain):
    candidates = []
    for home in () if domain in SKIP_SITE else (f"https://www.{domain}/", f"https://{domain}/"):
        try:
            r = S.get(home, timeout=12)
            if r.ok:
                html = r.text[:800_000]
                candidates += icon_links(html, r.url) + manifest_icons(html, r.url)
                break
        except Exception:
            continue
    if domain not in SKIP_SITE:
        candidates += [f"https://www.{domain}/apple-touch-icon.png", f"https://{domain}/apple-touch-icon.png"]
    seen = set()
    for url in candidates:
        if url in seen:
            continue
        seen.add(url)
        img = load(url, 96)
        if img:
            return square(img)
    # Icon services, for sites that turn away scripts.
    for url in (f"https://t1.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL"
                f"&url=https://www.{domain}&size=256",
                f"https://www.google.com/s2/favicons?domain={domain}&sz=256",
                f"https://icons.duckduckgo.com/ip3/{domain}.ico",
                f"https://www.{domain}/favicon.ico"):
        if domain in SKIP_SITE and domain in url and "gstatic" not in url and "google" not in url:
            continue
        img = load(url, 64)
        if img:
            return square(img)
    return None


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    redo = "--all" in sys.argv
    todo = [d for d in domains() if redo or not (OUT / f"{d}.png").exists()]
    missing = []

    def work(d):
        img = fetch(d)
        if img:
            img.save(OUT / f"{d}.png", optimize=True)
            return d, True
        return d, False

    with cf.ThreadPoolExecutor(12) as pool:
        for d, ok in pool.map(work, todo):
            print(("ok      " if ok else "MISSING ") + d, flush=True)
            if not ok:
                missing.append(d)
    all_missing = sorted(d for d in domains() if not (OUT / f"{d}.png").exists())
    (ROOT / "tools" / "logos-missing.txt").write_text("".join(f"{d}\n" for d in all_missing))
    print(f"\n{len(domains()) - len(all_missing)} logos, {len(all_missing)} missing")


if __name__ == "__main__":
    main()
