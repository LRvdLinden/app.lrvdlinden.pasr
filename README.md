# Pasr

Al je klantenkaarten en vouchers in één app, in de stijl van Apple Wallet. Voor iPhone, iPad en Apple Watch. Alles staat op je eigen apparaten en in je eigen iCloud; een gratis Pasr-account is optioneel.

Pasr is alleen voor Nederland: de app is volledig Nederlandstalig en de winkelsjablonen zijn Nederlandse winkels. Zet in App Store Connect bij *Prijzen en beschikbaarheid* alleen Nederland aan.

## Openen in Xcode

1. Open `Pasr.xcodeproj` (Xcode 26 of nieuwer).
2. Kies bij beide targets (Pasr en PasrWatch) je team onder *Signing & Capabilities*.
3. Maak in je Apple Developer-account aan, of laat Xcode dat doen:
   - App ID `nl.lrvdlinden.pasr` met iCloud (CloudKit), Push Notifications en App Groups;
   - App ID `nl.lrvdlinden.pasr.watchkitapp` met iCloud (CloudKit) en Push Notifications;
   - iCloud-container `iCloud.nl.lrvdlinden.pasr` en App Group `group.nl.lrvdlinden.pasr`.
4. Kies het schema **Pasr** voor iPhone of iPad, en **PasrWatch** voor de Watch.

## Opbouw

| Map | Inhoud |
| --- | --- |
| `App/` | App voor iPhone en iPad: splash, Wallet-stapel, editor, scanner, import van screenshots, instellingen |
| `Watch/` | Watch-app: kaarten in Wallet-stijl en de code op het hele scherm |
| `Widgets/` | Widgets: Favorieten (raster met je favoriete kaarten) en Kaart (één gekozen kaart met barcode, ook op het toegangsscherm) |
| `website/` | De website pasr.nl (statisch, Nederlands) |
| `Shared/` | Datamodel (SwiftData + CloudKit), barcode-encoders, kaartweergave, winkelsjablonen, vertalingen |
| `Config/` | Info.plist en entitlements |
| `tools/` | Scripts voor het projectbestand, het app-icoon en de barcodetest |

De mappen `App/`, `Shared/` en `Watch/` zijn gesynchroniseerde mappen: nieuwe bestanden horen automatisch bij de juiste target.

## Widgets

De app schrijft na elke wijziging een overzicht van je kaarten naar de App Group `group.nl.lrvdlinden.pasr`; de widgets lezen dat. Een tik op een kaart opent Pasr via `pasr://card/<id>` en haalt die kaart naar voren.

## Kaarten delen

Een gedeelde kaart is een link `https://pasr.nl/kaart/#<gegevens>`. De kaart staat na het `#`, dus de server ziet hem nooit. Met Pasr geïnstalleerd opent de link de app (universal link, `applinks:pasr.nl`); zonder Pasr toont `website/kaart/` de kaart met een werkende barcode. In de app: Deel bij een kaart, als link of als QR-code.

## Website

De site staat in `website/` en heeft schone adressen (`/privacy/`, `/support/`, geen `.html`). De homepage wordt gemaakt met `python3 tools/make_website.py` (met echte barcodes voor de voorbeeldkaarten).

De share-afbeeldingen maak je opnieuw met `python3 tools/og/render.py` (vanuit `tools/og/og.html` en `og-share.html`). Universal links staan in `website/.well-known/apple-app-site-association`.

Publiceren gaat via FTP met de workflow **Website** (`.github/workflows/website.yml`) bij elke push naar `main` die `website/` wijzigt. Zet hiervoor deze repository-secrets: `FTP_SERVER`, `FTP_USER`, `FTP_PASSWORD` en eventueel `FTP_PORT` en `FTP_DIR`. Zolang `FTP_SERVER` ontbreekt, slaat de workflow het uploaden over.

## Apple Wallet (build 17)

"Voeg toe aan Apple Wallet" bij een kaart die naar voren is gehaald. De app stuurt de kaart naar de functie `supabase/functions/wallet-pass` (Supabase Edge Function), die er een `.pkpass` van maakt, ondertekent met het Pass Type ID-certificaat en direct terugstuurt. Er wordt niets bewaard. Tot 10 filialen in de buurt gaan mee als `locations`, zodat iOS de pas op het toegangsscherm toont. EAN-codes worden Code 128 (Wallet kent geen EAN).

Instellen:
1. developer.apple.com › Identifiers › + › **Pass Type IDs** › `pass.nl.lrvdlinden.pasr`.
2. Certificaat aanmaken met een CSR uit Sleutelhangertoegang, downloaden, dubbelklikken, en in Sleutelhangertoegang exporteren als `.p12` met wachtwoord.
3. Repository-secrets: `PASS_CERT_P12` (`base64 -i Pasr.p12 | pbcopy`), `PASS_CERT_PASSWORD`, optioneel `PASS_TYPE_ID`.
4. Draai Actions › Backend. De knop verschijnt in de app zodra `AccountConfig` is ingevuld.

## Beoordelingsvraag (build 21)

De App Store-beoordelingsvraag (`App/Services/ReviewPrompt.swift`, via `requestReview`):

- Eerste keer: 4 uur na het eerste gebruik op dat apparaat.
- Daarna: hoogstens één keer per week opnieuw. iOS toont het venster zelf maximaal 3 keer per jaar en niet meer aan wie al heeft beoordeeld; in TestFlight verschijnt het nooit.
- Alleen op een rustig moment: 3 seconden na het openen, niet tijdens de splash of het welkomstscherm, niet als de app vergrendeld of afgedekt is, niet tijdens het toevoegen van een gedeelde kaart, en alleen als er minstens één kaart in Pasr staat.

## Pasr Beheer

Dashboard op beheer.pasr.nl en de app Pasr Beheer (iPhone, iPad, Mac): zie [`beheer/README.md`](beheer/README.md).

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

## Pasr-account (optioneel, build 6)

Gebruikers kunnen een gratis account maken (e-mail + wachtwoord) en hun kaarten daarin bewaren. Zonder account werkt Pasr zoals altijd via iCloud.

- **App**: `App/Account/` (geen SDK, gewone HTTPS). Sessie in de sleutelhanger, alleen op dit apparaat. `CardSync` synchroniseert in één ronde via de databasefunctie `pasr_sync`; de nieuwste wijziging van een kaart wint. Welkomstschermen: `App/Views/OnboardingView.swift`.
- **Server**: `supabase/schema.sql`. Kaarten staan versleuteld (pgcrypto, AES-256) in `pasr_cards`, alleen bereikbaar via `pasr_sync` en `pasr_delete_account`.
- **Tegen bots**: verborgen honeypotveld `website` + tijdmeting (`fill_ms`) in app en op pasr.nl/account, limiet per netwerk (3/uur, 10/dag, alleen een gezouten hash) en wegwerpadressen geweigerd, via de Auth-hook `pasr_before_user_created`. Onbevestigde accounts zonder kaarten gaan na 48 uur weg.
- **Mails** in Pasr-huisstijl: `supabase/templates/build.py` (bevestigen, wachtwoord vergeten, e-mail wijzigen, inloglink). Links gaan naar `pasr.nl/bevestigen/`, die pas na een tik bevestigt.
- **Workflow Backend** zet schema, mails, hook en Auth-instellingen bij elke wijziging in `supabase/`.

Instellen:
1. Maak op supabase.com een nieuw project **Pasr** (regio Frankfurt of Amsterdam).
2. Repository-secrets: `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `PASR_SUPABASE_URL`, `PASR_SUPABASE_KEY` (publishable key) en voor eigen mail `PASR_SMTP_HOST`, `PASR_SMTP_PORT`, `PASR_SMTP_USER`, `PASR_SMTP_PASSWORD`, `PASR_SMTP_FROM`.
3. Draai Actions › Backend en Actions › Website.
4. Vul `AccountConfig.url` en `AccountConfig.publishableKey` in `App/Account/AccountService.swift` in.

## Logo's

`App/StoreLogos/<domein>.png` zijn doorzichtige logo's, zoals SuperCards ze op de kaart zet: het volledige woordmerk van Wikidata/Wikimedia Commons waar dat er is, anders het icoon van de winkelsite met de achtergrond eruit gehaald. `Shared/Model/StoreLogoStyles.swift` (gegenereerd) geeft per winkel de kaartkleur. Workflow Logos haalt ze op (`tools/fetch_logos.py`).
