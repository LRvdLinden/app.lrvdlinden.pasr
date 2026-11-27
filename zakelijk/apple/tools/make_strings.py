#!/usr/bin/env python3
"""Schrijft PasrZakelijk/Localizable.xcstrings (nl = ontwikkeltaal, en = vertaling uit tools/strings_en.json) en
PasrZakelijk/InfoPlist.xcstrings. Zoekt de teksten in de Swift-bestanden: letterlijke teksten in Text/Button/Label/…
en String(localized:). Ontbreekt een Engelse vertaling, dan noemt het script hem (exit 1).

python3 zakelijk/apple/tools/make_strings.py
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
APP = HERE.parent / "PasrZakelijk"
EN = json.loads((HERE / "strings_en.json").read_text())

CALLS = r"(?:Text|Button|Label|Section|TextField|SecureField|Toggle|Picker|Stepper|LabeledContent|ColorPicker|Link|navigationTitle|" \
        r"ContentUnavailableView|alert|confirmationDialog|accessibilityLabel|accessibilityHint|prompt: Text|subject: Text|PhotosPicker|SettingsLabel)"
LIT = r'"((?:[^"\\]|\\.)*)"'


def keys():
    found = set()
    for f in sorted(APP.rglob("*.swift")):
        src = f.read_text()
        for m in re.finditer(r"String\(localized:\s*" + LIT, src):
            found.add(m.group(1))
        for m in re.finditer(r"\b" + CALLS + r"\(\s*" + LIT, src):
            found.add(m.group(1))
        # ternaries en LocalizedStringKey-returns: "…" : "…", case …: "…", return "…"
        for m in re.finditer(r"\?\s*" + LIT + r"\s*:\s*" + LIT, src):
            found.update([m.group(1), m.group(2)])
        for m in re.finditer(r"(?:case \.?\w+(?:, \.?\w+)*:|return|default:)\s*" + LIT, src):
            found.add(m.group(1))
        for m in re.finditer(r"\((\d+), " + LIT + r"\)", src):
            found.add(m.group(2))
        for m in re.finditer(r"feature\(\"[^\"]+\", " + LIT + r", " + LIT, src):
            found.update([m.group(1), m.group(2)])
        for m in re.finditer(r"item\(\"[^\"]+\", " + LIT + r", " + LIT, src):
            found.update([m.group(1), m.group(2)])
        for m in re.finditer(r"kpi\(" + LIT, src):
            found.add(m.group(1))
    out = set()
    for k in found:
        if "\\(" in k:
            continue  # interpolatie: staat apart in strings_en.json met %@/%lld
        if not k or not re.search(r"[A-Za-z]", k) or k.startswith(("#", "http", "pasr", "PZ", "app.")) and " " not in k:
            continue
        if re.fullmatch(r"[a-z0-9]+(\.[a-z0-9]+)+", k):
            continue  # SF Symbol
        if k in {"checkmark", "circle", "envelope", "hourglass", "paintpalette", "faceid", "touchid", "opticid"}:
            continue
        out.add(k.replace('\\"', '"'))
    return out


def main():
    ks = keys() | {k for k in EN if "%" in k}
    missing = sorted(k for k in ks if k not in EN)
    strings = {}
    for k in sorted(ks | set(EN)):
        entry = {"localizations": {"nl": {"stringUnit": {"state": "translated", "value": k}}}}
        if k in EN:
            entry["localizations"]["en"] = {"stringUnit": {"state": "translated", "value": EN[k]}}
        strings[k] = entry
    catalog = {"sourceLanguage": "nl", "strings": strings, "version": "1.0"}
    (APP / "Localizable.xcstrings").write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    info = {
        "CFBundleDisplayName": ("Pasr Zakelijk", "Pasr Zakelijk"),
        "CFBundleName": ("Pasr Zakelijk", "Pasr Zakelijk"),
        "NSCameraUsageDescription": (
            "Pasr Zakelijk gebruikt de camera om stempelkaarten, tickets, klantenkaarten, kortingsbonnen en codes van je klanten te scannen.",
            "Pasr Zakelijk uses the camera to scan your customers' stamp cards, tickets, loyalty cards, coupons and codes."),
        "NSFaceIDUsageDescription": (
            "Pasr Zakelijk gebruikt Face ID om de app te vergrendelen, zodat alleen jij stempels kunt zetten.",
            "Pasr Zakelijk uses Face ID to lock the app, so only you can add stamps."),
    }
    istr = {k: {"extractionState": "manual", "localizations": {
        "nl": {"stringUnit": {"state": "translated", "value": nl}},
        "en": {"stringUnit": {"state": "translated", "value": en}}}} for k, (nl, en) in info.items()}
    (APP / "InfoPlist.xcstrings").write_text(json.dumps({"sourceLanguage": "nl", "strings": istr, "version": "1.0"},
                                                         ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    print(f"{len(strings)} teksten, {len(missing)} zonder Engels")
    for k in missing:
        print("  ontbreekt:", json.dumps(k, ensure_ascii=False))
    sys.exit(1 if missing else 0)


if __name__ == "__main__":
    main()
