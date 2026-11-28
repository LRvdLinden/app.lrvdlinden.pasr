-- Pasr beheer › Mail (20261128-beheer-mail.sql), met verzonnen accounts en zaken. Draait na antibot_forms_smoke.sql in de
-- PR-check "backend-integration". Alleen testomgeving.

-- Wat de echte database wel heeft en de basisfixture niet.
alter table auth.users add column if not exists email text;
alter table auth.users add column if not exists email_confirmed_at timestamptz;
alter table auth.users add column if not exists raw_user_meta_data jsonb;
alter table public.pasr_businesses add column if not exists email text not null default '';
create table if not exists public.pasr_business_staff (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.pasr_businesses(id) on delete cascade,
 user_id uuid references auth.users(id), role text not null default 'staff', revoked_at timestamptz
);
create table if not exists public.pasr_secret (id int primary key, hook_secret text);
insert into public.pasr_secret (id, hook_secret) values (1, 'smoke-test-secret-only') on conflict (id) do update set hook_secret = excluded.hook_secret;
create table if not exists public.pasr_mail_prefs (
 user_id uuid primary key references auth.users (id) on delete cascade, unsub_token text not null
);

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

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
 ('a0000001-0000-4000-8000-000000000001', 'Anna@Voorbeeld.example', now(), '{"first_name":"Anna"}'),
 ('a0000002-0000-4000-8000-000000000002', 'bas@voorbeeld.example', now(), '{}'),
 ('a0000003-0000-4000-8000-000000000003', 'niet-bevestigd@voorbeeld.example', null, '{}'),
 ('a0000004-0000-4000-8000-000000000004', 'eigenaar@zaak-mail.example', now(), '{"first_name":"Els"}'),
 ('a0000005-0000-4000-8000-000000000005', 'medewerker@zaak-mail.example', now(), '{}'),
 ('a0000006-0000-4000-8000-000000000006', 'ingetrokken@zaak-mail.example', now(), '{}'),
 ('a0000007-0000-4000-8000-000000000007', 'geblokkeerd@zaak-mail.example', now(), '{}')
on conflict (id) do update set email = excluded.email, email_confirmed_at = excluded.email_confirmed_at, raw_user_meta_data = excluded.raw_user_meta_data;
insert into public.pasr_businesses (id, owner, name, city, status) values
 ('b0000001-0000-4000-8000-000000000001', 'a0000004-0000-4000-8000-000000000004', 'Mailzaak', 'Apeldoorn', 'approved'),
 ('b0000002-0000-4000-8000-000000000002', 'a0000007-0000-4000-8000-000000000007', 'Geblokkeerde zaak', 'Deventer', 'blocked')
on conflict (id) do nothing;
-- schoon beginnen (de test mag opnieuw draaien)
truncate public.pasr_mail_threads, public.pasr_mail_campaigns, public.pasr_mail_optout, public.pasr_mail_inbox_log restart identity cascade;
update public.pasr_mail_sync set lock_until = null, last_uid = null;
delete from public.pasr_business_staff where business_id = 'b0000001-0000-4000-8000-000000000001';
insert into public.pasr_business_staff (business_id, user_id, role, revoked_at) values
 ('b0000001-0000-4000-8000-000000000001', 'a0000005-0000-4000-8000-000000000005', 'staff', null),
 ('b0000001-0000-4000-8000-000000000001', 'a0000006-0000-4000-8000-000000000006', 'staff', now());

do $$
declare
 r jsonb; n bigint; n2 bigint; mid uuid; tok text; tok2 text; cnt int; id1 bigint; req uuid := 'c0000001-0000-4000-8000-000000000001';
 att jsonb; a text[]; b64 text;
begin
 -- ---- rechten: intern dicht, afmelden open ----
 if has_function_privilege('anon', 'public.pasr_mail_audience(text)', 'execute')
    or has_function_privilege('anon', 'public.pasr_mail_thread_list(text,text,text,integer,integer)', 'execute')
    or has_function_privilege('anon', 'public.pasr_mail_news_token(text,text)', 'execute')
    or has_function_privilege('authenticated', 'public.pasr_mail_attachment_get(uuid)', 'execute')
    or has_function_privilege('anon', 'public.pasr_mail_poll_kick()', 'execute') then
   raise exception 'mail internals must not be callable by anon/authenticated'; end if;
 if not has_function_privilege('anon', 'public.pasr_mail_news_unsubscribe(text)', 'execute')
    or not has_function_privilege('anon', 'public.pasr_mail_news_unsub_email(text,text,text)', 'execute')
    or not has_function_privilege('anon', 'public.pasr_mail_unsubscribe(text)', 'execute') then
   raise exception 'anon must keep execute on the unsubscribe RPCs'; end if;
 if has_table_privilege('anon', 'public.pasr_mail_threads', 'select') or has_table_privilege('authenticated', 'public.pasr_mail_messages', 'select')
    or has_table_privilege('anon', 'public.pasr_mail_attachments', 'select') or has_table_privilege('anon', 'public.pasr_mail_optout', 'select')
    or has_table_privilege('anon', 'public.pasr_mail_campaigns', 'select') then
   raise exception 'mail tables must be closed'; end if;

 -- ---- doelgroepen: alleen bevestigd, owners = eigenaar + medewerker van een goedgekeurde zaak ----
 select count(*) into cnt from public.pasr_mail_audience('users') where email like '%@voorbeeld.example' or email like '%@zaak-mail.example';
 if cnt <> 6 then raise exception 'users audience % (want 6)', cnt; end if;   -- 7 accounts min de onbevestigde
 if exists (select 1 from public.pasr_mail_audience('users') where email = 'niet-bevestigd@voorbeeld.example') then raise exception 'unconfirmed in audience'; end if;
 if not exists (select 1 from public.pasr_mail_audience('users') where email = 'anna@voorbeeld.example' and first_name = 'Anna') then raise exception 'email must be lowercased with first name'; end if;
 if (select count(*) from public.pasr_mail_audience('owners')) <> 2 then raise exception 'owners audience %', (select count(*) from public.pasr_mail_audience('owners')); end if;
 if exists (select 1 from public.pasr_mail_audience('owners') where email in ('ingetrokken@zaak-mail.example', 'geblokkeerd@zaak-mail.example', 'anna@voorbeeld.example')) then
   raise exception 'revoked, blocked or non-owner in owners audience'; end if;
 if public.pasr_mail_audience_count('owners') <> 2 then raise exception 'count owners'; end if;
 perform pg_temp.expect($q$select * from public.pasr_mail_audience('iedereen')$q$, 'bad_audience');
 -- de afmeldcode: 32 hex, per adres vast, per scope anders
 tok := (select a1.token from public.pasr_mail_audience('users') a1 where a1.email = 'bas@voorbeeld.example');
 if tok !~ '^[0-9a-f]{32}$' then raise exception 'token format %', tok; end if;
 if tok <> public.pasr_mail_news_token('BAS@voorbeeld.example ', 'news-users') then raise exception 'token must be stable and case-insensitive'; end if;
 if tok = public.pasr_mail_news_token('bas@voorbeeld.example', 'news-owners') then raise exception 'token must differ per scope'; end if;

 -- ---- afmelden ----
 r := public.pasr_mail_news_unsubscribe(tok);
 if (r->>'ok')::boolean is not true or r->>'scope' <> 'news-users' then raise exception 'unsubscribe %', r; end if;
 if exists (select 1 from public.pasr_mail_audience('users') where email = 'bas@voorbeeld.example') then raise exception 'opted-out still in users'; end if;
 if (select count(*) from public.pasr_mail_optout) <> 1 then raise exception 'one optout row'; end if;
 -- dubbel afmelden is gewoon goed
 if (public.pasr_mail_news_unsubscribe(tok)->>'ok')::boolean is not true then raise exception 'unsubscribe twice'; end if;
 if (select count(*) from public.pasr_mail_optout) <> 1 then raise exception 'still one optout row'; end if;
 -- vervalste code (andere controle) en rommel
 if (public.pasr_mail_news_unsubscribe(left(tok, 28) || '0000')->>'ok')::boolean then raise exception 'forged code accepted'; end if;
 if (public.pasr_mail_news_unsubscribe(repeat('a', 32))->>'ok')::boolean then raise exception 'random code accepted'; end if;
 if (public.pasr_mail_news_unsubscribe('nonsens')->>'ok')::boolean then raise exception 'garbage accepted'; end if;
 -- een afmelding voor de andere lijst wordt 'all'
 tok2 := public.pasr_mail_news_token('bas@voorbeeld.example', 'news-owners');
 r := public.pasr_mail_news_unsubscribe(tok2);
 if (select scope from public.pasr_mail_optout) <> 'all' then raise exception 'scope must become all, got %', (select scope from public.pasr_mail_optout); end if;
 -- owners-lijst: een eigenaar afmelden met het adres
 r := public.pasr_mail_news_unsub_email('Eigenaar@zaak-mail.example', 'news-owners');
 if (r->>'ok')::boolean is not true then raise exception 'unsub by email %', r; end if;
 if exists (select 1 from public.pasr_mail_audience('owners') where email = 'eigenaar@zaak-mail.example') then raise exception 'opted-out owner still listed'; end if;
 if not exists (select 1 from public.pasr_mail_audience('users') where email = 'eigenaar@zaak-mail.example') then raise exception 'owner opt-out must not touch the users list'; end if;
 r := public.pasr_mail_news_unsub_email('geen-adres', 'news-owners');
 if (r->>'ok')::boolean then raise exception 'bad address accepted'; end if;
 r := public.pasr_mail_news_unsub_email('x@voorbeeld.example', 'raar');
 if (r->>'ok')::boolean then raise exception 'bad scope accepted'; end if;
 -- honeypot: doet alsof, schrijft niets
 select count(*) into cnt from public.pasr_mail_optout;
 r := public.pasr_mail_news_unsub_email('bot@voorbeeld.example', 'all', 'x');
 if (select count(*) from public.pasr_mail_optout) <> cnt then raise exception 'honeypot wrote a row'; end if;
 -- handmatige lijst: afgemelden eruit, dubbelen weg
 if (select count(*) from public.pasr_mail_list_tokens(array['A@x.example', 'a@x.example', 'eigenaar@zaak-mail.example', ' '], 'news-owners')) <> 1 then
   raise exception 'list tokens'; end if;
 perform pg_temp.expect($q$select * from public.pasr_mail_list_tokens(array['a@x.example'], 'all')$q$, 'bad_scope');

 -- ---- bestaande herinneringen-afmelding blijft werken, en kent de nieuwe code ----
 insert into public.pasr_mail_prefs (user_id, unsub_token) values ('a0000001-0000-4000-8000-000000000001', repeat('ab', 16));
 r := public.pasr_mail_unsubscribe(repeat('ab', 16));
 if (r->>'ok')::boolean is not true or (r->>'removed')::boolean is not true or r->>'kind' <> 'reminders' then raise exception 'reminders unsubscribe %', r; end if;
 if exists (select 1 from public.pasr_mail_prefs) then raise exception 'prefs row must be gone'; end if;
 r := public.pasr_mail_unsubscribe(public.pasr_mail_news_token('anna@voorbeeld.example', 'news-users'));
 if (r->>'ok')::boolean is not true or r->>'kind' <> 'news' then raise exception 'news via old rpc %', r; end if;
 if exists (select 1 from public.pasr_mail_audience('users') where email = 'anna@voorbeeld.example') then raise exception 'anna still listed'; end if;
 r := public.pasr_mail_unsubscribe(repeat('0', 32));
 if (r->>'ok')::boolean is not true or (r->>'removed')::boolean then raise exception 'unknown token must stay ok/not removed %', r; end if;
 r := public.pasr_mail_unsubscribe('rommel');
 if (r->>'ok')::boolean then raise exception 'garbage token %', r; end if;

 -- ---- tickets ----
 n := public.pasr_mail_thread_create('zakelijk', 'Vraag over stempelkaart', 'Klant@Winkel.example', 'Karin');
 if n < 1001 then raise exception 'ticket numbers start at 1001, got %', n; end if;
 n2 := public.pasr_mail_thread_create('bestaat-niet', '', 'x@y.example', '');
 if (select brand from public.pasr_mail_threads where number = n2) <> 'pasr' then raise exception 'unknown brand falls back to pasr'; end if;
 if (select subject from public.pasr_mail_threads where number = n2) <> '(geen onderwerp)' then raise exception 'empty subject'; end if;
 if (select contact_email from public.pasr_mail_threads where number = n) <> 'klant@winkel.example' then raise exception 'email lowercased'; end if;
 r := public.pasr_mail_message_add(n, 'in', 'klant@winkel.example', '["support@pasr.nl"]', '[]', 0, 'Vraag over stempelkaart', 'Hoi, hoe werkt het?', '<p>Hoi</p>', null,
        '<abc@winkel.example>', null, '[]', 'zakelijk');
 mid := (r->>'id')::uuid;
 if mid is null or (r->>'duplicate')::boolean then raise exception 'first message %', r; end if;
 r := public.pasr_mail_message_add(n, 'in', 'klant@winkel.example', '[]', '[]', 0, 'x', 'dubbel', '', null, '<abc@winkel.example>', null, '[]', 'zakelijk');
 if (r->>'duplicate')::boolean is not true then raise exception 'duplicate message-id must be refused %', r; end if;
 if not public.pasr_mail_message_exists('<abc@winkel.example>') then raise exception 'message exists'; end if;
 if (select unread from public.pasr_mail_threads where number = n) is not true then raise exception 'incoming message = unread'; end if;
 perform pg_temp.expect($q$select public.pasr_mail_message_add(99999999, 'in', '', '[]', '[]', 0, '', '', '', null, null, null, '[]', null)$q$, 'not_found');
 perform pg_temp.expect($q$select public.pasr_mail_message_add(1001, 'raar', '', '[]', '[]', 0, '', '', '', null, null, null, '[]', null)$q$, 'bad_direction');
 -- lijst en tellingen
 r := public.pasr_mail_thread_list('active', null, null, 1, 30);
 if (r->>'total')::int < 2 or jsonb_array_length(r->'items') < 2 then raise exception 'list active %', r; end if;
 if (select (i->>'preview') from jsonb_array_elements(r->'items') i where (i->>'number')::bigint = n) <> 'Hoi, hoe werkt het?' then raise exception 'preview'; end if;
 if (public.pasr_mail_thread_list('active', 'WINKEL', null, 1, 30)->>'total')::int <> 1 then raise exception 'search by email'; end if;
 if (public.pasr_mail_thread_list('active', 'stempel%', null, 1, 30)->>'total')::int <> 0 then raise exception 'wildcards must be escaped'; end if;
 if (public.pasr_mail_thread_list('active', n::text, null, 1, 30)->>'total')::int <> 1 then raise exception 'search by number'; end if;
 if (public.pasr_mail_thread_list('active', null, 'zakelijk', 1, 30)->>'total')::int <> 1 then raise exception 'brand filter'; end if;
 if (public.pasr_mail_thread_list('active', null, null, 1, 1)->'items')::text is null or jsonb_array_length(public.pasr_mail_thread_list('active', null, null, 1, 1)->'items') <> 1 then raise exception 'page size'; end if;
 -- openen markeert gelezen; BCC-adressen komen nergens terug
 r := public.pasr_mail_thread_get(n);
 if (r->'thread'->>'unread')::boolean then raise exception 'thread_get must mark read'; end if;
 if jsonb_array_length(r->'messages') <> 1 or (r->'messages'->0->>'direction') <> 'in' then raise exception 'messages %', r; end if;
 if public.pasr_mail_thread_get(99999999) is not null then raise exception 'unknown thread = null'; end if;
 -- antwoord met BCC-aantal; status
 r := public.pasr_mail_message_add(n, 'out', 'Pasr Zakelijk <zakelijk@pasr.nl>', '["klant@winkel.example"]', '["cc@x.example"]', 3, '[#1001] Re', 'Antwoord', '<p>Antwoord</p>', 'Antwoord',
        '<pasr-ticket-1001.aaaa@pasr.nl>', '<abc@winkel.example>', '["<abc@winkel.example>"]', 'zakelijk', 'pending', null, true);
 if (r->>'id') is null then raise exception 'out message'; end if;
 r := public.pasr_mail_thread_get(n);
 if (r->'thread'->>'status') <> 'pending' or (r->'messages'->1->>'bcc_count')::int <> 3 then raise exception 'out message state %', r; end if;
 if r::text like '%"bcc":%' or exists (select 1 from public.pasr_mail_messages where bcc <> '[]'::jsonb) then raise exception 'bcc addresses must never be stored or returned'; end if;
 r := public.pasr_mail_thread_set(n, 'closed', 'high');
 if r->>'status' <> 'closed' or (select closed_at from public.pasr_mail_threads where number = n) is null then raise exception 'close %', r; end if;
 r := public.pasr_mail_thread_set(n, 'open', null);
 if (select closed_at from public.pasr_mail_threads where number = n) is not null or r->>'priority' <> 'high' then raise exception 'reopen %', r; end if;
 perform pg_temp.expect(format($q$select public.pasr_mail_thread_set(%s, 'raar', null)$q$, n), 'bad_status');
 perform pg_temp.expect(format($q$select public.pasr_mail_thread_set(%s, null, 'raar')$q$, n), 'bad_priority');
 perform pg_temp.expect($q$select public.pasr_mail_thread_set(99999999, 'open', null)$q$, 'not_found');
 -- tickets bij een binnengekomen mail: op nummer en op Message-ID
 r := public.pasr_mail_threads_for(array[n], array['<pasr-ticket-1001.aaaa@pasr.nl>']);
 if jsonb_array_length(r) <> 1 or r->0->'mids'->>0 <> '<pasr-ticket-1001.aaaa@pasr.nl>' then raise exception 'threads_for %', r; end if;
 r := public.pasr_mail_threads_for(array[]::bigint[], array['<pasr-ticket-1001.aaaa@pasr.nl>']);
 if jsonb_array_length(r) <> 1 then raise exception 'threads_for by id only %', r; end if;
 if jsonb_array_length(public.pasr_mail_threads_for(array[]::bigint[], array['<onbekend@x>'])) <> 0 then raise exception 'threads_for unknown'; end if;


 -- meta voor een antwoord, refs van een mail in groepen, terugdraaien, grenzen
 r := public.pasr_mail_message_add(n, 'out', 'Pasr <support@pasr.nl>', '[]', '[]', 120, 'Uitnodiging', 't', '', 'm', '<pasr-ticket-1001.eerste@pasr.nl>', null,
        '["<pasr-ticket-1001.eerste@pasr.nl>", "<pasr-ticket-1001.tweede@pasr.nl>"]', 'pasr', null, null, true);
 r := public.pasr_mail_thread_meta(n);
 if r->>'brand' <> 'zakelijk' or r->>'contact_email' <> 'klant@winkel.example' or jsonb_array_length(r->'ids') <> 3 then raise exception 'thread_meta %', r; end if;
 if public.pasr_mail_thread_meta(99999999) is not null then raise exception 'thread_meta unknown'; end if;
 r := public.pasr_mail_threads_for(array[]::bigint[], array['<pasr-ticket-1001.tweede@pasr.nl>']);
 if jsonb_array_length(r) <> 1 or r->0->'mids'->>0 <> '<pasr-ticket-1001.tweede@pasr.nl>' then raise exception 'threads_for via refs %', r; end if;
 n2 := public.pasr_mail_thread_create('pasr', 'Leeg', 'leeg@x.example', '');
 if not public.pasr_mail_thread_delete_empty(n2) then raise exception 'empty thread must be deleted'; end if;
 if public.pasr_mail_thread_delete_empty(n) then raise exception 'thread with messages must stay'; end if;
 if public.pasr_mail_out_recent(60) < 2 then raise exception 'out_recent'; end if;
 if public.pasr_mail_contact_recent('KLANT@winkel.example', 1) <> 1 then raise exception 'contact_recent'; end if;
 if public.pasr_mail_contact_recent('niemand@x.example', 1) <> 0 then raise exception 'contact_recent none'; end if;

 -- ---- bijlagen: max. 10 MB per bericht ----
 b64 := repeat('QUJD', 2000000);   -- 6 MB
 att := public.pasr_mail_attach(mid, null, 'groot.bin', 'application/octet-stream', b64);
 if (att->>'size')::int <> 6000000 then raise exception 'attachment size %', att; end if;
 perform pg_temp.expect(format($q$select public.pasr_mail_attach(%L::uuid, null, 'nog-groter.bin', 'x/y', repeat('QUJD', 2000000))$q$, mid), 'too_large');
 att := public.pasr_mail_attach(mid, null, 'klein.txt', 'text/plain', 'SGFsbG8=');
 r := public.pasr_mail_attachment_get((att->>'id')::uuid);
 if r->>'data_b64' <> 'SGFsbG8=' or r->>'name' <> 'klein.txt' then raise exception 'attachment get %', r; end if;
 if jsonb_array_length((select attachments from public.pasr_mail_messages where id = mid)) <> 2 then raise exception 'attachments meta on message'; end if;
 if public.pasr_mail_thread_get(n)::text like '%data_b64%' then raise exception 'thread_get must not return bytes'; end if;
 perform pg_temp.expect($q$select public.pasr_mail_attach(null, null, 'a', 'b', 'QUJD')$q$, 'bad_target');

 -- ---- IMAP-ronde: lease en logboek ----
 if not public.pasr_mail_sync_lock(60) then raise exception 'first lock'; end if;
 if public.pasr_mail_sync_lock(60) then raise exception 'second lock must fail'; end if;
 perform public.pasr_mail_sync_done(5, 2, null, 42, 7);
 if not public.pasr_mail_sync_lock(60) then raise exception 'lock free after done'; end if;
 perform public.pasr_mail_sync_done(0, 0, 'mislukt', null, null);
 if (public.pasr_mail_sync_state()->>'last_error') <> 'mislukt' or (public.pasr_mail_sync_state()->>'last_uid')::int <> 42 then raise exception 'sync state %', public.pasr_mail_sync_state(); end if;
 perform public.pasr_mail_log_add('pasr', 1, 7, 'imported', n);
 perform public.pasr_mail_log_add('pasr', 2, 7, 'error', null);
 perform public.pasr_mail_log_add('pasr', 3, 7, 'rejected:rate_limited', null);
 a := (select array_agg(x::text) from unnest(public.pasr_mail_log_done('pasr', 7, array[1, 2, 3, 4])) x);
 if a <> array['1'] then raise exception 'log_done must skip retryable results, got %', a; end if;

 -- ---- campagnes ----
 r := public.pasr_mail_campaign_create('pasr', 'users', 'Nieuwsbrief november', '# Hoi {{voornaam}}', req, 5);
 id1 := (r->>'id')::bigint;
 if (r->>'created')::boolean is not true or r->>'status' <> 'sending' then raise exception 'campaign create %', r; end if;
 r := public.pasr_mail_campaign_create('pasr', 'users', 'Nieuwsbrief november', '# Hoi', req, 99);
 if (r->>'created')::boolean or (r->>'id')::bigint <> id1 or (r->>'recipients')::int <> 5 then raise exception 'request_id must make it idempotent %', r; end if;
 perform pg_temp.expect($q$select public.pasr_mail_campaign_create('anders', 'users', 's', '', gen_random_uuid(), 1)$q$, 'bad_request');
 if not public.pasr_mail_campaign_claim(id1, 60) then raise exception 'claim'; end if;
 if public.pasr_mail_campaign_claim(id1, 60) then raise exception 'second claim must fail'; end if;
 r := public.pasr_mail_campaign_progress(id1, array[repeat('a', 26), repeat('b', 26), 'geen-hash'], 1, false);
 if (r->>'sent')::int <> 2 or (r->>'failed')::int <> 1 or r->>'status' <> 'sending' then raise exception 'progress %', r; end if;
 r := public.pasr_mail_campaign_progress(id1, array[repeat('a', 26), repeat('c', 26)], 0, false);
 if (r->>'sent')::int <> 3 then raise exception 'a hash must count once, got %', r; end if;
 if array_length(public.pasr_mail_campaign_sent_hashes(id1), 1) <> 3 then raise exception 'sent hashes'; end if;
 if not (id1 = any (public.pasr_mail_campaign_due())) then raise exception 'released campaign must be due'; end if;
 r := public.pasr_mail_campaign_progress(id1, '{}', 2, false, 0, array[repeat('d', 26)]);
 if (r->>'sent')::int <> 3 or (r->>'failed')::int <> 3 or array_length(public.pasr_mail_campaign_sent_hashes(id1), 1) <> 4 then raise exception 'failed hashes must be skipped, not counted %', r; end if;
 r := public.pasr_mail_campaign_progress(id1, '{}', 0, true);
 if r->>'status' <> 'sent' or (select finished_at from public.pasr_mail_campaigns where id = id1) is null then raise exception 'finish %', r; end if;
 if array_length(public.pasr_mail_campaign_sent_hashes(id1), 1) is not null then raise exception 'sent hashes must be cleaned up'; end if;
 perform pg_temp.expect(format('select public.pasr_mail_campaign_cancel(%s)', id1), 'not_cancellable');
 r := public.pasr_mail_campaign_create('zakelijk', 'owners', 'Uitnodiging', '', gen_random_uuid(), 2);
 r := public.pasr_mail_campaign_cancel((r->>'id')::bigint);
 if r->>'status' <> 'cancelled' then raise exception 'cancel %', r; end if;
 perform pg_temp.expect('select public.pasr_mail_campaign_cancel(99999999)', 'not_found');
 -- uitnodigingen aan een lijst: meteen klaar, aantallen zonder adressen
 r := public.pasr_mail_campaign_create('zakelijk', 'list', 'Kennismaken', 'Hoi', gen_random_uuid(), 4);
 r := public.pasr_mail_campaign_progress((r->>'id')::bigint, '{}', 1, false, 3);
 if (r->>'sent')::int <> 3 or (r->>'failed')::int <> 1 or r->>'status' <> 'sent' then raise exception 'list campaign %', r; end if;
 if jsonb_array_length(public.pasr_mail_campaign_list()) < 3 then raise exception 'campaign list'; end if;
 if public.pasr_mail_campaign_list()::text like '%body_md%' then raise exception 'campaign list must not return bodies'; end if;
 -- bijlage bij een campagne
 r := public.pasr_mail_campaign_create('pasr', 'users', 'Met bijlage', 'x', gen_random_uuid(), 1);
 att := public.pasr_mail_attach(null, (r->>'id')::bigint, 'flyer.pdf', 'application/pdf', 'SGFsbG8=');
 if jsonb_array_length(public.pasr_mail_campaign_attachments((r->>'id')::bigint)) <> 1 then raise exception 'campaign attachment'; end if;

 -- ---- cron ----
 perform public.pasr_mail_poll_kick();   -- zonder pasr_admin_config of cron: waarschuwing, geen fout
end $$;

-- opnieuw draaien mag (idempotent)
select 'beheer_mail_smoke ok' as result;
