"""Renders the share images: python3 tools/og/render.py [og og-share kaarten cadeaubon klantenkaart zakelijk] (needs: pip install playwright && playwright install chromium)."""
import asyncio
import sys
from pathlib import Path
from playwright.async_api import async_playwright

HERE = Path(__file__).resolve().parent
OUT = HERE.parent.parent / "website" / "assets"

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page(viewport={"width": 1200, "height": 630}, device_scale_factor=1)
        for name, out in [("og", OUT / "og.png"), ("og-share", OUT / "og-share.png"),
                          ("kaarten", OUT.parent / "og" / "kaarten.png"),
                          ("cadeaubon", OUT.parent / "og" / "cadeaubon.png"),          # /cadeaubon/ (gemaakt door make_gids.py)
                          ("klantenkaart", OUT.parent / "og" / "klantenkaart.png"),
                          ("zakelijk", OUT.parent / "og" / "zakelijk.png")]:   # /zakelijk/   # /klantenkaart/   # /kaarten/ (tools/og/kaarten.html)
            if len(sys.argv) > 1 and name not in sys.argv[1:]:
                continue
            await page.goto((HERE / f"{name}.html").as_uri())
            await page.wait_for_timeout(300)
            await page.screenshot(path=str(out))
        await browser.close()

asyncio.run(main())
