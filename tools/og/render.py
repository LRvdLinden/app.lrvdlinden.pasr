"""Renders the share images: python3 tools/og/render.py [og og-share kaarten cadeaubon klantenkaart zakelijk home] (needs: pip install playwright && playwright install chromium).
home.html en zakelijk.html worden eerst gemaakt door build_og_html.py (passen en stijlen van de site zelf)."""
import asyncio
import functools
import http.server
import shutil
import subprocess
import threading
import sys
from pathlib import Path
from playwright.async_api import async_playwright
from build_og_html import build as build_html

HERE = Path(__file__).resolve().parent
OUT = HERE.parent.parent / "website" / "assets"

def serve():
    """Kleine webserver op de repo-map: via file:// laadt Chrome geen CSS-maskers (de Pasr-stempel op stempelkaarten)."""
    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass
    handler = functools.partial(Quiet, directory=str(HERE.parent.parent))
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


async def main():
    srv = serve()
    base = f"http://127.0.0.1:{srv.server_address[1]}/tools/og/"
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        build_html()
        page = await browser.new_page(viewport={"width": 1200, "height": 630}, device_scale_factor=1,
                                      color_scheme="light", reduced_motion="reduce")
        for name, out in [("og", OUT / "og.png"), ("og-share", OUT / "og-share.png"),
                          ("kaarten", OUT.parent / "og" / "kaarten.png"),
                          ("cadeaubon", OUT.parent / "og" / "cadeaubon.png"),          # /cadeaubon/ (gemaakt door make_gids.py)
                          ("klantenkaart", OUT.parent / "og" / "klantenkaart.png"),
                          ("zakelijk", OUT.parent / "og" / "zakelijk.png"),    # /zakelijk/ en de zakelijk-app-pagina's
                          ("home", OUT.parent / "og" / "home.png")]:           # pasr.nl en de algemene pagina's   # /zakelijk/   # /klantenkaart/   # /kaarten/ (tools/og/kaarten.html)
            if len(sys.argv) > 1 and name not in sys.argv[1:]:
                continue
            await page.goto(base + f"{name}.html")
            await page.evaluate("document.fonts.ready")
            await page.wait_for_timeout(400)
            await page.screenshot(path=str(out))
            if shutil.which("pngquant"):   # onder ~300 KB voor deelafbeeldingen (pip install pngquant-cli)
                subprocess.run(["pngquant", "--quality=80-95", "--speed", "1", "--strip", "--force", "--output", str(out), str(out)], check=False)
        await browser.close()
    srv.shutdown()

asyncio.run(main())
