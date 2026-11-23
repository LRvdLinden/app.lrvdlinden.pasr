# Pasr Zakelijk

De iOS-app voor ondernemers (iPhone en iPad, iOS 17+, Nederlands en Engels): stempels zetten met de scanner,
stempelkaarten maken, QR-code en flyer, overzicht en logboek, medewerkers, vergrendelen met Face ID.
Bundle ID `app.lrvdlinden.pasrzakelijk`, versie 1.0.2 (build 100). Beheer van ondernemers blijft in PasrBeheer, LRbeheer en beheer.pasr.nl.

| Map | Inhoud |
|---|---|
| `apple/` | Xcode-project `PasrZakelijk.xcodeproj` (maak opnieuw met `python3 zakelijk/apple/make_project.py`; versie en build staan bovenin dat script) |
| `apple/tools/make_strings.py` | Schrijft `Localizable.xcstrings` en `InfoPlist.xcstrings` (nl = ontwikkeltaal, Engels uit `apple/tools/strings_en.json`) |
| `appstore/` | App Store-content: screenshots nl-NL en en-US (iPhone en iPad), productpagina-beelden, teksten, privacy en review-notities |

CI: `.github/workflows/zakelijk-app.yml` compileert de app bij elke push die `zakelijk/` raakt.

## Deellink met eigen pagina (iOS build 5)

QR-code, link en Delen gebruiken `https://pasr.nl/zakelijk/kaart/<kaart-id>/`: een eigen pagina per kaart met de kaart als OG-afbeelding (WhatsApp, iMessage, Facebook, LinkedIn). Oude QR-codes met `#<kaart-id>` blijven werken.

## Pushmeldingen (iOS build 4)

De app vraagt één keer om meldingen, op een rustig moment nadat je zaak is goedgekeurd, en meldt het APNs-token met
`pasr_device_register` (`p_app: "zakelijk"`, `p_platform: "ios"`, `p_push_provider: "apns"`, `p_push_sandbox`). Het beheer
kan dan een belangrijk bericht sturen aan iedereen met meldingen aan in Pasr Zakelijk (APNs-topic
`app.lrvdlinden.pasrzakelijk`). Een tik op een melding met `url` opent die link: een uitnodigingslink op de juiste plek in
de app, andere https-links in Safari in de app. Capability Push Notifications staat in `Config/PasrZakelijk.entitlements`
(`aps-environment`); bij automatisch ondertekenen zet Xcode Push Notifications ook aan bij de App ID.

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
  het artifact `PasrZakelijk-Android`. De APK staat op `pasr.nl/zakelijk/download/` (bestand `pasr-zakelijk.apk`); de app
  linkt daar ook naar in Instellingen ("Nieuwste versie downloaden") en in de uitnodigingstekst.
- Ondertekenen: altijd dezelfde sleutel (versleuteld in `android/zakelijk/signing/pasrzakelijk.jks.enc`, ontgrendeld met
  de secret `PASR_APNS_KEY_P8`). Vingerafdruk: `android/zakelijk/signing/cert-sha256.txt` (staat ook in
  `website/.well-known/assetlinks.json`). Geen Play Store: geen beoordelingsvraag of "Beoordeel"-link.
- Push: Firebase Cloud Messaging. `google-services.json` schrijft de workflow uit de secret `FIREBASE_GOOGLE_SERVICES_JSON`
  (nooit in de repo); het token gaat als `p_push_token` mee in `pasr_device_register`. De server verstuurt (ANDROID-PASR).
- Nieuwste APK en schermafbeeldingen: branch `android-builds`, mappen `zakelijk/` en `zakelijk-previews/`.
