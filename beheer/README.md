# Pasr Beheer

Het beheer van Pasr: tellingen, accounts en pushmeldingen. Twee onderdelen, één backend.

| Onderdeel | Waar | Wat |
|---|---|---|
| Dashboard | `beheer/web/` → https://beheer.pasr.nl | statisch (geen build-stap), strikte CSP, `noindex` |
| App Pasr Beheer | `beheer/apple/` | SwiftUI, één target voor iPhone, iPad en Mac (native), Face ID / Touch ID, pushmeldingen |
| Functie `admin` | `supabase/functions/admin/` | inloggen (eigen HMAC-token, 12 uur), statistieken, accounts, pushmeldingen (APNs) |
| Database | `supabase/schema.sql` (blok "Pasr Beheer") | tellingen per dag, logboek, pushapparaten, triggers die de functie een seintje geven |

## Wat je ziet

- **Overzicht:** accounts (nieuw, bevestigd, actief), kaarten in accounts, Wallet-passen, een grafiek per dag (week, maand, kwartaal, jaar) met nieuwe, bevestigde en verwijderde accounts, Wallet-passen en tegengehouden bots, de redenen waarom bots zijn tegengehouden, en hoeveel kaarten mensen in hun account hebben.
- **Accounts:** zoeken op e-mail of voornaam, filters, aantal kaarten, laatste login en sync, bevestigingsmail opnieuw sturen, account verwijderen.
- **Instellingen:** Face ID, pushmeldingen per soort, testmelding, uitloggen en overal uitloggen.

De inhoud van kaarten is nergens te zien: die staat versleuteld in de database en het beheer leest alleen aantallen.

## Pushmeldingen

De database geeft de functie `admin` via pg_net een seintje bij een nieuw account, een bevestiging, een verwijderd account en een tegengehouden bot (bots hoogstens één melding per uur). De functie stuurt een melding naar elk apparaat met Pasr Beheer dat die soort aan heeft. Meldingen bevatten alleen aantallen, nooit e-mailadressen of namen.

## Secrets (GitHub › Settings › Secrets and variables › Actions)

| Secret | Voor |
|---|---|
| `PASR_ADMIN_USER`, `PASR_ADMIN_PASSWORD` | inloggen (wachtwoord minstens 12 tekens) |
| `PASR_APNS_KEY_P8` | inhoud van het .p8-bestand van een APNs-sleutel (Apple Developer › Keys, "Apple Push Notifications service"); een sleutel van hetzelfde team werkt voor alle apps |
| `PASR_APNS_KEY_ID` | de Key ID van die sleutel (10 tekens) |
| `BEHEER_FTP_USER`, `BEHEER_FTP_PASSWORD` | een FTP-account dat uitkomt in de map van beheer.pasr.nl; of in plaats daarvan `BEHEER_FTP_DIR` (die map, gezien vanaf de FTP-login van pasr.nl) |

`PASR_TOKEN_SECRET` maakt de workflow Backend zelf, alleen in Supabase.

## Workflows

- **Backend** zet het schema, de functie `admin` en de secrets in Supabase en doet een rooktest.
- **Beheer** zet `beheer/web/` via FTPS op beheer.pasr.nl.
- **Beheer-app** bouwt de app voor de iOS-simulator en de Mac (zonder ondertekenen) als controle.

## App bouwen

Open `beheer/apple/PasrBeheer.xcodeproj`, kies bovenin iPhone, iPad of "My Mac" en druk op Run. Ondertekenen gaat automatisch met team EU3UY476T6; Xcode zet Push Notifications aan voor de app-id `nl.lrvdlinden.pasr.beheer`. Het buildnummer staat in `beheer/apple/make_project.py` (eigen reeks, los van Pasr).
