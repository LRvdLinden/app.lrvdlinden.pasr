#!/usr/bin/env python3
"""Maakt de Engelse teksttabel (EnStrings.kt) van Pasr Zakelijk voor Android.

Bron: dezelfde Localizable.xcstrings als de iOS-app (zakelijk/apple/PasrZakelijk) plus tools/android-en.json voor
teksten die alleen op Android bestaan. Controleert dat elke L("…")-tekst in de Kotlin-code een Engelse vertaling heeft.
Draaien vanuit de map android/zakelijk:  python3 tools/make_strings.py
"""
import json, re, sys, pathlib

here = pathlib.Path(__file__).resolve().parent.parent
repo = here.parent.parent
xc = json.loads((repo / "zakelijk/apple/PasrZakelijk/Localizable.xcstrings").read_text())["strings"]
extra = json.loads((here / "tools/android-en.json").read_text())

table = {}
for key, v in xc.items():
    en = v.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value")
    if en:
        table[key] = en
for key, en in extra.items():
    if not key.startswith("_"):
        table[key] = en

src = here / "app/src/main/java"
pattern = re.compile(r'\bL\(\s*"((?:[^"\\]|\\.)*)"')
def unescape(s):
    return re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)

used = set()
for f in src.rglob("*.kt"):
    for m in pattern.finditer(f.read_text()):
        used.add(unescape(m.group(1)))
# teksten die via een variabele vertaald worden (tabbladen, meetwaarden, periodekiezer)
used |= set(extra.get("_dynamic", []))

missing = sorted(k for k in used if k not in table)
if missing:
    print("Ontbrekende Engelse vertalingen:", file=sys.stderr)
    for k in missing:
        print("  " + json.dumps(k, ensure_ascii=False), file=sys.stderr)
    sys.exit(1)

def kt(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("\n", "\\n") + '"'

keys = sorted(used)
lines = ["package app.lrvdlinden.pasrzakelijk.core", "",
         "// Gemaakt door tools/make_strings.py uit zakelijk/apple/PasrZakelijk/Localizable.xcstrings en tools/android-en.json.",
         "// Niet met de hand wijzigen.", "", "internal object EnStrings {",
         "    val map: Map<String, String> = HashMap<String, String>(%d).apply {" % (len(keys) * 2)]
# in stukken, zodat geen enkele methode te groot wordt
chunks = [keys[i:i + 80] for i in range(0, len(keys), 80)]
for i, _ in enumerate(chunks):
    lines.append("        part%d(this)" % i)
lines.append("    }")
for i, chunk in enumerate(chunks):
    lines.append("")
    lines.append("    private fun part%d(m: HashMap<String, String>) {" % i)
    for k in chunk:
        lines.append("        m[%s] = %s" % (kt(k), kt(table[k])))
    lines.append("    }")
lines.append("}")
out = src / "app/lrvdlinden/pasrzakelijk/core/EnStrings.kt"
out.write_text("\n".join(lines) + "\n")
print("EnStrings.kt: %d teksten" % len(keys))
