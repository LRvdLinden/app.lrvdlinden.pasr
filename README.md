# Pasr

Al je klantenkaarten en vouchers in één app, in de stijl van Apple Wallet. Voor iPhone, iPad, Mac en Apple Watch, zonder account of server: alles staat op je eigen apparaten en in je eigen iCloud.

Pasr is alleen voor Nederland: de app is volledig Nederlandstalig en de winkelsjablonen zijn Nederlandse winkels. Zet in App Store Connect bij *Prijzen en beschikbaarheid* alleen Nederland aan.

## Openen in Xcode

1. Open `Pasr.xcodeproj` (Xcode 26 of nieuwer).
2. Kies bij beide targets (Pasr en PasrWatch) je team onder *Signing & Capabilities*.
3. Maak in je Apple Developer-account aan, of laat Xcode dat doen:
   - App ID `nl.lrvdlinden.pasr` met iCloud (CloudKit), Push Notifications en App Groups;
   - App ID `nl.lrvdlinden.pasr.watchkitapp` met iCloud (CloudKit) en Push Notifications;
   - iCloud-container `iCloud.nl.lrvdlinden.pasr` en App Group `group.nl.lrvdlinden.pasr`.
4. Kies het schema **Pasr** voor iPhone, iPad of *My Mac*, en **PasrWatch** voor de Watch.

## Opbouw

| Map | Inhoud |
| --- | --- |
| `App/` | App voor iPhone, iPad en Mac: splash, Wallet-stapel, editor, scanner, import van screenshots, instellingen |
| `Watch/` | Watch-app: kaarten in Wallet-stijl en de code op het hele scherm |
| `Shared/` | Datamodel (SwiftData + CloudKit), barcode-encoders, kaartweergave, winkelsjablonen, vertalingen |
| `Config/` | Info.plist en entitlements |
| `tools/` | Scripts voor het projectbestand, het app-icoon en de barcodetest |

De mappen `App/`, `Shared/` en `Watch/` zijn gesynchroniseerde mappen: nieuwe bestanden horen automatisch bij de juiste target.

## Logo's

Pasr levert geen logo's van winkels mee. Er zijn twee manieren om er een op een kaart te krijgen:

- **Van de website van de winkel.** Elke winkelsjabloon heeft een webadres (bijv. `ah.nl`); bij eigen kaarten kun je er zelf een invullen. Het apparaat haalt het icoon op dat de winkel daar publiceert (`apple-touch-icon`, anders het site-icoon). Dit staat standaard aan en kan uit in Instellingen; logo's van websites verdwijnen dan weer.
- **Zelf uitknippen.** Uit een foto, een screenshot of de foto van de voorkant van de kaart, ook bij het importeren van Klarna-screenshots. Een eigen logo wordt nooit overschreven.

## Barcodes

EAN-13, EAN-8, UPC-A, Code 128, Code 39 en ITF worden door Pasr zelf getekend, ook op de Watch. QR, PDF417 en Aztec maakt Core Image; de iPhone bewaart daarvan een PNG die via iCloud naar de Watch gaat.

Test van de encoders (1.800 gevallen tegen python-barcode):

```
pip install python-barcode
python3 tools/verify_barcodes.py
```
