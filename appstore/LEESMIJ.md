# Pasr in de App Store

Alles om Pasr in App Store Connect te zetten: teksten (Nederlands), screenshots in de verplichte formaten en promotiebeelden.

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

## Screenshots (`screenshots/`)

| Map | Toestel in App Store Connect | Formaat | Aantal |
|---|---|---|---|
| `iPhone 6.9 inch (1320x2868)` | iPhone 6,9" (verplicht) | 1320 × 2868 | 7 |
| `iPhone 6.5 inch (1284x2778)` | iPhone 6,5" (optioneel; anders schaalt Apple de 6,9") | 1284 × 2778 | 7 |
| `iPad 13 inch (2064x2752)` | iPad 13" (verplicht, Pasr werkt op de iPad) | 2064 × 2752 | 6 |
| `Apple Watch Ultra (422x514)` | Apple Watch Ultra 3 (verplicht, Pasr heeft een Watch-app) | 422 × 514 | 3 |
| `Apple Watch Series 46mm (416x496)` | Apple Watch Series 11 46 mm (optioneel) | 416 × 496 | 3 |

Volgorde = bestandsnaam (01 eerst). Apple staat 1 tot 10 screenshots per toestel toe.

## Promotie (`promo/`)

- `artwork-1920x1080.png` en `artwork-3840x2160.png`: artwork om Pasr bij Apple aan te melden voor uitlichting (App Store Connect › Featuring nomination) en voor de website.
- `event-card-1920x1080.png` en `event-details-1080x1920.png`: formaten voor een In-App Event (kaart 16:9 en detail 9:16).
- `social-1200x630.png`: voor sociale media en links.

## App-icoon

`app-icoon-1024.png` (1024 × 1024, zonder transparantie). Xcode gebruikt het icoon uit de app zelf; dit bestand is voor promotie of als je het los nodig hebt.

## Let op

- De screenshots laten de app zien zoals hij werkt, met echte winkellogo's (zoals in de app). Apple kan bij logo's van andere merken om uitleg vragen; daarvoor staat de zin over merknamen onderaan de beschrijving en in de review-notities.
- Opnieuw maken na een wijziging: `node appstore/source/render.cjs <map>` (teksten en kaarten staan in `appstore/source/scenes.html`).
