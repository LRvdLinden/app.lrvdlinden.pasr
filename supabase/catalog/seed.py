#!/usr/bin/env python3
"""Eenmalige vulling van pasr_stores met alle winkels uit de app (supabase/catalog/stores.json, gemaakt door
tools/build_catalog.py) plus de aanvullingen in dezelfde map (bijv. new_loyalty.json, new_vouchers.json): elk
*.json-bestand hier met een lijst winkels in hetzelfde formaat; guides*.json, *balance*.json en covers*.json (andere structuur)
worden overgeslagen. Bestaat een winkel al in het beheer, dan blijft die zoals hij is: het beheer is leidend.
Draait in de Backend-workflow met SUPABASE_ACCESS_TOKEN en REF."""
import json, os, urllib.error, urllib.request
from pathlib import Path

ref, token = os.environ["REF"], os.environ["SUPABASE_ACCESS_TOKEN"]
here = Path(__file__).parent
FIELDS = ["id", "name", "domain", "category", "card_hex", "format", "kind", "aliases", "logo", "published"]


def catalog_files():
    files = sorted(p for p in here.glob("*.json")
                   if not p.name.startswith(("guides", "balance", "covers")) and "balance" not in p.name)
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
def row_sql(r):
    return "(" + ", ".join(lit(r[c]) for c in FIELDS) + (", now())" if r["published"] else ", null)")


def insert(batch):
    values = ",\n".join(row_sql(r) for r in batch)
    res = query(f"insert into public.pasr_stores ({cols}) values\n{values}\non conflict (id) do nothing returning id;")
    return len(res) if isinstance(res, list) else 0


done, failed = 0, []
for i in range(0, len(rows), 25):
    batch = rows[i:i + 25]
    try:
        done += insert(batch)
    except urllib.error.HTTPError as e:
        # Eén foute winkel mag de rest niet tegenhouden: dan per winkel, en de fout laten zien.
        print(f"::warning::Groep {i // 25 + 1} geweigerd (HTTP {e.code}): {e.read()[:300].decode(errors='replace')}")
        for r in batch:
            try:
                done += insert([r])
            except urllib.error.HTTPError as e2:
                failed.append(r["id"])
                print(f"::error::Winkel {r['id']} geweigerd (HTTP {e2.code}): {e2.read()[:300].decode(errors='replace')}")
print(f"Catalogus: {done} nieuwe winkels in het beheer gezet ({len(rows)} in het bestand; de rest stond er al).")

# Saldo-checkers van de nieuwe cadeaukaarten uit alle *balance*.json ({store_id: url}); bestaat er al een, dan
# blijft die staan.
pages = {}
for balance_file in sorted(here.glob("*balance*.json")):
    data = json.loads(balance_file.read_text())
    if isinstance(data, dict):
        pages.update({k: v for k, v in data.items() if k not in pages})
if pages:
    values = ",\n".join(f"({lit(k)}, {lit(v)})" for k, v in pages.items())
    res = query(f"insert into public.pasr_balance_pages (store_id, url) values\n{values}\n"
                "on conflict (store_id) do nothing returning store_id;")
    print(f"Saldo-checkers: {len(res) if isinstance(res, list) else 0} nieuw ({len(pages)} in de bestanden).")

if failed:
    raise SystemExit(f"Niet ingevoegd: {', '.join(failed)}")
