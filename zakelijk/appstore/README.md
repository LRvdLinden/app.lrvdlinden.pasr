# Pasr Zakelijk in de App Store

App Store-content voor **Pasr Zakelijk 1.0.0 (build 2)**, bundle `app.lrvdlinden.pasrzakelijk`, iPhone en iPad.
Zelfde stijl als de App Store-beelden van Pasr (`appstore/` in de root): dezelfde achtergronden (donker, licht, iris),
typografie (Bricolage Grotesque en Figtree) en toestellen, met het icoon van Pasr Zakelijk en het mintgroene "ZAKELIJK" als accent.

## Inhoud

| Map / bestand | Wat |
|---|---|
| `metadata/` | Teksten in fastlane-deliver-opzet: `nl-NL/` en `en-US/` (naam, ondertitel, promotietekst, beschrijving, trefwoorden, Wat is nieuw, URL's), categorie, copyright |
| `metadata/review_information/` | `notes.txt` (Engels, voor App Review › Notes), `notes-nl.txt` (Nederlandse kopie, niet uploaden), contact en demo-account (alleen TODO's, nooit echte wachtwoorden) |
| `metadata/privacy/` | Privacytekst NL en EN |
| `app-info.md` | Algemene informatie, leeftijd, privacylabel en toegankelijkheid |
| `screenshots/<taal>/<toestel>/` | 10 screenshots per iPhone/iPad-toestel en taal; `mac/`: 7 Mac-screenshots (2880 × 1800) |
| `marketing/<taal>/` | Productpagina-beelden: header 5244×2950 en 3840×1646, zoekresultaten 5244×2950, 3840×2560 en 1920×1280 |
| `app-icoon-1024.png` | Het app-icoon (1024×1024, zonder transparantie) |
| `source/` | Bron: `scenes.html`, `render.cjs`, `flatten.py`, `base.css` en `status.js` (overgenomen van Pasr), `strings_en_all.json` (Engelse app-teksten), fonts, icoon |

## Talen van de beelden

De app is **Nederlands en Engels** (`Localizable.xcstrings`), dus de beelden zijn er in **nl-NL** en **en-US**. In de Engelse beelden
staan de echte Engelse teksten van de app (uit `Localizable.xcstrings` van app en widgets en `zakelijk/apple/tools/strings_en.json`, samengevoegd in `source/strings_en_all.json`).

## Screenshots

| Map | Toestel in App Store Connect | Formaat |
|---|---|---|
| `iphone-6.9` | iPhone 6,9" (verplicht) | 1320 × 2868 |
| `iphone-6.5` | iPhone 6,5" | 1284 × 2778 |
| `iphone-6.3` | iPhone 6,3" | 1206 × 2622 |
| `iphone-6.1` | iPhone 6,1" | 1179 × 2556 |
| `ipad-13` | iPad 13" (verplicht, de app werkt op de iPad) | 2064 × 2752 |
| `mac` | Mac (verplicht voor het macOS-platform) | 2880 × 1800 |

Volgorde iPhone/iPad: 01 scannen · 02 aantal stempels kiezen · 03 tabblad Acties · 04 QR-code, flyer en knop voor je website · 05 overzicht (grafiek) ·
06 medewerkers · 07 veilig stempelen (afkoeltijd, ongedaan maken, Face ID, logboek) · 08 tickets aan de deur · 09 klantenkaart met korting ·
10 gezamenlijke acties.

Volgorde Mac: 01 Vandaag · 02 scanvenster · 03 tickets · 04 klantenkaart met kortingsperiodes · 05 gezamenlijke acties · 06 inzichten ·
07 widgets op het bureaublad.

De schermen zijn **nagebouwd in HTML** op basis van de SwiftUI-code (er was geen Xcode/simulator), met neutrale voorbeelddata
(Koffiebar De Hoek, voorbeeld.nl-adressen). De Mac-schermen zijn nagebouwd uit `zakelijk/apple/Mac/` in een getekende MacBook. Geen Apple Watch- of Apple TV-screenshots.

Opnieuw maken (vanuit de root van de repo):

```
node zakelijk/appstore/source/render.cjs zakelijk/appstore
python3 zakelijk/appstore/source/flatten.py zakelijk/appstore
```

## Uploaden — checklist

1. App aanmaken in App Store Connect (bundle `app.lrvdlinden.pasrzakelijk`, SKU gelijk), taal Nederlands; taal English (U.S.) toevoegen.
2. **Apple ID**: 6837907454 (https://apps.apple.com/nl/app/pasrzakelijk/id6837907454), ingevuld in `AppStoreID.swift`.
3. Teksten uit `metadata/nl-NL` en `metadata/en-US`, URL's, categorie Business + Productivity, copyright.
4. Screenshots per toestel en taal; productpagina-beelden uit `marketing/`.
5. App Privacy en Toegankelijkheid volgens `app-info.md`; leeftijd 4+.
6. App Review: inloggegevens van het demo-account invullen (**TODO**), notes uit `metadata/review_information/notes.txt`.
   **Keur de demo-zaak vooraf goed** in het beheer (tab Ondernemers), anders kan de reviewer geen stempels zetten.
7. Contact (telefoon, e-mail): **TODO** in App Store Connect.
