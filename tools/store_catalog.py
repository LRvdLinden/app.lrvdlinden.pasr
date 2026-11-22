#!/usr/bin/env python3
"""Alle kaarten die Pasr kent, uit de bronnen in deze repo (voor de website):
- de winkels in de app: Shared/Model/StoreTemplates.swift (kleur via Shared/Model/StoreLogoStyles.swift, logo in App/StoreLogos/<domain>.png);
- de catalogus-winkels van de server: de seeds in supabase/schema.sql (pasr_stores, logo als base64; supabase/stores/<id>.b64 als terugval);
- saldo-pagina's: de inserts in public.pasr_balance_pages in supabase/schema.sql.
Kaarten zonder website ("Kapper (eigen kaart)" en dergelijke) zijn geen winkel en tellen niet mee.
Gebruik: python3 tools/store_catalog.py  (toont de aantallen)"""
import base64
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SWIFT = REPO / "Shared" / "Model" / "StoreTemplates.swift"
STYLES = REPO / "Shared" / "Model" / "StoreLogoStyles.swift"
SCHEMA = REPO / "supabase" / "schema.sql"
LOGOS = REPO / "App" / "StoreLogos"
SEEDS = REPO / "supabase" / "stores"


def logo_styles():
    """domain -> {card, tint, plate, opaque}"""
    out = {}
    pat = re.compile(r'"([^"]+)": \.init\(card: "([^"]+)", tint: (nil|"[^"]*"), plate: (nil|"[^"]*"), opaque: (true|false)\)')
    for d, card, tint, plate, opaque in pat.findall(STYLES.read_text(encoding="utf-8")):
        out[d] = dict(card=card, tint=None if tint == "nil" else tint.strip('"'),
                      plate=None if plate == "nil" else plate.strip('"'), opaque=opaque == "true")
    return out


def _swift_string(s):
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8") if "\\" in s else s


def built_in():
    """De winkels in de app (StoreTemplates.builtIn), in bronvolgorde."""
    src = SWIFT.read_text(encoding="utf-8")
    body = src[src.index("static let builtIn"):]
    body = body[:body.index("\n    ]\n")]
    out = []
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith(".init(id:"):
            continue
        field = lambda k: (re.search(k + r': "((?:[^"\\]|\\.)*)"', line) or [None, ""])[1]
        aliases = re.search(r'aliases: \[(.*?)\]', line)
        out.append(dict(
            id=field("id"), name=_swift_string(field("name")), domain=field("domain"), category=field("category"),
            color=field("colorHex"),
            aliases=[_swift_string(a) for a in re.findall(r'"((?:[^"\\]|\\.)*)"', aliases.group(1))] if aliases else [],
            kind="voucher" if "kind: .voucher" in line else "loyalty", source="app"))
    return out


# --- een kleine SQL-lezer voor de seeds -----------------------------------------------------------------------------
def _sql_values(text, start):
    """Leest 'values (...), (...)' vanaf start; geeft (rijen, eindpositie). Strings met '' als escape, array[...]."""
    i, rows, n = start, [], len(text)

    def skip_ws(i):
        while i < n:
            if text[i].isspace():
                i += 1
            elif text.startswith("--", i):
                i = text.index("\n", i) if "\n" in text[i:] else n
            else:
                break
        return i

    def value(i):
        i = skip_ws(i)
        if text[i] == "'":
            j, buf = i + 1, []
            while True:
                k = text.index("'", j)
                buf.append(text[j:k])
                if k + 1 < n and text[k + 1] == "'":
                    buf.append("'"); j = k + 2
                else:
                    return "".join(buf), k + 1
        if text[i:i + 6].lower() == "array[":
            i += 6; items = []
            while True:
                i = skip_ws(i)
                if text[i] == "]":
                    return items, i + 1
                v, i = value(i); items.append(v)
                i = skip_ws(i)
                if text[i] == ",":
                    i += 1
        m = re.compile(r"[A-Za-z0-9_.:+\-]+(\(\))?(::[a-z\[\]]+)?").match(text, i)
        word = m.group(0)
        low = word.lower()
        return ({"true": True, "false": False, "null": None}.get(low, word)), m.end()

    while True:
        i = skip_ws(i)
        if i >= n or text[i] != "(":
            return rows, i
        i += 1; row = []
        while True:
            v, i = value(i); row.append(v)
            i = skip_ws(i)
            if text[i] == ",":
                i += 1; continue
            if text[i] == ")":
                i += 1; break
            raise ValueError(f"onverwacht teken in schema.sql bij {i}: {text[i:i+20]!r}")
        rows.append(row)
        i = skip_ws(i)
        if i < n and text[i] == ",":
            i += 1; continue
        return rows, i


def _inserts(table):
    text = SCHEMA.read_text(encoding="utf-8")
    pat = re.compile(r"insert into public\." + re.escape(table) + r"\s*\(([^)]*)\)\s*values\s*", re.I)
    for m in pat.finditer(text):
        cols = [c.strip() for c in m.group(1).split(",")]
        rows, _ = _sql_values(text, m.end())
        for r in rows:
            yield dict(zip(cols, r))


def catalog_seeds():
    """Catalogus-winkels uit supabase/schema.sql. Ze staan daar op published false en gaan live via de workflow
    Winkel publiceren; we nemen ze mee."""
    out = {}
    for r in _inserts("pasr_stores"):
        logo = r.get("logo")
        b64 = SEEDS / f"{r['id']}.b64"
        if not logo and b64.exists():
            logo = b64.read_text().strip()
        out[r["id"]] = dict(id=r["id"], name=r["name"], domain=r.get("domain") or "", category=r.get("category") or "Overig",
                            color=r.get("card_hex") or "#2B2F3A", aliases=list(r.get("aliases") or []),
                            kind=r.get("kind") or "loyalty", source="catalogus",
                            logo_png=base64.b64decode(logo) if logo else None)
    # Later aan het beheer toegevoegde winkels (supabase/catalog/new_*.json, eenmalig ingevoegd door seed.py).
    for f in sorted((REPO / "supabase" / "catalog").glob("new_*.json")):
        try:
            rows = json.loads(f.read_text())
        except ValueError:
            continue
        if not isinstance(rows, list):
            continue
        for r in rows:
            if not isinstance(r, dict) or not r.get("id") or not r.get("published", True) or r["id"] in out:
                continue
            logo = r.get("logo")
            out[r["id"]] = dict(id=r["id"], name=r["name"], domain=r.get("domain") or "", category=r.get("category") or "Overig",
                                color=r.get("card_hex") or "#2B2F3A", aliases=list(r.get("aliases") or []),
                                kind=r.get("kind") or "loyalty", source="catalogus",
                                logo_png=base64.b64decode(logo) if logo else None)
    return list(out.values())


def balance_pages():
    pages = {r["store_id"]: r["url"] for r in _inserts("pasr_balance_pages") if r.get("url", "").startswith("https://")}
    for f in sorted((REPO / "supabase" / "catalog").glob("*balance*.json")):
        try:
            extra = json.loads(f.read_text())
        except ValueError:
            continue
        if isinstance(extra, dict):
            pages.update({k: v for k, v in extra.items() if isinstance(v, str) and v.startswith("https://") and k not in pages})
    return pages


def _repo_cards():
    """Alle kaarten uit de repo (zonder de live catalogus)."""
    styles, pages = logo_styles(), balance_pages()
    app = built_in()
    ids = {s["id"] for s in app}
    cards = app + [s for s in catalog_seeds() if s["id"] not in ids]
    out = []
    for s in cards:
        if not s["domain"]:
            continue
        st = styles.get(s["domain"])
        if s["source"] == "app":
            card = st["card"] if st else s["color"]
            png = LOGOS / f"{s['domain']}.png"
            logo = png if png.exists() else None
        else:
            card = s["color"]
            png = LOGOS / f"{s['domain']}.png"
            logo = s.get("logo_png") or (png if png.exists() else None)
        out.append(dict(id=s["id"], key=s["domain"], name=s["name"], domain=s["domain"], category=s["category"], kind=s["kind"],
                        aliases=s["aliases"], card=card.upper(), style=st if s["source"] == "app" else None, logo=logo,
                        balance=pages.get(s["id"]) if s["kind"] == "voucher" else None, source=s["source"], guide=None))
    return out


_CACHE = {}


def all_cards():
    """Alle kaarten: id, key (bestandsnaam van het logo: domain, of id als er geen domain is), name, domain, category, kind,
    aliases, card (kleur), style, logo (Path|bytes|None), balance, source, guide (alleen met de live catalogus).
    Met de live catalogus (.cache/live-catalog.json) is de database de bron: precies de gepubliceerde winkels van de server."""
    if "cards" not in _CACHE:
        _CACHE["cards"] = apply_live(_repo_cards())
    return [dict(c) for c in _CACHE["cards"]]


LIVE = REPO / ".cache" / "live-catalog.json"


def live_catalog():
    """De live catalogus van de server (tools/fetch_live_catalog.py), of None."""
    if "live" not in _CACHE:
        try:
            data = json.loads(LIVE.read_text(encoding="utf-8"))
            _CACHE["live"] = data if isinstance(data, dict) and isinstance(data.get("stores"), list) else None
        except (OSError, ValueError):
            _CACHE["live"] = None
    return _CACHE["live"]


def live_built():
    """Tijdstip van de laatste wijziging in de live catalogus (ISO), of None. Zo verandert de pagina alleen als er in het
    beheer iets is gewijzigd, en weet kaarten.js welke winkels daarna nog zijn aangepast."""
    live = live_catalog()
    if not live:
        return None
    stamps = [s.get("updated_at") for s in live["stores"] if isinstance(s, dict) and isinstance(s.get("updated_at"), str)]
    return max(stamps) if stamps else live.get("now")


def apply_live(out):
    """Zoals de app, maar strenger: de database is de bron. Alleen de gepubliceerde winkels van de server komen erin, met
    naam, kleur, soort, categorie, logo, gids en saldo-pagina uit het beheer. Logo en stijl uit de repo zijn alleen een
    terugval als de server (nog) geen logo heeft. Cadeaukaarten en vouchers komen er altijd in (ook zonder domein);
    klantenkaarten zonder domein ("Kapper (eigen kaart)") zijn geen winkel en vallen weg."""
    live = live_catalog()
    if not live:
        return out
    logos = live.get("logos") or {}
    pages = {k: v for k, v in (live.get("balance_pages") or {}).items() if isinstance(v, str) and v.startswith("https://")}
    repo = {c["id"].lower(): c for c in out}
    result = []
    for s in live["stores"]:
        if not isinstance(s, dict) or not s.get("id") or s.get("removed") or not s.get("name"):
            continue
        kind = "voucher" if s.get("kind") == "voucher" else "loyalty"
        domain = (s.get("domain") or "").strip()
        if not domain and kind != "voucher":
            continue
        sid = s["id"]
        base = repo.get(sid.lower()) or {}
        b64 = logos.get(sid)
        if b64:
            logo, style = base64.b64decode(b64), None   # logo's van de server hebben de stijl al ingebakken
        elif base.get("logo") is not None and base.get("domain") == domain:
            logo, style = base["logo"], base.get("style")
        else:
            logo, style = None, None
        hexcol = s.get("card_hex") if isinstance(s.get("card_hex"), str) and re.fullmatch(r"#[0-9A-Fa-f]{6}", s.get("card_hex") or "") \
            else (base.get("card") or "#2B2F3A")
        guide = s.get("guide") if isinstance(s.get("guide"), dict) and s.get("guide") else None
        result.append(dict(id=sid, key=domain or sid.lower(), name=s["name"], domain=domain,
                           category=s.get("category") or base.get("category") or "Overig", kind=kind,
                           aliases=list(s.get("aliases") or []), card=hexcol.upper(), style=style, logo=logo,
                           balance=pages.get(sid) if kind == "voucher" else None,
                           source=base.get("source", "live"), guide=guide, updated_at=s.get("updated_at")))
    return result


# --- stempelkaarten (pasr_business_directory) ------------------------------------------------------------------------
HIDDEN_BUSINESS = re.compile(r"apple\s*review", re.I)


def business_hidden(b):
    """Nooit op de site: de demo-zaak voor App Review en zaken die niet vindbaar willen zijn (listed = false)."""
    if not isinstance(b, dict) or b.get("listed") is False:
        return True
    return any(HIDDEN_BUSINESS.search(str(b.get(k) or "")) for k in ("business_name", "card_name", "name"))


def stamp_cards():
    """Stempelkaarten uit de live catalogus (pasr_business_directory: gepubliceerd, zaak goedgekeurd, listed), gefilterd."""
    live = live_catalog() or {}
    out = []
    for b in live.get("businesses") or []:
        if business_hidden(b) or not b.get("card_id") or not b.get("business_name"):
            continue
        col = b.get("color") if re.fullmatch(r"#[0-9A-Fa-f]{6}", str(b.get("color") or "")) else "#6A5CFF"
        txt = b.get("text_color") if re.fullmatch(r"#[0-9A-Fa-f]{6}", str(b.get("text_color") or "")) else None
        try:
            total = max(2, min(30, int(b.get("stamps_total") or 10)))
        except (TypeError, ValueError):
            total = 10
        logo = b.get("logo") if isinstance(b.get("logo"), str) and re.fullmatch(r"(/9j/|iVBORw0KGgo)[A-Za-z0-9+/]+=*", b["logo"]) else None
        out.append(dict(id=str(b["card_id"]), business=str(b["business_name"]), name=str(b.get("card_name") or ""),
                        city=str(b.get("city") or ""), color=col.upper(), text=txt.upper() if txt else None,
                        total=total, reward=str(b.get("reward") or ""), logo=logo))
    return out


def counts(cards=None):
    cards = cards if cards is not None else all_cards()
    loyalty = sum(1 for c in cards if c["kind"] == "loyalty")
    return dict(loyalty=loyalty, voucher=len(cards) - loyalty, total=len(cards), stamp=len(stamp_cards()),
                logos=len({c["key"] for c in cards if c["logo"] is not None}))


if __name__ == "__main__":
    cs = all_cards()
    c = counts(cs)
    print(f"Klantenkaarten: {c['loyalty']}  Cadeaukaarten/vouchers: {c['voucher']}  Stempelkaarten: {c['stamp']}  "
          f"(totaal {c['total']}, met logo: {c['logos']} winkels, live: {'ja' if live_catalog() else 'nee'})")
    print("Uit de catalogus:", ", ".join(x["name"] for x in cs if x["source"] == "catalogus"))
    print("Zonder logo:", ", ".join(x["name"] for x in cs if x["logo"] is None))
    print("Saldo-check:", sum(1 for x in cs if x["balance"]))
