# Pasr Zakelijk

De iOS-app voor ondernemers (iPhone en iPad, iOS 17+, Nederlands en Engels): stempels zetten met de scanner,
stempelkaarten maken, QR-code en flyer, overzicht en logboek, medewerkers, vergrendelen met Face ID.
Bundle ID `app.lrvdlinden.pasrzakelijk`, versie 1.0.0 (build 2). Beheer van ondernemers blijft in PasrBeheer, LRbeheer en beheer.pasr.nl.

| Map | Inhoud |
|---|---|
| `apple/` | Xcode-project `PasrZakelijk.xcodeproj` (maak opnieuw met `python3 zakelijk/apple/make_project.py`; versie en build staan bovenin dat script) |
| `apple/tools/make_strings.py` | Schrijft `Localizable.xcstrings` en `InfoPlist.xcstrings` (nl = ontwikkeltaal, Engels uit `apple/tools/strings_en.json`) |
| `appstore/` | App Store-content: screenshots nl-NL en en-US (iPhone en iPad), productpagina-beelden, teksten, privacy en review-notities |

CI: `.github/workflows/zakelijk-app.yml` compileert de app bij elke push die `zakelijk/` raakt.

## Apple ID invullen (link "Beoordeel Pasr Zakelijk")

Zodra de app in App Store Connect staat:

1. Kopieer in App Store Connect › Pasr Zakelijk › App-informatie het **Apple ID** (alleen cijfers, bijv. `6830000000`).
2. Vul het in `apple/PasrZakelijk/Core/AppStoreID.swift` in: `static let zakelijk = "6830000000"`.
3. Verhoog de build in `apple/make_project.py` (`BUILD`), draai het script en commit.

Zolang het ID leeg is, staat de link "Beoordeel Pasr Zakelijk" niet in Instellingen. De beoordelingsvraag van iOS
(`requestReview`, 4 uur na het eerste gebruik, daarna hoogstens 1 keer per week, alleen op een rustig moment) werkt ook zonder ID.
Gebruik nooit het ID van Pasr: dat is een andere app.

## Android (map `android/zakelijk/`)

Pasr Zakelijk voor Android 1.0.0 (package `app.lrvdlinden.pasrzakelijk`, Android 8+), met dezelfde functies en RPC's als
de iOS-app: inloggen met het Pasr-account, zaak aanmelden, scannen (CameraX + ML Kit) of code typen met aantal-kiezer,
ongedaan maken, inwisselen en afkoeltijd, kaarten met automatische huisstijl (business-brand), QR, link en A4-flyer (PDF),
overzicht in Homey Insights-stijl, leden en logboek, medewerkers met uitnodigingslinks (App Links op
`pasr.nl/zakelijk/uitnodiging`, `pasrzakelijk://uitnodiging#code`), instellingen (vindbaar in Pasr, adres, afkoeltijd,
max per scan, vergrendelen met vingerafdruk of gezicht, Meer apps-kaart). Nederlands en Engels.

- Stack zoals Noodpakket en Bekendr: Kotlin 2.1, Compose, AGP 8.7, SDK 35/26, Java 17.
- Teksten: Engels komt uit `apple/PasrZakelijk/Localizable.xcstrings` plus `android/zakelijk/tools/android-en.json`.
  Na een tekstwijziging: `python3 tools/make_strings.py` in `android/zakelijk` (CI controleert dit).
- CI: `.github/workflows/android-zakelijk.yml` bouwt bij elke push op `gedeelde-pasr` die `android/zakelijk/` raakt een
  ondertekende APK, maakt release `android-zakelijk-<versie>-<code>` (pasr-zakelijk.apk + .json, schermafbeeldingen) en
  het artifact `PasrZakelijk-Android`. De workflow Website zet hem op `pasr.nl/download/pasr-zakelijk.apk`.
- Ondertekenen: altijd dezelfde sleutel (versleuteld in `android/zakelijk/signing/pasrzakelijk.jks.enc`, ontgrendeld met
  de secret `PASR_APNS_KEY_P8`). Vingerafdruk: `android/zakelijk/signing/cert-sha256.txt` (staat ook in
  `website/.well-known/assetlinks.json`). Geen Play Store: geen beoordelingsvraag of "Beoordeel"-link.
