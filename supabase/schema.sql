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
