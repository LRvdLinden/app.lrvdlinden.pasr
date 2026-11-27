# CONTRACT Tickets + Klantenkaart met barcode (gedeeld door 3 agents — exact zo)

Ontwerp: /tmp/claude-0/-home-claude/2ef6343a-6e1e-57a7-8303-61ce398b7423/scratchpad/webcb/project/{TicketsA,KlantkaartA,OverzichtTK}.dc.html (screenshots/generator in .../scratchpad/dash/tk_gen.py). Bekijk ze.

Auth-stijl: zakelijke RPC's zoals bestaande pasr_business_* (p_business uuid, eigenaar of medewerker; medewerkers mogen scannen, alleen eigenaar mag aanmaken/wijzigen). Klant-RPC's op auth.uid(). Fouten als exception message (codes hieronder).

## Tickets (alleen gratis)
- pasr_business_event_save(p_business uuid, p_event jsonb) -> json {id}
  p_event: {id?, name, description, starts_at timestamptz, ends_at, doors_at|null, address, lat|null, lng|null, capacity int, max_per_person int (default 4), signup_until|null, waitlist bool, color|null (#RRGGBB, default zaakkleur), header_url|null, status 'draft'|'published'|'cancelled', ticket_types:[{id?, name, capacity|null}] (minstens 1, default "Toegang")}
- pasr_business_events(p_business) -> setof {id, name, starts_at, ends_at, doors_at, address, capacity, status, color, registered int, checked_in int, waitlist int, ticket_types json}
- pasr_business_event_registrations(p_business, p_event) -> setof {registration_id, ticket_id, first_name, last_name, email, birth_date date, ticket_type text, status 'registered'|'checked_in'|'waitlist'|'cancelled', created_at, checked_in_at}
- pasr_business_event_cancel(p_business, p_event, p_message text) -> void (mail + push naar alle aanmeldingen)
- pasr_business_ticket_scan(p_business, p_code text, p_event uuid|null) -> json {result:'valid'|'used'|'invalid'|'other_event'|'cancelled', first_name, last_name, ticket_type, event_id, event_name, checked_in_at, counts:{checked_in, registered, capacity}}  ('valid' zet meteen checked_in)
- pasr_event_public(p_event uuid) -> json {id, name, description, starts_at, ends_at, doors_at, address, lat, lng, color, header_url, business_name, business_logo, ticket_types:[{id,name,available}], spots_left, max_per_person, signup_open bool, waitlist bool, status}  (anon toegestaan, geen persoonsgegevens)
- pasr_event_register(p_event uuid, p_first_name text, p_last_name text, p_email text, p_birth_date date, p_ticket_type uuid, p_count int, p_hp text default null, p_fill_ms int default null [genegeerd]) -> json {status:'registered'|'waitlist', tickets:[{ticket_id, code}], add_link}  (anon of ingelogd; ingelogd => tickets direct in wallet van gebruiker; alle 4 persoonsvelden verplicht; fouten: 'event_full','signup_closed','too_many','invalid_input','event_cancelled')
- pasr_my_event_tickets() -> setof {ticket_id, code, event_id, event_name, starts_at, ends_at, doors_at, address, lat, lng, color, header_url, business_name, business_logo, holder_name, ticket_type, status, group_key}  (group_key = event_id; meerdere tickets zelfde event naast elkaar)
- pasr_event_ticket_claim(p_ticket uuid, p_code text) -> json {ticket_id}  (koppelt anoniem aangemaakt ticket aan ingelogde gebruiker; voor /add/t/<ticket>?c=<code>)
- QR-inhoud = alleen de willekeurige `code` (min. 20 tekens, base32). Geboortedatum NOOIT in QR/pass/push.
- Add-links: https://pasr.nl/add/e/<event_id> (aanmelden) en https://pasr.nl/add/t/<ticket_id>?c=<code> (ticket toevoegen).

## Klantenkaart met barcode (alleen via scannen in Pasr Zakelijk)
- pasr_business_member_card_save(p_business, p_card jsonb) -> json {id}
  p_card: {id?, name, color, logo|null, barcode_type 'qr'|'code128'|'ean13', prefix text (bv "KS-"; bij ean13 genegeerd), status 'draft'|'published'|'archived',
    goals:{membership bool, saving:{enabled bool, unit 'visits'|'points', target int, reward text}, fixed_discount:{enabled bool, percent numeric}, periods:[{id?, label, percent numeric, starts_on date, ends_on date, weekdays int[]|null (1=ma..7=zo), from_time time|null, to_time time|null}]}}
- pasr_business_member_cards(p_business) -> setof {id, name, color, logo, barcode_type, status, members int, goals json, discount_now json|null, next_discount json|null}
- pasr_business_member_card_scan(p_business, p_code text) -> json {result:'valid'|'invalid'|'other_business', card_id, card_name, member_name|null, number, discount_now:{percent,label,until}|null, next_discount:{percent,label,starts_at}|null, saving:{count,target,reward,can_redeem}|null}
- pasr_business_member_card_visit(p_business, p_code) -> json {saving:{count,target,reward,can_redeem}}  (registreert bezoek; bij unit 'points' param p_points int default 1 als 3e arg)
- pasr_business_member_card_redeem(p_business, p_code) -> json {saving}
- pasr_member_card_public(p_card) -> json {id,name,color,logo,business_name,goals_summary,discount_now,next_discount}  (anon)
- pasr_member_card_join(p_card uuid, p_share_name boolean) -> json {member_id, number, barcode_type}  (ingelogd; number = uniek per kaart, EAN-13 met geldige checksum bij ean13)
- pasr_my_member_cards() -> setof {member_id, card_id, name, color, logo, business_name, number, barcode_type, discount_now, next_discount, saving}
- pasr_member_card_leave(p_member uuid) -> void
- Add-link: https://pasr.nl/add/m/<card_id>
- Fouten: 'not_owner','card_not_found','already_member','invalid_code'.

## Push (type in payload, plus ids)
event_reminder {event_id} (dag ervoor), event_changed {event_id}, event_cancelled {event_id}, waitlist_promoted {event_id, ticket_id}, member_discount_started {card_id} (alleen als klant meldingen voor die kaart aan heeft; klant-toggle via pasr_member_card_notify(p_member uuid, p_on boolean)).

## Wallet
Apple: wallet-pass edge function: eventTicket voor tickets (groupingIdentifier = event_id, kleur/logo zaak/event, QR=code, naam houder), storeCard voor klantenkaart (barcode volgens type: QR / Code128 / EAN-13 niet ondersteund door Apple PassKit -> toon dan Code128 met hetzelfde nummer). Google Wallet: eventTicket en loyalty class/object in google-wallet function. Endpoints zoals bestaande pass-aanvraag; parameters kind 'event_ticket'|'member_card' en id.

## Versies (elk alleen de eigen app!)
- Agent backend/web/beheer: PasrBeheer BUILD+1, LRbeheer BUILD+1 (geen app-versies).
- Agent Zakelijk: Pasr Zakelijk iOS VERSION 1.0.5 + BUILD+1; Android versionName 1.0.5 + versionCode+1 (ook hardcoded in android-zakelijk.yml en asserts in pasr-app-pr-validation.yml) — APK moet via workflow naar android-builds/zakelijk/pasr-zakelijk.json met 1.0.5.
- Agent Pasr klant-app: Pasr iOS MARKETING_VERSION 1.0.6 + CURRENT_PROJECT_VERSION+1 (tools/make_project.py, script draaien, xcode-pasr.yml); Android versionName 1.0.6 + versionCode+1 (build.gradle.kts, CODE= en versie in android-pasr.yml, asserts) — APK moet naar android-builds/pasr/pasr.json met 1.0.6.

## Aanvulling backend (extra's; niets uit het contract hierboven is weggelaten of hernoemd)
Uitvoering: `supabase/20261127-tickets-klantenkaart.sql` (tests: `supabase/tests/tickets_klantenkaart_smoke.sql`).
- Ticketcode: 24 tekens base32 (`A-Z2-7`), begint nooit met `PZ`/`PC`. Scanner: PZ… = stempelkaart, PC… = kortingsbon,
  `^[A-Z2-7]{20,40}$` = eerst `pasr_business_ticket_scan`, anders/daarna `pasr_business_member_card_scan`.
- Kaartnummer klantenkaart = inhoud van de barcode: EAN-13 begint met `2` (eigen bereik) met geldig controlecijfer;
  anders voorvoegsel + 6 cijfers (`KS-000124`). Uniek per zaak; opzeggen en opnieuw lid = nieuw nummer.
- Extra velden: `pasr_business_events` ook `description, lat, lng, max_per_person, signup_until, waitlist_enabled,
  reminder, header_url, cancelled, signup_open, add_link, created_at`; `ticket_types[]` met `registered, waitlist`.
  `pasr_business_event_registrations` ook `waitlist_position`. `pasr_event_register` ook `registration_id, event_id`.
  `pasr_my_event_tickets` ook `description, event_status, cancel_message, checked_in_at, business_id`.
  `pasr_business_ticket_scan` ook `ticket_id, reason ('waitlist'|'draft')`, `counts.waitlist`.
  `pasr_event_ticket_claim` ook `ticket_ids` (koppelt alle tickets van dezelfde aanmelding), `event_id`.
  `pasr_business_member_cards` ook `prefix, add_link, visits_today, created_at`; `goals.periods[].id`.
  `pasr_my_member_cards` ook `notify, share_name, member_since, card_status, goals_summary, business_id`.
  `pasr_business_member_card_scan` ook `member_id, member_since, color, barcode_type, membership`;
  `discount_now` ook `kind ('fixed'|'period'), period_id, until_date`.
- Event-veld `reminder` (bool, standaard true): herinnering de dag ervoor vanaf 10:00 Nederlandse tijd.
- Extra RPC's: `pasr_business_event_registration_cancel(p_business, p_registration)` (eigenaar, plek naar de wachtlijst),
  `pasr_event_ticket_public(p_ticket, p_code)` en `pasr_event_ticket_cancel(p_ticket, p_code)` (anon, de code is het bewijs;
  voor pasr.nl/add/t/<ticket>?c=<code>[&afmelden=1]).
- Extra foutcodes: `event_not_found`, `not_signed_in`, `not_enough` (inwisselen), `barcode_type_locked`, `business_not_approved`.
- Push-payload: `{aps, kind: 'event'|'member_card', type, event_id?, ticket_id?, card_id?, member_id?}`; thread-id
  `event-<id>` / `member-card-<id>`; FCM-kanaal `tickets`.
- Wallet: Apple-serienummer = ticket_id / member_id; de pas werkt vanzelf bij (database seint `ET:<ticket>` / `MC:<lid>`).
  Google Wallet: `{action:"save", kind, id, key?, code?}`.
- Privacy: 30 dagen na het event (of na afgelasten) worden naam, e-mail en geboortedatum gewist.

## Anti-bot (20261127-antibot-forms.sql)

- Alleen honeypots, geen tijdmeting: wie snel is (wachtwoordmanager, automatisch aanvullen, direct op de knop) is geen
  bot en komt gewoon door.
- pasr.nl/add/e/…, het afmelden op /add/t/…&afmelden=1, pasr.nl/account (account maken, wachtwoord vergeten) en
  pasr.nl/zakelijk (inloggen, account maken, wachtwoord vergeten, vriendenactie-inloggen, "kaart in je browser") hebben
  in een `.hp-field`-blok (buiten beeld, `aria-hidden`, `tabindex=-1`) twee velden die een mens niet ziet:
  - tekstveld `hp_extra` (`autocomplete=off`, genegeerd door 1Password/LastPass/Bitwarden; bewust geen naam als
    `website`/`url`/`name` die automatisch aanvullen zou herkennen);
  - vinkje `nieuwsbrief_extra` met de tekst "Stuur mij aanbiedingen" (automatisch aanvullen zet nooit een vinkje).
  Tekst ingevuld of vinkje aan = bot: de pagina toont dat het gelukt is en stuurt niets.
- `pasr_event_register` en `pasr_event_ticket_cancel(p_ticket, p_code, p_hp default null, p_fill_ms default null)`:
  `p_hp` niet leeg (de tekst, of `'x'` voor het vinkje) = stil niets doen, met een gewoon antwoord (`tickets: []` /
  `cancelled: 0`); de poging komt in `pasr_form_bot_log` (alleen formulier, reden `honeypot`, tijd). `p_fill_ms` wordt
  genegeerd en blijft alleen in de signatuur zodat oudere pagina's in een cache niet breken; de website stuurt hem niet
  meer. De apps sturen geen van beide mee en blijven werken.
- Account maken (Auth-hook `pasr_before_user_created`): alleen `user_metadata.hp` telt; `fill_ms` (oudere apps sturen
  hem nog) wordt genegeerd en niet bewaard. Reden `too_fast` komt alleen nog in oude regels voor.
- Rem: aanmelden 30 per internetadres per dag (bestond al) en nu ook 10 per e-mailadres per dag (anoniem; gehasht in
  `pasr_form_rate`); afmelden 30 per internetadres per dag. Boven de rem: `rate_limited`.
- Beheer (service role): `pasr_form_bot_stats()` geeft de bot-pogingen per formulier en reden (24 uur, 7 dagen).

