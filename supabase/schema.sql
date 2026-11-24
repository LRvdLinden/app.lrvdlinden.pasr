-- Pasr-account: schema voor Supabase. Wordt bij elke push naar main uitgevoerd door de workflow Backend
-- (Management API), dus alles is herhaalbaar (if not exists / create or replace).
--
-- Kaarten staan versleuteld op de server: elke kaart is een JSON-object dat met pgp_sym_encrypt (AES-256) wordt
-- opgeslagen. De sleutel staat in een tabel die alleen de database zelf kan lezen. De app praat alleen via de functies
-- pasr_sync en pasr_delete_account; de tabel zelf is voor niemand direct leesbaar.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------------------------------------------
-- Sleutel
create table if not exists public.pasr_secret (
  id int primary key default 1 check (id = 1),
  card_key text not null,
  signup_salt text not null
);
alter table public.pasr_secret enable row level security;
revoke all on public.pasr_secret from anon, authenticated;
insert into public.pasr_secret (id, card_key, signup_salt)
values (1, encode(extensions.gen_random_bytes(32), 'hex'), encode(extensions.gen_random_bytes(16), 'hex'))
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------------------------
-- Kaarten
create table if not exists public.pasr_cards (
  user_id    uuid not null references auth.users (id) on delete cascade,
  id         uuid not null,
  payload    bytea not null,
  updated_at timestamptz not null,
  deleted    boolean not null default false,
  server_at  timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);
create index if not exists pasr_cards_changes on public.pasr_cards (user_id, server_at);
alter table public.pasr_cards enable row level security;
revoke all on public.pasr_cards from anon, authenticated;

-- Eén ronde synchroniseren. changes = [{id, updated_at, deleted, card:{…}}] (wijzigingen van dit apparaat; een
-- wijziging wint alleen als hij nieuwer is dan wat er staat). since = tijdstempel van de vorige ronde (null = alles).
-- Terug: {now, cards:[{id, updated_at, deleted, card}]} met alles wat sinds `since` op de server veranderd is.
create or replace function public.pasr_sync(changes jsonb, since timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  k text;
  started timestamptz := clock_timestamp();
  c jsonb;
  n int := 0;
begin
  if uid is null then raise exception 'not signed in' using errcode = '28000'; end if;
  select card_key into k from public.pasr_secret where id = 1;
  if jsonb_typeof(changes) = 'array' then
    if jsonb_array_length(changes) > 2000 then raise exception 'too many changes' using errcode = '22023'; end if;
    for c in select * from jsonb_array_elements(changes) loop
      continue when (c->>'id') is null or (c->>'updated_at') is null;
      continue when octet_length(coalesce(c->'card', '{}'::jsonb)::text) > 400000;
      n := n + 1;
      insert into public.pasr_cards as p (user_id, id, payload, updated_at, deleted, server_at)
      values (uid, (c->>'id')::uuid,
              pgp_sym_encrypt(coalesce(c->'card', '{}'::jsonb)::text, k, 'cipher-algo=aes256'),
              (c->>'updated_at')::timestamptz, coalesce((c->>'deleted')::boolean, false), clock_timestamp())
      on conflict (user_id, id) do update
        set payload = excluded.payload, updated_at = excluded.updated_at, deleted = excluded.deleted,
            server_at = clock_timestamp()
        where p.updated_at <= excluded.updated_at;
    end loop;
  end if;
  return jsonb_build_object(
    'now', started,
    'cards', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id, 'updated_at', p.updated_at, 'deleted', p.deleted,
               'card', case when p.deleted then null else pgp_sym_decrypt(p.payload, k)::jsonb end))
      from public.pasr_cards p
      where p.user_id = uid and (since is null or p.server_at > since)
    ), '[]'::jsonb));
end $$;
revoke all on function public.pasr_sync(jsonb, timestamptz) from public, anon;
grant execute on function public.pasr_sync(jsonb, timestamptz) to authenticated;

-- Account verwijderen: het account en (via cascade) alle kaarten op de server. De kaarten op het apparaat blijven.
create or replace function public.pasr_delete_account() returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not signed in' using errcode = '28000'; end if;
  -- gedeelde Pasrs waarin je het laatste lid bent verdwijnen mee (met hun kaarten)
  if to_regclass('public.pasr_group_members') is not null then
    delete from public.pasr_groups g
     where exists (select 1 from public.pasr_group_members m where m.group_id = g.id and m.user_id = uid)
       and not exists (select 1 from public.pasr_group_members m where m.group_id = g.id and m.user_id <> uid);
  end if;
  delete from auth.users where id = uid;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.pasr_delete_account() from public, anon;
grant execute on function public.pasr_delete_account() to authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Bescherming tegen nepaccounts (Auth-hook "Before User Created", aangezet door de workflow Backend)
--
-- 1. honeypot: het verborgen veld "website" (app en pasr.nl/account) is ingevuld → user_metadata.hp niet leeg.
-- 2. te snel: user_metadata.fill_ms < 2000 (formulier sneller verstuurd dan een mens kan).
-- 3. te veel: meer dan 3 accounts per uur of 10 per dag vanaf één netwerk.
-- 4. wegwerp-e-mail: domein in pasr_disposable_domains.
-- Er wordt geen IP- of e-mailadres bewaard: alleen een gezouten hash van het netwerk, 7 dagen.
create table if not exists public.pasr_signup_attempts (
  id bigint generated always as identity primary key,
  ip_hash text not null,
  at timestamptz not null default now(),
  allowed boolean not null,
  reason text
);
create index if not exists pasr_signup_attempts_ip on public.pasr_signup_attempts (ip_hash, at);
alter table public.pasr_signup_attempts enable row level security;
revoke all on public.pasr_signup_attempts from anon, authenticated;

create table if not exists public.pasr_disposable_domains (domain text primary key);
alter table public.pasr_disposable_domains enable row level security;
revoke all on public.pasr_disposable_domains from anon, authenticated;
insert into public.pasr_disposable_domains (domain) values
  ('mailinator.com'), ('guerrillamail.com'), ('10minutemail.com'), ('tempmail.com'), ('temp-mail.org'),
  ('yopmail.com'), ('trashmail.com'), ('getnada.com'), ('dispostable.com'), ('sharklasers.com'),
  ('maildrop.cc'), ('throwawaymail.com'), ('fakeinbox.com'), ('mohmal.com'), ('emailondeck.com')
on conflict do nothing;

create or replace function public.pasr_before_user_created(event jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  u jsonb := case when jsonb_typeof(event->'user') = 'object' then event->'user' else '{}'::jsonb end;
  meta jsonb := u->'user_metadata';
  ip text := nullif(btrim(coalesce(event->'metadata'->>'ip_address', '')), '');
  net text; h text; reason text; fill numeric; dom text;
begin
  if ip is null or coalesce(u->'app_metadata'->>'provider', 'email') <> 'email' then return '{}'::jsonb; end if;
  begin
    -- IPv6: het /64-netwerk; IPv4: het adres
    net := case when position(':' in ip) > 0 then set_masklen(ip::inet, 64)::cidr::text else host(ip::inet) end;
    select encode(digest(signup_salt || '|' || net, 'sha256'), 'hex') into h from public.pasr_secret where id = 1;
    perform pg_advisory_xact_lock(hashtextextended('pasr_signup:' || h, 0));
    if jsonb_typeof(meta) = 'object' and jsonb_typeof(meta->'fill_ms') = 'number' then
      fill := (meta->>'fill_ms')::numeric;
    end if;
    dom := lower(substring(coalesce(u->>'email', '') from '@([^@]*)$'));
    if jsonb_typeof(meta) = 'object' and coalesce(btrim(meta->>'hp'), '') <> '' then
      reason := 'honeypot';
    elsif fill is not null and fill < 2000 then
      reason := 'too_fast';
    elsif (select count(*) from public.pasr_signup_attempts where ip_hash = h and allowed and at > now() - interval '1 hour') >= 3
       or (select count(*) from public.pasr_signup_attempts where ip_hash = h and allowed and at > now() - interval '24 hours') >= 10 then
      reason := 'rate_limit';
    elsif dom is not null and exists (select 1 from public.pasr_disposable_domains d
                                      where dom = d.domain or dom like '%.' || d.domain) then
      reason := 'disposable';
    end if;
    insert into public.pasr_signup_attempts (ip_hash, allowed, reason) values (h, reason is null, reason);
    delete from public.pasr_signup_attempts where at < now() - interval '7 days';
  exception when others then
    raise warning 'pasr_before_user_created: % (%)', sqlerrm, sqlstate;
    return '{}'::jsonb;   -- een fout in de controle blokkeert nooit een echte aanmelding
  end;
  if reason = 'rate_limit' then
    return jsonb_build_object('error', jsonb_build_object('http_code', 429, 'message', 'Too many sign-ups from this network. Try again later.'));
  elsif reason = 'disposable' then
    return jsonb_build_object('error', jsonb_build_object('http_code', 400, 'message', 'Use a permanent email address.'));
  elsif reason is not null then
    return jsonb_build_object('error', jsonb_build_object('http_code', 400, 'message', 'Something went wrong. Please try again.'));
  end if;
  return '{}'::jsonb;
end $$;
revoke all on function public.pasr_before_user_created(jsonb) from public, anon, authenticated;
grant execute on function public.pasr_before_user_created(jsonb) to supabase_auth_admin;
grant usage on schema public to supabase_auth_admin;
grant all on public.pasr_signup_attempts, public.pasr_disposable_domains, public.pasr_secret to supabase_auth_admin;

-- Honeypot en tijdmeting nooit in het account bewaren; voornaam opschonen (max. 40 tekens, geen links of HTML).
create or replace function public.pasr_user_meta() returns trigger
language plpgsql security definer set search_path = public as $$
declare v text;
begin
  if new.raw_user_meta_data is null or jsonb_typeof(new.raw_user_meta_data) <> 'object' then return new; end if;
  new.raw_user_meta_data := new.raw_user_meta_data - 'hp' - 'fill_ms';
  -- land = de regio-instelling van het apparaat (twee letters, bv. NL); iets anders gaat weg
  if new.raw_user_meta_data ? 'country' then
    if upper(coalesce(new.raw_user_meta_data->>'country', '')) ~ '^[A-Z]{2}$' then
      new.raw_user_meta_data := jsonb_set(new.raw_user_meta_data, '{country}', to_jsonb(upper(new.raw_user_meta_data->>'country')));
    else
      new.raw_user_meta_data := new.raw_user_meta_data - 'country';
    end if;
  end if;
  v := new.raw_user_meta_data->>'first_name';
  if v is not null then
    v := left(btrim(regexp_replace(regexp_replace(v, '[<>]', '', 'g'), '\s+', ' ', 'g')), 40);
    if v ~* '(://|www\.|@)' or v = '' then
      new.raw_user_meta_data := new.raw_user_meta_data - 'first_name';
    else
      new.raw_user_meta_data := jsonb_set(new.raw_user_meta_data, '{first_name}', to_jsonb(v));
    end if;
  end if;
  return new;
end $$;
revoke all on function public.pasr_user_meta() from public, anon, authenticated;
drop trigger if exists pasr_user_meta on auth.users;
create trigger pasr_user_meta before insert or update of raw_user_meta_data on auth.users
  for each row execute function public.pasr_user_meta();

-- Onbevestigde accounts zonder kaarten na 48 uur weg (pg_cron, elk uur), als pg_cron beschikbaar is.
create or replace function public.pasr_unconfirmed_cleanup() returns int
language plpgsql security definer set search_path = public, auth as $$
declare n int;
begin
  delete from auth.users x
  where x.email_confirmed_at is null and x.created_at < now() - interval '48 hours' and x.last_sign_in_at is null
    and not exists (select 1 from public.pasr_cards c where c.user_id = x.id);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.pasr_unconfirmed_cleanup() from public, anon, authenticated;
do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'pasr-unconfirmed-cleanup';
  perform cron.schedule('pasr-unconfirmed-cleanup', '17 * * * *', 'select public.pasr_unconfirmed_cleanup()');
exception when others then
  raise notice 'pg_cron niet beschikbaar: %', sqlerrm;
end $$;

-- ===============================================================================================================
-- Pasr Beheer (beheer.pasr.nl en de app Pasr Beheer). Alleen de functie `admin` (service role) komt hierbij; voor
-- anon en authenticated is alles dicht (RLS aan, geen policies). Het beheer ziet tellingen en accounts (e-mailadres,
-- voornaam, data, aantal kaarten), nooit de inhoud van kaarten.
-- ===============================================================================================================

create extension if not exists pg_net with schema extensions;

-- Inlogtokens van het beheer: versie (Overal uitloggen = +1) en een logboek (IP alleen gehasht).
create table if not exists public.admin_token_state (id int primary key default 1 check (id = 1), v int not null default 1);
insert into public.admin_token_state (id, v) values (1, 1) on conflict do nothing;
create table if not exists public.admin_audit (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  action text not null,
  detail text not null default '',
  ip_hash text not null default ''
);
create index if not exists admin_audit_action on public.admin_audit (action, at);

-- Pushmeldingen van de app Pasr Beheer (APNs-token per apparaat, schakelaars per soort melding).
create table if not exists public.admin_push_devices (
  device_id  text primary key,
  token      text not null,
  platform   text not null,
  sandbox    boolean not null default false,
  app_build  int,
  prefs      jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists admin_push_devices_token on public.admin_push_devices (token);
-- Welke beheer-app (APNs-topic): PasrBeheer of LRbeheer. Leeg = de server zoekt het uit bij de eerste melding.
alter table public.admin_push_devices add column if not exists topic text;
-- Wanneer een soort melding het laatst ging (bots: hoogstens één melding per uur).
create table if not exists public.admin_push_state (kind text primary key, last_at timestamptz not null);

-- Tellingen per dag (UTC). Alleen aantallen, geen gegevens van wie dan ook.
create table if not exists public.pasr_daily (
  day       date primary key,
  signups   int not null default 0,
  confirmed int not null default 0,
  deleted   int not null default 0,
  expired   int not null default 0,
  wallet    int not null default 0,
  bots      int not null default 0
);

alter table public.pasr_daily add column if not exists cards_total int;

-- Elk uur: het aantal kaarten in accounts van vandaag (voor de grafiek; alleen een getal).
create or replace function public.pasr_daily_snapshot() returns void
language sql security definer set search_path = public as $$
  insert into public.pasr_daily as d (day, cards_total)
  values ((now() at time zone 'utc')::date, (select count(*) from public.pasr_cards where not deleted))
  on conflict (day) do update set cards_total = excluded.cards_total;
$$;
revoke all on function public.pasr_daily_snapshot() from public, anon, authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'pasr-daily-snapshot';
  perform cron.schedule('pasr-daily-snapshot', '7 * * * *', 'select public.pasr_daily_snapshot()');
exception when others then
  raise notice 'pg_cron niet beschikbaar: %', sqlerrm;
end $$;

-- Land van je account (regio-instelling van je apparaat), voor accounts van vóór deze instelling. Alleen als het nog leeg is.
create or replace function public.pasr_set_country(p_country text) returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null or upper(coalesce(p_country, '')) !~ '^[A-Z]{2}$' then return; end if;
  update auth.users set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('country', upper(p_country))
  where id = auth.uid() and coalesce(raw_user_meta_data->>'country', '') = '';
end $$;
revoke all on function public.pasr_set_country(text) from public, anon;
grant execute on function public.pasr_set_country(text) to authenticated;

-- Waar de database de functie admin bereikt (gezet door de workflow Backend) en het geheim van die aanroep.
create table if not exists public.pasr_admin_config (id int primary key default 1 check (id = 1), admin_url text);
insert into public.pasr_admin_config (id) values (1) on conflict do nothing;
alter table public.pasr_secret add column if not exists hook_secret text;
update public.pasr_secret set hook_secret = encode(extensions.gen_random_bytes(32), 'hex') where id = 1 and hook_secret is null;

alter table public.admin_token_state enable row level security;
alter table public.admin_audit enable row level security;
alter table public.admin_push_devices enable row level security;
alter table public.admin_push_state enable row level security;
alter table public.pasr_daily enable row level security;
alter table public.pasr_admin_config enable row level security;
revoke all on public.admin_token_state, public.admin_audit, public.admin_push_devices, public.admin_push_state,
  public.pasr_daily, public.pasr_admin_config from anon, authenticated;

create or replace function public.pasr_daily_bump(col text, n int default 1) returns void
language plpgsql security definer set search_path = public as $$
begin
  if col not in ('signups', 'confirmed', 'deleted', 'expired', 'wallet', 'bots', 'groups', 'temp_shares', 'store_requests') then return; end if;
  execute format('insert into public.pasr_daily as d (day, %1$I) values ((now() at time zone ''utc'')::date, $1)
                  on conflict (day) do update set %1$I = d.%1$I + $1', col) using n;
end $$;
revoke all on function public.pasr_daily_bump(text, int) from public, anon, authenticated;

-- Seintje aan de functie admin (die stuurt de pushmeldingen). Via pg_net: gaat op de achtergrond en houdt nooit iets op.
create or replace function public.pasr_admin_notify(kind text, extra jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare u text; s text;
begin
  select admin_url into u from public.pasr_admin_config where id = 1;
  select hook_secret into s from public.pasr_secret where id = 1;
  if coalesce(u, '') = '' or s is null then return; end if;
  perform net.http_post(
    url := u,
    body := jsonb_build_object('action', 'notify', 'kind', kind) || coalesce(extra, '{}'::jsonb),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-pasr-hook', s),
    timeout_milliseconds := 8000);
exception when others then
  raise warning 'pasr_admin_notify: %', sqlerrm;
end $$;
revoke all on function public.pasr_admin_notify(text, jsonb) from public, anon, authenticated;

-- Gebeurtenissen rond accounts: tellen en (voor de pushmeldingen) de functie admin een seintje geven.
create or replace function public.pasr_account_events() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform public.pasr_daily_bump('signups');
    perform public.pasr_admin_notify('signup');
  elsif tg_op = 'UPDATE' then
    if old.email_confirmed_at is null and new.email_confirmed_at is not null then
      perform public.pasr_daily_bump('confirmed');
      perform public.pasr_admin_notify('confirmed');
    end if;
  elsif tg_op = 'DELETE' then
    if old.email_confirmed_at is null then
      perform public.pasr_daily_bump('expired');      -- onbevestigd opgeruimd: wel tellen, geen melding
    else
      perform public.pasr_daily_bump('deleted');
      perform public.pasr_admin_notify('deleted');
    end if;
  end if;
  return null;
exception when others then
  raise warning 'pasr_account_events: %', sqlerrm;   -- tellen mag een aanmelding of verwijdering nooit tegenhouden
  return null;
end $$;
revoke all on function public.pasr_account_events() from public, anon, authenticated;
drop trigger if exists pasr_account_events on auth.users;
create trigger pasr_account_events after insert or update of email_confirmed_at or delete on auth.users
  for each row execute function public.pasr_account_events();

create or replace function public.pasr_bot_events() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not new.allowed then
    perform public.pasr_daily_bump('bots');
    perform public.pasr_admin_notify('bot', jsonb_build_object('reason', coalesce(new.reason, '')));
  end if;
  return null;
exception when others then
  raise warning 'pasr_bot_events: %', sqlerrm;
  return null;
end $$;
revoke all on function public.pasr_bot_events() from public, anon, authenticated;
drop trigger if exists pasr_bot_events on public.pasr_signup_attempts;
create trigger pasr_bot_events after insert on public.pasr_signup_attempts
  for each row execute function public.pasr_bot_events();
grant execute on function public.pasr_bot_events(), public.pasr_daily_bump(text, int), public.pasr_admin_notify(text, jsonb)
  to supabase_auth_admin;

-- Wallet-pas gemaakt (functie wallet-pass): alleen +1 voor vandaag.
create or replace function public.pasr_count_wallet() returns void
language sql security definer set search_path = public as $$ select public.pasr_daily_bump('wallet'); $$;
revoke all on function public.pasr_count_wallet() from public, anon, authenticated;

create or replace function public.pasr_admin_logout_all() returns int
language sql security definer set search_path = public as $$
  update public.admin_token_state set v = v + 1 where id = 1 returning v;
$$;
revoke all on function public.pasr_admin_logout_all() from public, anon, authenticated;

-- Statistieken voor het beheer. p_days ∈ 7|30|90|365, p_offset = aantal periodes terug.
create or replace function public.pasr_admin_stats(p_days int default 30, p_offset int default 0) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  today date := (now() at time zone 'utc')::date;
  last_day date := today - p_days * p_offset;
  first_day date := last_day - p_days + 1;
  result jsonb;
begin
  with users as (
    select u.id, u.created_at, u.email_confirmed_at, u.last_sign_in_at,
           (select count(*) from public.pasr_cards c where c.user_id = u.id and not c.deleted) as cards
    from auth.users u
  ), days as (
    select g::date as day from generate_series(first_day, last_day, interval '1 day') g
  ), totals_per_day as (
    -- accounts aan het eind van elke dag: nu, min wat er daarna bij kwam, plus wat er daarna weg ging
    select d.day,
           (select count(*) from users) - coalesce((select sum(x.signups - x.deleted - x.expired) from public.pasr_daily x where x.day > d.day), 0) as accounts
    from days d
  )
  select jsonb_build_object(
    'generated', now(),
    'totals', (select jsonb_build_object(
        'accounts', count(*),
        'confirmed', count(*) filter (where email_confirmed_at is not null),
        'unconfirmed', count(*) filter (where email_confirmed_at is null),
        'with_cards', count(*) filter (where cards > 0),
        'cards', coalesce(sum(cards), 0),
        'active_30d', count(*) filter (where last_sign_in_at > now() - interval '30 days'),
        'new_today', count(*) filter (where created_at >= today::timestamptz),
        'new_7d', count(*) filter (where created_at > now() - interval '7 days'),
        'new_30d', count(*) filter (where created_at > now() - interval '30 days'))
      from users),
    'wallet_total', (select coalesce(sum(wallet), 0) from public.pasr_daily),
    'range', jsonb_build_object('days', p_days, 'offset', p_offset, 'from', first_day, 'to', last_day),
    'per_day', (select coalesce(jsonb_agg(jsonb_build_object(
        'day', d.day, 'signups', coalesce(x.signups, 0), 'confirmed', coalesce(x.confirmed, 0),
        'deleted', coalesce(x.deleted, 0), 'expired', coalesce(x.expired, 0), 'wallet', coalesce(x.wallet, 0),
        'bots', coalesce(x.bots, 0), 'accounts', greatest(t.accounts, 0), 'cards', x.cards_total,
        'groups', coalesce(x.groups, 0), 'temp_shares', coalesce(x.temp_shares, 0),
        'store_requests', coalesce(x.store_requests, 0)) order by d.day), '[]'::jsonb)
      from days d left join public.pasr_daily x on x.day = d.day left join totals_per_day t on t.day = d.day),
    'countries', (select coalesce(jsonb_object_agg(c, n), '{}'::jsonb) from (
        select coalesce(u.raw_user_meta_data->>'country', '?') as c, count(*) as n from auth.users u group by 1) cc),
    'bots_7d', (select coalesce(jsonb_object_agg(reason, n), '{}'::jsonb) from (
        select coalesce(reason, 'other') as reason, count(*) as n from public.pasr_signup_attempts
        where not allowed and at > now() - interval '7 days' group by 1) b),
    'signups_allowed_7d', (select count(*) from public.pasr_signup_attempts where allowed and at > now() - interval '7 days'),
    'cards_per_account', (select coalesce(jsonb_object_agg(bucket, n), '{}'::jsonb) from (
        select case when cards = 0 then '0' when cards <= 5 then '1-5' when cards <= 15 then '6-15'
                    when cards <= 30 then '16-30' else '31+' end as bucket, count(*) as n
        from users group by 1) b),
    'push_devices', (select count(*) from public.admin_push_devices),
    'shared', jsonb_build_object(
      'groups', (select count(*) from public.pasr_groups),
      'members', (select count(*) from public.pasr_group_members),
      'people', (select count(distinct user_id) from public.pasr_group_members),
      'cards', (select count(*) from public.pasr_group_cards where not deleted),
      'invites', (select count(*) from public.pasr_group_invites where expires_at > now()),
      'new_7d', (select count(*) from public.pasr_groups where created_at > now() - interval '7 days')),
    'temp', case when to_regclass('public.pasr_temp_shares') is null then null else jsonb_build_object(
      'active', (select count(*) from public.pasr_temp_shares where not revoked and expires_at > now()),
      'opens', (select coalesce(sum(opens), 0) from public.pasr_temp_shares where expires_at > now() - interval '30 days'),
      'revoked_30d', (select count(*) from public.pasr_temp_shares where revoked and created_at > now() - interval '30 days'),
      'new_7d', (select count(*) from public.pasr_temp_shares where created_at > now() - interval '7 days')) end,
    'stores', case when to_regclass('public.pasr_stores') is null then null else jsonb_build_object(
      'requests_open', (select count(*) from public.pasr_store_requests where status = 'open'),
      'requests_7d', (select count(*) from public.pasr_store_requests where created_at > now() - interval '7 days'),
      'added', (select count(*) from public.pasr_stores where published),
      'push_devices', (select count(*) from public.pasr_user_push),
      'new_store_push', (select count(*) from public.pasr_user_push where new_stores)) end
  ) into result;
  return result;
end $$;
revoke all on function public.pasr_admin_stats(int, int) from public, anon, authenticated;

-- Snelle tellingen voor de pushmeldingen.
create or replace function public.pasr_admin_counts() returns jsonb
language sql security definer set search_path = public, auth as $$
  select jsonb_build_object(
    'accounts', (select count(*) from auth.users),
    'confirmed', (select count(*) from auth.users where email_confirmed_at is not null),
    'bots_hour', (select count(*) from public.pasr_signup_attempts where not allowed and at > now() - interval '1 hour'));
$$;
revoke all on function public.pasr_admin_counts() from public, anon, authenticated;

-- Accounts voor het beheer: zoeken op e-mail of voornaam, filter all|unconfirmed|cards|active, max. 100 per keer.
create or replace function public.pasr_admin_users(p_search text default '', p_filter text default 'all',
                                                   p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  q text := lower(btrim(coalesce(p_search, '')));
  result jsonb;
begin
  with base as (
    select u.id, u.email, u.raw_user_meta_data->>'first_name' as first_name, u.raw_user_meta_data->>'country' as country,
           u.created_at, u.email_confirmed_at,
           u.last_sign_in_at,
           (select count(*) from public.pasr_cards c where c.user_id = u.id and not c.deleted) as cards,
           (select max(c.server_at) from public.pasr_cards c where c.user_id = u.id) as synced_at,
           (select count(*) from public.pasr_group_members m where m.user_id = u.id) as groups
    from auth.users u
    where (q = '' or position(q in lower(coalesce(u.email, ''))) > 0
                  or position(q in lower(coalesce(u.raw_user_meta_data->>'first_name', ''))) > 0)
  ), filtered as (
    select * from base
    where case p_filter
      when 'unconfirmed' then email_confirmed_at is null
      when 'cards' then cards > 0
      when 'active' then last_sign_in_at > now() - interval '30 days'
      else true end
  )
  select jsonb_build_object(
    'total', (select count(*) from filtered),
    'users', coalesce((select jsonb_agg(to_jsonb(f) order by f.created_at desc) from (
        select * from filtered order by created_at desc
        limit least(greatest(p_limit, 1), 100) offset greatest(p_offset, 0)) f), '[]'::jsonb)
  ) into result;
  return result;
end $$;
revoke all on function public.pasr_admin_users(text, text, int, int) from public, anon, authenticated;

-- Opschonen: logboek ouder dan 400 dagen, tellingen ouder dan 3 jaar.
create or replace function public.pasr_admin_cleanup() returns void
language sql security definer set search_path = public as $$
  delete from public.admin_audit where at < now() - interval '400 days';
  delete from public.pasr_daily where day < (now() at time zone 'utc')::date - 1100;
$$;
revoke all on function public.pasr_admin_cleanup() from public, anon, authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'pasr-admin-cleanup';
  perform cron.schedule('pasr-admin-cleanup', '41 3 * * *', 'select public.pasr_admin_cleanup()');
exception when others then
  raise notice 'pg_cron niet beschikbaar: %', sqlerrm;
end $$;

-- ===============================================================================================================
-- Gedeelde Pasr (zoals de gedeelde groep in Wachtwoorden): iemand maakt een groep en nodigt anderen uit per e-mail.
-- Regels: hoogstens 2 gedeelde Pasrs per persoon, hoogstens 6 leden per groep (uitnodigingen tellen mee), en elk lid
-- mag alles: kaarten toevoegen, wijzigen en verwijderen, uitnodigen, leden verwijderen en de naam wijzigen.
-- Kaarten van een groep staan versleuteld (zelfde sleutel als pasr_cards) en zijn alleen via deze functies te lezen.
-- ===============================================================================================================

create table if not exists public.pasr_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.pasr_group_members (
  group_id uuid not null references public.pasr_groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists pasr_group_members_user on public.pasr_group_members (user_id);
create table if not exists public.pasr_group_invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pasr_groups (id) on delete cascade,
  email text not null,
  invited_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '14 days'
);
create unique index if not exists pasr_group_invites_once on public.pasr_group_invites (group_id, email);
create index if not exists pasr_group_invites_email on public.pasr_group_invites (email);
create table if not exists public.pasr_group_cards (
  group_id uuid not null references public.pasr_groups (id) on delete cascade,
  id uuid not null,
  payload bytea,
  updated_at timestamptz not null,
  deleted boolean not null default false,
  updated_by uuid,
  server_at timestamptz not null default clock_timestamp(),
  primary key (group_id, id)
);
create index if not exists pasr_group_cards_changes on public.pasr_group_cards (group_id, server_at);
alter table public.pasr_groups enable row level security;
alter table public.pasr_group_members enable row level security;
alter table public.pasr_group_invites enable row level security;
alter table public.pasr_group_cards enable row level security;
revoke all on public.pasr_groups, public.pasr_group_members, public.pasr_group_invites, public.pasr_group_cards from anon, authenticated;
alter table public.pasr_daily add column if not exists groups int not null default 0;

create or replace function public.pasr_group_check(p_group uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '28000'; end if;
  if not exists (select 1 from public.pasr_group_members where group_id = p_group and user_id = auth.uid()) then
    raise exception 'not a member' using errcode = '42501';
  end if;
end $$;
revoke all on function public.pasr_group_check(uuid) from public, anon, authenticated;

create or replace function public.pasr_group_clean_name(p text) returns text
language sql immutable as $$ select left(nullif(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g')), ''), 40) $$;

-- Mijn gedeelde Pasrs met leden en openstaande uitnodigingen, en de uitnodigingen aan mij.
create or replace function public.pasr_groups() returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid(); me text;
begin
  if uid is null then raise exception 'not signed in' using errcode = '28000'; end if;
  select lower(email) into me from auth.users where id = uid;
  return jsonb_build_object(
    'groups', coalesce((select jsonb_agg(jsonb_build_object(
        'id', g.id, 'name', g.name, 'created_at', g.created_at,
        'members', (select jsonb_agg(jsonb_build_object(
            'user_id', m.user_id, 'email', u.email, 'first_name', u.raw_user_meta_data->>'first_name',
            'me', m.user_id = uid, 'creator', m.user_id = g.created_by, 'joined_at', m.joined_at) order by m.joined_at)
          from public.pasr_group_members m join auth.users u on u.id = m.user_id where m.group_id = g.id),
        'invites', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'email', i.email, 'created_at', i.created_at)
            order by i.created_at)
          from public.pasr_group_invites i where i.group_id = g.id and i.expires_at > now()), '[]'::jsonb),
        'cards', (select count(*) from public.pasr_group_cards c where c.group_id = g.id and not c.deleted))
        order by g.created_at)
      from public.pasr_groups g join public.pasr_group_members gm on gm.group_id = g.id and gm.user_id = uid), '[]'::jsonb),
    'invites', coalesce((select jsonb_agg(jsonb_build_object(
        'id', i.id, 'group_id', i.group_id, 'group_name', g.name,
        'from', coalesce(nullif(u.raw_user_meta_data->>'first_name', ''), u.email),
        'members', (select count(*) from public.pasr_group_members m where m.group_id = i.group_id),
        'created_at', i.created_at) order by i.created_at)
      from public.pasr_group_invites i join public.pasr_groups g on g.id = i.group_id
      left join auth.users u on u.id = i.invited_by
      where i.email = me and i.expires_at > now()
        and not exists (select 1 from public.pasr_group_members m where m.group_id = i.group_id and m.user_id = uid)), '[]'::jsonb),
    'limits', jsonb_build_object('groups', 2, 'members', 6));
end $$;

create or replace function public.pasr_group_create(p_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); gid uuid; n text := public.pasr_group_clean_name(p_name);
begin
  if uid is null then raise exception 'not signed in' using errcode = '28000'; end if;
  if n is null then raise exception 'name required' using errcode = '22023'; end if;
  if (select count(*) from public.pasr_group_members where user_id = uid) >= 2 then
    raise exception 'group_limit' using errcode = 'P0001';
  end if;
  insert into public.pasr_groups (name, created_by) values (n, uid) returning id into gid;
  insert into public.pasr_group_members (group_id, user_id) values (gid, uid);
  perform public.pasr_daily_bump('groups');
  return jsonb_build_object('id', gid, 'name', n);
end $$;

create or replace function public.pasr_group_rename(p_group uuid, p_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n text := public.pasr_group_clean_name(p_name);
begin
  perform public.pasr_group_check(p_group);
  if n is null then raise exception 'name required' using errcode = '22023'; end if;
  update public.pasr_groups set name = n where id = p_group;
  return jsonb_build_object('ok', true);
end $$;

-- Uitnodigen: geeft terug wat de mail nodig heeft (de functie group-invite verstuurt hem).
create or replace function public.pasr_group_invite(p_group uuid, p_email text) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid(); e text := lower(btrim(coalesce(p_email, ''))); g record; inviter text; existing uuid;
begin
  perform public.pasr_group_check(p_group);
  if e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(e) > 200 then raise exception 'bad_email' using errcode = '22023'; end if;
  if exists (select 1 from public.pasr_group_members m join auth.users u on u.id = m.user_id
             where m.group_id = p_group and lower(u.email) = e) then
    raise exception 'already_member' using errcode = 'P0001';
  end if;
  delete from public.pasr_group_invites where group_id = p_group and expires_at <= now();
  if (select count(*) from public.pasr_group_members where group_id = p_group)
     + (select count(*) from public.pasr_group_invites where group_id = p_group and email <> e) >= 6 then
    raise exception 'member_limit' using errcode = 'P0001';
  end if;
  -- hoogstens 20 uitnodigingen per persoon per dag (tegen misbruik voor spam)
  if (select count(*) from public.pasr_group_invites where invited_by = uid and created_at > now() - interval '1 day') >= 20 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  insert into public.pasr_group_invites (group_id, email, invited_by) values (p_group, e, uid)
  on conflict (group_id, email) do update set created_at = now(), expires_at = now() + interval '14 days', invited_by = uid
  returning id into existing;
  select * into g from public.pasr_groups where id = p_group;
  select coalesce(nullif(raw_user_meta_data->>'first_name', ''), email) into inviter from auth.users where id = uid;
  return jsonb_build_object('id', existing, 'email', e, 'group_name', g.name, 'from', inviter,
    'has_account', exists (select 1 from auth.users where lower(email) = e));
end $$;

create or replace function public.pasr_group_cancel_invite(p_invite uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare gid uuid;
begin
  select group_id into gid from public.pasr_group_invites where id = p_invite;
  if gid is null then return jsonb_build_object('ok', true); end if;
  perform public.pasr_group_check(gid);
  delete from public.pasr_group_invites where id = p_invite;
  return jsonb_build_object('ok', true);
end $$;

-- Uitnodiging aan mij accepteren of weigeren (alleen met een bevestigd account op hetzelfde e-mailadres).
create or replace function public.pasr_invite_respond(p_invite uuid, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid(); me record; inv record;
begin
  if uid is null then raise exception 'not signed in' using errcode = '28000'; end if;
  select lower(email) as email, email_confirmed_at into me from auth.users where id = uid;
  select * into inv from public.pasr_group_invites where id = p_invite and email = me.email and expires_at > now();
  if inv.id is null then raise exception 'invite_not_found' using errcode = 'P0001'; end if;
  if not p_accept then
    delete from public.pasr_group_invites where id = p_invite;
    return jsonb_build_object('ok', true);
  end if;
  if me.email_confirmed_at is null then raise exception 'not_confirmed' using errcode = 'P0001'; end if;
  if (select count(*) from public.pasr_group_members where user_id = uid) >= 2 then
    raise exception 'group_limit' using errcode = 'P0001';
  end if;
  if (select count(*) from public.pasr_group_members where group_id = inv.group_id) >= 6 then
    raise exception 'member_limit' using errcode = 'P0001';
  end if;
  insert into public.pasr_group_members (group_id, user_id) values (inv.group_id, uid) on conflict do nothing;
  delete from public.pasr_group_invites where id = p_invite;
  return jsonb_build_object('ok', true, 'group_id', inv.group_id);
end $$;

-- Lid verwijderen (elk lid mag dat) of zelf vertrekken (p_user = null). Laatste lid weg = groep en kaarten weg.
create or replace function public.pasr_group_remove(p_group uuid, p_user uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare who uuid := coalesce(p_user, auth.uid());
begin
  perform public.pasr_group_check(p_group);
  delete from public.pasr_group_members where group_id = p_group and user_id = who;
  if not exists (select 1 from public.pasr_group_members where group_id = p_group) then
    delete from public.pasr_groups where id = p_group;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- Kaarten van een groep: zelfde werking als pasr_sync (nieuwste wijziging wint).
create or replace function public.pasr_group_sync(p_group uuid, changes jsonb, since timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid(); k text; started timestamptz := clock_timestamp(); c jsonb;
begin
  perform public.pasr_group_check(p_group);
  select card_key into k from public.pasr_secret where id = 1;
  if jsonb_typeof(changes) = 'array' then
    if jsonb_array_length(changes) > 2000 then raise exception 'too many changes' using errcode = '22023'; end if;
    for c in select * from jsonb_array_elements(changes) loop
      continue when (c->>'id') is null or (c->>'updated_at') is null;
      continue when octet_length(coalesce(c->'card', '{}'::jsonb)::text) > 400000;
      insert into public.pasr_group_cards as p (group_id, id, payload, updated_at, deleted, updated_by, server_at)
      values (p_group, (c->>'id')::uuid,
              pgp_sym_encrypt(coalesce(c->'card', '{}'::jsonb)::text, k, 'cipher-algo=aes256'),
              (c->>'updated_at')::timestamptz, coalesce((c->>'deleted')::boolean, false), uid, clock_timestamp())
      on conflict (group_id, id) do update
        set payload = excluded.payload, updated_at = excluded.updated_at, deleted = excluded.deleted,
            updated_by = excluded.updated_by, server_at = clock_timestamp()
        where p.updated_at <= excluded.updated_at;
    end loop;
  end if;
  return jsonb_build_object(
    'now', started,
    'cards', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id, 'updated_at', p.updated_at, 'deleted', p.deleted,
               'card', case when p.deleted then null else pgp_sym_decrypt(p.payload, k)::jsonb end))
      from public.pasr_group_cards p
      where p.group_id = p_group and (since is null or p.server_at > since)
    ), '[]'::jsonb));
end $$;

revoke all on function public.pasr_groups(), public.pasr_group_create(text), public.pasr_group_rename(uuid, text),
  public.pasr_group_invite(uuid, text), public.pasr_group_cancel_invite(uuid), public.pasr_invite_respond(uuid, boolean),
  public.pasr_group_remove(uuid, uuid), public.pasr_group_sync(uuid, jsonb, timestamptz) from public, anon;
grant execute on function public.pasr_groups(), public.pasr_group_create(text), public.pasr_group_rename(uuid, text),
  public.pasr_group_cancel_invite(uuid), public.pasr_invite_respond(uuid, boolean),
  public.pasr_group_remove(uuid, uuid), public.pasr_group_sync(uuid, jsonb, timestamptz),
  public.pasr_group_invite(uuid, text) to authenticated;

-- ============================================================================================================
-- Tijdelijk delen: een kaart delen tot een einddatum (via WhatsApp of mail). De kaart staat versleuteld op de
-- server onder een willekeurige code (token, 128 bit); de link is https://pasr.nl/tijdelijk/#<token>. Na het einde
-- (of als de deler eerder stopt) geeft de server de kaart niet meer uit en toont de app van de ontvanger de code
-- niet meer. Delen kan zonder account; per internetadres maximaal 50 per dag. 7 dagen na het einde opgeruimd.
-- ============================================================================================================
create table if not exists public.pasr_temp_shares (
  token text primary key,
  payload bytea,
  key_hash bytea not null,
  expires_at timestamptz not null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  opens int not null default 0,
  revoked boolean not null default false
);
create index if not exists pasr_temp_shares_expires on public.pasr_temp_shares (expires_at);
create table if not exists public.pasr_temp_share_rate (
  ip_hash text not null,
  day date not null default (now() at time zone 'utc')::date,
  n int not null default 0,
  primary key (ip_hash, day)
);
alter table public.pasr_temp_shares enable row level security;
alter table public.pasr_temp_share_rate enable row level security;
revoke all on public.pasr_temp_shares, public.pasr_temp_share_rate from anon, authenticated;
alter table public.pasr_daily add column if not exists temp_shares int not null default 0;


create or replace function public.pasr_temp_share_create(p_card jsonb, p_expires timestamptz) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare k text; tok text; owner text; ip text; used int; today date := (now() at time zone 'utc')::date;
begin
  if jsonb_typeof(p_card) <> 'object' or coalesce(p_card->>'storeName', '') = '' or coalesce(p_card->>'number', '') = ''
     or octet_length(p_card::text) > 6000 then
    raise exception 'bad_card' using errcode = '22023';
  end if;
  if p_expires is null or p_expires < now() + interval '5 minutes' or p_expires > now() + interval '91 days' then
    raise exception 'bad_expiry' using errcode = '22023';
  end if;
  -- per internetadres (gehasht, nooit bewaard als adres) en een algemene rem
  ip := split_part(coalesce(current_setting('request.headers', true)::json->>'x-forwarded-for', 'unknown'), ',', 1);
  ip := encode(digest(ip || coalesce((select hook_secret from public.pasr_secret where id = 1), ''), 'sha256'), 'hex');
  insert into public.pasr_temp_share_rate as r (ip_hash, day, n) values (ip, today, 1)
    on conflict (ip_hash, day) do update set n = r.n + 1 returning n into used;
  if used > 50 or (select coalesce(sum(n), 0) from public.pasr_temp_share_rate where day = today) > 20000 then
    raise exception 'rate_limited' using errcode = '22023';
  end if;
  select card_key into k from public.pasr_secret where id = 1;
  tok := translate(rtrim(encode(gen_random_bytes(16), 'base64'), '='), '+/', '-_');
  owner := encode(gen_random_bytes(16), 'hex');
  insert into public.pasr_temp_shares (token, payload, key_hash, expires_at, created_by)
  values (tok, pgp_sym_encrypt(p_card::text, k, 'cipher-algo=aes256'), digest(owner, 'sha256'), p_expires, auth.uid());
  perform public.pasr_daily_bump('temp_shares');
  return jsonb_build_object('token', tok, 'key', owner, 'expires_at', p_expires);
end $$;

-- De kaart ophalen (app van de ontvanger en pasr.nl/tijdelijk). Na het einde: alleen de status.
create or replace function public.pasr_temp_share_get(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s public.pasr_temp_shares; k text;
begin
  select * into s from public.pasr_temp_shares where token = left(coalesce(p_token, ''), 40);
  if not found then return jsonb_build_object('status', 'not_found'); end if;
  if s.revoked then return jsonb_build_object('status', 'revoked', 'expires_at', s.expires_at); end if;
  if s.expires_at <= now() then return jsonb_build_object('status', 'expired', 'expires_at', s.expires_at); end if;
  update public.pasr_temp_shares set opens = opens + 1 where token = s.token;
  select card_key into k from public.pasr_secret where id = 1;
  return jsonb_build_object('status', 'ok', 'expires_at', s.expires_at, 'card', pgp_sym_decrypt(s.payload, k)::jsonb);
end $$;

-- Status van meerdere tijdelijke kaarten tegelijk (de app van de ontvanger controleert of er eerder is gestopt).
create or replace function public.pasr_temp_share_status(p_tokens text[]) returns jsonb
language sql security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(t.tok, case
           when s.token is null then 'not_found'
           when s.revoked then 'revoked'
           when s.expires_at <= now() then 'expired'
           else 'ok' end), '{}'::jsonb)
  from (select distinct left(x, 40) as tok from unnest((coalesce(p_tokens, '{}'))[1:200]) x) t
  left join public.pasr_temp_shares s on s.token = t.tok;
$$;

-- Eerder stoppen: alleen met de sleutel die de deler bij het maken kreeg.
create or replace function public.pasr_temp_share_revoke(p_token text, p_key text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  update public.pasr_temp_shares set revoked = true, payload = null
   where token = p_token and key_hash = digest(coalesce(p_key, ''), 'sha256');
  return jsonb_build_object('ok', found);
end $$;

-- Einddatum wijzigen (langer delen, korter, of nu laten verlopen), alleen met de sleutel van de deler. Kan zolang de
-- kaart nog op de server staat: tot het nachtelijk opruimen na het einde. p_expires in het verleden = nu laten verlopen.
create or replace function public.pasr_temp_share_update(p_token text, p_key text, p_expires timestamptz) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare e timestamptz;
begin
  if p_expires is null or p_expires > now() + interval '91 days' then
    raise exception 'bad_expiry' using errcode = '22023';
  end if;
  e := greatest(p_expires, now());
  update public.pasr_temp_shares set expires_at = e
   where token = p_token and key_hash = digest(coalesce(p_key, ''), 'sha256') and not revoked and payload is not null;
  if not found then return jsonb_build_object('ok', false, 'error', 'gone'); end if;
  return jsonb_build_object('ok', true, 'expires_at', e);
end $$;

-- Status en einddatum van meerdere tijdelijke kaarten (de app van de ontvanger volgt zo verlengen en stoppen).
create or replace function public.pasr_temp_share_info(p_tokens text[]) returns jsonb
language sql security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(t.tok, jsonb_build_object(
           'status', case when s.token is null then 'not_found' when s.revoked then 'revoked'
                          when s.expires_at <= now() then 'expired' else 'ok' end,
           'expires_at', s.expires_at)), '{}'::jsonb)
  from (select distinct left(x, 40) as tok from unnest((coalesce(p_tokens, '{}'))[1:200]) x) t
  left join public.pasr_temp_shares s on s.token = t.tok;
$$;
revoke all on function public.pasr_temp_share_update(text, text, timestamptz), public.pasr_temp_share_info(text[]) from public;
grant execute on function public.pasr_temp_share_update(text, text, timestamptz), public.pasr_temp_share_info(text[]) to anon, authenticated;

create or replace function public.pasr_temp_share_cleanup() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from public.pasr_temp_shares where expires_at < now() - interval '7 days';
  get diagnostics n = row_count;
  update public.pasr_temp_shares set payload = null where expires_at < now() and payload is not null;
  delete from public.pasr_temp_share_rate where day < (now() at time zone 'utc')::date - 2;
  delete from public.pasr_group_invites where expires_at < now();   -- uitnodigingen hoogstens 14 dagen
  return n;
end $$;

revoke all on function public.pasr_temp_share_create(jsonb, timestamptz), public.pasr_temp_share_get(text),
  public.pasr_temp_share_status(text[]), public.pasr_temp_share_revoke(text, text), public.pasr_temp_share_cleanup() from public;
grant execute on function public.pasr_temp_share_create(jsonb, timestamptz), public.pasr_temp_share_get(text),
  public.pasr_temp_share_status(text[]), public.pasr_temp_share_revoke(text, text) to anon, authenticated;
do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'pasr-temp-share-cleanup';
  perform cron.schedule('pasr-temp-share-cleanup', '23 3 * * *', 'select public.pasr_temp_share_cleanup()');
exception when others then
  raise notice 'pg_cron niet beschikbaar: %', sqlerrm;
end $$;

-- ============================================================================================================
-- Winkels aanvragen en zonder app-update toevoegen. Gebruikers (met account) vragen een winkel aan met naam en
-- website; in het beheer maak je de kaart (logo, kleur, soort code), publiceer je hem en sluit je de aanvragen.
-- De apps halen gepubliceerde winkels op via pasr_store_catalog; wie de winkel vroeg (en wie "Nieuwe winkels"
-- aanzet) krijgt een pushmelding.
-- ============================================================================================================
create table if not exists public.pasr_stores (
  id text primary key check (id ~ '^[a-z0-9-]{2,40}$'),
  name text not null check (char_length(name) between 1 and 40),
  domain text not null default '',
  category text not null default 'Overig',
  card_hex text not null default '#2B2F3A' check (card_hex ~ '^#[0-9A-Fa-f]{6}$'),
  format text not null default 'code128',
  kind text not null default 'loyalty',
  aliases text[] not null default '{}',
  logo text,                                   -- PNG, base64 (hoogstens ~200 kB)
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  published_at timestamptz
);
create index if not exists pasr_stores_updated on public.pasr_stores (updated_at);
-- Cadeaubon-gids per winkel (geldigheid, online/winkel, uitleg, voorwaarden); zie het blok na pasr_store_logos.
alter table public.pasr_stores add column if not exists guide jsonb;
-- Kaartontwerp (voorkant) van een cadeaukaart, base64 JPEG/PNG (hoogstens ~150 kB). Gevuld uit
-- supabase/catalog/covers.json (supabase/catalog/covers.py, alleen waar cover nog leeg is) en te bewerken in het beheer.
alter table public.pasr_stores add column if not exists cover text;
do $$ begin
  alter table public.pasr_stores add constraint pasr_stores_cover_image
    check (cover is null or (octet_length(cover) <= 210000 and cover ~ '^(/9j/|iVBORw0KGgo)[A-Za-z0-9+/]+=*$'));
exception when duplicate_object then null;
end $$;
-- Welke winkels al eens een cover uit covers.json kregen: haalt het beheer hem weg, dan komt hij niet terug.
create table if not exists public.pasr_store_cover_seeded (id text primary key, at timestamptz not null default now());
alter table public.pasr_store_cover_seeded enable row level security;
revoke all on public.pasr_store_cover_seeded from anon, authenticated;
create table if not exists public.pasr_store_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  website text check (website is null or char_length(website) <= 200),
  note text check (note is null or char_length(note) <= 300),
  status text not null default 'open' check (status in ('open', 'added', 'rejected')),
  store_id text references public.pasr_stores (id) on delete set null,
  created_at timestamptz not null default now(),
  closed_at timestamptz
);
create index if not exists pasr_store_requests_status on public.pasr_store_requests (status, created_at);
create table if not exists public.pasr_user_push (
  device_id text primary key check (char_length(device_id) between 8 and 80),
  user_id uuid not null references auth.users (id) on delete cascade,
  token text not null check (token ~ '^[0-9a-f]{32,200}$'),
  sandbox boolean not null default false,
  new_stores boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.pasr_stores enable row level security;
alter table public.pasr_store_requests enable row level security;
alter table public.pasr_user_push enable row level security;
revoke all on public.pasr_stores, public.pasr_store_requests, public.pasr_user_push from anon, authenticated;
alter table public.pasr_daily add column if not exists store_requests int not null default 0;
-- klantenkaart of cadeaukaart/voucher
alter table public.pasr_store_requests add column if not exists kind text not null default 'loyalty';
drop function if exists public.pasr_store_request(text, text, text);

create or replace function public.pasr_store_request(p_name text, p_website text default null, p_note text default null,
                                                      p_kind text default 'loyalty') returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n text; w text; existing uuid; today int;
begin
  if uid is null then raise exception 'not signed in' using errcode = '28000'; end if;
  n := left(regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g'), 60);
  if n = '' then raise exception 'bad_name' using errcode = '22023'; end if;
  w := nullif(left(trim(coalesce(p_website, '')), 200), '');
  select id into existing from public.pasr_store_requests
   where user_id = uid and status = 'open' and lower(name) = lower(n) limit 1;
  if existing is not null then return jsonb_build_object('id', existing, 'duplicate', true); end if;
  select count(*) into today from public.pasr_store_requests where user_id = uid and created_at > now() - interval '1 day';
  if today >= 10 then raise exception 'rate_limited' using errcode = '22023'; end if;
  insert into public.pasr_store_requests (user_id, name, website, note, kind)
  values (uid, n, w, nullif(left(trim(coalesce(p_note, '')), 300), ''),
          case when p_kind = 'voucher' then 'voucher' else 'loyalty' end) returning id into existing;
  perform public.pasr_daily_bump('store_requests');
  perform public.pasr_admin_notify('store_request', jsonb_build_object('name', n));
  return jsonb_build_object('id', existing, 'duplicate', false);
end $$;

create or replace function public.pasr_my_store_requests() returns jsonb
language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name, 'website', r.website, 'status', r.status, 'kind', r.kind,
           'store_id', r.store_id, 'created_at', r.created_at, 'closed_at', r.closed_at) order by r.created_at desc), '[]'::jsonb)
  from public.pasr_store_requests r where r.user_id = auth.uid();
$$;

-- Gepubliceerde winkels die sinds p_since zijn gewijzigd (de app bewaart ze en vraagt alleen wat nieuw is).
-- Een winkel die weer offline gaat komt mee met removed = true.
-- Saldo-pagina's per winkel (ook voor winkels die in de app zitten): de knop "Saldo checken" bij een voucher.
create table if not exists public.pasr_balance_pages (
  store_id text primary key check (store_id ~ '^[a-z0-9-]{2,40}$'),
  url text not null check (url ~ '^https://' and char_length(url) <= 300),
  updated_at timestamptz not null default now()
);
alter table public.pasr_balance_pages enable row level security;
revoke all on public.pasr_balance_pages from anon, authenticated;

create or replace function public.pasr_store_catalog(p_since timestamptz default null) returns jsonb
language sql security definer set search_path = public as $$
  select jsonb_build_object('now', now(),
    'balance_pages', (select coalesce(jsonb_object_agg(b.store_id, b.url), '{}'::jsonb) from public.pasr_balance_pages b),
    'stores', coalesce(jsonb_agg(
    case when s.published then jsonb_build_object('id', s.id, 'name', s.name, 'domain', s.domain, 'category', s.category,
           'card_hex', s.card_hex, 'format', s.format, 'kind', s.kind, 'aliases', to_jsonb(s.aliases), 'logo', s.logo,
           'guide', s.guide, 'updated_at', s.updated_at)
           -- kaartontwerp als voorkant van een cadeaukaart (build 41): alleen meesturen als er een is
           || case when s.cover is not null then jsonb_build_object('cover', s.cover) else '{}'::jsonb end
         else jsonb_build_object('id', s.id, 'removed', true, 'updated_at', s.updated_at) end), '[]'::jsonb))
  from public.pasr_stores s
  -- Ook bij de eerste keer ophalen komen niet-gepubliceerde winkels mee (als removed): sinds versie 1.0.2 haalt het
  -- beheer daarmee ook winkels weg die in de app zitten.
  where p_since is null or s.updated_at > p_since;
$$;

create or replace function public.pasr_push_register(p_device text, p_token text, p_sandbox boolean default false,
                                                     p_new_stores boolean default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not signed in' using errcode = '28000'; end if;
  insert into public.pasr_user_push as p (device_id, user_id, token, sandbox, new_stores)
  values (p_device, uid, lower(p_token), coalesce(p_sandbox, false), coalesce(p_new_stores, false))
  on conflict (device_id) do update set user_id = uid, token = excluded.token, sandbox = excluded.sandbox,
    new_stores = coalesce(p_new_stores, p.new_stores), updated_at = now();
  -- één token hoort bij één apparaat
  delete from public.pasr_user_push where token = lower(p_token) and device_id <> p_device;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.pasr_push_unregister(p_device text) returns jsonb
language sql security definer set search_path = public as $$
  delete from public.pasr_user_push where device_id = p_device and user_id = auth.uid();
  select jsonb_build_object('ok', true);
$$;

revoke all on function public.pasr_store_request(text, text, text, text), public.pasr_my_store_requests(),
  public.pasr_store_catalog(timestamptz), public.pasr_push_register(text, text, boolean, boolean),
  public.pasr_push_unregister(text) from public;
grant execute on function public.pasr_store_request(text, text, text, text), public.pasr_my_store_requests(),
  public.pasr_push_register(text, text, boolean, boolean), public.pasr_push_unregister(text) to authenticated;
grant execute on function public.pasr_store_catalog(timestamptz) to anon, authenticated;

-- Voor de website (pasr.nl/kaarten): de lijst zonder logo's (klein), en logo's alleen voor de winkels die erom vragen.
create or replace function public.pasr_store_index() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('now', now(),
    'balance_pages', (select coalesce(jsonb_object_agg(b.store_id, b.url), '{}'::jsonb) from public.pasr_balance_pages b),
    'stores', coalesce(jsonb_agg(
      case when s.published then jsonb_build_object('id', s.id, 'name', s.name, 'domain', s.domain, 'category', s.category,
             'card_hex', s.card_hex, 'kind', s.kind, 'aliases', to_jsonb(s.aliases), 'has_logo', s.logo is not null,
             'has_cover', s.cover is not null, 'guide', s.guide, 'updated_at', s.updated_at)
           else jsonb_build_object('id', s.id, 'removed', true) end), '[]'::jsonb))
  from public.pasr_stores s;
$$;
create or replace function public.pasr_store_logos(p_ids text[]) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(s.id, s.logo), '{}'::jsonb)
  from public.pasr_stores s
  where s.published and s.logo is not null and s.id = any(p_ids[1:40]);
$$;
-- Kaartontwerpen (covers) voor pasr.nl/kaarten en de gidspagina's: alleen voor de gevraagde winkels (hoogstens 40).
create or replace function public.pasr_store_covers(p_ids text[]) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(s.id, s.cover), '{}'::jsonb)
  from public.pasr_stores s
  where s.published and s.cover is not null and s.id = any(p_ids[1:40]);
$$;
revoke all on function public.pasr_store_index(), public.pasr_store_logos(text[]), public.pasr_store_covers(text[]) from public;
grant execute on function public.pasr_store_index(), public.pasr_store_logos(text[]), public.pasr_store_covers(text[]) to anon, authenticated;

-- Cadeaubon-gids (versie 1.0.2). guide is een JSON-object met (allemaal optioneel): validity (tekst), online en store
-- (true/false), how (korte uitleg), shipping (tekst), terms_url (https) en checked (YYYY-MM-DD). De apps en pasr.nl lezen
-- hem via pasr_store_catalog / pasr_store_index. Gevuld uit supabase/catalog/guides.json (supabase/catalog/guides.py, alleen
-- waar guide nog leeg is) en daarna te bewerken in het beheer.
do $$ begin
  alter table public.pasr_stores add constraint pasr_stores_guide_object
    check (guide is null or (jsonb_typeof(guide) = 'object' and pg_column_size(guide) <= 4000));
exception when duplicate_object then null;
end $$;

-- Winkels die via deze repo zijn toegevoegd (zonder app-update). Alleen nieuw invoegen: wijzigingen in het beheer blijven staan.
insert into public.pasr_stores (id, name, domain, category, card_hex, format, kind, aliases, logo, published, published_at)
values ('bakkerscadeau', 'Bakkers Cadeau', 'bakkerscadeaukaart.nl', 'Cadeaukaarten', '#B5814A', 'code128', 'voucher',
        array['bakkers cadeau', 'bakkerscadeau', 'bakkerscadeaukaart', 'bakkers cadeaukaart'],
        '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', true, now())
on conflict (id) do nothing;

insert into public.pasr_stores (id, name, domain, category, card_hex, format, kind, aliases, logo, published, published_at)
values ('rossmann', 'Rossmann', 'rossmann.de', 'Drogist en beauty', '#C3002D', 'code128', 'loyalty',
        array['rossmann', 'rossmann app', 'rossmann drogerie'],
        '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', true, now()),
       ('dm', 'dm-drogerie markt', 'dm.de', 'Drogist en beauty', '#1F3685', 'code128', 'loyalty',
        array['dm', 'dm drogerie', 'dm drogerie markt', 'dm-drogerie markt', 'dm payback'],
        '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', true, now())
on conflict (id) do nothing;

insert into public.pasr_stores (id, name, domain, category, card_hex, format, kind, aliases, logo, published, published_at)
values ('lidl-de', 'Lidl Plus Deutschland', 'lidl.de', 'Supermarkt', '#0050AA', 'qr', 'loyalty',
        array['lidl duitsland', 'lidl deutschland', 'lidl plus de', 'lidl de', 'lidl.de'],
        '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', true, now())
on conflict (id) do nothing;

-- Logo-wissels en een tweede kans voor de catalogus: een nieuwe updated_at laat de app de winkel opnieuw ophalen.
update public.pasr_stores set logo = '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', updated_at = now()
  where id = 'rossmann' and logo is distinct from 'iVBORw0KGgoAAAANSUhEUgAAAWgAAABsCAYAAABHAyh3AAAQAElEQVR4AeydC3bjOA5F7dlYT62sqlfW0yvLvMsQDETxJ1mS7YQ5gkmB+DyAIKw4qcp/bj/g6+Pj47+O/mieU1j/AamYIc4MzAy8UQa+bYNWE6bp/qPxH+2Hp9+6zymsS5YLnT+SeYlLgIgD4k0FbDnBD3QF4A6egEMyL5O/K3IyfcwMnJWB/3CYRPmhf+TeDul/zwJds6s4aGRg/5AMTRcMkG6HL+R/yxYXtp7SbOQ8xCLUxAHxpgK2nOAHkg5XyL/0DrtkNGDRaHmt4Qk45HiRP+mBWezHL9kiPvYFesreEIVw4N/oKTgchkv9yy97kIh8PIM+Pr8ztj1g3JUHxUN9v2Q8PEFzqDhARxH2IBKm2D92JW3rhssRfmgcxLFVvSaPLWs22K/JHcYnDtGHDO6Nhdwfglk4KFxwQORCsDZd6IDHaoH7TQYKwn+Jhx2IOBnFuu5SXqgF/BqB6ToA8pRhIA/skVbOvaJf9jRR5J3ruGwdDLYHjNyXJStcYUeP3KEbSDz2t6JxKhssnn7ToE/1KOMUz2kBk0wRDY3kyl33+p8kPOl26ApxyBcJHFLYKiTbVig9VcPfkxvNycqOsLBn4OnFO4oFHz1byPQot7E7xp6jxnruM8fUUD1saYVBe/YMHATE2XiWb/wfTcRD/R9td7O9Kxo0oAiYw878MFJBksS8UHP7NJBf968v5p7CipR+if4WIa+heOGLp0H8FgX2MBUHT6q8ydSKHEzgAzd4GSHmd/kEt4ZjLuEhPmKtGQx4gvP7HRzQnS8pgAXS9NhLuEr5IXcl/rHOozVhIDfx7msQ/+kYhMbtme6uvTgXl+XggtDoWcW9vsB3ctFr0By00BikkY+sGWm5e3GQDmvSOhDYqhVk3kC4bwJUc/mf6I8oNBsJE5uG4nX05hFL0ZGYf0dM4CvGoXVwFxu18rTp0EieoqzlVXBu5AdqYcEG9YK8p7M+CtgUowf0pvNaHp+dh9mkDy6oXoMOTUENoDTSFIyKzaGAlSbN4S0sjbHUQLBRe9qkadA8IOZjRgtSipnYWnEd0qQVTysfNOfW+gI5mMVovbFouX4JCwe82pxln2sorxKkZsjfkHwd1WIFfAtGvKlijutHDjVfNWxH+r5pj6iHqq+4fqjPjcZmk96YsJZ4r0G3dBdrOpC9hmbytQK39d5Ye9qkmT3cmHFOkUPMO3E91KTlg4NWzQe+wbCFos7epgiemru9jd/r/Vsz/ig/5nLUzC45+aA51nRrT7U1+bP41Xo6y2HB7mzShaTsYR3WoM35SIPoFLqZWo3SqzVnGnPr8Kxs1RjygR2KnOabGlaMyzcbM4EcOna/ZUz2C0olXwWxNUtY+XghkOZbmjVxrw2KIzu7YpSePUmDZwsWeV1drSZYxb6ysp9xhY8eui4G1XCrrnr2j1r/jk368rwe3qDj7vaaS+ugRRPLQUVHgygliOb86MEPzqKP6gFQswFDKTaadAlbsNt4qfqSzkMxCSuNcdhGjF1ui9ewnaK2mFvxSKV0tXLMR1+t9ZK9YV4nP9g5zTfGoQEMiEGtumL9KvpuTfryeE5p0BxGVUDrUG86TLEwS0UXmqXWg71HR2H2V8Cf25QAfEjTxVV7ul8I2Q12bV4aYw5LS2fx0ptmwcFpH00UfD3CKtXII/a8btd2b0+9sZ3zLoZoN5yHOH/2MIr52ThH/V/apE9p0KORbpCrbTJ8GuNRhD2DxRNRzS5rJpdGHVCesNP9IxPZKvp4xGZHt+Wv1bw7Zo9ZHszHKY1Jvg/b173Z2IHB1/Jet0fosSecoyNsvYqNy5r0mQ36kKeuHYX5zE3ccihaDZEYeuvIXEWvgGUUw5Y9ODp/oxj3+M3fJPkuDqrZojGeiafmt8QHy2zSpcx0eGc26I7r22jxlA4cH21QnDndTv/6dGB+wfHJia96QzmqEPMDGT08Z1Bco/v1HIBfXmkGR2Mt1eCXx6/ZKXum3PMEn8fEA9Cq/r6ghNko7iB88gv7ctTZOBnqsPnTn6Sf2aC7WYiFmcvx63T8Sh8/HMxJH92uLxngNwg8UdieJNK9kMcfDhghDg7N2itTiPlh8us2z/WMbyN2sG/3zx6ffdi3NL/DsFZq8Nl7cVMRcgaoIaiGZ6QOa7pb+JyNEXlq+h2aNPG08upjPTWeMxt070CNJGB10ChMn52RuXTCbzS4keIOJP0RHBK7BRu39RebueYew9n72yF7vPfywOF6pTeMVoxgPao5rWqw4fgon7mLHIOvOT/P9fiHLWdhSr50rqgLHoASrzFhb05tag3fo0ucdeLpnYlgT2/ip8VzcIMOeO2lWRja1GbwCrqk3yxGc7xljDiaWFr2Kvr5gVqZqOit5MTg2ygOgKZPv3jDeBaWvB6ohda+dfegl03VYCnWls/DG2IJg2on4dK8iUcxPpwH2eheEQdNrSsrAZp0ikH3L3kpJuLp5RfsxHNKkz6lQZeKiigccbjcbXGaH8ii0EHMETwtV3we6NePxh4a40BePYat89EcgEVQPi47YHJWy2eedx9zTcfL9Oar5hYPbU/vyPUcQ2mfSjzDQPM4IhdmrzoqNzQzmlpVxi1QR5fVkPO7aaqYiIe4enrk+fAmfXiD1mEi6XlR9YIrrecfkfBtB7ZLsg/xtAlsALTLjvRXuJSHkUPROlg5FnJKUZ/yRK0YiB/K/dbuwaIwP8J/dF4TOohfymW3HgTuz17/FV3br1ae2Ke9bhd6FQwr39q7XpyHYVoALNwIC/hoaoXVFYsa6mFfKZ3FaNi1fW+IhKXDm/ShDVoFxUHqFUP3YIVQbzds3dxX62nJie2ejm5CzQGF6dd6eeAHPehs9UteKGyl++PQ5qjDxcECk4+jNydOjwd8PZ2H14XVcLbyB7aHfZkB+fxj84vGHD8/ILe4cwg1PnI0jkv2BWfKE1ha+4KYEbVzdV7N99AY4+FsjMiT68OepA9r0OoWJHkEWLfRyla3mJAR8TR5CCnzI9glduylzSdvo8WcO+cAU+BKxcdRzXovFrCBh/0IeGCcTTF/VTcC0q2lijKx+CWfl1YN7/XnffFZ9p8Fo3/j8ZWk83hKMofx4r70MJk/anhrvKZ7yah4eNPZ0qQPieehBk3xi2gMH8rSSAHwBLAXOAmSm5sVLw2Vw3AUBdvPeNHmk5PRYq5B/K2FUOjaE3Ki2+2XsJDn0UJsOQCLoHwQW0tuZG31cVemBOaMlW7JS7oZmQj0CrPy4nktf9Tn7vy38GUYFqJaAxO04Lsbnuz243KGRqfCRM5G65p6QX7U/OVyiof8jp6NQ+LpNWg2lQZsxNOR0YcyRJMcPQBbmnOvkOzAkjAKABKcp175U1UvhgVYbT6/9sf/n/xoLOwHe7S72IWFj6GOwEKMFKp63sduPDKS5zLPdStn1HCuL5PNixx6gZZ9L3fkfA+GHs6teXg4HtUS+97DZX6oFeTt/uVGxUPPuaxJ9xo0ReKJDTbakrwtzbloNyYmX/tX/FfZUDYux7f5PsZDQUOb9Z0CxU5jZL8ce3zqsBwRG3hO2SvhBB9UC44arq0t+EpYF2P0t9DLbnbnHDslDPI5iuuQPIDjKIrYR+v5tDo5MB5yfEmT7jXoR2MKgcQNetRWS9+eqFsyj66FJzEdnjA+aqylT74iHfEUy9P07oYRcVCMHDCoBb23tvnwke+CUeoqZ7ewbdmzVS2Rg9yZ7h0G3S2vlY3lcvcuf0NpxZYba8pW8pnbOPw+5rCJzTndXCdO95Kp4mH/T4/nrAYNeP4pNMT8kqSd7IRDw0c6gVToXL7x+flhUFQI/qOP0YLI/YM95226jzg8lr37yuHbkqshWeEDD1SLq5sDbShPqbm/vTmv4WjyI4aFjGID14JXu5FsKweodfOA0BkkbMQxmk/qBPkzoBxi84p4eg2azfY0EhifXz7amPG58KXCzQ/OYv1JN5cVO8UQac9TNU+QhxV7xMFTNTR64PwWPZQ3+V/VRzTewkIONteQfNXy1vQV8ewZ8ty0/NTst3R25aHmaCs/5rOFz5ukSW/eM2/g7PmOeGr1VITabNByTqP1RHOoHQ5zQAFsAmGKbzj6H1bl39b28rQ7XO2Lf5IdtZMf/FG9qpxw8Gbcw1LSp0ZGD95wXsEjZ62893KQr482ErldXnseKKRzyLlRHnp28jiX4E++i/hGc/vQR3QnhxLMb4yHN53e/gS7vDQbNAI5CQxPTa1DgAogRg8g8o9Sb7PBC26o5At+TuiYLPZt3Xj5eGW8wbf2YlNzVAM4DeNWLApgtEnkmP2bosysLvZqxYyM6huDcrM6NMQU9VaD1nx9rNYPZPwlbDSpTdTxX81DR++wZeWPfLf2yvsi9rwO/PrT5xvjoT8Sfxf35gYdLY4kdvQARpNfg4ItFX/VXpSvYtI63wVgs7TJ/IYJT4ILEhovG9YyHv8SsJXkXiORuWMuxQeOavzOi4/JsY+bbsBynFNnSf7ZZ8hxF9NaHeX8kXy2/OzJdY4B4NjZQ+i2qOSrJX/4mvZqtG7x/SOb9K4GrcRSmDxRkrga8S7ND9Rq6z0+PrwMRervF3Nhqm1286BFvYUtPbFgy3ihgduNG5PdTN5EcvzGX4xH3cQ4LvVZwx6xpPxU5Jr7iY7y2pVBrkAt3yub8uP3u2BuFyv/aKZp5CQMLZ+rPLSEz1qLtTJat9+xSTf3YVeDZrOUWJLaOgiI0aT3Fv/Ktoo4BCPfvDms1nGYk2SDf+ky5k8NQzawKX18J32zy1qJtE5+Sktn8objORMEthU/+X40B+Qcc566NuW7KaO9BJu3mfY1MvmOKZeJS4vhyO+ScgwLR2fcFPJwhpuuTe0X57m5Z87I5XlyvoemiofaGT2LzTed3Q0apBFIL7F83lI6aJiokmyX7KbN0Tqfv5IIbyOtR6ZPUr7W+4gimMAPE43gMXs28s96wZDbTuvoXkURIzivctnzc3geYow9v6y3fKf9qjSp0cbbyvVwzVcwYPsIIhc1SnmoCVzF176ONmke+h75zvySkBQPfaFVgx5HtUk/1KDxICAjid2X0NuNAr25LzanWPilIhc2kmRN1JkJ02ry0BPxGyvEFoR5EQ978HJcLE/KMqB8PS1P8s1eZYi+blUvxTpCoqeLzAi1fGT6eaPkYzV+bvIwyU9zDzZglKlzL+V99GzRBz6EprqHWnv6pXiowWqfyQDSI1cfiz3coKOTLggVAgCi+PBQspsXsxnL+SVdkx19el4Vt5LOt7+en/tlnY1Jvi6etJ7+PO6LYe1ylxfsVvwteds3Gw1gs25MiJFaYHyEdC7OrpVePHn8j4TzsK5yOtqkH/Z1hQHFw/626tDDWL3hHNKgBQIAvULgXQ+wHlBzHu1i28vV7ORyXme1dsTBqNhoNUiP6fJ5zOflfisOV3tSkMsLdmtuWzVJHa0eGpSjTTUqzK04djW/HRgEo3zJFvigssDtRh7yPNdkL+ELBOSIWwAAEABJREFU83do0ilXj8RzSIMGiUBQ2K0DgRifRyPHfJRKNrGzKCr5zzcVmeBLaxQo695nWvfM0Xlszr8zeb41DT4z/pW3+VPnlb63+NrabLfYDrJx39n7cF94WdSQ1ku1JvY5l2oI/6saOsFbL64cwwkQNpvsYd5s8JkKqkX6T6sWi/AOa9BYFwiaUw8EjZHCRKVLsok9KJddfbAu2TwJ+AITH2lgg3VvJ617Zm+ug4XNUlHjo6d+9nott29V8MpxKY49+T077tYbTSkGv/+rddUwteVlHp7LJnmDarZe8SkavPl5reF/C772gXiIaxjvoQ0arxEE0xaVmltVPtosBXZ5k1bj4ACV8PP0XMJYjAs7Ii7sFWW2MmWsaks5rK7hB91Iq6bB+h7CXk2vh0d6KxzSGc6v9MMVdUb09v7soGlbOVjFEYB9vuR1dOabSc92juUT4UmvI2bj3tHURsTfQkYxEU+zZnwghzfoaBwQcVoceMduNoyCVq3ANjdpJYnf0PBJGnqS1mEDc6mQac6sFWBXWfZRxJDvqpXlgtlccm+3Wu68HHEZef4jc+yV9EfwlPT28kb8tZ6E9/qt6sVaqq4fvaCa9/VeMv/fEvPZvIi710+eDXOTf8VEPL39CDZPadACgPPeodjUmKJNAgvAsxea9KJBSh5ZcJjowl9v3ZRsjAeq1HD2PnmZacYFNhhbKeIrHjLFushNxzZvnqsfnnV0VssRz4oPYxBP/mbj9xIzwyR/6EJVHclsyVGyI72mXQkW90T8vJaOqCOZbV7NM6k9q2FtGj17MeaY83y2q8vsK6aheE5p0EQpABR8syAkR2MaLgrZ5DDUbGILnzL7eUmeJKDzybjdFjK9dZQoWhENKz9QLN+ijTB/8GWBbYst4SPuIj7ZqeVLS9UrNGnZHd4bb0l6R+DJfT/6hNvKQ2vNh1ab+xrLZf7KGTE/OfsrvnzloHvVKvvSslaroZbOJWvCTo45z5f4u8hJN57TGjQBKqkUBInltkY0v9raih9t1g4UTU71/8HfUAwHXPIkwWNA5o8Zrq3LSGhSkgNfsKW5v3ji4aMSz3t0Dja5/gD/n5YxCYEPAl/tYO356MXcEnP4zgRfxmyNyInOwtNy3V3TPlMD0EpWa81crxROYFyIoZiDGBL1xL7H29calCOw187+a4EdQBPjoT9VpU9t0NFrN6HxUEfx/qDAOFCtwGhYNBcIWTCwuWacRgg/3MsethbrWqDR1IqVxoeOxE65wA9GpSZcxOGJf0UFPqiFMcX4AEqw4Bsg4Y1Dk3CQ4wiPdbBAD+PBbgGv35/C8hCLOsgFS7xcpnffsrHIR4yNnHqbLX0vd8S85yvHdoTPw2zorFLTvRgO83e2IcVDXVd7yekNugcgJoADT+LjbX/ArognWAKsKXA4KLhS46AB+uaCbM2O59OcN2H1ym6+pcjA5smZWU3JB/9E+AiMuXFyCZFPI+4NWy7P/R482EO3QPtZqhew5AZKvFzmofvYlM3GKjbhOmOvzN9ilC/ihRZ8d8NZXGF060+fKgbyteX8PB1zC4DiYT+KTfr0Bg2wCKCXUBrm5sKQbQLr2QZGiXrNxeuEJMofxeH5u+ayYx+RgB3aZccpGT6aM3O31J8KD292R+DwzsACbcbjjTAXvodtYEfkY+TN9mG7G7FRc4KRLo8nMU+e9HzmGE+Gs928cs457MWx3fCTNBQPdUgvWyCgQRNkiVbCC82NNwJgCQVIkSQDf6PlGz+o43+2O6PB3PQFJpoMxFys4y7FDHYI/OTc9qLnBCwQuGTmzsh9T6+6fr/fcxx77KHzS7a4mFf9NRbQ80ROGuLjSwJFHY4rjEuC0WP282AlPkl7Pm/SZ+EJPksvygEYWnirP7CULnjRNaJmS25O5zksxAOBaZNf2TA9dCFqF94mO0cIOyz4D/QfMTmUJULgCL/JRvRFAoqUBHdOov271Ek0pOmui9ghw8l8l6EtSsIfDqxG9kPD5yUbHIJAn5zwWsIm0ccvWTcc+NDt3eeUvHoKuOTVZBkfytf9fsc/doxoCnJxzCX7dh1mVwbZM8ObjyEfksnjInfHBLXRirC08DbzEnXRh0JsG90fJh6xWL6buGtOow1igV4pnl88Qddwvy3fJfyuIHwzIfmQ2Oni3ogDY5vNCD8JPmuieDjYgZ6IgeItUcAFxmdhm35nBr5rBr5lg/abpcbhmwpNFxI7XdwbhWbj9ed8ZmBmYGbgWRn49g3aJ3bOZwZmBmYG3ikDs0G/025NrDMDMwM/KgOzQf+o7Z7BzgzMDLxTBr4a9DuhnlhnBmYGZgZ+QAZmg/4BmzxDnBmYGXjPDMwG/Z77NlHPDMwMfGXg285mg/62WzsDmxmYGXj3DMwG/e47OPHPDMwMfNsMzAb9bbd2BjYz8JmB+fq+GZgN+n33biKfGZgZ+OYZmA36m2/wDG9mYGbgfTMwG/T77t1EfkQGpo2ZgRfOwGzQL7w5E9rMwMzAz87AbNA/e/9n9DMDMwMvnIHZoF94c3rQ+Asdnnry29enxszAzMAzM/C2Ddoa0zOTd7XvGPM/GsMl//94CszPlz8aoM1/41H25jUzMDPwIhl4ywZN81H+QnPSnFG32y7pvfxfL7aIhJVm+6F7Yh1puvzRT4hmDu36U0DyN6+ZgW+VAZ0lzj3naeQcPT32t2zQyhrNR8NDF82O5qU9+9izWQ85H1UWOJprHi9/igsKf6JLtmy0P+8lVrqI7bfscGErLczJzMAPzADnnvPE2edsvHQK3q5Bq8vkTebfrRmWDTZpq9qz5P9yjkNTvt/viz/Rdf/8I6v8uS77817+bzE69dts1D4bc/7TMzAb9KtVgJozDd5vzN80uFfD6fDwBhSekIWTxkyTdsvlqWRDs9ZqSd4atc+DROc1M/A6GdBZDR9HHIVI9jj7yRxnJN286OS0J+gT4+XbE2++1ID8eprHDVrov/omgU/E0/FwnCngz4lvwrkNvs1bFO2nynydGXhuBuJZ5TtdHiYYjwbEx4FH2zzc3ls16LhpjyRh0Zxl6C02STh3XVm+aPI8gdvHH2aTAzCbtGVjjq+SAX9W+S7yCFzJph563qLm36pBa4f857G6vd2U6Pyp8Fb6UrNavQtL9y02qRTPDl4q8hi3f3OiSfsn7R3mf6YKdSVK18/MwrFRK5mLcxnr9SEnmU1f+wW7r8N6twZtTWSoKVua4+aYrrEP3yT54TOz8LEBc3P0xLH6xBCL3udx9Qb2RNxv6/pF9v1t8xeBp7rV/cPnVHtCwzeb/MyJe5l+/ettGnRMsmU0b7bGX41RzzYnrccGle4PmtDkwIY/GjXzg0xvMxPjNiXfiI3Hdx/88DGtSQf8aX1OhjKQN5Cn7fkQ2hcXUg2e3TxTvb94KgK8t2nQQkvT0xAuOxTNZMfN9npBWS+mr+mhV46n5PtQh4PG0scbBXmfi9lcCglqsfRGz2f79rk+87MbTAvOFWuX+lB+H8pn1gN4es7P6KXxbHX2Fg1aSfaNwzeUXrzWINmULXrJbuY78UsTFRNPpOZnt8+S7R08i50n5WqRCzM4k/kt8SalkyeviCkPWXnk1xrZ/3xp3m/LQKpbqdlZ0vTxiz2iliLxrwn5LhcSa3HBY716bh5HM2bhLRq0QvENWre31Q8LYXpSuv2362x02ng2ysv6ufTsc2Q26UNrYRR/aLOwLeLiNyZWzW/UjvzuvjIfCwwVo14m5SmXlV1yA5ETqFnEUT7IaI68UTeXkjc/fg/E/ujqgluCpo9P3YZrSNfpmw2LIa9DRIdI3rGFnWE8TqeKO8pgsyozBLAgFG2DOVFBbIgVbYETMnuLfEpmEYMO0eLeO5JssON5+Vwy6Kd61v2HZOgLEHz8Q2LfOANGN33RY7jX9HnXuzRokhmyFDet9S37TRvBBlji829rqkmXHhtquqYf/Orlt9Zznthjl3TNNnbwMab4uFQzV6PmHX6wkweIfSEeLYeLGINJ3SEHBRkxkTcyHe61tLykix10S+volvjBiHRphOhCyEFhTS/oYlvT+iUbyKAPoW8x0BS0HC5kVkZKDEljB8IO9kwMPPDtPo3SwT5r6CDn9YKck2ENGXTCWulF8uQmNMfSuudJFt9Q8K+1MIrf9CG5xSV5fFpjBCcUbEnQ8lmyyUOVRNaXbIIr2NGccSUU+fhZrYlBD8A+3/HwIKW2cmfMCTmJP+96+QatRPvNI6k+W6vNkbxtHnI057wgiw0r6uUbygZB2ILydXh7aIVB/inkgFVzH/Me+wnn/X4fsVXDE/Ib8SSbAkRO2AuIuVhfl+T9HtgCcsjbPaO3yT1vruDN+bluvu51c9/oQkFGLzSyEJfm4RLedK957h9dKMjmL5KvNhmtsac0p2Rf+tiCNA0XMn49MPMX7aPXqeUpVwv3EQd5gcgdOSDOsO5fnGwNU1UXO1E/2NacEZ8sGREHZPeMYPIj8xXJHrla5LOQF2TwCXkb+PwleS5GPpLiZwbwvdxLzV++QStbfKuh4eY/S01J1aZRBBSsbYwVVmjOt4GvaMP00KCRsImBYERaNbLID4PscFgDnsBYvlgRLrm6kx46FBQyRlrZfkVbppjyZIyB8V/ZIBfgsXjAZKohJ6pyChzi/q5FxvAGozn6GtLFXoR1cXhq0RCuhZz8kgfviwMkV3fTtXgWelgq6OLzri908Wm61FGaSw9bxKnpR+4/6EYbGu4hTvmDT6zoQmLdUp1yI2PwySG3ED7RCyQG9xqql88D9ZgEZTvHGdbu9zv8MLeXKAsO8Bi7OEoWGS8Lxl+ye5eCx/BbssS/8ic5cId1zf1ltrAHYRa77M0v7HlhLS5sx3WweTF0072TIY7E1wR/EBh0+z7XSzfomHBLdioQbZ5PNMXAxkFJVjJ+g/3h8bqhsWu7KCoN4eJg03gWcmGl8SKs5h88hiNoaM1joemk+7jm/Qedg16abyjOx8K/ckfsVvx+jdyw5lQ/p+gUYkEWnc94JYqcBvgabpb/MNfLb5Fd5MkwGK8Vj9dd+IzKiz2JPGvWVlu5jYTTy8cYjGVjbt/fgydvEH7dbIQx5jHMeZG/lD+toedxIgJZDMwDSZaaLMmG9cKLlw35l++QA41gCPOohyy1jo/ICoPhCOuBoxfp5/GLewv515q3e9OX2Qj1UYgD+ZI9fEp9cZF75BfMd7l56QbdSaI/vBQt4mwEG0cxcW9k66EgjBnHtKZ7NnOhG4tDSzcKdrF2i19RJtkpFFyUDENqMlGvWFRBct+Lt0c+mlaEoRhTjGGhL15R1jnwvtkHqKkjm8FHjkN8v7/OxedU8infmnsfpT1crH9a+HqVL9YDjsit7nVctyFhECPpRzyWi5WtuC6VcIE36QbO8mXRrLSUN0SxbtQ1Mdz4kv38u0nsk09GRBbyMKSDvsUDJuRZ8pSwOGaqZ3jKJT4gbo1KerZmo+UrYBMeYgAT8RouZAR4zdkAAAqISURBVAO26Id7T/jBN6Pnv+38ZRu0NojNsU1jU7hPiWaDROlbJC3QDCA2SLf9Sz7YePMRCsO0WBOl4pCvUsHyDg8u7JhqqThWPmR7RM9sDo3RZpIV5uFcmJJ0wGW3fizFldYz3+xXy7fPl9lIORKj6Uvr6ZJfbCVdj581EXto6+CqxYcds7toOsYsjP47M69j/lDxfOrF41k1bxREXl+36fJ8n9+UL8VLHPhgRBEfdi6Ml+QRiJRs+xzGtepQkV3EXJFJNoXZ78n/dA9+KGGSMPESh5cV++vCj2hxTnVflf/SfN3Zyzbo0ZRpAyjAQCUdbbYVZWnZ8yiAcC8dNpUCQRfbvBGENf8iOWR8ES2aPLKSwRZTKByMyPN6f99uLAfCn9cJzB0vwVdLr4MDVeJn3EJN/PLpbQaMGW+Vw45zb6+2h5hoNWfWE6mmuvkXZmSS75qO8SXPE+GHnJgOeVo0E63RwLHLNJDTh2+6Yc1eMhlq0paIOfiQf/SNn/IEI1sLewJ/gEZkF74GbBIjZKLo05gh5sZvjXa2RvC17Dx97SUbdCwYS/LWA7slqb4Qwg/H5JsCN9+pwL1RyXDYkPP6iPQKgqcDDorZDzrxgNnT2OLpA4EN5O2OqJnPIBtxhHn+0lqLsua7hz/PGeqe18phOqDCk+YYiFTaQ+Q43OQ9ii0H7adfa/lfKn7dJR3Z8rGw31Yr1ItpgCc0TmNUxmBXNsFn+UXU6xKfNXYvQ+2ihzyU9rqQO7/mddDz5GNrnUuPo1cP2Pfy3BsRA7kKMRqzNSpXC4wt2XdYe8kGrcT5DQtFKt7ZFz45RGwwBUFhrIpVBQDP5EYwYRc5bGLb7gNPhwV7zFlrFT0yVYq40rqzm3h+Ivk8hkWetW64UFuswfAk2YDd8xpzi58nSO+joXKjAeHjdxSq4WHdx9U84MLNbyLwVIteND081HTAaUaY53i0NXdqwWTSKDzIe7uhwUvA84gJfWS1dCM3+Pgdbj5fkMlzm+Q/RRavrTUvuPDhF2weY7Dbbj1L3uMkrqSrCT+EHMUm8XB5+dxeEMhfhCG8iTLma8++f7kGrST5DbNCOyxPsu83MLfLhtKYIeZpHT1RfhAWMjp5HjsHJ/flC5wGFZ6EZHehl5zunyxweTPyRTHSlDy2Up7TU5XXL80Vd9Wfl5dvH6d/smr6inrk3jD7PJZ0ya1g3b2/BEX2LAfeTliXUlEnLMYX6S9kMp1SLuBRUwu9aC7UiWwSH2RsRuL1vLBPkvV2kIGQh6p+WKwQ+CpLn+zMJ8yajsdSk0G/RLzxhjPhFvkVSB+vW/qcChv7yZut9/252HiNeuQXQhdqaFy/9FINmoQpBf7QbN1gqW+6vH0ONcXtecGYcFEgtonwkL1r4pvMSk/rfsP9HP28ECX+0OXz5nEFo4qBIiYGKPDiCzETX7y9hYahm4Q3a0Baal6lholN/P6OmqHRxHk+JH2H2fRyWe451IxGxFPMrbMHFpP3Y2kP/XppvtBRrhb3Ugh4Cnxy4vck5Vs6di3ilo3FPplQHKkpidxz/3H5lvjk4Vb5Kq2JR74WWKSe34sVLs9f1WGQWL4keYEnBnDme8qTtGB8hCasCXljTvMGG4Qdcoi+eYBn88UoG3/EQA8dTW+tmmT9KfQyDVoJI1EkzBJBwnyyjb9pZNMzBfwEVlwzH2y6YHyw8cwhCoCnTb/R4LIG4PnB5sCL1x8QX4sIJBjBxhgokwrfGkvOYiCvUIpd8hwGpaB4oBdykh25fB7BhG8jcmg28fsnM+gPJDqC/oFOjtnUvLzxbEQ/+JKRMNdIrkr2wAyZ7khDQTa9ieimpONt0lxCvMIxgqcWm+d7+4IQmovVJPcl8vp53S7WHM4/mpO3kM/MKLGEuIwv2cW9+DlOsb6uTD5hUFFih3hyfXBTExBzcEEYLdVVCSM800cP4kzik/nx9IDFl2jQcaNImoVydML8RqcDE52lwoj3bDxYINt8lrDB01BtI3sHFRu1uLDNOk9VHAqKyPsOa+6FBsE6WI3c8g3sRshBto4v4uAAGC8fsWm8Uly25kefR/TNP6PJEf/Krw4kmLy+yTNy8O6aIKNheUVdbzP4Vk3RWPANreKXFcuBXxN788VeLJSECTyGF/u/G3jQRTbgkS71leeCHMBH9iYZ5JGB0EtrQaDw4nRYpb540wp6cQ2bYU0v5Awil7oNF+vEhc/A0AtxYScQ96J0RbvpfssEXVHur2Qi4IqyPjcmC0bSH0hM4mJPNL2ZbsjD7QW/XqJBKy++EDjEhyYsbh6bIVfhSv60RvHTAHzhBSG9oANxCCDmYqcLHXhGaYEJtjVSZIF0X4xLfPSxJfEb2Cgiir4mjz2TR6dH2EeHGCDuWzq2Tm6KGHJlF0MJF/bwW7UlfdbQhYK8fKADbk1vdqg4hMje7Eu6yKNnrNKITLCHPKQTm2xKYUvdeV/FNzDZB7eXk4vFZXgkegcX90Hgfr8TH7rw2ANshTV7QSYSMsZujshLALsabsT+WznAFznFh63d3Bf2yc0v6YMFeS+HHSOndvMynr9pLp/8q967lMC3IK1xBVxaT5eYOca0FifEhB7EPLJfb3iJBq2Epg3QnOQeninZTZurOf4WPsRbFILuudhAqLiJEkCHdagmQ1EHWjjMbrAlFkVtdmwUe30hLyIO4kKvRKyBDepiMC+yi7yGO/rG7o73+518sH/oJRL/l6gZD8YlE/Q1BnmNQceaCDIi4tSwvCSL7l1c/CLDiB0thYt5sCeZcInLvcmBO/B7L+iJgi+NVb24FuzLZhrF51rhkUy6JEA8yKCX+I9OsCsb5Acift1+XqyJQlzi4Df4F28RI/cik8OOyQYea6KFjuytLmTud71+Xk15iYT69ePKoGNIjvyBB3xGxKOlO+Midqf6UtOXaNBk5H6/hw1gfhaN+BiROREfRUXxCMadsVm04Lh/5g29Ep2eUzDkFDEF38zz9QfvmwcLfyJyEfz3fEl2SK5kB90S3/OQycmvP2MuPOQHKtaY1kNOGFv4WBdhJ8gjq/vm/iBzJQkP+IxeCttIHl6mQY+AnTLfJwN6Kubb4tGA+NgH2dQIuJk0M/DdMzAb9Hff4ReMT82Z7wz4jL3bpKOsRVH8vNcWv+E4Q/rhGZgN+ocXwNXhx4Ybnoj17efIt5zptyQkT2O/GvL0NzPwtAzMBv201P9Yx9Zwu805NnN7yuYHPT82aTPwn5mB2aB/5r4/M2pruA9/XPHMIKbvmYErMjAb9BVZnj5CBvREbM053A+8hI9CJMfv4c6PN5SIef2sDMwG/bP2+22iVTOfDfltdmsCPSsDs0Gfldln231B//ohn//c2T6LXiGNzdmenvnVutmsV1majJ+Qgdmgf8Iuv1aM1qT5/yBWH3moOcOz5nxTU+dfqb1WBBPNzMBFGZgN+qJETzcpA/6Hg/wudHo6js2Z/4fEhOdvblgm5vgjM/BDG/SP3OuXCFpPxDRk33j5D3vUmz/sf58znPMHg5aJOf7YDMwG/WO3/nmBF5q0B8NHIMX/I8ILzfnMwE/IwGzQP2GXXzBGmrToLmg8TRvRmCGatJbmNTPwszPwfwAAAP//jogRygAAAAZJREFUAwAoEie5pD4i7AAAAABJRU5ErkJggg==';
update public.pasr_stores set updated_at = now() where id = 'dm' and updated_at < '2026-11-13 07:00:00+00';
update public.pasr_stores set logo = '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', updated_at = now()
  where id = 'lidl-de' and logo is distinct from 'iVBORw0KGgoAAAANSUhEUgAAAYAAAACYCAYAAADtNT79AAAtWUlEQVR4Xu2dCZhcVZn3/7eqOnvS6c5GViCdbgMkIWBCSCMQQAyQKD6KgCggKjAffgqhFZfRwflGRkQ6iSAoi58ygyMo4DIkDmHfOiFEIJBA6E5nI/vSnX3rqrrz/M+9p3L79q19u1X9/h7q6Sa91K17qt//e97tGCh7DAOGEQA/wjRhRiOeL9kIBBHqPQC9Bh6HXlXDYZomKvoOROXxpwIwARiun7P+7eDO9Ti4fR0Mw0D40D7s37oa0fARRI4cjPs8sWsxo+qaBEEQioDbqJUHMYNP0+0y+DT0vapGoN/wWgwYMxF9hp6oPtLo0/hTBIxAsL69pcu9mN7WHPu3xdV1nb7eVFVr/X/HgfaYEBzauQEHtq5Ge+ubOLTzIyUWbmHg9ShBiEahBEEQBKEwlI8AKKMfCHQxpDSwA8d+HNUfq0flmEmoqp2GPkNOqN+7oQ9vMY26NvbawEfB/5TbT/c8oYduWNZb3Uf9OcVBC4IWiqaBNREcbt+M3a3LsHvNP9DWsgTtq5cqsYjB3QoFQcRAEIT8U+ICoMM7Lk+/96BRqBp3Bo47fTaq6s5E/5En0cg3tC5Qd5SGnkZeG3ptuJ2GPNNbr0XDKR62MgW0MMQE4tCujUoEtr71NNpb3sC+je93FgMjYO0KJEwkCELuydjQFRfbUzYj4dh10OgPmXQhRkz9LAafMqN+38YB2rs/s63ZjAAq9k9j7PTaC4VbGHgdb1TXBbhTUILAHQJFYPPSP2Pb2ws7iYERDMmuQBCEXFNaAqDDPNrwM1wyZML5GH3O1Rg+9VIafXr5NPw0+DS62vvO9Y3LBdyB6BBTEAg21syyxWBsGDtWvoiPXn0UW5b+BeFDe9XzqfCQR15DEAQhA0pDAHRSVyd0e1YOU0Z/zDlX10eOTtKe/hltzZ28/HTvR4/6jtiP9Jx+7HPi/NrRpgrPX31ksfXv8b6eCAqBFoQQEKIY8KHCRJuaHsOGlx7B3o9WWL/DDn3Fq2gSBEFIgbSNZGFxGboBoydgzIxrafzrD24fRm+f4R0aTh3aSeX6tDGnkdef93AZ/Gw56hIDikOqwqDFgNcwv2aW8vobT5x5FJuaHsdHr/wntr/77DEhgCHVQ4IgZEJKBrPwuGL8NPzjZt+KUWd/qX7P2h40/FPbmsOphne0ke/fcDDnhj5d9jeq4qOUBYFiwHBWp10BBWD1334eEwKGhiRZLAhCmvhPAJQxs2v3e1YOxcc+90OccOGNTsPPeLmu2IkHjT4NPsm1d59LtCDss4UhHnpXwNc9r2ZWQIWHtr39d6x89LZYaEiEQBCENPCRANDrt8MZgVAP1F56G8Ze9M2Gja8NZQkn4/vJwjza6PvZ4CeCYpBKqIg7gpgQMDS08dXf4/3Hf4TDbZvU74+VjwqCIMTHHwLAMkdd2TPstItxypfvqo8cnsBQTzLD76fwTi6hGCTbFVAIllbXBVlK2jjqE9vx4VM/wbpFv0Y00mHdU+6kpIdAEARviiwADq+f4xkmXNOIUWdd+eSy+SkZfj/E9PNNMiHQOYJf1MxSlUOql+Dd392sPspuQBAEX+4AnLH+UWddSePfsKlpxJzWBar6heEer+su9TBPpqQiBKyGYtVQ49iLwvjwqTvQ/NQdx3YDjqY5QRAEjwmXhUGHfEK9+2PiNXPrB4z5uq7sYbWLGP74JBMChoXmW0liA7s+fB1v338d9m9pkZCQIAhuCh8C0p7/wBNPx2n/9HB9NHza42/OS5jgZainn13RI1gkEoJOYaHR5+zC8odvwqbFf7R+0h6LLQhCt6dwAuDs5j3+gq/T829Y/0L/m1sXiNefBYmEwN4NqBETaF0wHyse/Y5KtjvDb4IgdFsKIwDOssTJ1/+6vvKEG3WFD2v63Xe/u8b5MyXZbqCpujb6hSlzgiok9MZdl+Lovl0iAoIg5F8AtLdZ0bcKU2/5Q31Fn5mJQj4S7smcREIQBsKqUmjY6S34xz1fUofUOMtvBUHoduRXALTx52lb0277a0PbqqmJQj6DntxTsk1cfiElERgzox1L7vy02hGICAhCtyV/AqANS1XNVGX8NzUNj2f8JeSTe3ZdVuk5fC6WF2CpKJPD655/SERAELon+REAp/Gv/+EzDRteqrqldYFnvF9CPvkj3m6A/QLzamYZqlT0nQduEBEQhO6JZ819Vojx9w26dNY9UoJNdre2LjBN04zMnXzjg+qCZScgCN2O3AqAivlHwirsU//DZ55c/lDVtLZmzurvUukj8f7CEE8EOEyuYc1Cdlu7RMAxjVUQhLImdwKgDYdt/Bn2sY1/l5EOYvwLC0WAeZZdn6/s9MTxRcAxnE8QhLIlNzkAXefP+f3nN65o2PjqEK+YvyR7iwtPKXOLAGHncOPYS6Jzx80O4vV/uxA73ntOEsOCUP5kLwCqwxdARb8qTP/B31nqGc/4D3piT/nf0RLAq0KIieG5NZdg7uhz27H4p5egffVSaRYThPImSwFwnNl71o+ebdi74ZPxSj2Hb95Z3neyxIgnAuq0sVFn78ALDRNwZM92OVxGEMoXz5HLKaPj/pOv/3Ui48+Yv+Av9HGZTlgdxN1b/cFtQ3Dmd/8bwZ59reFxfAiCUG5kLgA6UTjmvOt4Zm88z18Svv6Ex2Z6CTNnMz325rxwPcwzcOpX71WnilHoBUEoOzITAJX0jYQx4PhJNBJ/WjYvbpNXqZ7P2x2IJwI8k+GW1qfDStz5UBNEg7mrGBMEwRdkIAB2SIDhgSnffLRh3XN9p7e1qH90viLp8C0NKAJe4aCz2lqCt65+OqJ2ARR6JQJ2wl8QhLIgfQFQ3n9UGYaGHe9NZOjHfXyjGP/Sgn0CbhGgoN+6ZqFRv3eDEnp1epvkAwShrEhPAHTSd+T0yxka8Ir7s9ZfTu8qPXSzmBMKu8oHRI5MxClX3Sn5AEEoL1IXAGez16Sv3vvEsvkc8dC1y1dq/UsWr1BQLB9w4sybMGTiBbETxQRBKHlSFwB9luykr/6yYeNrQ6e1NZteoR+hdImXFK5vawnUtzebmHzDAwj1HgCYppSGCkLpk5oA6NDP0FM/hZHTv+DV6Stx//LAKylshYLmR9B3WA3qPvtdmGZUEsKCUPqkIAAs8DFNBEI9MOm6expaF5juih8icf/ywSsfwP4AVRU07tPfRr8RH7PyAVIVJAilTPIOT+39f+xz/9zQo/9PxPvvHngNjuNpYldMnRNs6ji4CE13zCylWUGmSb9FKBSGYZiFei4hc5LsAAxDbfd5oHvN7Funt7d4xv3F+y8/GApiRZcT7gLmtD4dUaHAwSef6/eqINM0A6ZphkzTDNIgyaNw94D33L73KUQZhGKR2CvS3v+kr/2ywQx/w8v7lyFv5YvXLoBTQy+feovRZITewis/OgtmuAOmmijtG4/P9vYDhmFE9OrQIAHob/+/7Abyg34P7PO491HZFfiP+H8IquwTJvoNr8MFjSs2PvvNgD0VLPYzkvgtf7zOFX69ujbyhSlzgnjrvq9gw8uP+CkUZHv7yvCbpjkKwGUAzgYwHsDw8l8xX7AFwCoArwJ4wjCMjfZ6cCcWE2Wh+CQQAPtowI9/45GGo/uvEe+/++IeHR3bBVT0a8YL356EaMSOFRV3F6CNv2maIwD8xDb+2usXisM+igCAHxqGsdkp0ELx8Y7P6aav/iNPwsj6K+a0LujS9OXVNCSUJ+61Zlko3xOqGmjUJ65S4Z8iVwQ5jP9MAMsAXMeQTyQSCXd0dESi0WjUOvxMHvm+B7zXvOe893bYjWuxzDTNmdwB2OE4wQfEmfAYCACRMI6/4OsNaxf1jAJhdoQ6r1cSv90HnRA+2lQRe9FntrWAzWFNY2d+Axte+l0xcwAO4389gAd5kdFoNMx/DwaDoWDQmma9e/du9dEs7kalbDHsYyMGDhxoBGhCAEQiESbfI4FAgOG3/zFN8wbDMB6SnYA/8AgB2avYc8AQnH/3e5te/v4QXqqz9l9i/90Pr4RwU3Vd9LKP3ww08RzhFS8UIxfgMP4XAlhEmxONRmmAlAVasWIFHnnkEbzyyitoaWnpfgtXBGpra3HOOefg2muvxYQJE9QVcFcQCAS4+6Aaf8owjGdFBIpPVwHQB72M+3RDQ+/qu70GvknlT/fEnQuI9QUc3b8Qi386q9ACwDJPO5wxDMA7AIZGo1F6nIFwOIzbbrsN999/P44ePdo9F6zI9OjRAzfddBPuuusuhEIhrhdFgDZnO4DJALbRtzQMg+E5oQh0zQGoDs9gCMfPuC5e3b/QPfHKBdzausDE4FPOU2MiCt8dTONBr/JOAMOi0SgrTAKRSAQXXngh5s+fr4w/jQ83BAxRyCP/94D3mvec955rwLXgmnBt7DWiYN9pr138QhQh73QWAHX0n2li0Piz0X/0KWd6DHwrpdg/wxYsY9QP/r+QOe7mMIYFz2hrjtTvXd8bo8+52vrNdvA3z7DW304osuLnMnr+0Wg0SOPzne98By+//DIqKiqUwedugDlgxv7lkf97wHvNe857zzXgWnBNuDZcI64V14zVWvYaiggUCe8qoBM+eX1D6wJV7ue8rlKp/KHB3zJiMHZ9vhL7GvvEHvx//ju/LuQGayKsaWL0OV9GsEdvtQsozCHy+pziywH0NU0zEgqFjA8++AD33nsvmPilEZKEb/HgvecacC24JlwbrhHXimsGqLUjcuZ0kXAIAMc+RCPoNfA4HPfxT3Nrz9Z/53WVgvfPODWNfiL4dRGBzPAOAy00VQhoyITzC1gSqrtO2eRFz1J5kb/5zW9UuIHepxj/4sM14FpwTbg2zrWyG/SIb7rIuxvHBECFf5hGm3xRw/rn+9H7d1b+uOfC+BEadWepYjIRoFgI6eE1I+iMtuaoOi9gxPQvpPfbMsMe9RA1TbM3AFVmEgwGDXqbL774ojI4Vtm/4Ae4FlwTro29I9Ahnwn2GnItJQxUBBw7APsvZqT3H3HP6Z0Hg/kNr5EFyaBYSF4gfdy7AO4UG1oXGhh66kx1dnABwkB2ApECcBxfAatL9u7dizVr1sTi/II/0HkXrg3XyK4EIly73rmaEUQRsYfQcRBdtg8OEsyrKNnDCrO9zqQ/n+hdYAuAPfWzV9UIDBr/Ccb/3ad9+T38cyTDBG+ycJHQFe4CnHCnOK2tOarCh5wSSgrTGczQAbtN7ae0KlwEf6IrsBxw7XIW/rGnvUaYWM7BIza8Ll+TTVn+moPrTPpaE70brO5ea/RDBFXjzqjft3EA67ud8f9SSP6mGvpxk+nPdXcYEnTeO4YM69tbAk1DJn4SW//xdIESwerd293XooTJydrZFWEcQV1l9xdkA0XpMBvHAew0DKPdNdmU10yvmoY3I/FyXO9pAAZmc7EpwNez2DCMmKPkpPMoiOFTPjO9rVnN9k3hF5cNDAO5vVohMXQKdjUdy6Fwx8j3TtPQyTPV6XGxAXGCkHcYyaCn+3EAz+bo2bjN3Wua5gYA7wN4DcArhmHwc2VM7ZlGmYy5pojQxt4P4MwcXW882AXJMRxtWnic32iFgHjoS6CiJ6rHn1Xf3lJy4R+J4xcet2AqAWhvYTXQWPXwwYA4odtBw8zsv/7IzzN50EiyaWgQAHrpXwLwKwDvmqb5umma/4e7DTt8w51HpofeHLCvj2KTyXUm+hkKIr/OaaxxHXq2R1p13APGTETf48a5m79KofonW+8925/vrrjfG2wKU97/0MkXW/ekME1hgmBDz5rGONuH9tBpOLWgUFQY+qm3PXeKQYNpmj0Zy+fpZxmsQrbXmerPx4WOm6Veg+rqG9YsDDD+7/xuv1f/aEpBqModJoO5g2QhgfVaZeymULJQBLSg0Ljz4RQEHjZ0N+PrpmmexRh7KY65trx/UnkChzOVLJkKVSkkuP2K+95RAFhBhv6jTlY7AYYWBaF8cAqCrkBjiOgl0zRv1mcd5Lt8NJew+ieq/lhLNP6vYZlqursAfr/fy1v9jFceQBUQMAfQZ+iJsgMQyhiKAXcFjJgwNDTfNM277IqhXItAtof4xMXaAfSqGo7e1aMY/y+17l8n6Xrz6X6/0BW36Kp+ADoUlcdPkvsl+Bgabsb13Q+dPE21ElI3WvH3fMc0zZ/aJZcJG7DSRIej0vnI0D6/P+EETCtx0Wfo2Pq9G/qYQKejHzMNqxQLeqQ8qyBZVzCN1qAn9hTrMssa7gCYB2jqP+oUAH8q9IvVWTGdxROKj16LTEtl8kQqBlpX2fB7E/Us6N4AisD3TNNsNgzjtzk88IZ9CYfsa0hVmDQ0dHF/xhKAAaNPYQ03m3ncHcDxOO/OH+OlVSfH/XqmmL/TAwIzxxnWYYcwG5Zo9Clo/Jhu1c+//uUL+PFfcj/mZsZ4lhQDM8avxLnj31cf4/HSqlNw3p23Z35T4vDjz/4Jt382czvNe+psCIvtIAeMpgAUFL7LdV2d4D+4NularzzB2vi/ADjiMuy0h2xu4YiKE+0mLa1bOtQTDy0CFI1fmqbZZBjGhywRzeLAGwoKr+kXAH6mG9BSvCe81bwmXs9e/oxX45olAP1GjofZtVEs3Zi6n9Ai0M9PF+VCC6hTSLM1yIVGvUcajz0rBUA1hA0+uQaBYEUhG8K41v8BqL9u2QH4B70WPWhqintZ2ijuB3CVs8PXjWmaQwFMBfB5APT+eOmpiAANLscRs8nrghy93IPsSM7R7+qEJQD9R4zH3g2dzv0l6XrKQvbonUY2Xnkx0aWgjWNmnIBAj96IHirYFEEGO2fYLk9OZgwIOYOWl660T45k4tujyjRNGtUuvoLd4MVjKxfwYZrmvwP4CYAr7LdXomiWGhMB4HzTNC81DOOvOQgF6aQy7bXnSIdEJBpZEVKHePSqHlG//vkuAlBO6LzAoCf3+F7YSkkEvJwEVQkUqOiF3oNGYd9GK85VAGhk2PbIvxARAH/BtaH1YmutT9ZGDVHzGo9A7FJOlUg1DGM1gCtN01wG4Oe2gddJ1njwJf/ANM2/2aKRDTz+jh3H6mM2v8hNSFVs9KoaYc8Aiq1NsvCPO16daT5Ax8HziTMpzFPB0hUBKz5/zI5l+lrTwUsEcnUNub7nzsFw3AGcyUogOhY9K4cWUgAI/yqTZeyEwqN3AKWCbWhVvN0e9cBY/t3254zHJwoH8S3Il3wGgOmGYTTlYBeQF0JqBHQg1CPdAXAMUdxuF3kwQflShglKCkk+wx1eFUHpigCvccb3jiVo85UAd0MR0MnhXF7Di9/7cV7eTJrYe6nPkBPy+kSCUADsUQ+kwjCMu0zT5Cl0s5OIAAWCm54rATT5Z+PTmQC36TzUm3+0zh6AUisB9SJROShFoBSGyLECye+43ysxAeg3vNbv1y4IqWDvCPTJZQ32yGhuOOOFZHSe4ELOCYo3jjlFeDiNGkfBj2k8kkbbAoh0sMa07Ehk/DWlIAKFCDflAzUTKHKUtcuCUBbYVUMMBTXbCWJdZumFNr50gmr4DVlMDd1PATEM47D9kZ+n8kiaLwihR//B6uJ8U6KbPakYf6cIpJsTyASWdzKc8/Kqk9PuKWCILVGPgG+x31uCUEYwG0vjzuYZlojGg9+j8wQ8t/pDO0WVznwsvYu4xDRNlpby/1P5eV3u+ohhGGsT9SKEMPDE08tJANIx/pmKgAod8eyhNFFxfLvpK52mLoaBnDkIvxMLJQ48kYOyBKGcUAfAmKa51G45YXuDNrhutAdel+EN0ALAY1ato1bTg7mHtYnyDwGY0bTrSv1KJsbfKQKp5AR2XXbsFKxMsYSgYNWReSduxVg0UjbvLUGw0UZ9M6AeJFmoZWSWd895JoHX/CL3v7EXkv/GjwlRtawsAXWTrAzUb2Rj/FMVARr/XJ0hnE7lU6nmAeSEdqHcsL1/9gZwjMSOFAVAxwuSCUU8aKf1mQTpfEwhCVwG5ML4JxOBXBr/7oCXUyEIZYI2rAeTvB79fb38+roTtTT7EqsG/9icsVwa/3gi0J2NP+91KZSiCkIRSOph26SSuC0KSgAWV2eaoygcNELGV/7YKRySD+PvFgG38c9kmqgXrAbyM9b00R+rZLVTcAWhu+OY7tk3yb3QIZ9kO4VkpJsD0DmBpCEnfc6lb9EeqDsOnk/j7xQBJ7FzBO707e3Kmnj3OxFeeRHlVISPJH0DCkIpoWcHmabZG8Aw+9qT7QR2pvh98dDHXKQLK5QSYs0C8kDN0J9esEGOXUhkiJTxX8Cy2MKRy0Nk+NrSOV+APQSFIOfnHsR5bwlCCaOnh46xzw0gyQRgQ4avl54/jf/LPHc4gz6AFvt5ExwIs3/ragyZ4JtJoKl4oKmUa+aSXBh/vq5zV1mln+n0ABSCnBt+zYGtnKIoCOUExzLQoE63K3P0oS1e6BzrqmSGOA5aABZyBlGmNzHRgTQhHNiiVMI5B6hYZDJkjef66lO/8kEujD9hCCvTgXnplIymQypimwmxrnIRAKH80KOZr7JfWjzvXw9AZfz/vQwFQNNPzwJK8zwAjrxOGIa1zgMoMpl6oDT+PPmLR/Xko1InV8Y/G/IR/smX4XfSVFULbH+v6O8tQcgVeqSzaZrT7NO+6KHHO1tYf225YRib7dxBptVA7D4Oc+OR5VC5LoRw9EB7U+XYDsNqNIhBr7oQx7elEwt3oo2/hoe851IE/GD8ST68/1yHoPhecRLbTR7dqxtlBKGk0YPcKAIA7rHj8YnO59We99P2C+fP+a4zPqS26ZEjBw2g0j0SOhH02otVHqi8/uu6VlblSgTcxt/9WgvVmev0/t31+IW6hkyICcCe9e9m8vOC4Cec45xN03zQPugl0YEwNP40+OwWftx+LZl6/3klBDMaQfjgnsXVdZXT2ppjZwIkG3mgDoEpUi17ouqkbEUgnudf6NfqdTh8oa8hVdzvlSUsAY1GOhA5zMO3C4oRBIwQp1CkMKFFKAz2WnBtfISe6smP7sviFauHHrtsT+O8D8BXbE++U8TEhT4M5m+GYbT69TQwEkL40D4c2M6JcWPcI6FZbVPMUtBMyVQE/BL28TL+pQLfQ4uragOIHt2P/Vt1GVphMIFIOxCOJK/LEwqLMrE8gt0/nSFqqmecK4pdpR36+QyA/wdgoj3iOZHx15NBKQJ32KOjs4WVR5RPHg6f9h20zzHwxHohh3asZ9Jualtz2r/cr6QrAn4w/pwQyph/Kc3+d5fk2k6EgUNtmxHt4Ba4YBi9gOpvASajg7ID8A96B9AHao18QoVdWeN8p7Bss6d9dj0PcjkHUMZ/kn3NicI+Gu3932cYxvIcef+HbCOeKOeQEZYA7N24cvGIM3Bz64JOv6TYzWDZkqoIFMv4O0dCl5rh17jDP2oHwBDQwe1rCn0iGI3LwG/ZPlqy1hyhsOioeHEFQL8rONN9sf1OcUJ7yPEO/LrzSnX8PlkQSxv/VgA/sHcP2cT+9fWON03zPDuvkK4IMPG8OF71kC0AG1ZgxBmUv07D4RJVAuX7YPFckUwEUjH+NM75qMZJB+4KzN9dns6PFIVYGJHvqULDJ2eYgQ3sIgD+ggJQARijfXFZtHPqmMYE0HDrRqxUhmbq7+URu180DGOv7f1nIwBacK4B1CMTeCbAcABteoyFW/Hora1tqjzhiIHksyNKkXgikIrxFxLjVQKqegDWPccj8AqOSjTGO59JKB56B+Af4hlm7TqkM39Hh4b4Kr9kGMabOQr9aOLlKhKh/wr2Jcq8WMp2cMc6HNm7Y0l1HeUqdmOSVQKVMmL8c4P7PfJGdV0AphnF7nVv5+YZBCEvaAPv/qgrgFKFIRa6HfT8LzMM4ym7bDTdUE0ieE3xrjeVf49LAEYgqGK17at5xmWXw+ELPXcnH3iNdOauQMgODuVzQudhcVWtgcNtm/SIEUEoU2jg6WUzjM4jFc9zGH/fNXzFI2BXTAO71/yjsWZWFwHY5/ojLzXE+BeOWPx/38b3ET68H4aRSuxUEEoBGns9l5/oYOOvAEwzDGOJs2GsVAgAdl1p++o3GLt1J4JLGTH++cUd/6cA0IlA++o3rWcOiAAIhUbHy7P5qBPA9PLpzfOjDsPQ4+f//xnAWYZh3GQYxm475p+u55/NNabzswl2AIzXkt2ty3C4fTNjuM6GsFLOA3BekEZi/rnH/d5YquL/0Qi2vb3Qerb0m1YEIQt0/J7eeaybN4PPdVydv4cGX3v7nOf+MwCnG4bxOdvrZ3MWO4Yzifnzd/P69MdMrjXez/A18GudB3W5CKk/UuYBOg7usT23SxnLDTqm3JVqRzC7mAc9uUeFsSTmn1vc8f9YB/CR3ZuwZ/1y2/5nUwInCOnCAmDdb5xpITC9eCZ0dwPYBoDVbO8AYI50pTb0ejhchoZfw0Qkr1eXkOYDPkeCA2EUanIKsHXZ3xprZl36eBtzGscoZQOqREASvnknAkQWV9eFsOO95zlcUDkV3A0IQp5xGGE2d7G+P9NCYB3n7zAM45DXZdvdwxwjkbFz4/hZnilADz3T602E/p28zr2Wle96NoA90yJqvZhdq15rOvX6owHXtqGUw0BCfnAXB3ACqKr/X7vohU5ORf4pm/El3ZCcrp3d7UqPOifYXr7OY9FGMtaTbpw/LoZhFHxYohvrxTEPwIoNjobes/Zt9gPQo3N+czmUgwq5wSv8M79mVhDhQ3ux/d1F1nuqIN6/jp/aZNIvIxSOLuujY985g/H4XD3oqetpoPbnORWsXF1nst+T6OY6qjQCVgPP5jeeLMdyUCF3uKt/VP1/da2JnR+8isPtW6zyz/wmgO0pi9ymb7VeWdREYADQcyz9tFhUU/ABjDBzTbg2XCOulQXX7lCOJmYqGObI1SPfdy5X15ns96QoAHYYaMubf20aODa8tLqu0+AjhoFkFyAQr5BgU1Wdgc1LnrDuUH7LP+1YZsCO01ozhyIRUx0E0O88275IBap/CFhrwrXhGnGtLFbYa8i1zLvBFbpy7K/EGQbatepV+lBdwkBNCSuKhG5AnPBPAEf37cS2t6xxsoUL/5BXLdeP1csc5Ps1IBi0NyCZFoIIuYPev2mtCdfGuVZ67WR0X9FwuUl2GGjdcw+phh4X7q2/0P1wJ3/pJDTWzDKweemfOU9KVf/kOfxjo3NUfwRwABwDFw2b6HUSMOyb9qkwOQ8xC2lBNzJkrQXXhGvDNbJG9h0A1NoRqRYrEp0FQHluhoGt//jvpt6DtzAM5G4KkzBQ98Xt/ROr+cuMYv3zDxcy8M6Qgd19uRnAEwgEDAQCEVVSPeLnwMBzgQ6WhdPeUAh0X0wue23kd3n3W3HCDO+5aa0B14JrwrXhGnGtgCcMw9hsr6GEf4qEawdgN4VxjsvG1//AXYA7DFTqs4GEzPHy/tXxj3vWvKU6yQ0YBQr/aCgCNCbfs5p2uPtAVDmY454Fht8CmD2AcBgqxcVQhDzyfw94r3nPee+5BlwL60BgKgA/YYPV9+y1E+NfRDzOtrSTweuff7jpxJk3La2u6znddVh8qXYGC5nj5f0TFSp86/77rBySCv9k/iRpwtI824Pcaprm1QAWAQEWJUVhVAQwah4w+GvAzkeAA68ARwp7RHG3pWct0PccYPC1QK8J9m2gXVF5GjqdVxuGWrNglp20QpZ4Z8l0F+eUm/+rvu/QLz725rxwyJpXoZC5Ot2PLSMGd3rRtLLzamYZjcdNWYvn55yEaITxlqLM/9GGxDTN6wE8aF1HlC4oJ5oce49H2N2vrrH7LWBBsG91cKDj2Vjxw3qSgLYfNxiG8ZAYf3+Q4HR7w8C65x5s+sTtX2Sct94xHkKXhHLMglD+eHn/9uTPAFb96T8QDR+FEQzBjOSsSzId6EXaBoWGZQOA3wIBHoPH/GIY0aiBQNBAcKCUBRWEqIloxESAHn+QNoaPLQCuMwzjGTH+/sG7WJrJYMZzd658iY+5NbOYXeuUqZdcQPfBvdY0/vNrVOnnLqz5n/tU8rcwpZ9xcYjAMwCmWCLA4/CCIQQqgnZvgmRts5uSmeL9CwSse66MP48k5FpMEePvPxLvAPinvuqJf236xO0z3JfOXQA9w36OkctC+eHl/dulnyGs+tMvVf2/Twa/OUSAlUFfNU3zX3hMH4CzAYy3D8cW8g+9/VV2nT+rfTbyKcXz9x+Jt8Rs6Wdyr/6fn2nYt/FTt7QuiDjHRJMPXxiGGeNX+u+VCTkhbux/5Fnb8ELDBBzd32Y9UX5HP6SDXV3C7tLYrpXGB0B/+/dIKCg/6OTKPo97z7k6knzxGQl2AA7e/e23Gs//+fLp7S0VzoogMvGHG1mFLZQhXt4/Z/40Mvzz1v3fVyEgn3j/TmxDw7yAPtiD81IoBjoLLOQZW3AptDT80ujlUxILgC7t27/5Q2xsemxuzaxrH29r7rQLkIRweULj7479s/JnSVVdwHo/vP6H2A7Rp9hz19Wo81wOHBOSI0a/NEi+FVZhIJjoVTkMF8x7/4nlD1VOb2vmfL/Yz0pZaPnhDv2Qu8deEpk7bnYQTXfMxPbli/zo/QuCkDrJRybqIXGHd2/FB4/96LIpt6hOG+dT6ISwUB7ES/wq48+Jn2L8BaEsSC4A1v7Z6vJc+9wDPDCGh394lYXKnKDSxyv0w7LPeTWXGAgf2oeVv/+uNfPHP0lfQRAyIzUB0ANU2Ojz1q+/1njiRR1LqmuVYXA+7a7PV4oIlDhe/R2vV9dG5tbMDuD9//o+Dmxb4/fYvyAIqZGiAOhdQDDEHQCan/r3eTWzu+wCiDSIlS67LqvscvHc6V0+ZY512PuaZ+6TuL8glA+pC4ASAXYIB4JofuqOJuCNX9TMCnkdGhNvcJjgX7hm7gN/YqGfjgPteOfBGyX0IwjlRXoCoENBHPy17J6rGsfMaGds2B0K4i5ARKB08Ir7E1X1w9DP2w/cgAPbWiX0IwjlRZoC4EgIMxb89gM30EAwRuy+LRQBSQr7H66RV9jutera8Lxxs0NoXTBfVf6oYW88MEgQhHIhfQFQIsBQUDCkDEPrgvnza2aHwkCXSZCSFPY3NP5cIzexuH97yxtY8Z/flri/IJQnmQlATAQCQRqIJhNLvPIBRETAn8Qz/tac/0sMNeNn2T1XqRLg2DFagiCUE5kLAI0CjQMfS346q3H41LVe/QFEKoP8h9eaMJczt+YSzOUh70vunC0ln4JQ3mQhAGobYKrEIL3FpfMubxx9bhu9R69OYa8SQ6E4cC28Kn5iSV9W/LQ1L5a4vyCUN1kKgKM0lIeCL7lzNr1HepHuyiAaHGV4FleU9x31MSrs42H8yd1jL7aSvu89Mgfrnn+omCd8CYJQGJIPg0sVfSTgCRdcj8k3Pnjr6qcjDWsWBpxD4zSDntwjx0kWmHgxf/LzsZdYxp+G/50Hbjjm+cu4B0EoZ7LfAWg4JoIiYBsRDg5rqq6NuncCRBLDhSWR8Y+Ve8aMP6e/stxTjL8glDu52wFo0tgJ9G84KEdK5pl4TV7enn8geKzqRxCEcie1E8HSwbkTADB38o0PAojcumahEUDnHYeuRJFzhfNDYuN/cce8cbMrjnn+YvwFobuR+x1AnJ1AQ+sCzGldEHWLAJEDZXKL7u51V/oQhuQax14SVbP9Y2EfMf6C0B3JnwAQHQ4aeupMTL3lDw0bXqryOlheIyGh7EkU77eavGYFGmtmQVX7cMyDPvFNYv6C0O3IrwA4RaCqZiqm3fbXhk1Nw29uXRAOwTv8JCKQOYlCPhzvwEa9xrEXhbH84ZusUk/x/AWhO5N/AXCKQK+q4RSBekSnzml9OlLf1uJZJkpECFInUciHsNKH85qa+g5vwxs/+wx2ffi61PkLglAYAVAiQG8zGkGo9wBMvKYRx1/wdeYFJCSUOckMf6d4P43+2/dfh/1bWmS4myAIyiwX9DaoeDOHiwEUAEy8Zm7D+hf6JwoJyW7Am0ThHsKQzxVT5wSbqmqhYv0rH71NneOghVgQhG5PYQXA0hzDEoJoBANPPB2n/dPD9dHwabe2Loie2dbMOlHP5rTF1XX41HXvdPuS0VS8fp7PYIV8jtul4v2bFv/RvvXHBFgQhG5PEQTARlcIhXr3x8lX3oGxF3+TISHuBoJA0GuEhKY75geSGX7t9atEL6t8ti9/Bu/+/29h/5ZmGe0gCIIXxRMAazNwzCNlqeikr96DfsPrkuUGupMQpGL4Wd65pLoOl025JYCOg3vwweM/wpq/32vdY57kFelyWI8gCEJxBcBWASsuHQmjok8lxn3626i99LaGtc/0YOMYvyVeWKhchcB5TKNXM5eGSV7OW5pXM9uK9W98/TGs+uPtltfPxmv7CE9BEAQPfCAANs7k5IDRE3DKl+/CsNMu1rsBhoSSCQE7intO7yjZPEEq3r6y6YDJJC9PYVPhnr0frVBJ3m1v/93SVPH6BUFIjn8EwLJcxxLEZOikC3HSFf+Gqtpp6QgBYZ6A+H3OUKpGnzDUQ49fJXjp8R9u24QPHv8XfPTqo4iGj4rXLwhCOvhMAGyc4YtAsAKjz7kaNbPncGdAIbi1dQFrSdVcoUTJYo3eGfhBEFIN7zjha11cXWvGQj1H9mzD2kW/xtpF9+PInu2Wdtp9FoIgCCniTwGICYHDqAVCPTD67C/j+PO/huqP1VMI6ttbcEZbc0rhISdOQeDnPaZ3pHi7UkeffMYY/hH7FLRE8Xw3DPPQ8L9RXRfgKWvK49+3aRU2NT2OtYt+pUQgZvj1we2CIAip428BsCxc57AQYWho7EX/V1UOBSp66kmjeleQLFcQD6cwuOHXnHgZ80wMvRNt9JdU1yIAQ5VzKsPf9mET1r/wG3z02u8R7Thi3RbG+eXgFkEQMqcEBECjhcDh7fYfOR4j66/EyPor+DmFgLB6yBkiSiVMVCx4nXzwGpdW1x0z+gztbFn2V2x46XdKAGK3QQa4CYKQG0pIABzQCHJ8sR4rEajoqXYDI6Z+FkMmXYjeg0ZpMWCYaGpbc5gG1vnIze1LHxp7evp80ODzmmKefvjQXuxY8aIy/NveWhgL83iJnyAIQpYUzRDmBJUsNgwrFGLDzuIhE87H4JNnYOjkmWwso2A4BYF5AxpgvTPQIaNc7hS0kdcf+bsZz+9k8MmhnRuw473nsXPVq9jx7rM4tGtjJ2/fKXSCIAg5pLQF4JiltPIExCkG3ClQACgEg8afjf6jTtKCwJ3B9Lbm2G/g/09ra4555/oLyUTBfeg9xWRJdZ3abTB+zxlGRMXylcHf9RH2bfwAbc2L1biGPeuXI3LEqlkl6nUE5GB2QRDyTpkIgBMtBtwZuEYgaEHoN3I8Ko+fhAFjJqHP4DHoe1yNGlOtQktQYuDGKRbaqLuJGXnScaAdh3dvxaGdH6G99U0c2Loa+z5aib0bV3Yy+Mro83mpGdFoLKwlCIKQZ8pQANxiwNfIwiDmDByhIicVfQeiV9UI9Kwchj5DjkefISeohtuKPgNRecKpME0TBg20A/1vB3esx8Ed69RobRr9PevfReTwfuzf2oLwoX2ez6m9/Fh4h5EiQRCEwvK/X1fMgAYEcgAAAAAASUVORK5CYII=';

-- DreamLand: eerst onzichtbaar; de workflow "Winkel publiceren" zet hem live via beheer (aanvragen dicht + push).
insert into public.pasr_stores (id, name, domain, category, card_hex, format, kind, aliases, logo, published, published_at)
values ('dreamland', 'DreamLand', 'dreamland.nl', 'Cadeaukaarten', '#3A1FC5', 'code128', 'voucher',
        array['dreamland', 'dream land', 'dreamland cadeaubon', 'dreamland cadeaubonnen', 'dreamland cadeaukaart', 'dreamland keuze cadeaubon'],
        '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', false, null)
on conflict (id) do nothing;
insert into public.pasr_balance_pages (store_id, url)
values ('dreamland', 'https://www.dreamland.nl/cadeaubonnen/cadeaubon-saldo-checker')
on conflict (store_id) do nothing;

-- Smyths Toys: eerst onzichtbaar; de workflow "Winkel publiceren" zet hem live (aanvragen dicht + push).
insert into public.pasr_stores (id, name, domain, category, card_hex, format, kind, aliases, logo, published, published_at)
values ('smyths', 'Smyths Toys', 'smythstoys.com', 'Cadeaukaarten', '#BB1D29', 'code128', 'voucher',
        array['smyths', 'smyths toys', 'smythstoys', 'smyths cadeaukaart', 'smyths toys cadeaukaart', 'smyths giftcard'],
        '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', false, null)
on conflict (id) do nothing;
insert into public.pasr_balance_pages (store_id, url)
values ('smyths', 'https://www.smythstoys.com/nl/nl-nl/cadeaukaart/cadeaukaart-saldo')
on conflict (store_id) do nothing;

-- Prénatal: klantenkaart en cadeaukaart, eerst onzichtbaar; de workflow "Winkel publiceren" zet ze live.
insert into public.pasr_stores (id, name, domain, category, card_hex, format, kind, aliases, logo, published, published_at)
values ('prenatal', 'Prénatal', 'prenatal.nl', 'Warenhuis en wonen', '#644682', 'code128', 'loyalty',
        array['prenatal', 'prénatal', 'prenatal klantenkaart', 'prenatal pas'],
        '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', false, null),
       ('prenatal-cadeaukaart', 'Prénatal cadeaukaart', 'prenatal.nl', 'Cadeaukaarten', '#644682', 'code128', 'voucher',
        array['prenatal cadeaukaart', 'prénatal cadeaukaart', 'prenatal giftcard', 'prenatal cadeaubon'],
        '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', false, null)
on conflict (id) do nothing;
insert into public.pasr_balance_pages (store_id, url)
values ('prenatal-cadeaukaart', 'https://www.prenatal.nl/cadeaukaart/')
on conflict (store_id) do nothing;

-- Saldo-pagina's uit de cadeaukaartendatabase (gecontroleerd 2026-11-21): alleen geverifieerde, directe saldocheckers.
-- "do nothing": een adres dat in het beheer is aangepast blijft staan.
insert into public.pasr_balance_pages (store_id, url)
values ('action', 'https://www.action.com/nl-nl/saldo-cadeaukaart-checken/'),
       ('action2', 'https://www.action.com/nl-nl/saldo-cadeaukaart-checken/'),
       ('ah', 'https://service2.loyaltyinabox.com/CardBalanceChecker/2/paymentapi.aspx?cmd=showbalance&username=1379001&lang=nl-NL'),
       ('ahcadeau', 'https://service2.loyaltyinabox.com/CardBalanceChecker/2/paymentapi.aspx?cmd=showbalance&username=1379001&lang=nl-NL'),
       ('bijenkorf', 'https://www.debijenkorf.nl/klantenservice/De-Bijenkorf-Cadeaucard'),
       ('bijenkorfgift', 'https://www.debijenkorf.nl/klantenservice/De-Bijenkorf-Cadeaucard'),
       ('boekenbon', 'https://boekenbon.nl/bestellen/saldocheck'),
       ('bol', 'https://www.bol.com/nl/nl/sf/cadeaubon-bestellen/'),
       ('bol2', 'https://www.bol.com/nl/nl/sf/cadeaubon-bestellen/'),
       ('coolblue', 'https://www.coolblue.nl/saldo-checker'),
       ('decathlon', 'https://www.decathlon.nl/services/giftcard/balance'),
       ('decathlon2', 'https://www.decathlon.nl/services/giftcard/balance'),
       ('dirk', 'https://www.dirk.nl/meer/over-dirk/dirk-cadeaukaart/cadeaukaart-dirk'),
       ('douglas', 'https://www.douglas.nl/nl/cp/gift-card-details-page/giftcarddetails'),
       ('fashioncheque', 'https://www.fashioncheque.com/nl-nl/check-je-saldo'),
       ('hm', 'https://www2.hm.com/nl_nl/customer-service/gift-card.html'),
       ('hm2', 'https://www2.hm.com/nl_nl/customer-service/gift-card.html'),
       ('hollandbarrett', 'https://www.hollandandbarrett.nl/gift-card/saldochecker'),
       ('hunkemoller', 'https://giftcard.hunkemoller.nl/BalanceChecker'),
       ('hunkemoller2', 'https://giftcard.hunkemoller.nl/BalanceChecker'),
       ('ici', 'https://www.iciparisxl.nl/egiftcard'),
       ('intertoys', 'https://kadokaart.intertoys.nl/BalanceChecker'),
       ('intertoyscadeau', 'https://kadokaart.intertoys.nl/BalanceChecker'),
       ('intratuin', 'https://www.intratuin.nl/cadeaukaart#saldochecker'),
       ('jumbo', 'https://www.icpmimas.nl/jumbo/Default.aspx?culture=nl-NL'),
       ('jumbofoodmarkt', 'https://www.icpmimas.nl/jumbo/Default.aspx?culture=nl-NL'),
       ('kruidvat', 'https://www.kruidvat.nl/cadeaukaart'),
       ('kruidvatv', 'https://www.kruidvat.nl/cadeaukaart'),
       ('mediamarkt', 'https://www.mediamarkt.nl/nl/service/giftCard'),
       ('nelson', 'https://www.nelson.nl/cadeaukaart/'),
       ('omoda', 'https://www.omoda.nl/account/cadeaubon-saldo/'),
       ('pathe', 'https://www.pathe.nl/nl/giftcard'),
       ('plus', 'https://service2.loyaltyinabox.com/CardBalanceChecker/2/paymentapi.aspx?cmd=showbalance&username=2528001&lang=nl-NL'),
       ('podiumcadeau', 'https://podiumcadeaukaart.nl/ik-heb-een-cadeaukaart/saldo-checken'),
       ('praxis', 'https://www.praxis.nl/service/cadeaukaart#saldo-check'),
       ('primera', 'https://www.primera.nl/saldo-checker'),
       ('vvv', 'https://www.vvvcadeaukaarten.nl/saldocheck'),
       ('wehkamp', 'https://www.wehkamp.nl/klantenservice/cadeaukaart/'),
       ('xenos', 'https://www.xenos.nl/saldochecker'),
       ('ytickets', 'https://www.yourgift.nl/saldochecker/'),
       ('zara', 'https://www.zara.com/nl/nl/z-zara-card/balance?c=815540')
on conflict (store_id) do nothing;

-- Klantenkaarten voor winkels met een cadeaukaart in de database (gecontroleerd 2026-11-21 op de eigen sites):
-- Obelink Member, Vrijbuiter spaarpas, Swarovski Club, Oil & Vinegar member (Food Lovers Club Card), SNIPES CLUB
-- (Loyalty-ID), Foot Locker FLX (membernummer), VILA Club (Membership ID) en de Ouwehands abonnementspas.
-- Eerst onzichtbaar; de workflow "Winkel publiceren" zet ze live.
insert into public.pasr_stores (id, name, domain, category, card_hex, format, kind, aliases, logo, published, published_at)
values ('obelink', 'Obelink', 'obelink.nl', 'Sport en fitness', '#0032A0', 'code128', 'loyalty',
        array['obelink', 'obelink member', 'obelink membercard', 'obelink klantenkaart'],
        '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',
        false, null),
       ('vrijbuiter', 'Vrijbuiter', 'vrijbuiter.nl', 'Sport en fitness', '#1C4546', 'code128', 'loyalty',
        array['vrijbuiter', 'vrijbuiter spaarpas', 'vrijbuiter spaarpunten'],
        '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',
        false, null),
       ('swarovski', 'Swarovski', 'swarovski.com', 'Mode en schoenen', '#000000', 'code128', 'loyalty',
        array['swarovski', 'swarovski club', 'swarovski lidmaatschap'],
        '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',
        false, null),
       ('oilvinegar', 'Oil & Vinegar', 'oilvinegar.nl', 'Drank en eten', '#EAE6DA', 'code128', 'loyalty',
        array['oil & vinegar', 'oil and vinegar', 'oil vinegar', 'oil & vinegar member', 'food lovers club'],
        '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',
        false, null),
       ('snipes', 'SNIPES', 'snipes.com', 'Mode en schoenen', '#EA640C', 'code128', 'loyalty',
        array['snipes', 'snipes club', 'snipes loyalty id'],
        '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',
        false, null),
       ('footlocker', 'Foot Locker', 'footlocker.nl', 'Mode en schoenen', '#111111', 'code128', 'loyalty',
        array['foot locker', 'footlocker', 'flx', 'foot locker flx', 'kids foot locker'],
        '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',
        false, null),
       ('vila', 'VILA', 'vila.com', 'Mode en schoenen', '#1A1A1A', 'ean13', 'loyalty',
        array['vila', 'vila club', 'vila membership'],
        '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',
        false, null),
       ('ouwehand', 'Ouwehands Dierenpark', 'ouwehand.nl', 'Uitgaan en vrije tijd', '#FFFFFF', 'code128', 'loyalty',
        array['ouwehands', 'ouwehand', 'ouwehands dierenpark', 'ouwehands abonnement', 'ouwehands abonnementspas'],
        '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',
        false, null)
on conflict (id) do nothing;

-- ===============================================================================================================
-- Review-account voor Apple App Review (beheer › Review-account maken). Het account zelf maakt de functie `admin`
-- (auth admin API, met het wachtwoord dat de beheerder kiest; dat wordt nergens bewaard of gelogd). Deze functie zet
-- er voorbeeldkaarten in: drie privékaarten en een gedeelde Pasr "Gezin" met twee kaarten. Opnieuw draaien zet alles
-- terug (vaste kaart-id's per account, de groep wordt hergebruikt).
-- ===============================================================================================================
create or replace function public.pasr_admin_user_id(p_email text) returns uuid
language sql stable security definer set search_path = public, auth as $$
  select id from auth.users where lower(email) = lower(btrim(p_email)) limit 1
$$;
revoke all on function public.pasr_admin_user_id(text) from public, anon, authenticated;

create or replace function public.pasr_admin_review_seed(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  k text; gid uuid; now_ts timestamptz := clock_timestamp(); c jsonb; i int := 0;
  priv jsonb := jsonb_build_array(
    jsonb_build_object('storeName', 'Albert Heijn', 'templateID', 'ah', 'number', '2620123456782', 'format', 'ean13',
                       'kind', 'loyalty', 'colorHex', '#00A0E2', 'isFavorite', true),
    jsonb_build_object('storeName', 'Lidl Plus', 'templateID', 'lidl', 'number', 'LP-4821-7730-1956', 'format', 'qr',
                       'kind', 'loyalty', 'colorHex', '#0050AA'),
    jsonb_build_object('storeName', 'Bakkers Cadeau', 'templateID', 'bakkerscadeau', 'number', '6012345678901234',
                       'format', 'code128', 'kind', 'voucher', 'colorHex', '#B5814A', 'balance', 25, 'currencyCode', 'EUR',
                       'pin', '4821', 'expiresAt', to_char((now() + interval '1 year') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  grp jsonb := jsonb_build_array(
    jsonb_build_object('storeName', 'HEMA', 'templateID', 'hema', 'number', '2639876543212', 'format', 'ean13',
                       'kind', 'loyalty', 'colorHex', '#E30613'),
    jsonb_build_object('storeName', 'IKEA Family', 'templateID', 'ikea', 'number', '6275980012345678', 'format', 'code128',
                       'kind', 'loyalty', 'colorHex', '#0058A3'));
begin
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'user not found' using errcode = 'P0002'; end if;
  select card_key into k from public.pasr_secret where id = 1;

  for c in select * from jsonb_array_elements(priv) loop
    i := i + 1;
    insert into public.pasr_cards as p (user_id, id, payload, updated_at, deleted, server_at)
    values (p_user, md5(p_user::text || ':review:' || i)::uuid,
            pgp_sym_encrypt((c || jsonb_build_object('note', '', 'isLocked', false, 'useCount', 0,
                             'createdAt', to_char(now_ts at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')))::text, k, 'cipher-algo=aes256'),
            now_ts, false, now_ts)
    on conflict (user_id, id) do update set payload = excluded.payload, updated_at = excluded.updated_at,
      deleted = false, server_at = clock_timestamp();
  end loop;

  select g.id into gid from public.pasr_groups g join public.pasr_group_members m on m.group_id = g.id
  where m.user_id = p_user and g.created_by = p_user and g.name = 'Gezin' limit 1;
  if gid is null then
    if (select count(*) from public.pasr_group_members where user_id = p_user) >= 2 then
      raise exception 'group_limit' using errcode = 'P0001';
    end if;
    insert into public.pasr_groups (name, created_by) values ('Gezin', p_user) returning id into gid;
    insert into public.pasr_group_members (group_id, user_id) values (gid, p_user);
  end if;
  i := 0;
  for c in select * from jsonb_array_elements(grp) loop
    i := i + 1;
    insert into public.pasr_group_cards as p (group_id, id, payload, updated_at, deleted, updated_by, server_at)
    values (gid, md5(gid::text || ':review:' || i)::uuid,
            pgp_sym_encrypt((c || jsonb_build_object('note', '', 'isFavorite', false, 'isLocked', false, 'useCount', 0,
                             'createdAt', to_char(now_ts at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')))::text, k, 'cipher-algo=aes256'),
            now_ts, false, p_user, now_ts)
    on conflict (group_id, id) do update set payload = excluded.payload, updated_at = excluded.updated_at,
      deleted = false, updated_by = excluded.updated_by, server_at = clock_timestamp();
  end loop;
  return jsonb_build_object('ok', true, 'group_id', gid, 'cards', jsonb_array_length(priv), 'group_cards', jsonb_array_length(grp));
end $$;
revoke all on function public.pasr_admin_review_seed(uuid) from public, anon, authenticated;

-- ============================================================================================================
-- Herinneringen per e-mail (Pasr 1.0.2, app-agent). Wie dat in de app aanzet (Instellingen › Meldingen ›
-- Herinneren via: E-mail of Beide) krijgt vanaf support@pasr.nl een mail als een voucher of kortingscode bijna
-- verloopt (7 dagen ervoor en op de dag), twee dagen voor de verlenging van een abonnement, en (instelbaar: elke week,
-- maand of kwartaal) een overzicht van het tegoed op cadeaukaarten. Alleen de eigen kaarten in het account tellen mee
-- (niet die in een gedeelde Pasr). Elke ochtend kiest pasr_mail_due wat er te melden is (uit de versleutelde kaarten);
-- de functie reminder-mail stuurt de mails via SMTP en schrijft met pasr_mail_sent weg wat er verstuurd is, zodat
-- niets twee keer gaat. Afmelden: in de app, via de link in de mail (pasr.nl/afmelden/) of met één klik in het
-- mailprogramma (List-Unsubscribe).
-- ============================================================================================================
create table if not exists public.pasr_mail_prefs (
  user_id          uuid primary key references auth.users (id) on delete cascade,
  expiry           boolean not null default true,
  balance          boolean not null default true,
  balance_interval text not null default 'month' check (balance_interval in ('week', 'month', 'quarter')),
  tz               text not null default 'Europe/Amsterdam',
  unsub_token      text not null default encode(extensions.gen_random_bytes(16), 'hex'),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index if not exists pasr_mail_prefs_unsub on public.pasr_mail_prefs (unsub_token);
create table if not exists public.pasr_mail_log (
  user_id uuid not null references auth.users (id) on delete cascade,
  key     text not null,
  sent_at timestamptz not null default now(),
  primary key (user_id, key)
);
alter table public.pasr_mail_prefs enable row level security;
alter table public.pasr_mail_log enable row level security;
revoke all on public.pasr_mail_prefs, public.pasr_mail_log from anon, authenticated;
alter table public.pasr_admin_config add column if not exists reminder_url text;

-- Aan- of uitzetten vanuit de app (alleen voor jezelf). p_enabled false = geen mails meer (de rij gaat weg).
create or replace function public.pasr_mail_prefs_set(p_enabled boolean, p_expiry boolean default true,
                                                      p_balance boolean default true, p_interval text default 'month',
                                                      p_tz text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); zone text := 'Europe/Amsterdam';
begin
  if uid is null then raise exception 'not signed in' using errcode = '28000'; end if;
  if not coalesce(p_enabled, false) then
    delete from public.pasr_mail_prefs where user_id = uid;
    return jsonb_build_object('enabled', false);
  end if;
  if p_tz is not null and exists (select 1 from pg_timezone_names where name = p_tz) then zone := p_tz; end if;
  insert into public.pasr_mail_prefs as m (user_id, expiry, balance, balance_interval, tz)
  values (uid, coalesce(p_expiry, true), coalesce(p_balance, true),
          case when p_interval in ('week', 'month', 'quarter') then p_interval else 'month' end, zone)
  on conflict (user_id) do update set expiry = excluded.expiry, balance = excluded.balance,
    balance_interval = excluded.balance_interval, tz = excluded.tz, updated_at = now();
  return jsonb_build_object('enabled', true);
end $$;

create or replace function public.pasr_mail_prefs_get() returns jsonb
language sql security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('enabled', true, 'expiry', m.expiry, 'balance', m.balance,
                                             'interval', m.balance_interval)
                   from public.pasr_mail_prefs m where m.user_id = auth.uid()),
                  jsonb_build_object('enabled', false));
$$;
revoke all on function public.pasr_mail_prefs_set(boolean, boolean, boolean, text, text), public.pasr_mail_prefs_get()
  from public, anon;
grant execute on function public.pasr_mail_prefs_set(boolean, boolean, boolean, text, text), public.pasr_mail_prefs_get()
  to authenticated;

-- Afmelden met de code uit de mail (pasr.nl/afmelden/ en List-Unsubscribe). De code is 128 bits willekeurig.
create or replace function public.pasr_mail_unsubscribe(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if coalesce(p_token, '') !~ '^[0-9a-f]{32}$' then return jsonb_build_object('ok', false); end if;
  delete from public.pasr_mail_prefs where unsub_token = p_token;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'removed', n > 0);
end $$;
revoke all on function public.pasr_mail_unsubscribe(text) from public;
grant execute on function public.pasr_mail_unsubscribe(text) to anon, authenticated;

-- Wat er vandaag te mailen is, per gebruiker: [{user_id, email, first_name, unsub, items:[…]}]. Een item:
--   {key, type: expiry|renew|balance, kind, store, days, date, balance, currency, cost, period}
-- Alleen voor de functie reminder-mail (service role). Items die al verstuurd zijn (pasr_mail_log) vallen weg.
create or replace function public.pasr_mail_due(p_now timestamptz default now()) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  k text;
  m record;
  r record;
  c jsonb;
  today date;
  d date;
  days int;
  bal numeric;
  items jsonb;
  balance_items jsonb;
  balance_day boolean;
  result jsonb := '[]'::jsonb;
begin
  select card_key into k from public.pasr_secret where id = 1;
  for m in
    select p.*, u.email, coalesce(u.raw_user_meta_data->>'first_name', '') as first_name
    from public.pasr_mail_prefs p join auth.users u on u.id = p.user_id
    where u.email is not null and u.email_confirmed_at is not null and (p.expiry or p.balance)
  loop
    today := (p_now at time zone m.tz)::date;
    balance_day := m.balance and case m.balance_interval
      when 'week' then extract(isodow from today) = 6
      when 'quarter' then extract(day from today) = 1 and extract(month from today) in (1, 4, 7, 10)
      else extract(day from today) = 1 end;
    items := '[]'::jsonb;
    balance_items := '[]'::jsonb;
    for r in select pc.id, pc.payload from public.pasr_cards pc where pc.user_id = m.user_id and not pc.deleted loop
      begin
        c := pgp_sym_decrypt(r.payload, k)::jsonb;
        -- vervaldatum: voucher en kortingscode, 7 dagen ervoor en op de dag
        if m.expiry and c->>'kind' in ('voucher', 'code') and coalesce(c->>'expiresAt', '') <> '' then
          d := ((c->>'expiresAt')::timestamptz at time zone m.tz)::date;
          days := d - today;
          if days in (7, 0) then
            bal := case when c->>'kind' = 'voucher' and jsonb_typeof(c->'balance') = 'number' then (c->>'balance')::numeric end;
            items := items || jsonb_build_object('key', 'exp:' || r.id || ':' || d || ':' || days, 'type', 'expiry',
              'kind', c->>'kind', 'store', left(coalesce(c->>'storeName', ''), 60), 'days', days, 'date', d,
              'balance', bal, 'currency', coalesce(c->>'currencyCode', 'EUR'));
          end if;
        end if;
        -- abonnement: twee dagen voor de verlenging
        if m.expiry and c->>'kind' = 'subscription' and coalesce(c->'details'->>'renewsAt', '') <> '' then
          d := ((c->'details'->>'renewsAt')::timestamptz at time zone m.tz)::date;
          if d - today = 2 then
            items := items || jsonb_build_object('key', 'renew:' || r.id || ':' || d, 'type', 'renew',
              'kind', 'subscription', 'store', left(coalesce(c->>'storeName', ''), 60), 'days', 2, 'date', d,
              'cost', case when jsonb_typeof(c->'details'->'cost') = 'number' then (c->'details'->>'cost')::numeric end,
              'period', coalesce(c->'details'->>'period', 'month'), 'currency', coalesce(c->>'currencyCode', 'EUR'));
          end if;
        end if;
        -- tegoed: cadeaukaarten met tegoed die niet verlopen zijn, ook zonder vervaldatum
        if balance_day and c->>'kind' = 'voucher' and jsonb_typeof(c->'balance') = 'number' and (c->>'balance')::numeric > 0
           and (coalesce(c->>'expiresAt', '') = '' or ((c->>'expiresAt')::timestamptz at time zone m.tz)::date >= today) then
          balance_items := balance_items || jsonb_build_object('type', 'balance', 'kind', 'voucher',
            'store', left(coalesce(c->>'storeName', ''), 60), 'balance', (c->>'balance')::numeric,
            'currency', coalesce(c->>'currencyCode', 'EUR'),
            'date', case when coalesce(c->>'expiresAt', '') <> '' then ((c->>'expiresAt')::timestamptz at time zone m.tz)::date end);
        end if;
      exception when others then
        continue;   -- een kaart met vreemde waarden slaan we over; de rest gaat gewoon door
      end;
    end loop;
    if jsonb_array_length(balance_items) > 0 then
      -- één overzicht per keer; de sleutel is de dag, zodat het niet twee keer gaat
      select coalesce(jsonb_agg(e.value || jsonb_build_object('key', 'bal:' || today)), '[]'::jsonb) into balance_items
      from jsonb_array_elements(balance_items) as e(value);
      items := items || balance_items;
    end if;
    select coalesce(jsonb_agg(e.value), '[]'::jsonb) into items from jsonb_array_elements(items) as e(value)
    where not exists (select 1 from public.pasr_mail_log l where l.user_id = m.user_id and l.key = e.value->>'key');
    if jsonb_array_length(items) > 0 then
      result := result || jsonb_build_object('user_id', m.user_id, 'email', m.email, 'first_name', left(m.first_name, 40),
                                       'unsub', m.unsub_token, 'items', items);
    end if;
  end loop;
  return result;
end $$;

-- Verstuurd: de sleutels wegschrijven (de functie reminder-mail, na een geslaagde mail).
create or replace function public.pasr_mail_sent(p_user uuid, p_keys text[]) returns void
language sql security definer set search_path = public as $$
  insert into public.pasr_mail_log (user_id, key)
  select p_user, unnest(p_keys) on conflict do nothing;
$$;
revoke all on function public.pasr_mail_due(timestamptz), public.pasr_mail_sent(uuid, text[]) from public, anon, authenticated;
grant execute on function public.pasr_mail_due(timestamptz), public.pasr_mail_sent(uuid, text[]) to service_role;

-- Elke ochtend (07:05 UTC, 08:05 of 09:05 in Nederland): seintje aan de functie reminder-mail. Het adres zet de workflow
-- Backend (pasr_admin_config.reminder_url); leeg = er gebeurt niets. Het logboek houdt 400 dagen bij.
create or replace function public.pasr_mail_kick() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare u text; s text;
begin
  delete from public.pasr_mail_log where sent_at < now() - interval '400 days';
  select reminder_url into u from public.pasr_admin_config where id = 1;
  select hook_secret into s from public.pasr_secret where id = 1;
  if coalesce(u, '') = '' or s is null then return; end if;
  if not exists (select 1 from public.pasr_mail_prefs) then return; end if;
  perform net.http_post(url := u, body := jsonb_build_object('action', 'run'),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-pasr-hook', s),
    timeout_milliseconds := 120000);
exception when others then
  raise warning 'pasr_mail_kick: %', sqlerrm;
end $$;
revoke all on function public.pasr_mail_kick() from public, anon, authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'pasr-mail-reminders';
  perform cron.schedule('pasr-mail-reminders', '5 7 * * *', 'select public.pasr_mail_kick()');
exception when others then
  raise notice 'pg_cron niet beschikbaar: %', sqlerrm;
end $$;

-- ===============================================================================================================
-- 1.0.3 app
-- ===============================================================================================================

-- Wallet-passen bijwerken vanaf de server (Apple PassKit-webservice, functie wallet-pass). Per pas staan de gegevens
-- hier versleuteld (AES-GCM) met een sleutel uit het authenticationToken van de pas; dat token kent alleen het
-- apparaat met de pas (en de iCloud-sleutelhanger van de eigenaar). Hier staat alleen een hash ervan, zodat de server
-- een verzoek van Wallet kan controleren. member_code alleen bij een zakelijke stempelkaart (om de pas bij een nieuwe
-- stempel bij te werken); dat is geen persoonsgegeven.
create table if not exists public.pasr_wallet_passes (
  serial text primary key check (serial ~ '^[0-9A-Fa-f-]{36}$'),
  token_hash text not null check (token_hash ~ '^[0-9a-f]{64}$'),
  data text not null check (char_length(data) <= 1400000),
  member_code text check (member_code is null or char_length(member_code) <= 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists pasr_wallet_passes_member on public.pasr_wallet_passes (member_code) where member_code is not null;
-- Welk apparaat (Wallet) welke pas heeft, met het push-token dat Apple daarvoor gaf.
create table if not exists public.pasr_wallet_registrations (
  device text not null check (char_length(device) between 1 and 128),
  serial text not null references public.pasr_wallet_passes (serial) on delete cascade,
  push_token text not null check (char_length(push_token) between 16 and 200),
  created_at timestamptz not null default now(),
  primary key (device, serial)
);
create index if not exists pasr_wallet_registrations_serial on public.pasr_wallet_registrations (serial);
alter table public.pasr_wallet_passes enable row level security;
alter table public.pasr_wallet_registrations enable row level security;
revoke all on public.pasr_wallet_passes, public.pasr_wallet_registrations from anon, authenticated;

-- Nieuwe stand van een zakelijke stempelkaart: seintje aan de functie wallet-pass, die Apple vraagt de passen in
-- Wallet bij te werken. Alleen als er een pas van die klantcode is. Via pg_net: houdt de stempel nooit op.
create or replace function public.pasr_wallet_business_kick() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare u text; s text;
begin
  if new.stamps_count is not distinct from old.stamps_count then return new; end if;
  if not exists (select 1 from public.pasr_wallet_passes where member_code = new.member_code) then return new; end if;
  select admin_url into u from public.pasr_admin_config where id = 1;
  select hook_secret into s from public.pasr_secret where id = 1;
  if coalesce(u, '') = '' or s is null then return new; end if;
  u := regexp_replace(u, '/admin/?$', '/wallet-pass');
  perform net.http_post(url := u, body := jsonb_build_object('action', 'business', 'code', new.member_code),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-pasr-hook', s), timeout_milliseconds := 30000);
  return new;
exception when others then
  raise warning 'pasr_wallet_business_kick: %', sqlerrm;
  return new;
end $$;
revoke all on function public.pasr_wallet_business_kick() from public, anon, authenticated;
-- De tabel pasr_business_members maakt het blok "1.0.3 web"; bestaat hij (nog) niet, dan volgt de trigger bij de
-- volgende keer dat dit schema draait.
do $$
begin
  if to_regclass('public.pasr_business_members') is not null then
    drop trigger if exists pasr_wallet_business on public.pasr_business_members;
    create trigger pasr_wallet_business after update of stamps_count on public.pasr_business_members
      for each row execute function public.pasr_wallet_business_kick();
  end if;
exception when others then
  raise notice 'pasr_wallet_business trigger: %', sqlerrm;
end $$;

-- Opruimen: passen die meer dan 400 dagen niet zijn bijgewerkt en op geen enkel apparaat meer staan.
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'pasr-wallet-cleanup';
  perform cron.schedule('pasr-wallet-cleanup', '35 3 * * *',
    $q$delete from public.pasr_wallet_passes p where p.updated_at < now() - interval '400 days'
       and not exists (select 1 from public.pasr_wallet_registrations r where r.serial = p.serial)$q$);
exception when others then
  raise notice 'pg_cron niet beschikbaar: %', sqlerrm;
end $$;

-- Verjaardag (alleen dag en maand) voor het verjaardagsvoordeel. Optioneel; wissen laat een lege rij met de tijd
-- staan, zodat je andere apparaten ook zien dat hij weg is.
create table if not exists public.pasr_birthdays (
  user_id uuid primary key references auth.users (id) on delete cascade,
  day smallint check (day between 1 and 31),
  month smallint check (month between 1 and 12),
  updated_at timestamptz not null default now(),
  check ((day is null) = (month is null))
);
alter table public.pasr_birthdays enable row level security;
revoke all on public.pasr_birthdays from anon, authenticated;

create or replace function public.pasr_birthday_get() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('day', b.day, 'month', b.month, 'updated_at', b.updated_at)
                   from public.pasr_birthdays b where b.user_id = auth.uid()), '{}'::jsonb);
$$;

create or replace function public.pasr_birthday_set(p_day int, p_month int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); ts timestamptz := now();
begin
  if uid is null then raise exception 'not signed in' using errcode = '28000'; end if;
  if (p_day is null) <> (p_month is null) then raise exception 'bad_birthday' using errcode = '22023'; end if;
  if p_day is not null then
    begin
      perform make_date(2000, p_month, p_day);   -- 2000 is een schrikkeljaar: 29 februari mag
    exception when others then
      raise exception 'bad_birthday' using errcode = '22023';
    end;
  end if;
  insert into public.pasr_birthdays as b (user_id, day, month, updated_at) values (uid, p_day, p_month, ts)
  on conflict (user_id) do update set day = excluded.day, month = excluded.month, updated_at = ts;
  return jsonb_build_object('ok', true, 'updated_at', ts);
end $$;
revoke all on function public.pasr_birthday_get(), public.pasr_birthday_set(int, int) from public, anon;
grant execute on function public.pasr_birthday_get(), public.pasr_birthday_set(int, int) to authenticated;

-- 1.0.3 web
-- ============================================================================================================
-- Pasr 1.0.3, agent WEB: gerichte pushberichten (opt-in), Pasr voor ondernemers (stempelkaarten) en de gids-sleutel
-- `birthday`. Alles via security definer-functies; de tabellen zelf zijn dicht voor anon en authenticated.
-- ============================================================================================================

-- Rem per internetadres (gehasht met het hook-geheim, nooit het adres zelf) per soort per dag.
create table if not exists public.pasr_web_rate (
  bucket text not null,
  ip_hash text not null,
  day date not null,
  n int not null default 0,
  primary key (bucket, ip_hash, day)
);
alter table public.pasr_web_rate enable row level security;
revoke all on public.pasr_web_rate from anon, authenticated;

create or replace function public.pasr_web_rate_hit(p_bucket text, p_per_ip int, p_total int) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare ip text; used int; today date := (now() at time zone 'utc')::date;
begin
  ip := split_part(coalesce(current_setting('request.headers', true)::json->>'x-forwarded-for', 'unknown'), ',', 1);
  ip := encode(digest(ip || coalesce((select hook_secret from public.pasr_secret where id = 1), ''), 'sha256'), 'hex');
  insert into public.pasr_web_rate as r (bucket, ip_hash, day, n) values (p_bucket, ip, today, 1)
    on conflict (bucket, ip_hash, day) do update set n = r.n + 1 returning n into used;
  if used > p_per_ip or (select coalesce(sum(n), 0) from public.pasr_web_rate where bucket = p_bucket and day = today) > p_total then
    raise exception 'rate_limited' using errcode = '22023';
  end if;
end $$;
revoke all on function public.pasr_web_rate_hit(text, int, int) from public, anon, authenticated;

-- ------------------------------------------------------------------------------------------------------------
-- Gerichte pushberichten (5). Alleen wie in de app "Nieuws over mijn kaarten" aanzet, staat hierin: het apparaat
-- (willekeurige id), het APNs-token en de winkel-id's (template-id's) van de kaarten. Geen kaartnummers, geen namen.
-- Werkt ook zonder Pasr-account. Het beheer (functie admin) kiest een doelgroep en stuurt via APNs.
-- ------------------------------------------------------------------------------------------------------------
create table if not exists public.pasr_news_devices (
  device_id text primary key check (device_id ~ '^[A-Za-z0-9_-]{8,80}$'),
  token text check (token is null or token ~ '^[0-9a-f]{64,200}$'),   -- leeg: het token staat in pasr_user_push
  sandbox boolean not null default false,
  stores text[] not null default '{}',
  user_id uuid references auth.users (id) on delete set null,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now()
);
create index if not exists pasr_news_devices_stores on public.pasr_news_devices using gin (stores);
create index if not exists pasr_news_devices_last on public.pasr_news_devices (last_seen);
create index if not exists pasr_news_devices_first on public.pasr_news_devices (first_seen);
create table if not exists public.pasr_news_campaigns (
  id uuid primary key default gen_random_uuid(),
  title text check (title is null or char_length(title) <= 60),
  body text not null check (char_length(body) between 1 and 240),
  audience text not null check (audience in ('all', 'store', 'new', 'inactive')),
  store_id text,
  recipients int not null default 0,
  sent int not null default 0,
  failed int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.pasr_news_devices alter column token drop not null;
alter table public.pasr_news_devices enable row level security;
alter table public.pasr_news_campaigns enable row level security;
revoke all on public.pasr_news_devices, public.pasr_news_campaigns from anon, authenticated;

create or replace function public.pasr_news_register(p_device text, p_token text, p_sandbox boolean default false,
                                                     p_stores text[] default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare t text := lower(trim(coalesce(p_token, ''))); s text[];
begin
  if coalesce(p_device, '') !~ '^[A-Za-z0-9_-]{8,80}$' then raise exception 'bad_device' using errcode = '22023'; end if;
  if t !~ '^[0-9a-f]{64,200}$' then raise exception 'bad_token' using errcode = '22023'; end if;
  -- alleen geldige winkel-id's, uniek, hoogstens 300
  select coalesce(array_agg(x order by x), '{}') into s
  from (select distinct lower(x) x from unnest(coalesce(p_stores, '{}')) x where lower(x) ~ '^[a-z0-9-]{2,40}$' limit 300) q;
  if not exists (select 1 from public.pasr_news_devices where device_id = p_device) then
    perform public.pasr_web_rate_hit('news', 30, 50000);
  end if;
  insert into public.pasr_news_devices as d (device_id, token, sandbox, stores, user_id)
  values (p_device, t, coalesce(p_sandbox, false), s, auth.uid())
  on conflict (device_id) do update set token = excluded.token, sandbox = excluded.sandbox, stores = excluded.stores,
    user_id = coalesce(auth.uid(), d.user_id), last_seen = now();
  -- één token hoort bij één apparaat
  delete from public.pasr_news_devices where token = t and device_id <> p_device;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.pasr_news_unregister(p_device text) returns jsonb
language sql security definer set search_path = public as $$
  delete from public.pasr_news_devices where device_id = p_device;
  select jsonb_build_object('ok', true);
$$;

-- Zo doet de app het (1.0.3, met een Pasr-account): het apparaat staat al in pasr_user_push (token, sandbox; elke
-- start bijgewerkt) en meldt hier alleen of "Nieuws over mijn kaarten" aanstaat en welke winkels erin staan.
-- p_enabled false = de rij weg. Het token komt bij het versturen uit pasr_user_push.
create or replace function public.pasr_push_stores(p_device text, p_enabled boolean, p_stores text[] default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s text[];
begin
  if uid is null then raise exception 'not signed in' using errcode = '28000'; end if;
  if coalesce(p_device, '') !~ '^[A-Za-z0-9_-]{8,80}$' then raise exception 'bad_device' using errcode = '22023'; end if;
  if not coalesce(p_enabled, false) then
    delete from public.pasr_news_devices where device_id = p_device and (user_id = uid or user_id is null);
    return jsonb_build_object('ok', true, 'enabled', false);
  end if;
  select coalesce(array_agg(x order by x), '{}') into s
  from (select distinct lower(x) x from unnest(coalesce(p_stores, '{}')) x where lower(x) ~ '^[a-z0-9-]{2,40}$' limit 300) q;
  insert into public.pasr_news_devices as d (device_id, token, sandbox, stores, user_id)
  select p_device, u.token, coalesce(u.sandbox, false), s, uid
  from (select 1) one left join public.pasr_user_push u on u.device_id = p_device and u.user_id = uid
  on conflict (device_id) do update set stores = excluded.stores, user_id = uid,
    token = coalesce(excluded.token, d.token), sandbox = excluded.sandbox, last_seen = now();
  return jsonb_build_object('ok', true, 'enabled', true);
end $$;

-- Voor de functie admin: de apparaten van een doelgroep. new = de laatste p_days dagen aangezet, inactive = al
-- p_days dagen de app niet geopend, store = heeft een kaart van die winkel.
create or replace function public.pasr_admin_news_targets(p_audience text, p_store text default null, p_days int default null)
returns table (device_id text, token text, sandbox boolean)
language sql stable security definer set search_path = public as $$
  -- token en omgeving: bij voorkeur uit pasr_user_push (houdt de app bij elke start bij), anders van de opt-in zelf;
  -- laatst actief: de opt-in of de laatste aanmelding van het pushtoken, wat het nieuwst is
  select d.device_id, coalesce(u.token, d.token), coalesce(u.sandbox, d.sandbox)
  from public.pasr_news_devices d left join public.pasr_user_push u on u.device_id = d.device_id
  where coalesce(u.token, d.token) is not null and case p_audience
    when 'all' then true
    when 'store' then d.stores @> array[lower(coalesce(p_store, ''))]
    when 'new' then d.first_seen > now() - make_interval(days => coalesce(p_days, 7))
    when 'inactive' then greatest(d.last_seen, coalesce(u.updated_at, d.last_seen)) < now() - make_interval(days => coalesce(p_days, 30))
    else false end;
$$;
-- Tellingen voor het scherm "Bericht sturen": per doelgroep, en de winkels die het vaakst voorkomen.
create or replace function public.pasr_admin_news_overview() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'all', (select count(*) from public.pasr_admin_news_targets('all')),
    'new', (select count(*) from public.pasr_admin_news_targets('new')),
    'inactive', (select count(*) from public.pasr_admin_news_targets('inactive')),
    'stores', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'count', n) order by n desc, id), '[]'::jsonb)
               from (select x id, count(*) n from public.pasr_news_devices, unnest(stores) x group by x order by n desc, x limit 400) q));
$$;
revoke all on function public.pasr_news_register(text, text, boolean, text[]), public.pasr_news_unregister(text),
  public.pasr_push_stores(text, boolean, text[]),
  public.pasr_admin_news_targets(text, text, int), public.pasr_admin_news_overview() from public;
grant execute on function public.pasr_news_register(text, text, boolean, text[]), public.pasr_news_unregister(text) to anon, authenticated;
grant execute on function public.pasr_push_stores(text, boolean, text[]) to authenticated;
grant execute on function public.pasr_admin_news_targets(text, text, int), public.pasr_admin_news_overview() to service_role;

-- ------------------------------------------------------------------------------------------------------------
-- Pasr voor ondernemers (8). Een zaak meldt zich aan op pasr.nl/zakelijk met een Pasr-account (e-mail + wachtwoord);
-- Léon keurt hem goed in het beheer. Daarna ontwerpt de zaak een stempelkaart, deelt de join-link/QR
-- (pasr.nl/zakelijk/kaart/#<kaart-id>) en zet stempels met de web-scanner (pasr.nl/zakelijk/scan). Klanten hebben
-- een lidcode (member_code); daar hangt niets persoonlijks aan, ook geen account als ze zonder inloggen aansluiten.
-- ------------------------------------------------------------------------------------------------------------
create table if not exists public.pasr_businesses (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null unique references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 2 and 60),
  city text not null default '' check (char_length(city) <= 60),
  email text not null default '' check (char_length(email) <= 200),
  website text check (website is null or char_length(website) <= 200),
  note text check (note is null or char_length(note) <= 300),
  status text not null default 'pending' check (status in ('pending', 'approved', 'blocked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create table if not exists public.pasr_business_cards (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.pasr_businesses (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  logo text check (logo is null or (octet_length(logo) <= 210000 and logo ~ '^(/9j/|iVBORw0KGgo)[A-Za-z0-9+/]+=*$')),
  color text not null default '#6A5CFF' check (color ~ '^#[0-9A-F]{6}$'),
  kind text not null default 'stamps' check (kind in ('stamps', 'points')),
  stamps_total int not null default 10 check (stamps_total between 2 and 30),
  reward text not null check (char_length(reward) between 1 and 80),
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists pasr_business_cards_business on public.pasr_business_cards (business_id);
create table if not exists public.pasr_business_members (
  id uuid primary key default gen_random_uuid(),
  business_card_id uuid not null references public.pasr_business_cards (id) on delete cascade,
  member_code text not null unique check (member_code ~ '^PZ[A-HJ-NP-Z2-9]{10}$'),
  stamps_count int not null default 0 check (stamps_count between 0 and 1000),
  rewards_redeemed int not null default 0 check (rewards_redeemed >= 0),
  user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_stamp_at timestamptz
);
create index if not exists pasr_business_members_card on public.pasr_business_members (business_card_id, created_at);
create table if not exists public.pasr_business_events (
  id bigint generated always as identity primary key,
  business_card_id uuid not null references public.pasr_business_cards (id) on delete cascade,
  member_id uuid references public.pasr_business_members (id) on delete cascade,
  kind text not null check (kind in ('join', 'stamp', 'redeem')),
  amount int not null default 1,
  by_user uuid,
  at timestamptz not null default now()
);
create index if not exists pasr_business_events_card on public.pasr_business_events (business_card_id, at);
alter table public.pasr_businesses enable row level security;
alter table public.pasr_business_cards enable row level security;
alter table public.pasr_business_members enable row level security;
alter table public.pasr_business_events enable row level security;
revoke all on public.pasr_businesses, public.pasr_business_cards, public.pasr_business_members, public.pasr_business_events
  from anon, authenticated;

-- Wallet-passen van zakelijke stempelkaarten bijwerken (blok "1.0.3 app", functie pasr_wallet_business_kick): de trigger
-- hier ook zetten, zodat hij er meteen bij de eerste keer is (dat blok staat eerder in dit bestand dan deze tabel).
do $$
begin
  if to_regprocedure('public.pasr_wallet_business_kick()') is not null then
    drop trigger if exists pasr_wallet_business on public.pasr_business_members;
    create trigger pasr_wallet_business after update of stamps_count on public.pasr_business_members
      for each row execute function public.pasr_wallet_business_kick();
  end if;
exception when others then
  raise notice 'pasr_wallet_business trigger: %', sqlerrm;
end $$;

-- Wat iedereen van een kaart mag zien (join-pagina, app, Wallet-pas): geen e-mail, geen eigenaar.
create or replace function public.pasr_business_card_json(c public.pasr_business_cards, b public.pasr_businesses) returns jsonb
language sql immutable as $$
  select jsonb_build_object('id', c.id, 'name', c.name, 'business', b.name, 'city', b.city, 'logo', c.logo, 'color', c.color,
    'kind', c.kind, 'stamps_total', c.stamps_total, 'reward', c.reward);
$$;

create or replace function public.pasr_business_card_public(p_card uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select public.pasr_business_card_json(c, b) from public.pasr_business_cards c join public.pasr_businesses b on b.id = c.business_id
  where c.id = p_card and c.published and b.status = 'approved';
$$;

-- Zelfde, onder de naam die de app gebruikt.
create or replace function public.pasr_business_card(p_card uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select public.pasr_business_card_public(p_card);
$$;

-- pasr_business_new_code (lidcode van 16 tekens): blok "zakelijk 1.0".

create or replace function public.pasr_business_member_json(m public.pasr_business_members, c public.pasr_business_cards,
                                                            b public.pasr_businesses) returns jsonb
language sql immutable as $$
  select jsonb_build_object('status', 'ok', 'name', c.name, 'business', b.name, 'member_code', m.member_code, 'stamps_count', m.stamps_count,
    'stamps_total', c.stamps_total, 'reward', c.reward, 'rewards_redeemed', m.rewards_redeemed, 'updated_at', m.updated_at,
    'card', public.pasr_business_card_json(c, b));
$$;

-- Aansluiten bij een kaart: nieuwe lidcode. Zonder account kan; ingelogd wordt het lidmaatschap aan je account gekoppeld.
create or replace function public.pasr_business_join(p_card uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.pasr_business_cards; b public.pasr_businesses; m public.pasr_business_members;
begin
  select * into c from public.pasr_business_cards where id = p_card and published;
  select * into b from public.pasr_businesses where id = c.business_id and status = 'approved';
  if c.id is null or b.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  perform public.pasr_web_rate_hit('join', 40, 100000);
  if (select count(*) from public.pasr_business_events where business_card_id = c.id and kind = 'join'
        and at > now() - interval '1 hour') >= 500 then
    raise exception 'rate_limited' using errcode = '22023';
  end if;
  insert into public.pasr_business_members (business_card_id, member_code, user_id)
  values (c.id, public.pasr_business_new_code(), auth.uid()) returning * into m;
  insert into public.pasr_business_events (business_card_id, member_id, kind, amount, by_user) values (c.id, m.id, 'join', 0, auth.uid());
  return public.pasr_business_member_json(m, c, b);
end $$;

-- Actuele stand met de lidcode (app, Wallet-pas, webpagina). Niets persoonlijks.
create or replace function public.pasr_business_member(p_code text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m public.pasr_business_members; c public.pasr_business_cards; b public.pasr_businesses;
begin
  select * into m from public.pasr_business_members where member_code = upper(trim(coalesce(p_code, '')));
  if m.id is null then return jsonb_build_object('status', 'not_found'); end if;
  select * into c from public.pasr_business_cards where id = m.business_card_id;
  select * into b from public.pasr_businesses where id = c.business_id;
  if not c.published or b.status <> 'approved' then return jsonb_build_object('status', 'blocked'); end if;
  return public.pasr_business_member_json(m, c, b);
end $$;

-- ---- voor de ondernemer (ingelogd) ----
-- pasr_business_json: blok "zakelijk 1.0" (met afkoeltijd en max per scan).

create or replace function public.pasr_business_register(p_name text, p_city text default '', p_website text default null,
                                                         p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n text; b public.pasr_businesses; mail text; isnew boolean;
begin
  if uid is null then raise exception 'not signed in' using errcode = '28000'; end if;
  select email into mail from auth.users where id = uid and email_confirmed_at is not null;
  if mail is null then raise exception 'not_confirmed' using errcode = '28000'; end if;
  n := left(regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g'), 60);
  if char_length(n) < 2 then raise exception 'bad_name' using errcode = '22023'; end if;
  select * into b from public.pasr_businesses where owner = uid;
  if b.status = 'blocked' then raise exception 'blocked' using errcode = '42501'; end if;
  isnew := b.id is null;
  insert into public.pasr_businesses as x (owner, name, city, email, website, note)
  values (uid, n, left(trim(coalesce(p_city, '')), 60), mail, nullif(left(trim(coalesce(p_website, '')), 200), ''),
          nullif(left(trim(coalesce(p_note, '')), 300), ''))
  on conflict (owner) do update set name = excluded.name, city = excluded.city, email = excluded.email,
    website = excluded.website, note = excluded.note, updated_at = now()
  returning * into b;
  if isnew then perform public.pasr_admin_notify('business', jsonb_build_object('name', n)); end if;
  return public.pasr_business_json(b);
end $$;

-- pasr_business_me: blok "zakelijk 1.0" (alle zaken waar je eigenaar of medewerker bent).

-- Kaart opslaan (nieuw zonder id). Publiceren kan pas als de zaak is goedgekeurd. Hoogstens 5 kaarten per zaak.
-- (Blok "zakelijk 1.0" vervangt deze functie met text_color.)
create or replace function public.pasr_business_card_save(p_card jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); b public.pasr_businesses; c public.pasr_business_cards; cid uuid; lg text;
        nm text; rw text; col text; tot int; pub boolean;
begin
  if uid is null then raise exception 'not signed in' using errcode = '28000'; end if;
  select * into b from public.pasr_businesses where owner = uid;
  if b.id is null then raise exception 'no_business' using errcode = '42501'; end if;
  if b.status = 'blocked' then raise exception 'blocked' using errcode = '42501'; end if;
  if jsonb_typeof(p_card) <> 'object' or octet_length(p_card::text) > 230000 then raise exception 'bad_card' using errcode = '22023'; end if;
  nm := left(regexp_replace(trim(coalesce(p_card->>'name', '')), '\s+', ' ', 'g'), 40);
  rw := left(regexp_replace(trim(coalesce(p_card->>'reward', '')), '\s+', ' ', 'g'), 80);
  col := upper(coalesce(p_card->>'color', '#6A5CFF'));
  tot := coalesce((p_card->>'stamps_total')::int, 10);
  if nm = '' then raise exception 'bad_name' using errcode = '22023'; end if;
  if rw = '' then raise exception 'bad_reward' using errcode = '22023'; end if;
  if col !~ '^#[0-9A-F]{6}$' then raise exception 'bad_color' using errcode = '22023'; end if;
  if tot not between 2 and 30 then raise exception 'bad_total' using errcode = '22023'; end if;
  lg := nullif(regexp_replace(coalesce(p_card->>'logo', ''), '^data:image/[a-z]+;base64,', ''), '');
  if lg is not null and (octet_length(lg) > 210000 or lg !~ '^(/9j/|iVBORw0KGgo)[A-Za-z0-9+/]+=*$') then
    raise exception 'bad_logo' using errcode = '22023';
  end if;
  pub := coalesce((p_card->>'published')::boolean, false) and b.status = 'approved';
  cid := nullif(p_card->>'id', '')::uuid;
  if cid is null then
    if (select count(*) from public.pasr_business_cards where business_id = b.id) >= 5 then
      raise exception 'card_limit' using errcode = '22023';
    end if;
    insert into public.pasr_business_cards (business_id, name, logo, color, stamps_total, reward, published)
    values (b.id, nm, lg, col, tot, rw, pub) returning * into c;
  else
    update public.pasr_business_cards set name = nm, logo = case when p_card ? 'logo' then lg else logo end, color = col,
      stamps_total = tot, reward = rw, published = pub, updated_at = now()
    where id = cid and business_id = b.id returning * into c;
    if c.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  end if;
  return public.pasr_business_card_json(c, b) || jsonb_build_object('published', c.published);
end $$;

create or replace function public.pasr_business_card_delete(p_card uuid) returns jsonb
language sql security definer set search_path = public as $$
  delete from public.pasr_business_cards c using public.pasr_businesses b
  where c.id = p_card and c.business_id = b.id and b.owner = auth.uid();
  select jsonb_build_object('ok', true);
$$;

-- Leden, scanner (pasr_business_scan/_stamp/_redeem) en beheer (pasr_admin_businesses): blok "zakelijk 1.0"
-- (rollen eigenaar/medewerker, afkoeltijd, ongedaan maken).

revoke all on function public.pasr_business_card_json(public.pasr_business_cards, public.pasr_businesses),
  public.pasr_business_member_json(public.pasr_business_members, public.pasr_business_cards, public.pasr_businesses),
  public.pasr_business_card_public(uuid), public.pasr_business_card(uuid), public.pasr_business_join(uuid), public.pasr_business_member(text),
  public.pasr_business_register(text, text, text, text), public.pasr_business_card_save(jsonb),
  public.pasr_business_card_delete(uuid) from public;
grant execute on function public.pasr_business_card_public(uuid), public.pasr_business_card(uuid), public.pasr_business_join(uuid), public.pasr_business_member(text)
  to anon, authenticated;
grant execute on function public.pasr_business_register(text, text, text, text),
  public.pasr_business_card_save(jsonb), public.pasr_business_card_delete(uuid) to authenticated;

-- Opruimen: de rem van gisteren en eerder, en pushapparaten die al 400 dagen niets van zich lieten horen.
create or replace function public.pasr_web_cleanup() returns void
language sql security definer set search_path = public as $$
  delete from public.pasr_web_rate where day < (now() at time zone 'utc')::date - 1;
  delete from public.pasr_news_devices where last_seen < now() - interval '400 days';
$$;
revoke all on function public.pasr_web_cleanup() from public, anon, authenticated;
do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'pasr-web-cleanup';
  perform cron.schedule('pasr-web-cleanup', '41 3 * * *', 'select public.pasr_web_cleanup()');
exception when others then
  raise notice 'pg_cron niet beschikbaar: %', sqlerrm;
end $$;

-- Gids-sleutel birthday (verjaardagsvoordeel, tekst tot 160 tekens): gevuld uit supabase/catalog/birthdays.json door
-- supabase/catalog/guides.py, één keer per winkel (pasr_store_birthday_seeded); haalt het beheer hem weg, dan komt hij
-- niet terug.
create table if not exists public.pasr_store_birthday_seeded (id text primary key, at timestamptz not null default now());
alter table public.pasr_store_birthday_seeded enable row level security;
revoke all on public.pasr_store_birthday_seeded from anon, authenticated;

-- ============================================================================================================
-- zakelijk 1.0 (Pasr Zakelijk 1.0.0 en Pasr 1.0.3 build 43). Alleen de ondernemer en zijn medewerkers zetten
-- stempels, nooit de klant. Rollen per zaak: 'owner' (de eigenaar, pasr_businesses.owner) of 'staff' (uitgenodigd).
-- Afkoeltijd en max per scan per zaak, ongedaan maken binnen 2 minuten, een log die ondernemers niet kunnen wissen,
-- stats per dag, lidcodes van 16 tekens en het overnemen van een browser-lidcode in de app (pasr_business_claim).
--
-- Fouten van de scanner- en medewerkerfuncties: message = nette Nederlandse zin (zo tonen), hint = vaste code
-- (cooldown, too_many, not_approved, not_found, other_business, not_enough, too_soon, undo_expired, undo_not_latest,
-- not_allowed, invite_invalid, invite_own, staff_limit, bad_settings, bad_amount, not_signed_in), details = bij
-- cooldown het aantal seconden tot het weer mag (tekst). PostgREST geeft {code, message, details, hint}.
-- ============================================================================================================

-- ---- instellingen per zaak ----
alter table public.pasr_businesses add column if not exists cooldown_minutes int not null default 5;
-- max per scan: de ondernemer kiest per scan 1 tot max_per_scan stempels (aantal-kiezer, standaard 1)
alter table public.pasr_businesses add column if not exists max_per_scan int not null default 10;
alter table public.pasr_businesses alter column max_per_scan set default 10;
-- vindbaar in Pasr (Kaart toevoegen › Stempelkaart): aan/uit, adres en optioneel een locatie voor "In de buurt"
alter table public.pasr_businesses add column if not exists listed boolean not null default true;
alter table public.pasr_businesses add column if not exists address text;
alter table public.pasr_businesses add column if not exists lat double precision;
alter table public.pasr_businesses add column if not exists lng double precision;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'pasr_businesses_cooldown_check') then
    alter table public.pasr_businesses add constraint pasr_businesses_cooldown_check check (cooldown_minutes between 0 and 1440);
  end if;
  if exists (select 1 from pg_constraint where conname = 'pasr_businesses_max_per_scan_check') then
    alter table public.pasr_businesses drop constraint pasr_businesses_max_per_scan_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pasr_businesses_max_per_scan_v2') then
    alter table public.pasr_businesses add constraint pasr_businesses_max_per_scan_v2 check (max_per_scan between 1 and 30);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pasr_businesses_place_check') then
    alter table public.pasr_businesses add constraint pasr_businesses_place_check check (
      (address is null or char_length(address) <= 200) and (lat is null) = (lng is null)
      and (lat is null or (lat between -90 and 90 and lng between -180 and 180)));
  end if;
end $$;

-- ---- lidcodes: nieuw 16 tekens (PZ + 14), de bestaande van 12 blijven geldig ----
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'pasr_business_members_member_code_check') then
    alter table public.pasr_business_members drop constraint pasr_business_members_member_code_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pasr_business_members_code_v2') then
    alter table public.pasr_business_members add constraint pasr_business_members_code_v2
      check (member_code ~ '^PZ([A-HJ-NP-Z2-9]{10}|[A-HJ-NP-Z2-9]{14})$');
  end if;
end $$;

create or replace function public.pasr_business_new_code() returns text
language plpgsql volatile security definer set search_path = public, extensions as $$
declare alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; code text; bytes bytea; i int;
begin
  loop
    bytes := gen_random_bytes(14); code := 'PZ';
    for i in 0..13 loop code := code || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1); end loop;
    exit when not exists (select 1 from public.pasr_business_members where member_code = code);
  end loop;
  return code;
end $$;

-- ---- medewerkers ----
create table if not exists public.pasr_business_staff (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.pasr_businesses (id) on delete cascade,
  user_id uuid references auth.users (id) on delete cascade,            -- leeg tot de uitnodiging is aangenomen
  role text not null default 'staff' check (role in ('owner', 'staff')),
  name text not null default '' check (char_length(name) <= 60),
  invited_email text check (invited_email is null or char_length(invited_email) <= 200),
  invite_code text unique check (invite_code is null or invite_code ~ '^[A-HJ-NP-Z2-9]{20}$'),
  invite_expires_at timestamptz,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  revoked_at timestamptz
);
create unique index if not exists pasr_business_staff_active on public.pasr_business_staff (business_id, user_id)
  where revoked_at is null and user_id is not null;
create index if not exists pasr_business_staff_user on public.pasr_business_staff (user_id) where revoked_at is null;
alter table public.pasr_business_staff enable row level security;
revoke all on public.pasr_business_staff from anon, authenticated;

-- Eigenaar staat er ook in (migratie van bestaande zaken, en elke nieuwe zaak via de trigger).
insert into public.pasr_business_staff (business_id, user_id, role, name, invited_email, created_at, accepted_at)
select b.id, b.owner, 'owner', '', b.email, b.created_at, b.created_at from public.pasr_businesses b
where b.owner is not null and not exists (select 1 from public.pasr_business_staff s where s.business_id = b.id and s.role = 'owner' and s.revoked_at is null);

create or replace function public.pasr_business_owner_row() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.pasr_business_staff where business_id = new.id and role = 'owner' and revoked_at is null) then
    insert into public.pasr_business_staff (business_id, user_id, role, invited_email, accepted_at)
    values (new.id, new.owner, 'owner', new.email, now());
  end if;
  return new;
end $$;
revoke all on function public.pasr_business_owner_row() from public, anon, authenticated;
drop trigger if exists pasr_business_owner_row on public.pasr_businesses;
create trigger pasr_business_owner_row after insert on public.pasr_businesses
  for each row execute function public.pasr_business_owner_row();

-- Rol van de ingelogde gebruiker bij een zaak: 'owner', 'staff' of null.
create or replace function public.pasr_business_role(p_business uuid) returns text
language sql stable security definer set search_path = public as $$
  select case
    when auth.uid() is null then null
    when exists (select 1 from public.pasr_businesses where id = p_business and owner = auth.uid()) then 'owner'
    else (select s.role from public.pasr_business_staff s where s.business_id = p_business and s.user_id = auth.uid()
          and s.revoked_at is null order by s.role = 'owner' desc limit 1)
  end;
$$;

-- ---- events: wie, welk apparaat, ongedaan maken; blijven staan als een kaart of lid verdwijnt ----
alter table public.pasr_business_events add column if not exists event_id uuid not null default gen_random_uuid();
alter table public.pasr_business_events add column if not exists business_id uuid references public.pasr_businesses (id) on delete cascade;
alter table public.pasr_business_events add column if not exists member_suffix text;
alter table public.pasr_business_events add column if not exists device text check (device is null or char_length(device) <= 80);
alter table public.pasr_business_events add column if not exists stamps_before int;
alter table public.pasr_business_events add column if not exists stamps_after int;
alter table public.pasr_business_events add column if not exists undone_at timestamptz;
alter table public.pasr_business_events add column if not exists undo_of uuid;
alter table public.pasr_business_events alter column business_card_id drop not null;
create unique index if not exists pasr_business_events_event_id on public.pasr_business_events (event_id);
create index if not exists pasr_business_events_business on public.pasr_business_events (business_id, at);
create index if not exists pasr_business_events_member on public.pasr_business_events (member_id, at);
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'pasr_business_events_kind_check') then
    alter table public.pasr_business_events drop constraint pasr_business_events_kind_check;
  end if;
  -- (blok "zakelijk 1.1" vervangt hem door kind_v3 met 'admin'; dan niet opnieuw zetten)
  if not exists (select 1 from pg_constraint where conname in ('pasr_business_events_kind_v2', 'pasr_business_events_kind_v3')) then
    alter table public.pasr_business_events add constraint pasr_business_events_kind_v2
      check (kind in ('join', 'stamp', 'redeem', 'undo', 'claim'));
  end if;
  -- een kaart of lid verwijderen wist de log niet meer (on delete set null in plaats van cascade)
  if exists (select 1 from pg_constraint where conname = 'pasr_business_events_business_card_id_fkey' and confdeltype = 'c') then
    alter table public.pasr_business_events drop constraint pasr_business_events_business_card_id_fkey;
    alter table public.pasr_business_events add constraint pasr_business_events_business_card_id_fkey
      foreign key (business_card_id) references public.pasr_business_cards (id) on delete set null;
  end if;
  if exists (select 1 from pg_constraint where conname = 'pasr_business_events_member_id_fkey' and confdeltype = 'c') then
    alter table public.pasr_business_events drop constraint pasr_business_events_member_id_fkey;
    alter table public.pasr_business_events add constraint pasr_business_events_member_id_fkey
      foreign key (member_id) references public.pasr_business_members (id) on delete set null;
  end if;
end $$;
-- kaartnaam bewaren voor de log (ook als de kaart later weg is)
alter table public.pasr_business_events add column if not exists card_name text;
update public.pasr_business_events e set business_id = c.business_id, card_name = coalesce(e.card_name, c.name)
from public.pasr_business_cards c where c.id = e.business_card_id and (e.business_id is null or e.card_name is null);
update public.pasr_business_events e set member_suffix = right(m.member_code, 4)
from public.pasr_business_members m where m.id = e.member_id and e.member_suffix is null;

create or replace function public.pasr_business_event_fill() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.business_card_id is not null and (new.business_id is null or new.card_name is null) then
    select coalesce(new.business_id, c.business_id), coalesce(new.card_name, c.name) into new.business_id, new.card_name
    from public.pasr_business_cards c where c.id = new.business_card_id;
  end if;
  if new.member_id is not null and new.member_suffix is null then
    select right(m.member_code, 4) into new.member_suffix from public.pasr_business_members m where m.id = new.member_id;
  end if;
  return new;
end $$;
revoke all on function public.pasr_business_event_fill() from public, anon, authenticated;
drop trigger if exists pasr_business_event_fill on public.pasr_business_events;
create trigger pasr_business_event_fill before insert on public.pasr_business_events
  for each row execute function public.pasr_business_event_fill();

-- Ondernemers kunnen events niet wissen of wijzigen: geen policies, geen grants, geen RPC (alleen undone_at via undo).

-- ---- tekstkleur op de kaart (wit of zwart op de kaartkleur; leeg = de app/website kiest zelf) ----
alter table public.pasr_business_cards add column if not exists text_color text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'pasr_business_cards_text_color_check') then
    alter table public.pasr_business_cards add constraint pasr_business_cards_text_color_check
      check (text_color is null or text_color ~ '^#[0-9A-F]{6}$');
  end if;
end $$;

-- Wat iedereen van een kaart mag zien (join-pagina, app, Wallet-pas, scanner, zoeklijst): nu met text_color.
create or replace function public.pasr_business_card_json(c public.pasr_business_cards, b public.pasr_businesses) returns jsonb
language sql immutable as $$
  select jsonb_build_object('id', c.id, 'name', c.name, 'business', b.name, 'city', b.city, 'logo', c.logo, 'color', c.color,
    'text_color', c.text_color, 'kind', c.kind, 'stamps_total', c.stamps_total, 'reward', c.reward);
$$;

-- Kaart opslaan (vervangt de versie uit blok 1.0.3 web): ook text_color.
create or replace function public.pasr_business_card_save(p_card jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); b public.pasr_businesses; c public.pasr_business_cards; cid uuid; lg text;
        nm text; rw text; col text; tot int; pub boolean; tc text;
begin
  if uid is null then raise exception 'not signed in' using errcode = '28000'; end if;
  select * into b from public.pasr_businesses where owner = uid;
  if b.id is null then raise exception 'no_business' using errcode = '42501'; end if;
  if b.status = 'blocked' then raise exception 'blocked' using errcode = '42501'; end if;
  if jsonb_typeof(p_card) <> 'object' or octet_length(p_card::text) > 230000 then raise exception 'bad_card' using errcode = '22023'; end if;
  nm := left(regexp_replace(trim(coalesce(p_card->>'name', '')), '\s+', ' ', 'g'), 40);
  rw := left(regexp_replace(trim(coalesce(p_card->>'reward', '')), '\s+', ' ', 'g'), 80);
  col := upper(coalesce(p_card->>'color', '#6A5CFF'));
  tot := coalesce((p_card->>'stamps_total')::int, 10);
  if nm = '' then raise exception 'bad_name' using errcode = '22023'; end if;
  if rw = '' then raise exception 'bad_reward' using errcode = '22023'; end if;
  if col !~ '^#[0-9A-F]{6}$' then raise exception 'bad_color' using errcode = '22023'; end if;
  if tot not between 2 and 30 then raise exception 'bad_total' using errcode = '22023'; end if;
  -- tekstkleur op de kaart (Pasr Zakelijk, huisstijl van de website): #RRGGBB of leeg
  tc := nullif(upper(coalesce(p_card->>'text_color', '')), '');
  if tc is not null and tc !~ '^#[0-9A-F]{6}$' then raise exception 'bad_color' using errcode = '22023'; end if;
  lg := nullif(regexp_replace(coalesce(p_card->>'logo', ''), '^data:image/[a-z]+;base64,', ''), '');
  if lg is not null and (octet_length(lg) > 210000 or lg !~ '^(/9j/|iVBORw0KGgo)[A-Za-z0-9+/]+=*$') then
    raise exception 'bad_logo' using errcode = '22023';
  end if;
  pub := coalesce((p_card->>'published')::boolean, false) and b.status = 'approved';
  cid := nullif(p_card->>'id', '')::uuid;
  if cid is null then
    if (select count(*) from public.pasr_business_cards where business_id = b.id) >= 5 then
      raise exception 'card_limit' using errcode = '22023';
    end if;
    insert into public.pasr_business_cards (business_id, name, logo, color, stamps_total, reward, published, text_color)
    values (b.id, nm, lg, col, tot, rw, pub, tc) returning * into c;
  else
    update public.pasr_business_cards set name = nm, logo = case when p_card ? 'logo' then lg else logo end, color = col,
      stamps_total = tot, reward = rw, published = pub, updated_at = now(),
      text_color = case when p_card ? 'text_color' then tc else text_color end
    where id = cid and business_id = b.id returning * into c;
    if c.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  end if;
  return public.pasr_business_card_json(c, b) || jsonb_build_object('published', c.published);
end $$;

-- ---- json ----
create or replace function public.pasr_business_json(b public.pasr_businesses) returns jsonb
language sql immutable as $$
  select jsonb_build_object('id', b.id, 'name', b.name, 'city', b.city, 'email', b.email, 'website', b.website, 'note', b.note,
    'status', b.status, 'created_at', b.created_at, 'reviewed_at', b.reviewed_at,
    'cooldown_minutes', b.cooldown_minutes, 'max_per_scan', b.max_per_scan,
    'listed', b.listed, 'address', b.address, 'lat', b.lat, 'lng', b.lng);
$$;

-- Kaarten van een zaak; met tellingen (leden, stempels, beloningen) als p_stats.
create or replace function public.pasr_business_cards_json(b public.pasr_businesses, p_stats boolean) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.pasr_business_card_json(c, b) || jsonb_build_object('published', c.published, 'updated_at', c.updated_at)
      || case when p_stats then jsonb_build_object(
        'members', (select count(*) from public.pasr_business_members m where m.business_card_id = c.id),
        'stamps', (select coalesce(sum(amount), 0) from public.pasr_business_events e where e.business_card_id = c.id and e.kind = 'stamp' and e.undone_at is null),
        'rewards', (select count(*) from public.pasr_business_events e where e.business_card_id = c.id and e.kind = 'redeem' and e.undone_at is null))
      else '{}'::jsonb end
      order by c.created_at), '[]'::jsonb)
  from public.pasr_business_cards c where c.business_id = b.id;
$$;

-- Alle zaken van de ingelogde gebruiker (eigenaar of medewerker). business/cards bovenaan = de eigen zaak (zoals
-- 1.0.3, voor het web-dashboard); businesses = alles met role per zaak. Medewerkers zien kaarten zonder tellingen.
create or replace function public.pasr_business_me() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); b public.pasr_businesses; list jsonb;
begin
  if uid is null then raise exception 'not signed in' using errcode = '28000', hint = 'not_signed_in'; end if;
  select coalesce(jsonb_agg(public.pasr_business_json(x) || jsonb_build_object('role', r.role,
      'cards', public.pasr_business_cards_json(x, r.role = 'owner'))
      order by r.role = 'owner' desc, x.name), '[]'::jsonb) into list
  from (select distinct on (bid) bid, role from (
          select id bid, 'owner' role from public.pasr_businesses where owner = uid
          union all
          select business_id, s.role from public.pasr_business_staff s where s.user_id = uid and s.revoked_at is null) q
        order by bid, role = 'owner' desc) r
  join public.pasr_businesses x on x.id = r.bid;
  select * into b from public.pasr_businesses where owner = uid;
  if b.id is null then return jsonb_build_object('business', null, 'cards', '[]'::jsonb, 'businesses', list); end if;
  return jsonb_build_object('business', public.pasr_business_json(b) || jsonb_build_object('role', 'owner'),
    'cards', public.pasr_business_cards_json(b, true), 'businesses', list);
end $$;

-- ---- interne hulpjes (zonder rechtencheck; alleen via de functies hieronder en het beheer) ----
create or replace function public.pasr_business_staff_json(p_business uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name,
      'email', coalesce(u.email, s.invited_email), 'role', s.role, 'created_at', s.created_at, 'accepted_at', s.accepted_at,
      'pending', s.user_id is null and s.revoked_at is null, 'expired', s.user_id is null and s.invite_expires_at < now(),
      'revoked', s.revoked_at is not null, 'revoked_at', s.revoked_at)
      order by s.revoked_at is not null, s.role = 'owner' desc, s.created_at), '[]'::jsonb)
  from public.pasr_business_staff s left join auth.users u on u.id = s.user_id
  where s.business_id = p_business;
$$;

create or replace function public.pasr_business_log_json(p_business uuid, p_limit int) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', e.event_id, 'kind', e.kind, 'amount', e.amount, 'at', e.at,
      'card_id', e.business_card_id, 'card_name', e.card_name, 'member_suffix', e.member_suffix,
      -- wie: bij join en claim de klant (nooit tonen wie dat is)
      'by_name', case when e.kind in ('join', 'claim') then null else coalesce(nullif(s.name, ''), u.email) end,
      'by_role', case when e.kind in ('join', 'claim') then 'customer' else coalesce(s.role, 'unknown') end,
      'device', e.device, 'stamps_before', e.stamps_before, 'stamps_after', e.stamps_after,
      'undone', e.undone_at is not null, 'undone_at', e.undone_at, 'undo_of', e.undo_of) order by e.at desc, e.id desc), '[]'::jsonb)
  from (select * from public.pasr_business_events where business_id = p_business
        order by at desc, id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) e
  left join lateral (select st.name, st.role from public.pasr_business_staff st
                     where st.business_id = p_business and st.user_id = e.by_user order by st.revoked_at is null desc limit 1) s on e.kind not in ('join', 'claim')
  left join auth.users u on u.id = e.by_user and e.kind not in ('join', 'claim');
$$;

create or replace function public.pasr_business_stats_json(p_business uuid, p_days int) returns jsonb
language sql stable security definer set search_path = public as $$
  with d as (select least(greatest(coalesce(p_days, 30), 1), 366) n),
  days as (select generate_series((now() at time zone 'Europe/Amsterdam')::date - (select n - 1 from d),
                                  (now() at time zone 'Europe/Amsterdam')::date, interval '1 day')::date as day),
  ev as (select (at at time zone 'Europe/Amsterdam')::date as day, kind, amount from public.pasr_business_events
         where business_id = p_business and undone_at is null and at > now() - make_interval(days => (select n from d) + 1)),
  per as (select x.day, coalesce(sum(ev.amount) filter (where ev.kind = 'stamp'), 0)::int stamps,
                 count(ev.kind) filter (where ev.kind = 'redeem')::int rewards, count(ev.kind) filter (where ev.kind = 'join')::int new_members
          from days x left join ev on ev.day = x.day group by x.day)
  select jsonb_build_object('days', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'stamps', stamps, 'rewards', rewards,
      'new_members', new_members) order by day) from per), '[]'::jsonb),
    'totals', jsonb_build_object('stamps', (select coalesce(sum(stamps), 0) from per), 'rewards', (select coalesce(sum(rewards), 0) from per),
      'new_members', (select coalesce(sum(new_members), 0) from per),
      'members', (select count(*) from public.pasr_business_members m join public.pasr_business_cards c on c.id = m.business_card_id
                  where c.business_id = p_business)));
$$;

-- ---- medewerkers (eigenaar) ----
create or replace function public.pasr_business_need_owner(p_business uuid) returns public.pasr_businesses
language plpgsql stable security definer set search_path = public as $$
declare b public.pasr_businesses;
begin
  if auth.uid() is null then raise exception 'Log eerst in.' using errcode = '28000', hint = 'not_signed_in'; end if;
  select * into b from public.pasr_businesses where id = p_business;
  if b.id is null or public.pasr_business_role(p_business) is distinct from 'owner' then
    raise exception 'Alleen de eigenaar van de zaak kan dit.' using errcode = '42501', hint = 'not_allowed';
  end if;
  return b;
end $$;

create or replace function public.pasr_business_staff_list(p_business uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.pasr_business_need_owner(p_business);
  return public.pasr_business_staff_json(p_business);
end $$;

create or replace function public.pasr_business_staff_invite(p_business uuid, p_name text, p_email text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare b public.pasr_businesses; alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; code text; bytes bytea; i int;
        nm text := left(regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g'), 60);
        mail text := nullif(lower(trim(coalesce(p_email, ''))), ''); s public.pasr_business_staff;
begin
  b := public.pasr_business_need_owner(p_business);
  if b.status = 'blocked' then raise exception 'Je zaak is geblokkeerd.' using errcode = '42501', hint = 'blocked'; end if;
  if char_length(nm) < 1 then raise exception 'Vul de naam van je medewerker in.' using errcode = '22023', hint = 'bad_name'; end if;
  if mail is not null and (char_length(mail) > 200 or mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'Dit e-mailadres klopt niet.' using errcode = '22023', hint = 'bad_email';
  end if;
  if (select count(*) from public.pasr_business_staff where business_id = b.id and revoked_at is null and role = 'staff'
        and (user_id is not null or invite_expires_at > now())) >= 25 then
    raise exception 'Je kunt hoogstens 25 medewerkers hebben.' using errcode = '22023', hint = 'staff_limit';
  end if;
  loop
    bytes := gen_random_bytes(20); code := '';
    for i in 0..19 loop code := code || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1); end loop;
    exit when not exists (select 1 from public.pasr_business_staff where invite_code = code);
  end loop;
  insert into public.pasr_business_staff (business_id, role, name, invited_email, invite_code, invite_expires_at)
  values (b.id, 'staff', nm, mail, code, now() + interval '14 days') returning * into s;
  return jsonb_build_object('id', s.id, 'invite_code', code, 'link', 'https://pasr.nl/zakelijk/uitnodiging/#' || code,
    'app_link', 'pasrzakelijk://uitnodiging#' || code, 'expires_at', s.invite_expires_at, 'business', b.name);
end $$;

-- Uitnodiging bekijken vóór het aannemen (pagina /zakelijk/uitnodiging/): alleen de naam van de zaak.
create or replace function public.pasr_business_staff_invite_info(p_code text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.pasr_business_staff; b public.pasr_businesses;
begin
  select * into s from public.pasr_business_staff where invite_code = upper(trim(coalesce(p_code, '')))
    and user_id is null and revoked_at is null and invite_expires_at > now();
  if s.id is null then return jsonb_build_object('status', 'invalid'); end if;
  select * into b from public.pasr_businesses where id = s.business_id;
  return jsonb_build_object('status', 'ok', 'business', b.name, 'city', b.city, 'name', s.name);
end $$;

create or replace function public.pasr_business_staff_accept(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s public.pasr_business_staff; b public.pasr_businesses; mail text;
begin
  if uid is null then raise exception 'Log eerst in.' using errcode = '28000', hint = 'not_signed_in'; end if;
  perform public.pasr_web_rate_hit('staff_accept', 30, 20000);
  select * into s from public.pasr_business_staff where invite_code = upper(trim(coalesce(p_code, ''))) for update;
  if s.id is null or s.revoked_at is not null or s.user_id is not null or s.invite_expires_at <= now() then
    raise exception 'Deze uitnodiging is verlopen of al gebruikt. Vraag de eigenaar om een nieuwe.' using errcode = 'P0002', hint = 'invite_invalid';
  end if;
  select * into b from public.pasr_businesses where id = s.business_id;
  if b.owner = uid then raise exception 'Dit is je eigen zaak.' using errcode = '22023', hint = 'invite_own'; end if;
  select email into mail from auth.users where id = uid;
  if exists (select 1 from public.pasr_business_staff where business_id = b.id and user_id = uid and revoked_at is null) then
    -- al medewerker: uitnodiging opruimen, gewoon de zaak teruggeven
    update public.pasr_business_staff set revoked_at = now(), invite_code = null where id = s.id;
  else
    update public.pasr_business_staff set user_id = uid, accepted_at = now(), invite_code = null,
      invited_email = coalesce(invited_email, mail) where id = s.id;
  end if;
  return jsonb_build_object('business', public.pasr_business_json(b) || jsonb_build_object('role', 'staff'));
end $$;

create or replace function public.pasr_business_staff_revoke(p_staff uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.pasr_business_staff;
begin
  select * into s from public.pasr_business_staff where id = p_staff;
  if s.id is null then raise exception 'Medewerker niet gevonden.' using errcode = 'P0002', hint = 'not_found'; end if;
  perform public.pasr_business_need_owner(s.business_id);
  if s.role = 'owner' then raise exception 'De eigenaar kun je niet intrekken.' using errcode = '42501', hint = 'not_allowed'; end if;
  update public.pasr_business_staff set revoked_at = coalesce(revoked_at, now()), invite_code = null where id = s.id;
  return jsonb_build_object('ok', true);
end $$;

-- ---- instellingen (eigenaar) ----
create or replace function public.pasr_business_settings_apply(p_business uuid, p_settings jsonb) returns public.pasr_businesses
language plpgsql security definer set search_path = public as $$
declare b public.pasr_businesses; cd int; mx int; li boolean; ad text; la double precision; lo double precision;
begin
  if jsonb_typeof(coalesce(p_settings, '{}'::jsonb)) <> 'object' then
    raise exception 'Ongeldige instellingen.' using errcode = '22023', hint = 'bad_settings';
  end if;
  select * into b from public.pasr_businesses where id = p_business for update;
  begin
    cd := coalesce((p_settings->>'cooldown_minutes')::int, b.cooldown_minutes);
    mx := coalesce((p_settings->>'max_per_scan')::int, b.max_per_scan);
    li := coalesce((p_settings->>'listed')::boolean, b.listed);
    -- adres: weglaten = laten staan, leeg of null = wissen (dan ook de locatie)
    ad := case when p_settings ? 'address' then nullif(left(regexp_replace(trim(coalesce(p_settings->>'address', '')), '\s+', ' ', 'g'), 200), '')
               else b.address end;
    la := case when p_settings ? 'lat' then (p_settings->>'lat')::double precision else b.lat end;
    lo := case when p_settings ? 'lng' then (p_settings->>'lng')::double precision else b.lng end;
    if p_settings ? 'address' and ad is null and not (p_settings ? 'lat') then la := null; lo := null; end if;
  exception when others then
    raise exception 'Ongeldige instellingen.' using errcode = '22023', hint = 'bad_settings';
  end;
  if cd not between 0 and 1440 then raise exception 'Afkoeltijd moet tussen 0 en 1440 minuten liggen.' using errcode = '22023', hint = 'bad_settings'; end if;
  if mx not between 1 and 30 then raise exception 'Max per scan moet tussen 1 en 30 liggen.' using errcode = '22023', hint = 'bad_settings'; end if;
  if (la is null) <> (lo is null) or (la is not null and (la not between -90 and 90 or lo not between -180 and 180)) then
    raise exception 'Deze locatie klopt niet.' using errcode = '22023', hint = 'bad_settings';
  end if;
  update public.pasr_businesses set cooldown_minutes = cd, max_per_scan = mx, listed = li, address = ad, lat = la, lng = lo,
    updated_at = now() where id = b.id returning * into b;
  return b;
end $$;

create or replace function public.pasr_business_settings_save(p_business uuid, p_settings jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.pasr_businesses;
begin
  perform public.pasr_business_need_owner(p_business);
  b := public.pasr_business_settings_apply(p_business, p_settings);
  return public.pasr_business_json(b) || jsonb_build_object('role', 'owner');
end $$;

-- ---- log en stats ----
create or replace function public.pasr_business_log(p_business uuid, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.pasr_business_need_owner(p_business);
  return jsonb_build_object('events', public.pasr_business_log_json(p_business, p_limit));
end $$;

create or replace function public.pasr_business_stats(p_business uuid, p_days int default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.pasr_business_role(p_business) is null then
    raise exception 'Je hoort niet bij deze zaak.' using errcode = '42501', hint = 'not_allowed';
  end if;
  return public.pasr_business_stats_json(p_business, p_days);
end $$;

-- Leden van een kaart (eigenaar; alleen de laatste 4 tekens van de code) en stempels per dag (30 dagen).
create or replace function public.pasr_business_members_list(p_card uuid, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.pasr_business_cards;
begin
  select * into c from public.pasr_business_cards where id = p_card;
  if c.id is null or public.pasr_business_role(c.business_id) is distinct from 'owner' then
    raise exception 'not_found' using errcode = 'P0002', hint = 'not_found';
  end if;
  return jsonb_build_object(
    'total', (select count(*) from public.pasr_business_members where business_card_id = c.id),
    'members', coalesce((select jsonb_agg(jsonb_build_object('code', '…' || right(m.member_code, 4), 'stamps_count', m.stamps_count,
        'rewards_redeemed', m.rewards_redeemed, 'created_at', m.created_at, 'last_stamp_at', m.last_stamp_at, 'app', m.user_id is not null)
        order by coalesce(m.last_stamp_at, m.created_at) desc)
      from (select * from public.pasr_business_members where business_card_id = c.id
            order by coalesce(last_stamp_at, created_at) desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) m), '[]'::jsonb),
    'days', coalesce((select jsonb_agg(jsonb_build_object('day', d, 'stamps', s, 'rewards', r, 'joins', j) order by d)
      from (select (at at time zone 'Europe/Amsterdam')::date d,
                   coalesce(sum(amount) filter (where kind = 'stamp'), 0) s, count(*) filter (where kind = 'redeem') r,
                   count(*) filter (where kind = 'join') j
            from public.pasr_business_events where business_card_id = c.id and undone_at is null
              and at > now() - interval '30 days' group by 1) q), '[]'::jsonb));
end $$;

-- ---- scanner: eigenaar of medewerker van een goedgekeurde zaak, alleen voor de kaarten van die zaak ----
drop function if exists public.pasr_business_stamp(text, int);
drop function if exists public.pasr_business_redeem(text);

create or replace function public.pasr_business_scan_member(p_code text, out m public.pasr_business_members,
                                                            out c public.pasr_business_cards, out b public.pasr_businesses)
language plpgsql security definer set search_path = public as $$
declare code text := upper(regexp_replace(coalesce(p_code, ''), '^.*#', ''));
begin
  if auth.uid() is null then raise exception 'Log eerst in.' using errcode = '28000', hint = 'not_signed_in'; end if;
  -- alleen wie bij een goedgekeurde zaak hoort mag codes opzoeken (klanten nooit)
  if not exists (select 1 from public.pasr_businesses x where x.status = 'approved' and (x.owner = auth.uid() or exists (
      select 1 from public.pasr_business_staff s where s.business_id = x.id and s.user_id = auth.uid() and s.revoked_at is null))) then
    if exists (select 1 from public.pasr_businesses x where x.owner = auth.uid() or exists (
        select 1 from public.pasr_business_staff s where s.business_id = x.id and s.user_id = auth.uid() and s.revoked_at is null)) then
      raise exception 'Je zaak is nog niet goedgekeurd. Je krijgt bericht zodra dat zo is.' using errcode = '42501', hint = 'not_approved';
    end if;
    raise exception 'Alleen de ondernemer en zijn medewerkers kunnen stempels zetten.' using errcode = '42501', hint = 'not_allowed';
  end if;
  select * into m from public.pasr_business_members where member_code = trim(code) for update;
  if m.id is null then raise exception 'Deze klantcode kennen we niet. Controleer de code.' using errcode = 'P0002', hint = 'not_found'; end if;
  select * into c from public.pasr_business_cards where id = m.business_card_id;
  select * into b from public.pasr_businesses where id = c.business_id;
  if public.pasr_business_role(b.id) is null then
    raise exception 'Deze kaart hoort bij een andere zaak.' using errcode = '42501', hint = 'other_business';
  end if;
  if b.status <> 'approved' then
    raise exception 'Je zaak is nog niet goedgekeurd. Je krijgt bericht zodra dat zo is.' using errcode = '42501', hint = 'not_approved';
  end if;
end $$;

-- Het laatste stempel/inwisseling van dit lid dat je nog mag terugdraaien (2 minuten; eigen event, of alles als eigenaar).
create or replace function public.pasr_business_undo_candidate(p_member uuid, p_business uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select e.event_id from (select * from public.pasr_business_events where member_id = p_member and kind in ('stamp', 'redeem')
                          and undone_at is null order by at desc, id desc limit 1) e
  where e.at > now() - interval '2 minutes'
    and (e.by_user = auth.uid() or public.pasr_business_role(p_business) = 'owner');
$$;

create or replace function public.pasr_business_scan_json(m public.pasr_business_members, c public.pasr_business_cards,
                                                          b public.pasr_businesses, p_event uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select public.pasr_business_member_json(m, c, b) || jsonb_build_object(
    'member_code_suffix', right(m.member_code, 4),
    'stamps', m.stamps_count,
    'card_id', c.id, 'business_id', b.id,
    'last_stamp_at', m.last_stamp_at,
    'cooldown_minutes', b.cooldown_minutes, 'max_per_scan', b.max_per_scan,
    'cooldown_until', case when m.last_stamp_at is not null and b.cooldown_minutes > 0
                            and m.last_stamp_at + make_interval(mins => b.cooldown_minutes) > now()
                           then m.last_stamp_at + make_interval(mins => b.cooldown_minutes) end,
    'can_redeem', m.stamps_count >= c.stamps_total,
    'can_undo_event_id', public.pasr_business_undo_candidate(m.id, b.id),
    'event_id', p_event,
    'role', public.pasr_business_role(b.id));
$$;

create or replace function public.pasr_business_scan(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  select * into r from public.pasr_business_scan_member(p_code);
  return public.pasr_business_scan_json(r.m, r.c, r.b);
end $$;

create or replace function public.pasr_business_stamp(p_code text, p_amount int default 1, p_device text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; m public.pasr_business_members; amt int := coalesce(p_amount, 1); left_s int; ev uuid;
  cfg jsonb; mult int := 1; actual int; today int;
begin
  select * into r from public.pasr_business_scan_member(p_code);
  if amt < 1 then raise exception 'Kies minstens 1 stempel.' using errcode = '22023', hint = 'bad_amount'; end if;
  if amt > (r.b).max_per_scan then
    raise exception 'Je kunt hoogstens % % per keer geven.', (r.b).max_per_scan,
      case when (r.b).max_per_scan = 1 then 'stempel' else 'stempels' end using errcode = '22023', hint = 'too_many';
  end if;
  -- dubbel scannen: binnen 5 seconden nooit nog een keer
  if (r.m).last_stamp_at > now() - interval '5 seconds' then
    raise exception 'Net al een stempel gezet. Wacht een paar seconden.' using errcode = '22023', hint = 'too_soon';
  end if;
  if (r.b).cooldown_minutes > 0 and (r.m).last_stamp_at > now() - make_interval(mins => (r.b).cooldown_minutes) then
    left_s := ceil(extract(epoch from ((r.m).last_stamp_at + make_interval(mins => (r.b).cooldown_minutes) - now())))::int;
    raise exception 'Deze klant kreeg net al een stempel, probeer het over % min opnieuw.', greatest(1, ceil(left_s / 60.0)::int)
      using errcode = '22023', hint = 'cooldown', detail = left_s::text;
  end if;
  -- Tijdelijke stempelactie alleen als de eigenaar hem op deze kaart aanzet.
  select settings->'campaign' into cfg from public.pasr_business_programs where card_id=(r.c).id;
  today := extract(dow from now() at time zone 'Europe/Amsterdam')::int;
  if coalesce((cfg->>'enabled')::boolean,false)
     and coalesce((cfg->>'weekday')::int,-1)=today then
    mult := greatest(1, least(3,coalesce((cfg->>'multiplier')::int,1)));
  end if;
  actual := least(amt * mult,(r.b).max_per_scan);
  update public.pasr_business_members set stamps_count = least(stamps_count + actual, 1000), last_stamp_at = now(), updated_at = now()
  where id = (r.m).id returning * into m;
  insert into public.pasr_business_events (business_card_id, business_id, member_id, kind, amount, by_user, device, stamps_before, stamps_after)
  values ((r.c).id, (r.b).id, m.id, 'stamp', actual, auth.uid(), nullif(left(trim(coalesce(p_device, '')), 80), ''), (r.m).stamps_count, m.stamps_count)
  returning event_id into ev;
  -- Een uitgenodigde klant krijgt pas bij de eerste echte, door de zaak gescande aankoop een bonus.
  if (r.m).last_stamp_at is null then
    perform public.pasr_business_referral_award_internal(m.id,(r.b).id,(r.c).id);
    select * into m from public.pasr_business_members where id=(r.m).id;
  end if;
  return public.pasr_business_scan_json(m, r.c, r.b, ev) || jsonb_build_object('stamps_added',actual,'campaign_multiplier',mult);
end $$;

create or replace function public.pasr_business_redeem(p_code text, p_device text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; m public.pasr_business_members; ev uuid;
begin
  select * into r from public.pasr_business_scan_member(p_code);
  if (r.m).stamps_count < (r.c).stamps_total then
    raise exception 'Nog niet genoeg stempels voor de beloning (% van %).', (r.m).stamps_count, (r.c).stamps_total
      using errcode = '22023', hint = 'not_enough';
  end if;
  -- de volle kaart gaat eraf; stempels boven het maximum vervallen niet maar blijven staan voor de volgende ronde
  update public.pasr_business_members set stamps_count = stamps_count - (r.c).stamps_total, rewards_redeemed = rewards_redeemed + 1,
    updated_at = now()
  where id = (r.m).id returning * into m;
  insert into public.pasr_business_events (business_card_id, business_id, member_id, kind, amount, by_user, device, stamps_before, stamps_after)
  values ((r.c).id, (r.b).id, m.id, 'redeem', 1, auth.uid(), nullif(left(trim(coalesce(p_device, '')), 80), ''), (r.m).stamps_count, m.stamps_count)
  returning event_id into ev;
  return public.pasr_business_scan_json(m, r.c, r.b, ev);
end $$;

-- Ongedaan maken: alleen het laatste stempel/inwisseling van dat lid, binnen 2 minuten, eigen event (eigenaar: elk).
create or replace function public.pasr_business_undo(p_event uuid, p_device text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.pasr_business_events; m public.pasr_business_members; c public.pasr_business_cards; b public.pasr_businesses;
        role text; prev timestamptz; ev uuid;
begin
  if auth.uid() is null then raise exception 'Log eerst in.' using errcode = '28000', hint = 'not_signed_in'; end if;
  select * into e from public.pasr_business_events where event_id = p_event for update;
  if e.id is null or e.kind not in ('stamp', 'redeem') or e.member_id is null then
    raise exception 'Niet gevonden.' using errcode = 'P0002', hint = 'not_found';
  end if;
  role := public.pasr_business_role(e.business_id);
  if role is null then raise exception 'Je hoort niet bij deze zaak.' using errcode = '42501', hint = 'not_allowed'; end if;
  if role <> 'owner' and e.by_user is distinct from auth.uid() then
    raise exception 'Je kunt alleen je eigen stempels ongedaan maken.' using errcode = '42501', hint = 'not_allowed';
  end if;
  if e.undone_at is not null then raise exception 'Dit is al ongedaan gemaakt.' using errcode = '22023', hint = 'undo_expired'; end if;
  if e.at <= now() - interval '2 minutes' then
    raise exception 'Ongedaan maken kan tot 2 minuten na het stempelen.' using errcode = '22023', hint = 'undo_expired';
  end if;
  select * into m from public.pasr_business_members where id = e.member_id for update;
  if exists (select 1 from public.pasr_business_events where member_id = e.member_id and kind in ('stamp', 'redeem')
             and undone_at is null and (at, id) > (e.at, e.id)) then
    raise exception 'Er is daarna al iets anders gebeurd met deze kaart; dit kan niet meer ongedaan.' using errcode = '22023', hint = 'undo_not_latest';
  end if;
  select * into c from public.pasr_business_cards where id = m.business_card_id;
  select * into b from public.pasr_businesses where id = c.business_id;
  if b.status <> 'approved' then
    raise exception 'Je zaak is nog niet goedgekeurd. Je krijgt bericht zodra dat zo is.' using errcode = '42501', hint = 'not_approved';
  end if;
  update public.pasr_business_events set undone_at = now() where id = e.id;
  if e.kind = 'stamp' then
    select max(at) into prev from public.pasr_business_events where member_id = m.id and kind = 'stamp' and undone_at is null;
    update public.pasr_business_members set stamps_count = greatest(0, coalesce(e.stamps_before, stamps_count - e.amount)),
      last_stamp_at = prev, updated_at = now() where id = m.id returning * into m;
  else
    update public.pasr_business_members set stamps_count = coalesce(e.stamps_before, stamps_count + c.stamps_total),
      rewards_redeemed = greatest(0, rewards_redeemed - 1), updated_at = now() where id = m.id returning * into m;
  end if;
  insert into public.pasr_business_events (business_card_id, business_id, member_id, kind, amount, by_user, device, stamps_before, stamps_after, undo_of)
  values (c.id, b.id, m.id, 'undo', e.amount, auth.uid(), nullif(left(trim(coalesce(p_device, '')), 80), ''),
          e.stamps_after, m.stamps_count, e.event_id)
  returning event_id into ev;
  return public.pasr_business_scan_json(m, c, b, ev) || jsonb_build_object('undone', e.kind);
end $$;

-- ---- klant: een bestaande (browser-)lidcode in de app overnemen, de stempels gaan mee ----
create or replace function public.pasr_business_claim(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.pasr_business_members; c public.pasr_business_cards; b public.pasr_businesses;
        code text := upper(trim(regexp_replace(coalesce(p_code, ''), '^.*#', '')));
begin
  perform public.pasr_web_rate_hit('claim', 120, 200000);
  if code !~ '^PZ([A-HJ-NP-Z2-9]{10}|[A-HJ-NP-Z2-9]{14})$' then return jsonb_build_object('status', 'not_found'); end if;
  select * into m from public.pasr_business_members where member_code = code for update;
  if m.id is null then return jsonb_build_object('status', 'not_found'); end if;
  select * into c from public.pasr_business_cards where id = m.business_card_id;
  select * into b from public.pasr_businesses where id = c.business_id;
  if not c.published or b.status <> 'approved' then return jsonb_build_object('status', 'blocked'); end if;
  if auth.uid() is not null and m.user_id is null then
    update public.pasr_business_members set user_id = auth.uid() where id = m.id returning * into m;
    insert into public.pasr_business_events (business_card_id, business_id, member_id, kind, amount, by_user)
    values (c.id, b.id, m.id, 'claim', 0, auth.uid());
  end if;
  return public.pasr_business_member_json(m, c, b) || jsonb_build_object('business_card_id', c.id, 'claimed', true);
end $$;

-- ---- vindbaar in Pasr: Kaart toevoegen › Stempelkaart (anon) ----
-- Alleen gepubliceerde kaarten van goedgekeurde zaken met listed = true. Zoeken op zaak, kaart en plaats; met een
-- locatie eerst wat dichtbij is (distance_km, alleen als de zaak een locatie heeft). Geen e-mail, geen eigenaar.
create or replace function public.pasr_business_directory(p_query text default null, p_lat double precision default null,
                                                          p_lng double precision default null, p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare q text := nullif(lower(left(regexp_replace(trim(coalesce(p_query, '')), '\s+', ' ', 'g'), 60)), '');
        here boolean := p_lat between -90 and 90 and p_lng between -180 and 180;
begin
  return coalesce((select jsonb_agg(x.j order by x.dist nulls last, x.bname, x.cname) from (
    select jsonb_build_object('card_id', c.id, 'card_name', c.name, 'business_name', b.name, 'city', b.city, 'logo', c.logo,
             'color', c.color, 'text_color', c.text_color, 'stamps_total', c.stamps_total, 'reward', c.reward,
             'distance_km', case when d.km is not null then round(d.km::numeric, 1) end) j,
           d.km dist, lower(b.name) bname, lower(c.name) cname
    from public.pasr_business_cards c join public.pasr_businesses b on b.id = c.business_id
    cross join lateral (select case when here and b.lat is not null then
        6371 * 2 * asin(sqrt(power(sin(radians(b.lat - p_lat) / 2), 2)
          + cos(radians(p_lat)) * cos(radians(b.lat)) * power(sin(radians(b.lng - p_lng) / 2), 2))) end km) d
    where c.published and b.status = 'approved' and b.listed
      and (q is null or strpos(lower(b.name || ' ' || c.name || ' ' || b.city || ' ' || coalesce(b.address, '')), q) > 0)
    order by d.km nulls last, lower(b.name), lower(c.name)
    limit least(greatest(coalesce(p_limit, 50), 1), 200)) x), '[]'::jsonb);
end $$;

-- ---- huisstijl van de website (functie business-brand): rem per zaak ----
create table if not exists public.pasr_business_brand_hits (
  business_id uuid not null references public.pasr_businesses (id) on delete cascade,
  at timestamptz not null default now()
);
create index if not exists pasr_business_brand_hits_biz on public.pasr_business_brand_hits (business_id, at);
alter table public.pasr_business_brand_hits enable row level security;
revoke all on public.pasr_business_brand_hits from anon, authenticated;

-- Telt een keer ophalen; geeft 0 (mag) of het aantal seconden tot het weer mag. Ruimt oude tellingen van de zaak op.
create or replace function public.pasr_business_brand_hit(p_business uuid, p_per_hour int default 20) returns int
language plpgsql security definer set search_path = public as $$
declare n int; oldest timestamptz;
begin
  delete from public.pasr_business_brand_hits where business_id = p_business and at < now() - interval '1 hour';
  select count(*), min(at) into n, oldest from public.pasr_business_brand_hits where business_id = p_business;
  if n >= greatest(coalesce(p_per_hour, 20), 1) then
    return greatest(1, ceil(extract(epoch from (oldest + interval '1 hour' - now())))::int);
  end if;
  insert into public.pasr_business_brand_hits (business_id) values (p_business);
  return 0;
end $$;
revoke all on function public.pasr_business_brand_hit(uuid, int) from public, anon, authenticated;
grant execute on function public.pasr_business_brand_hit(uuid, int) to service_role;

-- ---- beheer (functie admin, service role) ----
create or replace function public.pasr_admin_businesses() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.pasr_business_json(b) || jsonb_build_object(
      'cards', public.pasr_business_cards_json(b, true),
      'staff_count', (select count(*) from public.pasr_business_staff s where s.business_id = b.id and s.role = 'staff'
                      and s.revoked_at is null and s.user_id is not null),
      'last_event_at', (select max(at) from public.pasr_business_events e where e.business_id = b.id))
    order by case b.status when 'pending' then 0 when 'approved' then 1 else 2 end, b.created_at desc), '[]'::jsonb)
  from public.pasr_businesses b;
$$;

create or replace function public.pasr_admin_business_detail(p_business uuid, p_limit int default 200, p_days int default 30) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when b.id is null then null else jsonb_build_object(
    'business', public.pasr_business_json(b),
    'staff', public.pasr_business_staff_json(b.id),
    'log', public.pasr_business_log_json(b.id, p_limit),
    'stats', public.pasr_business_stats_json(b.id, p_days)) end
  from (select 1) one left join public.pasr_businesses b on b.id = p_business;
$$;

create or replace function public.pasr_admin_business_status(p_business uuid, p_status text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.pasr_businesses;
begin
  if p_status not in ('pending', 'approved', 'blocked') then raise exception 'bad_status' using errcode = '22023'; end if;
  update public.pasr_businesses set status = p_status, reviewed_at = now(), updated_at = now() where id = p_business returning * into b;
  if b.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  -- geblokkeerd: kaarten offline
  if p_status = 'blocked' then update public.pasr_business_cards set published = false, updated_at = now() where business_id = b.id and published; end if;
  return public.pasr_business_json(b);
end $$;

create or replace function public.pasr_admin_business_settings(p_business uuid, p_settings jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.pasr_businesses;
begin
  if not exists (select 1 from public.pasr_businesses where id = p_business) then raise exception 'not_found' using errcode = 'P0002'; end if;
  b := public.pasr_business_settings_apply(p_business, p_settings);
  return public.pasr_business_json(b);
end $$;

create or replace function public.pasr_admin_business_staff_revoke(p_staff uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  update public.pasr_business_staff set revoked_at = coalesce(revoked_at, now()), invite_code = null where id = p_staff and role = 'staff';
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---- rechten ----
revoke all on function public.pasr_business_new_code(), public.pasr_business_json(public.pasr_businesses),
  public.pasr_business_cards_json(public.pasr_businesses, boolean), public.pasr_business_me(), public.pasr_business_role(uuid),
  public.pasr_business_staff_json(uuid), public.pasr_business_log_json(uuid, int), public.pasr_business_stats_json(uuid, int),
  public.pasr_business_need_owner(uuid), public.pasr_business_staff_list(uuid), public.pasr_business_staff_invite(uuid, text, text),
  public.pasr_business_staff_invite_info(text), public.pasr_business_staff_accept(text), public.pasr_business_staff_revoke(uuid),
  public.pasr_business_settings_apply(uuid, jsonb), public.pasr_business_settings_save(uuid, jsonb),
  public.pasr_business_log(uuid, int), public.pasr_business_stats(uuid, int), public.pasr_business_members_list(uuid, int),
  public.pasr_business_scan_member(text), public.pasr_business_undo_candidate(uuid, uuid),
  public.pasr_business_scan_json(public.pasr_business_members, public.pasr_business_cards, public.pasr_businesses, uuid),
  public.pasr_business_scan(text), public.pasr_business_stamp(text, int, text), public.pasr_business_redeem(text, text),
  public.pasr_business_undo(uuid, text), public.pasr_business_claim(text),
  public.pasr_admin_businesses(), public.pasr_admin_business_detail(uuid, int, int), public.pasr_admin_business_status(uuid, text),
  public.pasr_admin_business_settings(uuid, jsonb), public.pasr_admin_business_staff_revoke(uuid)
  from public, anon, authenticated;
revoke all on function public.pasr_business_directory(text, double precision, double precision, int) from public;
grant execute on function public.pasr_business_claim(text), public.pasr_business_staff_invite_info(text),
  public.pasr_business_directory(text, double precision, double precision, int) to anon, authenticated;
grant execute on function public.pasr_business_me(), public.pasr_business_role(uuid), public.pasr_business_staff_list(uuid),
  public.pasr_business_staff_invite(uuid, text, text), public.pasr_business_staff_accept(text), public.pasr_business_staff_revoke(uuid),
  public.pasr_business_settings_save(uuid, jsonb), public.pasr_business_log(uuid, int), public.pasr_business_stats(uuid, int),
  public.pasr_business_members_list(uuid, int), public.pasr_business_scan(text), public.pasr_business_stamp(text, int, text),
  public.pasr_business_redeem(text, text), public.pasr_business_undo(uuid, text) to authenticated;
grant execute on function public.pasr_admin_businesses(), public.pasr_admin_business_detail(uuid, int, int),
  public.pasr_admin_business_status(uuid, text), public.pasr_admin_business_settings(uuid, jsonb),
  public.pasr_admin_business_staff_revoke(uuid) to service_role;

-- ============================================================================================================
-- zakelijk 1.1: het beheer maakt zelf zaken en stempelkaarten (functie admin, service role).
-- Een zaak van het beheer is meteen goedgekeurd. Eigenaar: heeft het e-mailadres al een (bevestigd) Pasr-account, dan
-- wordt dat account eigenaar; anders een eigenaarsuitnodiging met code (pasr.nl/zakelijk/uitnodiging/#<code>, zelfde
-- flow als medewerkers, rol 'owner'). Een zaak zonder eigenaar mag; dan beheert het beheer hem. Een account is van
-- hoogstens één zaak eigenaar (zoals bij aanmelden). Alles van het beheer komt in de log als kind 'admin' met actor
-- 'beheer' en een korte omschrijving (note); die regels ziet alleen het beheer, niet de ondernemer.
-- ============================================================================================================

-- ---- zaak zonder eigenaar, en wie hem maakte ----
alter table public.pasr_businesses alter column owner drop not null;
alter table public.pasr_businesses add column if not exists created_by text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'pasr_businesses_created_by_check') then
    alter table public.pasr_businesses add constraint pasr_businesses_created_by_check check (created_by is null or created_by = 'beheer');
  end if;
end $$;

-- eigenaarsrij alleen als er een eigenaar is (een zaak van het beheer kan zonder beginnen)
create or replace function public.pasr_business_owner_row() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.owner is not null and not exists (select 1 from public.pasr_business_staff where business_id = new.id and role = 'owner'
                                           and revoked_at is null and user_id is not null) then
    insert into public.pasr_business_staff (business_id, user_id, role, invited_email, accepted_at)
    values (new.id, new.owner, 'owner', new.email, now());
  end if;
  return new;
end $$;
revoke all on function public.pasr_business_owner_row() from public, anon, authenticated;

-- ---- log: regels van het beheer ----
alter table public.pasr_business_events add column if not exists actor text;
alter table public.pasr_business_events add column if not exists note text;
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'pasr_business_events_kind_v2') then
    alter table public.pasr_business_events drop constraint pasr_business_events_kind_v2;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pasr_business_events_kind_v3') then
    alter table public.pasr_business_events add constraint pasr_business_events_kind_v3
      check (kind in ('join', 'stamp', 'redeem', 'undo', 'claim', 'admin'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pasr_business_events_actor_check') then
    alter table public.pasr_business_events add constraint pasr_business_events_actor_check
      check ((actor is null or actor = 'beheer') and (note is null or char_length(note) <= 200));
  end if;
end $$;

create or replace function public.pasr_admin_event(p_business uuid, p_card uuid, p_note text) returns void
language sql security definer set search_path = public as $$
  insert into public.pasr_business_events (business_id, business_card_id, kind, amount, actor, note)
  values (p_business, p_card, 'admin', 0, 'beheer', left(p_note, 200));
$$;

-- Log met of zonder de regels van het beheer (p_admin). De ondernemer krijgt ze niet (zijn apps kennen 'admin' niet).
create or replace function public.pasr_business_log_json_all(p_business uuid, p_limit int, p_admin boolean) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', e.event_id, 'kind', e.kind, 'amount', e.amount, 'at', e.at,
      'card_id', e.business_card_id, 'card_name', e.card_name, 'member_suffix', e.member_suffix,
      -- wie: bij join en claim de klant (nooit tonen wie dat is), bij het beheer "Beheer"
      'by_name', case when e.actor = 'beheer' then 'Beheer' when e.kind in ('join', 'claim') then null
                      else coalesce(nullif(s.name, ''), u.email) end,
      'by_role', case when e.actor = 'beheer' then 'beheer' when e.kind in ('join', 'claim') then 'customer'
                      else coalesce(s.role, 'unknown') end,
      'actor', e.actor, 'note', e.note,
      'device', e.device, 'stamps_before', e.stamps_before, 'stamps_after', e.stamps_after,
      'undone', e.undone_at is not null, 'undone_at', e.undone_at, 'undo_of', e.undo_of) order by e.at desc, e.id desc), '[]'::jsonb)
  from (select * from public.pasr_business_events where business_id = p_business and (p_admin or kind <> 'admin')
        order by at desc, id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) e
  left join lateral (select st.name, st.role from public.pasr_business_staff st
                     where st.business_id = p_business and st.user_id = e.by_user order by st.revoked_at is null desc limit 1) s
    on e.kind not in ('join', 'claim') and e.actor is null
  left join auth.users u on u.id = e.by_user and e.kind not in ('join', 'claim') and e.actor is null;
$$;
create or replace function public.pasr_business_log_json(p_business uuid, p_limit int) returns jsonb
language sql stable security definer set search_path = public as $$
  select public.pasr_business_log_json_all(p_business, p_limit, false);
$$;

-- ---- uitnodigingscode (20 tekens, zonder 0/O/1/I) ----
create or replace function public.pasr_business_invite_code() returns text
language plpgsql volatile security definer set search_path = public, extensions as $$
declare alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; code text; bytes bytea; i int;
begin
  loop
    bytes := gen_random_bytes(20); code := '';
    for i in 0..19 loop code := code || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1); end loop;
    exit when not exists (select 1 from public.pasr_business_staff where invite_code = code);
  end loop;
  return code;
end $$;

-- ---- kaart opslaan: gedeelde controle voor de ondernemer (pasr_business_card_save) en het beheer ----
create or replace function public.pasr_business_card_apply(b public.pasr_businesses, p_card jsonb) returns public.pasr_business_cards
language plpgsql security definer set search_path = public as $$
declare c public.pasr_business_cards; cid uuid; lg text; nm text; rw text; col text; tot int; pub boolean; tc text;
begin
  if jsonb_typeof(p_card) is distinct from 'object' or octet_length(p_card::text) > 230000 then raise exception 'bad_card' using errcode = '22023'; end if;
  nm := left(regexp_replace(trim(coalesce(p_card->>'name', '')), '\s+', ' ', 'g'), 40);
  rw := left(regexp_replace(trim(coalesce(p_card->>'reward', '')), '\s+', ' ', 'g'), 80);
  col := upper(coalesce(p_card->>'color', '#6A5CFF'));
  begin
    tot := coalesce((p_card->>'stamps_total')::int, 10);
  exception when others then raise exception 'bad_total' using errcode = '22023';
  end;
  if nm = '' then raise exception 'bad_name' using errcode = '22023'; end if;
  if rw = '' then raise exception 'bad_reward' using errcode = '22023'; end if;
  if col !~ '^#[0-9A-F]{6}$' then raise exception 'bad_color' using errcode = '22023'; end if;
  if tot not between 2 and 30 then raise exception 'bad_total' using errcode = '22023'; end if;
  tc := nullif(upper(coalesce(p_card->>'text_color', '')), '');
  if tc is not null and tc !~ '^#[0-9A-F]{6}$' then raise exception 'bad_color' using errcode = '22023'; end if;
  lg := nullif(regexp_replace(coalesce(p_card->>'logo', ''), '^data:image/[a-z]+;base64,', ''), '');
  if lg is not null and (octet_length(lg) > 210000 or lg !~ '^(/9j/|iVBORw0KGgo)[A-Za-z0-9+/]+=*$') then
    raise exception 'bad_logo' using errcode = '22023';
  end if;
  pub := coalesce((p_card->>'published')::boolean, false) and b.status = 'approved';
  begin
    cid := nullif(p_card->>'id', '')::uuid;
  exception when others then raise exception 'not_found' using errcode = 'P0002';
  end;
  if cid is null then
    if (select count(*) from public.pasr_business_cards where business_id = b.id) >= 5 then
      raise exception 'card_limit' using errcode = '22023';
    end if;
    insert into public.pasr_business_cards (business_id, name, logo, color, stamps_total, reward, published, text_color)
    values (b.id, nm, lg, col, tot, rw, pub, tc) returning * into c;
  else
    update public.pasr_business_cards set name = nm, logo = case when p_card ? 'logo' then lg else logo end, color = col,
      stamps_total = tot, reward = rw, published = case when p_card ? 'published' then pub else published and b.status = 'approved' end,
      updated_at = now(), text_color = case when p_card ? 'text_color' then tc else text_color end
    where id = cid and business_id = b.id returning * into c;
    if c.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  end if;
  return c;
end $$;

-- Kaart opslaan door de ondernemer (zelfde gedrag als blok "zakelijk 1.0", nu via pasr_business_card_apply).
create or replace function public.pasr_business_card_save(p_card jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); b public.pasr_businesses; c public.pasr_business_cards;
begin
  if uid is null then raise exception 'not signed in' using errcode = '28000'; end if;
  select * into b from public.pasr_businesses where owner = uid;
  if b.id is null then raise exception 'no_business' using errcode = '42501'; end if;
  if b.status = 'blocked' then raise exception 'blocked' using errcode = '42501'; end if;
  -- zoals voorheen: weglaten van published = concept
  c := public.pasr_business_card_apply(b, p_card || jsonb_build_object('published', coalesce((p_card->>'published')::boolean, false)));
  return public.pasr_business_card_json(c, b) || jsonb_build_object('published', c.published);
end $$;

-- ---- uitnodiging: ook voor de rol eigenaar ----
create or replace function public.pasr_business_staff_invite_info(p_code text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.pasr_business_staff; b public.pasr_businesses;
begin
  select * into s from public.pasr_business_staff where invite_code = upper(trim(coalesce(p_code, '')))
    and user_id is null and revoked_at is null and invite_expires_at > now();
  if s.id is null then return jsonb_build_object('status', 'invalid'); end if;
  select * into b from public.pasr_businesses where id = s.business_id;
  if s.role = 'owner' and b.owner is not null then return jsonb_build_object('status', 'invalid'); end if;
  return jsonb_build_object('status', 'ok', 'business', b.name, 'city', b.city, 'name', s.name, 'role', s.role);
end $$;

create or replace function public.pasr_business_staff_accept(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s public.pasr_business_staff; b public.pasr_businesses; mail text; confirmed timestamptz;
begin
  if uid is null then raise exception 'Log eerst in.' using errcode = '28000', hint = 'not_signed_in'; end if;
  perform public.pasr_web_rate_hit('staff_accept', 30, 20000);
  select * into s from public.pasr_business_staff where invite_code = upper(trim(coalesce(p_code, ''))) for update;
  if s.id is null or s.revoked_at is not null or s.user_id is not null or s.invite_expires_at <= now() then
    raise exception 'Deze uitnodiging is verlopen of al gebruikt. Vraag de eigenaar om een nieuwe.' using errcode = 'P0002', hint = 'invite_invalid';
  end if;
  select * into b from public.pasr_businesses where id = s.business_id for update;
  select email, email_confirmed_at into mail, confirmed from auth.users where id = uid;

  if s.role = 'owner' then
    -- eigenaarsuitnodiging (van het beheer): dit account wordt eigenaar van de zaak
    if b.owner is not null and b.owner <> uid then
      raise exception 'Deze zaak heeft al een eigenaar. Vraag Pasr om een nieuwe uitnodiging.' using errcode = 'P0002', hint = 'invite_invalid';
    end if;
    if confirmed is null then
      raise exception 'Bevestig eerst je e-mailadres (zie de mail van Pasr) en probeer het dan opnieuw.' using errcode = '28000', hint = 'not_confirmed';
    end if;
    if exists (select 1 from public.pasr_businesses where owner = uid and id <> b.id) then
      raise exception 'Je bent al eigenaar van een andere zaak. Log in met een ander Pasr-account of vraag Pasr om hulp.' using errcode = '22023', hint = 'owner_taken';
    end if;
    update public.pasr_businesses set owner = uid, email = coalesce(mail, email), updated_at = now() where id = b.id returning * into b;
    -- was je hier medewerker of stond er al een eigenaarsrij voor je: opruimen
    update public.pasr_business_staff set revoked_at = now(), invite_code = null
    where business_id = b.id and user_id = uid and revoked_at is null and id <> s.id;
    update public.pasr_business_staff set user_id = uid, accepted_at = now(), invite_code = null,
      invited_email = coalesce(invited_email, mail) where id = s.id;
    -- andere open eigenaarsuitnodigingen vervallen
    update public.pasr_business_staff set revoked_at = now(), invite_code = null
    where business_id = b.id and role = 'owner' and user_id is null and revoked_at is null;
    insert into public.pasr_business_events (business_id, kind, amount, by_user, note)
    values (b.id, 'admin', 0, uid, 'Eigenaarsuitnodiging aangenomen');
    return jsonb_build_object('business', public.pasr_business_json(b) || jsonb_build_object('role', 'owner'));
  end if;

  if b.owner = uid then raise exception 'Dit is je eigen zaak.' using errcode = '22023', hint = 'invite_own'; end if;
  if exists (select 1 from public.pasr_business_staff where business_id = b.id and user_id = uid and revoked_at is null) then
    update public.pasr_business_staff set revoked_at = now(), invite_code = null where id = s.id;
  else
    update public.pasr_business_staff set user_id = uid, accepted_at = now(), invite_code = null,
      invited_email = coalesce(invited_email, mail) where id = s.id;
  end if;
  return jsonb_build_object('business', public.pasr_business_json(b) || jsonb_build_object('role', 'staff'));
end $$;

-- ---- beheer: eigenaar ----
-- Open eigenaarsuitnodiging van een zaak (of null).
create or replace function public.pasr_admin_owner_invite_json(p_business uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', s.id, 'invite_code', s.invite_code, 'email', s.invited_email,
      'link', 'https://pasr.nl/zakelijk/uitnodiging/#' || s.invite_code, 'app_link', 'pasrzakelijk://uitnodiging#' || s.invite_code,
      'expires_at', s.invite_expires_at, 'expired', s.invite_expires_at <= now(), 'created_at', s.created_at)
  from public.pasr_business_staff s
  where s.business_id = p_business and s.role = 'owner' and s.user_id is null and s.revoked_at is null and s.invite_code is not null
  order by s.created_at desc limit 1;
$$;

-- Eigenaar regelen voor een zaak zonder eigenaar: bevestigd account met dit adres = eigenaar, anders een (nieuwe)
-- eigenaarsuitnodiging van 30 dagen (oude open uitnodigingen vervallen). Geeft {owner: 'account'|'invite', invite}.
create or replace function public.pasr_admin_owner_assign(p_business uuid, p_email text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.pasr_businesses; mail text := lower(trim(coalesce(p_email, ''))); uid uuid; s public.pasr_business_staff;
begin
  select * into b from public.pasr_businesses where id = p_business for update;
  if b.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if b.owner is not null then raise exception 'has_owner' using errcode = '22023'; end if;
  if mail = '' then mail := lower(b.email); end if;
  if mail = '' or char_length(mail) > 200 or mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'bad_email' using errcode = '22023'; end if;
  select id into uid from auth.users where lower(email) = mail and email_confirmed_at is not null order by created_at limit 1;
  if uid is not null then
    if exists (select 1 from public.pasr_businesses where owner = uid) then raise exception 'owner_taken' using errcode = '22023'; end if;
    update public.pasr_businesses set owner = uid, email = mail, updated_at = now() where id = b.id;
    update public.pasr_business_staff set revoked_at = now(), invite_code = null
    where business_id = b.id and ((user_id = uid and revoked_at is null) or (role = 'owner' and user_id is null and revoked_at is null));
    insert into public.pasr_business_staff (business_id, user_id, role, invited_email, accepted_at)
    values (b.id, uid, 'owner', mail, now());
    perform public.pasr_admin_event(b.id, null, 'Eigenaar gekoppeld (bestaand Pasr-account)');
    return jsonb_build_object('owner', 'account', 'invite', null);
  end if;
  update public.pasr_business_staff set revoked_at = now(), invite_code = null
  where business_id = b.id and role = 'owner' and user_id is null and revoked_at is null;
  insert into public.pasr_business_staff (business_id, role, name, invited_email, invite_code, invite_expires_at)
  values (b.id, 'owner', '', mail, public.pasr_business_invite_code(), now() + interval '30 days') returning * into s;
  update public.pasr_businesses set email = mail, updated_at = now() where id = b.id and email is distinct from mail;
  perform public.pasr_admin_event(b.id, null, 'Eigenaarsuitnodiging gemaakt (30 dagen geldig)');
  -- bestaat er al een onbevestigd account met dit adres, dan kan het beheer dat bevestigen en eigenaar maken
  return jsonb_build_object('owner', 'invite', 'invite', public.pasr_admin_owner_invite_json(b.id),
    'unconfirmed_account', exists (select 1 from auth.users where lower(email) = mail and email_confirmed_at is null));
end $$;

-- ---- beheer: zaak aanmaken of bewerken ----
-- p_business: {id? (leeg = nieuw), name, city, address, website, email, note, listed, cooldown_minutes, max_per_scan}.
-- Nieuw: status approved, created_by 'beheer'; met e-mail meteen de eigenaar (account of uitnodiging), zonder e-mail
-- geen eigenaar. Bewerken: weglaten = laten staan; een nieuw e-mailadres bij een zaak zonder eigenaar regelt de eigenaar
-- opnieuw. Een ander adres wist de oude locatie (die zet de ondernemer met Pasr Zakelijk).
-- Antwoord: {business, owner: 'account'|'invite'|'none'|'unchanged', invite}.
create or replace function public.pasr_admin_business_save(p_business jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.pasr_businesses; bid uuid; isnew boolean; nm text; ct text; web text; mail text; nt text; own jsonb;
        sets jsonb := '{}'::jsonb; changes text[] := '{}'; prev public.pasr_businesses; uid uuid;
begin
  if jsonb_typeof(p_business) is distinct from 'object' then raise exception 'bad_business' using errcode = '22023'; end if;
  begin
    bid := nullif(p_business->>'id', '')::uuid;
  exception when others then raise exception 'not_found' using errcode = 'P0002';
  end;
  isnew := bid is null;
  if not isnew then
    select * into prev from public.pasr_businesses where id = bid for update;
    if prev.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  end if;
  nm := case when p_business ? 'name' or isnew then left(regexp_replace(trim(coalesce(p_business->>'name', '')), '\s+', ' ', 'g'), 60) else prev.name end;
  if char_length(nm) < 2 then raise exception 'bad_name' using errcode = '22023'; end if;
  ct := case when p_business ? 'city' or isnew then left(regexp_replace(trim(coalesce(p_business->>'city', '')), '\s+', ' ', 'g'), 60) else prev.city end;
  web := case when p_business ? 'website' or isnew then nullif(left(trim(coalesce(p_business->>'website', '')), 200), '') else prev.website end;
  if web is not null and web !~* '^https?://' then web := 'https://' || web; end if;
  if web is not null and (char_length(web) > 200 or web !~* '^https?://[a-z0-9.-]+\.[a-z]{2,}(:[0-9]+)?([/?#].*)?$') then
    raise exception 'bad_url' using errcode = '22023';
  end if;
  mail := case when p_business ? 'email' or isnew then lower(trim(coalesce(p_business->>'email', ''))) else prev.email end;
  if mail <> '' and (char_length(mail) > 200 or mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then raise exception 'bad_email' using errcode = '22023'; end if;
  nt := case when p_business ? 'note' then nullif(left(trim(coalesce(p_business->>'note', '')), 300), '') when isnew then null else prev.note end;

  -- eigenaar met een bestaand account dat al een zaak heeft: eerst melden, niets aanmaken
  if mail <> '' and (isnew or (prev.owner is null and mail is distinct from lower(prev.email))) then
    select id into uid from auth.users where lower(email) = mail and email_confirmed_at is not null order by created_at limit 1;
    if uid is not null and exists (select 1 from public.pasr_businesses where owner = uid) then
      raise exception 'owner_taken' using errcode = '22023';
    end if;
  end if;

  if isnew then
    insert into public.pasr_businesses (owner, name, city, email, website, note, status, reviewed_at, created_by)
    values (null, nm, ct, mail, web, nt, 'approved', now(), 'beheer') returning * into b;
    perform public.pasr_admin_event(b.id, null, 'Zaak aangemaakt door het beheer');
  else
    update public.pasr_businesses set name = nm, city = ct, website = web, note = nt,
      email = case when prev.owner is null then mail else (case when mail = '' then email else mail end) end, updated_at = now()
    where id = bid returning * into b;
    if nm is distinct from prev.name then changes := array_append(changes, 'naam'); end if;
    if ct is distinct from prev.city then changes := array_append(changes, 'plaats'); end if;
    if web is distinct from prev.website then changes := array_append(changes, 'website'); end if;
    if b.email is distinct from prev.email then changes := array_append(changes, 'e-mail'); end if;
    if nt is distinct from prev.note then changes := array_append(changes, 'notitie'); end if;
  end if;

  -- instellingen via dezelfde controle als de ondernemer (afkoeltijd, max per scan, vindbaar, adres)
  if p_business ? 'cooldown_minutes' and jsonb_typeof(p_business->'cooldown_minutes') <> 'null' then sets := sets || jsonb_build_object('cooldown_minutes', p_business->'cooldown_minutes'); end if;
  if p_business ? 'max_per_scan' and jsonb_typeof(p_business->'max_per_scan') <> 'null' then sets := sets || jsonb_build_object('max_per_scan', p_business->'max_per_scan'); end if;
  if p_business ? 'listed' and jsonb_typeof(p_business->'listed') <> 'null' then sets := sets || jsonb_build_object('listed', p_business->'listed'); end if;
  if p_business ? 'address' then
    sets := sets || jsonb_build_object('address', p_business->'address');
    if isnew or nullif(trim(coalesce(p_business->>'address', '')), '') is distinct from prev.address then
      sets := sets || jsonb_build_object('lat', null, 'lng', null);
    end if;
  end if;
  if sets <> '{}'::jsonb then
    b := public.pasr_business_settings_apply(b.id, sets);
    if not isnew then
      if b.cooldown_minutes is distinct from prev.cooldown_minutes then changes := array_append(changes, ('afkoeltijd ' || b.cooldown_minutes || ' min')); end if;
      if b.max_per_scan is distinct from prev.max_per_scan then changes := array_append(changes, ('max per scan ' || b.max_per_scan)); end if;
      if b.listed is distinct from prev.listed then changes := array_append(changes, (case when b.listed then 'vindbaar aan' else 'vindbaar uit' end)); end if;
      if b.address is distinct from prev.address then changes := array_append(changes, 'adres'); end if;
    end if;
  end if;
  if not isnew and array_length(changes, 1) > 0 then
    perform public.pasr_admin_event(b.id, null, left('Zaak bewerkt: ' || array_to_string(changes, ', '), 200));
  end if;

  -- eigenaar
  own := jsonb_build_object('owner', case when b.owner is not null then 'unchanged' else 'none' end, 'invite', null);
  if b.owner is null and mail <> '' and (isnew or mail is distinct from lower(prev.email)
                                          or public.pasr_admin_owner_invite_json(b.id) is null) then
    own := public.pasr_admin_owner_assign(b.id, mail);
  elsif b.owner is null and mail = '' and not isnew then
    -- geen e-mail meer: open eigenaarsuitnodigingen vervallen
    update public.pasr_business_staff set revoked_at = now(), invite_code = null
    where business_id = b.id and role = 'owner' and user_id is null and revoked_at is null;
  elsif b.owner is null then
    own := jsonb_build_object('owner', 'none', 'invite', public.pasr_admin_owner_invite_json(b.id));
  end if;
  select * into b from public.pasr_businesses where id = b.id;
  return jsonb_build_object('business', public.pasr_admin_business_json(b)) || own;
end $$;

-- Zaak voor het beheer: zaak-json met eigenaar, kaarten (met tellingen), medewerkers en open eigenaarsuitnodiging.
create or replace function public.pasr_admin_business_json(b public.pasr_businesses) returns jsonb
language sql stable security definer set search_path = public as $$
  select public.pasr_business_json(b) || jsonb_build_object(
    'cards', public.pasr_business_cards_json(b, true),
    'has_owner', b.owner is not null,
    'owner_email', (select u.email from auth.users u where u.id = b.owner),
    'owner_invite', public.pasr_admin_owner_invite_json(b.id),
    'created_by', b.created_by,
    'staff_count', (select count(*) from public.pasr_business_staff s where s.business_id = b.id and s.role = 'staff'
                    and s.revoked_at is null and s.user_id is not null),
    'last_event_at', (select max(at) from public.pasr_business_events e where e.business_id = b.id and e.kind <> 'admin'));
$$;

create or replace function public.pasr_admin_businesses() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.pasr_admin_business_json(b)
    order by case b.status when 'pending' then 0 when 'approved' then 1 else 2 end, b.created_at desc), '[]'::jsonb)
  from public.pasr_businesses b;
$$;

create or replace function public.pasr_admin_business_detail(p_business uuid, p_limit int default 200, p_days int default 30) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when b.id is null then null else jsonb_build_object(
    'business', public.pasr_admin_business_json(b),
    'staff', public.pasr_business_staff_json(b.id),
    'log', public.pasr_business_log_json_all(b.id, p_limit, true),
    'stats', public.pasr_business_stats_json(b.id, p_days)) end
  from (select 1) one left join public.pasr_businesses b on b.id = p_business;
$$;

-- status, instellingen en intrekken: nu ook in de log
create or replace function public.pasr_admin_business_status(p_business uuid, p_status text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.pasr_businesses; prev text;
begin
  if p_status not in ('pending', 'approved', 'blocked') then raise exception 'bad_status' using errcode = '22023'; end if;
  select status into prev from public.pasr_businesses where id = p_business;
  update public.pasr_businesses set status = p_status, reviewed_at = now(), updated_at = now() where id = p_business returning * into b;
  if b.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if p_status = 'blocked' then update public.pasr_business_cards set published = false, updated_at = now() where business_id = b.id and published; end if;
  if prev is distinct from p_status then
    perform public.pasr_admin_event(b.id, null, case p_status when 'approved' then 'Zaak goedgekeurd' when 'blocked' then 'Zaak geblokkeerd (kaarten offline)'
                                                 else 'Zaak terug naar wachten' end);
  end if;
  return public.pasr_business_json(b);
end $$;

create or replace function public.pasr_admin_business_settings(p_business uuid, p_settings jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.pasr_businesses; prev public.pasr_businesses; changes text[] := '{}';
begin
  select * into prev from public.pasr_businesses where id = p_business;
  if prev.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  b := public.pasr_business_settings_apply(p_business, p_settings);
  if b.cooldown_minutes is distinct from prev.cooldown_minutes then changes := array_append(changes, ('afkoeltijd ' || b.cooldown_minutes || ' min')); end if;
  if b.max_per_scan is distinct from prev.max_per_scan then changes := array_append(changes, ('max per scan ' || b.max_per_scan)); end if;
  if b.listed is distinct from prev.listed then changes := array_append(changes, (case when b.listed then 'vindbaar aan' else 'vindbaar uit' end)); end if;
  if b.address is distinct from prev.address then changes := array_append(changes, 'adres'); end if;
  if array_length(changes, 1) > 0 then
    perform public.pasr_admin_event(b.id, null, left('Instellingen: ' || array_to_string(changes, ', '), 200));
  end if;
  return public.pasr_business_json(b);
end $$;

create or replace function public.pasr_admin_business_staff_revoke(p_staff uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.pasr_business_staff;
begin
  update public.pasr_business_staff set revoked_at = coalesce(revoked_at, now()), invite_code = null where id = p_staff and role = 'staff'
  returning * into s;
  if s.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  perform public.pasr_admin_event(s.business_id, null, left('Medewerker ingetrokken' || case when s.name <> '' then ': ' || s.name else '' end, 200));
  return jsonb_build_object('ok', true);
end $$;

-- Nieuwe eigenaarsuitnodiging (opnieuw versturen): alleen voor een zaak zonder eigenaar. p_email leeg = het adres van de zaak.
create or replace function public.pasr_admin_owner_invite(p_business uuid, p_email text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; b public.pasr_businesses;
begin
  r := public.pasr_admin_owner_assign(p_business, p_email);
  select * into b from public.pasr_businesses where id = p_business;
  return jsonb_build_object('business', public.pasr_admin_business_json(b)) || r;
end $$;

-- ---- beheer: stempelkaarten van elke zaak ----
create or replace function public.pasr_admin_card_json(c public.pasr_business_cards, b public.pasr_businesses) returns jsonb
language sql stable security definer set search_path = public as $$
  select public.pasr_business_card_json(c, b) || jsonb_build_object('business_id', b.id, 'published', c.published, 'updated_at', c.updated_at,
    'members', (select count(*) from public.pasr_business_members m where m.business_card_id = c.id));
$$;

create or replace function public.pasr_admin_card_save(p_business uuid, p_card jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.pasr_businesses; c public.pasr_business_cards; prev public.pasr_business_cards; isnew boolean;
begin
  select * into b from public.pasr_businesses where id = p_business;
  if b.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if coalesce((p_card->>'published')::boolean, false) and b.status <> 'approved' then raise exception 'not_approved' using errcode = '22023'; end if;
  isnew := nullif(p_card->>'id', '') is null;
  if not isnew then
    begin
      select * into prev from public.pasr_business_cards where id = (p_card->>'id')::uuid and business_id = b.id;
    exception when others then raise exception 'not_found' using errcode = 'P0002';
    end;
  end if;
  c := public.pasr_business_card_apply(b, p_card);
  perform public.pasr_admin_event(b.id, c.id, case
    when isnew then 'Stempelkaart aangemaakt' || case when c.published then ' en gepubliceerd' else ' (concept)' end
    when c.published and not prev.published then 'Stempelkaart gewijzigd en gepubliceerd'
    when not c.published and prev.published then 'Stempelkaart gewijzigd en offline gehaald'
    else 'Stempelkaart gewijzigd' end);
  return public.pasr_admin_card_json(c, b);
end $$;

create or replace function public.pasr_admin_card_publish(p_card uuid, p_published boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.pasr_businesses; c public.pasr_business_cards;
begin
  select * into c from public.pasr_business_cards where id = p_card;
  if c.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  select * into b from public.pasr_businesses where id = c.business_id;
  if p_published and b.status <> 'approved' then raise exception 'not_approved' using errcode = '22023'; end if;
  if c.published is distinct from p_published then
    update public.pasr_business_cards set published = p_published, updated_at = now() where id = c.id returning * into c;
    perform public.pasr_admin_event(b.id, c.id, case when p_published then 'Stempelkaart gepubliceerd' else 'Stempelkaart offline gehaald' end);
  end if;
  return public.pasr_admin_card_json(c, b);
end $$;

-- Verwijderen: leden en hun stempels gaan mee weg; de log blijft (met de kaartnaam).
create or replace function public.pasr_admin_card_delete(p_card uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.pasr_business_cards; n int;
begin
  select * into c from public.pasr_business_cards where id = p_card;
  if c.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  select count(*) into n from public.pasr_business_members where business_card_id = c.id;
  perform public.pasr_admin_event(c.business_id, c.id, left('Stempelkaart verwijderd (' || n || case when n = 1 then ' lid)' else ' leden)' end, 200));
  delete from public.pasr_business_cards where id = c.id;
  return jsonb_build_object('ok', true, 'members', n);
end $$;

-- ---- beheer: testklant per stempelkaart (App Review van Pasr Zakelijk) ----
-- Een lid met label "Testklant (App Review)", zelfde codegenerator als pasr_business_join. De reviewer scant de QR-code
-- of typt de code. Alleen leden met een label kan het beheer resetten of verwijderen.
alter table public.pasr_business_members add column if not exists label text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'pasr_business_members_label_check') then
    alter table public.pasr_business_members add constraint pasr_business_members_label_check check (label is null or char_length(label) <= 60);
  end if;
end $$;

create or replace function public.pasr_admin_test_members_json(p_card uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'member_code', m.member_code, 'label', m.label, 'stamps_count', m.stamps_count,
      'rewards_redeemed', m.rewards_redeemed, 'created_at', m.created_at, 'last_stamp_at', m.last_stamp_at) order by m.created_at), '[]'::jsonb)
  from public.pasr_business_members m where m.business_card_id = p_card and m.label is not null;
$$;

create or replace function public.pasr_admin_test_member_create(p_card uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.pasr_business_cards; m public.pasr_business_members;
begin
  select * into c from public.pasr_business_cards where id = p_card;
  if c.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if (select count(*) from public.pasr_business_members where business_card_id = c.id and label is not null) >= 10 then
    raise exception 'test_limit' using errcode = '22023';
  end if;
  insert into public.pasr_business_members (business_card_id, member_code, label)
  values (c.id, public.pasr_business_new_code(), 'Testklant (App Review)') returning * into m;
  perform public.pasr_admin_event(c.business_id, c.id, 'Testklant (App Review) gemaakt: …' || right(m.member_code, 4));
  return jsonb_build_object('id', m.id, 'member_code', m.member_code, 'label', m.label, 'stamps_count', m.stamps_count,
    'rewards_redeemed', m.rewards_redeemed, 'created_at', m.created_at, 'last_stamp_at', m.last_stamp_at);
end $$;

-- p_action: 'reset' (stempels en beloningen op 0) of 'delete'.
create or replace function public.pasr_admin_test_member(p_member uuid, p_action text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.pasr_business_members; c public.pasr_business_cards;
begin
  select * into m from public.pasr_business_members where id = p_member and label is not null;
  if m.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  select * into c from public.pasr_business_cards where id = m.business_card_id;
  if p_action = 'reset' then
    update public.pasr_business_members set stamps_count = 0, rewards_redeemed = 0, last_stamp_at = null, updated_at = now()
    where id = m.id returning * into m;
    perform public.pasr_admin_event(c.business_id, c.id, 'Testklant gereset: …' || right(m.member_code, 4));
    return jsonb_build_object('ok', true, 'stamps_count', 0);
  elsif p_action = 'delete' then
    perform public.pasr_admin_event(c.business_id, c.id, 'Testklant verwijderd: …' || right(m.member_code, 4));
    delete from public.pasr_business_members where id = m.id;
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'bad_request' using errcode = '22023';
end $$;

-- kaart voor het beheer: met de testklanten
create or replace function public.pasr_admin_card_json(c public.pasr_business_cards, b public.pasr_businesses) returns jsonb
language sql stable security definer set search_path = public as $$
  select public.pasr_business_card_json(c, b) || jsonb_build_object('business_id', b.id, 'published', c.published, 'updated_at', c.updated_at,
    'members', (select count(*) from public.pasr_business_members m where m.business_card_id = c.id),
    'test_members', public.pasr_admin_test_members_json(c.id));
$$;

-- kaarten in het beheer-overzicht ook met testklanten
create or replace function public.pasr_admin_business_json(b public.pasr_businesses) returns jsonb
language sql stable security definer set search_path = public as $$
  select public.pasr_business_json(b) || jsonb_build_object(
    'cards', coalesce((select jsonb_agg(x || jsonb_build_object('test_members', public.pasr_admin_test_members_json((x->>'id')::uuid)))
                       from jsonb_array_elements(public.pasr_business_cards_json(b, true)) x), '[]'::jsonb),
    'has_owner', b.owner is not null,
    'owner_email', (select u.email from auth.users u where u.id = b.owner),
    'owner_invite', public.pasr_admin_owner_invite_json(b.id),
    'created_by', b.created_by,
    'unconfirmed_account', b.owner is null and b.email <> '' and exists (select 1 from auth.users u where lower(u.email) = lower(b.email) and u.email_confirmed_at is null),
    'staff_count', (select count(*) from public.pasr_business_staff s where s.business_id = b.id and s.role = 'staff'
                    and s.revoked_at is null and s.user_id is not null),
    'last_event_at', (select max(at) from public.pasr_business_events e where e.business_id = b.id and e.kind <> 'admin'));
$$;


-- ---- rechten ----
revoke all on function public.pasr_admin_event(uuid, uuid, text), public.pasr_business_log_json_all(uuid, int, boolean),
  public.pasr_business_invite_code(), public.pasr_business_card_apply(public.pasr_businesses, jsonb),
  public.pasr_admin_owner_invite_json(uuid), public.pasr_admin_owner_assign(uuid, text), public.pasr_admin_business_save(jsonb),
  public.pasr_admin_business_json(public.pasr_businesses), public.pasr_admin_owner_invite(uuid, text),
  public.pasr_admin_card_json(public.pasr_business_cards, public.pasr_businesses), public.pasr_admin_card_save(uuid, jsonb),
  public.pasr_admin_card_publish(uuid, boolean), public.pasr_admin_card_delete(uuid),
  public.pasr_admin_test_members_json(uuid), public.pasr_admin_test_member_create(uuid), public.pasr_admin_test_member(uuid, text),
  public.pasr_business_log_json(uuid, int), public.pasr_business_staff_invite_info(text), public.pasr_business_staff_accept(text),
  public.pasr_business_card_save(jsonb), public.pasr_admin_businesses(), public.pasr_admin_business_detail(uuid, int, int),
  public.pasr_admin_business_status(uuid, text), public.pasr_admin_business_settings(uuid, jsonb), public.pasr_admin_business_staff_revoke(uuid)
  from public, anon, authenticated;
grant execute on function public.pasr_business_staff_invite_info(text) to anon, authenticated;
grant execute on function public.pasr_business_staff_accept(text), public.pasr_business_card_save(jsonb) to authenticated;
grant execute on function public.pasr_admin_business_save(jsonb), public.pasr_admin_owner_invite(uuid, text),
  public.pasr_admin_card_save(uuid, jsonb), public.pasr_admin_card_publish(uuid, boolean), public.pasr_admin_card_delete(uuid),
  public.pasr_admin_test_member_create(uuid), public.pasr_admin_test_member(uuid, text),
  public.pasr_admin_businesses(), public.pasr_admin_business_detail(uuid, int, int), public.pasr_admin_business_status(uuid, text),
  public.pasr_admin_business_settings(uuid, jsonb), public.pasr_admin_business_staff_revoke(uuid) to service_role;
-- beheer: e-mailadres bevestigen (user_confirm, business_owner_confirm) loggen via de functie admin
grant execute on function public.pasr_admin_event(uuid, uuid, text), public.pasr_admin_user_id(text) to service_role;

-- ============================================================================================================
-- android 1.0 (Pasr en Pasr Zakelijk voor Android, Google Wallet). Elk apparaat meldt bij het opstarten (hoogstens
-- 1x per dag, en na in-/uitloggen of een update) welke app, welk platform en welke versie het draait. Alleen een
-- willekeurige id per installatie, geen naam, geen IP. Voor de inzichten in het beheer (iOS/Android, versies, actief).
-- Google Wallet: per object alleen een hash van de sleutel die de app bewaart, en bij een zakelijke stempelkaart de
-- klantcode (om het object na een stempel bij te werken). De kaartgegevens zelf staan bij Google, niet hier.
-- ============================================================================================================
create table if not exists public.pasr_devices (
  device_id  text primary key check (device_id ~ '^[A-Za-z0-9_-]{8,80}$'),
  app        text not null check (app in ('pasr', 'zakelijk')),
  platform   text not null check (platform in ('ios', 'android')),
  version    text check (version is null or char_length(version) <= 20),
  build      text check (build is null or char_length(build) <= 20),
  os         text check (os is null or char_length(os) <= 40),
  country    text check (country is null or country ~ '^[A-Z]{2}$'),
  user_id    uuid references auth.users (id) on delete set null,
  first_seen timestamptz not null default now(),
  last_seen  timestamptz not null default now()
);
create index if not exists pasr_devices_app on public.pasr_devices (app, platform, last_seen);
-- Actief per dag (een rij per apparaat per dag waarop het zich meldde), voor de grafiek. 400 dagen bewaard.
create table if not exists public.pasr_device_days (
  day       date not null,
  device_id text not null,
  app       text not null,
  platform  text not null,
  primary key (day, device_id)
);
create index if not exists pasr_device_days_day on public.pasr_device_days (day, app, platform);
alter table public.pasr_devices enable row level security;
alter table public.pasr_device_days enable row level security;
revoke all on public.pasr_devices, public.pasr_device_days from anon, authenticated;

create or replace function public.pasr_device_register(p_device text, p_app text, p_platform text, p_version text,
  p_build text default null, p_os text default null, p_country text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a text := lower(trim(coalesce(p_app, ''))); pl text := lower(trim(coalesce(p_platform, '')));
  c text := upper(trim(coalesce(p_country, '')));
begin
  if coalesce(p_device, '') !~ '^[A-Za-z0-9_-]{8,80}$' then raise exception 'bad_device' using errcode = '22023', hint = 'bad_device'; end if;
  if a not in ('pasr', 'zakelijk') then raise exception 'bad_app' using errcode = '22023', hint = 'bad_app'; end if;
  if pl not in ('ios', 'android') then raise exception 'bad_platform' using errcode = '22023', hint = 'bad_platform'; end if;
  if not exists (select 1 from public.pasr_devices where device_id = p_device) then
    perform public.pasr_web_rate_hit('device', 40, 100000);
  end if;
  insert into public.pasr_devices as d (device_id, app, platform, version, build, os, country, user_id)
  values (p_device, a, pl, nullif(left(trim(coalesce(p_version, '')), 20), ''), nullif(left(trim(coalesce(p_build, '')), 20), ''),
          nullif(left(trim(coalesce(p_os, '')), 40), ''), case when c ~ '^[A-Z]{2}$' then c end, auth.uid())
  on conflict (device_id) do update set app = excluded.app, platform = excluded.platform, version = excluded.version,
    build = excluded.build, os = coalesce(excluded.os, d.os), country = coalesce(excluded.country, d.country),
    user_id = auth.uid(), last_seen = now();
  insert into public.pasr_device_days (day, device_id, app, platform)
  values ((now() at time zone 'utc')::date, p_device, a, pl) on conflict do nothing;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.pasr_device_unregister(p_device text) returns jsonb
language sql security definer set search_path = public as $$
  delete from public.pasr_devices where device_id = p_device and (user_id is null or user_id = auth.uid());
  select jsonb_build_object('ok', true);
$$;

revoke all on function public.pasr_device_register(text, text, text, text, text, text, text),
  public.pasr_device_unregister(text) from public;
grant execute on function public.pasr_device_register(text, text, text, text, text, text, text),
  public.pasr_device_unregister(text) to anon, authenticated;

-- ---- Google Wallet (functie google-wallet) ----
create table if not exists public.pasr_gwallet_objects (
  object_id   text primary key check (char_length(object_id) between 3 and 200),
  key_hash    text not null check (key_hash ~ '^[0-9a-f]{64}$'),
  kind        text,
  member_code text check (member_code is null or char_length(member_code) <= 120),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
-- Logo van de kaart (PNG, base64, hoogstens ~200 kB): Google haalt het op via GET google-wallet?logo=<object_id>.
alter table public.pasr_gwallet_objects add column if not exists logo text check (logo is null or char_length(logo) <= 280000);
create index if not exists pasr_gwallet_member on public.pasr_gwallet_objects (member_code) where member_code is not null;
alter table public.pasr_gwallet_objects enable row level security;
revoke all on public.pasr_gwallet_objects from anon, authenticated;
alter table public.pasr_daily add column if not exists gwallet int not null default 0;

create or replace function public.pasr_count_gwallet() returns void
language sql security definer set search_path = public as $$
  insert into public.pasr_daily as d (day, gwallet) values ((now() at time zone 'utc')::date, 1)
  on conflict (day) do update set gwallet = d.gwallet + 1;
$$;
revoke all on function public.pasr_count_gwallet() from public, anon, authenticated;
grant execute on function public.pasr_count_gwallet() to service_role;

-- Nieuwe stand van een zakelijke stempelkaart: seintje aan de functie google-wallet (naast wallet-pass voor Apple).
create or replace function public.pasr_gwallet_business_kick() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare u text; s text;
begin
  if new.stamps_count is not distinct from old.stamps_count and new.rewards_redeemed is not distinct from old.rewards_redeemed then
    return new;
  end if;
  if not exists (select 1 from public.pasr_gwallet_objects where member_code = new.member_code) then return new; end if;
  select admin_url into u from public.pasr_admin_config where id = 1;
  select hook_secret into s from public.pasr_secret where id = 1;
  if coalesce(u, '') = '' or s is null then return new; end if;
  u := regexp_replace(u, '/admin/?$', '/google-wallet');
  perform net.http_post(url := u, body := jsonb_build_object('action', 'business', 'code', new.member_code),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-pasr-hook', s), timeout_milliseconds := 30000);
  return new;
exception when others then
  raise warning 'pasr_gwallet_business_kick: %', sqlerrm;
  return new;
end $$;
revoke all on function public.pasr_gwallet_business_kick() from public, anon, authenticated;
do $$
begin
  if to_regclass('public.pasr_business_members') is not null then
    drop trigger if exists pasr_gwallet_business on public.pasr_business_members;
    create trigger pasr_gwallet_business after update on public.pasr_business_members
      for each row execute function public.pasr_gwallet_business_kick();
  end if;
exception when others then
  raise notice 'pasr_gwallet_business trigger: %', sqlerrm;
end $$;

-- ---- Inzichten voor het beheer (functie admin, actie platforms) ----
create or replace function public.pasr_admin_platforms(p_days int default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d int := least(greatest(coalesce(p_days, 30), 7), 365); since date := (now() at time zone 'utc')::date - d + 1;
  apps jsonb := '{}'::jsonb; a text; pl text; block jsonb;
begin
  foreach a in array array['pasr', 'zakelijk'] loop
    block := '{}'::jsonb;
    foreach pl in array array['ios', 'android'] loop
      block := block || jsonb_build_object(pl, (
        select jsonb_build_object(
          'devices', count(*),
          'active_1', count(*) filter (where last_seen > now() - interval '1 day'),
          'active_7', count(*) filter (where last_seen > now() - interval '7 days'),
          'active_30', count(*) filter (where last_seen > now() - interval '30 days'),
          'new_period', count(*) filter (where first_seen::date >= since),
          'signed_in', count(*) filter (where user_id is not null))
        from public.pasr_devices where app = a and platform = pl));
    end loop;
    apps := apps || jsonb_build_object(a, block);
  end loop;
  return jsonb_build_object(
    'days', d,
    'apps', apps,
    'versions', coalesce((select jsonb_agg(v order by v->>'app', v->>'platform', (v->>'devices')::int desc) from (
        select jsonb_build_object('app', app, 'platform', platform, 'version', coalesce(version, '?'), 'build', coalesce(build, ''),
               'devices', count(*), 'active_30', count(*) filter (where last_seen > now() - interval '30 days')) v
        from public.pasr_devices group by app, platform, version, build) q), '[]'::jsonb),
    'os', coalesce((select jsonb_agg(jsonb_build_object('platform', platform, 'os', os, 'devices', n) order by n desc) from (
        select platform, coalesce(os, '?') os, count(*) n from public.pasr_devices
        where last_seen > now() - interval '30 days' group by platform, os order by n desc limit 20) q), '[]'::jsonb),
    'accounts', (select jsonb_build_object(
        'ios', count(*) filter (where coalesce(raw_user_meta_data->>'app', '') = 'ios'),
        'android', count(*) filter (where coalesce(raw_user_meta_data->>'app', '') in ('android', 'zakelijk-android')),
        'web', count(*) filter (where coalesce(raw_user_meta_data->>'app', '') like 'web%'),
        'other', count(*) filter (where coalesce(raw_user_meta_data->>'app', '') not in ('ios', 'android', 'zakelijk-android')
                                    and coalesce(raw_user_meta_data->>'app', '') not like 'web%'))
      from auth.users),
    'series', coalesce((select jsonb_agg(jsonb_build_object('day', g::date,
        'pasr_ios', (select count(*) from public.pasr_device_days x where x.day = g::date and x.app = 'pasr' and x.platform = 'ios'),
        'pasr_android', (select count(*) from public.pasr_device_days x where x.day = g::date and x.app = 'pasr' and x.platform = 'android'),
        'zakelijk_ios', (select count(*) from public.pasr_device_days x where x.day = g::date and x.app = 'zakelijk' and x.platform = 'ios'),
        'zakelijk_android', (select count(*) from public.pasr_device_days x where x.day = g::date and x.app = 'zakelijk' and x.platform = 'android'),
        'new_ios', (select count(*) from public.pasr_devices x where x.first_seen::date = g::date and x.platform = 'ios'),
        'new_android', (select count(*) from public.pasr_devices x where x.first_seen::date = g::date and x.platform = 'android'),
        'gwallet', coalesce((select x.gwallet from public.pasr_daily x where x.day = g::date), 0),
        'wallet', coalesce((select x.wallet from public.pasr_daily x where x.day = g::date), 0)) order by g)
      from generate_series(since, (now() at time zone 'utc')::date, interval '1 day') g), '[]'::jsonb),
    'gwallet', jsonb_build_object(
        'objects', (select count(*) from public.pasr_gwallet_objects),
        'updated_30', (select count(*) from public.pasr_gwallet_objects where updated_at > now() - interval '30 days'),
        'period', (select coalesce(sum(gwallet), 0) from public.pasr_daily where day >= since)),
    'apple_wallet', jsonb_build_object('period', (select coalesce(sum(wallet), 0) from public.pasr_daily where day >= since),
        'total', (select coalesce(sum(wallet), 0) from public.pasr_daily))
  );
end $$;
revoke all on function public.pasr_admin_platforms(int) from public, anon, authenticated;
grant execute on function public.pasr_admin_platforms(int) to service_role;

-- Opruimen: dagen ouder dan 400 dagen, apparaten die al 400 dagen niets lieten horen.
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'pasr-device-cleanup';
  perform cron.schedule('pasr-device-cleanup', '45 3 * * *',
    $q$delete from public.pasr_device_days where day < current_date - 400;
       delete from public.pasr_devices where last_seen < now() - interval '400 days';$q$);
exception when others then
  raise notice 'pg_cron niet beschikbaar: %', sqlerrm;
end $$;

-- ============================================================================================================
-- android push (FCM). Pasr en Pasr Zakelijk voor Android melden hun FCM-token mee met pasr_device_register. De
-- functie admin stuurt dan dezelfde meldingen als op iOS (APNs) ook via FCM HTTP v1: nieuws over mijn kaarten, een
-- stempel of een volle zakelijke stempelkaart, en een nieuwe winkel aan wie hem aanvroeg. Alleen het token, of
-- "Nieuws over mijn kaarten" aanstaat, de winkel-id's (zoals "ah") en de klantcodes van zakelijke stempelkaarten
-- (willekeurige codes, geen persoonsgegevens). Ongeldige tokens wist de functie admin meteen.
-- ============================================================================================================
alter table public.pasr_devices add column if not exists push_token text check (push_token is null or char_length(push_token) between 20 and 4096);
alter table public.pasr_devices add column if not exists push_provider text check (push_provider is null or push_provider in ('fcm', 'apns'));
alter table public.pasr_devices add column if not exists push_news boolean not null default false;
alter table public.pasr_devices add column if not exists push_stores text[] not null default '{}';
alter table public.pasr_devices add column if not exists member_codes text[] not null default '{}';
alter table public.pasr_devices add column if not exists push_updated timestamptz;
create index if not exists pasr_devices_push on public.pasr_devices (push_provider) where push_token is not null;
create index if not exists pasr_devices_members on public.pasr_devices using gin (member_codes);
create index if not exists pasr_devices_stores on public.pasr_devices using gin (push_stores);
-- beheer-apps op Android (later): provider per apparaat; bestaande rijen zijn APNs
alter table public.admin_push_devices add column if not exists provider text not null default 'apns';

drop function if exists public.pasr_device_register(text, text, text, text, text, text, text);
create or replace function public.pasr_device_register(p_device text, p_app text, p_platform text, p_version text,
  p_build text default null, p_os text default null, p_country text default null,
  p_push_token text default null, p_push_provider text default null, p_push_news boolean default null,
  p_stores text[] default null, p_member_codes text[] default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a text := lower(trim(coalesce(p_app, ''))); pl text := lower(trim(coalesce(p_platform, '')));
  c text := upper(trim(coalesce(p_country, ''))); t text := nullif(trim(coalesce(p_push_token, '')), '');
  pv text := lower(trim(coalesce(p_push_provider, ''))); s text[]; m text[];
begin
  if coalesce(p_device, '') !~ '^[A-Za-z0-9_-]{8,80}$' then raise exception 'bad_device' using errcode = '22023', hint = 'bad_device'; end if;
  if a not in ('pasr', 'zakelijk') then raise exception 'bad_app' using errcode = '22023', hint = 'bad_app'; end if;
  if pl not in ('ios', 'android') then raise exception 'bad_platform' using errcode = '22023', hint = 'bad_platform'; end if;
  if t is not null then
    if pv = '' then pv := case when pl = 'android' then 'fcm' else 'apns' end; end if;
    if pv not in ('fcm', 'apns') then raise exception 'bad_provider' using errcode = '22023', hint = 'bad_provider'; end if;
    if char_length(t) not between 20 and 4096 or t !~ '^[A-Za-z0-9_:.-]+$' then
      raise exception 'bad_token' using errcode = '22023', hint = 'bad_token';
    end if;
  end if;
  if p_stores is not null then
    select coalesce(array_agg(x order by x), '{}') into s
    from (select distinct lower(x) x from unnest(p_stores) x where lower(x) ~ '^[a-z0-9-]{2,40}$' limit 300) q;
  end if;
  if p_member_codes is not null then
    select coalesce(array_agg(x order by x), '{}') into m
    from (select distinct upper(x) x from unnest(p_member_codes) x where upper(x) ~ '^PZ[A-Z0-9]{10,40}$' limit 100) q;
  end if;
  if not exists (select 1 from public.pasr_devices where device_id = p_device) then
    perform public.pasr_web_rate_hit('device', 40, 100000);
  end if;
  insert into public.pasr_devices as d (device_id, app, platform, version, build, os, country, user_id,
                                        push_token, push_provider, push_news, push_stores, member_codes, push_updated)
  values (p_device, a, pl, nullif(left(trim(coalesce(p_version, '')), 20), ''), nullif(left(trim(coalesce(p_build, '')), 20), ''),
          nullif(left(trim(coalesce(p_os, '')), 40), ''), case when c ~ '^[A-Z]{2}$' then c end, auth.uid(),
          t, case when t is not null then pv end, coalesce(p_push_news, false), coalesce(s, '{}'), coalesce(m, '{}'),
          case when t is not null then now() end)
  on conflict (device_id) do update set app = excluded.app, platform = excluded.platform, version = excluded.version,
    build = excluded.build, os = coalesce(excluded.os, d.os), country = coalesce(excluded.country, d.country),
    user_id = auth.uid(), last_seen = now(),
    push_token = case when p_push_token is null then d.push_token else t end,
    push_provider = case when p_push_token is null then d.push_provider when t is null then null else pv end,
    push_updated = case when p_push_token is null then d.push_updated else now() end,
    push_news = coalesce(p_push_news, d.push_news),
    push_stores = coalesce(s, d.push_stores),
    member_codes = coalesce(m, d.member_codes);
  -- één token hoort bij één apparaat
  if t is not null then
    update public.pasr_devices set push_token = null, push_provider = null where push_token = t and device_id <> p_device;
  end if;
  insert into public.pasr_device_days (day, device_id, app, platform)
  values ((now() at time zone 'utc')::date, p_device, a, pl) on conflict do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.pasr_device_register(text, text, text, text, text, text, text, text, text, boolean, text[], text[]) from public;
grant execute on function public.pasr_device_register(text, text, text, text, text, text, text, text, text, boolean, text[], text[])
  to anon, authenticated;

-- Voor de functie admin: FCM-toestellen van Pasr met "Nieuws over mijn kaarten" aan, per doelgroep (zelfde regels als
-- pasr_admin_news_targets voor iOS).
create or replace function public.pasr_admin_news_targets_fcm(p_audience text, p_store text default null, p_days int default null)
returns table (device_id text, token text)
language sql stable security definer set search_path = public as $$
  select d.device_id, d.push_token from public.pasr_devices d
  where d.app = 'pasr' and d.push_provider = 'fcm' and d.push_token is not null and d.push_news and case p_audience
    when 'all' then true
    when 'store' then d.push_stores @> array[lower(coalesce(p_store, ''))]
    when 'new' then d.first_seen > now() - make_interval(days => coalesce(p_days, 7))
    when 'inactive' then d.last_seen < now() - make_interval(days => coalesce(p_days, 30))
    else false end;
$$;
-- FCM-toestellen met een zakelijke stempelkaart van deze klantcode (melding na een stempel of als hij vol is).
create or replace function public.pasr_admin_member_devices(p_code text)
returns table (device_id text, token text)
language sql stable security definer set search_path = public as $$
  select d.device_id, d.push_token from public.pasr_devices d
  where d.push_provider = 'fcm' and d.push_token is not null and d.member_codes @> array[upper(coalesce(p_code, ''))];
$$;
-- Wist een ongeldig FCM-token (de functie admin, na UNREGISTERED of INVALID_ARGUMENT van Google).
create or replace function public.pasr_admin_push_forget(p_devices text[]) returns int
language sql security definer set search_path = public as $$
  with x as (update public.pasr_devices set push_token = null, push_provider = null, push_updated = now()
             where device_id = any(coalesce(p_devices, '{}')) returning 1)
  select count(*)::int from x;
$$;
revoke all on function public.pasr_admin_news_targets_fcm(text, text, int), public.pasr_admin_member_devices(text),
  public.pasr_admin_push_forget(text[]) from public, anon, authenticated;
grant execute on function public.pasr_admin_news_targets_fcm(text, text, int), public.pasr_admin_member_devices(text),
  public.pasr_admin_push_forget(text[]) to service_role;

-- Stempel gezet of kaart vol: seintje aan de functie admin (die stuurt via FCM naar Android-toestellen met die kaart).
-- Alleen als er zo'n toestel is. Via pg_net: houdt de stempel nooit op.
create or replace function public.pasr_member_push_kick() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.stamps_count is not distinct from old.stamps_count then return new; end if;
  if not exists (select 1 from public.pasr_devices where push_provider = 'fcm' and member_codes @> array[upper(new.member_code)]) then
    return new;
  end if;
  perform public.pasr_admin_notify('member', jsonb_build_object('code', new.member_code, 'before', old.stamps_count, 'after', new.stamps_count));
  return new;
exception when others then
  raise warning 'pasr_member_push_kick: %', sqlerrm;
  return new;
end $$;
revoke all on function public.pasr_member_push_kick() from public, anon, authenticated;
do $$
begin
  if to_regclass('public.pasr_business_members') is not null then
    drop trigger if exists pasr_member_push on public.pasr_business_members;
    create trigger pasr_member_push after update of stamps_count on public.pasr_business_members
      for each row execute function public.pasr_member_push_kick();
  end if;
exception when others then
  raise notice 'pasr_member_push trigger: %', sqlerrm;
end $$;

-- Inzichten: "push aan" per platform (bovenop pasr_admin_platforms).
create or replace function public.pasr_admin_push_platforms() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'ios', (select count(distinct x.device_id) from (
              select device_id from public.pasr_user_push
              union select device_id from public.pasr_news_devices where token is not null) x),
    'ios_news', (select count(*) from public.pasr_news_devices),
    'android', (select count(*) from public.pasr_devices where app = 'pasr' and push_provider = 'fcm' and push_token is not null),
    'android_news', (select count(*) from public.pasr_devices where app = 'pasr' and push_provider = 'fcm' and push_token is not null and push_news),
    'zakelijk_android', (select count(*) from public.pasr_devices where app = 'zakelijk' and push_provider = 'fcm' and push_token is not null));
$$;
revoke all on function public.pasr_admin_push_platforms() from public, anon, authenticated;
grant execute on function public.pasr_admin_push_platforms() to service_role;

-- ============================================================================================================
-- push iedereen (beheer › Bericht sturen, 22 nov 2026). Naast de opt-in "Nieuws over mijn kaarten" kan het beheer een
-- belangrijk bericht sturen aan iedereen met meldingen aan: elk apparaat met een geldig push-token, van Pasr en/of
-- Pasr Zakelijk, op Apple en/of Android. Apple-richtlijn 4.5.4: zonder opt-in alleen belangrijke berichten, geen
-- reclame. Optioneel met een https-link die een tik op de melding opent. iOS meldt het APNs-token nu ook met
-- pasr_device_register (p_push_provider 'apns', p_push_sandbox), zodat ook apparaten zonder account en zonder opt-in
-- (en Pasr Zakelijk voor iOS) bereikbaar zijn. Alleen tokens, geen namen of kaartgegevens.
-- ============================================================================================================
alter table public.pasr_devices add column if not exists push_sandbox boolean not null default false;

alter table public.pasr_news_campaigns drop constraint if exists pasr_news_campaigns_audience_check;
alter table public.pasr_news_campaigns add constraint pasr_news_campaigns_audience_check
  check (audience in ('all', 'store', 'new', 'inactive', 'everyone'));
alter table public.pasr_news_campaigns add column if not exists platform text not null default 'all';
alter table public.pasr_news_campaigns add column if not exists app text not null default 'pasr';
alter table public.pasr_news_campaigns add column if not exists url text;
alter table public.pasr_news_campaigns add column if not exists fingerprint text;
alter table public.pasr_news_campaigns drop constraint if exists pasr_news_campaigns_platform_check;
alter table public.pasr_news_campaigns add constraint pasr_news_campaigns_platform_check check (platform in ('all', 'ios', 'android'));
alter table public.pasr_news_campaigns drop constraint if exists pasr_news_campaigns_app_check;
alter table public.pasr_news_campaigns add constraint pasr_news_campaigns_app_check check (app in ('pasr', 'zakelijk', 'both'));
alter table public.pasr_news_campaigns drop constraint if exists pasr_news_campaigns_url_check;
alter table public.pasr_news_campaigns add constraint pasr_news_campaigns_url_check
  check (url is null or (char_length(url) <= 500 and url ~ '^https://[^\s]+$'));
create index if not exists pasr_news_campaigns_created on public.pasr_news_campaigns (created_at desc);

drop function if exists public.pasr_device_register(text, text, text, text, text, text, text, text, text, boolean, text[], text[]);
create or replace function public.pasr_device_register(p_device text, p_app text, p_platform text, p_version text,
  p_build text default null, p_os text default null, p_country text default null,
  p_push_token text default null, p_push_provider text default null, p_push_news boolean default null,
  p_stores text[] default null, p_member_codes text[] default null, p_push_sandbox boolean default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a text := lower(trim(coalesce(p_app, ''))); pl text := lower(trim(coalesce(p_platform, '')));
  c text := upper(trim(coalesce(p_country, ''))); t text := nullif(trim(coalesce(p_push_token, '')), '');
  pv text := lower(trim(coalesce(p_push_provider, ''))); s text[]; m text[];
begin
  if coalesce(p_device, '') !~ '^[A-Za-z0-9_-]{8,80}$' then raise exception 'bad_device' using errcode = '22023', hint = 'bad_device'; end if;
  if a not in ('pasr', 'zakelijk') then raise exception 'bad_app' using errcode = '22023', hint = 'bad_app'; end if;
  if pl not in ('ios', 'android') then raise exception 'bad_platform' using errcode = '22023', hint = 'bad_platform'; end if;
  if t is not null then
    if pv = '' then pv := case when pl = 'android' then 'fcm' else 'apns' end; end if;
    if pv not in ('fcm', 'apns') then raise exception 'bad_provider' using errcode = '22023', hint = 'bad_provider'; end if;
    if char_length(t) not between 20 and 4096 or t !~ '^[A-Za-z0-9_:.-]+$' then
      raise exception 'bad_token' using errcode = '22023', hint = 'bad_token';
    end if;
    -- APNs-tokens zijn hex (kleine letters, zoals in pasr_user_push)
    if pv = 'apns' then
      t := lower(t);
      if t !~ '^[0-9a-f]{64,200}$' then raise exception 'bad_token' using errcode = '22023', hint = 'bad_token'; end if;
    end if;
  end if;
  if p_stores is not null then
    select coalesce(array_agg(x order by x), '{}') into s
    from (select distinct lower(x) x from unnest(p_stores) x where lower(x) ~ '^[a-z0-9-]{2,40}$' limit 300) q;
  end if;
  if p_member_codes is not null then
    select coalesce(array_agg(x order by x), '{}') into m
    from (select distinct upper(x) x from unnest(p_member_codes) x where upper(x) ~ '^PZ[A-Z0-9]{10,40}$' limit 100) q;
  end if;
  if not exists (select 1 from public.pasr_devices where device_id = p_device) then
    perform public.pasr_web_rate_hit('device', 40, 100000);
  end if;
  insert into public.pasr_devices as d (device_id, app, platform, version, build, os, country, user_id,
                                        push_token, push_provider, push_news, push_stores, member_codes, push_updated, push_sandbox)
  values (p_device, a, pl, nullif(left(trim(coalesce(p_version, '')), 20), ''), nullif(left(trim(coalesce(p_build, '')), 20), ''),
          nullif(left(trim(coalesce(p_os, '')), 40), ''), case when c ~ '^[A-Z]{2}$' then c end, auth.uid(),
          t, case when t is not null then pv end, coalesce(p_push_news, false), coalesce(s, '{}'), coalesce(m, '{}'),
          case when t is not null then now() end, coalesce(p_push_sandbox, false))
  on conflict (device_id) do update set app = excluded.app, platform = excluded.platform, version = excluded.version,
    build = excluded.build, os = coalesce(excluded.os, d.os), country = coalesce(excluded.country, d.country),
    user_id = auth.uid(), last_seen = now(),
    push_token = case when p_push_token is null then d.push_token else t end,
    push_provider = case when p_push_token is null then d.push_provider when t is null then null else pv end,
    push_updated = case when p_push_token is null then d.push_updated else now() end,
    push_sandbox = coalesce(p_push_sandbox, d.push_sandbox),
    push_news = coalesce(p_push_news, d.push_news),
    push_stores = coalesce(s, d.push_stores),
    member_codes = coalesce(m, d.member_codes);
  -- één token hoort bij één apparaat
  if t is not null then
    update public.pasr_devices set push_token = null, push_provider = null where push_token = t and device_id <> p_device;
  end if;
  insert into public.pasr_device_days (day, device_id, app, platform)
  values ((now() at time zone 'utc')::date, p_device, a, pl) on conflict do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.pasr_device_register(text, text, text, text, text, text, text, text, text, boolean, text[], text[], boolean) from public;
grant execute on function public.pasr_device_register(text, text, text, text, text, text, text, text, text, boolean, text[], text[], boolean)
  to anon, authenticated;

-- Voor de functie admin: iedereen met meldingen aan. p_app: pasr | zakelijk | both; p_platform: all | ios | android.
-- Een toestel kan in meer tabellen staan (apparaatregister, account, opt-in): per app en token één rij.
-- src zegt waar het token vandaan komt, zodat de functie admin een ongeldig token op de juiste plek wist.
create or replace function public.pasr_admin_push_everyone(p_app text default 'pasr', p_platform text default 'all')
returns table (device_id text, token text, provider text, sandbox boolean, app text, src text)
language sql stable security definer set search_path = public as $$
  with x as (
    select d.device_id, d.push_token token, d.push_provider provider, d.push_sandbox sandbox, d.app, 'device'::text src, 3 prio
    from public.pasr_devices d
    where d.push_token is not null and d.push_provider in ('apns', 'fcm')
    union all
    select u.device_id, u.token, 'apns', u.sandbox, 'pasr', 'user', 1 from public.pasr_user_push u
    union all
    select n.device_id, n.token, 'apns', n.sandbox, 'pasr', 'news', 2 from public.pasr_news_devices n where n.token is not null
  )
  select distinct on (x.app, lower(x.token)) x.device_id, x.token, x.provider, x.sandbox, x.app, x.src
  from x
  where (coalesce(p_app, 'pasr') = 'both' or x.app = coalesce(p_app, 'pasr'))
    and case coalesce(p_platform, 'all') when 'ios' then x.provider = 'apns' when 'android' then x.provider = 'fcm' else true end
  order by x.app, lower(x.token), x.prio;
$$;
-- Tellingen voor het scherm "Bericht sturen": iedereen met meldingen aan, per app en platform.
create or replace function public.pasr_admin_push_everyone_counts() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'pasr', jsonb_build_object(
      'ios', (select count(*) from public.pasr_admin_push_everyone('pasr', 'ios')),
      'android', (select count(*) from public.pasr_admin_push_everyone('pasr', 'android'))),
    'zakelijk', jsonb_build_object(
      'ios', (select count(*) from public.pasr_admin_push_everyone('zakelijk', 'ios')),
      'android', (select count(*) from public.pasr_admin_push_everyone('zakelijk', 'android'))));
$$;
revoke all on function public.pasr_admin_push_everyone(text, text), public.pasr_admin_push_everyone_counts()
  from public, anon, authenticated;
grant execute on function public.pasr_admin_push_everyone(text, text), public.pasr_admin_push_everyone_counts() to service_role;

-- ============================================================================================================
-- Deelpagina per stempelkaart (pasr.nl/zakelijk/kaart/<id>/ met eigen titel, beschrijving en OG-afbeelding).
-- De Website-workflow bouwt elk uur een pagina voor elke gepubliceerde kaart van een goedgekeurde zaak, ook als de zaak
-- niet vindbaar is (listed = false: die pagina krijgt noindex en staat niet in de sitemap). Daarom NIET voor anon: anders
-- kan iedereen met de publieke sleutel de niet-vindbare zaken opsommen. De workflow vraagt hem op via de Management API
-- (SUPABASE_ACCESS_TOKEN); zonder die sleutel valt hij terug op pasr_business_directory (alleen vindbare kaarten).
-- Alleen velden die ook op de kaart en de joinpagina staan (pasr_business_card_public), plus website, listed en
-- updated_at (zodat de OG-afbeelding alleen opnieuw wordt gemaakt als er iets veranderd is). Geen e-mail, geen eigenaar.
create or replace function public.pasr_business_share_cards() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('card_id', c.id, 'card_name', c.name, 'business_name', b.name, 'city', b.city,
      'website', b.website, 'logo', c.logo, 'color', c.color, 'text_color', c.text_color, 'stamps_total', c.stamps_total,
      'reward', c.reward, 'listed', b.listed, 'updated_at', greatest(c.updated_at, b.updated_at))
    order by lower(b.name), lower(c.name), c.id), '[]'::jsonb)
  from public.pasr_business_cards c join public.pasr_businesses b on b.id = c.business_id
  where c.published and b.status = 'approved';
$$;
revoke all on function public.pasr_business_share_cards() from public, anon, authenticated;
grant execute on function public.pasr_business_share_cards() to service_role;


-- PASR LOYALTY 2: opt-in instellingen, campagnes, beloningen, referral en kortingsbonnen.
-- Nieuwe objecten hebben RLS aan; clients gebruiken uitsluitend security-definer RPC's.
create table if not exists public.pasr_business_programs (
  card_id uuid primary key references public.pasr_business_cards(id) on delete cascade,
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint pasr_program_settings_object check (jsonb_typeof(settings) = 'object' and octet_length(settings::text) <= 12000)
);
alter table public.pasr_business_programs enable row level security;
revoke all on public.pasr_business_programs from anon, authenticated;

create table if not exists public.pasr_business_coupons (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.pasr_businesses(id) on delete cascade,
  card_id uuid references public.pasr_business_cards(id) on delete set null,
  title text not null check (char_length(title) between 3 and 80),
  description text not null default '' check (char_length(description) <= 300),
  discount_type text not null check (discount_type in ('amount','percent')),
  discount_value numeric(10,2) not null check (discount_value > 0),
  min_spend numeric(10,2) not null default 0 check (min_spend >= 0),
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  max_claims integer not null default 500 check (max_claims between 1 and 100000),
  one_per_customer boolean not null default true,
  public boolean not null default false,
  created_at timestamptz not null default now(),
  constraint pasr_coupon_window check (ends_at > starts_at and ends_at <= starts_at + interval '366 days'),
  constraint pasr_coupon_discount check ((discount_type='percent' and discount_value <= 100) or (discount_type='amount' and discount_value <= 100000))
);
create index if not exists pasr_coupons_public_idx on public.pasr_business_coupons(public,starts_at,ends_at);
create index if not exists pasr_coupons_business_idx on public.pasr_business_coupons(business_id,created_at desc);
alter table public.pasr_business_coupons enable row level security;
revoke all on public.pasr_business_coupons from anon, authenticated;

create table if not exists public.pasr_business_coupon_claims (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.pasr_business_coupons(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  redeem_code text not null unique,
  claimed_at timestamptz not null default now(),
  redeemed_at timestamptz,
  redeemed_by uuid references auth.users(id),
  constraint pasr_claim_code_format check (redeem_code ~ '^PC[A-HJ-NP-Z2-9]{22}$')
);
create index if not exists pasr_claim_coupon_idx on public.pasr_business_coupon_claims(coupon_id, claimed_at);
create index if not exists pasr_claim_user_idx on public.pasr_business_coupon_claims(user_id, claimed_at desc);
alter table public.pasr_business_coupon_claims enable row level security;
revoke all on public.pasr_business_coupon_claims from anon, authenticated;

-- Alleen eigenaren kunnen configuraties van hun kaarten wijzigen; veld- en lengtelimieten worden op server gevalideerd.
create or replace function public.pasr_business_program(p_card uuid, p_settings jsonb default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_business public.pasr_businesses; p jsonb; rewards jsonb; v jsonb; n int; prev int := 0;
begin
  select business_row.* into v_business from public.pasr_business_cards card_row
    join public.pasr_businesses business_row on business_row.id=card_row.business_id where card_row.id=p_card;
  if v_business.id is null or v_business.owner is distinct from auth.uid() then
    raise exception 'Alleen de eigenaar kan kaartinstellingen wijzigen.' using errcode='42501';
  end if;
  if p_settings is not null then
    if v_business.status='blocked' or jsonb_typeof(p_settings)<>'object' or octet_length(p_settings::text)>12000 then
      raise exception 'Ongeldige instellingen.' using errcode='22023';
    end if;
    if exists (select 1 from jsonb_object_keys(p_settings) k
      where k not in ('rewards','referral','campaign','vip','retention','locations','marketing','community')) then
      raise exception 'Onbekende instellingen.' using errcode='22023';
    end if;
    -- Een reward is een vast aantal stempels tussen 2 en het kaartmaximum, met eigen titel.
    rewards:=coalesce(p_settings->'rewards','[]'::jsonb);
    if jsonb_typeof(rewards)<>'array' or jsonb_array_length(rewards)>8 then
      raise exception 'Maximaal 8 beloningen.' using errcode='22023';
    end if;
    for v in select value from jsonb_array_elements(rewards) loop
      if jsonb_typeof(v)<>'object' or (v->>'stamps')!~'^[0-9]{1,2}$'
        or char_length(coalesce(v->>'title','')) not between 3 and 80 then
        raise exception 'Controleer de beloningen.' using errcode='22023';
      end if;
      n:=(v->>'stamps')::int;
      if n<=prev or n> (select stamps_total from public.pasr_business_cards where id=p_card) then
        raise exception 'Mijlpalen moeten oplopend en binnen het kaartmaximum liggen.' using errcode='22023';
      end if;
      prev:=n;
    end loop;
    for v in select value from jsonb_each(p_settings) loop
      if jsonb_typeof(v) not in ('object','array') then
        raise exception 'Ongeldige instellingen.' using errcode='22023';
      end if;
    end loop;
    insert into public.pasr_business_programs(card_id,settings,updated_at)
      values(p_card,p_settings,now())
    on conflict(card_id) do update set settings=excluded.settings,updated_at=now();
  end if;
  select settings into p from public.pasr_business_programs where card_id=p_card;
  return jsonb_build_object('card_id',p_card,'settings',coalesce(p,'{}'::jsonb));
end $$;

-- Publicatie bevat alleen de zichtbaar ingestelde kaartvoordelen. Nooit interne campagnes/ledengegevens.
create or replace function public.pasr_business_program_public(p_card uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce((select jsonb_build_object('rewards',coalesce(p.settings->'rewards','[]'::jsonb),
      'vip',coalesce(p.settings->'vip','{}'::jsonb),
      'referral',coalesce(p.settings->'referral','{}'::jsonb),
      'campaign',coalesce(p.settings->'campaign','{}'::jsonb))
    from public.pasr_business_programs p
    join public.pasr_business_cards c on c.id=p.card_id
    join public.pasr_businesses b on b.id=c.business_id
    where p.card_id=p_card and c.published and b.status='approved'), '{}'::jsonb);
$$;

-- Alleen een eigen ondernemer krijgt alle eigen coupons; voor andere gebruikers alleen live openbare aanbiedingen.
create or replace function public.pasr_business_coupon_list(p_business uuid default null)
returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'business_id',b.id,'business',b.name,'city',b.city,
     'card_id',c.card_id,'title',c.title,'description',c.description,'discount_type',c.discount_type,
     'discount_value',c.discount_value,'min_spend',c.min_spend,'starts_at',c.starts_at,'ends_at',c.ends_at,
     'max_claims',c.max_claims,'one_per_customer',c.one_per_customer,'public',c.public,
     'claimed', (select count(*) from public.pasr_business_coupon_claims cc where cc.coupon_id=c.id),
     'redeemed',(select count(*) from public.pasr_business_coupon_claims cc where cc.coupon_id=c.id and cc.redeemed_at is not null))
    order by c.ends_at), '[]'::jsonb)
  from public.pasr_business_coupons c join public.pasr_businesses b on b.id=c.business_id
  where b.status='approved' and (
    (p_business is not null and c.business_id=p_business and b.owner=auth.uid()) or
    (p_business is null and c.public and b.listed and now() between c.starts_at and c.ends_at));
$$;

create or replace function public.pasr_business_coupon_save(p_coupon jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare b public.pasr_businesses; cid uuid; c public.pasr_business_coupons;
  t text; desc_text text; typ text; v numeric; m numeric; st timestamptz; en timestamptz;
  maxn int; pub boolean; onep boolean; linked uuid;
begin
  if auth.uid() is null then raise exception 'Log eerst in.' using errcode='28000'; end if;
  if jsonb_typeof(p_coupon)<>'object' or octet_length(p_coupon::text)>4000 then raise exception 'Ongeldige kortingsbon.' using errcode='22023'; end if;
  select * into b from public.pasr_businesses where id=(p_coupon->>'business_id')::uuid and owner=auth.uid();
  if b.id is null or b.status<>'approved' then raise exception 'Je zaak is niet goedgekeurd.' using errcode='42501'; end if;
  cid:=nullif(p_coupon->>'id','')::uuid;
  t:=trim(coalesce(p_coupon->>'title',''));desc_text:=trim(coalesce(p_coupon->>'description',''));
  typ:=p_coupon->>'discount_type';
  v:=(p_coupon->>'discount_value')::numeric;m:=coalesce((p_coupon->>'min_spend')::numeric,0);
  st:=coalesce((p_coupon->>'starts_at')::timestamptz,now());
  en:=(p_coupon->>'ends_at')::timestamptz;
  maxn:=coalesce((p_coupon->>'max_claims')::int,500);
  onep:=coalesce((p_coupon->>'one_per_customer')::boolean,true);
  pub:=coalesce((p_coupon->>'public')::boolean,false);
  linked:=nullif(p_coupon->>'card_id','')::uuid;
  if linked is not null and not exists(select 1 from public.pasr_business_cards where id=linked and business_id=b.id) then
    raise exception 'Kaart hoort niet bij je zaak.' using errcode='42501';
  end if;
  if char_length(t) not between 3 and 80 or char_length(desc_text)>300 or
     typ not in ('amount','percent') or v<=0 or v > (case when typ='percent' then 100 else 100000 end) or
     m<0 or maxn not between 1 and 100000 or en is null or en<=st or en>st+interval '366 days' then
     raise exception 'Controleer bedrag, tekst en datums.' using errcode='22023';
  end if;
  if cid is null then
    insert into public.pasr_business_coupons(business_id,card_id,title,description,discount_type,discount_value,min_spend,starts_at,ends_at,max_claims,one_per_customer,public)
    values(b.id,linked,t,desc_text,typ,v,m,st,en,maxn,onep,pub) returning * into c;
  else
    update public.pasr_business_coupons set title=t,description=desc_text,card_id=linked,discount_type=typ,
       discount_value=v,min_spend=m,starts_at=st,ends_at=en,max_claims=maxn,one_per_customer=onep,public=pub
    where id=cid and business_id=b.id returning * into c;
    if c.id is null then raise exception 'Kortingsbon niet gevonden.' using errcode='P0002'; end if;
  end if;
  return jsonb_build_object('id',c.id,'ok',true);
end $$;

-- Geauthenticeerde klanten halen een persoonlijke niet te raden QR-code op. Geen code zonder actieve campagne.
create or replace function public.pasr_business_coupon_claim(p_coupon uuid)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare c public.pasr_business_coupons; b public.pasr_businesses; used int; code text; alphabet text:='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  raw bytea; i int; claim public.pasr_business_coupon_claims;
begin
  if auth.uid() is null then raise exception 'Log in bij Pasr om deze kortingsbon te bewaren.' using errcode='28000'; end if;
  select * into c from public.pasr_business_coupons where id=p_coupon for update;
  if c.id is null then raise exception 'Kortingsbon niet gevonden.' using errcode='P0002'; end if;
  select * into b from public.pasr_businesses where id=c.business_id;
  if not c.public or not b.listed or b.status<>'approved' or now() not between c.starts_at and c.ends_at then
    raise exception 'Deze kortingsbon is niet beschikbaar.' using errcode='22023';
  end if;
  if c.one_per_customer then
    select * into claim from public.pasr_business_coupon_claims where coupon_id=c.id and user_id=auth.uid() order by claimed_at desc limit 1;
    if claim.id is not null then
      return jsonb_build_object('id',claim.id,'code',claim.redeem_code,'redeemed',claim.redeemed_at is not null,'ends_at',c.ends_at);
    end if;
  end if;
  select count(*) into used from public.pasr_business_coupon_claims where coupon_id=c.id;
  if used>=c.max_claims then raise exception 'Alle kortingsbonnen zijn uitgegeven.' using errcode='22023'; end if;
  loop
    code:='PC';raw:=gen_random_bytes(22);
    for i in 0..21 loop code:=code||substr(alphabet,(get_byte(raw,i)%32)+1,1);end loop;
    exit when not exists(select 1 from public.pasr_business_coupon_claims where redeem_code=code);
  end loop;
  insert into public.pasr_business_coupon_claims(coupon_id,user_id,redeem_code)
  values(c.id,auth.uid(),code) returning * into claim;
  return jsonb_build_object('id',claim.id,'code',claim.redeem_code,'redeemed',false,'ends_at',c.ends_at);
end $$;

create or replace function public.pasr_business_coupon_mine()
returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',cc.id,'coupon_id',c.id,'code',cc.redeem_code,
    'title',c.title,'business',b.name,'discount_type',c.discount_type,'discount_value',c.discount_value,
    'min_spend',c.min_spend,'ends_at',c.ends_at,'redeemed',cc.redeemed_at is not null)
    order by c.ends_at), '[]'::jsonb)
  from public.pasr_business_coupon_claims cc
  join public.pasr_business_coupons c on c.id=cc.coupon_id
  join public.pasr_businesses b on b.id=c.business_id
  where cc.user_id=auth.uid();
$$;

-- De bon wordt in een transactie met FOR UPDATE eenmaal verzilverd; medewerker mag eigen zaak afhandelen.
create or replace function public.pasr_business_coupon_redeem(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare claim public.pasr_business_coupon_claims; c public.pasr_business_coupons; b public.pasr_businesses;
begin
  if auth.uid() is null then raise exception 'Log in om een bon te verzilveren.' using errcode='28000'; end if;
  select * into claim from public.pasr_business_coupon_claims where redeem_code=upper(trim(p_code)) for update;
  if claim.id is null then raise exception 'Onbekende kortingsbon.' using errcode='P0002'; end if;
  select * into c from public.pasr_business_coupons where id=claim.coupon_id;
  select * into b from public.pasr_businesses where id=c.business_id;
  if b.owner is distinct from auth.uid() and public.pasr_business_role(b.id) is null then
     raise exception 'Deze bon hoort niet bij jouw zaak.' using errcode='42501';
  end if;
  if claim.redeemed_at is not null then raise exception 'Deze kortingsbon is al gebruikt.' using errcode='22023'; end if;
  if now()<c.starts_at or now()>c.ends_at or not c.public or b.status<>'approved' then
     raise exception 'Deze kortingsbon is niet (meer) geldig.' using errcode='22023';
  end if;
  update public.pasr_business_coupon_claims set redeemed_at=now(),redeemed_by=auth.uid() where id=claim.id;
  return jsonb_build_object('ok',true,'business',b.name,'title',c.title,
      'discount_type',c.discount_type,'discount_value',c.discount_value,'min_spend',c.min_spend);
end $$;

revoke all on function public.pasr_business_program(uuid,jsonb),
 public.pasr_business_program_public(uuid), public.pasr_business_coupon_list(uuid),
 public.pasr_business_coupon_save(jsonb), public.pasr_business_coupon_claim(uuid),
 public.pasr_business_coupon_mine(),public.pasr_business_coupon_redeem(text) from public;
grant execute on function public.pasr_business_program(uuid,jsonb),public.pasr_business_coupon_save(jsonb),
  public.pasr_business_coupon_claim(uuid),public.pasr_business_coupon_mine(),public.pasr_business_coupon_redeem(text) to authenticated;
grant execute on function public.pasr_business_program_public(uuid), public.pasr_business_coupon_list(uuid) to anon,authenticated;


-- Tussentijdse beloningen: vaste mijlpalen per kaart; slechts eenmaal per ronde.
create table if not exists public.pasr_business_reward_claims (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.pasr_business_members(id) on delete cascade,
  card_id uuid not null references public.pasr_business_cards(id) on delete cascade,
  cycle integer not null check(cycle >= 0),
  milestone integer not null check(milestone >= 2 and milestone <= 30),
  title text not null check(char_length(title) between 3 and 80),
  by_user uuid references auth.users(id),
  at timestamptz not null default now(),
  unique(member_id,cycle,milestone)
);
alter table public.pasr_business_reward_claims enable row level security;
revoke all on public.pasr_business_reward_claims from anon,authenticated;

-- Geeft de eigenaar/medewerker na een scan de beschikbare tussentijdse beloningen.
create or replace function public.pasr_business_reward_progress(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r record; cfg jsonb;
begin
  select * into r from public.pasr_business_scan_member(p_code);
  select coalesce(settings->'rewards','[]'::jsonb) into cfg
    from public.pasr_business_programs where card_id=(r.c).id;
  return coalesce((select jsonb_agg(jsonb_build_object(
     'stamps',(x.value->>'stamps')::int,'title',x.value->>'title',
     'available', (r.m).stamps_count >= (x.value->>'stamps')::int
       and not exists(select 1 from public.pasr_business_reward_claims v
           where v.member_id=(r.m).id and v.cycle=(r.m).rewards_redeemed
             and v.milestone=(x.value->>'stamps')::int))
      order by (x.value->>'stamps')::int)
    from jsonb_array_elements(coalesce(cfg,'[]'::jsonb)) x
    where (x.value->>'stamps')::int < (r.c).stamps_total),'[]'::jsonb);
end $$;

create or replace function public.pasr_business_reward_claim(p_code text,p_stamps integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r record; m public.pasr_business_members; reward_title text;
begin
  select * into r from public.pasr_business_scan_member(p_code);
  select * into m from public.pasr_business_members where id=(r.m).id for update;
  if p_stamps<2 or p_stamps>=(r.c).stamps_total then
    raise exception 'Deze mijlpaal bestaat niet.' using errcode='22023';
  end if;
  select e.value->>'title' into reward_title
    from public.pasr_business_programs p, lateral jsonb_array_elements(p.settings->'rewards') e
    where p.card_id=(r.c).id and (e.value->>'stamps')::int=p_stamps
    limit 1;
  if reward_title is null then raise exception 'Mijlpaal niet gevonden.' using errcode='P0002'; end if;
  if m.stamps_count<p_stamps then raise exception 'Nog niet genoeg stempels.' using errcode='22023'; end if;
  insert into public.pasr_business_reward_claims(member_id,card_id,cycle,milestone,title,by_user)
    values(m.id,(r.c).id,m.rewards_redeemed,p_stamps,reward_title,auth.uid())
    on conflict(member_id,cycle,milestone) do nothing;
  if not found then raise exception 'Deze beloning is al afgehaald.' using errcode='22023'; end if;
  return public.pasr_business_scan_json(m,r.c,r.b) ||
         jsonb_build_object('milestone_redeemed',p_stamps,'milestone_reward',reward_title);
end $$;

revoke all on function public.pasr_business_reward_progress(text),
  public.pasr_business_reward_claim(text,integer) from public;
grant execute on function public.pasr_business_reward_progress(text),
  public.pasr_business_reward_claim(text,integer) to authenticated;


-- Geaggregeerde zakelijke inzichten, uitsluitend voor de eigenaar. Geen namen, codes of persoonsgegevens.
create or replace function public.pasr_business_loyalty_insights(p_business uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare own public.pasr_businesses;
begin
  select * into own from public.pasr_businesses where id=p_business and owner=auth.uid();
  if own.id is null then raise exception 'Alleen de eigenaar ziet deze inzichten.' using errcode='42501'; end if;
  return jsonb_build_object(
    'members',(select count(*) from public.pasr_business_members m
       join public.pasr_business_cards c on c.id=m.business_card_id where c.business_id=p_business),
    'members_30d',(select count(*) from public.pasr_business_members m
       join public.pasr_business_cards c on c.id=m.business_card_id
       where c.business_id=p_business and m.created_at >= now()-interval '30 days'),
    'stamps_30d',(select coalesce(sum(e.amount),0) from public.pasr_business_events e
       where e.business_id=p_business and e.kind='stamp' and e.undone_at is null
         and e.at >= now()-interval '30 days'),
    'returning_customers_90d',(select count(*) from (
       select e.member_id from public.pasr_business_events e
       where e.business_id=p_business and e.kind='stamp' and e.undone_at is null
         and e.at >= now()-interval '90 days'
       group by e.member_id having count(*)>=2
    ) repeated),
    'milestone_rewards',(select count(*) from public.pasr_business_reward_claims rc
       join public.pasr_business_cards c on c.id=rc.card_id where c.business_id=p_business),
    'claimed_coupons',(select count(*) from public.pasr_business_coupon_claims cc
       join public.pasr_business_coupons c on c.id=cc.coupon_id where c.business_id=p_business),
    'redeemed_coupons',(select count(*) from public.pasr_business_coupon_claims cc
       join public.pasr_business_coupons c on c.id=cc.coupon_id
       where c.business_id=p_business and cc.redeemed_at is not null));
end $$;
revoke all on function public.pasr_business_loyalty_insights(uuid) from public;
grant execute on function public.pasr_business_loyalty_insights(uuid) to authenticated;


-- Referral wordt uitgegeven per bestaande, aan een echt Pasr-account gekoppelde kaart.
create table if not exists public.pasr_business_referral_invites(
  member_id uuid primary key references public.pasr_business_members(id) on delete cascade,
  token text not null unique check(token ~ '^PR[0-9A-F]{30}$'),
  created_at timestamptz not null default now()
);
alter table public.pasr_business_referral_invites enable row level security;
revoke all on public.pasr_business_referral_invites from anon,authenticated;

create table if not exists public.pasr_business_referrals(
  id uuid primary key default gen_random_uuid(),
  inviter_member_id uuid not null references public.pasr_business_members(id) on delete cascade,
  referred_member_id uuid not null unique references public.pasr_business_members(id) on delete cascade,
  business_card_id uuid not null references public.pasr_business_cards(id) on delete cascade,
  joined_at timestamptz not null default now(),
  rewarded_at timestamptz,
  constraint pasr_referrer_different check(inviter_member_id <> referred_member_id)
);
create index if not exists pasr_referrals_inviter_idx on public.pasr_business_referrals(inviter_member_id,joined_at);
alter table public.pasr_business_referrals enable row level security;
revoke all on public.pasr_business_referrals from anon,authenticated;

create or replace function public.pasr_business_referral_invite(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare m public.pasr_business_members; c public.pasr_business_cards; b public.pasr_businesses;
  cfg jsonb; existing text; token text;
begin
  if auth.uid() is null then raise exception 'Log in om vrienden uit te nodigen.' using errcode='28000'; end if;
  select * into m from public.pasr_business_members
    where member_code=upper(trim(p_code)) and user_id=auth.uid() for update;
  if m.id is null then raise exception 'Deze kaart hoort niet bij je account.' using errcode='42501'; end if;
  select * into c from public.pasr_business_cards where id=m.business_card_id and published;
  select * into b from public.pasr_businesses where id=c.business_id and status='approved';
  select settings->'referral' into cfg from public.pasr_business_programs where card_id=c.id;
  if c.id is null or b.id is null or coalesce((cfg->>'enabled')::boolean,false) is not true then
    raise exception 'Vrienden uitnodigen staat voor deze kaart niet aan.' using errcode='22023';
  end if;
  select i.token into existing from public.pasr_business_referral_invites i where i.member_id=m.id;
  if existing is null then
    token := 'PR'||upper(encode(gen_random_bytes(15),'hex'));
    insert into public.pasr_business_referral_invites(member_id,token)
       values(m.id,token) on conflict(member_id) do nothing;
    select i.token into existing from public.pasr_business_referral_invites i where i.member_id=m.id;
  end if;
  return jsonb_build_object('token',existing,'card_id',c.id,'name',c.name,
    'share_url','https://pasr.nl/zakelijk/kaart/'||c.id::text||'/?ref='||existing,
    'terms','Beide klanten ontvangen de bonus pas na de eerste gecontroleerde aankoop.');
end $$;

create or replace function public.pasr_business_referral_join(p_card uuid,p_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.pasr_business_cards; b public.pasr_businesses;
  inviter public.pasr_business_members; invited public.pasr_business_members;
  cfg jsonb; normalized text:=upper(trim(p_token));
begin
  if auth.uid() is null then raise exception 'Log in om de uitnodiging te accepteren.' using errcode='28000'; end if;
  select * into c from public.pasr_business_cards where id=p_card and published;
  select * into b from public.pasr_businesses where id=c.business_id and status='approved';
  select m.* into inviter from public.pasr_business_referral_invites i
    join public.pasr_business_members m on m.id=i.member_id
    where i.token=normalized and m.business_card_id=p_card;
  select settings->'referral' into cfg from public.pasr_business_programs where card_id=p_card;
  if c.id is null or b.id is null or inviter.id is null or
    coalesce((cfg->>'enabled')::boolean,false) is not true then
    raise exception 'Uitnodiging ongeldig of niet meer actief.' using errcode='22023';
  end if;
  if inviter.user_id is null or inviter.user_id=auth.uid() then
    raise exception 'Je kunt jezelf niet uitnodigen.' using errcode='22023';
  end if;
  if exists(select 1 from public.pasr_business_members where business_card_id=p_card and user_id=auth.uid()) then
    raise exception 'Je hebt al een kaart bij deze ondernemer.' using errcode='22023';
  end if;
  -- Maximaal 50 open uitnodigingen per lid; voorkomt grootschalig misbruik.
  if (select count(*) from public.pasr_business_referrals
      where inviter_member_id=inviter.id and rewarded_at is null)>=50 then
    raise exception 'Voor deze uitnodigingslink staan te veel aanvragen open.' using errcode='22023';
  end if;
  insert into public.pasr_business_members(business_card_id,member_code,user_id)
    values(c.id,public.pasr_business_new_code(),auth.uid()) returning * into invited;
  insert into public.pasr_business_referrals(inviter_member_id,referred_member_id,business_card_id)
    values(inviter.id,invited.id,c.id);
  insert into public.pasr_business_events(business_card_id,business_id,member_id,kind,amount,by_user)
    values(c.id,b.id,invited.id,'join',0,auth.uid());
  return public.pasr_business_member_json(invited,c,b)||
    jsonb_build_object('referral_pending',true,'referral_bonus_after_first_verified_purchase',true);
end $$;

-- Wordt alleen aangeroepen vanuit de vertrouwde scantransactie, niet rechtstreeks door klanten.
create or replace function public.pasr_business_referral_award_internal(
 p_member uuid,p_business uuid,p_card uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare rr public.pasr_business_referrals; cfg jsonb; bonus int; before_inv int; before_new int;
  after_inv int; after_new int; approved boolean;
begin
  select * into rr from public.pasr_business_referrals
    where referred_member_id=p_member and business_card_id=p_card and rewarded_at is null for update;
  if rr.id is null then return '{}'::jsonb; end if;
  select settings->'referral' into cfg from public.pasr_business_programs where card_id=p_card;
  if coalesce((cfg->>'enabled')::boolean,false) is not true then return '{}'::jsonb; end if;
  if public.pasr_business_role(p_business) is null then
    raise exception 'Geen recht om referralbonussen te verwerken.' using errcode='42501';
  end if;
  bonus:=least(3,greatest(1,coalesce((cfg->>'bonus')::int,1)));
  select stamps_count into before_inv from public.pasr_business_members where id=rr.inviter_member_id for update;
  select stamps_count into before_new from public.pasr_business_members where id=rr.referred_member_id for update;
  update public.pasr_business_members set stamps_count=least(stamps_count+bonus,1000),updated_at=now()
    where id=rr.inviter_member_id returning stamps_count into after_inv;
  update public.pasr_business_members set stamps_count=least(stamps_count+bonus,1000),updated_at=now()
    where id=rr.referred_member_id returning stamps_count into after_new;
  insert into public.pasr_business_events(business_card_id,business_id,member_id,kind,amount,by_user,stamps_before,stamps_after)
    values(p_card,p_business,rr.inviter_member_id,'stamp',after_inv-before_inv,auth.uid(),before_inv,after_inv),
          (p_card,p_business,rr.referred_member_id,'stamp',after_new-before_new,auth.uid(),before_new,after_new);
  update public.pasr_business_referrals set rewarded_at=now() where id=rr.id;
  return jsonb_build_object('referral_bonus',bonus,'rewarded',true);
end $$;
-- Deze helper mag alleen in de scancontext worden gebruikt, met personeel dat bij de zaak hoort.
revoke all on function public.pasr_business_referral_award_internal(uuid,uuid,uuid)
 from public,anon,authenticated;
grant execute on function public.pasr_business_referral_award_internal(uuid,uuid,uuid) to service_role;

revoke all on function public.pasr_business_referral_invite(text),
 public.pasr_business_referral_join(uuid,text) from public,anon;
grant execute on function public.pasr_business_referral_invite(text),
 public.pasr_business_referral_join(uuid,text) to authenticated;


-- Controleer een kortingsbon op de zakelijke scanner zonder hem voortijdig te verzilveren.
create or replace function public.pasr_business_coupon_check(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare claim public.pasr_business_coupon_claims; c public.pasr_business_coupons; b public.pasr_businesses;
begin
  if auth.uid() is null then raise exception 'Log eerst in bij Pasr Zakelijk.' using errcode='28000'; end if;
  select * into claim from public.pasr_business_coupon_claims where redeem_code=upper(trim(p_code));
  if claim.id is null then raise exception 'Onbekende kortingsbon.' using errcode='P0002'; end if;
  select * into c from public.pasr_business_coupons where id=claim.coupon_id;
  select * into b from public.pasr_businesses where id=c.business_id;
  if public.pasr_business_role(b.id) is null or b.status<>'approved' then
    raise exception 'Deze bon hoort niet bij jouw zaak.' using errcode='42501';
  end if;
  return jsonb_build_object('business',b.name,'title',c.title,'description',c.description,
    'discount_type',c.discount_type,'discount_value',c.discount_value,'min_spend',c.min_spend,
    'valid',claim.redeemed_at is null and c.public and now() between c.starts_at and c.ends_at,
    'used',claim.redeemed_at is not null,'ends_at',c.ends_at);
end $$;
revoke all on function public.pasr_business_coupon_check(text) from public,anon;
grant execute on function public.pasr_business_coupon_check(text) to authenticated;


-- Marketingkalender: echte geplande acties, niet alleen een tekstveld in de instellingen.
-- Alleen de eigenaar kan campagnes lezen of wijzigen; publicatie stuurt geen berichten zonder toestemming.
create table if not exists public.pasr_business_marketing_events(
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.pasr_businesses(id) on delete cascade,
  card_id uuid references public.pasr_business_cards(id) on delete set null,
  title text not null check(char_length(title) between 3 and 100),
  details text not null default '' check(char_length(details)<=600),
  channel text not null default 'social' check(channel in ('social','winkel','web','email')),
  starts_on date not null,
  ends_on date not null,
  status text not null default 'planned' check(status in ('draft','planned','completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(ends_on >= starts_on and ends_on <= starts_on + 366)
);
create index if not exists pasr_marketing_business_dates on public.pasr_business_marketing_events(business_id,starts_on);
alter table public.pasr_business_marketing_events enable row level security;
revoke all on public.pasr_business_marketing_events from public,anon,authenticated;

create or replace function public.pasr_business_marketing_list(p_business uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not exists(select 1 from public.pasr_businesses where id=p_business and owner=auth.uid()) then
    raise exception 'Alleen de eigenaar mag de marketingkalender zien.' using errcode='42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
     'id',e.id,'card_id',e.card_id,'card_name',c.name,'title',e.title,'details',e.details,
     'channel',e.channel,'starts_on',e.starts_on,'ends_on',e.ends_on,'status',e.status)
     order by e.starts_on,e.created_at)
    from public.pasr_business_marketing_events e
    left join public.pasr_business_cards c on c.id=e.card_id
    where e.business_id=p_business),'[]'::jsonb);
end $$;

create or replace function public.pasr_business_marketing_save(p_event jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare b uuid; cid uuid; eid uuid; t text; d text; ch text; st text; sd date; ed date;
begin
  if auth.uid() is null or jsonb_typeof(p_event)<>'object' or octet_length(p_event::text)>3000 then
    raise exception 'Ongeldige campagne.' using errcode='22023';
  end if;
  b:=(p_event->>'business_id')::uuid;
  if not exists(select 1 from public.pasr_businesses where id=b and owner=auth.uid() and status='approved') then
    raise exception 'Alleen een goedgekeurde eigenaar kan campagnes maken.' using errcode='42501';
  end if;
  cid:=nullif(p_event->>'card_id','')::uuid;
  if cid is not null and not exists(select 1 from public.pasr_business_cards where id=cid and business_id=b) then
    raise exception 'De geselecteerde kaart is niet van deze zaak.' using errcode='42501';
  end if;
  eid:=nullif(p_event->>'id','')::uuid;
  t:=trim(coalesce(p_event->>'title',''));
  d:=trim(coalesce(p_event->>'details',''));
  ch:=coalesce(p_event->>'channel','social');
  st:=coalesce(p_event->>'status','planned');
  sd:=(p_event->>'starts_on')::date;ed:=(p_event->>'ends_on')::date;
  if length(t) not between 3 and 100 or length(d)>600 or ch not in ('social','winkel','web','email')
     or st not in ('draft','planned','completed') or sd is null or ed is null
     or ed<sd or ed>sd+366 then
     raise exception 'Controleer de campagnevelden en datums.' using errcode='22023';
  end if;
  if eid is null then
    if (select count(*) from public.pasr_business_marketing_events where business_id=b)>=200 then
      raise exception 'Maximaal 200 geplande campagnes per zaak.' using errcode='22023';
    end if;
    insert into public.pasr_business_marketing_events(business_id,card_id,title,details,channel,starts_on,ends_on,status)
    values(b,cid,t,d,ch,sd,ed,st) returning id into eid;
  else
    update public.pasr_business_marketing_events
      set card_id=cid,title=t,details=d,channel=ch,starts_on=sd,ends_on=ed,status=st,updated_at=now()
      where id=eid and business_id=b returning id into eid;
    if eid is null then raise exception 'Campagne niet gevonden.' using errcode='P0002'; end if;
  end if;
  return jsonb_build_object('id',eid,'ok',true);
end $$;

create or replace function public.pasr_business_marketing_delete(p_event uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare removed uuid;
begin
  delete from public.pasr_business_marketing_events e
   where e.id=p_event and exists(select 1 from public.pasr_businesses b where b.id=e.business_id and b.owner=auth.uid())
  returning e.id into removed;
  return removed is not null;
end $$;

revoke all on function public.pasr_business_marketing_list(uuid),
 public.pasr_business_marketing_save(jsonb),public.pasr_business_marketing_delete(uuid)
 from public,anon;
grant execute on function public.pasr_business_marketing_list(uuid),
 public.pasr_business_marketing_save(jsonb),public.pasr_business_marketing_delete(uuid)
 to authenticated;


-- VIP niveau per kaart (optioneel door ondernemer). Toont uitsluitend status, geen persoonsgegevens.
create or replace function public.pasr_business_vip_status(p_code text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare m public.pasr_business_members; c public.pasr_business_cards; b public.pasr_businesses;
  cfg jsonb; visits int; silver int; gold int; tier text; next_at int;
begin
  select * into m from public.pasr_business_members
    where member_code=upper(trim(coalesce(p_code,'')));
  if m.id is null then return jsonb_build_object('enabled',false); end if;
  select * into c from public.pasr_business_cards where id=m.business_card_id and published;
  select * into b from public.pasr_businesses where id=c.business_id and status='approved';
  if c.id is null or b.id is null then return jsonb_build_object('enabled',false); end if;
  select settings->'vip' into cfg from public.pasr_business_programs where card_id=c.id;
  if coalesce((cfg->>'enabled')::boolean,false) is not true then
    return jsonb_build_object('enabled',false);
  end if;
  silver:=greatest(1,least(1000,coalesce((cfg->>'silver')::int,10)));
  gold:=greatest(silver+1,least(2000,coalesce((cfg->>'gold')::int,25)));
  select count(*) into visits from public.pasr_business_events e
    where e.member_id=m.id and e.kind='stamp' and e.amount>0 and e.undone_at is null;
  tier:=case when visits>=gold then 'Goud' when visits>=silver then 'Zilver' else 'Brons' end;
  next_at:=case when visits<silver then silver when visits<gold then gold else null end;
  return jsonb_build_object('enabled',true,'tier',tier,'visits',visits,
    'silver_from',silver,'gold_from',gold,'next_at',next_at);
end $$;
revoke all on function public.pasr_business_vip_status(text) from public;
grant execute on function public.pasr_business_vip_status(text) to anon,authenticated;


-- Meerdere vestigingen: echte filiaalrecords. Een stempel kan aan precies één vestiging
-- worden toegeschreven. Bestaande scans zonder locatie blijven gewoon werken.
create table if not exists public.pasr_business_locations(
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.pasr_businesses(id) on delete cascade,
  name text not null check(char_length(name) between 2 and 100),
  address text not null default '' check(char_length(address)<=200),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists pasr_business_locations_business on public.pasr_business_locations(business_id,name);
alter table public.pasr_business_locations enable row level security;
revoke all on public.pasr_business_locations from public,anon,authenticated;
alter table public.pasr_business_events
  add column if not exists location_id uuid references public.pasr_business_locations(id) on delete set null;

create or replace function public.pasr_business_locations_list(p_business uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if public.pasr_business_role(p_business) is null then
    raise exception 'Je hoort niet bij deze onderneming.' using errcode='42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'name',l.name,
    'address',l.address,'active',l.active) order by l.name)
    from public.pasr_business_locations l where l.business_id=p_business),'[]'::jsonb);
end $$;

create or replace function public.pasr_business_location_save(
 p_business uuid,p_name text,p_address text default '',p_id uuid default null,p_active boolean default true)
returns jsonb language plpgsql security definer set search_path=public as $$
declare loc public.pasr_business_locations; clean_name text:=trim(p_name);
begin
  if not exists(select 1 from public.pasr_businesses where id=p_business and owner=auth.uid() and status='approved') then
    raise exception 'Alleen de eigenaar kan vestigingen beheren.' using errcode='42501';
  end if;
  if char_length(clean_name) not between 2 and 100 or length(coalesce(p_address,''))>200 then
    raise exception 'Controleer de vestigingsnaam en het adres.' using errcode='22023';
  end if;
  if p_id is null then
    if (select count(*) from public.pasr_business_locations where business_id=p_business)>=30 then
      raise exception 'Maximaal 30 vestigingen per zaak.' using errcode='22023';
    end if;
    insert into public.pasr_business_locations(business_id,name,address,active)
      values(p_business,clean_name,trim(coalesce(p_address,'')),coalesce(p_active,true)) returning * into loc;
  else
    update public.pasr_business_locations set name=clean_name,address=trim(coalesce(p_address,'')),
      active=coalesce(p_active,true) where id=p_id and business_id=p_business returning * into loc;
    if loc.id is null then raise exception 'Vestiging niet gevonden.' using errcode='P0002'; end if;
  end if;
  return jsonb_build_object('id',loc.id,'name',loc.name,'active',loc.active);
end $$;

create or replace function public.pasr_business_stamp_location(
 p_code text,p_amount int default 1,p_device text default null,p_location uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r record; loc public.pasr_business_locations; result jsonb; eventid uuid;
begin
  select * into r from public.pasr_business_scan_member(p_code);
  if p_location is not null then
    select * into loc from public.pasr_business_locations
      where id=p_location and business_id=(r.b).id and active;
    if loc.id is null then raise exception 'Onbekend of niet actief filiaal.' using errcode='22023'; end if;
  end if;
  result:=public.pasr_business_stamp(p_code,p_amount,p_device);
  eventid:=nullif(result->>'event_id','')::uuid;
  if eventid is not null and p_location is not null then
    update public.pasr_business_events
       set location_id=p_location
       where event_id=eventid and business_id=(r.b).id;
  end if;
  return result || jsonb_build_object('location_id',p_location,'location_name',loc.name);
end $$;

create or replace function public.pasr_business_location_insights(p_business uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not exists(select 1 from public.pasr_businesses where id=p_business and owner=auth.uid()) then
    raise exception 'Alleen de eigenaar kan filiaalinzichten zien.' using errcode='42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'name',l.name,
    'stamps_30d',coalesce((select sum(e.amount) from public.pasr_business_events e
      where e.location_id=l.id and e.kind='stamp' and e.undone_at is null
      and e.at>=now()-interval '30 days'),0))
    order by l.name) from public.pasr_business_locations l where l.business_id=p_business),'[]'::jsonb);
end $$;

revoke all on function public.pasr_business_locations_list(uuid),
 public.pasr_business_location_save(uuid,text,text,uuid,boolean),
 public.pasr_business_stamp_location(text,integer,text,uuid),
 public.pasr_business_location_insights(uuid) from public,anon;
grant execute on function public.pasr_business_locations_list(uuid),
 public.pasr_business_location_save(uuid,text,text,uuid,boolean),
 public.pasr_business_stamp_location(text,integer,text,uuid),
 public.pasr_business_location_insights(uuid) to authenticated;

-- Pasr Zakelijk: herbruikbare eigen actiecodes, gescheiden van persoonlijke PC-couponcodes.
-- Publiek kan geen codes of statistieken uitlezen; alleen eigenaar beheert, eigenaar/medewerker verzilvert.
create table if not exists public.pasr_business_promo_codes (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.pasr_businesses(id) on delete cascade,
 code text not null unique check (code ~ '^[A-Z0-9][A-Z0-9-]{3,23}$' and code !~ '^PC[A-HJ-NP-Z2-9]{22}$'),
 title text not null check (char_length(title) between 3 and 80),
 discount_type text not null check (discount_type in ('amount','percent')),
 discount_value numeric(10,2) not null check (discount_value > 0 and discount_value <= 100000),
 min_spend numeric(10,2) not null default 0 check(min_spend >= 0),
 starts_at timestamptz not null default now(),
 ends_at timestamptz not null,
 max_uses integer not null default 100 check (max_uses between 1 and 100000),
 used_count integer not null default 0 check (used_count >= 0),
 active boolean not null default false,
 created_at timestamptz not null default now(),
 constraint pasr_promo_window check (ends_at > starts_at and ends_at <= starts_at + interval '366 days'),
 constraint pasr_promo_discount check (discount_type <> 'percent' or discount_value <= 100),
 constraint pasr_promo_capacity check (used_count <= max_uses)
);
create index if not exists pasr_promo_business_idx on public.pasr_business_promo_codes(business_id,created_at desc);
alter table public.pasr_business_promo_codes enable row level security;
revoke all on public.pasr_business_promo_codes from public,anon,authenticated;

create or replace function public.pasr_business_promo_list(p_business uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not exists(select 1 from public.pasr_businesses biz where biz.id=p_business and biz.owner=auth.uid()) then
   raise exception 'Alleen de eigenaar kan actiecodes beheren.' using errcode='42501';
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
   'id',pr.id,'code',pr.code,'title',pr.title,'discount_type',pr.discount_type,
   'discount_value',pr.discount_value,'min_spend',pr.min_spend,
   'starts_at',pr.starts_at,'ends_at',pr.ends_at,'max_uses',pr.max_uses,
   'used_count',pr.used_count,'active',pr.active) order by pr.created_at desc)
   from public.pasr_business_promo_codes pr where pr.business_id=p_business),'[]'::jsonb);
end $$;

create or replace function public.pasr_business_promo_save(p_promo jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare biz public.pasr_businesses; existing public.pasr_business_promo_codes;
 v_id uuid; v_code text; v_title text; v_type text; v_value numeric; v_min numeric;
 v_start timestamptz; v_end timestamptz; v_limit integer; v_active boolean;
begin
 if auth.uid() is null or jsonb_typeof(p_promo)<>'object' or octet_length(p_promo::text)>4000 then
   raise exception 'Ongeldige actiecode.' using errcode='22023';
 end if;
 select * into biz from public.pasr_businesses
 where id=(p_promo->>'business_id')::uuid and owner=auth.uid();
 if biz.id is null or biz.status<>'approved' then
   raise exception 'Alleen de eigenaar van een goedgekeurde zaak kan actiecodes aanmaken.' using errcode='42501';
 end if;
 v_id:=nullif(p_promo->>'id','')::uuid;
 v_code:=upper(trim(coalesce(p_promo->>'code','')));
 v_title:=trim(coalesce(p_promo->>'title',''));
 v_type:=p_promo->>'discount_type';
 v_value:=(p_promo->>'discount_value')::numeric;
 v_min:=coalesce((p_promo->>'min_spend')::numeric,0);
 v_start:=coalesce((p_promo->>'starts_at')::timestamptz,now());
 v_end:=(p_promo->>'ends_at')::timestamptz;
 v_limit:=coalesce((p_promo->>'max_uses')::int,100);
 v_active:=coalesce((p_promo->>'active')::boolean,false);
 if v_code !~ '^[A-Z0-9][A-Z0-9-]{3,23}$' or v_code ~ '^PC[A-HJ-NP-Z2-9]{22}$'
   or char_length(v_title) not between 3 and 80 or v_type not in ('amount','percent')
   or v_value<=0 or v_value>case when v_type='percent' then 100 else 100000 end
   or v_min<0 or v_limit not between 1 and 100000 or v_end is null
   or v_end<=v_start or v_end>v_start+interval '366 days' then
   raise exception 'Controleer code (4–24 tekens), titel, bedrag, geldigheid en maximaal gebruik.' using errcode='22023';
 end if;
 if v_id is null then
   insert into public.pasr_business_promo_codes(business_id,code,title,discount_type,discount_value,
       min_spend,starts_at,ends_at,max_uses,active)
   values(biz.id,v_code,v_title,v_type,v_value,v_min,v_start,v_end,v_limit,v_active)
   returning * into existing;
 else
   update public.pasr_business_promo_codes set code=v_code,title=v_title,discount_type=v_type,
     discount_value=v_value,min_spend=v_min,starts_at=v_start,ends_at=v_end,max_uses=v_limit,active=v_active
   where id=v_id and business_id=biz.id and used_count<=v_limit
   returning * into existing;
   if existing.id is null then raise exception 'Actiecode niet gevonden of limiet is te laag.' using errcode='P0002'; end if;
 end if;
 return jsonb_build_object('id',existing.id,'code',existing.code,'ok',true);
exception when unique_violation then
 raise exception 'Deze actiecode bestaat al. Kies een andere code.' using errcode='23505';
end $$;

create or replace function public.pasr_business_promo_check(p_code text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare p public.pasr_business_promo_codes; biz public.pasr_businesses;
begin
 if auth.uid() is null then raise exception 'Log in als ondernemer.' using errcode='28000'; end if;
 select * into p from public.pasr_business_promo_codes where code=upper(trim(p_code));
 if p.id is null then return jsonb_build_object('valid',false); end if;
 select * into biz from public.pasr_businesses where id=p.business_id;
 if biz.owner is distinct from auth.uid() and public.pasr_business_role(biz.id) is null then
   raise exception 'Actiecode hoort niet bij jouw zaak.' using errcode='42501';
 end if;
 return jsonb_build_object('valid',p.active and biz.status='approved' and now() between p.starts_at and p.ends_at and p.used_count<p.max_uses,
   'title',p.title,'discount_type',p.discount_type,'discount_value',p.discount_value,
   'min_spend',p.min_spend,'remaining',p.max_uses-p.used_count,'business',biz.name);
end $$;

create or replace function public.pasr_business_promo_redeem(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare p public.pasr_business_promo_codes; biz public.pasr_businesses;
begin
 if auth.uid() is null then raise exception 'Log in als ondernemer.' using errcode='28000'; end if;
 select * into p from public.pasr_business_promo_codes where code=upper(trim(p_code)) for update;
 if p.id is null then raise exception 'Onbekende actiecode.' using errcode='P0002'; end if;
 select * into biz from public.pasr_businesses where id=p.business_id;
 if biz.owner is distinct from auth.uid() and public.pasr_business_role(biz.id) is null then
   raise exception 'Actiecode hoort niet bij jouw zaak.' using errcode='42501';
 end if;
 if not p.active or biz.status<>'approved' or now() not between p.starts_at and p.ends_at or p.used_count>=p.max_uses then
   raise exception 'Deze actiecode is niet (meer) geldig.' using errcode='22023';
 end if;
 update public.pasr_business_promo_codes set used_count=used_count+1 where id=p.id;
 return jsonb_build_object('ok',true,'title',p.title,'code',p.code,'discount_type',p.discount_type,
   'discount_value',p.discount_value,'min_spend',p.min_spend,'remaining',p.max_uses-p.used_count-1);
end $$;

revoke all on function public.pasr_business_promo_list(uuid),
 public.pasr_business_promo_save(jsonb),public.pasr_business_promo_check(text),
 public.pasr_business_promo_redeem(text) from public;
grant execute on function public.pasr_business_promo_list(uuid),public.pasr_business_promo_save(jsonb),
 public.pasr_business_promo_check(text),public.pasr_business_promo_redeem(text) to authenticated;
