-- Anti-bot voor openbare formulieren (20261127-antibot-forms.sql en p_hp in 20261127-tickets-klantenkaart.sql).
-- Alleen de honeypot (p_hp: tekstveld of vinkje, de website stuurt dan 'x') houdt iets tegen; p_fill_ms wordt genegeerd:
-- er is geen afwijzing op tijd meer.
-- Draait na tickets_klantenkaart_smoke.sql in de PR-check "backend-integration". Alleen testomgeving.

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
 ua text := '11111111-1111-4111-8111-111111111111';
 klant text := '33333333-3333-4333-8333-333333333333';
 ev uuid; r json; x json; n int; regs int; outbox int; i int; tid uuid; code text;
begin
 -- ---- één variant per functie (p_fill_ms blijft in de signatuur); de oude (zonder p_hp/p_fill_ms) bestaat niet meer ----
 if to_regprocedure('public.pasr_event_register(uuid,text,text,text,date,uuid,integer)') is not null then
   raise exception 'old pasr_event_register overload still exists'; end if;
 if to_regprocedure('public.pasr_event_ticket_cancel(uuid,text)') is not null then
   raise exception 'old pasr_event_ticket_cancel overload still exists'; end if;
 if not has_function_privilege('anon', 'public.pasr_event_register(uuid,text,text,text,date,uuid,integer,text,integer)', 'execute')
    or not has_function_privilege('anon', 'public.pasr_event_ticket_cancel(uuid,text,text,integer)', 'execute') then
   raise exception 'anon must keep execute on the public RPCs'; end if;
 if has_function_privilege('anon', 'public.pasr_form_bot(text,text)', 'execute')
    or has_function_privilege('anon', 'public.pasr_form_rate_hit(text,text,integer)', 'execute')
    or has_function_privilege('anon', 'public.pasr_form_bot_stats()', 'execute') then
   raise exception 'anti-bot helpers must not be callable by anon'; end if;
 if has_table_privilege('anon', 'public.pasr_form_rate', 'select') or has_table_privilege('anon', 'public.pasr_form_bot_log', 'select') then
   raise exception 'anti-bot tables must be closed'; end if;

 -- ---- een event om op aan te melden ----
 perform set_config('app.user_id', ua, true);
 ev := (public.pasr_business_event_save(a, jsonb_build_object('status','published','name','Proefavond',
   'starts_at',now()+interval '30 days','ends_at',now()+interval '30 days 2 hours','address','Markt 1, Apeldoorn',
   'capacity',100,'max_per_person',20,'ticket_types',jsonb_build_array(jsonb_build_object('name','Toegang'))))->>'id')::uuid;
 delete from public.pasr_form_bot_log;
 delete from public.pasr_form_rate;

 -- ---- honeypot ingevuld: gewoon antwoord, maar niets aangemaakt en niets gemaild ----
 perform set_config('app.user_id', '', true);
 select count(*) into regs from public.pasr_tk_registrations where event_id = ev;
 select count(*) into outbox from public.pasr_tk_outbox;
 r := public.pasr_event_register(ev, 'Bot', 'Bot', 'bot@example.nl', '1990-01-01', null, 1, 'https://spam.example', 9000);
 if r->>'status' <> 'registered' or json_array_length(r->'tickets') <> 0 or r->>'add_link' is not null then raise exception 'honeypot answer %', r; end if;
 -- het vinkje (de website stuurt p_hp = 'x'), ook met ongeldige invoer: geen foutmelding die iets verraadt
 r := public.pasr_event_register(ev, '', '', 'geen-mail', null, null, 1, 'x');
 if r->>'status' <> 'registered' then raise exception 'checkbox honeypot answer %', r; end if;
 r := public.pasr_event_register(p_event => ev, p_first_name => 'Bot', p_last_name => 'Bot', p_email => 'bot@example.nl',
   p_birth_date => '1990-01-01', p_ticket_type => null, p_count => 1, p_hp => '  x  ');
 if (select count(*) from public.pasr_tk_registrations where event_id = ev) <> regs then raise exception 'bot created a registration'; end if;
 if (select count(*) from public.pasr_tk_outbox) <> outbox then raise exception 'bot queued a mail'; end if;
 if (select count(*) from public.pasr_form_bot_log where form = 'event_register' and reason = 'honeypot') <> 3
    or exists (select 1 from public.pasr_form_bot_log where reason = 'too_fast') then
   raise exception 'bot log %', (select json_agg(l) from public.pasr_form_bot_log l); end if;
 if (public.pasr_form_bot_stats()->'day'->>'event_register:honeypot')::int <> 3 then raise exception 'bot stats %', public.pasr_form_bot_stats(); end if;
 if exists (select 1 from public.pasr_form_rate) then raise exception 'bots must not count for the rate limit'; end if;

 -- ---- een mens: lege honeypot; ook razendsnel (p_fill_ms 0 of 50, oude pagina in een cache) gaat gewoon door;
 -- en de apps zonder de nieuwe parameters ----
 r := public.pasr_event_register(ev, 'Anna', 'de Vries', 'anna.antibot@example.nl', '1991-03-14', null, 1, '', 8000);
 if r->>'status' <> 'registered' or json_array_length(r->'tickets') <> 1 then raise exception 'human %', r; end if;
 r := public.pasr_event_register(ev, 'Snelle', 'Invuller', 'snel.antibot@example.nl', '1993-06-01', null, 1, null, 50);
 if r->>'status' <> 'registered' or json_array_length(r->'tickets') <> 1 then raise exception 'fast human rejected %', r; end if;
 r := public.pasr_event_register(p_event => ev, p_first_name => 'Nul', p_last_name => 'Seconden', p_email => 'nul.antibot@example.nl',
   p_birth_date => '1994-02-02', p_ticket_type => null, p_count => 1, p_fill_ms => 0);
 if r->>'status' <> 'registered' or json_array_length(r->'tickets') <> 1 then raise exception 'zero fill_ms rejected %', r; end if;
 r := public.pasr_event_register(ev, 'Mehmet', 'Yilmaz', 'mehmet.antibot@example.nl', '1985-11-02', null, 1);
 if r->>'status' <> 'registered' then raise exception 'app call without new params %', r; end if;
 tid := (r->'tickets'->0->>'ticket_id')::uuid; code := r->'tickets'->0->>'code';
 if (select count(*) from public.pasr_tk_outbox) <> outbox + 4 then raise exception 'human confirmations not queued'; end if;
 -- geboortedatum in de toekomst of leeg blijft ongeldig
 perform pg_temp.expect(format('select public.pasr_event_register(%L,''Sanne'',''Bakker'',''s@example.nl'',%L,null,1,null,5000)', ev, current_date + 1), 'invalid_input');

 -- ---- rem per e-mailadres: 10 per dag (anoniem), hoofdletters tellen niet ----
 for i in 1..10 loop
   r := public.pasr_event_register(ev, 'Veel', 'Aanmeldingen', case when i % 2 = 0 then 'Veel@Example.nl' else 'veel@example.nl' end, '1980-05-05', null, 1, null, 5000);
   if r->>'status' <> 'registered' then raise exception 'rate %: %', i, r; end if;
 end loop;
 perform pg_temp.expect(format('select public.pasr_event_register(%L,''Veel'',''Aanmeldingen'',''veel@example.nl'',''1980-05-05'',null,1,null,5000)', ev), 'rate_limited');
 if exists (select 1 from public.pasr_form_rate where key_hash ~* 'veel|example') then raise exception 'e-mail stored in clear'; end if;
 -- een ander e-mailadres kan nog gewoon
 r := public.pasr_event_register(ev, 'Joris', 'Hendriks', 'joris.antibot@example.nl', '1996-09-09', null, 1, null, 5000);
 if r->>'status' <> 'registered' then raise exception 'other mail %', r; end if;
 -- ingelogd (de app) telt niet mee voor de rem per e-mailadres
 perform set_config('app.user_id', klant, true);
 r := public.pasr_event_register(ev, 'Veel', 'Aanmeldingen', 'veel@example.nl', '1980-05-05', null, 1);
 if r->>'status' <> 'registered' then raise exception 'signed in user limited %', r; end if;

 -- ---- afmelden: bot doet niets, een mens wel ----
 perform set_config('app.user_id', '', true);
 x := public.pasr_event_ticket_cancel(tid, code, 'https://spam.example', 5000);
 if (x->>'cancelled')::int <> 0 then raise exception 'bot cancelled %', x; end if;
 x := public.pasr_event_ticket_cancel(tid, code, 'x');   -- vinkje aangevinkt
 if (x->>'cancelled')::int <> 0 then raise exception 'checkbox bot cancelled %', x; end if;
 if (select status from public.pasr_tk_tickets where id = tid) <> 'registered' then raise exception 'ticket touched by bot'; end if;
 if (select count(*) from public.pasr_form_bot_log where form = 'event_ticket_cancel') <> 2 then raise exception 'cancel bot log'; end if;
 if exists (select 1 from public.pasr_form_bot_log where reason = 'too_fast') then raise exception 'too_fast must not be logged anymore'; end if;
 -- een mens die meteen afmeldt (p_fill_ms 10) gaat gewoon door
 x := public.pasr_event_ticket_cancel(tid, code, '', 10);
 if (x->>'cancelled')::int <> 1 then raise exception 'human cancel %', x; end if;
 -- zonder de nieuwe parameters (apps, oude pagina): code blijft het bewijs
 perform pg_temp.expect(format('select public.pasr_event_ticket_cancel(%L,''FOUT'')', tid), 'invalid_code');

 -- opruimen voor een volgende run
 delete from public.pasr_form_rate;
 raise notice 'PASR ANTIBOT TEST PASSED';
end $$;
