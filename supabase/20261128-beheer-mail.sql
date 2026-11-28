-- ============================================================================================================
-- Pasr beheer › Mail (28-11-2026): inbox met tickets, mails versturen als Pasr of Pasr Zakelijk, nieuwsbrieven.
-- Idempotent; draait in de workflow Backend na 20261127-antibot-forms.sql. Uitleg: docs/beheer-mail.md.
--
-- Alles staat achter de service role (de functie mail, die alleen de functie admin en de cron aanroepen). RLS staat aan en
-- alles is ingetrokken voor anon en authenticated, behalve het afmelden met de code uit een mail (pasr_mail_news_unsubscribe,
-- pasr_mail_news_unsub_email en de uitgebreide pasr_mail_unsubscribe).
--
-- Privacy: het beheer krijgt van de doelgroepen alleen aantallen. BCC-adressen worden niet bewaard (alleen het aantal);
-- bij een afmelding bewaren we alleen een gezouten hash van het e-mailadres.
-- ============================================================================================================

-- ------------------------------------------------------------------------------------------- tickets
create table if not exists public.pasr_mail_threads (
  id uuid primary key default gen_random_uuid(),
  number bigint generated always as identity (start with 1001) unique,
  brand text not null default 'pasr' check (brand in ('pasr', 'zakelijk')),
  subject text not null check (char_length(subject) between 1 and 200),
  status text not null default 'new' check (status in ('new', 'open', 'pending', 'closed')),
  priority text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  contact_email text not null default '' check (char_length(contact_email) <= 254),
  contact_name text not null default '' check (char_length(contact_name) <= 80),
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  unread boolean not null default true,
  closed_at timestamptz
);
create index if not exists pasr_mail_threads_list on public.pasr_mail_threads (status, last_message_at desc);
create index if not exists pasr_mail_threads_contact on public.pasr_mail_threads (contact_email, created_at);

create table if not exists public.pasr_mail_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.pasr_mail_threads (id) on delete cascade,
  direction text not null check (direction in ('in', 'out', 'note')),
  from_addr text not null default '' check (char_length(from_addr) <= 300),
  to_addrs jsonb not null default '[]'::jsonb,
  cc jsonb not null default '[]'::jsonb,
  -- BCC-adressen worden nooit bewaard: deze kolom blijft leeg, het aantal staat in bcc_count
  bcc jsonb not null default '[]'::jsonb,
  bcc_count integer not null default 0 check (bcc_count >= 0),
  subject text not null default '' check (char_length(subject) <= 300),
  body_text text not null default '' check (char_length(body_text) <= 100000),
  body_html text not null default '' check (char_length(body_html) <= 300000),
  body_md text check (body_md is null or char_length(body_md) <= 100000),
  message_id text unique check (message_id is null or char_length(message_id) <= 300),
  in_reply_to text check (in_reply_to is null or char_length(in_reply_to) <= 300),
  refs jsonb not null default '[]'::jsonb,
  brand text check (brand is null or brand in ('pasr', 'zakelijk')),
  attachments jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default clock_timestamp(),   -- clock_timestamp: berichten in één transactie blijven op volgorde
  sent_at timestamptz,
  error text check (error is null or char_length(error) <= 200)
);
create index if not exists pasr_mail_messages_thread on public.pasr_mail_messages (thread_id, created_at);

-- campagnes (nieuwsbrieven en uitnodigingen)
create table if not exists public.pasr_mail_campaigns (
  id bigint generated always as identity primary key,
  brand text not null check (brand in ('pasr', 'zakelijk')),
  audience text not null check (audience in ('users', 'owners', 'list')),
  subject text not null check (char_length(subject) between 1 and 200),
  body_md text not null default '' check (char_length(body_md) <= 100000),
  status text not null default 'draft' check (status in ('draft', 'sending', 'sent', 'cancelled')),
  recipients integer not null default 0,
  sent integer not null default 0,
  failed integer not null default 0,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  request_id uuid unique,
  lock_until timestamptz
);

-- bijlagen: bij een bericht in een ticket, of bij een campagne (bytes; max. 20 MB per mail, zie pasr_mail_attach)
create table if not exists public.pasr_mail_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid references public.pasr_mail_messages (id) on delete cascade,
  campaign_id bigint references public.pasr_mail_campaigns (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 200),
  type text not null default 'application/octet-stream' check (char_length(type) <= 120),
  size integer not null check (size between 0 and 20971520),
  data bytea not null,
  created_at timestamptz not null default now(),
  check (message_id is not null or campaign_id is not null)
);
create index if not exists pasr_mail_attachments_message on public.pasr_mail_attachments (message_id);
create index if not exists pasr_mail_attachments_campaign on public.pasr_mail_attachments (campaign_id);

-- Welke ontvangers van een campagne al een mail kregen (alleen de eerste 26 tekens van de gezouten hash), om verder te
-- kunnen waar een ronde stopte. Gaat weg zodra de campagne klaar is.
create table if not exists public.pasr_mail_campaign_sent (
  campaign_id bigint not null references public.pasr_mail_campaigns (id) on delete cascade,
  email_hash text not null check (email_hash ~ '^[0-9a-f]{26}$'),
  primary key (campaign_id, email_hash)
);

-- IMAP-import: één rij (laatste ronde en wat er gebeurde) en een kort logboek met alleen codes (geen adressen of onderwerpen)
create table if not exists public.pasr_mail_sync (
  id integer primary key default 1 check (id = 1),
  last_uid bigint,
  uidvalidity bigint,
  last_run timestamptz,
  last_error text check (last_error is null or char_length(last_error) <= 300),
  fetched integer not null default 0,
  imported integer not null default 0,
  lock_until timestamptz,
  error_uid bigint,
  error_count integer not null default 0
);
insert into public.pasr_mail_sync (id) values (1) on conflict do nothing;
create table if not exists public.pasr_mail_inbox_log (
  id bigint generated always as identity primary key,
  box text not null default 'pasr' check (box in ('pasr', 'zakelijk')),
  uid bigint not null,
  uidvalidity bigint,
  result text not null check (char_length(result) <= 60),
  ticket_number bigint,
  at timestamptz not null default now()
);
create index if not exists pasr_mail_inbox_log_uid on public.pasr_mail_inbox_log (box, uidvalidity, uid);
create index if not exists pasr_mail_inbox_log_at on public.pasr_mail_inbox_log (at);

-- Afmeldingen voor nieuwsbrieven en uitnodigingen. Geen e-mailadres: de eerste 26 tekens van sha256(zout|adres). De afmeldcode
-- in de mail is hash(26) + scope(2) + controle(4) en is dus voor elk adres af te leiden zonder per ontvanger iets op te slaan.
create table if not exists public.pasr_mail_optout (
  email_hash text primary key check (email_hash ~ '^[0-9a-f]{26}$'),
  scope text not null check (scope in ('news-users', 'news-owners', 'all')),
  created_at timestamptz not null default now(),
  token text unique check (token is null or token ~ '^[0-9a-f]{32}$')
);

do $$
begin
  if to_regclass('public.pasr_admin_config') is not null then
    alter table public.pasr_admin_config add column if not exists mail_url text;
  end if;
end $$;

alter table public.pasr_mail_threads enable row level security;
alter table public.pasr_mail_messages enable row level security;
alter table public.pasr_mail_campaigns enable row level security;
alter table public.pasr_mail_attachments enable row level security;
alter table public.pasr_mail_campaign_sent enable row level security;
alter table public.pasr_mail_sync enable row level security;
alter table public.pasr_mail_inbox_log enable row level security;
alter table public.pasr_mail_optout enable row level security;
revoke all on public.pasr_mail_threads, public.pasr_mail_messages, public.pasr_mail_campaigns, public.pasr_mail_attachments,
  public.pasr_mail_campaign_sent, public.pasr_mail_sync, public.pasr_mail_inbox_log, public.pasr_mail_optout
  from public, anon, authenticated;

-- ------------------------------------------------------------------------------------------- zout, hashes, afmeldcodes
create or replace function public.pasr_mail_salt() returns text
language plpgsql stable security definer set search_path = '' as $$
declare s text := '';
begin
  if to_regclass('public.pasr_secret') is not null then
    begin
      execute 'select coalesce(hook_secret, '''') from public.pasr_secret where id = 1' into s;
    exception when others then s := '';
    end;
  end if;
  return coalesce(s, '');
end $$;

-- eerste 26 tekens van sha256(zout|mailnews|adres)
create or replace function public.pasr_mail_hash(p_email text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare salt text := public.pasr_mail_salt();
begin
  if salt = '' then raise exception 'no_secret' using errcode = '22023'; end if;
  return left(encode(sha256(convert_to(salt || '|mailnews|' || lower(btrim(coalesce(p_email, ''))), 'UTF8')), 'hex'), 26);
end $$;

create or replace function public.pasr_mail_scope_code(p_scope text) returns text
language sql immutable set search_path = '' as $$
  select case p_scope when 'news-users' then '01' when 'news-owners' then '02' when 'all' then '03' else null end;
$$;

-- afmeldcode: hash(26) + scope(2) + controle(4)
create or replace function public.pasr_mail_token_of(p_hash text, p_scope text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare code text := public.pasr_mail_scope_code(p_scope); salt text := public.pasr_mail_salt();
begin
  if code is null then raise exception 'bad_scope' using errcode = '22023'; end if;
  if salt = '' then raise exception 'no_secret' using errcode = '22023'; end if;
  return p_hash || code || left(encode(sha256(convert_to(salt || '|mailtoken|' || p_hash || code, 'UTF8')), 'hex'), 4);
end $$;

create or replace function public.pasr_mail_news_token(p_email text, p_scope text) returns text
language sql stable security definer set search_path = '' as $$
  select public.pasr_mail_token_of(public.pasr_mail_hash(p_email), p_scope);
$$;

-- Afmelden met de code uit de mail. Ongeldige of vervalste code: {ok:false}. Een bestaande afmelding voor een andere
-- lijst wordt 'all'.
create or replace function public.pasr_mail_news_unsubscribe(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare h text; code text; sc text; want text;
begin
  if coalesce(p_token, '') !~ '^[0-9a-f]{32}$' then return jsonb_build_object('ok', false); end if;
  h := left(p_token, 26); code := substr(p_token, 27, 2);
  sc := case code when '01' then 'news-users' when '02' then 'news-owners' when '03' then 'all' else null end;
  if sc is null or public.pasr_mail_salt() = '' then return jsonb_build_object('ok', false); end if;
  want := public.pasr_mail_token_of(h, sc);
  if want <> p_token then return jsonb_build_object('ok', false); end if;
  insert into public.pasr_mail_optout as o (email_hash, scope, token) values (h, sc, p_token)
    on conflict (email_hash) do update set
      scope = case when o.scope = excluded.scope then o.scope else 'all' end,
      token = excluded.token;
  return jsonb_build_object('ok', true, 'removed', true, 'scope', sc);
end $$;

-- Afmelden met het e-mailadres (de link in een mail aan meerdere ontvangers via BCC kent geen persoonlijke code).
create or replace function public.pasr_mail_news_unsub_email(p_email text, p_scope text, p_hp text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e text := lower(btrim(coalesce(p_email, ''))); h text;
begin
  if coalesce(p_hp, '') <> '' then return jsonb_build_object('ok', true, 'removed', false); end if;   -- honeypot: doen alsof
  if p_scope not in ('news-users', 'news-owners', 'all') or e !~ '^[^\s@<>()",;:\\\[\]]{1,64}@[A-Za-z0-9.-]{1,200}\.[A-Za-z]{2,}$' or char_length(e) > 254 then
    return jsonb_build_object('ok', false);
  end if;
  if to_regprocedure('public.pasr_web_rate_hit(text,integer,integer)') is not null and to_regclass('public.pasr_secret') is not null then
    perform public.pasr_web_rate_hit('mailnews', 20, 50000);
  end if;
  h := public.pasr_mail_hash(e);
  insert into public.pasr_mail_optout as o (email_hash, scope) values (h, p_scope)
    on conflict (email_hash) do update set scope = case when o.scope = excluded.scope then o.scope else 'all' end;
  return jsonb_build_object('ok', true, 'removed', true, 'scope', p_scope);
end $$;

-- Het bestaande pasr_mail_unsubscribe (herinneringen, pasr.nl/afmelden/ en List-Unsubscribe) herkent nu ook de code van
-- een nieuwsbrief of uitnodiging. Eerst de herinneringen (zoals altijd); anders de nieuwe code; een onbekende maar
-- goed gevormde code blijft {ok:true, removed:false}.
create or replace function public.pasr_mail_unsubscribe(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int := 0; r jsonb;
begin
  if coalesce(p_token, '') !~ '^[0-9a-f]{32}$' then return jsonb_build_object('ok', false); end if;
  if to_regclass('public.pasr_mail_prefs') is not null then
    execute 'delete from public.pasr_mail_prefs where unsub_token = $1' using p_token;
    get diagnostics n = row_count;
  end if;
  if n > 0 then return jsonb_build_object('ok', true, 'removed', true, 'kind', 'reminders'); end if;
  r := public.pasr_mail_news_unsubscribe(p_token);
  if coalesce((r->>'ok')::boolean, false) then return r || jsonb_build_object('kind', 'news'); end if;
  return jsonb_build_object('ok', true, 'removed', false);
end $$;
revoke all on function public.pasr_mail_unsubscribe(text) from public;
grant execute on function public.pasr_mail_unsubscribe(text) to anon, authenticated;

-- ------------------------------------------------------------------------------------------- doelgroepen
-- users = bevestigde Pasr-accounts (auth.users); owners = eigenaren en medewerkers (pasr_business_staff, aangenomen en niet
-- ingetrokken) en eigenaren (pasr_businesses.owner) van een goedgekeurde zaak, met bevestigd e-mailadres. Afgemelden vallen weg.
-- Met de afmeldcode per ontvanger. Alleen de service role; het beheer krijgt alleen aantallen te zien.
create or replace function public.pasr_mail_audience(p_audience text)
returns table (email text, first_name text, token text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare sc text;
begin
  if p_audience = 'users' then sc := 'news-users';
  elsif p_audience = 'owners' then sc := 'news-owners';
  else raise exception 'bad_audience' using errcode = '22023';
  end if;
  if public.pasr_mail_salt() = '' then raise exception 'no_secret' using errcode = '22023'; end if;
  return query
    select x.email, x.first_name, public.pasr_mail_token_of(x.h, sc)
    from (
      select distinct on (a.email) a.email, a.first_name, public.pasr_mail_hash(a.email) as h
      from (
        select lower(btrim(u.email)) as email, left(btrim(coalesce(u.raw_user_meta_data->>'first_name', '')), 40) as first_name
        from auth.users u
        where u.email is not null and u.email_confirmed_at is not null
          and (p_audience = 'users'
               or u.id in (select b.owner from public.pasr_businesses b where b.status = 'approved')
               or u.id in (select s.user_id from public.pasr_business_staff s join public.pasr_businesses b2 on b2.id = s.business_id
                            where s.user_id is not null and s.revoked_at is null and b2.status = 'approved'))
      ) a
      where a.email ~ '^[^\s@<>()",;:\\\[\]]{1,64}@[A-Za-z0-9.-]{1,200}\.[A-Za-z]{2,}$'
      order by a.email
    ) x
    where not exists (select 1 from public.pasr_mail_optout o where o.email_hash = x.h and o.scope in ('all', sc))
    order by x.email;
end $$;

create or replace function public.pasr_mail_audience_count(p_audience text) returns integer
language sql stable security definer set search_path = '' as $$
  select count(*)::integer from public.pasr_mail_audience(p_audience);
$$;

-- Handmatig opgegeven adressen (uitnodigingen): de afgemelden eruit; p_scope = news-users of news-owners.
create or replace function public.pasr_mail_list_tokens(p_emails text[], p_scope text)
returns table (email text, token text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  if p_scope not in ('news-users', 'news-owners') then raise exception 'bad_scope' using errcode = '22023'; end if;
  return query
    select e.email, public.pasr_mail_token_of(e.h, p_scope)
    from (select distinct lower(btrim(v)) as email, public.pasr_mail_hash(v) as h from unnest(p_emails) as v where btrim(coalesce(v, '')) <> '') e
    where not exists (select 1 from public.pasr_mail_optout o where o.email_hash = e.h and o.scope in ('all', p_scope));
end $$;

-- ------------------------------------------------------------------------------------------- tickets: lezen en schrijven
create or replace function public.pasr_mail_counts() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'new', count(*) filter (where status = 'new'), 'open', count(*) filter (where status = 'open'),
    'pending', count(*) filter (where status = 'pending'), 'closed', count(*) filter (where status = 'closed'),
    'unread', count(*) filter (where unread and status <> 'closed'))
  from public.pasr_mail_threads;
$$;

drop function if exists public.pasr_mail_thread_list(text, text, text, integer, integer);
-- p_box: 'inbox' (standaard: de statusfilter, standaard actief), 'sent' (tickets met minstens één uitgaand bericht, nieuwste uitgaande eerst) of 'all'.
-- Per rij: last_direction ('in'|'out'), sent_at, to_preview, to_count, cc_count, bcc_count en attachments van het laatste uitgaande bericht (nooit BCC-adressen).
create or replace function public.pasr_mail_thread_list(p_status text default 'active', p_q text default null, p_brand text default null,
                                                        p_page integer default 1, p_size integer default 30, p_box text default 'inbox') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare size integer := greatest(1, least(coalesce(p_size, 30), 100)); page integer := greatest(1, coalesce(p_page, 1));
        q text := nullif(btrim(coalesce(p_q, '')), ''); pat text; total integer; items jsonb;
        box text := case when p_box in ('sent', 'all') then p_box else 'inbox' end;
begin
  if q is not null then pat := '%' || replace(replace(replace(left(q, 100), '\', '\\'), '%', '\%'), '_', '\_') || '%'; end if;
  select count(*) into total from public.pasr_mail_threads t
   where (p_status = 'all' or (p_status = 'active' and t.status <> 'closed') or t.status = p_status)
     and (p_brand is null or t.brand = p_brand)
     and (box <> 'sent' or exists (select 1 from public.pasr_mail_messages o where o.thread_id = t.id and o.direction = 'out'))
     and (pat is null or t.subject ilike pat or t.contact_name ilike pat or t.contact_email ilike pat
          or ('#' || t.number::text) = q or t.number::text = q);
  select coalesce(jsonb_agg(row_to_json(r)::jsonb order by case when box = 'sent' then r.sent_at else r.last_message_at end desc nulls last, r.number desc), '[]'::jsonb) into items from (
    select t.number, t.subject, t.status, t.priority, t.brand, t.contact_name, t.contact_email, t.last_message_at, t.unread,
           coalesce(ln.preview, '') as preview, ln.direction as last_direction,
           lo.created_at as sent_at, lo.to_count, lo.cc_count, lo.bcc_count, lo.attachments,
           case when lo.id is null then null
                when lo.to_count > 0 then lo.to_first
                when lo.bcc_count > 0 then lo.bcc_count::text || case when lo.bcc_count = 1 then ' ontvanger' else ' ontvangers' end
                else lo.cc_first end as to_preview
      from public.pasr_mail_threads t
      left join lateral (select m.direction, left(regexp_replace(m.body_text, '\s+', ' ', 'g'), 140) as preview
                           from public.pasr_mail_messages m where m.thread_id = t.id and m.direction <> 'note'
                          order by m.created_at desc, m.id desc limit 1) ln on true
      left join lateral (select m.id, m.created_at, jsonb_array_length(m.to_addrs) as to_count, jsonb_array_length(m.cc) as cc_count, m.bcc_count,
                                jsonb_array_length(m.attachments) as attachments, left(m.to_addrs->>0, 254) as to_first, left(m.cc->>0, 254) as cc_first
                           from public.pasr_mail_messages m where m.thread_id = t.id and m.direction = 'out'
                          order by m.created_at desc, m.id desc limit 1) lo on true
     where (p_status = 'all' or (p_status = 'active' and t.status <> 'closed') or t.status = p_status)
       and (p_brand is null or t.brand = p_brand)
       and (box <> 'sent' or lo.id is not null)
       and (pat is null or t.subject ilike pat or t.contact_name ilike pat or t.contact_email ilike pat
            or ('#' || t.number::text) = q or t.number::text = q)
     order by case when box = 'sent' then lo.created_at else t.last_message_at end desc nulls last, t.number desc offset (page - 1) * size limit size
  ) r;
  return jsonb_build_object('total', total, 'page', page, 'box', box, 'items', items, 'counts', public.pasr_mail_counts());
end $$;

-- Eén ticket met berichten (zonder bijlage-bytes en zonder BCC-adressen); markeert het als gelezen.
create or replace function public.pasr_mail_thread_get(p_number bigint, p_mark_read boolean default true) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t public.pasr_mail_threads; msgs jsonb;
begin
  select * into t from public.pasr_mail_threads where number = p_number;
  if t.id is null then return null; end if;
  if p_mark_read and t.unread then
    update public.pasr_mail_threads set unread = false where id = t.id;
    t.unread := false;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', m.id, 'direction', m.direction, 'from', m.from_addr, 'to', m.to_addrs, 'cc', m.cc, 'bcc_count', m.bcc_count,
      'subject', m.subject, 'body_html', m.body_html, 'body_text', m.body_text, 'attachments', m.attachments,
      'brand', m.brand, 'created_at', m.created_at, 'error', m.error) order by m.created_at, m.id), '[]'::jsonb)
    into msgs from public.pasr_mail_messages m where m.thread_id = t.id;
  return jsonb_build_object('thread', jsonb_build_object(
      'number', t.number, 'subject', t.subject, 'status', t.status, 'priority', t.priority, 'brand', t.brand,
      'contact_name', t.contact_name, 'contact_email', t.contact_email, 'created_at', t.created_at,
      'last_message_at', t.last_message_at, 'unread', t.unread, 'closed_at', t.closed_at),
    'messages', msgs);
end $$;

create or replace function public.pasr_mail_thread_create(p_brand text, p_subject text, p_email text, p_name text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare n bigint;
begin
  insert into public.pasr_mail_threads (brand, subject, contact_email, contact_name)
  values (case when p_brand = 'zakelijk' then 'zakelijk' else 'pasr' end, left(coalesce(nullif(btrim(p_subject), ''), '(geen onderwerp)'), 200),
          left(lower(btrim(coalesce(p_email, ''))), 254), left(btrim(coalesce(p_name, '')), 80))
  returning number into n;
  return n;
end $$;

-- Een bericht toevoegen (in, out of note) en het ticket bijwerken. Dubbel Message-ID: {id:null, duplicate:true}.
-- in -> ongelezen; out/note -> gelezen. p_status leeg = status laten staan.
create or replace function public.pasr_mail_message_add(
  p_number bigint, p_direction text, p_from text, p_to jsonb, p_cc jsonb, p_bcc_count integer, p_subject text, p_text text,
  p_html text, p_md text, p_message_id text, p_in_reply_to text, p_refs jsonb, p_brand text, p_status text default null,
  p_error text default null, p_sent boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t public.pasr_mail_threads; mid uuid; st text;
begin
  if p_direction not in ('in', 'out', 'note') then raise exception 'bad_direction' using errcode = '22023'; end if;
  select * into t from public.pasr_mail_threads where number = p_number for update;
  if t.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  insert into public.pasr_mail_messages (thread_id, direction, from_addr, to_addrs, cc, bcc_count, subject, body_text, body_html, body_md,
      message_id, in_reply_to, refs, brand, error, sent_at)
  values (t.id, p_direction, left(coalesce(p_from, ''), 300), coalesce(p_to, '[]'::jsonb), coalesce(p_cc, '[]'::jsonb),
      greatest(0, coalesce(p_bcc_count, 0)), left(coalesce(p_subject, ''), 300), left(coalesce(p_text, ''), 100000),
      left(coalesce(p_html, ''), 300000), left(p_md, 100000), nullif(left(coalesce(p_message_id, ''), 300), ''),
      left(p_in_reply_to, 300), coalesce(p_refs, '[]'::jsonb), p_brand, left(p_error, 200), case when p_sent then now() end)
  on conflict (message_id) do nothing returning id into mid;
  if mid is null then return jsonb_build_object('id', null, 'duplicate', true); end if;
  st := case when p_status in ('new', 'open', 'pending', 'closed') then p_status else t.status end;
  update public.pasr_mail_threads set status = st, last_message_at = now(),
         unread = case when p_direction = 'in' then true else false end,
         closed_at = case when st = 'closed' then coalesce(t.closed_at, now()) else null end
   where id = t.id;
  return jsonb_build_object('id', mid, 'duplicate', false);
end $$;

create or replace function public.pasr_mail_thread_set(p_number bigint, p_status text default null, p_priority text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t public.pasr_mail_threads;
begin
  select * into t from public.pasr_mail_threads where number = p_number for update;
  if t.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if p_status is not null and p_status not in ('new', 'open', 'pending', 'closed') then raise exception 'bad_status' using errcode = '22023'; end if;
  if p_priority is not null and p_priority not in ('low', 'normal', 'high', 'urgent') then raise exception 'bad_priority' using errcode = '22023'; end if;
  update public.pasr_mail_threads set status = coalesce(p_status, status), priority = coalesce(p_priority, priority),
         closed_at = case when coalesce(p_status, status) = 'closed' then coalesce(closed_at, now()) else null end
   where id = t.id returning * into t;
  return jsonb_build_object('number', t.number, 'status', t.status, 'priority', t.priority);
end $$;

-- Tickets bij een binnengekomen mail: op nummer en op opgeslagen Message-ID's van onze eigen mails (message_id of de
-- refs van een bericht met meer Message-ID's, bv. een mail in groepen van 50 BCC). mids = welke van de gevraagde ID's bij het ticket horen.
create or replace function public.pasr_mail_threads_for(p_numbers bigint[], p_ids text[]) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('number', x.number, 'email', x.contact_email, 'status', x.status, 'brand', x.brand,
           'mids', coalesce((select jsonb_agg(distinct u.v)
                               from public.pasr_mail_messages m
                               cross join lateral (select m.message_id as v union all select jsonb_array_elements_text(m.refs)) u
                              where m.thread_id = x.id and u.v = any (coalesce(p_ids, '{}'::text[]))), '[]'::jsonb))), '[]'::jsonb)
  from (
    select distinct t.* from public.pasr_mail_threads t
     where t.number = any (coalesce(p_numbers, '{}'::bigint[]))
        or t.id in (select m2.thread_id from public.pasr_mail_messages m2
                     where m2.message_id = any (coalesce(p_ids, '{}'::text[])) or m2.refs ?| coalesce(p_ids, '{}'::text[]))
     limit 10
  ) x;
$$;

-- Wat een antwoord nodig heeft: merk, contact, onderwerp, status en de laatste Message-ID's (voor In-Reply-To en References).
create or replace function public.pasr_mail_thread_meta(p_number bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('number', t.number, 'brand', t.brand, 'status', t.status, 'subject', t.subject, 'contact_email', t.contact_email,
           'contact_name', t.contact_name,
           'ids', coalesce((select jsonb_agg(z.mid order by z.at) from (
                   select m.message_id as mid, m.created_at as at from public.pasr_mail_messages m
                    where m.thread_id = t.id and m.message_id is not null order by m.created_at desc limit 20) z), '[]'::jsonb))
    from public.pasr_mail_threads t where t.number = p_number;
$$;

-- Terugdraaien van een ticket zonder berichten (een dubbele Message-ID tijdens het aanmaken).
create or replace function public.pasr_mail_thread_delete_empty(p_number bigint) returns boolean
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  delete from public.pasr_mail_threads t where t.number = p_number and not exists (select 1 from public.pasr_mail_messages m where m.thread_id = t.id);
  get diagnostics n = row_count;
  return n > 0;
end $$;

-- Voor de grenzen: uitgaande berichten in de laatste p_minutes minuten, en nieuwe tickets van één afzender in de laatste p_hours uur.
create or replace function public.pasr_mail_out_recent(p_minutes integer) returns integer
language sql stable security definer set search_path = '' as $$
  select count(*)::integer from public.pasr_mail_messages where direction = 'out' and created_at > now() - make_interval(mins => greatest(1, coalesce(p_minutes, 60)));
$$;
create or replace function public.pasr_mail_contact_recent(p_email text, p_hours integer) returns integer
language sql stable security definer set search_path = '' as $$
  select count(*)::integer from public.pasr_mail_threads
   where contact_email = lower(btrim(coalesce(p_email, ''))) and created_at > now() - make_interval(hours => greatest(1, coalesce(p_hours, 1)));
$$;

create or replace function public.pasr_mail_message_exists(p_message_id text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.pasr_mail_messages where message_id = p_message_id);
$$;

-- Bijlage bij een bericht of campagne, als base64 (geen hex-verdubbeling). Max. 20 MB per bericht (of campagne) in totaal.
create or replace function public.pasr_mail_attach(p_message uuid, p_campaign bigint, p_name text, p_type text, p_b64 text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare d bytea; used bigint; aid uuid; meta jsonb;
begin
  if (p_message is null) = (p_campaign is null) then raise exception 'bad_target' using errcode = '22023'; end if;
  d := decode(coalesce(p_b64, ''), 'base64');
  select coalesce(sum(a.size), 0) into used from public.pasr_mail_attachments a
   where (p_message is not null and a.message_id = p_message) or (p_campaign is not null and a.campaign_id = p_campaign);
  if used + octet_length(d) > 20971520 then raise exception 'too_large' using errcode = '22023'; end if;
  insert into public.pasr_mail_attachments (message_id, campaign_id, name, type, size, data)
  values (p_message, p_campaign, left(coalesce(nullif(btrim(p_name), ''), 'bijlage'), 200), left(coalesce(p_type, 'application/octet-stream'), 120), octet_length(d), d)
  returning id into aid;
  meta := jsonb_build_object('id', aid, 'name', left(coalesce(nullif(btrim(p_name), ''), 'bijlage'), 200),
                             'type', left(coalesce(p_type, 'application/octet-stream'), 120), 'size', octet_length(d));
  if p_message is not null then
    update public.pasr_mail_messages set attachments = attachments || jsonb_build_array(meta) where id = p_message;
  end if;
  return meta;
end $$;

create or replace function public.pasr_mail_attachment_get(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('name', a.name, 'type', a.type, 'size', a.size, 'data_b64', encode(a.data, 'base64'))
    from public.pasr_mail_attachments a where a.id = p_id;
$$;
create or replace function public.pasr_mail_campaign_attachments(p_campaign bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('name', a.name, 'type', a.type, 'data_b64', replace(encode(a.data, 'base64'), E'\n', '')) order by a.created_at), '[]'::jsonb)
    from public.pasr_mail_attachments a where a.campaign_id = p_campaign;
$$;

-- ------------------------------------------------------------------------------------------- IMAP: ronde en logboek
-- Nooit twee rondes tegelijk (cron en de knop "Nu ophalen"): korte lease.
create or replace function public.pasr_mail_sync_lock(p_seconds integer default 120) returns boolean
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  insert into public.pasr_mail_sync (id) values (1) on conflict do nothing;
  update public.pasr_mail_sync set lock_until = now() + make_interval(secs => greatest(10, least(coalesce(p_seconds, 120), 600)))
   where id = 1 and (lock_until is null or lock_until < now());
  get diagnostics n = row_count;
  return n > 0;
end $$;

create or replace function public.pasr_mail_sync_done(p_fetched integer, p_imported integer, p_error text, p_uid bigint, p_uidvalidity bigint,
                                                      p_error_uid bigint default null, p_error_count integer default 0) returns void
language sql security definer set search_path = '' as $$
  update public.pasr_mail_sync set last_run = now(), fetched = coalesce(p_fetched, 0), imported = coalesce(p_imported, 0),
         last_error = left(p_error, 300), last_uid = coalesce(p_uid, last_uid), uidvalidity = coalesce(p_uidvalidity, uidvalidity),
         error_uid = p_error_uid, error_count = coalesce(p_error_count, 0), lock_until = null
   where id = 1;
$$;

create or replace function public.pasr_mail_sync_state() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('last_run', last_run, 'last_error', last_error, 'fetched', fetched, 'imported', imported,
                            'last_uid', last_uid, 'uidvalidity', uidvalidity, 'error_uid', error_uid, 'error_count', error_count)
    from public.pasr_mail_sync where id = 1;
$$;

create or replace function public.pasr_mail_log_add(p_box text, p_uid bigint, p_uidvalidity bigint, p_result text, p_ticket bigint) returns void
language sql security definer set search_path = '' as $$
  insert into public.pasr_mail_inbox_log (box, uid, uidvalidity, result, ticket_number)
  values (case when p_box = 'zakelijk' then 'zakelijk' else 'pasr' end, p_uid, p_uidvalidity, left(p_result, 60), p_ticket);
$$;
-- UID's uit het logboek waarover al definitief is besloten (vangnet voor een server zonder IMAP-trefwoorden)
create or replace function public.pasr_mail_log_done(p_box text, p_uidvalidity bigint, p_uids bigint[]) returns bigint[]
language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct l.uid), '{}'::bigint[]) from public.pasr_mail_inbox_log l
   where l.box = p_box and l.uidvalidity is not distinct from p_uidvalidity and l.uid = any (p_uids)
     and not (l.result = 'error' or l.result like 'error:retry%' or l.result = 'rejected:rate_limited');
$$;

-- ------------------------------------------------------------------------------------------- campagnes
-- Maakt een campagne (idempotent op request_id: dezelfde aanvraag geeft dezelfde campagne terug, created=false).
create or replace function public.pasr_mail_campaign_create(p_brand text, p_audience text, p_subject text, p_body_md text, p_request uuid, p_recipients integer)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c public.pasr_mail_campaigns; made boolean := true;
begin
  if p_brand not in ('pasr', 'zakelijk') or p_audience not in ('users', 'owners', 'list') then raise exception 'bad_request' using errcode = '22023'; end if;
  insert into public.pasr_mail_campaigns (brand, audience, subject, body_md, status, recipients, request_id, started_at)
  values (p_brand, p_audience, left(btrim(p_subject), 200), left(coalesce(p_body_md, ''), 100000),
          case when p_audience = 'list' then 'sent' else 'sending' end, greatest(0, coalesce(p_recipients, 0)), p_request, now())
  on conflict (request_id) do nothing returning * into c;
  if c.id is null then
    select * into c from public.pasr_mail_campaigns where request_id = p_request;
    made := false;
  end if;
  return jsonb_build_object('id', c.id, 'created', made, 'status', c.status, 'recipients', c.recipients, 'sent', c.sent, 'failed', c.failed);
end $$;

create or replace function public.pasr_mail_campaign_get(p_id bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select to_jsonb(c) - 'lock_until' from public.pasr_mail_campaigns c where c.id = p_id;
$$;

-- Een ronde van een lopende campagne claimen (lease); false als hij niet loopt of al bezig is.
create or replace function public.pasr_mail_campaign_claim(p_id bigint, p_seconds integer default 150) returns boolean
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  update public.pasr_mail_campaigns set lock_until = now() + make_interval(secs => greatest(10, least(coalesce(p_seconds, 150), 600)))
   where id = p_id and status = 'sending' and (lock_until is null or lock_until < now());
  get diagnostics n = row_count;
  return n > 0;
end $$;

create or replace function public.pasr_mail_campaign_sent_hashes(p_id bigint) returns text[]
language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(email_hash), '{}'::text[]) from public.pasr_mail_campaign_sent where campaign_id = p_id;
$$;

-- (oudere signaturen van dit ontwerp weg, zodat er één variant overblijft)
drop function if exists public.pasr_mail_campaign_progress(bigint, text[], integer, boolean);
drop function if exists public.pasr_mail_campaign_progress(bigint, text[], integer, boolean, integer);
-- Voortgang: p_sent_hashes = ontvangers die nu een mail kregen; p_failed_hashes = definitief mislukt (niet opnieuw proberen); p_sent_extra = aantal verstuurd zonder hash (uitnodigingen aan een
-- losse lijst: de adressen worden niet bewaard); p_failed erbij; p_done = alle ontvangers gehad.
create or replace function public.pasr_mail_campaign_progress(p_id bigint, p_sent_hashes text[], p_failed integer, p_done boolean, p_sent_extra integer default 0,
                                                              p_failed_hashes text[] default '{}') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c public.pasr_mail_campaigns; added integer := 0;
begin
  with ins as (
    insert into public.pasr_mail_campaign_sent (campaign_id, email_hash)
    select p_id, h from unnest(coalesce(p_sent_hashes, '{}'::text[])) as h where h ~ '^[0-9a-f]{26}$'
    on conflict do nothing returning 1)
  select count(*) into added from ins;
  -- ontvangers die definitief niet lukten (bv. een bestaand adres dat de server weigert): niet opnieuw proberen, niet als verstuurd tellen
  insert into public.pasr_mail_campaign_sent (campaign_id, email_hash)
  select p_id, h from unnest(coalesce(p_failed_hashes, '{}'::text[])) as h where h ~ '^[0-9a-f]{26}$' on conflict do nothing;
  update public.pasr_mail_campaigns set sent = sent + added + greatest(0, coalesce(p_sent_extra, 0)), failed = failed + greatest(0, coalesce(p_failed, 0)), lock_until = null,
         status = case when status = 'sending' and coalesce(p_done, false) then 'sent' else status end,
         finished_at = case when status = 'sending' and coalesce(p_done, false) then now() else finished_at end
   where id = p_id returning * into c;
  if c.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if c.status in ('sent', 'cancelled') then delete from public.pasr_mail_campaign_sent where campaign_id = p_id; end if;
  return jsonb_build_object('id', c.id, 'status', c.status, 'sent', c.sent, 'failed', c.failed, 'recipients', c.recipients);
end $$;

create or replace function public.pasr_mail_campaign_list() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'brand', c.brand, 'audience', c.audience, 'subject', c.subject, 'status', c.status,
           'recipients', c.recipients, 'sent', c.sent, 'failed', c.failed, 'created_at', c.created_at) order by c.created_at desc), '[]'::jsonb)
    from (select * from public.pasr_mail_campaigns order by created_at desc limit 50) c;
$$;

create or replace function public.pasr_mail_campaign_cancel(p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c public.pasr_mail_campaigns;
begin
  update public.pasr_mail_campaigns set status = 'cancelled', finished_at = now(), lock_until = null
   where id = p_id and status in ('draft', 'sending') returning * into c;
  if c.id is null then
    if exists (select 1 from public.pasr_mail_campaigns where id = p_id) then raise exception 'not_cancellable' using errcode = '22023'; end if;
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  delete from public.pasr_mail_campaign_sent where campaign_id = p_id;
  return jsonb_build_object('id', c.id, 'status', c.status, 'sent', c.sent, 'failed', c.failed);
end $$;

-- Lopende campagnen die geen ronde hebben (de cron gaat verder waar een aanroep stopte)
create or replace function public.pasr_mail_campaign_due() returns bigint[]
language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(id order by id), '{}'::bigint[]) from public.pasr_mail_campaigns
   where status = 'sending' and (lock_until is null or lock_until < now());
$$;

-- ------------------------------------------------------------------------------------------- cron
-- Elke 5 minuten een seintje aan de functie mail (poll_inbox: IMAP-import en lopende campagnes). Het adres zet de workflow
-- Backend (pasr_admin_config.mail_url); leeg = er gebeurt niets. Het logboek van de import houdt 30 dagen bij.
create or replace function public.pasr_mail_poll_kick() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare u text; s text;
begin
  delete from public.pasr_mail_inbox_log where at < now() - interval '30 days';
  select mail_url into u from public.pasr_admin_config where id = 1;
  select hook_secret into s from public.pasr_secret where id = 1;
  if coalesce(u, '') = '' or s is null then return; end if;
  perform net.http_post(url := u, body := jsonb_build_object('action', 'poll_inbox'),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-pasr-cron', s),
    timeout_milliseconds := 120000);
exception when others then
  raise warning 'pasr_mail_poll_kick: %', sqlerrm;
end $$;
revoke all on function public.pasr_mail_poll_kick() from public, anon, authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'pasr-mail-poll';
  perform cron.schedule('pasr-mail-poll', '*/5 * * * *', 'select public.pasr_mail_poll_kick()');
exception when others then
  raise notice 'pg_cron niet beschikbaar: %', sqlerrm;
end $$;


-- Pushmelding voor nieuwe mail (nieuw ticket of antwoord van een klant): p_items = [{number, brand, subject}], nooit adressen of inhoud.
-- De functie admin maakt er één melding van (soort mail_ticket, schakelaar "mail").
create or replace function public.pasr_mail_notify(p_items jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then return; end if;
  perform public.pasr_admin_notify('mail_ticket', jsonb_build_object('items', (
    select coalesce(jsonb_agg(jsonb_build_object('number', (i->>'number')::bigint, 'brand', case when i->>'brand' = 'zakelijk' then 'zakelijk' else 'pasr' end,
                                                 'subject', left(regexp_replace(coalesce(i->>'subject', ''), '[[:cntrl:]]+', ' ', 'g'), 60))), '[]'::jsonb)
      from (select value as i from jsonb_array_elements(p_items) limit 20) x where (i->>'number') ~ '^[0-9]{1,15}$')));
end $$;

-- ------------------------------------------------------------------------------------------- rechten
revoke all on function
  public.pasr_mail_salt(), public.pasr_mail_hash(text), public.pasr_mail_scope_code(text), public.pasr_mail_token_of(text, text),
  public.pasr_mail_news_token(text, text), public.pasr_mail_audience(text), public.pasr_mail_audience_count(text),
  public.pasr_mail_list_tokens(text[], text), public.pasr_mail_counts(), public.pasr_mail_thread_list(text, text, text, integer, integer, text),
  public.pasr_mail_thread_get(bigint, boolean), public.pasr_mail_thread_create(text, text, text, text),
  public.pasr_mail_message_add(bigint, text, text, jsonb, jsonb, integer, text, text, text, text, text, text, jsonb, text, text, text, boolean),
  public.pasr_mail_thread_set(bigint, text, text), public.pasr_mail_threads_for(bigint[], text[]), public.pasr_mail_message_exists(text),
  public.pasr_mail_attach(uuid, bigint, text, text, text), public.pasr_mail_attachment_get(uuid), public.pasr_mail_campaign_attachments(bigint),
  public.pasr_mail_sync_lock(integer), public.pasr_mail_sync_done(integer, integer, text, bigint, bigint, bigint, integer),
  public.pasr_mail_sync_state(), public.pasr_mail_log_add(text, bigint, bigint, text, bigint), public.pasr_mail_log_done(text, bigint, bigint[]),
  public.pasr_mail_campaign_create(text, text, text, text, uuid, integer), public.pasr_mail_campaign_get(bigint),
  public.pasr_mail_campaign_claim(bigint, integer), public.pasr_mail_campaign_sent_hashes(bigint),
  public.pasr_mail_campaign_progress(bigint, text[], integer, boolean, integer, text[]), public.pasr_mail_campaign_list(),
  public.pasr_mail_thread_meta(bigint), public.pasr_mail_thread_delete_empty(bigint), public.pasr_mail_out_recent(integer), public.pasr_mail_contact_recent(text, integer),
  public.pasr_mail_campaign_cancel(bigint), public.pasr_mail_campaign_due(), public.pasr_mail_notify(jsonb)
  from public, anon, authenticated;
revoke all on function public.pasr_mail_news_unsubscribe(text), public.pasr_mail_news_unsub_email(text, text, text) from public;
grant execute on function public.pasr_mail_news_unsubscribe(text), public.pasr_mail_news_unsub_email(text, text, text) to anon, authenticated;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function
      public.pasr_mail_salt(), public.pasr_mail_hash(text), public.pasr_mail_scope_code(text), public.pasr_mail_token_of(text, text),
      public.pasr_mail_news_token(text, text), public.pasr_mail_audience(text), public.pasr_mail_audience_count(text),
      public.pasr_mail_list_tokens(text[], text), public.pasr_mail_counts(), public.pasr_mail_thread_list(text, text, text, integer, integer, text),
      public.pasr_mail_thread_get(bigint, boolean), public.pasr_mail_thread_create(text, text, text, text),
      public.pasr_mail_message_add(bigint, text, text, jsonb, jsonb, integer, text, text, text, text, text, text, jsonb, text, text, text, boolean),
      public.pasr_mail_thread_set(bigint, text, text), public.pasr_mail_threads_for(bigint[], text[]), public.pasr_mail_message_exists(text),
      public.pasr_mail_attach(uuid, bigint, text, text, text), public.pasr_mail_attachment_get(uuid), public.pasr_mail_campaign_attachments(bigint),
      public.pasr_mail_sync_lock(integer), public.pasr_mail_sync_done(integer, integer, text, bigint, bigint, bigint, integer),
      public.pasr_mail_sync_state(), public.pasr_mail_log_add(text, bigint, bigint, text, bigint), public.pasr_mail_log_done(text, bigint, bigint[]),
      public.pasr_mail_campaign_create(text, text, text, text, uuid, integer), public.pasr_mail_campaign_get(bigint),
      public.pasr_mail_campaign_claim(bigint, integer), public.pasr_mail_campaign_sent_hashes(bigint),
      public.pasr_mail_campaign_progress(bigint, text[], integer, boolean, integer, text[]), public.pasr_mail_campaign_list(),
      public.pasr_mail_thread_meta(bigint), public.pasr_mail_thread_delete_empty(bigint), public.pasr_mail_out_recent(integer), public.pasr_mail_contact_recent(text, integer),
      public.pasr_mail_campaign_cancel(bigint), public.pasr_mail_campaign_due(), public.pasr_mail_notify(jsonb)
      to service_role;
  end if;
end $$;
