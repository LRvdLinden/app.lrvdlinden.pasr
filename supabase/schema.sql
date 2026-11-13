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
           'updated_at', s.updated_at)
         else jsonb_build_object('id', s.id, 'removed', true, 'updated_at', s.updated_at) end), '[]'::jsonb))
  from public.pasr_stores s
  where (p_since is null and s.published) or (p_since is not null and s.updated_at > p_since);
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

-- Winkels die via deze repo zijn toegevoegd (zonder app-update). Alleen nieuw invoegen: wijzigingen in het beheer blijven staan.
insert into public.pasr_stores (id, name, domain, category, card_hex, format, kind, aliases, logo, published, published_at)
values ('bakkerscadeau', 'Bakkers Cadeau', 'bakkerscadeaukaart.nl', 'Cadeaukaarten', '#B5814A', 'code128', 'voucher',
        array['bakkers cadeau', 'bakkerscadeau', 'bakkerscadeaukaart', 'bakkers cadeaukaart'],
        'iVBORw0KGgoAAAANSUhEUgAAAHgAAABOCAYAAADrR9JiAAAPiklEQVR4AezcjXnkRBIG4PYlcBDBQQRABAcRABEAEbBE4CUCIAIgAiACuAiACOAigIvA973tKa0ka+xZjwy2Vvuopn+qurq6vq7+kfzsP9r+b9Me2AHeNLyt7QDvAG/cAxsf3h7BO8Ab98DGh7dH8A7wxj2w8eG9qhG8cVhfDG8H+IUvNpnbAX4gWK+urt4OvfFA6k9WuwN8sqtOFwywH0T659BvyaOPkz4L/Rj6IvSXAb8DHBTu+wAqBLCfkw5P9P079FPIA8yvk/lX6N3Qs1CBDnj0Wuoe5NkBPsOtFxcXv6c50N5OOn6A+GcqUJL+fJxf8kn6A/T3k5MC/Hnyqz87wOe79L2o+Dz0SwiACLAit6I4rCZK8dron4lBFu8yS8AXI94q2R3gM92YKP4z9Dz0TlR9GwIswIBnL05VA+I3rTUAf99aU275R1Zdsv2xT6vrhTV+doDX8OILHaK4wKtaUQxESzQCujLART5+yUrxpavQDOBVdL6yShLF34dejwMs2+jN5D2iWVokSkW5wxieqC6eusqfnT5JgLNXvRZy+nyetIjTjjokch+ESlbqcHRU/hxGQP7pQL8nBfQn0QdEUSvKgStS2YDkK6oBHvF1ntUAjvNc7N9NukjrmDto4YSPUrocEaelePOJTXifhoOqDR2pevgnIH8T+jAE6B9mPVrSAf/egf9t7F3tsLUawDGaUT8mXaQY7VnlOhBHiBCR8WX68zjoiAz5GxR5fPIcXPz53lf1D5rGFtehYRlP+fXQJyER3JLi/xpn8ePZtqwGcAzjQFRGASHVFxepsBcBwDLqOmAQqT77qSg8FaySBzh7zjbgPgouLi70zz+Ldocvon8JyO7I9+liaLMawAeNlptDtv2nMjHY7PysyknXOkgUYENf0X3b89aBuejYA+9RJPEZf/Xt7hyD1gbYgaHsedAIyewGrr1Vf6f2Vfb9qtETINcoZ4Z7m7o2wBUhDJpHCUDUo8WIC2hvhFz2nXKllvSWOvU9r/GBCqyW2T7pK/IOfNrXBKBD/1Wey9NPft5H7yr6RBKbkNN76Sm+/sjoo+roJE/vXB6PHnzkhD+RoSTjslTTvWgXmbtobYDL6a4Hw3IdBzG+ZqJoq8NRtw8/9F0Kv4WcdP+Z1HtahzJ1qHSH1Z+aTHOw7Fu+5Dj0yXfh/AzOj+OGNun349Ya/eS1i+j1Ex7Q8Bx49OeDAZ3sAhLC146Mjw7aeKGh3pjp1aYrjU7nDzzjVCc1dm35Sd2YXK/mYx/zb82vBnAMN8uQDrsDU9fvq6ngAMabka4Dc/A5x13QdeLNAPBZyIHN4CY6o6ueGnRfDQ596YdzS2boJxW173fbUhbVHI8U0SAfffSwi93vxJ665pig6vC1cTL/UOZA9AGN/aWPvP6MEeheiNAJbD7R1DiHSajiQP9Nipfk5Z/VAE7XY+MsP1ep+yNkwAYINNeBGnRY/eFEbX+JEzmrVx5+aq+0Ijio9eo434CR8k8p00+PMsdyOF0OKurQfEKwi8PJakNWCgi6RZ52bAaqPNKX1NbALhMG9br8GB890pIt2wEfkeadtRTZZ01kk3usBw8t1ak/idYEuCJEx5zrauQFvLy6+m4KTGWOFAVV5uBeP/opnWMHY1cbec4DrtTq4PohQjiMk/XD0UAjb0IAlw7yZLX5MhOMDjKiTBuTjvPV0WNCDHp65fUPXde51kS6axCbjQmA0uJLLzMpu570SVab8hP+mNgxLr9Ufk2Aa5AM5lyzm4MsQaKEYWQ4Vx7VjCa3NFMnUafBgQp4gNi/6P2Bsw78eVJ61OvTxNInENQNFMdzKL66IdJS/ywVZbuoHttb+o2dTRFtLfaYNL409YnWWisee+3jX0dvtW1H/pGt9kdEjlevCXAZOh547zkDHdcxuNfnp/JjfqqbaCl9ynN+8URB6fDqkuwS1YTAE4U9jXOBKT+m0qfurcj4MxtbzWUqRLMzgkmb4vCU/rmdg8AhI5LHMiYS/TVxDmKTxOFu3GbCvKuwCsBxQjlcf7Vvyh+lWZv/LQiWo0XFPNKKx9G1tDm9AnxBVSt5emwbLf+AW2CnODxjHQ44othSPnmlOEhfZ2r8/cB3XXXzNxPdWOzPbHCTqMh0ZgH2pFF8xEYrAbsnvFMLqwCczmqAybYbsy2Gjo2vZard8a+iYjK46Br39XmcBuRylOV3SW21+Sry9IlEckvy3amYIXuz7UabFK+f2DBMguRr8mBO5FQsERtCohnYZfugc9TGBPxqVH7p7FoAW0Z65zF8AnAcwGGWt87PTzd4JufeG9b1kzacVqDMo6LqRUNNFiBrLBL0J98pukpeuQAQlcpeIoz56kpGfs6zdTwLw3UsSX8GmdmYOtNPbHBfTnL1x9XV1QBk5PWFiNVY5IuMceLPYpya3g7wCVpiMDDMtC59KFfe4J1wa1AOHZamzs9PGQ8Yshwo2h2cCij7oOVXP2nSKrKrrbo+aZLRxp7GocDTb9cbHmd1Z8axIrgc+l1spr+3CY/e4n0aXh9bUnx2max1aIzaVpNbO+UlYod69g2rRnQaE/tEMZvIDBRbbtQNzBMz9wY4xnm95vAxns269UYm7KurFIBrEAy1j1mWUj08ygZn4IDRphzYwYgkB9NThyj6Ut2GvT6OAEhNHHxvirShtwAofdoifUvJkNVGW3UALLtMAHYV3zjGYAJIm7l+dUV41carS6dnByv9sp1O/ZX8aum9AY4FjOYI+8gx8rYm/r9wz6sBpun1c3FxQYf7Mme7LzowaaN+rNMBh4yG1WcBqq5FF/7QJmVt6KFXPd1d1k/4Jp3DDh4i35f68LRjlzbaI2NwgsajooiM9rWKVP2QRp/Vg4z+2Onwho7pHNqem7k3wDHaPdch5DaaO+OGvdFj8JZu90UHmj6TD/Wlu9dpnPobderRiDdMptS572ojUogNNOLhD30QCI9d7GEXMiGwJhQ5bdGgP8vX8xHVqmASsqXGSudg50TpioV7A7yiDVtUBWxbiu3GFvC3jXEH+AFcn6i21ANZ1D54lN42hB3g27xzHs/S/LeCy/wdYF4IZc90Vaq9s07G4TRXN1ek4rk9kJ3LqCsZd2VL8+QOnz60LZm6Ot3Zx6jd0CZ1PsXSZyJ1HUs/fwnAMcbgEYNqgOPUVcQ1CfnqNObJ93syPUuDOLcuel1Z3HEtq/9srbGjOy4893JXJN04NF4m43rT+cm3yIzb00EGizw+MFwn1atzdVMmg+/T5LgPZX2YWPrXDqnvbfKjns0mUorLz2oAZ5AABARAAAYojjJ4sx05qVq2OmWvcpJErgvugsg1whWoy8RsqZmrvRcP7tneCNGtD5Pm1kFGx9EndvvozllssHeWLqC4g7PfK1F2OknX3zWzq8AZ2mdMdHReOq0UEMZgfHSYBL2f9C/ake/l1QeZNG9O5/S5YrX8478k/ekvfNJf9dEr5z/3AjhGeUtUF3ZONrPMaIa7WnAWgw3IpzWGIwYPNDemyjHaFWWQS1lbRK97sr8rdjd1l/wo7Xx6M6k4OsWXerxZcn0pR3mNyakizbg41YQrpeVYf9YKJOCM25PjC3V/8lUqTE5+UZZnZ/UnMl05x32Q4QP+TPNGX8u/4eVO8mTYmOzx5ySAGRkCKDLjdehDOfAAidzvgFJGHe91BU5A15c+gQ5wwLwfO4HNgXf2ElnjAFI5u596o9vLCxGH9APk0sexJS+vvqJaRGuDyvlWATKCwrJs0lgR3kv/2k/6T50yu6oPbclJe11k6CfXyxjH6CjAUWLpA6gZ+loGzZlIJJmNfwmQxwyf18c+E85bLvRR7LeEc8RcdFzmJOWlz5XFG6ImOjmefB2eqqyuqOpKpur9QYLVB42jFd9KJEVL7a0aIromTQE+6SP22SaLR9f0PyONgE3dHioCLDEARXfOlK7tEfwEaHbbs0SV/boctmRdTVLLfOfHByLNgaei1oGo8/JjOU/Syh/l8P41LG1NitJVutvhH17PRs5Zxd7ey/nx15pJ+lN9lG6VQOvltKXHX5yqr7oKRH3aOpTJXQOcRoAF6htx0KOMUKN5Gco4RAmgRbKx3WgeGQ6x3xo/OU53ILLlcB4grWQ+Dlhea7LUuQPfROBQS28/+R46ImM7o5/MZfxMD/1A1If2+umAh29i1aqjPZ3UsVN00o9KxrlD2aQWiPZyfemzj7mWaOFv2dUhhZugAMh5QOas2gsnY4uM/RZZ7izHDoZ1irXcO9VbQuXpUvZhwT7KmT4gOPBZ5ktGGXWnp8OSoaeWam3DaqUTTx4NfRAIqaPPqiSPlNnA3gluGRPdxn4dwYeK6Nnek7EZKIcAuSJwMtDImNxWrgKk81Nv4qvD69GROmXynNhSVo+P5LWRdyZYkhFdXb+ftCdPpzbVXnmpD/XkEfmaiFTN6cUSPeccKz/V+jgRyGa8JfipDuNku7PUW8JfHYB5JiCLnN8zePuiqk1SxgfYy8N4r5foTY50eVD2Wm/DzPBliSdcG3Cdtq1S9vA+kjpk9cLWfzKr7YkOSN4eTYYb57geOakONBF4xIWD7YB9N2P04sc4u8WvFMB9xK05mNTVx9Uo/rlyPXElAfxAYQz8Q95BzZVIpLS/81/s8a7c9YrdDo+uXTe2n1cG4DiEM9wZUc1wTsmkv/C3Vq4bS3SRf/4+yyHNNarvcdHnlagXKe6iz1MW+Q+29Ee/u7qJaZKJVhPR/dcYhhP3fNJtHuA4xtLrJYU3TP7w3XtrYLniOF3PfbJYDsjeSXOk64mJAHTXL0u+CePtkhcZvnQBXvQrA7+oR39sMhmWCL9kAVk6TMr+4iLGufvWN4A77d80wHEkp3DOtwEIKJbn+KhxzNnRFp3uo4B3PxVJ+vDXmV5sOND5AOIlRJGJYHlfIsssu0rWZKQPmFITa7hbtxP/bRbggAtA+xPneG05uCTAcCSHDnW3Ze7DSx9eWgB/TLUCAGtOJslY1uvJ+3Q9abNZgDNKe5QoAGaKNx576Y3KrVVsGWDvnieRW+Alui2RlsKq2my6ZYB9w7bnLYEH4GORvST/ZOu2DLA/j7EPT8BJ9Fqafa5z+p3wtljYMsBOzA5ZA24BF+BO1Q47qxxiBuWPNLNlgL2P9bbHCwl3Sh/avbHyPRbvkUKyrlmbBTjXFHdULyJ8hPcx35Lsjnrjdd66Ln1c2jYLcLk5QHud5wWBO+axQ1eJby49B+DNOWOLA9oB3iKqozHtAI+cscXsDvAWUR2NaQd45IwtZneAt4jqaEw7wCNnbDG7A7xFVEdj2gEeOePE7JMS2wF+UnC9vLH/BwAA//9MwHcJAAAABklEQVQDAG5PygbOK7tSAAAAAElFTkSuQmCC', true, now())
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
  where id = 'rossmann' and logo is distinct from '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';
update public.pasr_stores set updated_at = now() where id = 'dm' and updated_at < '2026-11-13 07:00:00+00';

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
