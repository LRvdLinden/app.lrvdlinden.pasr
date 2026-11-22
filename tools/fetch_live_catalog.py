#!/usr/bin/env python3
"""Haalt de live catalogus van de server op (zoals de app hem ziet, inclusief alles wat in het beheer is aangepast):
pasr_store_index (winkels, gids en saldo-pagina's), pasr_store_logos (logo's, 40 per keer), pasr_store_covers
(kaartontwerpen, 40 per keer) en pasr_business_directory (stempelkaarten van zaken die vindbaar willen zijn).
Schrijft .cache/live-catalog.json; tools/store_catalog.py en tools/make_kaarten.py gebruiken dat bestand als het er is,
zodat pasr.nl/kaarten/ precies dezelfde kaarten, kleuren, logo's en ontwerpen toont als de app.
Omgeving: PASR_SUPABASE_URL en PASR_SUPABASE_KEY (publieke waarden). Lukt het niet, dan blijft alles bij de repo-gegevens.
Gebruik (in de Website-workflow): python3 tools/fetch_live_catalog.py && python3 tools/make_website.py"""
import json
import os
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
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(json.dumps({"now": idx.get("now") if isinstance(idx, dict) else None, "stores": stores, "logos": logos,
                                   "covers": covers, "balance_pages": pages if isinstance(pages, dict) else {},
                                   "businesses": businesses}), encoding="utf-8")
        print(f"Live catalogus: {len(stores)} winkels, {len(logos)} logo's, {len(covers)} kaartontwerpen, "
              f"{len(businesses) if businesses is not None else '?'} stempelkaarten.")
    except Exception as e:  # noqa: BLE001 - nooit de deploy breken
        print(f"::warning::Live catalogus niet opgehaald ({e}); de website gebruikt de gegevens uit de repo.")
        if OUT.exists():
            OUT.unlink()
    return 0


if __name__ == "__main__":
    sys.exit(main())
