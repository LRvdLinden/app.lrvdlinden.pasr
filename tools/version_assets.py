#!/usr/bin/env python3
"""Zet een versie achter de css/js-bestanden in alle pagina's (…/style.css?v=1a2b3c4d), zodat browsers na een
nieuwe versie van de site meteen de nieuwe bestanden laden (ze worden een week gecachet).
Draait in de Website-workflow vlak voor het uploaden; lokaal mag ook: python3 tools/version_assets.py"""
import hashlib, re
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent / "website"
REF = re.compile(r'(["\'])(/assets/[\w./-]+\.(?:css|js))(?:\?v=[0-9a-f]+)?\1')


def version(path):
    f = SITE / path.lstrip("/")
    return hashlib.md5(f.read_bytes()).hexdigest()[:8] if f.exists() else None


def main():
    changed = 0
    for page in SITE.rglob("*.html"):
        html = page.read_text(encoding="utf-8")
        def sub(m):
            v = version(m.group(2))
            return f"{m.group(1)}{m.group(2)}?v={v}{m.group(1)}" if v else m.group(0)
        new = REF.sub(sub, html)
        if new != html:
            page.write_text(new, encoding="utf-8")
            changed += 1
    print(f"Versie achter css/js gezet in {changed} pagina's")


if __name__ == "__main__":
    main()
