# Pasr Zakelijk — App-informatie voor App Store Connect

Versie **1.0.0 (build 2)** · iPhone en iPad · iOS 17 of nieuwer

## Algemene informatie

| Veld (ASC) | Waarde |
|---|---|
| Name | Pasr Zakelijk |
| Bundle ID | `app.lrvdlinden.pasrzakelijk` |
| SKU | `app.lrvdlinden.pasrzakelijk` |
| Apple ID | **TODO** — bestaat pas als Léon de app in App Store Connect aanmaakt. Vul het daarna ook in `zakelijk/apple/PasrZakelijk/Core/AppStoreID.swift` in (zie `zakelijk/README.md`). |
| Primary Language | Dutch (Nederlands) |
| App-talen | Nederlands en Engels |
| Primary Category | Business (Zakelijk) — de app is een werkinstrument voor ondernemers (stempels zetten, kaarten beheren, medewerkers). |
| Secondary Category | Productivity (Productiviteit) — scannen aan de kassa, overzicht en logboek. |
| Content Rights | De app toont geen inhoud van derden. Logo's en kleuren van stempelkaarten komen van de ondernemer zelf (eigen foto of de openbare website van zijn eigen zaak). |
| License Agreement | Apple Standard EULA |
| Prijs | Gratis, geen in-app aankopen, geen abonnement, geen reclame |
| Beschikbaarheid | Nederland (net als Pasr; België kan Léon er eventueel bij zetten) |
| Toestellen | iPhone en iPad. Mac (Apple-chip) en Vision Pro: niet aanvinken, de app is gebouwd zonder "Designed for iPad". |
| Copyright | 2026 Léon van der Linden |
| Support-URL | https://pasr.nl/support/ |
| Marketing-URL | https://pasr.nl/zakelijk/ |
| Privacybeleid-URL | https://pasr.nl/privacy/#stempelkaarten-van-ondernemers (zelfde URL als in de app) |
| Export compliance | Alleen standaardversleuteling (HTTPS): `ITSAppUsesNonExemptEncryption = NO` staat in de Info.plist |
| Inloggen voor review | Ja — Pasr-account; demo-account: **TODO** (Léon vult in bij Sign-In Information) |

## Leeftijdsclassificatie (Age Rating)

Alle vragen: **Geen / Nee** (geen geweld, seks, grof taalgebruik, gokken, drugs, medische informatie, onbeperkte webtoegang, gebruikerscontact of door gebruikers gemaakte openbare inhoud). Uitkomst: **4+**.
Toelichting: de app opent alleen links naar pasr.nl en lrvdlinden.app in Safari; er is geen ingebouwde browser en geen chat.

## App Privacy (privacylabel)

Tracking: **Nee**. Geen advertenties, geen data brokers, geen analytics- of crash-SDK's van derden.

| Gegevenstype (ASC) | Waarom | Gekoppeld aan gebruiker | Tracking | Doel |
|---|---|---|---|---|
| Contact Info › Email Address | Pasr-account; e-mailadres van een uitgenodigde medewerker | Ja | Nee | App Functionality |
| Contact Info › Name | Voornaam bij het account; naam van een uitgenodigde medewerker | Ja | Nee | App Functionality |
| Identifiers › User ID | Account-ID (rol per zaak, logboek) | Ja | Nee | App Functionality |
| User Content › Photos or Videos | Het logo dat de ondernemer kiest voor een stempelkaart (verkleind tot 256 px) | Ja | Nee | App Functionality |
| User Content › Other User Content | Gegevens van de zaak (naam, plaats, website, adres met kaartpositie), stempelkaarten, logboek | Ja | Nee | App Functionality |

Niet verzameld: locatie van het apparaat (het adres van de zaak wordt door de ondernemer getypt), camerabeelden (QR-codes worden op het apparaat gelezen), Face ID-gegevens (blijven op het apparaat), gebruiksgegevens, diagnose, aankopen, financiële gegevens. Het logboek noteert alleen het soort apparaat ("iPhone"/"iPad"), geen apparaat-ID.

Dit klopt met `zakelijk/apple/PasrZakelijk/PrivacyInfo.xcprivacy` (e-mailadres, naam, gebruikers-ID, foto's, overige gebruikersinhoud; UserDefaults `CA92.1`).

## Toegankelijkheid (Accessibility Nutrition Labels)

Gecontroleerd in de code, voor iPhone en iPad:

| Functie | Claim | Waarom |
|---|---|---|
| VoiceOver | **Ja** | Knoppen met alleen een icoon hebben een label (zaklamp, zoeken, minder/meer, verversen, nieuwe kaart), de stempelkaart wordt voorgelezen als "Koffiekaart: 6 van 10 stempels", aantal-kiezer is aanpasbaar met vegen, periodekiezer W/M/K/J leest "Week/Maand/Kwartaal/Jaar". Splash en slot verbergen de app voor VoiceOver. |
| Larger Text | **Ja** | Teksten gebruiken de tekststijlen van iOS (Dynamic Type) en schermen scrollen. Enkele grote cijfers (kop van de grafiek, KPI's) hebben een vaste grootte. |
| Dark Interface | **Ja** | Weergave Automatisch / Licht / Donker; donker is volledig uitgewerkt. |
| Reduced Motion | Niet geclaimd | Het splashscreen volgt "Verminder beweging", andere animaties (veren bij stempels) nog niet overal. |
| Differentiate Without Color Alone | Niet geclaimd | Status heeft tekst en iconen (Online/Concept, rollen), maar niet volledig gecontroleerd. |
| Sufficient Contrast | Niet geclaimd | Niet gemeten. |
| Voice Control | Niet geclaimd | Niet getest. |
| Captions / Audio Descriptions | n.v.t. | De app heeft geen video of audio. |
