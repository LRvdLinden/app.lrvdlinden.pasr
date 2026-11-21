#!/usr/bin/env python3
"""Eenmalige vulling van pasr_stores met alle winkels uit de app (supabase/catalog/stores.json, gemaakt door
tools/build_catalog.py). Bestaat een winkel al in het beheer, dan blijft die zoals hij is: het beheer is leidend.
Draait in de Backend-workflow met SUPABASE_ACCESS_TOKEN en REF."""
import json, os, urllib.request
from pathlib import Path

ref, token = os.environ["REF"], os.environ["SUPABASE_ACCESS_TOKEN"]
rows = json.loads((Path(__file__).parent / "stores.json").read_text())


def lit(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, list):
        return "array[" + ",".join(lit(x) for x in v) + "]::text[]" if v else "'{}'::text[]"
    return "'" + str(v).replace("'", "''") + "'"


def query(sql):
    req = urllib.request.Request(f"https://api.supabase.com/v1/projects/{ref}/database/query", method="POST",
                                 data=json.dumps({"query": sql}).encode(),
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read() or b"[]")


cols = "id, name, domain, category, card_hex, format, kind, aliases, logo, published, published_at"
done = 0
for i in range(0, len(rows), 25):
    values = ",\n".join(
        "(" + ", ".join(lit(r[c]) for c in ["id", "name", "domain", "category", "card_hex", "format", "kind", "aliases", "logo", "published"])
        + (", now())" if r["published"] else ", null)")
        for r in rows[i:i + 25])
    res = query(f"insert into public.pasr_stores ({cols}) values\n{values}\non conflict (id) do nothing returning id;")
    done += len(res) if isinstance(res, list) else 0
print(f"Catalogus: {done} nieuwe winkels in het beheer gezet ({len(rows)} in het bestand; de rest stond er al).")
