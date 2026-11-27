# Gezamenlijke acties op uitnodiging

Contract tussen de backend (`supabase/20261127-community-invites.sql`) en de apps (Pasr Zakelijk iOS en Android,
Pasr iOS en Android, het dashboard op pasr.nl/zakelijk en het beheer). Namen, parameters en velden hieronder zijn vast:
er mag iets bij komen, niets mag weg of een andere naam krijgen.

Sinds 27-11-2026 doet een zaak alleen nog mee aan een gezamenlijke actie als de organisator haar uitnodigt (op naam of
plaats, of met een e-mail, link of QR-code), of als de organisator de actie open zet voor zaken in dezelfde plaats.
Een actie start pas als genoeg zaken meedoen (`min_participants`, de organisator telt mee). Tot dan ziet de klant niets
en kan er niets worden uitgegeven.

## Aanroepen

Alle functies zijn `public.` RPC's (PostgREST: `POST /rest/v1/rpc/<naam>` met de JWT van de ingelogde gebruiker), net als
de bestaande `pasr_business_community_*`. `p_business` is de zaak namens wie je werkt; de database controleert met
`pasr_business_role(p_business)` of je eigenaar of medewerker bent.

- **Lezen** (lijst, uitnodigingen bekijken, mijn uitnodigingen): eigenaar of medewerker van `p_business`.
- **Wijzigen** (aanmaken, uitnodigen, intrekken, verwijderen, reageren, link accepteren, meedoen): eigenaar (of
  medewerker met eigenaarsrol) van een goedgekeurde zaak. Uitnodigen, intrekken en verwijderen alleen als `p_business`
  de organisator van de actie is.

## Velden van een campagne

| Kolom | Type | Standaard | Betekenis |
| --- | --- | --- | --- |
| `invite_only` | boolean | `true` | Alleen op uitnodiging (altijd het omgekeerde van `open_same_city`) |
| `open_same_city` | boolean | `false` | Zaken in dezelfde plaats als de organisator mogen zonder uitnodiging meedoen |
| `min_participants` | int (2–30) | `2` | Zoveel zaken moeten meedoen voordat de actie start (organisator telt mee) |
| `activated_at` | timestamptz | leeg | Extra: wanneer het minimum voor het eerst werd bereikt (melding "gestart" gaat één keer) |

`state` (berekend): `cancelled` (gestopt) › `ended` (verlopen) › `waiting` (minder dan `min_participants` geaccepteerd)
› `active`.

## Functies

| Functie | Geeft | Notities |
| --- | --- | --- |
| `pasr_business_community_create(p_business, p_name, p_reward, p_required, p_days default 60, p_open_same_city boolean default false, p_min_participants int default 2)` | jsonb `{id, ok, state, min_participants, open_same_city}` | Oude aanroep met 5 parameters werkt nog. Organisator doet meteen mee (`accepted`, organisator). |
| `pasr_business_community_list(p_business)` | jsonb-lijst | Acties waaraan de zaak meedoet (ook als organisator), plus gestopte of verlopen acties van de laatste 30 dagen. Per rij de bestaande velden (`id, name, reward, required, starts_at, ends_at, lead_business, lead_city, is_lead, participants, participant_names, joined, claims_here, can_manage`) en nieuw: `role` (`owner` = organisator, `participant`), `open_same_city`, `min_participants`, `accepted_count`, `state`. Extra: `invite_only`, `pending_invites` (organisator), `cancelled_at`, `activated_at`. |
| `pasr_business_community_search(p_business uuid, p_campaign uuid, p_query text)` | setof `(business_id uuid, name text, city text, logo_url text, invite_status text null)` | Goedgekeurde zaken met "Vindbaar in Pasr" aan, zoekt in naam en plaats, max 25, zonder eigen zaak. Alleen organisator. `logo_url` is een `data:`-URL van het logo van de eerste kaart (alleen kleine logo's, anders `null`). `invite_status` is de laatste status voor deze actie of `null`. |
| `pasr_business_community_invite(p_business uuid, p_campaign uuid, p_target uuid)` | json `{invite_id, status}` | Alleen organisator. Al uitgenodigd: dezelfde uitnodiging terug. Na weigeren of intrekken mag opnieuw. Max 50 uitnodigingen per actie per dag. |
| `pasr_business_community_invite_email(p_business uuid, p_campaign uuid, p_email text)` | json `{invite_id, token, link}` | `link` = `https://pasr.nl/zakelijk/uitnodiging/?t=<token>` (token: 64 hex-tekens). `p_email` null: alleen link/QR, geen mail. Verloopt na 14 dagen, werkt voor één zaak. De database bewaart alleen een hash van het token. |
| `pasr_business_community_invites(p_business uuid, p_campaign uuid)` | setof `(invite_id uuid, business_id uuid null, name text, city text, email text null, status text, created_at timestamptz)` + extra `expires_at timestamptz, organizer boolean` | `status`: `invited`, `accepted`, `declined`, `revoked`. Organisator ziet alles (ook e-mailadressen), een deelnemer alleen `accepted` en nooit e-mailadressen. De organisator zelf staat erin als `accepted` met `organizer = true`. Bij een link zonder zaak is `name` het e-mailadres of "Uitnodigingslink". |
| `pasr_business_community_revoke(p_business uuid, p_invite uuid)` | void | Alleen organisator, alleen een openstaande (`invited`) uitnodiging. |
| `pasr_business_community_remove(p_business uuid, p_campaign uuid, p_target uuid)` | void | Deelnemer eruit (niet de organisator). Alleen organisator. Kan de actie terugzetten naar `waiting`. |
| `pasr_business_community_my_invites(p_business uuid)` | setof `(invite_id uuid, campaign_id uuid, title text, reward text, starts_at timestamptz, ends_at timestamptz, initiator_name text, participant_names text[])` + extra `initiator_city text, required int, min_participants int, accepted_count int, created_at timestamptz` | Openstaande uitnodigingen voor deze zaak (lopende acties). |
| `pasr_business_community_respond(p_business uuid, p_invite uuid, p_accept boolean)` | void | Accepteren of weigeren. |
| `pasr_business_community_accept_token(p_business uuid, p_token text)` | json `{campaign_id}` | Koppelt een e-mail/link-uitnodiging aan deze zaak en accepteert. Een eerdere uitnodiging op naam voor deze zaak vervalt. |
| `pasr_business_community_invite_preview(p_token text)` | json | **Openbaar (anon).** `{status, campaign_id, title, reward, starts_at, ends_at, initiator_name, participant_names}`; `status`: `invited`, `used`, `revoked`, `expired`, `not_found` (dan alleen `status`). Nooit e-mailadressen. |
| `pasr_business_community_join(p_business, p_campaign)` | jsonb `{ok, joined, campaign_id}` | Alleen als `open_same_city` en dezelfde plaats als de organisator, anders `invite_required`. Staat er een uitnodiging klaar, dan telt dit als accepteren. |
| `pasr_business_community_leave(p_business, p_campaign)` | jsonb | Ongewijzigd; de uitnodiging wordt `declined`. |
| `pasr_business_community_settings(p_business, p_campaign, p_open_same_city boolean default null, p_min_participants int default null)` | jsonb `{ok, open_same_city, invite_only, min_participants, accepted_count, state}` | **Extra.** Instellingen van een lopende actie wijzigen (organisator); `null` = laten staan. |
| `pasr_business_community_open(p_business)` | jsonb-lijst | **Extra.** Open acties in de plaats van deze zaak waaraan ze nog niet meedoet (meedoen met `join`). |

Klant en kassa: `pasr_business_community_progress()`, `pasr_business_community_member()` en
`pasr_business_community_claim()` houden hun vorm, maar tellen alleen nog acties met `state = active` en alleen zaken
die meedoen. De klant ziet in `businesses` alleen deelnemende zaken. `claim` op een wachtende actie geeft een fout met
hint `waiting`.

## Foutcodes

De exception message is precies de code (PostgREST: `message`; ook in `hint`):

| Code | SQLSTATE | Wanneer |
| --- | --- | --- |
| `invite_required` | 42501 | `join` zonder uitnodiging bij een actie die niet open is voor jouw plaats |
| `not_owner` | 42501 | Geen eigenaar van `p_business`, zaak niet goedgekeurd, of niet de organisator van de actie |
| `already_participant` | 23505 | Zaak doet al mee (uitnodigen, link accepteren) |
| `invite_not_found` | P0002 | Uitnodiging of deelnemer bestaat niet (meer), al beantwoord of ingetrokken, of de actie loopt niet meer |
| `invite_expired` | 22023 | Link ouder dan 14 dagen, of de actie is gestopt of verlopen |

Andere fouten (validatie, limieten) hebben een Nederlandse zin als message, zoals de bestaande functies.

## Meldingen

Elke gebeurtenis komt in `pasr_business_community_outbox`. Daaruit:

- **Mail** (functie `community-mail`, Pasr-huisstijl uit `supabase/templates/build.py`): (a) uitnodiging voor een
  bestaande zaak, (b) uitnodiging per e-mail met de link, (c) aan de organisator: geaccepteerd of geweigerd, (d) aan
  alle deelnemers: actie is gestart, (e) deelnemer verwijderd of uitnodiging ingetrokken. Ontvanger van een zaak: het
  e-mailadres van de zaak, anders dat van het account van de eigenaar.
- **Push** naar de apparaten van Pasr Zakelijk (`pasr_devices`, app `zakelijk`, APNs en FCM) van de eigenaar en
  medewerkers met eigenaarsrol; bij `community_active` ook gewone medewerkers. Payload:

```json
{ "aps": { "alert": { "title": "…", "body": "…" }, "sound": "default", "thread-id": "community" },
  "kind": "community", "type": "community_invite", "campaign": "<uuid>" }
```

`type`: `community_invite` (uitgenodigd), `community_invite_answered` (aan de organisator: geaccepteerd of geweigerd),
`community_active` (minimum bereikt), `community_removed` (verwijderd of uitnodiging ingetrokken). Op Android komen
`type` en `campaign` als data-velden mee (FCM data-only, kanaal `zakelijk`).

## Website

`https://pasr.nl/zakelijk/uitnodiging/?t=<token>` toont de uitnodiging (via `pasr_business_community_invite_preview`),
met inloggen of aanmelden in het dashboard en daarna accepteren (`pasr_business_community_accept_token`). Het token blijft
in de sessie bewaard, zodat het na inloggen of aanmelden verder gaat. De oude medewerkerslink
`/zakelijk/uitnodiging/#<code>` werkt zoals voorheen.

## Beheer

Functie `admin`: `community_detail {id}`, `community_revoke {invite_id}`, `community_remove {campaign_id, business_id}`
(SQL: `pasr_admin_community_detail`, `pasr_admin_community_revoke`, `pasr_admin_community_remove`). In beheer.pasr.nl,
PasrBeheer en LRbeheer bij de zaak, onder Gezamenlijke acties.
