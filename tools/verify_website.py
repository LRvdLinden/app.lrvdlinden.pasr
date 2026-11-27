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
}
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
