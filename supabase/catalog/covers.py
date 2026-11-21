#!/usr/bin/env python3
"""Vult het kaartontwerp (voorkant) van cadeaukaarten (pasr_stores.cover) uit supabase/catalog/covers.json
({store_id: base64 JPEG/PNG}, gemaakt met tools/make_covers.py). Alleen waar cover nog leeg is en de winkel nog nooit een
cover uit dit bestand kreeg (tabel pasr_store_cover_seeded): wat in het beheer is aangepast of verwijderd blijft zo.
Een winkel die een cover krijgt, krijgt ook een nieuwe updated_at, zodat de apps hem opnieuw ophalen. Draait in de
Backend-workflow na de catalogus-stap, met SUPABASE_ACCESS_TOKEN en REF. Zonder die variabelen (of met --check)
controleert het alleen het bestand."""
import base64, json, os, re, sys, urllib.request
from pathlib import Path

MAX = 210_000   # zelfde grens als de check constraint pasr_stores_cover_image


def check(covers):
    for sid, b64 in covers.items():
        assert re.fullmatch(r"[a-z0-9-]{2,40}", sid), f"ongeldig id {sid!r}"
        assert isinstance(b64, str) and len(b64) <= MAX, f"{sid}: te groot"
        assert b64.startswith(("/9j/", "iVBORw0KGgo")), f"{sid}: geen JPEG of PNG"
        base64.b64decode(b64, validate=True)


def lit(v):
    return "'" + str(v).replace("'", "''") + "'"


def query(ref, token, sql):
    req = urllib.request.Request(f"https://api.supabase.com/v1/projects/{ref}/database/query", method="POST",
                                 data=json.dumps({"query": sql}).encode(),
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read() or b"[]")


def main():
    covers = json.loads((Path(__file__).parent / "covers.json").read_text(encoding="utf-8"))
    check(covers)
    ref, token = os.environ.get("REF"), os.environ.get("SUPABASE_ACCESS_TOKEN")
    if "--check" in sys.argv or not (ref and token):
        print(f"Covers: {len(covers)} in covers.json, bestand in orde.")
        return
    items, done = sorted(covers.items()), 0
    for i in range(0, len(items), 10):
        values = ",\n".join(f"({lit(k)}, {lit(v)})" for k, v in items[i:i + 10])
        res = query(ref, token,
                    f"with c(id, cover) as (values\n{values}\n),\n"
                    "upd as (update public.pasr_stores s set cover = c.cover, updated_at = now() from c\n"
                    "  where s.id = c.id and s.cover is null\n"
                    "    and not exists (select 1 from public.pasr_store_cover_seeded x where x.id = c.id) returning s.id),\n"
                    "ins as (insert into public.pasr_store_cover_seeded (id) select id from upd on conflict (id) do nothing)\n"
                    "select id from upd;")
        done += len(res) if isinstance(res, list) else 0
    print(f"Covers: {done} cadeaukaarten kregen een kaartontwerp ({len(covers)} in het bestand; de rest had er al een, "
          "kreeg er eerder een of bestaat niet).")


if __name__ == "__main__":
    main()
