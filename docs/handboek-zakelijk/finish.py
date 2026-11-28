#!/usr/bin/env python3
"""Hulpje voor render.cjs (pypdf).
  finish.py pages <pdf>                  JSON {anker-id: paginanummer} uit de benoemde bestemmingen (links in de inhoudsopgave)
  finish.py count <pdf>                  aantal pagina's
  finish.py merge <pdf> <laag> <uit>     kop/voet-laag erover, metadata, bladwijzers van Chromium blijven staan
"""
import json
import sys

from pypdf import PdfReader, PdfWriter


def pages(path):
    r = PdfReader(path)
    index = {p.indirect_reference.idnum: i + 1 for i, p in enumerate(r.pages)}
    out = {}
    for name, d in r.named_destinations.items():
        page = d.get("/Page")
        if page is not None and hasattr(page, "idnum") and page.idnum in index:
            out[name.lstrip("/")] = index[page.idnum]
    return dict(sorted(out.items(), key=lambda kv: (kv[1], kv[0])))


def merge(src, layer, out):
    w = PdfWriter(clone_from=src)
    lay = PdfReader(layer)
    for i, page in enumerate(w.pages):
        if i < len(lay.pages):
            page.merge_page(lay.pages[i], over=True)
    w.add_metadata({"/Title": "Handboek Pasr Zakelijk", "/Author": "Pasr", "/Subject": "Alles om klanten terug te laten komen · versie 1.0.4 · november 2026",
                    "/Keywords": "Pasr Zakelijk, handboek, stempelkaart, klantenkaart, tickets, kortingsbon, actiecode, gezamenlijke actie", "/Creator": "docs/handboek-zakelijk/render.cjs"})
    w.page_mode = "/UseOutlines"
    w.compress_identical_objects(remove_duplicates=True, remove_unreferenced=True)
    with open(out, "wb") as f:
        w.write(f)
    print(f"Geschreven: {out} ({len(w.pages)} pagina's)")


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "pages":
        print(json.dumps(pages(sys.argv[2])))
    elif cmd == "count":
        print(len(PdfReader(sys.argv[2]).pages))
    elif cmd == "merge":
        merge(sys.argv[2], sys.argv[3], sys.argv[4])
