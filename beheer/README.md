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
- **Berichten (1.0.3):** een pushmelding sturen aan gebruikers die in de app "Nieuws over mijn kaarten" aanzetten. Doelgroep: iedereen met opt-in, heeft een kaart van winkel X, nieuwe gebruikers (7 dagen) of inactief (30 dagen). Met voorbeeld, aantal ontvangers, bevestiging en geschiedenis. Alleen winkel-id's per apparaat, nooit kaartnummers.
- **Ondernemers (1.0.3):** zaken die zich aanmeldden op pasr.nl/zakelijk goedkeuren, blokkeren (kaarten gaan offline) of terugzetten, met hun stempelkaarten (leden, stempels, beloningen). Een nieuwe aanmelding geeft een pushmelding (schakelaar "Winkel aangevraagd of nieuwe ondernemer").
- **Ondernemers: details (zakelijk 1.0, PasrBeheer build 12, LRbeheer build 58):** per zaak de instellingen (afkoeltijd, max stempels per scan, vindbaar in Pasr aan/uit om een zaak uit de lijst te halen, adres), stempels per dag (30 dagen), medewerkers (intrekken) en de log (wie gaf wanneer welke stempel, ook ongedaan gemaakt). Acties `business_detail`, `business_settings`, `business_staff_revoke` in de functie admin. Op het web: knop Details bij een zaak.
- **iOS en Android (PasrBeheer build 14, LRbeheer build 60, beheer.pasr.nl):** kaart **iOS en Android** in Overzicht (Pasr of Zakelijk): actieve toestellen per dag per platform (gestapeld, met kruisdraad, Homey Insights-stijl), nieuwe installaties, Google Wallet- en Apple Wallet-passen per dag, accounts per platform (signup-metadata `app`), versies in gebruik. Op het web ook als bronnen in Insights (Pasr actief op iOS/Android, nieuwe Android-toestellen, Google Wallet-passen). Actie `platforms` (functie admin, `pasr_admin_platforms`); de apps melden zich met `pasr_device_register`. Teksten niet meer alleen Apple: "Apple Wallet-passen" naast Google Wallet.
- **Ondernemers: zelf aanmaken (zakelijk 1.1, PasrBeheer build 13, LRbeheer build 59):** knop **Nieuwe ondernemer** (naam, plaats, adres, website, e-mail van de eigenaar, vindbaar, afkoeltijd, max per scan; meteen goedgekeurd). Heeft het e-mailadres al een bevestigd Pasr-account, dan wordt dat eigenaar; anders een eigenaarslink (30 dagen, `pasr.nl/zakelijk/uitnodiging/#code`, gemaild via PASR_SMTP_* of te kopiëren, opnieuw te versturen). Zonder e-mail: geen eigenaar, het beheer beheert de zaak. Per zaak **Bewerken** en **Nieuwe stempelkaart**: kaarteditor met live voorbeeld (zoals pasr.nl/zakelijk), **Huisstijl ophalen** (zelfde code als business-brand), QR-code en link, flyer, publiceren, offline halen en verwijderen. Per kaart **Testklant maken** voor de App Review: lid met label "Testklant (App Review)", klantcode als tekst en grote QR-code (PNG of afdrukken), resetten of verwijderen. Alles komt in de log van de zaak met actor "beheer" (alleen zichtbaar in het beheer). Acties `business_create`, `business_update`, `business_owner_invite`, `business_card_save/_publish/_delete`, `business_brand`, `business_test_member/_reset/_delete`.
- **E-mail bevestigen (zakelijk 1.1):** bij Accounts de knop **E-mail bevestigen** voor accounts zonder bevestigd e-mailadres (bijv. review@pasr.nl, dat geen mail kan ontvangen); zet via de Auth admin API `email_confirm=true`, vraagt eerst om bevestiging en komt in het audit-log. Bij **Nieuwe ondernemer** met een adres van een onbevestigd account: **Account bevestigen en eigenaar maken**. Wachtwoorden stelt het beheer nooit in. Acties `user_confirm`, `business_owner_confirm`.
- **Gids:** ook het verjaardagsvoordeel (`birthday`), alleen als de officiële site het noemt.
- **Instellingen:** Face ID, pushmeldingen per soort, testmelding, uitloggen en overal uitloggen.

De inhoud van kaarten is nergens te zien: die staat versleuteld in de database en het beheer leest alleen aantallen.

## Pushmeldingen

De database geeft de functie `admin` via pg_net een seintje bij een nieuw account, een bevestiging, een verwijderd account en een tegengehouden bot (bots hoogstens één melding per uur). De functie stuurt een melding naar elk apparaat met Pasr Beheer dat die soort aan heeft. Meldingen bevatten alleen aantallen, nooit e-mailadressen of namen.

## Secrets (GitHub › Settings › Secrets and variables › Actions)

| Secret | Voor |
|---|---|
| `PASR_ADMIN_USER`, `PASR_ADMIN_PASSWORD` | inloggen (wachtwoord minstens 6 tekens) |
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
