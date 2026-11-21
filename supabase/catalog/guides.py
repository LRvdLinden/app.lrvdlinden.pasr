#!/usr/bin/env python3
"""Vult de cadeaubon-gids (pasr_stores.guide) uit supabase/catalog/guides.json ({store_id: guide}).
Alleen waar guide nog leeg is: wat in het beheer is aangepast blijft staan. Een winkel die een gids krijgt, krijgt
ook een nieuwe updated_at, zodat de apps hem opnieuw ophalen. Draait in de Backend-workflow na de catalogus-stap,
met SUPABASE_ACCESS_TOKEN en REF. Zonder die variabelen (of met --check) controleert het alleen het bestand."""
import json, os, re, sys, urllib.request
from pathlib import Path

KEYS = {"validity": str, "online": bool, "store": bool, "how": str, "shipping": str, "terms_url": str, "checked": str}


def check(guides):
    """Zelfde regels als het beheer (supabase/functions/admin/stores.ts, cleanGuide)."""
    for sid, g in guides.items():
        assert re.fullmatch(r"[a-z0-9-]{2,40}", sid), f"ongeldig id {sid!r}"
        assert isinstance(g, dict) and g, f"{sid}: gids moet een niet-leeg object zijn"
        for k, v in g.items():
            assert k in KEYS, f"{sid}: onbekende sleutel {k!r}"
            assert isinstance(v, KEYS[k]), f"{sid}.{k}: verkeerd type"
        for k, n in (("validity", 80), ("how", 400), ("shipping", 200), ("terms_url", 300)):
            assert len(g.get(k, "")) <= n, f"{sid}.{k}: te lang"
        if "terms_url" in g:
            assert g["terms_url"].startswith("https://"), f"{sid}.terms_url: geen https"
        if "checked" in g:
            assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", g["checked"]), f"{sid}.checked: geen YYYY-MM-DD"


def lit(v):
    return "'" + str(v).replace("'", "''") + "'"


def main():
    guides = json.loads((Path(__file__).parent / "guides.json").read_text(encoding="utf-8"))
    check(guides)
    ref, token = os.environ.get("REF"), os.environ.get("SUPABASE_ACCESS_TOKEN")
    if "--check" in sys.argv or not (ref and token):
        print(f"Gidsen: {len(guides)} in guides.json, bestand in orde.")
        return
    values = ",\n".join(f"({lit(k)}, {lit(json.dumps(v, ensure_ascii=False))}::jsonb)" for k, v in sorted(guides.items()))
    sql = (f"update public.pasr_stores s set guide = g.guide, updated_at = now()\n"
           f"from (values\n{values}\n) as g(id, guide)\nwhere s.id = g.id and s.guide is null returning s.id;")
    req = urllib.request.Request(f"https://api.supabase.com/v1/projects/{ref}/database/query", method="POST",
                                 data=json.dumps({"query": sql}).encode(),
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        res = json.loads(r.read() or b"[]")
    n = len(res) if isinstance(res, list) else 0
    print(f"Gidsen: {n} winkels kregen een gids ({len(guides)} in het bestand; de rest had er al een of bestaat niet).")


if __name__ == "__main__":
    main()
