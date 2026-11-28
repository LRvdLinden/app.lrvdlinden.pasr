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
- Bijlagen: `{name, type, data_b64}`, hoogstens 10 stuks en 10 MB per mail. Het verzoek mag tot 20 MB (alleen met geldig token).
- `body_md` is Markdown (geen HTML): koppen, vet, cursief, lijsten, citaten, code, `[[Knop|https://…]]`, links alleen `https:` of `mailto:`. `{{voornaam}}` wordt ingevuld; `{{email}}` is niet toegestaan.
- Merken: `pasr` (iris `#6A5CFF`) en `zakelijk` (mint `#2ED3A6`, eigen kop en icoon, "Pasr voor ondernemers"). Donker met lichte variant via `prefers-color-scheme`.

Campagnes: doelgroep `users` (alle accounts in `auth.users` zonder afmelding) of `owners` (eigenaren van een zaak). `request_id` (uuid) maakt een verzoek herhaalbaar. Elke ontvanger krijgt een eigen mail met voornaam, persoonlijke afmeldlink en `List-Unsubscribe` plus `List-Unsubscribe-Post` (één klik). Een ronde stopt na ongeveer 90 seconden; pg_cron gaat verder (`pasr_mail_campaign_due`) en wie al een mail kreeg staat als korte hash in `pasr_mail_campaign_sent`.

Foutcodes: `bad_address`, `no_recipient`, `too_many`, `too_large` (413), `bad_attachment`, `bad_subject`, `bad_body`, `bad_brand`, `bad_status`, `bad_priority`, `bad_number`, `bad_audience`, `bad_request_id`, `rate_limited` (429), `not_found` (404), `smtp_not_configured` (503), `mail_unreachable` (502 vanuit admin).

## Antwoorden komen terug

1. Elke uitgaande ticketmail heeft `[#1001]` in het onderwerp, een `Message-ID` van de vorm `<pasr-ticket-1001.xxxx@pasr.nl>`, de kop `X-Pasr-Ticket` en een `Reply-To` naar de postbus (`PASR_IMAP_USER`).
2. pg_cron roept elke 5 minuten `poll_inbox` aan (`pasr_mail_poll_kick`, job `pasr-mail-poll`, URL uit `pasr_admin_config.mail_url`, kop `x-pasr-cron` met het hook-geheim uit `pasr_secret`). Ook "Nu ophalen" in het beheer (`mail_poll`).
3. De mailbox wordt via IMAP gelezen; een mail wordt aan een ticket gekoppeld via het nummer in het onderwerp en via `In-Reply-To`/`References` (ook oudere berichten). Verwerkte mail krijgt het trefwoord `$PasrDone` (en gaat naar de map `Pasr-verwerkt` als die bestaat). Geen koppeling: een nieuw ticket (hoogstens 3 per afzender per uur).
4. Automatische mail (`Auto-Submitted`, `Precedence: bulk`, mailer-daemon) wordt genegeerd. Een ontvangstbevestiging gaat alleen uit met `PASR_MAIL_AUTOREPLY=1`.
5. Een medewerker kan ook rechtstreeks per mail antwoorden: afzenders in `PASR_MAIL_AGENTS` (en de eigen adressen) tellen alleen mee als de bovenste `Authentication-Results` van onze eigen server `dkim=pass` voor het domein van de afzender meldt. Het antwoord gaat dan gebrand naar de klant.
6. Bijlagen van klanten worden bewaard tot 10 MB per mail; de rest krijgt een regel "niet overgenomen".

## Afmelden

- Persoonlijke link: `https://pasr.nl/afmelden/?t=<token>&k=nieuws` (stateloos token: korte hash, doelgroepcode, mac) of één klik via `?stop=<token>` (RFC 8058).
- Bij BCC-groepen zonder persoonlijke code: `https://pasr.nl/afmelden/?k=nieuws&s=users|owners`; daar vult iemand zijn e-mailadres in (`pasr_mail_news_unsub_email`, met honeypot en rem).
- Afgemelden staan in `pasr_mail_optout`, zijn uit elke doelgroep en uit BCC-lijsten gehaald en krijgen geen nieuwsbrief of uitnodiging meer. Losse mails en ticketmail worden nooit geblokkeerd.

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
