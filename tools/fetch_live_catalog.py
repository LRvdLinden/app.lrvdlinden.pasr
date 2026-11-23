#!/usr/bin/env python3
"""Haalt de live catalogus van de server op (zoals de app hem ziet, inclusief alles wat in het beheer is aangepast):
pasr_store_index (winkels, gids en saldo-pagina's), pasr_store_logos (logo's, 40 per keer), pasr_store_covers
(kaartontwerpen, 40 per keer) en pasr_business_directory (stempelkaarten van zaken die vindbaar willen zijn).
Voor de deelpagina's pasr.nl/zakelijk/kaart/<id>/ ook pasr_business_share_cards (alle gepubliceerde stempelkaarten, ook
niet-vindbare; alleen service role, dus via de Management API met SUPABASE_ACCESS_TOKEN). Zonder die sleutel: share_cards =
null en tools/make_kaart_pages.py maakt alleen pagina's voor de vindbare kaarten uit pasr_business_directory.
Schrijft .cache/live-catalog.json; tools/store_catalog.py en tools/make_kaarten.py gebruiken dat bestand als het er is,
zodat pasr.nl/kaarten/ precies dezelfde kaarten, kleuren, logo's en ontwerpen toont als de app.
Omgeving: PASR_SUPABASE_URL en PASR_SUPABASE_KEY (publieke waarden). Lukt het niet, dan blijft alles bij de repo-gegevens.
Gebruik (in de Website-workflow): python3 tools/fetch_live_catalog.py && python3 tools/make_website.py"""
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / ".cache" / "live-catalog.json"


def rpc(url, key, name, body):
    req = urllib.request.Request(url.rstrip("/") + "/rest/v1/rpc/" + name, data=json.dumps(body).encode(),
                                 headers={"apikey": key, "Content-Type": "application/json", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())


def share_cards(url):
    """Alle gepubliceerde stempelkaarten van goedgekeurde zaken (pasr_business_share_cards), of None zonder sleutel/fout."""
    token = (os.environ.get("SUPABASE_ACCESS_TOKEN") or "").strip()
    ref = (os.environ.get("SUPABASE_PROJECT_REF") or "").strip()
    if not ref:
        m = re.match(r"https://([a-z0-9]+)\.supabase\.co", url or "")
        ref = m.group(1) if m else ""
    if not token or not ref:
        print("Deelpagina's: geen SUPABASE_ACCESS_TOKEN, alleen de vindbare stempelkaarten krijgen een pagina.")
        return None
    try:
        req = urllib.request.Request(f"https://api.supabase.com/v1/projects/{ref}/database/query",
                                     data=json.dumps({"query": "select public.pasr_business_share_cards() as cards"}).encode(),
                                     headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json",
                                              "User-Agent": "pasr-website-build"})
        with urllib.request.urlopen(req, timeout=60) as r:
            rows = json.loads(r.read().decode())
        cards = rows[0]["cards"] if isinstance(rows, list) and rows and isinstance(rows[0], dict) else None
        if isinstance(cards, str):
            cards = json.loads(cards)
        return cards if isinstance(cards, list) else None
    except Exception as e:  # noqa: BLE001
        print(f"::warning::Stempelkaarten voor de deelpagina's niet opgehaald ({str(e)[:160]}); alleen vindbare kaarten.")
        return None


def main():
    url, key = (os.environ.get("PASR_SUPABASE_URL") or "").strip(), (os.environ.get("PASR_SUPABASE_KEY") or "").strip()
    if not url or not key:
        print("Live catalogus overgeslagen: PASR_SUPABASE_URL / PASR_SUPABASE_KEY ontbreken.")
        return 0
    try:
        idx = rpc(url, key, "pasr_store_index", {})
        stores = idx.get("stores") if isinstance(idx, dict) else idx
        if not isinstance(stores, list) or len(stores) < 50:
            raise ValueError(f"onverwachte index ({type(stores).__name__}, {len(stores) if isinstance(stores, list) else '?'})")
        logos, covers = {}, {}
        for field, fn, dest in (("has_logo", "pasr_store_logos", logos), ("has_cover", "pasr_store_covers", covers)):
            ids = [s["id"] for s in stores if s.get(field)]
            for i in range(0, len(ids), 40):
                part = rpc(url, key, fn, {"p_ids": ids[i:i + 40]})
                if isinstance(part, dict):
                    dest.update({k: v for k, v in part.items() if isinstance(v, str) and v})
        pages = idx.get("balance_pages") if isinstance(idx, dict) else None
        try:   # stempelkaarten: los, zodat een fout hier de winkels niet tegenhoudt
            businesses = rpc(url, key, "pasr_business_directory", {"p_limit": 200})
            businesses = businesses if isinstance(businesses, list) else None
        except Exception as e:  # noqa: BLE001
            print(f"::warning::Stempelkaarten niet opgehaald ({e}); de lijst blijft leeg op de site.")
            businesses = None
        shared = share_cards(url)
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(json.dumps({"now": idx.get("now") if isinstance(idx, dict) else None, "stores": stores, "logos": logos,
                                   "covers": covers, "balance_pages": pages if isinstance(pages, dict) else {},
                                   "businesses": businesses, "share_cards": shared}), encoding="utf-8")
        print(f"Live catalogus: {len(stores)} winkels, {len(logos)} logo's, {len(covers)} kaartontwerpen, "
              f"{len(businesses) if businesses is not None else '?'} stempelkaarten "
              f"({len(shared) if shared is not None else 'alleen vindbare'} voor de deelpagina's).")
    except Exception as e:  # noqa: BLE001 - nooit de deploy breken
        print(f"::warning::Live catalogus niet opgehaald ({e}); de website gebruikt de gegevens uit de repo.")
        if OUT.exists():
            OUT.unlink()
    return 0


if __name__ == "__main__":
    sys.exit(main())
