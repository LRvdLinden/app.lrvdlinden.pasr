-- Tickets en klantenkaart met barcode (20261127-tickets-klantenkaart.sql), met verzonnen zaken en accounts.
-- Draait na community_invites_smoke.sql in de PR-check "backend-integration". Alleen testomgeving.

-- Wat de echte database wel heeft en de basisfixture niet (de community-test zette e-mail, medewerkers en apparaten al).
alter table auth.users add column if not exists raw_user_meta_data jsonb;
create table if not exists public.pasr_user_push (
 device_id text primary key, user_id uuid not null, token text not null, sandbox boolean not null default false
);
update auth.users set raw_user_meta_data = '{"first_name":"Anna","last_name":"de Vries"}'
 where id = '33333333-3333-4333-8333-333333333333';
insert into public.pasr_user_push(device_id,user_id,token) values ('klant-c-iphone','33333333-3333-4333-8333-333333333333',repeat('ef',32))
 on conflict do nothing;
insert into public.pasr_devices(device_id,app,platform,user_id,push_token,push_provider) values
('klant-c-android','pasr','android','33333333-3333-4333-8333-333333333333',repeat('y',40),'fcm')
on conflict do nothing;

-- Fout verwacht: de exception message moet precies de code zijn.
create or replace function pg_temp.expect(p_sql text, p_code text) returns void language plpgsql as $$
declare m text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics m = message_text;
    if m <> p_code then raise exception 'Expected % but got "%" for: %', p_code, m, p_sql; end if;
    return;
  end;
  raise exception 'Expected % but call succeeded: %', p_code, p_sql;
end $$;

do $$
declare
 a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';   -- De Koffiehoek (eigenaar ua)
 b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';   -- De Bakkerij (eigenaar ub)
 ua text := '11111111-1111-4111-8111-111111111111';
 ub text := '22222222-2222-4222-8222-222222222222';
 klant text := '33333333-3333-4333-8333-333333333333';
 d0 date := (now() at time zone 'Europe/Amsterdam')::date;
 ev uuid; ev2 uuid; ev3 uuid; t_toegang uuid; t_kind uuid; r1 json; r2 json; r3 json; r4 json; x json; j jsonb; n int; s text;
 pub json; code1 text; tid1 uuid;
begin
 delete from public.pasr_tk_outbox;
 perform set_config('app.user_id',ua,true);

 -- ---- event maken (concept), ticketsoorten, standaardkleur van de zaak ----
 ev := (public.pasr_business_event_save(a, jsonb_build_object(
   'name','Winterborrel','description','Glühwein en chocolademelk','starts_at',now()+interval '20 days',
   'ends_at',now()+interval '20 days 3 hours','doors_at',now()+interval '20 days'-interval '15 minutes',
   'address','Hoofdstraat 12, Apeldoorn','capacity',3,'max_per_person',2,'waitlist',true,
   'ticket_types',jsonb_build_array(jsonb_build_object('name','Toegang'),jsonb_build_object('name','Kinderen t/m 12','capacity',1))))->>'id')::uuid;
 if (select color from public.pasr_tk_events where id = ev) <> '#6A5CFF' then raise exception 'default colour'; end if;
 if (select status from public.pasr_tk_events where id = ev) <> 'draft' then raise exception 'default status draft'; end if;
 select id into t_toegang from public.pasr_tk_ticket_types where event_id = ev and name = 'Toegang';
 select id into t_kind from public.pasr_tk_ticket_types where event_id = ev and capacity = 1;
 if public.pasr_event_public(ev) is not null then raise exception 'Draft must not be public'; end if;
 perform pg_temp.expect(format('select public.pasr_event_register(%L,''A'',''B'',''a@b.nl'',''1990-01-01'',null,1)', ev), 'event_not_found');
 perform pg_temp.expect(format('select public.pasr_business_event_save(%L, ''{"name":"x"}''::jsonb)', a), 'invalid_input');
 -- een ander mag niet aanmaken of wijzigen
 perform set_config('app.user_id',klant,true);
 perform pg_temp.expect(format('select public.pasr_business_event_save(%L, ''{"name":"Feest"}''::jsonb)', a), 'not_owner');
 perform pg_temp.expect(format('select * from public.pasr_business_events(%L)', a), 'not_owner');

 -- ---- online zetten (zelfde id, soorten blijven) ----
 perform set_config('app.user_id',ua,true);
 perform public.pasr_business_event_save(a, jsonb_build_object('id',ev,'status','published','name','Winterborrel',
   'starts_at',now()+interval '20 days','ends_at',now()+interval '20 days 3 hours','address','Hoofdstraat 12, Apeldoorn',
   'capacity',3,'max_per_person',2,'color','#1f3a5f',
   'ticket_types',jsonb_build_array(jsonb_build_object('id',t_toegang,'name','Toegang'),jsonb_build_object('id',t_kind,'name','Kinderen t/m 12','capacity',1))));
 if (select count(*) from public.pasr_tk_ticket_types where event_id = ev) <> 2 then raise exception 'types kept'; end if;
 pub := public.pasr_event_public(ev);
 if (pub->>'spots_left')::int <> 3 or (pub->>'signup_open')::boolean is not true or pub->>'color' <> '#1F3A5F'
    or pub->>'business_name' <> 'De Koffiehoek' or json_array_length(pub->'ticket_types') <> 2 then raise exception 'public %', pub; end if;
 if pub::text ~* '(email|birth|first_name|last_name)' then raise exception 'Public event leaks personal fields'; end if;

 -- ---- aanmelden (anoniem): capaciteit, max per persoon, wachtlijst, ticketsoort ----
 perform set_config('app.user_id','',true);
 perform pg_temp.expect(format('select public.pasr_event_register(%L,'''',''de Vries'',''anna@example.nl'',''1991-03-14'',null,1)', ev), 'invalid_input');
 perform pg_temp.expect(format('select public.pasr_event_register(%L,''Anna'',''de Vries'',''geen-mail'',''1991-03-14'',null,1)', ev), 'invalid_input');
 perform pg_temp.expect(format('select public.pasr_event_register(%L,''Anna'',''de Vries'',''anna@example.nl'',null,null,1)', ev), 'invalid_input');
 perform pg_temp.expect(format('select public.pasr_event_register(%L,''Anna'',''de Vries'',''anna@example.nl'',%L,null,1)', ev, current_date + 1), 'invalid_input');
 perform pg_temp.expect(format('select public.pasr_event_register(%L,''Anna'',''de Vries'',''anna@example.nl'',''1991-03-14'',null,3)', ev), 'too_many');
 r1 := public.pasr_event_register(ev,'Anna','de Vries','Anna@Example.nl','1991-03-14',t_toegang,2);
 if r1->>'status' <> 'registered' or json_array_length(r1->'tickets') <> 2 then raise exception 'r1 %', r1; end if;
 code1 := r1->'tickets'->0->>'code'; tid1 := (r1->'tickets'->0->>'ticket_id')::uuid;
 if code1 !~ '^[A-Z2-7]{24}$' or code1 ~ '^P[ZC]' then raise exception 'ticket code format %', code1; end if;
 if r1->>'add_link' <> 'https://pasr.nl/add/t/' || tid1 || '?c=' || code1 then raise exception 'add_link %', r1->>'add_link'; end if;
 perform pg_temp.expect(format('select public.pasr_event_register(%L,''Anna'',''de Vries'',''anna@example.nl'',''1991-03-14'',null,1)', ev), 'too_many');
 r2 := public.pasr_event_register(ev,'Mehmet','Yilmaz','m.yilmaz@example.nl','1985-11-02',t_toegang,2);
 if r2->>'status' <> 'waitlist' then raise exception 'r2 should be waitlist %', r2; end if;
 r3 := public.pasr_event_register(ev,'Sanne','Bakker','sanne@example.nl','1979-06-27',t_kind,1);
 if r3->>'status' <> 'registered' then raise exception 'r3 kinderen %', r3; end if;
 r4 := public.pasr_event_register(ev,'Joris','Hendriks','joris@example.nl','1996-09-09',t_toegang,1);
 if r4->>'status' <> 'waitlist' then raise exception 'r4 %', r4; end if;
 if (public.pasr_event_public(ev)->>'spots_left')::int <> 0 then raise exception 'spots after full'; end if;
 select count(*) into n from public.pasr_tk_outbox where kind = 'ticket_confirmed' and pushed_at is not null and mailed_at is null;
 if n <> 4 then raise exception 'confirmations in outbox: %', n; end if;
 -- ticketsoort vol: nog een kind gaat naar de wachtlijst
 x := public.pasr_event_register(ev,'Fatima','El Amrani','f.elamrani@example.nl','1988-01-30',t_kind,1);
 if x->>'status' <> 'waitlist' then raise exception 'type capacity %', x; end if;

 -- ---- afmelden met de code: wachtlijst schuift door (oudste eerst, per soort) ----
 perform pg_temp.expect(format('select public.pasr_event_ticket_cancel(%L,''FOUT'')', tid1), 'invalid_code');
 x := public.pasr_event_ticket_cancel(tid1, lower(code1));
 if (x->>'cancelled')::int <> 2 or (x->>'promoted')::int <> 2 then raise exception 'cancel/promote %', x; end if;
 if (select count(*) from public.pasr_tk_tickets where registration_id = (r2->>'registration_id')::uuid and status = 'registered') <> 2
 then raise exception 'r2 not promoted'; end if;
 if (select status from public.pasr_tk_tickets where id = (r4->'tickets'->0->>'ticket_id')::uuid) <> 'waitlist' then raise exception 'r4 should still wait'; end if;
 select count(*) into n from public.pasr_tk_outbox where kind = 'waitlist_promoted';
 if n <> 2 then raise exception 'waitlist_promoted rows %', n; end if;

 -- ---- aanmeldingen: alleen de eigenaar, met geboortedatum en positie op de wachtlijst ----
 perform set_config('app.user_id',ua,true);
 select count(*) into n from public.pasr_business_event_registrations(a, ev);
 if n <> 7 then raise exception 'registrations rows %', n; end if;
 if (select birth_date from public.pasr_business_event_registrations(a, ev) where email = 'sanne@example.nl') <> date '1979-06-27'
 then raise exception 'birth date for owner'; end if;
 if (select waitlist_position from public.pasr_business_event_registrations(a, ev) where email = 'joris@example.nl') <> 1
 then raise exception 'waitlist position'; end if;
 if (select registered from public.pasr_business_events(a) where id = ev) <> 3
    or (select waitlist from public.pasr_business_events(a) where id = ev) <> 2 then raise exception 'event counts'; end if;
 perform set_config('app.user_id',ub,true);
 perform pg_temp.expect(format('select * from public.pasr_business_event_registrations(%L,%L)', a, ev), 'not_owner');
 perform pg_temp.expect(format('select * from public.pasr_business_event_registrations(%L,%L)', b, ev), 'event_not_found');

 -- ---- scannen aan de deur ----
 perform set_config('app.user_id',ua,true);
 ev2 := (public.pasr_business_event_save(a, jsonb_build_object('name','Kerstbrood proeven','status','published',
   'starts_at',now()+interval '25 days','ends_at',now()+interval '25 days 2 hours','capacity',40))->>'id')::uuid;
 if (select count(*) from public.pasr_tk_ticket_types where event_id = ev2 and name = 'Toegang') <> 1 then raise exception 'default type'; end if;
 code1 := (select code from public.pasr_tk_tickets where registration_id = (r2->>'registration_id')::uuid order by created_at limit 1);
 x := public.pasr_business_ticket_scan(a, code1, ev);
 if x->>'result' <> 'valid' or x->>'first_name' <> 'Mehmet' or x->>'ticket_type' <> 'Toegang' or x->>'checked_in_at' is null
    or (x->'counts'->>'checked_in')::int <> 1 or (x->'counts'->>'registered')::int <> 3 or (x->'counts'->>'capacity')::int <> 3
 then raise exception 'scan valid %', x; end if;
 if x::text ~* 'birth' then raise exception 'scan leaks birth date'; end if;
 if public.pasr_business_ticket_scan(a, lower(code1), ev)->>'result' <> 'used' then raise exception 'scan used'; end if;
 if public.pasr_business_ticket_scan(a, code1, ev2)->>'result' <> 'other_event' then raise exception 'scan other_event'; end if;
 if public.pasr_business_ticket_scan(a, 'ABCDEFGHIJKLMNOPQRSTUVWX', ev)->>'result' <> 'invalid' then raise exception 'scan invalid'; end if;
 if public.pasr_business_ticket_scan(a, (r4->'tickets'->0->>'code'), ev)->>'result' <> 'invalid' then raise exception 'scan waitlist'; end if;
 if public.pasr_business_ticket_scan(a, (r1->'tickets'->1->>'code'), ev)->>'result' <> 'cancelled' then raise exception 'scan cancelled ticket'; end if;
 perform set_config('app.user_id',ub,true);
 if public.pasr_business_ticket_scan(b, (r3->'tickets'->0->>'code'), null)->>'result' <> 'invalid' then raise exception 'other business ticket'; end if;
 perform set_config('app.user_id',klant,true);
 perform pg_temp.expect(format('select public.pasr_business_ticket_scan(%L,%L,null)', a, r3->'tickets'->0->>'code'), 'not_owner');

 -- ---- ticket aan het account koppelen; ingelogd aanmelden zet het meteen in de wallet ----
 perform pg_temp.expect(format('select public.pasr_event_ticket_claim(%L,''FOUT'')', r4->'tickets'->0->>'ticket_id'), 'invalid_code');
 x := public.pasr_event_ticket_claim((r4->'tickets'->0->>'ticket_id')::uuid, r4->'tickets'->0->>'code');
 if x->>'ticket_id' <> r4->'tickets'->0->>'ticket_id' then raise exception 'claim %', x; end if;
 x := public.pasr_event_register(ev2,'Anna','de Vries','anna@example.nl','1991-03-14',null,2);
 select count(*) into n from public.pasr_my_event_tickets() t where t.event_id = ev2 and t.group_key = ev2::text and t.holder_name = 'Anna de Vries';
 if n <> 2 then raise exception 'my tickets ev2 %', n; end if;
 if not exists (select 1 from public.pasr_my_event_tickets() t where t.event_id = ev and t.status = 'waitlist') then raise exception 'claimed ticket missing'; end if;
 perform set_config('app.user_id',ub,true);
 perform pg_temp.expect(format('select public.pasr_event_ticket_claim(%L,%L)', r4->'tickets'->0->>'ticket_id', r4->'tickets'->0->>'code'), 'invalid_code');

 -- ---- aanmelden dicht, vol zonder wachtlijst, afgelast ----
 perform set_config('app.user_id',ua,true);
 ev3 := (public.pasr_business_event_save(a, jsonb_build_object('name','Proeverij','status','published','capacity',1,'waitlist',false,
   'starts_at',now()+interval '3 days','ends_at',now()+interval '3 days 1 hour'))->>'id')::uuid;
 perform set_config('app.user_id','',true);
 x := public.pasr_event_register(ev3,'Piet','Jansen','piet@example.nl','1970-01-01',null,1);
 perform pg_temp.expect(format('select public.pasr_event_register(%L,''Kees'',''Jansen'',''kees@example.nl'',''1970-01-01'',null,1)', ev3), 'event_full');
 perform set_config('app.user_id',ua,true);
 perform public.pasr_business_event_save(a, jsonb_build_object('id',ev3,'name','Proeverij','capacity',1,'waitlist',false,
   'starts_at',now()+interval '3 days','ends_at',now()+interval '3 days 1 hour','signup_until',now()-interval '1 hour'));
 perform set_config('app.user_id','',true);
 perform pg_temp.expect(format('select public.pasr_event_register(%L,''Kees'',''Jansen'',''kees@example.nl'',''1970-01-01'',null,1)', ev3), 'signup_closed');
 perform set_config('app.user_id',ua,true);
 delete from public.pasr_tk_outbox;
 perform public.pasr_business_event_cancel(a, ev2, 'Helaas ziek, we plannen een nieuwe datum.');
 if (select status from public.pasr_tk_events where id = ev2) <> 'cancelled' then raise exception 'cancel status'; end if;
 if exists (select 1 from public.pasr_tk_tickets where event_id = ev2 and status <> 'cancelled') then raise exception 'tickets not cancelled'; end if;
 if (select count(*) from public.pasr_tk_outbox where kind = 'event_cancelled' and message like 'Helaas%' and user_id = klant::uuid) <> 1
 then raise exception 'cancel outbox'; end if;
 if public.pasr_business_ticket_scan(a, (x->'tickets'->0->>'code'), null)->>'result' <> 'valid' then raise exception 'ev3 ticket'; end if;
 perform set_config('app.user_id','',true);
 perform pg_temp.expect(format('select public.pasr_event_register(%L,''Kees'',''Jansen'',''kees@example.nl'',''1970-01-01'',null,1)', ev2), 'event_cancelled');
 perform set_config('app.user_id',ua,true);
 perform pg_temp.expect(format('select public.pasr_business_event_save(%L, %L::jsonb)', a, jsonb_build_object('id',ev2,'name','Weer open',
   'starts_at',now()+interval '25 days','ends_at',now()+interval '25 days 2 hours','capacity',40)), 'event_cancelled');

 -- ---- wijziging: mail en push naar iedereen met een ticket ----
 perform public.pasr_business_event_save(a, jsonb_build_object('id',ev,'name','Winterborrel','starts_at',now()+interval '21 days',
   'ends_at',now()+interval '21 days 3 hours','address','Marktplein 1, Apeldoorn','capacity',3,'max_per_person',2,
   'ticket_types',jsonb_build_array(jsonb_build_object('id',t_toegang,'name','Toegang'),jsonb_build_object('id',t_kind,'name','Kinderen t/m 12','capacity',1))));
 select count(*) into n from public.pasr_tk_outbox where kind = 'event_changed' and event_id = ev;
 if n <> 4 then raise exception 'event_changed rows %', n; end if;
 -- meer plekken: wachtlijst schuift door
 perform public.pasr_business_event_save(a, jsonb_build_object('id',ev,'name','Winterborrel','starts_at',now()+interval '21 days',
   'ends_at',now()+interval '21 days 3 hours','address','Marktplein 1, Apeldoorn','capacity',4,'max_per_person',2,
   'ticket_types',jsonb_build_array(jsonb_build_object('id',t_toegang,'name','Toegang'),jsonb_build_object('id',t_kind,'name','Kinderen t/m 12','capacity',1))));
 if (select status from public.pasr_tk_tickets where id = (r4->'tickets'->0->>'ticket_id')::uuid) <> 'registered' then raise exception 'capacity promote'; end if;

 -- ---- outbox voor de functies: mail met codes en link, push met de apparaten van de klant ----
 j := public.pasr_tk_mail_due(200);
 if not exists (select 1 from jsonb_array_elements(j) i where i->>'kind' = 'event_changed' and i->>'to' = 'joris@example.nl'
                and i->'event'->>'address' = 'Marktplein 1, Apeldoorn' and i->'tickets'->0->>'add_link' like 'https://pasr.nl/add/t/%?c=%')
 then raise exception 'mail_due %', j; end if;
 if j::text ~* 'birth' then raise exception 'mail_due leaks birth date'; end if;
 if jsonb_array_length(public.pasr_tk_mail_due(200)) <> 0 then raise exception 'claimed mail offered twice'; end if;
 perform public.pasr_tk_mail_sent(array(select (i->>'id')::bigint from jsonb_array_elements(j) i));
 j := public.pasr_tk_push_due(200);
 if not exists (select 1 from jsonb_array_elements(j) i where i->>'kind' = 'event_cancelled' and jsonb_array_length(i->'devices') = 2
                and i->>'event_id' = ev2::text and i->>'title' = 'Kerstbrood proeven') then raise exception 'push_due %', j; end if;
 perform public.pasr_tk_push_sent(array(select (i->>'id')::bigint from jsonb_array_elements(j) i));
 if jsonb_array_length(public.pasr_tk_push_due(200)) <> 0 then raise exception 'push offered after sent'; end if;

 -- ---- herinnering de dag ervoor (vanaf 10:00 Nederlandse tijd), één keer ----
 perform public.pasr_business_event_save(a, jsonb_build_object('id',ev3,'name','Proeverij','status','published','capacity',1,'waitlist',false,
   'starts_at',((d0 + 1) + time '19:00') at time zone 'Europe/Amsterdam','ends_at',((d0 + 1) + time '21:00') at time zone 'Europe/Amsterdam'));
 perform public.pasr_business_event_save(a, jsonb_build_object('id',ev3,'name','Proeverij','capacity',2,'waitlist',false,
   'starts_at',((d0 + 1) + time '19:00') at time zone 'Europe/Amsterdam','ends_at',((d0 + 1) + time '21:00') at time zone 'Europe/Amsterdam'));
 perform set_config('app.user_id','',true);
 perform public.pasr_event_register(ev3,'Kees','Jansen','kees@example.nl','1970-01-01',null,1);
 perform set_config('app.user_id',ua,true);
 delete from public.pasr_tk_outbox;
 j := public.pasr_tk_cron(((d0) + time '09:30') at time zone 'Europe/Amsterdam');
 if (j->>'reminders')::int <> 0 then raise exception 'reminder before 10:00 %', j; end if;
 j := public.pasr_tk_cron(((d0) + time '10:05') at time zone 'Europe/Amsterdam');
 if (j->>'reminders')::int <> 1 or not exists (select 1 from public.pasr_tk_outbox where kind = 'event_reminder' and email = 'kees@example.nl')
 then raise exception 'reminder %', j; end if;
 if (public.pasr_tk_cron(((d0) + time '10:15') at time zone 'Europe/Amsterdam')->>'reminders')::int <> 0 then raise exception 'reminder twice'; end if;

 -- ---- privacy na het event: gegevens weg ----
 j := public.pasr_tk_cron(now() + interval '60 days');
 if (j->>'purged')::int < 2 then raise exception 'purge %', j; end if;
 if exists (select 1 from public.pasr_tk_registrations where event_id = ev and (email is not null or birth_date is not null))
 then raise exception 'personal data kept after event'; end if;

 -- ---- beheer ----
 j := public.pasr_admin_tk_business(a);
 if jsonb_array_length(j->'events') <> 3 then raise exception 'admin events %', j; end if;
 perform public.pasr_admin_event_cancel(ev, 'Afgelast door Pasr');
 if (select status from public.pasr_tk_events where id = ev) <> 'cancelled' then raise exception 'admin cancel'; end if;
 raise notice 'PASR TICKETS TEST PASSED';
end $$;

-- ---- privacy: anon leest geen tabellen en geen aanmeldingen; alleen de openbare functies ----
do $$
declare ok boolean;
begin
 set local role anon;
 begin
  perform 1 from public.pasr_tk_registrations limit 1;
  raise exception 'anon read registrations';
 exception when insufficient_privilege then null;
 end;
 begin
  perform 1 from public.pasr_tk_tickets limit 1;
  raise exception 'anon read tickets';
 exception when insufficient_privilege then null;
 end;
 begin
  perform 1 from public.pasr_mc_members limit 1;
  raise exception 'anon read members';
 exception when insufficient_privilege then null;
 end;
 begin
  perform * from public.pasr_business_event_registrations('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid());
  raise exception 'anon called registrations';
 exception when insufficient_privilege then null;
 end;
 begin
  perform public.pasr_tk_mail_due(1);
  raise exception 'anon called mail_due';
 exception when insufficient_privilege then null;
 end;
 perform public.pasr_event_public(gen_random_uuid());
 perform public.pasr_member_card_public(gen_random_uuid());
 reset role;
 raise notice 'PASR TICKETS PRIVACY TEST PASSED';
end $$;

-- ---- klantenkaart met barcode ----
do $$
declare
 a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
 ua text := '11111111-1111-4111-8111-111111111111';
 ub text := '22222222-2222-4222-8222-222222222222';
 klant text := '33333333-3333-4333-8333-333333333333';
 d0 date := (now() at time zone 'Europe/Amsterdam')::date;
 kc uuid; kp uuid; kd uuid; j jsonb; x json; num text; num2 text; mem uuid; n int;
begin
 -- EAN-13-controlecijfer (bekend voorbeeld 4006381333931)
 if public.pasr_mc_ean_check('400638133393') <> '1' or not public.pasr_mc_ean_valid('4006381333931')
    or public.pasr_mc_ean_valid('4006381333932') then raise exception 'EAN-13 checksum'; end if;

 perform set_config('app.user_id',ua,true);
 kc := (public.pasr_business_member_card_save(a, jsonb_build_object('name','Korenschoof Klantenkaart','color','#8a4b1f',
   'barcode_type','ean13','prefix','KS-','status','published',
   'goals',jsonb_build_object('membership',true,
     'saving',jsonb_build_object('enabled',true,'unit','visits','target',3,'reward','Gratis gebakje'),
     'fixed_discount',jsonb_build_object('enabled',true,'percent',5),
     'periods',jsonb_build_array(
       jsonb_build_object('label','15% op alles','percent',15,'starts_on','2026-12-01','ends_on','2026-12-15'),
       jsonb_build_object('label','happy hour','percent',20,'starts_on','2026-12-01','ends_on','2026-12-31','weekdays',jsonb_build_array(2),'from_time','17:00','to_time','19:00'),
       jsonb_build_object('label','Zomeravond','percent',10,'starts_on','2027-07-01','ends_on','2027-07-31','weekdays',jsonb_build_array(2),'from_time','17:00','to_time','19:00')))))->>'id')::uuid;
 if (select prefix from public.pasr_mc_cards where id = kc) <> '' then raise exception 'ean13 ignores prefix'; end if;
 perform pg_temp.expect(format('select public.pasr_business_member_card_save(%L, %L::jsonb)', a,
   '{"name":"X","status":"published","goals":{}}'), 'invalid_input');
 perform pg_temp.expect(format('select public.pasr_business_member_card_save(%L, %L::jsonb)', a,
   '{"name":"X","goals":{"periods":[{"percent":10,"starts_on":"2026-12-10","ends_on":"2026-12-01"}]}}'), 'invalid_input');

 -- ---- korting nu en straks, in Nederlandse tijd (winter +01:00, zomer +02:00) ----
 j := public.pasr_mc_discount(kc, timestamptz '2026-12-08 17:00:00+00');   -- dinsdag 18:00
 if (j->'now'->>'percent')::numeric <> 20 or j->'now'->>'label' <> 'happy hour'
    or (j->'now'->>'until')::timestamptz <> timestamptz '2026-12-08 18:00:00+00' then raise exception 'tuesday 18:00 %', j; end if;
 j := public.pasr_mc_discount(kc, timestamptz '2026-12-08 15:00:00+00');   -- dinsdag 16:00
 if (j->'now'->>'percent')::numeric <> 15 or (j->'next'->>'percent')::numeric <> 20
    or (j->'next'->>'starts_at')::timestamptz <> timestamptz '2026-12-08 16:00:00+00' then raise exception 'tuesday 16:00 %', j; end if;
 j := public.pasr_mc_discount(kc, timestamptz '2026-12-09 17:00:00+00');   -- woensdag 18:00: geen happy hour
 if (j->'now'->>'percent')::numeric <> 15 or (j->'next'->>'starts_at')::timestamptz <> timestamptz '2026-12-15 16:00:00+00'
 then raise exception 'wednesday %', j; end if;
 j := public.pasr_mc_discount(kc, timestamptz '2026-12-20 11:00:00+00');   -- na de 15e: alleen vaste korting
 if (j->'now'->>'percent')::numeric <> 5 or j->'now'->>'kind' <> 'fixed' then raise exception 'fixed %', j; end if;
 j := public.pasr_mc_discount(kc, timestamptz '2027-07-06 15:30:00+00');   -- dinsdag 17:30 zomertijd
 if (j->'now'->>'percent')::numeric <> 10 then raise exception 'summer time %', j; end if;
 j := public.pasr_mc_discount(kc, timestamptz '2027-07-06 17:30:00+00');   -- dinsdag 19:30 zomertijd: voorbij
 if (j->'now'->>'percent')::numeric <> 5 or (j->'next'->>'starts_at')::timestamptz <> timestamptz '2027-07-13 15:00:00+00'
 then raise exception 'summer after %', j; end if;
 j := public.pasr_mc_discount(kc, timestamptz '2026-11-30 12:00:00+00');   -- voor de start
 if (j->'next'->>'starts_at')::timestamptz <> timestamptz '2026-11-30 23:00:00+00' then raise exception 'next start %', j; end if;

 -- ---- openbare kaart zonder ledengegevens ----
 x := public.pasr_member_card_public(kc);
 if x->>'business_name' <> 'De Koffiehoek' or json_array_length(x->'goals_summary'->'lines') < 3 then raise exception 'public card %', x; end if;

 -- ---- lid worden (ingelogd), EAN-13 met geldig controlecijfer ----
 perform set_config('app.user_id','',true);
 perform pg_temp.expect(format('select public.pasr_member_card_join(%L,true)', kc), 'not_signed_in');
 perform set_config('app.user_id',klant,true);
 x := public.pasr_member_card_join(kc, true);
 num := x->>'number'; mem := (x->>'member_id')::uuid;
 if x->>'barcode_type' <> 'ean13' or not public.pasr_mc_ean_valid(num) or left(num,1) <> '2' then raise exception 'join ean %', x; end if;
 perform pg_temp.expect(format('select public.pasr_member_card_join(%L,true)', kc), 'already_member');
 perform pg_temp.expect(format('select public.pasr_member_card_join(%L,true)', gen_random_uuid()), 'card_not_found');
 if (select count(*) from public.pasr_my_member_cards() m where m.card_id = kc and m.number = num) <> 1 then raise exception 'my cards'; end if;
 perform public.pasr_member_card_notify(mem, false);
 if (select notify from public.pasr_mc_members where id = mem) then raise exception 'notify off'; end if;
 perform public.pasr_member_card_notify(mem, true);

 -- ---- scannen, bezoek, sparen en inwisselen ----
 perform set_config('app.user_id',ua,true);
 x := public.pasr_business_member_card_scan(a, num);
 if x->>'result' <> 'valid' or x->>'member_name' <> 'Anna de Vries' or (x->'saving'->>'count')::int <> 0
    or (x->'saving'->>'target')::int <> 3 or x->'discount_now' is null then raise exception 'scan %', x; end if;
 if public.pasr_business_member_card_scan(a, '2999999999999')->>'result' <> 'invalid' then raise exception 'scan invalid'; end if;
 perform pg_temp.expect(format('select public.pasr_business_member_card_redeem(%L,%L)', a, num), 'not_enough');
 perform public.pasr_business_member_card_visit(a, num);
 perform public.pasr_business_member_card_visit(a, num);
 x := public.pasr_business_member_card_visit(a, num, 50);   -- bij bezoeken telt een scan altijd 1
 if (x->'saving'->>'count')::int <> 3 or (x->'saving'->>'can_redeem')::boolean is not true then raise exception 'visits %', x; end if;
 x := public.pasr_business_member_card_redeem(a, num);
 if (x->'saving'->>'count')::int <> 0 or (select rewards_redeemed from public.pasr_mc_members where id = mem) <> 1 then raise exception 'redeem %', x; end if;
 perform pg_temp.expect(format('select public.pasr_business_member_card_visit(%L,''ONBEKEND1'')', a), 'invalid_code');
 perform set_config('app.user_id',ub,true);
 if public.pasr_business_member_card_scan(b, num)->>'result' <> 'other_business' then raise exception 'other_business'; end if;
 perform set_config('app.user_id',klant,true);
 perform pg_temp.expect(format('select public.pasr_business_member_card_scan(%L,%L)', a, num), 'not_owner');

 -- ---- punten en Code 128 met voorvoegsel; barcodetype vast zodra er leden zijn ----
 perform set_config('app.user_id',ua,true);
 kp := (public.pasr_business_member_card_save(a, jsonb_build_object('name','Puntenkaart','barcode_type','code128','prefix','ks-',
   'status','published','goals',jsonb_build_object('saving',jsonb_build_object('enabled',true,'unit','points','target',100,'reward','Taart')))) ->>'id')::uuid;
 perform set_config('app.user_id',klant,true);
 num2 := public.pasr_member_card_join(kp, false)->>'number';
 if num2 <> 'KS-000001' then raise exception 'prefix number %', num2; end if;
 perform set_config('app.user_id',ua,true);
 x := public.pasr_business_member_card_visit(a, 'ks-000001', 40);
 if (x->'saving'->>'count')::int <> 40 or x->'saving'->>'unit' <> 'points' then raise exception 'points %', x; end if;
 if public.pasr_business_member_card_scan(a, num2)->>'member_name' is not null then raise exception 'name shared without consent'; end if;
 perform pg_temp.expect(format('select public.pasr_business_member_card_save(%L, %L::jsonb)', a,
   jsonb_build_object('id',kp,'name','Puntenkaart','barcode_type','ean13')), 'barcode_type_locked');
 select members into n from public.pasr_business_member_cards(a) where id = kp;
 if n <> 1 then raise exception 'members count %', n; end if;

 -- ---- push als een kortingsperiode begint (alleen leden met meldingen aan) ----
 kd := (public.pasr_business_member_card_save(a, jsonb_build_object('name','Dagkaart','status','published',
   'goals',jsonb_build_object('periods',jsonb_build_array(jsonb_build_object('label','Avondkorting','percent',25,
     'starts_on',d0,'ends_on',d0 + 7,'from_time','17:00','to_time','20:00')))))->>'id')::uuid;
 perform set_config('app.user_id',klant,true);
 perform public.pasr_member_card_join(kd, false);
 delete from public.pasr_tk_outbox;
 j := public.pasr_tk_cron((d0 + time '16:50') at time zone 'Europe/Amsterdam');
 if (j->>'discounts')::int <> 0 then raise exception 'discount push too early %', j; end if;
 j := public.pasr_tk_cron((d0 + time '17:05') at time zone 'Europe/Amsterdam');
 if (j->>'discounts')::int <> 1 or not exists (select 1 from public.pasr_tk_outbox where kind = 'member_discount_started'
    and card_id = kd and user_id = klant::uuid and mailed_at is not null) then raise exception 'discount push %', j; end if;
 if (public.pasr_tk_cron((d0 + time '17:15') at time zone 'Europe/Amsterdam')->>'discounts')::int <> 0 then raise exception 'discount push twice'; end if;
 j := public.pasr_tk_push_due(50);
 if not exists (select 1 from jsonb_array_elements(j) i where i->>'kind' = 'member_discount_started' and i->>'card_id' = kd::text
    and (i->>'percent')::numeric = 25 and jsonb_array_length(i->'devices') = 2) then raise exception 'discount push_due %', j; end if;

 -- ---- opzeggen en opnieuw lid: nieuw nummer ----
 perform public.pasr_member_card_leave(mem);
 if exists (select 1 from public.pasr_my_member_cards() m where m.member_id = mem) then raise exception 'left card still listed'; end if;
 if (public.pasr_member_card_join(kc, true)->>'number') = num then raise exception 'rejoin reuses number'; end if;
 perform set_config('app.user_id',ua,true);
 if public.pasr_business_member_card_scan(a, num)->>'result' <> 'invalid' then raise exception 'old number still valid'; end if;

 -- ---- Wallet-gegevens en beheer ----
 j := public.pasr_tk_pass_data('member_card', (select id from public.pasr_mc_members where card_id = kp limit 1));
 if j->>'number' <> 'KS-000001' or j->>'barcode_type' <> 'code128' then raise exception 'pass data %', j; end if;
 j := public.pasr_admin_tk_business(a);
 if jsonb_array_length(j->'member_cards') <> 3 then raise exception 'admin cards %', j; end if;
 perform public.pasr_admin_member_card_archive(kp);
 if public.pasr_business_member_card_scan(a, 'KS-000001')->>'result' <> 'invalid' then raise exception 'archived card scans'; end if;
 if public.pasr_member_card_public(kp) is not null then raise exception 'archived card public'; end if;
 raise notice 'PASR KLANTENKAART TEST PASSED';
end $$;
