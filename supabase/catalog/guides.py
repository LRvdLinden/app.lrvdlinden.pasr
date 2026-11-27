#!/usr/bin/env python3
"""Vult de gids per winkel (cadeaubon-gids en, voor klantenkaarten, de programmagids) (pasr_stores.guide) uit supabase/catalog/guides.json ({store_id: guide}).
Alleen waar guide nog leeg is: wat in het beheer is aangepast blijft staan. Een winkel die een gids krijgt, krijgt
ook een nieuwe updated_at, zodat de apps hem opnieuw ophalen. Draait in de Backend-workflow na de catalogus-stap,
met SUPABASE_ACCESS_TOKEN en REF. Zonder die variabelen (of met --check) controleert het alleen het bestand."""
import json, os, re, sys, urllib.request
from pathlib import Path

KEYS = {"validity": str, "online": bool, "store": bool, "how": str, "shipping": str, "earn": str, "perks": str,
        "program_url": str, "terms_url": str, "checked": str, "birthday": str,
        # ticket (1.0.5): evenementgegevens voor de ticketweergave en de Wallet-pas (zie TicketEvent in stores.ts)
        "event": str, "brand": str, "date": str, "end_date": str, "doors": str, "ends": str, "venue": str,
        "city": str, "address": str, "ticket_type": str, "ticket_note": str, "info_url": str,
        "text_hex": str, "label_hex": str}
TICKET_TEXT = {"event": 60, "brand": 30, "venue": 60, "city": 40, "address": 120, "ticket_type": 30, "ticket_note": 40}


def check(guides):
    """Zelfde regels als het beheer (supabase/functions/admin/stores.ts, cleanGuide)."""
    for sid, g in guides.items():
        assert re.fullmatch(r"[a-z0-9-]{2,40}", sid), f"ongeldig id {sid!r}"
        assert isinstance(g, dict) and g, f"{sid}: gids moet een niet-leeg object zijn"
        for k, v in g.items():
            assert k in KEYS, f"{sid}: onbekende sleutel {k!r}"
            assert isinstance(v, KEYS[k]), f"{sid}.{k}: verkeerd type"
        for k, n in (("validity", 80), ("how", 400), ("shipping", 200), ("earn", 400), ("perks", 400), ("birthday", 160), ("program_url", 300), ("terms_url", 300)):
            assert len(g.get(k, "")) <= n, f"{sid}.{k}: te lang"
        for k in ("terms_url", "program_url", "info_url"):
            if k in g:
                assert g[k].startswith("https://"), f"{sid}.{k}: geen https"
        for k, n in TICKET_TEXT.items():
            assert len(g.get(k, "")) <= n, f"{sid}.{k}: te lang"
        for k in ("date", "end_date"):
            if k in g:
                assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", g[k]), f"{sid}.{k}: geen YYYY-MM-DD"
        if "date" in g and "end_date" in g:
            assert g["end_date"] >= g["date"], f"{sid}: einddatum voor begindatum"
        for k in ("doors", "ends"):
            if k in g:
                assert re.fullmatch(r"([01]\d|2[0-3]):[0-5]\d", g[k]), f"{sid}.{k}: geen HH:MM"
        for k in ("text_hex", "label_hex"):
            if k in g:
                assert re.fullmatch(r"#[0-9A-F]{6}", g[k]), f"{sid}.{k}: geen #RRGGBB (hoofdletters)"
        if "checked" in g:
            assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", g["checked"]), f"{sid}.checked: geen YYYY-MM-DD"


def lit(v):
    return "'" + str(v).replace("'", "''") + "'"


def check_birthdays(b):
    """birthdays.json: {store_id: {"birthday": tekst (hoogstens 160), "source": https-adres van de officiële site, "checked": YYYY-MM-DD}}."""
    for sid, v in b.items():
        assert re.fullmatch(r"[a-z0-9-]{2,40}", sid), f"ongeldig id {sid!r}"
        assert set(v) <= {"birthday", "source", "checked"}, f"{sid}: onbekende sleutel"
        assert isinstance(v.get("birthday"), str) and 0 < len(v["birthday"]) <= 160, f"{sid}.birthday"
        assert str(v.get("source", "")).startswith("https://"), f"{sid}.source: geen https"
        assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", v.get("checked", "")), f"{sid}.checked"


def query(ref, token, sql):
    req = urllib.request.Request(f"https://api.supabase.com/v1/projects/{ref}/database/query", method="POST",
                                 data=json.dumps({"query": sql}).encode(),
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read() or b"[]")


def birthdays(ref, token, b):
    """Verjaardagsvoordeel (1.0.3) in de gids zetten, één keer per winkel: pasr_store_birthday_seeded onthoudt het, zodat
    een tekst die in het beheer is weggehaald of aangepast niet terugkomt."""
    if not b:
        return 0
    values = ",\n".join(f"({lit(k)}, {lit(v['birthday'])})" for k, v in sorted(b.items()))
    sql = (f"with src(id, birthday) as (values\n{values}\n),\n"
           f"todo as (select src.* from src join public.pasr_stores s on s.id = src.id\n"
           f"         where not exists (select 1 from public.pasr_store_birthday_seeded x where x.id = src.id)),\n"
           f"upd as (update public.pasr_stores s set guide = coalesce(s.guide, '{{}}'::jsonb) || jsonb_build_object('birthday', t.birthday),\n"
           f"        updated_at = now() from todo t where s.id = t.id and coalesce(s.guide->>'birthday', '') = '' returning s.id),\n"
           f"seen as (insert into public.pasr_store_birthday_seeded (id) select id from todo on conflict do nothing)\n"
           f"select id from upd;")
    res = query(ref, token, sql)
    return len(res) if isinstance(res, list) else 0


def main():
    guides = json.loads((Path(__file__).parent / "guides.json").read_text(encoding="utf-8"))
    check(guides)
    bfile = Path(__file__).parent / "birthdays.json"
    bdays = json.loads(bfile.read_text(encoding="utf-8")) if bfile.exists() else {}
    check_birthdays(bdays)
    ref, token = os.environ.get("REF"), os.environ.get("SUPABASE_ACCESS_TOKEN")
    if "--check" in sys.argv or not (ref and token):
        print(f"Gidsen: {len(guides)} in guides.json, {len(bdays)} in birthdays.json, bestanden in orde.")
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
    print(f"Verjaardagsvoordeel: {birthdays(ref, token, bdays)} winkels kregen het in hun gids ({len(bdays)} in birthdays.json).")


if __name__ == "__main__":
    main()
