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
