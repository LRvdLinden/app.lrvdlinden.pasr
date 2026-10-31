"""Renders the share images: python3 tools/og/render.py (needs: pip install playwright && playwright install chromium)."""
import asyncio
from pathlib import Path
from playwright.async_api import async_playwright

HERE = Path(__file__).resolve().parent
OUT = HERE.parent.parent / "website" / "assets"

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page(viewport={"width": 1200, "height": 630}, device_scale_factor=1)
        for name in ["og", "og-share"]:
            await page.goto((HERE / f"{name}.html").as_uri())
            await page.wait_for_timeout(300)
            await page.screenshot(path=str(OUT / f"{name}.png"))
        await browser.close()

asyncio.run(main())
