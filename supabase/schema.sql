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
  if col not in ('signups', 'confirmed', 'deleted', 'expired', 'wallet', 'bots') then return; end if;
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
        'bots', coalesce(x.bots, 0), 'accounts', greatest(t.accounts, 0), 'cards', x.cards_total) order by d.day), '[]'::jsonb)
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
    'push_devices', (select count(*) from public.admin_push_devices)
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
           (select max(c.server_at) from public.pasr_cards c where c.user_id = u.id) as synced_at
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
