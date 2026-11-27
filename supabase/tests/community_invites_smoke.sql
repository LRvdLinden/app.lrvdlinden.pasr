-- Gezamenlijke acties op uitnodiging (20261127-community-invites.sql), met verzonnen zaken en accounts.
-- Draait na loyalty_smoke.sql in de PR-check "backend-integration". Alleen testomgeving.

-- Wat de echte database wel heeft en de basisfixture niet: e-mail, medewerkers en apparaten.
alter table auth.users add column if not exists email text;
alter table public.pasr_businesses add column if not exists email text not null default '';
create table if not exists public.pasr_business_staff (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.pasr_businesses(id) on delete cascade,
 user_id uuid references auth.users(id), role text not null default 'staff', revoked_at timestamptz
);
create table if not exists public.pasr_devices (
 device_id text primary key, app text not null, platform text not null, user_id uuid,
 push_token text, push_provider text, push_sandbox boolean not null default false
);

insert into auth.users(id,email) values
('44444444-4444-4444-8444-444444444444','eigenaar@zaak-c.example'),
('55555555-5555-4555-8555-555555555555','eigenaar@zaak-d.example')
on conflict (id) do update set email = excluded.email;
update public.pasr_businesses set city = 'Apeldoorn' where id in ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
update public.pasr_businesses set email = 'info@koffiehoek.example' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
insert into public.pasr_businesses(id,owner,name,city) values
('cccccccc-0000-4ccc-8ccc-cccccccccccc','44444444-4444-4444-8444-444444444444','Bloemenhuis Roos','Apeldoorn'),
('dddddddd-0000-4ddd-8ddd-dddddddddddd','55555555-5555-4555-8555-555555555555','Fietsenmaker Wiel','Deventer');
insert into public.pasr_devices(device_id,app,platform,user_id,push_token,push_provider) values
('device-zaak-b-ios','zakelijk','ios','22222222-2222-4222-8222-222222222222',repeat('ab',32),'apns'),
('device-zaak-b-and','zakelijk','android','22222222-2222-4222-8222-222222222222',repeat('x',40),'fcm'),
('device-klant-b-1','pasr','ios','22222222-2222-4222-8222-222222222222',repeat('cd',32),'apns');

do $$
declare
 a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';   -- organisator, Apeldoorn
 b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';   -- Apeldoorn
 c uuid := 'cccccccc-0000-4ccc-8ccc-cccccccccccc';   -- Apeldoorn
 d uuid := 'dddddddd-0000-4ddd-8ddd-dddddddddddd';   -- Deventer
 ua text := '11111111-1111-4111-8111-111111111111';
 ub text := '22222222-2222-4222-8222-222222222222';
 uc text := '44444444-4444-4444-8444-444444444444';
 ud text := '55555555-5555-4555-8555-555555555555';
 klant text := '33333333-3333-4333-8333-333333333333';
 camp uuid; inv jsonb; link jsonb; preview json; rows jsonb; n int; s text; due jsonb; tok text;
begin
 delete from public.pasr_business_community_outbox;

 -- aanmaken met de nieuwe parameters; oude aanroep (5 parameters) werkt nog
 perform set_config('app.user_id',ua,true);
 camp := (public.pasr_business_community_create(a,'Binnenstadroute','Gratis taartje',2,30,false,3)->>'id')::uuid;
 rows := public.pasr_business_community_list(a);
 if rows->0->>'role' <> 'owner' or rows->0->>'state' <> 'waiting' or (rows->0->>'accepted_count')::int <> 1
    or (rows->0->>'min_participants')::int <> 3 or (rows->0->>'open_same_city')::boolean is not false
 then raise exception 'List after create wrong: %',rows; end if;
 if public.pasr_business_community_state(camp) <> 'waiting' then raise exception 'state'; end if;

 -- zoeken: geen eigen zaak, met status
 select count(*) into n from public.pasr_business_community_search(a,camp,'');
 if n <> 3 then raise exception 'Search should give 3 other businesses, got %',n; end if;
 if exists (select 1 from public.pasr_business_community_search(a,camp,'') x where x.business_id = a) then raise exception 'Own business in search'; end if;
 select count(*) into n from public.pasr_business_community_search(a,camp,'bloem');
 if n <> 1 then raise exception 'Search by name failed'; end if;

 -- uitnodigen op naam; dubbel geeft dezelfde uitnodiging
 inv := public.pasr_business_community_invite(a,camp,b)::jsonb;
 if inv->>'status' <> 'invited' then raise exception 'invite %',inv; end if;
 if (public.pasr_business_community_invite(a,camp,b)::jsonb)->>'invite_id' <> inv->>'invite_id' then raise exception 'Duplicate invite'; end if;
 if (select x.invite_status from public.pasr_business_community_search(a,camp,'bakkerij') x) <> 'invited' then raise exception 'Search status'; end if;
 select count(*) into n from public.pasr_business_community_outbox where kind = 'invite' and business_id = b;
 if n <> 1 then raise exception 'Invite not in outbox'; end if;

 -- alleen de organisator nodigt uit
 perform set_config('app.user_id',ub,true);
 begin
  perform public.pasr_business_community_invite(b,camp,c);
  raise exception 'Non-organizer could invite';
 exception when sqlstate '42501' then
  get stacked diagnostics s = message_text;
  if s <> 'not_owner' then raise exception 'Wrong error %',s; end if;
 end;
 -- B ziet de uitnodiging en weigert
 select count(*) into n from public.pasr_business_community_my_invites(b);
 if n <> 1 then raise exception 'my_invites %',n; end if;
 if (select x.initiator_name from public.pasr_business_community_my_invites(b) x) <> 'De Koffiehoek' then raise exception 'initiator'; end if;
 perform public.pasr_business_community_respond(b,(inv->>'invite_id')::uuid,false);
 begin
  perform public.pasr_business_community_respond(b,(inv->>'invite_id')::uuid,true);
  raise exception 'Answered twice';
 exception when sqlstate 'P0002' then null;
 end;
 if not exists (select 1 from public.pasr_business_community_outbox where kind = 'declined' and business_id = a) then raise exception 'declined not queued'; end if;
 -- zonder uitnodiging meedoen kan niet (actie niet open)
 begin
  perform public.pasr_business_community_join(b,camp);
  raise exception 'Joined invite-only campaign';
 exception when sqlstate '42501' then
  get stacked diagnostics s = message_text;
  if s <> 'invite_required' then raise exception 'Wrong error %',s; end if;
 end;
 -- deelnemer kan geen uitnodigingen zien
 begin
  perform * from public.pasr_business_community_invites(b,camp);
  raise exception 'Non participant saw invites';
 exception when sqlstate '42501' then null;
 end;

 -- opnieuw uitnodigen na weigeren mag; nu accepteren
 perform set_config('app.user_id',ua,true);
 inv := public.pasr_business_community_invite(a,camp,b)::jsonb;
 perform set_config('app.user_id',ub,true);
 perform public.pasr_business_community_respond(b,(inv->>'invite_id')::uuid,true);
 rows := public.pasr_business_community_list(b);
 if rows->0->>'role' <> 'participant' or (rows->0->>'accepted_count')::int <> 2 or rows->0->>'state' <> 'waiting'
 then raise exception 'Participant list %',rows; end if;
 -- deelnemer ziet alleen geaccepteerde (organisator + zichzelf), zonder e-mailadressen
 select count(*) into n from public.pasr_business_community_invites(b,camp);
 if n <> 2 then raise exception 'Participant sees % invites',n; end if;
 begin
  perform public.pasr_business_community_invite(a,camp,c);
  raise exception 'Participant invited for organizer';
 exception when sqlstate '42501' then null;
 end;

 -- link/e-mailuitnodiging voor een zaak die nog niet in Pasr zit (C maakt daarna een zaak aan)
 perform set_config('app.user_id',ua,true);
 link := public.pasr_business_community_invite_email(a,camp,'Nieuw@Winkel.example')::jsonb;
 tok := link->>'token';
 if tok !~ '^[0-9a-f]{64}$' or link->>'link' <> 'https://pasr.nl/zakelijk/uitnodiging/?t=' || tok then raise exception 'link %',link; end if;
 if exists (select 1 from public.pasr_business_community_invites where token_hash = tok) then raise exception 'Token stored in plain text'; end if;
 if not exists (select 1 from public.pasr_business_community_outbox where kind = 'invite_email' and email = 'nieuw@winkel.example' and secret = tok)
 then raise exception 'invite_email not queued'; end if;
 -- zonder e-mail: alleen link, geen mail
 select count(*) into n from public.pasr_business_community_outbox where kind = 'invite_email';
 perform public.pasr_business_community_invite_email(a,camp,null);
 if (select count(*) from public.pasr_business_community_outbox where kind = 'invite_email') <> n then raise exception 'Link-only invite mailed'; end if;
 select count(*) into n from public.pasr_business_community_invites(a,camp);
 if n <> 5 then raise exception 'Organizer should see 5 invites (incl. declined), got %',n; end if;

 -- openbare preview (anon): alleen de afgesproken velden
 perform set_config('app.user_id','',true);
 preview := public.pasr_business_community_invite_preview(tok);
 if preview->>'status' <> 'invited' or preview->>'title' <> 'Binnenstadroute' or preview->>'initiator_name' <> 'De Koffiehoek'
    or json_array_length(preview->'participant_names') <> 2 or preview::text like '%@%'
 then raise exception 'preview %',preview; end if;
 if public.pasr_business_community_invite_preview('onzin')->>'status' <> 'not_found' then raise exception 'preview bad token'; end if;

 -- C accepteert met de link; daarmee is het minimum (3) bereikt
 perform set_config('app.user_id',uc,true);
 if (public.pasr_business_community_accept_token(c,tok)::jsonb)->>'campaign_id' <> camp::text then raise exception 'accept_token'; end if;
 begin
  perform public.pasr_business_community_accept_token(c,tok);
  raise exception 'Token used twice';
 exception when sqlstate '23505' then
  get stacked diagnostics s = message_text;
  if s <> 'already_participant' then raise exception 'Wrong error %',s; end if;
 end;
 if public.pasr_business_community_state(camp) <> 'active' then raise exception 'Should be active'; end if;
 select count(*) into n from public.pasr_business_community_outbox where kind = 'active' and campaign_id = camp;
 if n <> 3 then raise exception 'active should be queued for 3 businesses, got %',n; end if;
 if public.pasr_business_community_invite_preview(tok)->>'status' <> 'used' then raise exception 'preview used'; end if;

 -- verlopen link
 perform set_config('app.user_id',ua,true);
 link := public.pasr_business_community_invite_email(a,camp,null)::jsonb;
 update public.pasr_business_community_invites set expires_at = now() - interval '1 minute'
  where token_hash = public.pasr_business_community_hash(link->>'token');
 perform set_config('app.user_id',ud,true);
 begin
  perform public.pasr_business_community_accept_token(d,link->>'token');
  raise exception 'Expired token accepted';
 exception when sqlstate '22023' then
  get stacked diagnostics s = message_text;
  if s <> 'invite_expired' then raise exception 'Wrong error %',s; end if;
 end;

 -- intrekken en verwijderen
 perform set_config('app.user_id',ua,true);
 inv := public.pasr_business_community_invite(a,camp,d)::jsonb;
 perform public.pasr_business_community_revoke(a,(inv->>'invite_id')::uuid);
 perform set_config('app.user_id',ud,true);
 select count(*) into n from public.pasr_business_community_my_invites(d);
 if n <> 0 then raise exception 'Revoked invite still visible'; end if;
 perform set_config('app.user_id',ua,true);
 begin
  perform public.pasr_business_community_revoke(a,(inv->>'invite_id')::uuid);
  raise exception 'Revoked twice';
 exception when sqlstate 'P0002' then
  get stacked diagnostics s = message_text;
  if s <> 'invite_not_found' then raise exception 'Wrong error %',s; end if;
 end;
 perform public.pasr_business_community_remove(a,camp,c);
 if public.pasr_business_community_state(camp) <> 'waiting' then raise exception 'Should be waiting after removal'; end if;
 if not exists (select 1 from public.pasr_business_community_outbox where kind = 'removed' and business_id = c) then raise exception 'removed not queued'; end if;
 begin
  perform public.pasr_business_community_remove(a,camp,c);
  raise exception 'Removed twice';
 exception when sqlstate 'P0002' then null;
 end;
 begin
  perform public.pasr_business_community_invite(a,camp,b);
  raise exception 'Invited a participant';
 exception when sqlstate '23505' then
  get stacked diagnostics s = message_text;
  if s <> 'already_participant' then raise exception 'Wrong error %',s; end if;
 end;

 -- open voor zaken in dezelfde plaats: C (Apeldoorn) mag meedoen, D (Deventer) niet
 perform public.pasr_business_community_settings(a,camp,true,null);
 perform set_config('app.user_id',uc,true);
 if jsonb_array_length(public.pasr_business_community_open(c)) <> 1 then raise exception 'open list'; end if;
 perform public.pasr_business_community_join(c,camp);
 if public.pasr_business_community_state(camp) <> 'active' then raise exception 'active again'; end if;
 -- "gestart" maar één keer
 select count(*) into n from public.pasr_business_community_outbox where kind = 'active' and campaign_id = camp;
 if n <> 3 then raise exception 'active queued twice (%)',n; end if;
 perform set_config('app.user_id',ud,true);
 begin
  perform public.pasr_business_community_join(d,camp);
  raise exception 'Other city joined';
 exception when sqlstate '42501' then
  get stacked diagnostics s = message_text;
  if s <> 'invite_required' then raise exception 'Wrong error %',s; end if;
 end;

 -- de klant: alleen een actieve actie, alleen deelnemende zaken
 perform set_config('app.user_id',klant,true);
 rows := public.pasr_business_community_progress();
 if not exists (select 1 from jsonb_array_elements(rows) x where x->>'id' = camp::text
                and jsonb_array_length(x->'businesses') = 3) then raise exception 'Customer progress %',rows; end if;
 begin
  perform * from public.pasr_business_community_my_invites(a);
  raise exception 'Customer saw invites';
 exception when sqlstate '42501' then null;
 end;

 -- outbox voor de functies (service role): mail met ontvanger en link, push met de apparaten van Pasr Zakelijk
 due := public.pasr_business_community_mail_due(200);
 if not exists (select 1 from jsonb_array_elements(due) x where x->>'kind' = 'invite_email'
                and x->>'to' = 'nieuw@winkel.example' and x->>'link' like 'https://pasr.nl/zakelijk/uitnodiging/?t=%')
 then raise exception 'mail_due invite_email %',due; end if;
 if not exists (select 1 from jsonb_array_elements(due) x where x->>'kind' = 'declined' and x->>'to' = 'info@koffiehoek.example')
 then raise exception 'mail_due business mail %',due; end if;
 if not exists (select 1 from jsonb_array_elements(due) x where x->>'kind' = 'removed' and x->>'to' = 'eigenaar@zaak-c.example')
 then raise exception 'mail_due owner account mail %',due; end if;
 if jsonb_array_length(public.pasr_business_community_mail_due(200)) <> 0 then raise exception 'Claimed mail offered twice'; end if;
 perform public.pasr_business_community_mail_sent(array(select (x->>'id')::bigint from jsonb_array_elements(due) x));
 if exists (select 1 from public.pasr_business_community_outbox where secret is not null) then raise exception 'Token kept after mailing'; end if;
 due := public.pasr_business_community_push_due(200);
 if exists (select 1 from jsonb_array_elements(due) x where x->>'business_id' is null) then raise exception 'push without business'; end if;
 if not exists (select 1 from jsonb_array_elements(due) x where x->>'kind' = 'invite' and x->>'business_id' = b::text
                and jsonb_array_length(x->'devices') = 2) then raise exception 'push_due devices %',due; end if;
 perform public.pasr_business_community_push_sent(array(select (x->>'id')::bigint from jsonb_array_elements(due) x));
 if jsonb_array_length(public.pasr_business_community_push_due(200)) <> 0 then raise exception 'push offered after sent'; end if;

 -- beheer
 rows := public.pasr_admin_community_detail(camp);
 if jsonb_array_length(rows->'participants') <> 3 or rows->'campaign'->>'state' <> 'active' then raise exception 'admin detail %',rows; end if;
 perform public.pasr_admin_community_remove(camp,b);
 if public.pasr_business_community_accepted(camp) <> 2 then raise exception 'admin remove'; end if;
 perform set_config('app.user_id',ua,true);
 inv := public.pasr_business_community_invite(a,camp,d)::jsonb;
 perform public.pasr_admin_community_revoke((inv->>'invite_id')::uuid);
 if (select status from public.pasr_business_community_invites where id = (inv->>'invite_id')::uuid) <> 'revoked' then raise exception 'admin revoke'; end if;
 begin
  perform public.pasr_admin_community_remove(camp,a);
  raise exception 'Admin removed organizer';
 exception when sqlstate '22023' then null;
 end;
 raise notice 'PASR COMMUNITY INVITES TEST PASSED';
end $$;
