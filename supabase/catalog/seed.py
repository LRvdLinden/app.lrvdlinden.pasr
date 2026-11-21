#!/usr/bin/env python3
"""Eenmalige vulling van pasr_stores met alle winkels uit de app (supabase/catalog/stores.json, gemaakt door
tools/build_catalog.py) plus de aanvullingen in dezelfde map (bijv. new_loyalty.json, new_vouchers.json): elk
*.json-bestand hier met een lijst winkels in hetzelfde formaat; guides*.json, balance*.json en covers.json (andere structuur)
worden overgeslagen. Bestaat een winkel al in het beheer, dan blijft die zoals hij is: het beheer is leidend.
Draait in de Backend-workflow met SUPABASE_ACCESS_TOKEN en REF."""
import json, os, urllib.request
from pathlib import Path

ref, token = os.environ["REF"], os.environ["SUPABASE_ACCESS_TOKEN"]
here = Path(__file__).parent
FIELDS = ["id", "name", "domain", "category", "card_hex", "format", "kind", "aliases", "logo", "published"]


def catalog_files():
    files = sorted(p for p in here.glob("*.json") if not p.name.startswith(("guides", "balance", "covers")))
    return sorted(files, key=lambda p: p.name != "stores.json")  # stores.json eerst


rows, seen = [], set()
for path in catalog_files():
    data = json.loads(path.read_text())
    if not isinstance(data, list) or not all(isinstance(r, dict) and set(FIELDS) <= set(r) for r in data):
        print(f"Overgeslagen: {path.name} (geen lijst winkels in het catalogusformaat)")
        continue
    new = [r for r in data if r["id"] not in seen]
    seen.update(r["id"] for r in new)
    rows += new
    print(f"{path.name}: {len(new)} winkels")


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
        "(" + ", ".join(lit(r[c]) for c in FIELDS)
        + (", now())" if r["published"] else ", null)")
        for r in rows[i:i + 25])
    res = query(f"insert into public.pasr_stores ({cols}) values\n{values}\non conflict (id) do nothing returning id;")
    done += len(res) if isinstance(res, list) else 0
print(f"Catalogus: {done} nieuwe winkels in het beheer gezet ({len(rows)} in het bestand; de rest stond er al).")

# Saldo-checkers van de nieuwe cadeaukaarten (bestaat er al een, dan blijft die staan).
balance_file = here / "new_vouchers_balance.json"
if balance_file.exists():
    pages = json.loads(balance_file.read_text())
    if pages:
        values = ",\n".join(f"({lit(k)}, {lit(v)})" for k, v in pages.items())
        res = query(f"insert into public.pasr_balance_pages (store_id, url) values\n{values}\n"
                    "on conflict (store_id) do nothing returning store_id;")
        print(f"Saldo-checkers: {len(res) if isinstance(res, list) else 0} nieuw ({len(pages)} in het bestand).")
