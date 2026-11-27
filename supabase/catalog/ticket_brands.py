#!/usr/bin/env python3
"""Logo en merkkleur van de evenementsites (supabase/catalog/ticket_brands.json, gemaakt door
`tools/fetch_logos.py --tickets` in de workflow Logos) in het beheer zetten bij de tickets met dat domein.
Alleen waar het ticket nog geen logo heeft, en de kleur alleen als het ticket nog de neutrale kleur #2B2F3A heeft:
wat in het beheer is ingesteld blijft staan. Een ticket dat iets krijgt, krijgt ook een nieuwe updated_at, zodat de
apps het opnieuw ophalen. Draait in de Backend-workflow na de gidsen, met SUPABASE_ACCESS_TOKEN en REF. Zonder die
variabelen (of met --check) controleert het alleen het bestand."""
import base64, json, os, re, sys, urllib.request
from pathlib import Path

NEUTRAL = "#2B2F3A"


def check(brands):
    for domain, b in brands.items():
        assert re.fullmatch(r"[a-z0-9-]+(\.[a-z0-9-]+)+", domain), f"ongeldig domein {domain!r}"
        assert set(b) <= {"logo", "card", "replace"}, f"{domain}: onbekende sleutel"
        if "card" in b:
            assert re.fullmatch(r"#[0-9A-F]{6}", b["card"]), f"{domain}.card: geen #RRGGBB"
        if "logo" in b:
            raw = base64.b64decode(b["logo"], validate=True)
            assert raw[:8] == b"\x89PNG\r\n\x1a\n", f"{domain}.logo: geen PNG"
            assert len(b["logo"]) <= 400_000, f"{domain}.logo: te groot"


def lit(v):
    return "null" if v is None else "'" + str(v).replace("'", "''") + "'"


def main():
    path = Path(__file__).parent / "ticket_brands.json"
    brands = json.loads(path.read_text()) if path.exists() else {}
    check(brands)
    ref, token = os.environ.get("REF"), os.environ.get("SUPABASE_ACCESS_TOKEN")
    if "--check" in sys.argv or not (ref and token) or not brands:
        print(f"Ticketmerken: {len(brands)} in ticket_brands.json, bestand in orde.")
        return
    # "replace": true = aangeleverd door Léon (officieel logo): vervangt een bestaand logo.
    values = ",\n".join(f"({lit(d)}, {lit(b.get('logo'))}, {lit(b.get('card'))}, {'true' if b.get('replace') else 'false'})" for d, b in sorted(brands.items()))
    sql = (f"update public.pasr_stores s set\n"
           f"  logo = case when b.replace and b.logo is not null then b.logo else coalesce(s.logo, b.logo) end,\n"
           f"  card_hex = case when upper(s.card_hex) = '{NEUTRAL}' and b.card is not null then b.card else s.card_hex end,\n"
           f"  updated_at = now()\n"
           f"from (values\n{values}\n) as b(domain, logo, card, replace)\n"
           f"where s.kind = 'ticket' and s.domain = b.domain\n"
           f"  and ((s.logo is null and b.logo is not null) or (b.replace and b.logo is not null and s.logo is distinct from b.logo)\n"
           f"       or (upper(s.card_hex) = '{NEUTRAL}' and b.card is not null))\n"
           f"returning s.id;")
    req = urllib.request.Request(f"https://api.supabase.com/v1/projects/{ref}/database/query", method="POST",
                                 data=json.dumps({"query": sql}).encode(),
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        res = json.loads(r.read() or b"[]")
    n = len(res) if isinstance(res, list) else 0
    print(f"Ticketmerken: {n} tickets kregen logo of merkkleur ({len(brands)} sites in het bestand).")


if __name__ == "__main__":
    main()
