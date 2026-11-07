# Pasr in de App Store

Alles om Pasr in App Store Connect te zetten: teksten (Nederlands en Engels), screenshots in de verplichte formaten en promotiebeelden.

Bijgewerkt voor build 30: gedeelde Pasr, tijdelijk delen, overstappen met een schermopname, winkels aanvragen, filter, licht thema, screenshotblokkade, Mac en Apple Vision Pro.

## Teksten (`teksten/`)

| Bestand | Veld in App Store Connect | Limiet |
|---|---|---|
| `01-naam.txt` | Naam | 30 tekens |
| `02-ondertitel.txt` | Ondertitel | 30 tekens |
| `03-promotietekst.txt` | Promotietekst (kun je altijd wijzigen zonder nieuwe versie) | 170 tekens |
| `04-beschrijving.txt` | Beschrijving | 4000 tekens |
| `05-trefwoorden.txt` | Trefwoorden (komma's, geen spaties, geen namen van andere apps) | 100 tekens |
| `06-nieuw-in-deze-versie.txt` | Nieuw in deze versie | 4000 tekens |
| `07-urls-en-overig.txt` | Support-, marketing- en privacy-URL, copyright, categorie, leeftijd | |
| `08-app-review-notities.txt` | App Review › Notities (Engels, voor de reviewer); vul het demo-account in | |
| `09-app-privacy.txt` | App Privacy (privacylabels) en encryptie | |

`teksten/en-US/` bevat naam, ondertitel, promotietekst, beschrijving, trefwoorden en nieuw-in-deze-versie voor de Engelse winkelpagina (taal *English (U.S.)* toevoegen in App Store Connect). De Engelse beschrijving zegt dat de app zelf Nederlands is. URL's, review-notities en privacy gelden voor beide talen.

## Screenshots (`screenshots/`)

| Map | Toestel in App Store Connect | Formaat | Aantal |
|---|---|---|---|
| `iPhone 6.9 inch (1320x2868)` | iPhone 6,9" (verplicht) | 1320 × 2868 | 10 |
| `iPhone 6.5 inch (1284x2778)` | iPhone 6,5" | 1284 × 2778 | 10 |
| `iPhone 6.3 inch (1206x2622)` | iPhone 6,3" | 1206 × 2622 | 10 |
| `iPhone 6.1 inch (1179x2556)` | iPhone 6,1" | 1179 × 2556 | 10 |
| `iPad 13 inch (2064x2752)` | iPad 13" (verplicht, Pasr werkt op de iPad) | 2064 × 2752 | 9 |
| `Apple Watch Ultra 3 (422x514)` | Apple Watch Ultra 3, in een Ultra 3-mockup | 422 × 514 | 3 |
| `Apple Watch Ultra 3 zonder mockup (422x514)` | Apple Watch Ultra 3, alleen het scherm (als Apple de mockup niet accepteert) | 422 × 514 | 3 |
| `Apple Watch Series 46mm (416x496)` | Apple Watch Series 11 46 mm, in mockup | 416 × 496 | 3 |

Volgorde = bestandsnaam (01 eerst). Apple staat 1 tot 10 screenshots per toestel toe.

iPhone-volgorde: 01 overzicht · 02 kaart aan de kassa · 03 scannen · 04 overstappen met één schermopname · 05 gedeelde Pasr met je gezin · 06 tijdelijk uitlenen · 07 t/m 10 Apple Wallet, cadeaukaarten, Watch en privacy. De iPad-set is gelijk, zonder het Watch-scherm.

**Waarom alleen Nederlandse screenshots?** De app zelf is alleen Nederlands. App Store Connect toont deze screenshots ook op de Engelse winkelpagina; Engelse screenshots zouden een app laten zien die niet bestaat.

**Mac en Apple Vision Pro** draaien Pasr als iPad-app (*Designed for iPad*). Daarvoor gebruikt App Store Connect automatisch de iPad-screenshots; aparte Mac- of Vision-screenshots zijn niet nodig. Zet wel de vinkjes aan onder *Prijzen en beschikbaarheid*.

## Promotie (`promo/`)

- `App Store artwork 1 (5244x2950, 3840x1646)`: voor het eerste artwork-vak (5244 × 2950 en 3840 × 1646).
- `App Store artwork 2 (5244x2950, 3840x2560, 1920x1280)`: voor het tweede artwork-vak.
- `In-App Event`: kaart 1920 × 1080 en detail 1080 × 1920.
- `Overig/social-1200x630.png`: voor sociale media en links.

## App-icoon

`app-icoon-1024.png` (1024 × 1024, zonder transparantie). Xcode gebruikt het icoon uit de app zelf; dit bestand is voor promotie of als je het los nodig hebt.

## Let op

- De screenshots laten de app zien zoals hij werkt, met echte winkellogo's (zoals in de app). Apple kan bij logo's van andere merken om uitleg vragen; daarvoor staat de zin over merknamen onderaan de beschrijving en in de review-notities.
- Opnieuw maken na een wijziging: `node appstore/source/render.cjs <map>` (teksten en kaarten staan in `appstore/source/scenes.html`).
