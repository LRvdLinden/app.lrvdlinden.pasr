# Pasr beheer › Mail (backend)

Tickets, losse mails en nieuwsbrieven vanuit Pasr beheer. Dit document beschrijft het contract van de backend; het scherm in het beheer bouwt erop voort.

## Onderdelen

| Onderdeel | Waar |
|---|---|
| Database (tabellen, RPC's, afmeldtokens, pg_cron) | `supabase/20261128-beheer-mail.sql` (herhaalbaar), test: `supabase/tests/beheer_mail_smoke.sql` |
| Functie `mail` (SMTP, IMAP, Markdown, campagnes) | `supabase/functions/mail/` |
| Doorsturen vanuit beheer | `supabase/functions/admin/mail.ts` plus de acties `mail_*` in `admin/index.ts` |
| Afmeldpagina | `website/afmelden/` (`?t=<token>` en `?k=nieuws`) |

`admin` controleert de beheersessie en schrijft het logboek (`admin_audit`: alleen aantallen en onderwerpen, nooit adressen of inhoud) en stuurt dan door naar `mail` met de kop `x-pasr-admin` (HMAC van `PASR_TOKEN_SECRET`). `mail` accepteert verder alleen `x-pasr-cron` (pg_cron, alleen `poll_inbox`) en de één-klik-afmelding `?stop=`.

## Acties (admin, alle met beheertoken)

`mail_status`, `mail_poll`, `mail_thread_list`, `mail_thread_get`, `mail_thread_reply`, `mail_thread_status`, `mail_thread_note`, `mail_compose`, `mail_attachment`, `mail_preview`, `mail_test`, `mail_campaign_audience`, `mail_campaign_send`, `mail_campaign_list`, `mail_campaign_cancel`.

Samenstellen (`mail_compose`) en antwoorden hebben drie volwaardige adresvelden: `to` (Aan), `cc` en `bcc`. Elk veld is een lijst of tekst met komma, puntkomma, spatie of regeleinde als scheiding.

- Aan en CC staan echt in de kopregels `To:` en `Cc:`. BCC staat alleen in de envelop (nooit in een kopregel of in de opgeslagen mail; er wordt alleen het aantal bewaard).
- Is Aan leeg en is er wel BCC, dan toont `To:` het afzenderadres.
- Grenzen: Aan 20, CC 20, in totaal 200 per aanroep; BCC gaat in groepen van hoogstens 50 per mail. Een adres dat al in Aan of CC staat, valt weg uit BCC.
- Bijlagen: `{name, type, data_b64}`, hoogstens 10 bestanden en samen **20 MB** (ruwe bytes) per mail. Het verzoek (base64 in JSON) mag tot **32 MB** (alleen met geldig token). Bij te veel krijgt de aanroep HTTP 413 met `{error: "too_large", max_bytes: 20971520, max_mb: 20, message}`; het maximum staat dus altijd in de foutmelding.
  Veel mailservers weigeren zelf mail boven ~20-25 MB (inclusief base64-overhead, een derde extra); daarom is 20 MB de bovengrens. Groter: gebruik een downloadlink.
  Geheugen en tijd: een edge function heeft 256 MB geheugen en 2 s CPU-tijd. De bijlagen worden in blokken (de)codeerd; lokaal gemeten kost 20 MB ongeveer 0,1 s decoderen, 0,3 s MIME opbouwen en 0,2 s opslaan, met een piek van ruim 250 MB RSS (waarvan een deel nog niet vrijgegeven afval). Dat past, maar zit dicht tegen de geheugengrens; BCC-groepen bouwen de mail per groep opnieuw op. Is de platformlimiet lager, dan komt dat als 5xx terug; de 413 hierboven komt alleen van onze eigen controle.
- `body_md` is Markdown (geen HTML): koppen, vet, cursief, lijsten, citaten, code, `[[Knop|https://…]]`, links alleen `https:` of `mailto:`. `{{voornaam}}` wordt ingevuld; `{{email}}` is niet toegestaan.
- Merken: `pasr` (iris `#6A5CFF`) en `zakelijk` (mint `#2ED3A6`, eigen kop en icoon, "Pasr voor ondernemers"). Donker met lichte variant via `prefers-color-scheme`.

Campagnes: doelgroep `users` (alle accounts in `auth.users` zonder afmelding) of `owners` (eigenaren van een zaak). `request_id` (uuid) maakt een verzoek herhaalbaar. Elke ontvanger krijgt een eigen mail met voornaam, persoonlijke afmeldlink en `List-Unsubscribe` plus `List-Unsubscribe-Post` (één klik). Een ronde stopt na ongeveer 90 seconden; pg_cron gaat verder (`pasr_mail_campaign_due`) en wie al een mail kreeg staat als korte hash in `pasr_mail_campaign_sent`.

Foutcodes: `bad_address`, `no_recipient`, `too_many`, `too_large` (413), `bad_attachment`, `bad_subject`, `bad_body`, `bad_brand`, `bad_status`, `bad_priority`, `bad_number`, `bad_audience`, `bad_request_id`, `rate_limited` (429), `not_found` (404), `smtp_not_configured` (503), `mail_unreachable` (502 vanuit admin).

## Inbox, Verzonden en alles

`mail_thread_list` (`thread_list`) heeft het filter `box`:

| `box` | Wat |
|---|---|
| `inbox` (standaard) | zoals tot nu toe; zonder `status` = actief (niet gesloten) |
| `sent` | tickets met minstens één uitgaand bericht, nieuwste uitgaande eerst; zonder `status` = alle statussen |
| `all` | alles, nieuwste activiteit eerst; zonder `status` = alle statussen |

Elk item: `number, subject, status, priority, brand, contact_name, contact_email, last_message_at, unread, preview`, en nieuw:

- `last_direction`: `"in"` of `"out"` (richting van het laatste echte bericht; notities tellen niet), `null` bij een leeg ticket
- `sent_at`: tijdstip van het laatste uitgaande bericht (`null` als er geen is)
- `to_preview`: het eerste adres van Aan van dat bericht; alleen BCC: `"n ontvangers"` (`"1 ontvanger"`); alleen CC: het eerste CC-adres; `null` zonder uitgaand bericht
- `to_count`, `cc_count`, `bcc_count`, `attachments`: aantallen van het laatste uitgaande bericht (BCC nooit als adressen)

Het antwoord heeft ook `box`, `total`, `page` en `counts`. Foutcode bij een onbekend filter: `bad_box`. `mail_thread_get` toont bij uitgaande berichten `to` en `cc` volledig en `bcc_count` als aantal. Compose (met `thread`, standaard `true`), `thread_reply` en uitnodigingen met een ticket staan altijd in Verzonden. Nieuwsbrief-campagnes blijven apart in `mail_campaign_list`.

## Pushmelding bij nieuwe mail

Na elke `poll_inbox`-ronde geeft de functie `mail` de database één seintje (`pasr_mail_notify`) met de nieuwe tickets en klantantwoorden van die ronde: `[{number, brand, subject}]` (onderwerp op 60 tekens, nooit adres of inhoud). `pasr_admin_notify('mail_ticket', …)` laat de functie `admin` de push versturen naar alle beheerapparaten (PasrBeheer en LRbeheer, dezelfde topics en deeplink-schema `pasrbeheer://`).

- Soort (`kind`): `mail_ticket`; schakelaar in `prefs`: `mail` (standaard aan, net als de andere schakelaars via `push_register` en `push_prefs`).
- Eén nieuwe mail: titel `Nieuwe mail · Pasr` of `Nieuwe mail · Pasr Zakelijk`, tekst `Ticket #1001: <onderwerp>`.
- Meer in één ronde: één melding met tekst `3 nieuwe mails` (de titel noemt het merk als alle mails van hetzelfde merk zijn, anders alleen `Nieuwe mail`).
- Deeplink (`url` in de payload): `pasrbeheer://mail`.

## Antwoorden komen terug

1. Elke uitgaande ticketmail heeft `[#1001]` in het onderwerp, een `Message-ID` van de vorm `<pasr-ticket-1001.xxxx@pasr.nl>`, de kop `X-Pasr-Ticket` en een `Reply-To` naar de postbus (`PASR_IMAP_USER`).
2. pg_cron roept elke 5 minuten `poll_inbox` aan (`pasr_mail_poll_kick`, job `pasr-mail-poll`, URL uit `pasr_admin_config.mail_url`, kop `x-pasr-cron` met het hook-geheim uit `pasr_secret`). Ook "Nu ophalen" in het beheer (`mail_poll`).
3. De mailbox wordt via IMAP gelezen; een mail wordt aan een ticket gekoppeld via het nummer in het onderwerp en via `In-Reply-To`/`References` (ook oudere berichten). Verwerkte mail krijgt het trefwoord `$PasrDone` (en gaat naar de map `Pasr-verwerkt` als die bestaat). Geen koppeling: een nieuw ticket (hoogstens 3 per afzender per uur).
4. Automatische mail (`Auto-Submitted`, `Precedence: bulk`, mailer-daemon) wordt genegeerd. Een ontvangstbevestiging gaat alleen uit met `PASR_MAIL_AUTOREPLY=1`.
5. Een medewerker kan ook rechtstreeks per mail antwoorden: afzenders in `PASR_MAIL_AGENTS` (en de eigen adressen) tellen alleen mee als de bovenste `Authentication-Results` van onze eigen server `dkim=pass` voor het domein van de afzender meldt. Het antwoord gaat dan gebrand naar de klant.
6. Bijlagen van klanten worden bewaard tot 20 MB per mail; de rest krijgt een regel "niet overgenomen".

## Afmelden

- Persoonlijke link: `https://pasr.nl/afmelden/?t=<token>&k=nieuws` (stateloos token: korte hash, doelgroepcode, mac) of één klik via `?stop=<token>` (RFC 8058).
- Bij BCC-groepen zonder persoonlijke code: `https://pasr.nl/afmelden/?k=nieuws&s=users|owners`; daar vult iemand zijn e-mailadres in (`pasr_mail_news_unsub_email`, met honeypot en rem).
- Afgemelden staan in `pasr_mail_optout`, zijn uit elke doelgroep en uit BCC-lijsten gehaald en krijgen geen nieuwsbrief of uitnodiging meer. Losse mails en ticketmail worden nooit geblokkeerd.

## Handtekening Team Pasr

Elke mail die via het beheer wordt verstuurd, krijgt standaard een handtekening: een afbeelding (JPG 1200x300, getoond op 600x150) onder de inhoud en boven de voet (afmeldregel en juridische links). Merk `pasr`: `https://pasr.nl/assets/handtekening-pasr.jpg`, alt "Team Pasr", linkt naar `https://pasr.nl/`. Merk `zakelijk`: `handtekening-pasr-zakelijk.jpg`, alt "Team Pasr Zakelijk", linkt naar `https://pasr.nl/zakelijk/`. De bestanden staan in `website/assets/` en gaan met de Website-workflow mee (sha256-manifest: nieuwe bestanden worden automatisch geüpload). De afbeelding is `width:100%;max-width:600px;height:auto` (past zich aan op mobiel) en heeft een eigen donker vlak, dus werkt in licht en donker. De platte tekst krijgt "Team Pasr" resp. "Team Pasr Zakelijk" plus de site-URL, vóór de afmeldregel.

- `renderMail({ …, signature })` (standaard `true`; `false` laat hem weg) geldt voor alle soorten (`reply`, `mail`, `news`, `invite`), dus ook voor systeemmails die `renderMail` gebruiken.
- De acties `compose`, `thread_reply`, `test`, `preview` en `campaign_send` nemen een veld `signature` (boolean, standaard `true`; alleen `false` zet hem uit). `preview` toont hem dus ook.
- Een campagne wordt in rondes verstuurd. Staat de handtekening uit, dan bewaart `campaign_send` dat als slotregel `<!--pasr:geen-handtekening-->` in de opgeslagen tekst van de campagne (geen extra databasekolom, dus geen migratie); `campaign.ts` haalt die regel er per mail weer af en de vlag komt nooit in een mail.
- Beheer-UI (web, PasrBeheer en LRbeheer): schakelaar "Handtekening Team Pasr / Team Pasr Zakelijk toevoegen" (standaard aan, naam volgt het merk) bij Nieuwe mail, Antwoord en Nieuwsbrief; de bevestiging toont de keuze en het voorbeeld ook de handtekening.

## Secrets (GitHub repository secrets, door Léon te zetten)

De workflow `backend.yml` zet ze als function-secrets. Ontbreekt iets, dan komt er een waarschuwing en geen fout.

| Secret | Betekenis |
|---|---|
| `PASR_SMTP_HOST`, `PASR_SMTP_PORT`, `PASR_SMTP_USER`, `PASR_SMTP_PASSWORD`, `PASR_SMTP_FROM` | verzenden (bestaan al) |
| `PASR_IMAP_HOST`, `PASR_IMAP_PORT` (standaard 993), `PASR_IMAP_USER`, `PASR_IMAP_PASSWORD` | de postbus waar antwoorden binnenkomen |
| `PASR_MAIL_FROM_PASR`, `PASR_MAIL_FROM_ZAKELIJK` | afzenders (standaard `support@pasr.nl`, `zakelijk@pasr.nl`) |
| `PASR_MAIL_AGENTS` | adressen die per mail op tickets mogen antwoorden (komma's) |
| `PASR_MAIL_AUTHSERV` (optioneel) | naam van onze ontvangende server in `Authentication-Results` |
| `PASR_MAIL_AUTOREPLY` (optioneel) | `1` = ontvangstbevestiging bij een nieuw ticket |

`PASR_TOKEN_SECRET` bestaat al (door de adminstap aangemaakt) en wordt hergebruikt voor de sleutel tussen `admin` en `mail`.

## Tests

`deno test --no-check --allow-env --allow-net=127.0.0.1 supabase/functions/mail/` (Markdown en XSS, IMAP tegen een nep-server, uitgaande mail, campagnes, inbox), `deno test --no-check supabase/functions/admin/mail_test.ts`, en `supabase/tests/beheer_mail_smoke.sql` in de CI (backend-integration).
