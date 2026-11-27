from pathlib import Path
from html.parser import HTMLParser
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent / "website"
checks = {
    "index.html": ("ch-menu", "px-discover", "hv2-stage", "populaire-kaarten"),
    "kaarten/index.html": ("ch-menu", "ch-real-art"),
    "cadeaubon/index.html": ("ch-menu", "ch-real-art"),
    "klantenkaart/index.html": ("ch-menu", "ch-real-art"),
    "kortingsbonnen/index.html": ("ch-menu", "ch-real-art", "ch-live-coupon"),
    "stempelkaarten/index.html": ("ch-menu", "ch-real-art", "ds-search"),
    "saldo-checken/index.html": ("ch-menu", "ch-real-art", "ds-search"),
    "support/index.html": ("ch-menu", "ch-support-hero"),
    "overstappen/klarna/index.html": ("ch-menu", "ch-move-hero"),
    "overstappen/supercards/index.html": ("ch-menu", "ch-move-hero"),
    "zakelijk/index.html": ("zk-mobile-menu", "zc-hero"),
    "toevoegen/index.html": ("ch-menu", "ta-main", "/assets/toevoegen.js", "/android/", "id6829229123"),
    "aanmelden/index.html": ("ch-menu", "ev-main", "/assets/aanmelden.js", "/assets/vendor/qrcode.js", "id6829229123"),
}
# De knop "Voeg toe aan Pasr" (tools/make_badges.py): alleen Nederlands, SVG en PNG @1x/@2x/@3x per variant.
for theme in ("zwart", "wit", "nachtblauw"):
    for size in ("", "-compact"):
        for suffix in (".svg", ".png", "@2x.png", "@3x.png"):
            badge = ROOT / "badge" / "nl" / f"{theme}{size}{suffix}"
            if not badge.is_file() or badge.stat().st_size < 200:
                raise SystemExit(f"missing badge {badge.relative_to(ROOT)} (python3 tools/make_badges.py)")
for rel, marker in ((".htaccess", "/toevoegen/index.html"), ("404.html", "/toevoegen/"),
                    (".htaccess", "^add/e/"), (".htaccess", "[kcatgsm]"), ("404.html", "/aanmelden/#"),
                    ("assets/toevoegen.js", "pasr_member_card_public"), ("assets/toevoegen.js", "pasr_event_ticket_public"),
                    ("assets/aanmelden.js", "pasr_event_register"), ("assets/aanmelden.js", "pasr_event_public"),
                    (".well-known/apple-app-site-association", '"/add/*"')):
    if marker not in (ROOT / rel).read_text(encoding="utf-8"):
        raise SystemExit(f"{rel}: missing {marker} (Voeg toe aan Pasr)")
print("OK badges and /add/ links")
class Scripts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.active = False
        self.code = []
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "script":
            self.active = not a.get("src") and a.get("type", "") in ("", "text/javascript", "application/javascript")
    def handle_data(self, data):
        if self.active:
            self.code.append(data)
    def handle_endtag(self, tag):
        if tag == "script":
            self.active = False

for rel, markers in checks.items():
    page = ROOT / rel
    html = page.read_text(encoding="utf-8")
    for marker in (*markers, "/assets/catalog-hub.css"):
        if marker not in html:
            raise SystemExit(f"{rel}: missing {marker}")
    parser = Scripts()
    parser.feed(html)
    for script in parser.code:
        if script.strip():
            with tempfile.NamedTemporaryFile(mode="w", suffix=".js", encoding="utf-8") as tmp:
                tmp.write(script)
                tmp.flush()
                subprocess.run(["node", "--check", tmp.name], check=True)
    print(f"OK {rel}")
print("All required public pages contain the new design and valid inline JavaScript.")
