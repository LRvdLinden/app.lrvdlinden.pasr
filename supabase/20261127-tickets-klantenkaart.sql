-- Pasr: gratis tickets voor events en de eigen klantenkaart met barcode (27-11-2026).
-- Contract met de apps (Pasr, Pasr Zakelijk, dashboard, beheer): docs/tickets-klantenkaart.md. Namen, parameters en
-- velden van de RPC's staan daar vast; hier komt alleen iets bij. Idempotent: "if not exists" / "create or replace".
--
-- Privacy: voornaam, achternaam, e-mail en geboortedatum van wie zich aanmeldt staan alleen in pasr_tk_registrations
-- (dicht voor anon en authenticated) en zijn alleen te zien voor de eigenaar van de zaak die het event organiseert.
-- De QR-code van een ticket is een willekeurige code (24 tekens base32), nooit een naam of geboortedatum. 30 dagen na
-- het event worden de persoonsgegevens gewist (pasr_tk_cron).
--
-- Meldingen: elke gebeurtenis komt in pasr_tk_outbox. De functie event-mail mailt (Pasr-huisstijl), de functie admin
-- pusht (notify kind "tickets") naar de Pasr-app van de klant (APNs en FCM). Vangnet en herinneringen: pg_cron.
-- Foutcodes (exception message = code, ook in hint): not_owner, event_not_found, event_full, signup_closed, too_many,
-- invalid_input, event_cancelled, card_not_found, already_member, invalid_code, not_signed_in, not_enough,
-- barcode_type_locked, business_not_approved.

-- ============================================================================================================ tabellen
create table if not exists public.pasr_tk_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.pasr_businesses(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 80),
  description text not null default '' check (char_length(description) <= 2000),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  doors_at timestamptz,
  address text not null default '' check (char_length(address) <= 200),
  lat double precision check (lat is null or lat between -90 and 90),
  lng double precision check (lng is null or lng between -180 and 180),
  capacity integer not null check (capacity between 1 and 100000),
  max_per_person integer not null default 4 check (max_per_person between 1 and 20),
  signup_until timestamptz,
  waitlist boolean not null default true,
  reminder boolean not null default true,
  color text not null default '#6A5CFF' check (color ~ '^#[0-9A-F]{6}$'),
  header_url text check (header_url is null or (char_length(header_url) <= 500 and header_url ~ '^https://')),
  status text not null default 'draft' check (status in ('draft', 'published', 'cancelled')),
  cancel_message text check (cancel_message is null or char_length(cancel_message) <= 500),
  cancelled_at timestamptz,
  reminder_sent_at timestamptz,
  purged_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (doors_at is null or doors_at <= starts_at)
);
create index if not exists pasr_tk_events_business on public.pasr_tk_events(business_id, starts_at);
create index if not exists pasr_tk_events_open on public.pasr_tk_events(starts_at) where status = 'published';

create table if not exists public.pasr_tk_ticket_types (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.pasr_tk_events(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  capacity integer check (capacity is null or capacity between 1 and 100000),
  position integer not null default 0,
  archived boolean not null default false
);
create index if not exists pasr_tk_ticket_types_event on public.pasr_tk_ticket_types(event_id, position);

-- Persoonsgegevens: alleen hier, alleen voor de eigenaar van de zaak. Na het event gewist (purged_at op het event).
create table if not exists public.pasr_tk_registrations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.pasr_tk_events(id) on delete cascade,
  ticket_type_id uuid references public.pasr_tk_ticket_types(id) on delete set null,
  first_name text check (first_name is null or char_length(first_name) between 1 and 60),
  last_name text check (last_name is null or char_length(last_name) between 1 and 60),
  email text check (email is null or (char_length(email) between 3 and 200 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  birth_date date,
  ticket_count integer not null check (ticket_count between 1 and 20),
  user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists pasr_tk_registrations_event on public.pasr_tk_registrations(event_id, created_at);
create index if not exists pasr_tk_registrations_email on public.pasr_tk_registrations(event_id, email);

create table if not exists public.pasr_tk_tickets (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null references public.pasr_tk_registrations(id) on delete cascade,
  event_id uuid not null references public.pasr_tk_events(id) on delete cascade,
  ticket_type_id uuid references public.pasr_tk_ticket_types(id) on delete set null,
  code text not null unique check (code ~ '^[A-Z2-7]{20,40}$'),
  user_id uuid references auth.users(id) on delete set null,
  status text not null check (status in ('registered', 'checked_in', 'waitlist', 'cancelled')),
  checked_in_at timestamptz,
  checked_in_by uuid references auth.users(id) on delete set null,
  cancelled_at timestamptz,
  promoted_at timestamptz,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists pasr_tk_tickets_event on public.pasr_tk_tickets(event_id, status);
create index if not exists pasr_tk_tickets_user on public.pasr_tk_tickets(user_id) where user_id is not null;
create index if not exists pasr_tk_tickets_registration on public.pasr_tk_tickets(registration_id);

-- ---- klantenkaart met barcode ----
create table if not exists public.pasr_mc_cards (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.pasr_businesses(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  color text not null default '#6A5CFF' check (color ~ '^#[0-9A-F]{6}$'),
  logo text check (logo is null or (octet_length(logo) <= 210000 and logo ~ '^(/9j/|iVBORw0KGgo)[A-Za-z0-9+/]+=*$')),
  barcode_type text not null default 'qr' check (barcode_type in ('qr', 'code128', 'ean13')),
  prefix text not null default '' check (prefix ~ '^[A-Z0-9-]{0,8}$'),
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  goals jsonb not null default '{}'::jsonb,
  next_seq bigint not null default 1,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);
create index if not exists pasr_mc_cards_business on public.pasr_mc_cards(business_id);

create table if not exists public.pasr_mc_periods (
  id uuid primary key default gen_random_uuid(),
  card_id uuid not null references public.pasr_mc_cards(id) on delete cascade,
  label text not null default '' check (char_length(label) <= 40),
  percent numeric(5,2) not null check (percent > 0 and percent <= 100),
  starts_on date not null,
  ends_on date not null,
  weekdays integer[] check (weekdays is null or (weekdays <@ array[1,2,3,4,5,6,7] and cardinality(weekdays) between 1 and 7)),
  from_time time,
  to_time time,
  check (ends_on >= starts_on),
  check (from_time is null or to_time is null or to_time > from_time)
);
create index if not exists pasr_mc_periods_card on public.pasr_mc_periods(card_id, starts_on);

create table if not exists public.pasr_mc_members (
  id uuid primary key default gen_random_uuid(),
  card_id uuid not null references public.pasr_mc_cards(id) on delete cascade,
  business_id uuid not null references public.pasr_businesses(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  number text not null check (char_length(number) between 4 and 40),
  share_name boolean not null default false,
  notify boolean not null default true,
  saving_count integer not null default 0 check (saving_count >= 0),
  rewards_redeemed integer not null default 0 check (rewards_redeemed >= 0),
  last_visit_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  left_at timestamptz
);
create unique index if not exists pasr_mc_members_number on public.pasr_mc_members(business_id, number);
create unique index if not exists pasr_mc_members_one on public.pasr_mc_members(card_id, user_id) where left_at is null;
create index if not exists pasr_mc_members_user on public.pasr_mc_members(user_id) where left_at is null;
create index if not exists pasr_mc_members_card on public.pasr_mc_members(card_id) where left_at is null;

create table if not exists public.pasr_mc_visits (
  id bigint generated always as identity primary key,
  member_id uuid references public.pasr_mc_members(id) on delete set null,
  card_id uuid not null references public.pasr_mc_cards(id) on delete cascade,
  business_id uuid not null references public.pasr_businesses(id) on delete cascade,
  kind text not null check (kind in ('join', 'visit', 'redeem')),
  amount integer not null default 1,
  by_user uuid,
  at timestamptz not null default now()
);
create index if not exists pasr_mc_visits_business on public.pasr_mc_visits(business_id, at);

create table if not exists public.pasr_mc_period_notified (
  period_id uuid not null references public.pasr_mc_periods(id) on delete cascade,
  day date not null,
  at timestamptz not null default now(),
  primary key (period_id, day)
);

-- ---- outbox voor mails (event-mail) en pushmeldingen (admin, notify kind "tickets") ----
create table if not exists public.pasr_tk_outbox (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('ticket_confirmed', 'event_reminder', 'event_changed', 'event_cancelled',
                                     'waitlist_promoted', 'member_discount_started')),
  event_id uuid references public.pasr_tk_events(id) on delete cascade,
  registration_id uuid references public.pasr_tk_registrations(id) on delete cascade,
  ticket_id uuid references public.pasr_tk_tickets(id) on delete cascade,
  card_id uuid references public.pasr_mc_cards(id) on delete cascade,
  member_id uuid references public.pasr_mc_members(id) on delete cascade,
  period_id uuid references public.pasr_mc_periods(id) on delete cascade,
  email text,
  user_id uuid references auth.users(id) on delete cascade,
  message text,
  created_at timestamptz not null default now(),
  attempts integer not null default 0,
  mail_claimed_at timestamptz,
  mailed_at timestamptz,
  push_attempts integer not null default 0,
  push_claimed_at timestamptz,
  pushed_at timestamptz
);
create index if not exists pasr_tk_outbox_mail on public.pasr_tk_outbox(id) where mailed_at is null;
create index if not exists pasr_tk_outbox_push on public.pasr_tk_outbox(id) where pushed_at is null;

alter table public.pasr_tk_events enable row level security;
alter table public.pasr_tk_ticket_types enable row level security;
alter table public.pasr_tk_registrations enable row level security;
alter table public.pasr_tk_tickets enable row level security;
alter table public.pasr_mc_cards enable row level security;
alter table public.pasr_mc_periods enable row level security;
alter table public.pasr_mc_members enable row level security;
alter table public.pasr_mc_visits enable row level security;
alter table public.pasr_mc_period_notified enable row level security;
alter table public.pasr_tk_outbox enable row level security;
revoke all on public.pasr_tk_events, public.pasr_tk_ticket_types, public.pasr_tk_registrations, public.pasr_tk_tickets,
  public.pasr_mc_cards, public.pasr_mc_periods, public.pasr_mc_members, public.pasr_mc_visits,
  public.pasr_mc_period_notified, public.pasr_tk_outbox from public, anon, authenticated;

do $$
begin
  if to_regclass('public.pasr_admin_config') is not null then
    alter table public.pasr_admin_config add column if not exists tickets_url text;
  end if;
end $$;

-- ============================================================================================================ intern
create or replace function public.pasr_tk_err(p_code text, p_state text default '22023') returns void
language plpgsql volatile set search_path = '' as $$
begin
  raise exception '%', p_code using errcode = p_state, hint = p_code;
end $$;

-- Eigenaar of medewerker (p_owner = false), of alleen eigenaar (p_owner = true); anders not_owner.
create or replace function public.pasr_tk_need(p_business uuid, p_owner boolean) returns text
language plpgsql stable security definer set search_path = '' as $$
declare r text;
begin
  if auth.uid() is null then perform public.pasr_tk_err('not_owner', '42501'); end if;
  r := public.pasr_business_role(p_business);
  if r is null or (p_owner and r is distinct from 'owner')
     or not exists (select 1 from public.pasr_businesses b where b.id = p_business and b.status <> 'blocked') then
    perform public.pasr_tk_err('not_owner', '42501');
  end if;
  return r;
end $$;

-- Kleur en logo van de zaak: van de eerste stempelkaart (de zaak heeft zelf geen kleur).
create or replace function public.pasr_tk_biz_color(p_business uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare c text;
begin
  select upper(x.color) into c from public.pasr_business_cards x where x.business_id = p_business
   order by x.created_at limit 1;
  return case when c ~ '^#[0-9A-F]{6}$' then c else '#6A5CFF' end;
end $$;
create or replace function public.pasr_tk_biz_logo(p_business uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  return (select x.logo from public.pasr_business_cards x where x.business_id = p_business and x.logo is not null
           order by x.created_at limit 1);
end $$;

-- Willekeurige ticketcode: 24 tekens base32 (A-Z, 2-7), uit twee uuid's (zonder de vaste versie-bits). Nooit PZ/PC
-- vooraan, zodat de scanners hem niet met een stempelkaart of kortingsbon verwarren.
create or replace function public.pasr_tk_code() returns text
language plpgsql volatile security definer set search_path = '' as $$
declare a text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; b bytea; c text; j int;
begin
  loop
    b := decode(replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''), 'hex');
    c := '';
    for j in 0..31 loop
      continue when j in (6, 8, 22, 24);
      c := c || substr(a, (get_byte(b, j) % 32) + 1, 1);
      exit when char_length(c) = 24;
    end loop;
    exit when c !~ '^P[ZC]' and not exists (select 1 from public.pasr_tk_tickets t where t.code = c);
  end loop;
  return c;
end $$;

create or replace function public.pasr_tk_add_link(p_ticket uuid, p_code text) returns text
language sql immutable set search_path = '' as $$
  select 'https://pasr.nl/add/t/' || lower(p_ticket::text) || '?c=' || p_code;
$$;

-- Bezette plekken (aangemeld of binnen) van een event of een ticketsoort.
create or replace function public.pasr_tk_taken(p_event uuid, p_type uuid default null) returns integer
language plpgsql stable security definer set search_path = '' as $$
begin
  return (select count(*)::integer from public.pasr_tk_tickets t
           where t.event_id = p_event and t.status in ('registered', 'checked_in')
             and (p_type is null or t.ticket_type_id = p_type));
end $$;

-- Aanmelden open: gepubliceerd, nog niet begonnen en (als gezet) voor signup_until.
create or replace function public.pasr_tk_signup_open(e public.pasr_tk_events) returns boolean
language sql stable set search_path = '' as $$
  select e.status = 'published' and now() < coalesce(e.signup_until, e.starts_at) and now() < e.ends_at;
$$;

-- Seintje aan de functies (pg_net verstuurt pas na de commit). Fouten houden niets tegen.
create or replace function public.pasr_tk_kick() returns void
language plpgsql security definer set search_path = '' as $$
declare u text; s text;
begin
  begin
    perform public.pasr_admin_notify('tickets', '{}'::jsonb);
  exception when others then raise warning 'tickets push kick: %', sqlerrm;
  end;
  begin
    select tickets_url into u from public.pasr_admin_config where id = 1;
    select hook_secret into s from public.pasr_secret where id = 1;
    if coalesce(u, '') <> '' and s is not null then
      perform net.http_post(url := u, body := jsonb_build_object('action', 'run'),
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-pasr-hook', s),
        timeout_milliseconds := 30000);
    end if;
  exception when others then raise warning 'tickets mail kick: %', sqlerrm;
  end;
end $$;

create or replace function public.pasr_tk_outbox_kick() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.pasr_tk_kick();
  return null;
end $$;
drop trigger if exists pasr_tk_outbox_kick on public.pasr_tk_outbox;
create trigger pasr_tk_outbox_kick after insert on public.pasr_tk_outbox
  for each statement execute function public.pasr_tk_outbox_kick();

-- Een melding over een aanmelding: mail naar het e-mailadres, push naar het account (als het ticket in een account staat).
-- ticket_confirmed is alleen een mail (geen push).
create or replace function public.pasr_tk_enqueue(p_kind text, p_registration uuid, p_ticket uuid default null,
  p_message text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.pasr_tk_registrations; u uuid;
begin
  select * into r from public.pasr_tk_registrations where id = p_registration;
  if r.id is null then return; end if;
  u := coalesce((select t.user_id from public.pasr_tk_tickets t where t.id = p_ticket), r.user_id,
                (select t.user_id from public.pasr_tk_tickets t where t.registration_id = r.id and t.user_id is not null limit 1));
  if r.email is null and (u is null or p_kind = 'ticket_confirmed') then return; end if;
  insert into public.pasr_tk_outbox(kind, event_id, registration_id, ticket_id, email, user_id, message, mailed_at, pushed_at)
  values (p_kind, r.event_id, r.id, p_ticket, r.email, u, left(p_message, 500),
          case when r.email is null then now() end,
          case when u is null or p_kind = 'ticket_confirmed' then now() end);
end $$;

-- Wallet-passen (Apple en Google) van een ticket of lidmaatschap bijwerken: zelfde seintje als bij een stempel
-- (action "business"), met code "ET:<ticket>" of "MC:<lid>". Alleen als er zo'n pas is; fouten houden niets tegen.
create or replace function public.pasr_tk_wallet_kick(p_code text) returns void
language plpgsql security definer set search_path = '' as $$
declare u text; s text; apple boolean := false; google boolean := false;
begin
  begin
    select exists (select 1 from public.pasr_wallet_passes w where w.member_code = p_code) into apple;
  exception when others then apple := false;
  end;
  begin
    select exists (select 1 from public.pasr_gwallet_objects g where g.member_code = p_code) into google;
  exception when others then google := false;
  end;
  if not apple and not google then return; end if;
  select admin_url into u from public.pasr_admin_config where id = 1;
  select hook_secret into s from public.pasr_secret where id = 1;
  if coalesce(u, '') = '' or s is null then return; end if;
  if apple then
    perform net.http_post(url := regexp_replace(u, '/admin/?$', '/wallet-pass'), body := jsonb_build_object('action', 'business', 'code', p_code),
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-pasr-hook', s), timeout_milliseconds := 30000);
  end if;
  if google then
    perform net.http_post(url := regexp_replace(u, '/admin/?$', '/google-wallet'), body := jsonb_build_object('action', 'business', 'code', p_code),
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-pasr-hook', s), timeout_milliseconds := 30000);
  end if;
exception when others then
  raise warning 'pasr_tk_wallet_kick: %', sqlerrm;
end $$;

create or replace function public.pasr_tk_ticket_wallet_trigger() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status is distinct from old.status or new.user_id is distinct from old.user_id then
    perform public.pasr_tk_wallet_kick('ET:' || new.id::text);
  end if;
  return new;
end $$;
drop trigger if exists pasr_tk_ticket_wallet on public.pasr_tk_tickets;
create trigger pasr_tk_ticket_wallet after update on public.pasr_tk_tickets
  for each row execute function public.pasr_tk_ticket_wallet_trigger();

create or replace function public.pasr_mc_member_wallet_trigger() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.saving_count is distinct from old.saving_count or new.left_at is distinct from old.left_at
     or new.share_name is distinct from old.share_name then
    perform public.pasr_tk_wallet_kick('MC:' || new.id::text);
  end if;
  return new;
end $$;
drop trigger if exists pasr_mc_member_wallet on public.pasr_mc_members;
create trigger pasr_mc_member_wallet after update on public.pasr_mc_members
  for each row execute function public.pasr_mc_member_wallet_trigger();

-- Wachtlijst doorschuiven: de oudste wachtende tickets krijgen een plek zolang er plek is (ook per ticketsoort).
create or replace function public.pasr_tk_promote(p_event uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare e public.pasr_tk_events; t record; n integer := 0; free integer; tfree integer;
begin
  select * into e from public.pasr_tk_events where id = p_event for update;
  if e.id is null or e.status <> 'published' or e.ends_at <= now() then return 0; end if;
  for t in select x.id, x.registration_id, x.ticket_type_id, tt.capacity as type_capacity
             from public.pasr_tk_tickets x left join public.pasr_tk_ticket_types tt on tt.id = x.ticket_type_id
            where x.event_id = e.id and x.status = 'waitlist' order by x.created_at, x.id loop
    free := e.capacity - public.pasr_tk_taken(e.id);
    exit when free <= 0;
    if t.type_capacity is not null then
      tfree := t.type_capacity - public.pasr_tk_taken(e.id, t.ticket_type_id);
      continue when tfree <= 0;
    end if;
    update public.pasr_tk_tickets set status = 'registered', promoted_at = now() where id = t.id;
    perform public.pasr_tk_enqueue('waitlist_promoted', t.registration_id, t.id);
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.pasr_tk_types_json(p_event uuid) returns json
language plpgsql stable security definer set search_path = '' as $$
begin
  return coalesce((select json_agg(json_build_object('id', tt.id, 'name', tt.name, 'capacity', tt.capacity,
      'registered', public.pasr_tk_taken(p_event, tt.id),
      'waitlist', (select count(*) from public.pasr_tk_tickets x where x.ticket_type_id = tt.id and x.status = 'waitlist'))
      order by tt.position, tt.name)
    from public.pasr_tk_ticket_types tt where tt.event_id = p_event and not tt.archived), '[]'::json);
end $$;

-- ============================================================================================================ tickets: zaak
create or replace function public.pasr_business_event_save(p_business uuid, p_event jsonb) returns json
language plpgsql security definer set search_path = '' as $$
declare
  old public.pasr_tk_events; v_id uuid; v_name text; v_desc text; v_start timestamptz; v_end timestamptz; v_doors timestamptz;
  v_addr text; v_lat double precision; v_lng double precision; v_cap integer; v_max integer; v_until timestamptz;
  v_wait boolean; v_rem boolean; v_color text; v_header text; v_status text; v_types jsonb; t jsonb; v_tid uuid;
  keep uuid[] := '{}'; pos integer := 0; changed boolean := false; r record; v_tcap integer; v_tname text;
begin
  perform public.pasr_tk_need(p_business, true);
  if p_event is null or jsonb_typeof(p_event) <> 'object' then perform public.pasr_tk_err('invalid_input'); end if;
  begin
    v_id := nullif(p_event->>'id', '')::uuid;
    v_name := trim(coalesce(p_event->>'name', ''));
    v_desc := trim(coalesce(p_event->>'description', ''));
    v_start := (p_event->>'starts_at')::timestamptz;
    v_end := (p_event->>'ends_at')::timestamptz;
    v_doors := nullif(p_event->>'doors_at', '')::timestamptz;
    v_addr := trim(coalesce(p_event->>'address', ''));
    v_lat := nullif(p_event->>'lat', '')::double precision;
    v_lng := nullif(p_event->>'lng', '')::double precision;
    v_cap := (p_event->>'capacity')::integer;
    v_max := coalesce(nullif(p_event->>'max_per_person', '')::integer, 4);
    v_until := nullif(p_event->>'signup_until', '')::timestamptz;
    v_wait := coalesce((p_event->>'waitlist')::boolean, true);
    v_rem := coalesce((p_event->>'reminder')::boolean, true);
    v_color := upper(nullif(trim(coalesce(p_event->>'color', '')), ''));
    v_header := nullif(trim(coalesce(p_event->>'header_url', '')), '');
    v_status := coalesce(nullif(p_event->>'status', ''), 'draft');
  exception when others then
    perform public.pasr_tk_err('invalid_input');
  end;
  if v_id is not null then
    select * into old from public.pasr_tk_events where id = v_id and business_id = p_business for update;
    if old.id is null then perform public.pasr_tk_err('event_not_found', 'P0002'); end if;
    if old.status = 'cancelled' then perform public.pasr_tk_err('event_cancelled'); end if;
    if p_event->>'status' is null then v_status := old.status; end if;
  end if;
  if v_status = 'cancelled' then
    if v_id is null then perform public.pasr_tk_err('invalid_input'); end if;
    perform public.pasr_business_event_cancel(p_business, v_id, null);
    return json_build_object('id', v_id);
  end if;
  if char_length(v_name) not between 2 and 80 or char_length(v_desc) > 2000 or v_start is null or v_end is null
     or v_end <= v_start or (v_doors is not null and v_doors > v_start) or char_length(v_addr) > 200
     or v_cap is null or v_cap not between 1 and 100000 or v_max not between 1 and 20
     or (v_lat is not null and v_lat not between -90 and 90) or (v_lng is not null and v_lng not between -180 and 180)
     or (v_color is not null and v_color !~ '^#[0-9A-F]{6}$')
     or (v_header is not null and (v_header !~ '^https://' or char_length(v_header) > 500))
     or v_status not in ('draft', 'published')
     or (v_until is not null and v_until > v_end) then
    perform public.pasr_tk_err('invalid_input');
  end if;
  if v_status = 'published' and not exists (select 1 from public.pasr_businesses b where b.id = p_business and b.status = 'approved') then
    perform public.pasr_tk_err('business_not_approved', '42501');
  end if;
  v_types := case when jsonb_typeof(p_event->'ticket_types') = 'array' and jsonb_array_length(p_event->'ticket_types') > 0
                  then p_event->'ticket_types' else '[{"name":"Toegang"}]'::jsonb end;
  if jsonb_array_length(v_types) > 10 then perform public.pasr_tk_err('invalid_input'); end if;
  if v_id is null then
    if (select count(*) from public.pasr_tk_events x where x.business_id = p_business and x.status <> 'cancelled'
          and x.ends_at > now()) >= 50 then
      perform public.pasr_tk_err('invalid_input');
    end if;
    insert into public.pasr_tk_events(business_id, name, description, starts_at, ends_at, doors_at, address, lat, lng, capacity,
      max_per_person, signup_until, waitlist, reminder, color, header_url, status, created_by)
    values (p_business, v_name, v_desc, v_start, v_end, v_doors, v_addr, v_lat, v_lng, v_cap, v_max, v_until, v_wait, v_rem,
      coalesce(v_color, public.pasr_tk_biz_color(p_business)), v_header, v_status, auth.uid())
    returning id into v_id;
  else
    changed := old.status = 'published' and (old.name <> v_name or old.starts_at <> v_start or old.ends_at <> v_end
               or old.doors_at is distinct from v_doors or old.address <> v_addr);
    update public.pasr_tk_events set name = v_name, description = v_desc, starts_at = v_start, ends_at = v_end, doors_at = v_doors,
      address = v_addr, lat = v_lat, lng = v_lng, capacity = v_cap, max_per_person = v_max, signup_until = v_until,
      waitlist = v_wait, reminder = v_rem, color = coalesce(v_color, old.color), header_url = v_header, status = v_status,
      reminder_sent_at = case when old.starts_at <> v_start then null else old.reminder_sent_at end, updated_at = now()
    where id = v_id;
  end if;
  -- ticketsoorten: bestaande bijwerken, nieuwe erbij, weggelaten soorten met tickets archiveren, anders weg
  for t in select value from jsonb_array_elements(v_types) loop
    begin
      v_tid := nullif(t->>'id', '')::uuid;
      v_tname := trim(coalesce(t->>'name', ''));
      v_tcap := nullif(t->>'capacity', '')::integer;
    exception when others then
      perform public.pasr_tk_err('invalid_input');
    end;
    if char_length(v_tname) not between 1 and 40 or (v_tcap is not null and v_tcap not between 1 and 100000) then
      perform public.pasr_tk_err('invalid_input');
    end if;
    if v_tid is not null and exists (select 1 from public.pasr_tk_ticket_types x where x.id = v_tid and x.event_id = v_id) then
      update public.pasr_tk_ticket_types set name = v_tname, capacity = v_tcap, position = pos, archived = false where id = v_tid;
    else
      insert into public.pasr_tk_ticket_types(event_id, name, capacity, position) values (v_id, v_tname, v_tcap, pos) returning id into v_tid;
    end if;
    keep := keep || v_tid;
    pos := pos + 1;
  end loop;
  update public.pasr_tk_ticket_types x set archived = true
   where x.event_id = v_id and not (x.id = any(keep)) and exists (select 1 from public.pasr_tk_tickets k where k.ticket_type_id = x.id);
  delete from public.pasr_tk_ticket_types x
   where x.event_id = v_id and not (x.id = any(keep)) and not exists (select 1 from public.pasr_tk_tickets k where k.ticket_type_id = x.id);
  if changed then
    for r in select distinct g.id from public.pasr_tk_registrations g join public.pasr_tk_tickets k on k.registration_id = g.id
              where g.event_id = v_id and k.status in ('registered', 'checked_in', 'waitlist') loop
      perform public.pasr_tk_enqueue('event_changed', r.id);
    end loop;
    perform public.pasr_tk_wallet_kick('ET:' || k.id::text) from public.pasr_tk_tickets k where k.event_id = v_id and k.status <> 'cancelled';
  end if;
  perform public.pasr_tk_promote(v_id);
  return json_build_object('id', v_id);
end $$;

create or replace function public.pasr_business_events(p_business uuid)
returns table (id uuid, name text, starts_at timestamptz, ends_at timestamptz, doors_at timestamptz, address text,
  capacity integer, status text, color text, registered integer, checked_in integer, waitlist integer, ticket_types json,
  description text, lat double precision, lng double precision, max_per_person integer, signup_until timestamptz,
  waitlist_enabled boolean, reminder boolean, header_url text, cancelled integer, signup_open boolean,
  add_link text, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.pasr_tk_need(p_business, false);
  return query
  select e.id, e.name, e.starts_at, e.ends_at, e.doors_at, e.address, e.capacity, e.status, e.color,
    (select count(*)::integer from public.pasr_tk_tickets t where t.event_id = e.id and t.status in ('registered', 'checked_in')),
    (select count(*)::integer from public.pasr_tk_tickets t where t.event_id = e.id and t.status = 'checked_in'),
    (select count(*)::integer from public.pasr_tk_tickets t where t.event_id = e.id and t.status = 'waitlist'),
    public.pasr_tk_types_json(e.id),
    e.description, e.lat, e.lng, e.max_per_person, e.signup_until, e.waitlist, e.reminder, e.header_url,
    (select count(*)::integer from public.pasr_tk_tickets t where t.event_id = e.id and t.status = 'cancelled'),
    public.pasr_tk_signup_open(e), 'https://pasr.nl/add/e/' || e.id::text, e.created_at
  from public.pasr_tk_events e
  where e.business_id = p_business and (e.ends_at > now() - interval '90 days' or e.status = 'draft')
  order by e.starts_at;
end $$;

-- Aanmeldingen met persoonsgegevens: alleen de eigenaar van de zaak. Eén rij per ticket.
create or replace function public.pasr_business_event_registrations(p_business uuid, p_event uuid)
returns table (registration_id uuid, ticket_id uuid, first_name text, last_name text, email text, birth_date date,
  ticket_type text, status text, created_at timestamptz, checked_in_at timestamptz, waitlist_position integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.pasr_tk_need(p_business, true);
  if not exists (select 1 from public.pasr_tk_events e where e.id = p_event and e.business_id = p_business) then
    perform public.pasr_tk_err('event_not_found', 'P0002');
  end if;
  return query
  select g.id, t.id, g.first_name, g.last_name, g.email, g.birth_date, tt.name, t.status, t.created_at, t.checked_in_at,
    case when t.status = 'waitlist' then (select count(*)::integer from public.pasr_tk_tickets w
       where w.event_id = t.event_id and w.status = 'waitlist' and (w.created_at, w.id) <= (t.created_at, t.id)) end
  from public.pasr_tk_tickets t
  join public.pasr_tk_registrations g on g.id = t.registration_id
  left join public.pasr_tk_ticket_types tt on tt.id = t.ticket_type_id
  where t.event_id = p_event
  order by g.created_at, t.created_at, t.id;
end $$;

create or replace function public.pasr_business_event_cancel(p_business uuid, p_event uuid, p_message text) returns void
language plpgsql security definer set search_path = '' as $$
declare e public.pasr_tk_events; r record;
begin
  perform public.pasr_tk_need(p_business, true);
  select * into e from public.pasr_tk_events where id = p_event and business_id = p_business for update;
  if e.id is null then perform public.pasr_tk_err('event_not_found', 'P0002'); end if;
  if e.status = 'cancelled' then return; end if;
  if char_length(coalesce(p_message, '')) > 500 then perform public.pasr_tk_err('invalid_input'); end if;
  perform public.pasr_tk_cancel_event(p_event, p_message);
end $$;

-- Gedeeld door zaak en beheer: event afgelast, alle tickets vervallen, mail en push naar elke aanmelding.
create or replace function public.pasr_tk_cancel_event(p_event uuid, p_message text) returns void
language plpgsql security definer set search_path = '' as $$
declare e public.pasr_tk_events; r record;
begin
  select * into e from public.pasr_tk_events where id = p_event for update;
  if e.id is null or e.status = 'cancelled' then return; end if;
  update public.pasr_tk_events set status = 'cancelled', cancelled_at = now(), updated_at = now(),
    cancel_message = nullif(trim(coalesce(p_message, '')), '') where id = e.id;
  if e.status = 'published' then
    for r in select distinct g.id from public.pasr_tk_registrations g join public.pasr_tk_tickets k on k.registration_id = g.id
              where g.event_id = e.id and k.status in ('registered', 'checked_in', 'waitlist') loop
      perform public.pasr_tk_enqueue('event_cancelled', r.id, null, nullif(trim(coalesce(p_message, '')), ''));
    end loop;
  end if;
  update public.pasr_tk_tickets set status = 'cancelled', cancelled_at = now()
   where event_id = e.id and status in ('registered', 'waitlist');
end $$;

-- Extra: één aanmelding afmelden (eigenaar); de plek gaat naar de wachtlijst.
create or replace function public.pasr_business_event_registration_cancel(p_business uuid, p_registration uuid) returns json
language plpgsql security definer set search_path = '' as $$
declare g public.pasr_tk_registrations; n integer;
begin
  perform public.pasr_tk_need(p_business, true);
  select g2.* into g from public.pasr_tk_registrations g2 join public.pasr_tk_events e on e.id = g2.event_id
   where g2.id = p_registration and e.business_id = p_business;
  if g.id is null then perform public.pasr_tk_err('event_not_found', 'P0002'); end if;
  update public.pasr_tk_tickets set status = 'cancelled', cancelled_at = now()
   where registration_id = g.id and status in ('registered', 'waitlist');
  get diagnostics n = row_count;
  return json_build_object('cancelled', n, 'promoted', public.pasr_tk_promote(g.event_id));
end $$;

create or replace function public.pasr_business_ticket_scan(p_business uuid, p_code text, p_event uuid default null) returns json
language plpgsql security definer set search_path = '' as $$
declare t public.pasr_tk_tickets; e public.pasr_tk_events; g public.pasr_tk_registrations; v_type text; v_result text;
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '\s+', '', 'g'));
begin
  perform public.pasr_tk_need(p_business, false);
  select * into t from public.pasr_tk_tickets where code = v_code for update;
  if t.id is not null then select * into e from public.pasr_tk_events where id = t.event_id; end if;
  if t.id is null or e.business_id is distinct from p_business then
    return json_build_object('result', 'invalid', 'event_id', p_event,
      'counts', case when p_event is not null then public.pasr_tk_counts(p_event, p_business) end);
  end if;
  select * into g from public.pasr_tk_registrations where id = t.registration_id;
  select name into v_type from public.pasr_tk_ticket_types where id = t.ticket_type_id;
  if p_event is not null and t.event_id <> p_event then v_result := 'other_event';
  elsif e.status = 'cancelled' or t.status = 'cancelled' then v_result := 'cancelled';
  elsif t.status = 'checked_in' then v_result := 'used';
  elsif t.status = 'waitlist' or e.status <> 'published' then v_result := 'invalid';
  else
    update public.pasr_tk_tickets set status = 'checked_in', checked_in_at = now(), checked_in_by = auth.uid()
     where id = t.id returning * into t;
    v_result := 'valid';
  end if;
  return json_build_object('result', v_result, 'first_name', g.first_name, 'last_name', g.last_name, 'ticket_type', v_type,
    'event_id', e.id, 'event_name', e.name, 'checked_in_at', t.checked_in_at, 'ticket_id', t.id,
    'reason', case when t.status = 'waitlist' then 'waitlist' when e.status = 'draft' then 'draft' end,
    'counts', public.pasr_tk_counts(e.id, p_business));
end $$;

create or replace function public.pasr_tk_counts(p_event uuid, p_business uuid) returns json
language plpgsql stable security definer set search_path = '' as $$
declare e public.pasr_tk_events;
begin
  select * into e from public.pasr_tk_events where id = p_event and business_id = p_business;
  if e.id is null then return null; end if;
  return json_build_object(
    'checked_in', (select count(*) from public.pasr_tk_tickets t where t.event_id = e.id and t.status = 'checked_in'),
    'registered', public.pasr_tk_taken(e.id), 'capacity', e.capacity,
    'waitlist', (select count(*) from public.pasr_tk_tickets t where t.event_id = e.id and t.status = 'waitlist'));
end $$;

-- ============================================================================================================ tickets: openbaar en klant
create or replace function public.pasr_event_public(p_event uuid) returns json
language plpgsql stable security definer set search_path = '' as $$
declare e public.pasr_tk_events; b public.pasr_businesses; v_free integer;
begin
  select * into e from public.pasr_tk_events where id = p_event and status in ('published', 'cancelled');
  if e.id is null then return null; end if;
  select * into b from public.pasr_businesses where id = e.business_id and status = 'approved';
  if b.id is null then return null; end if;
  v_free := greatest(0, e.capacity - public.pasr_tk_taken(e.id));
  return json_build_object('id', e.id, 'name', e.name, 'description', e.description, 'starts_at', e.starts_at,
    'ends_at', e.ends_at, 'doors_at', e.doors_at, 'address', e.address, 'lat', e.lat, 'lng', e.lng, 'color', e.color,
    'header_url', e.header_url, 'business_name', b.name, 'business_logo', public.pasr_tk_biz_logo(b.id),
    'ticket_types', coalesce((select json_agg(json_build_object('id', tt.id, 'name', tt.name,
        'available', case when tt.capacity is null then v_free
                          else greatest(0, least(v_free, tt.capacity - public.pasr_tk_taken(e.id, tt.id))) end)
        order by tt.position, tt.name)
      from public.pasr_tk_ticket_types tt where tt.event_id = e.id and not tt.archived), '[]'::json),
    'spots_left', v_free, 'max_per_person', e.max_per_person, 'signup_open', public.pasr_tk_signup_open(e),
    'waitlist', e.waitlist, 'status', e.status, 'business_city', b.city, 'signup_until', e.signup_until,
    'cancel_message', e.cancel_message);
end $$;

-- p_hp en p_fill_ms (anti-bot, 20261127-antibot-forms.sql): het verborgen veld "website" en de invultijd in ms van
-- pasr.nl/add/e/…; achteraan met een standaardwaarde, zodat de apps (7 parameters) gewoon blijven werken. De oude
-- variant met 7 parameters gaat weg: twee varianten naast elkaar maakt de aanroep met 7 namen dubbelzinnig.
drop function if exists public.pasr_event_register(uuid, text, text, text, date, uuid, integer);
create or replace function public.pasr_event_register(p_event uuid, p_first_name text, p_last_name text, p_email text,
  p_birth_date date, p_ticket_type uuid, p_count integer, p_hp text default null, p_fill_ms integer default null) returns json
language plpgsql security definer set search_path = '' as $$
declare
  e public.pasr_tk_events; tt public.pasr_tk_ticket_types; v_first text := trim(coalesce(p_first_name, ''));
  v_last text := trim(coalesce(p_last_name, '')); v_email text := lower(trim(coalesce(p_email, '')));
  v_count integer := coalesce(p_count, 1); v_status text; v_reg uuid; v_tid uuid; v_code text; v_list jsonb := '[]'::jsonb;
  v_have integer; v_free integer; i integer; v_first_link text;
begin
  -- bot (honeypot ingevuld of sneller dan een mens): niets aanmaken en niets mailen, wel een gewoon antwoord
  if coalesce(btrim(p_hp), '') <> '' or (p_fill_ms is not null and p_fill_ms < 2000) then
    if to_regprocedure('public.pasr_form_bot(text,text)') is not null then
      perform public.pasr_form_bot('event_register', case when coalesce(btrim(p_hp), '') <> '' then 'honeypot' else 'too_fast' end);
    end if;
    return json_build_object('status', 'registered', 'tickets', '[]'::json, 'add_link', null, 'registration_id', null,
      'event_id', p_event);
  end if;
  if char_length(v_first) not between 1 and 60 or char_length(v_last) not between 1 and 60
     or char_length(v_email) not between 3 and 200 or v_email !~ '^[^@\s<>"'',;]+@[^@\s<>"'',;]+\.[^@\s<>"'',;]+$'
     or p_birth_date is null or p_birth_date < date '1900-01-01' or p_birth_date > current_date
     or v_count not between 1 and 20 or p_event is null then
    perform public.pasr_tk_err('invalid_input');
  end if;
  if to_regprocedure('public.pasr_web_rate_hit(text,integer,integer)') is not null and auth.uid() is null then
    perform public.pasr_web_rate_hit('event_register', 30, 200000);
  end if;
  -- en per e-mailadres (gehasht), over alle events samen
  if to_regprocedure('public.pasr_form_rate_hit(text,text,integer)') is not null and auth.uid() is null then
    perform public.pasr_form_rate_hit('event_register_mail', v_email, 10);
  end if;
  select * into e from public.pasr_tk_events where id = p_event for update;
  if e.id is null or e.status = 'draft'
     or not exists (select 1 from public.pasr_businesses b where b.id = e.business_id and b.status = 'approved') then
    perform public.pasr_tk_err('event_not_found', 'P0002');
  end if;
  if e.status = 'cancelled' then perform public.pasr_tk_err('event_cancelled'); end if;
  if not public.pasr_tk_signup_open(e) then perform public.pasr_tk_err('signup_closed'); end if;
  if p_ticket_type is null then
    select * into tt from public.pasr_tk_ticket_types x where x.event_id = e.id and not x.archived order by x.position limit 1;
  else
    select * into tt from public.pasr_tk_ticket_types x where x.id = p_ticket_type and x.event_id = e.id and not x.archived;
  end if;
  if tt.id is null then perform public.pasr_tk_err('invalid_input'); end if;
  -- hoogstens max_per_person tickets per e-mailadres (en per account) voor dit event
  select count(*) into v_have from public.pasr_tk_tickets t join public.pasr_tk_registrations g on g.id = t.registration_id
   where t.event_id = e.id and t.status <> 'cancelled'
     and (g.email = v_email or (auth.uid() is not null and (g.user_id = auth.uid() or t.user_id = auth.uid())));
  if v_have + v_count > e.max_per_person then perform public.pasr_tk_err('too_many'); end if;
  v_free := e.capacity - public.pasr_tk_taken(e.id);
  if tt.capacity is not null then v_free := least(v_free, tt.capacity - public.pasr_tk_taken(e.id, tt.id)); end if;
  -- wie al op de wachtlijst staat, gaat voor
  if exists (select 1 from public.pasr_tk_tickets w where w.event_id = e.id and w.status = 'waitlist'
               and (tt.capacity is null or w.ticket_type_id = tt.id)) then
    v_free := 0;
  end if;
  if v_count <= v_free then v_status := 'registered';
  elsif e.waitlist then v_status := 'waitlist';
  else perform public.pasr_tk_err('event_full');
  end if;
  insert into public.pasr_tk_registrations(event_id, ticket_type_id, first_name, last_name, email, birth_date, ticket_count, user_id)
  values (e.id, tt.id, v_first, v_last, v_email, p_birth_date, v_count, auth.uid()) returning id into v_reg;
  for i in 1..v_count loop
    v_code := public.pasr_tk_code();
    insert into public.pasr_tk_tickets(registration_id, event_id, ticket_type_id, code, user_id, status)
    values (v_reg, e.id, tt.id, v_code, auth.uid(), v_status) returning id into v_tid;
    v_list := v_list || jsonb_build_object('ticket_id', v_tid, 'code', v_code);
    if v_first_link is null then v_first_link := public.pasr_tk_add_link(v_tid, v_code); end if;
  end loop;
  perform public.pasr_tk_enqueue('ticket_confirmed', v_reg);
  return json_build_object('status', v_status, 'tickets', v_list, 'add_link', v_first_link, 'registration_id', v_reg,
    'event_id', e.id);
end $$;

create or replace function public.pasr_my_event_tickets()
returns table (ticket_id uuid, code text, event_id uuid, event_name text, starts_at timestamptz, ends_at timestamptz,
  doors_at timestamptz, address text, lat double precision, lng double precision, color text, header_url text,
  business_name text, business_logo text, holder_name text, ticket_type text, status text, group_key text,
  description text, event_status text, cancel_message text, checked_in_at timestamptz, business_id uuid)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then perform public.pasr_tk_err('not_signed_in', '28000'); end if;
  return query
  select t.id, t.code, e.id, e.name, e.starts_at, e.ends_at, e.doors_at, e.address, e.lat, e.lng, e.color, e.header_url,
    b.name, public.pasr_tk_biz_logo(b.id), nullif(trim(coalesce(g.first_name, '') || ' ' || coalesce(g.last_name, '')), ''),
    tt.name, t.status, e.id::text, e.description, e.status, e.cancel_message, t.checked_in_at, b.id
  from public.pasr_tk_tickets t
  join public.pasr_tk_events e on e.id = t.event_id
  join public.pasr_businesses b on b.id = e.business_id
  join public.pasr_tk_registrations g on g.id = t.registration_id
  left join public.pasr_tk_ticket_types tt on tt.id = t.ticket_type_id
  where t.user_id = auth.uid() and e.ends_at > now() - interval '30 days'
  order by e.starts_at, e.id, t.created_at, t.id;
end $$;

-- Ticket uit de mail of van de aanmeldpagina aan het account koppelen (alle tickets van dezelfde aanmelding).
create or replace function public.pasr_event_ticket_claim(p_ticket uuid, p_code text) returns json
language plpgsql security definer set search_path = '' as $$
declare t public.pasr_tk_tickets; v_ids uuid[];
begin
  if auth.uid() is null then perform public.pasr_tk_err('not_signed_in', '28000'); end if;
  select * into t from public.pasr_tk_tickets where id = p_ticket for update;
  if t.id is null or t.code <> upper(trim(coalesce(p_code, ''))) or (t.user_id is not null and t.user_id <> auth.uid()) then
    perform public.pasr_tk_err('invalid_code');
  end if;
  with x as (update public.pasr_tk_tickets set user_id = auth.uid()
              where registration_id = t.registration_id and (user_id is null or user_id = auth.uid()) returning id)
  select array_agg(id) into v_ids from x;
  update public.pasr_tk_registrations set user_id = coalesce(user_id, auth.uid()) where id = t.registration_id;
  return json_build_object('ticket_id', t.id, 'ticket_ids', to_json(coalesce(v_ids, array[t.id])), 'event_id', t.event_id);
end $$;

-- Extra (openbaar, met de code als bewijs): ticket bekijken op pasr.nl/add/t/<ticket>?c=<code>. Geen geboortedatum,
-- geen e-mail; alleen de naam van de houder.
create or replace function public.pasr_event_ticket_public(p_ticket uuid, p_code text) returns json
language plpgsql stable security definer set search_path = '' as $$
declare t public.pasr_tk_tickets; e public.pasr_tk_events; g public.pasr_tk_registrations;
begin
  select * into t from public.pasr_tk_tickets where id = p_ticket;
  if t.id is null or t.code <> upper(trim(coalesce(p_code, ''))) then return null; end if;
  select * into e from public.pasr_tk_events where id = t.event_id;
  select * into g from public.pasr_tk_registrations where id = t.registration_id;
  return json_build_object('ticket_id', t.id, 'status', t.status, 'event', public.pasr_event_public(e.id),
    'holder_name', nullif(trim(coalesce(g.first_name, '') || ' ' || coalesce(g.last_name, '')), ''),
    'ticket_type', (select name from public.pasr_tk_ticket_types where id = t.ticket_type_id),
    'tickets', (select count(*) from public.pasr_tk_tickets x where x.registration_id = t.registration_id and x.status <> 'cancelled'),
    'claimed', t.user_id is not null);
end $$;

-- Extra (openbaar, met de code): zelf afmelden. Alle tickets van de aanmelding vervallen; de wachtlijst schuift door.
-- p_hp en p_fill_ms: anti-bot zoals bij pasr_event_register (oude variant met 2 parameters gaat weg).
drop function if exists public.pasr_event_ticket_cancel(uuid, text);
create or replace function public.pasr_event_ticket_cancel(p_ticket uuid, p_code text, p_hp text default null,
  p_fill_ms integer default null) returns json
language plpgsql security definer set search_path = '' as $$
declare t public.pasr_tk_tickets; n integer;
begin
  if coalesce(btrim(p_hp), '') <> '' or (p_fill_ms is not null and p_fill_ms < 1000) then
    if to_regprocedure('public.pasr_form_bot(text,text)') is not null then
      perform public.pasr_form_bot('event_ticket_cancel', case when coalesce(btrim(p_hp), '') <> '' then 'honeypot' else 'too_fast' end);
    end if;
    return json_build_object('cancelled', 0, 'promoted', 0);
  end if;
  -- rem per internetadres: de code raden kost zo te veel pogingen
  if to_regprocedure('public.pasr_web_rate_hit(text,integer,integer)') is not null and auth.uid() is null then
    perform public.pasr_web_rate_hit('event_ticket_cancel', 30, 50000);
  end if;
  select * into t from public.pasr_tk_tickets where id = p_ticket for update;
  if t.id is null or t.code <> upper(trim(coalesce(p_code, ''))) then perform public.pasr_tk_err('invalid_code'); end if;
  update public.pasr_tk_tickets set status = 'cancelled', cancelled_at = now()
   where registration_id = t.registration_id and status in ('registered', 'waitlist');
  get diagnostics n = row_count;
  return json_build_object('cancelled', n, 'promoted', public.pasr_tk_promote(t.event_id));
end $$;

-- ============================================================================================================ klantenkaart: intern
create or replace function public.pasr_mc_ean_check(p_base text) returns text
language plpgsql immutable set search_path = '' as $$
declare s integer := 0; i integer;
begin
  if p_base !~ '^\d{12}$' then return null; end if;
  for i in 1..12 loop
    s := s + substr(p_base, i, 1)::integer * (case when i % 2 = 0 then 3 else 1 end);
  end loop;
  return ((10 - s % 10) % 10)::text;
end $$;

create or replace function public.pasr_mc_ean_valid(p_number text) returns boolean
language sql immutable set search_path = '' as $$
  select p_number ~ '^\d{13}$' and public.pasr_mc_ean_check(left(p_number, 12)) = right(p_number, 1);
$$;

-- Nieuw kaartnummer: EAN-13 (begint met 2, het bereik voor eigen nummers, met geldig controlecijfer) of voorvoegsel +
-- volgnummer van 6 cijfers ("KS-000124"). Uniek per zaak.
create or replace function public.pasr_mc_new_number(p_card uuid) returns text
language plpgsql volatile security definer set search_path = '' as $$
declare c public.pasr_mc_cards; v_base text; v_n text; v_seq bigint;
begin
  select * into c from public.pasr_mc_cards where id = p_card;
  loop
    if c.barcode_type = 'ean13' then
      v_base := '2' || lpad((floor(random() * 100000000000))::bigint::text, 11, '0');
      v_n := v_base || public.pasr_mc_ean_check(v_base);
      exit when not exists (select 1 from public.pasr_mc_members m where m.number = v_n);
    else
      update public.pasr_mc_cards set next_seq = next_seq + 1 where id = c.id returning next_seq - 1 into v_seq;
      v_n := c.prefix || lpad(v_seq::text, 6, '0');
      exit when not exists (select 1 from public.pasr_mc_members m where m.business_id = c.business_id and m.number = v_n);
    end if;
  end loop;
  return v_n;
end $$;

-- Korting die nu geldt en de volgende, in Nederlandse tijd (Europe/Amsterdam). Vaste korting telt mee; bij meer
-- tegelijk de hoogste. now: {percent, label, until, kind, period_id?}; next: {percent, label, starts_at, period_id}.
create or replace function public.pasr_mc_discount(p_card uuid, p_at timestamptz default now()) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare c public.pasr_mc_cards; loc timestamp := p_at at time zone 'Europe/Amsterdam'; d date := (p_at at time zone 'Europe/Amsterdam')::date;
  t time := (p_at at time zone 'Europe/Amsterdam')::time; dow integer := extract(isodow from (p_at at time zone 'Europe/Amsterdam'))::integer;
  best jsonb; bp numeric := 0; nxt jsonb; nts timestamptz; r public.pasr_mc_periods; dd date; st timestamptz; fx numeric; v_label text;
begin
  select * into c from public.pasr_mc_cards where id = p_card;
  if c.id is null then return jsonb_build_object('now', null, 'next', null); end if;
  if coalesce((c.goals->'fixed_discount'->>'enabled')::boolean, false) then
    fx := nullif(c.goals->'fixed_discount'->>'percent', '')::numeric;
    if fx > 0 then
      bp := fx;
      best := jsonb_build_object('percent', fx, 'label', 'Vaste korting', 'until', null, 'kind', 'fixed');
    end if;
  end if;
  for r in select * from public.pasr_mc_periods p where p.card_id = c.id and p.ends_on >= d order by p.starts_on loop
    v_label := coalesce(nullif(r.label, ''), trim(to_char(r.percent, 'FM990.##')) || '% korting');
    if d between r.starts_on and r.ends_on and (r.weekdays is null or dow = any(r.weekdays))
       and (r.from_time is null or t >= r.from_time) and (r.to_time is null or t < r.to_time) and r.percent > bp then
      bp := r.percent;
      best := jsonb_build_object('percent', r.percent, 'label', v_label, 'kind', 'period', 'period_id', r.id,
        'until', case when r.to_time is not null then (d + r.to_time) at time zone 'Europe/Amsterdam'
                      else ((r.ends_on + 1)::timestamp) at time zone 'Europe/Amsterdam' end,
        'until_date', r.ends_on);
    end if;
    -- volgende keer dat deze periode begint
    if r.weekdays is null and r.from_time is null then
      st := (r.starts_on::timestamp) at time zone 'Europe/Amsterdam';
      if st > p_at and (nts is null or st < nts) then
        nts := st;
        nxt := jsonb_build_object('percent', r.percent, 'label', v_label, 'starts_at', st, 'period_id', r.id);
      end if;
    else
      dd := greatest(d, r.starts_on);
      while dd <= least(r.ends_on, d + 120) loop
        if r.weekdays is null or extract(isodow from dd)::integer = any(r.weekdays) then
          st := (dd + coalesce(r.from_time, time '00:00')) at time zone 'Europe/Amsterdam';
          if st > p_at then
            if nts is null or st < nts then
              nts := st;
              nxt := jsonb_build_object('percent', r.percent, 'label', v_label, 'starts_at', st, 'period_id', r.id);
            end if;
            exit;
          end if;
        end if;
        dd := dd + 1;
      end loop;
    end if;
  end loop;
  return jsonb_build_object('now', best, 'next', nxt);
end $$;

create or replace function public.pasr_mc_goals_json(p_card uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare c public.pasr_mc_cards;
begin
  select * into c from public.pasr_mc_cards where id = p_card;
  return jsonb_build_object(
    'membership', coalesce((c.goals->>'membership')::boolean, false),
    'saving', coalesce(c.goals->'saving', '{"enabled":false}'::jsonb),
    'fixed_discount', coalesce(c.goals->'fixed_discount', '{"enabled":false}'::jsonb),
    'periods', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'label', p.label, 'percent', p.percent,
        'starts_on', p.starts_on, 'ends_on', p.ends_on, 'weekdays', to_jsonb(p.weekdays),
        'from_time', to_char(p.from_time, 'HH24:MI'), 'to_time', to_char(p.to_time, 'HH24:MI')) order by p.starts_on, p.from_time)
      from public.pasr_mc_periods p where p.card_id = p_card), '[]'::jsonb));
end $$;

create or replace function public.pasr_mc_saving_json(p_member uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare m public.pasr_mc_members; c public.pasr_mc_cards; v_target integer;
begin
  select * into m from public.pasr_mc_members where id = p_member;
  select * into c from public.pasr_mc_cards where id = m.card_id;
  if c.id is null or not coalesce((c.goals->'saving'->>'enabled')::boolean, false) then return null; end if;
  v_target := greatest(1, coalesce(nullif(c.goals->'saving'->>'target', '')::integer, 10));
  return jsonb_build_object('count', m.saving_count, 'target', v_target, 'reward', coalesce(c.goals->'saving'->>'reward', ''),
    'can_redeem', m.saving_count >= v_target, 'unit', coalesce(c.goals->'saving'->>'unit', 'visits'));
end $$;

create or replace function public.pasr_mc_member_name(p_member uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare m public.pasr_mc_members; v text;
begin
  select * into m from public.pasr_mc_members where id = p_member;
  if m.id is null or not m.share_name or m.user_id is null then return null; end if;
  begin
    execute 'select nullif(trim(coalesce(u.raw_user_meta_data->>''first_name'', '''') || '' '' || coalesce(u.raw_user_meta_data->>''last_name'', '''')), '''')
               from auth.users u where u.id = $1' into v using m.user_id;
  exception when others then v := null;
  end;
  return left(v, 80);
end $$;

-- Samenvatting van de doelen voor de klant (openbare pagina en app): regels in gewone taal plus de velden.
create or replace function public.pasr_mc_goals_summary(p_card uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare g jsonb := public.pasr_mc_goals_json(p_card); lines jsonb := '[]'::jsonb; p jsonb; v_unit text;
begin
  if coalesce((g->>'membership')::boolean, false) then lines := lines || to_jsonb('Laat je kaart zien: de zaak herkent je als lid'::text); end if;
  if coalesce((g->'saving'->>'enabled')::boolean, false) then
    v_unit := case when g->'saving'->>'unit' = 'points' then 'punten' else 'bezoeken' end;
    lines := lines || to_jsonb(('Spaar: ' || coalesce(g->'saving'->>'reward', 'een beloning') || ' na ' || coalesce(g->'saving'->>'target', '10') || ' ' || v_unit)::text);
  end if;
  if coalesce((g->'fixed_discount'->>'enabled')::boolean, false) then
    lines := lines || to_jsonb(('Altijd ' || coalesce(g->'fixed_discount'->>'percent', '0') || '% korting')::text);
  end if;
  for p in select value from jsonb_array_elements(g->'periods') loop
    continue when (p->>'ends_on')::date < (now() at time zone 'Europe/Amsterdam')::date;
    lines := lines || to_jsonb((coalesce(nullif(p->>'label', ''), (p->>'percent') || '% korting') || ' · ' ||
      to_char((p->>'starts_on')::date, 'DD-MM') || ' t/m ' || to_char((p->>'ends_on')::date, 'DD-MM'))::text);
  end loop;
  return jsonb_build_object('lines', lines, 'membership', g->'membership',
    'saving', case when coalesce((g->'saving'->>'enabled')::boolean, false) then g->'saving' end,
    'fixed_discount', case when coalesce((g->'fixed_discount'->>'enabled')::boolean, false) then g->'fixed_discount' end,
    'periods', g->'periods');
end $$;

-- ============================================================================================================ klantenkaart: zaak
create or replace function public.pasr_business_member_card_save(p_business uuid, p_card jsonb) returns json
language plpgsql security definer set search_path = '' as $$
declare
  old public.pasr_mc_cards; v_id uuid; v_name text; v_color text; v_logo text; v_type text; v_prefix text; v_status text;
  g jsonb; v_goals jsonb; v_saving jsonb; v_fixed jsonb; p jsonb; v_pid uuid; keep uuid[] := '{}'; v_wd integer[];
  v_from time; v_to time; v_start date; v_end date; v_pct numeric; v_label text; v_any boolean; v_logo_given boolean;
begin
  perform public.pasr_tk_need(p_business, true);
  if p_card is null or jsonb_typeof(p_card) <> 'object' then perform public.pasr_tk_err('invalid_input'); end if;
  begin
    v_id := nullif(p_card->>'id', '')::uuid;
    v_name := trim(coalesce(p_card->>'name', ''));
    v_color := upper(trim(coalesce(p_card->>'color', '#6A5CFF')));
    v_logo_given := p_card ? 'logo';
    v_logo := nullif(regexp_replace(coalesce(p_card->>'logo', ''), '^data:image/[a-z]+;base64,', ''), '');
    v_type := coalesce(nullif(p_card->>'barcode_type', ''), 'qr');
    v_prefix := upper(trim(coalesce(p_card->>'prefix', '')));
    v_status := coalesce(nullif(p_card->>'status', ''), 'draft');
    g := coalesce(p_card->'goals', '{}'::jsonb);
  exception when others then
    perform public.pasr_tk_err('invalid_input');
  end;
  if v_id is not null then
    select * into old from public.pasr_mc_cards where id = v_id and business_id = p_business for update;
    if old.id is null then perform public.pasr_tk_err('card_not_found', 'P0002'); end if;
    if p_card->>'status' is null then v_status := old.status; end if;
    if not v_logo_given then v_logo := old.logo; end if;
    if old.barcode_type <> v_type and exists (select 1 from public.pasr_mc_members m where m.card_id = old.id) then
      perform public.pasr_tk_err('barcode_type_locked');
    end if;
  end if;
  if v_type = 'ean13' then v_prefix := ''; end if;
  if char_length(v_name) not between 1 and 40 or v_color !~ '^#[0-9A-F]{6}$' or v_type not in ('qr', 'code128', 'ean13')
     or v_prefix !~ '^[A-Z0-9-]{0,8}$' or v_status not in ('draft', 'published', 'archived') or jsonb_typeof(g) <> 'object'
     or (v_logo is not null and (octet_length(v_logo) > 210000 or v_logo !~ '^(/9j/|iVBORw0KGgo)[A-Za-z0-9+/]+=*$')) then
    perform public.pasr_tk_err('invalid_input');
  end if;
  -- doelen
  v_saving := jsonb_build_object('enabled', false);
  if coalesce((g->'saving'->>'enabled')::boolean, false) then
    v_saving := jsonb_build_object('enabled', true, 'unit', coalesce(nullif(g->'saving'->>'unit', ''), 'visits'),
      'target', (g->'saving'->>'target')::integer, 'reward', trim(coalesce(g->'saving'->>'reward', '')));
    if v_saving->>'unit' not in ('visits', 'points') or (v_saving->>'target')::integer is null
       or (v_saving->>'target')::integer not between 1 and 1000 or char_length(v_saving->>'reward') not between 1 and 80 then
      perform public.pasr_tk_err('invalid_input');
    end if;
  end if;
  v_fixed := jsonb_build_object('enabled', false);
  if coalesce((g->'fixed_discount'->>'enabled')::boolean, false) then
    v_pct := (g->'fixed_discount'->>'percent')::numeric;
    if v_pct is null or v_pct <= 0 or v_pct > 100 then perform public.pasr_tk_err('invalid_input'); end if;
    v_fixed := jsonb_build_object('enabled', true, 'percent', v_pct);
  end if;
  if g->'periods' is not null and jsonb_typeof(g->'periods') <> 'array' then perform public.pasr_tk_err('invalid_input'); end if;
  if jsonb_array_length(coalesce(g->'periods', '[]'::jsonb)) > 20 then perform public.pasr_tk_err('invalid_input'); end if;
  v_goals := jsonb_build_object('membership', coalesce((g->>'membership')::boolean, false), 'saving', v_saving, 'fixed_discount', v_fixed);
  v_any := (v_goals->>'membership')::boolean or (v_saving->>'enabled')::boolean or (v_fixed->>'enabled')::boolean
           or jsonb_array_length(coalesce(g->'periods', '[]'::jsonb)) > 0;
  if v_status = 'published' and not v_any then perform public.pasr_tk_err('invalid_input'); end if;
  if v_status = 'published' and not exists (select 1 from public.pasr_businesses b where b.id = p_business and b.status = 'approved') then
    perform public.pasr_tk_err('business_not_approved', '42501');
  end if;
  if v_id is null then
    if (select count(*) from public.pasr_mc_cards x where x.business_id = p_business and x.status <> 'archived') >= 10 then
      perform public.pasr_tk_err('invalid_input');
    end if;
    insert into public.pasr_mc_cards(business_id, name, color, logo, barcode_type, prefix, status, goals, created_by, archived_at)
    values (p_business, v_name, v_color, v_logo, v_type, v_prefix, v_status, v_goals, auth.uid(),
            case when v_status = 'archived' then now() end)
    returning id into v_id;
  else
    update public.pasr_mc_cards set name = v_name, color = v_color, logo = v_logo, barcode_type = v_type, prefix = v_prefix,
      status = v_status, goals = v_goals, updated_at = now(),
      archived_at = case when v_status = 'archived' then coalesce(archived_at, now()) end
    where id = v_id;
  end if;
  -- kortingsperiodes
  for p in select value from jsonb_array_elements(coalesce(g->'periods', '[]'::jsonb)) loop
    begin
      v_pid := nullif(p->>'id', '')::uuid;
      v_label := trim(coalesce(p->>'label', ''));
      v_pct := (p->>'percent')::numeric;
      v_start := (p->>'starts_on')::date;
      v_end := (p->>'ends_on')::date;
      v_wd := case when jsonb_typeof(p->'weekdays') = 'array' and jsonb_array_length(p->'weekdays') > 0
                   then (select array_agg(distinct x::integer order by x::integer) from jsonb_array_elements_text(p->'weekdays') x) end;
      v_from := nullif(p->>'from_time', '')::time;
      v_to := nullif(p->>'to_time', '')::time;
    exception when others then
      perform public.pasr_tk_err('invalid_input');
    end;
    if char_length(v_label) > 40 or v_pct is null or v_pct <= 0 or v_pct > 100 or v_start is null or v_end is null
       or v_end < v_start or v_end > v_start + 3660 or (v_wd is not null and not (v_wd <@ array[1,2,3,4,5,6,7]))
       or (v_from is not null and v_to is not null and v_to <= v_from) then
      perform public.pasr_tk_err('invalid_input');
    end if;
    if v_pid is not null and exists (select 1 from public.pasr_mc_periods x where x.id = v_pid and x.card_id = v_id) then
      update public.pasr_mc_periods set label = v_label, percent = v_pct, starts_on = v_start, ends_on = v_end, weekdays = v_wd,
        from_time = v_from, to_time = v_to where id = v_pid;
    else
      insert into public.pasr_mc_periods(card_id, label, percent, starts_on, ends_on, weekdays, from_time, to_time)
      values (v_id, v_label, v_pct, v_start, v_end, v_wd, v_from, v_to) returning id into v_pid;
    end if;
    keep := keep || v_pid;
  end loop;
  delete from public.pasr_mc_periods x where x.card_id = v_id and not (x.id = any(keep));
  return json_build_object('id', v_id);
end $$;

create or replace function public.pasr_business_member_cards(p_business uuid)
returns table (id uuid, name text, color text, logo text, barcode_type text, status text, members integer, goals json,
  discount_now json, next_discount json, prefix text, add_link text, visits_today integer, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.pasr_tk_need(p_business, false);
  return query
  select c.id, c.name, c.color, c.logo, c.barcode_type, c.status,
    (select count(*)::integer from public.pasr_mc_members m where m.card_id = c.id and m.left_at is null),
    public.pasr_mc_goals_json(c.id)::json,
    (public.pasr_mc_discount(c.id)->'now')::json, (public.pasr_mc_discount(c.id)->'next')::json, c.prefix,
    'https://pasr.nl/add/m/' || c.id::text,
    (select count(*)::integer from public.pasr_mc_visits v where v.card_id = c.id and v.kind = 'visit'
       and v.at >= date_trunc('day', now() at time zone 'Europe/Amsterdam') at time zone 'Europe/Amsterdam'),
    c.created_at
  from public.pasr_mc_cards c where c.business_id = p_business
  order by c.status = 'archived', c.created_at;
end $$;

create or replace function public.pasr_mc_scan_json(m public.pasr_mc_members, p_result text) returns json
language plpgsql stable security definer set search_path = '' as $$
declare c public.pasr_mc_cards; d jsonb;
begin
  select * into c from public.pasr_mc_cards where id = m.card_id;
  d := public.pasr_mc_discount(c.id);
  return json_build_object('result', p_result, 'card_id', c.id, 'card_name', c.name, 'member_name', public.pasr_mc_member_name(m.id),
    'number', m.number, 'discount_now', d->'now', 'next_discount', d->'next', 'saving', public.pasr_mc_saving_json(m.id),
    'member_id', m.id, 'member_since', m.created_at, 'color', c.color, 'barcode_type', c.barcode_type,
    'membership', coalesce((c.goals->>'membership')::boolean, false));
end $$;

-- Lid zoeken op het gescande nummer: eerst bij deze zaak; staat het nummer alleen bij een andere zaak: other_business.
create or replace function public.pasr_mc_find(p_business uuid, p_code text) returns public.pasr_mc_members
language plpgsql stable security definer set search_path = '' as $$
declare m public.pasr_mc_members; v text := upper(regexp_replace(coalesce(p_code, ''), '\s+', '', 'g'));
begin
  select x.* into m from public.pasr_mc_members x join public.pasr_mc_cards c on c.id = x.card_id
   where x.business_id = p_business and x.number = v and x.left_at is null and c.status <> 'archived';
  return m;
end $$;

create or replace function public.pasr_business_member_card_scan(p_business uuid, p_code text) returns json
language plpgsql stable security definer set search_path = '' as $$
declare m public.pasr_mc_members; v text := upper(regexp_replace(coalesce(p_code, ''), '\s+', '', 'g'));
begin
  perform public.pasr_tk_need(p_business, false);
  m := public.pasr_mc_find(p_business, v);
  if m.id is not null then return public.pasr_mc_scan_json(m, 'valid'); end if;
  if v <> '' and exists (select 1 from public.pasr_mc_members x where x.number = v and x.business_id <> p_business and x.left_at is null) then
    return json_build_object('result', 'other_business', 'card_id', null, 'card_name', null, 'member_name', null, 'number', v,
      'discount_now', null, 'next_discount', null, 'saving', null);
  end if;
  return json_build_object('result', 'invalid', 'card_id', null, 'card_name', null, 'member_name', null, 'number', v,
    'discount_now', null, 'next_discount', null, 'saving', null);
end $$;

create or replace function public.pasr_business_member_card_visit(p_business uuid, p_code text, p_points integer default 1) returns json
language plpgsql security definer set search_path = '' as $$
declare m public.pasr_mc_members; c public.pasr_mc_cards; v_amount integer := 1; v_saving boolean;
begin
  perform public.pasr_tk_need(p_business, false);
  m := public.pasr_mc_find(p_business, p_code);
  if m.id is null then perform public.pasr_tk_err('invalid_code'); end if;
  select * into c from public.pasr_mc_cards where id = m.card_id;
  v_saving := coalesce((c.goals->'saving'->>'enabled')::boolean, false);
  if v_saving and c.goals->'saving'->>'unit' = 'points' then
    v_amount := coalesce(p_points, 1);
    if v_amount not between 1 and 1000 then perform public.pasr_tk_err('invalid_input'); end if;
  end if;
  update public.pasr_mc_members set saving_count = case when v_saving then saving_count + v_amount else saving_count end,
    last_visit_at = now(), updated_at = now() where id = m.id;
  insert into public.pasr_mc_visits(member_id, card_id, business_id, kind, amount, by_user) values (m.id, c.id, p_business, 'visit', v_amount, auth.uid());
  return json_build_object('saving', public.pasr_mc_saving_json(m.id), 'member_id', m.id);
end $$;

create or replace function public.pasr_business_member_card_redeem(p_business uuid, p_code text) returns json
language plpgsql security definer set search_path = '' as $$
declare m public.pasr_mc_members; s jsonb;
begin
  perform public.pasr_tk_need(p_business, false);
  m := public.pasr_mc_find(p_business, p_code);
  if m.id is null then perform public.pasr_tk_err('invalid_code'); end if;
  select * into m from public.pasr_mc_members where id = m.id for update;
  s := public.pasr_mc_saving_json(m.id);
  if s is null or not (s->>'can_redeem')::boolean then perform public.pasr_tk_err('not_enough'); end if;
  update public.pasr_mc_members set saving_count = saving_count - (s->>'target')::integer, rewards_redeemed = rewards_redeemed + 1,
    updated_at = now() where id = m.id;
  insert into public.pasr_mc_visits(member_id, card_id, business_id, kind, amount, by_user)
  values (m.id, m.card_id, p_business, 'redeem', (s->>'target')::integer, auth.uid());
  return json_build_object('saving', public.pasr_mc_saving_json(m.id), 'member_id', m.id);
end $$;

-- ============================================================================================================ klantenkaart: openbaar en klant
create or replace function public.pasr_member_card_public(p_card uuid) returns json
language plpgsql stable security definer set search_path = '' as $$
declare c public.pasr_mc_cards; b public.pasr_businesses; d jsonb;
begin
  select * into c from public.pasr_mc_cards where id = p_card and status = 'published';
  if c.id is null then return null; end if;
  select * into b from public.pasr_businesses where id = c.business_id and status = 'approved';
  if b.id is null then return null; end if;
  d := public.pasr_mc_discount(c.id);
  return json_build_object('id', c.id, 'name', c.name, 'color', c.color, 'logo', coalesce(c.logo, public.pasr_tk_biz_logo(b.id)),
    'business_name', b.name, 'goals_summary', public.pasr_mc_goals_summary(c.id), 'discount_now', d->'now',
    'next_discount', d->'next', 'barcode_type', c.barcode_type, 'business_city', b.city);
end $$;

create or replace function public.pasr_member_card_join(p_card uuid, p_share_name boolean) returns json
language plpgsql security definer set search_path = '' as $$
declare c public.pasr_mc_cards; v_id uuid; v_n text;
begin
  if auth.uid() is null then perform public.pasr_tk_err('not_signed_in', '28000'); end if;
  select * into c from public.pasr_mc_cards where id = p_card and status = 'published' for update;
  if c.id is null or not exists (select 1 from public.pasr_businesses b where b.id = c.business_id and b.status = 'approved') then
    perform public.pasr_tk_err('card_not_found', 'P0002');
  end if;
  if exists (select 1 from public.pasr_mc_members m where m.card_id = c.id and m.user_id = auth.uid() and m.left_at is null) then
    perform public.pasr_tk_err('already_member', '23505');
  end if;
  v_n := public.pasr_mc_new_number(c.id);
  insert into public.pasr_mc_members(card_id, business_id, user_id, number, share_name)
  values (c.id, c.business_id, auth.uid(), v_n, coalesce(p_share_name, false)) returning id into v_id;
  insert into public.pasr_mc_visits(member_id, card_id, business_id, kind, amount, by_user) values (v_id, c.id, c.business_id, 'join', 0, auth.uid());
  return json_build_object('member_id', v_id, 'number', v_n, 'barcode_type', c.barcode_type, 'card_id', c.id);
end $$;

create or replace function public.pasr_my_member_cards()
returns table (member_id uuid, card_id uuid, name text, color text, logo text, business_name text, number text,
  barcode_type text, discount_now json, next_discount json, saving json, notify boolean, share_name boolean,
  member_since timestamptz, card_status text, goals_summary json, business_id uuid)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then perform public.pasr_tk_err('not_signed_in', '28000'); end if;
  return query
  select m.id, c.id, c.name, c.color, coalesce(c.logo, public.pasr_tk_biz_logo(b.id)), b.name, m.number, c.barcode_type,
    (public.pasr_mc_discount(c.id)->'now')::json, (public.pasr_mc_discount(c.id)->'next')::json,
    public.pasr_mc_saving_json(m.id)::json, m.notify, m.share_name, m.created_at, c.status,
    public.pasr_mc_goals_summary(c.id)::json, b.id
  from public.pasr_mc_members m
  join public.pasr_mc_cards c on c.id = m.card_id
  join public.pasr_businesses b on b.id = c.business_id
  where m.user_id = auth.uid() and m.left_at is null
  order by m.created_at;
end $$;

create or replace function public.pasr_member_card_leave(p_member uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then perform public.pasr_tk_err('not_signed_in', '28000'); end if;
  update public.pasr_mc_members set left_at = now(), notify = false, updated_at = now()
   where id = p_member and user_id = auth.uid() and left_at is null;
  if not found then perform public.pasr_tk_err('card_not_found', 'P0002'); end if;
end $$;

create or replace function public.pasr_member_card_notify(p_member uuid, p_on boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then perform public.pasr_tk_err('not_signed_in', '28000'); end if;
  update public.pasr_mc_members set notify = coalesce(p_on, false), updated_at = now()
   where id = p_member and user_id = auth.uid() and left_at is null;
  if not found then perform public.pasr_tk_err('card_not_found', 'P0002'); end if;
end $$;

-- ============================================================================================================ cron
-- Elke 10 minuten: herinnering de dag ervoor (vanaf 10:00), push als een kortingsperiode begint (vanaf het begin, of
-- 09:00 bij een hele dag), mails/pushes opnieuw proberen, persoonsgegevens 30 dagen na het event wissen.
create or replace function public.pasr_tk_cron(p_now timestamptz default now()) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e record; r record; p record; loc timestamp := p_now at time zone 'Europe/Amsterdam'; d date; v_at timestamptz;
  n_rem integer := 0; n_disc integer := 0; n_purge integer := 0; m record;
begin
  d := loc::date;
  -- herinnering de dag ervoor
  for e in select x.* from public.pasr_tk_events x
            where x.status = 'published' and x.reminder and x.reminder_sent_at is null and x.starts_at > p_now
              and (x.starts_at at time zone 'Europe/Amsterdam')::date = d + 1 and loc::time >= time '10:00' loop
    update public.pasr_tk_events set reminder_sent_at = p_now where id = e.id;
    for r in select distinct g.id from public.pasr_tk_registrations g join public.pasr_tk_tickets k on k.registration_id = g.id
              where g.event_id = e.id and k.status = 'registered' loop
      perform public.pasr_tk_enqueue('event_reminder', r.id);
      n_rem := n_rem + 1;
    end loop;
  end loop;
  -- kortingsperiode begint
  for p in select pr.*, c.id as cid from public.pasr_mc_periods pr
             join public.pasr_mc_cards c on c.id = pr.card_id and c.status = 'published'
             join public.pasr_businesses b on b.id = c.business_id and b.status = 'approved'
            where d between pr.starts_on and pr.ends_on
              and (pr.weekdays is null or extract(isodow from d)::integer = any(pr.weekdays))
              and not exists (select 1 from public.pasr_mc_period_notified n where n.period_id = pr.id and n.day = d) loop
    -- een doorlopende periode zonder dagen of tijden alleen op de eerste dag
    continue when p.weekdays is null and p.from_time is null and d <> p.starts_on;
    v_at := (d + coalesce(p.from_time, time '09:00')) at time zone 'Europe/Amsterdam';
    continue when p_now < v_at or p_now > v_at + interval '3 hours';
    continue when p.to_time is not null and loc::time >= p.to_time;
    insert into public.pasr_mc_period_notified(period_id, day) values (p.id, d) on conflict do nothing;
    for m in select x.id, x.user_id from public.pasr_mc_members x where x.card_id = p.cid and x.left_at is null loop
      if m.user_id is not null and (select x2.notify from public.pasr_mc_members x2 where x2.id = m.id) then
        insert into public.pasr_tk_outbox(kind, card_id, member_id, period_id, user_id, mailed_at)
        values ('member_discount_started', p.cid, m.id, p.id, m.user_id, p_now);
        n_disc := n_disc + 1;
      end if;
      perform public.pasr_tk_wallet_kick('MC:' || m.id::text);
    end loop;
  end loop;
  -- persoonsgegevens wissen, 30 dagen na het event (of na het afgelasten)
  for e in select x.id from public.pasr_tk_events x where x.purged_at is null
            and (x.ends_at < p_now - interval '30 days' or (x.status = 'cancelled' and x.cancelled_at < p_now - interval '30 days')) loop
    update public.pasr_tk_registrations set first_name = null, last_name = null, email = null, birth_date = null where event_id = e.id;
    update public.pasr_tk_events set purged_at = p_now where id = e.id;
    n_purge := n_purge + 1;
  end loop;
  delete from public.pasr_tk_outbox where created_at < p_now - interval '30 days';
  if exists (select 1 from public.pasr_tk_outbox where (mailed_at is null and attempts < 5) or (pushed_at is null and push_attempts < 5)) then
    perform public.pasr_tk_kick();
  end if;
  return jsonb_build_object('reminders', n_rem, 'discounts', n_disc, 'purged', n_purge);
end $$;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'pasr-tickets';
  perform cron.schedule('pasr-tickets', '*/10 * * * *', 'select public.pasr_tk_cron()');
exception when others then
  raise notice 'pg_cron niet beschikbaar: %', sqlerrm;
end $$;

-- ============================================================================================================ outbox (service role)
create or replace function public.pasr_tk_event_json(p_event uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare e public.pasr_tk_events; b public.pasr_businesses;
begin
  select * into e from public.pasr_tk_events where id = p_event;
  if e.id is null then return null; end if;
  select * into b from public.pasr_businesses where id = e.business_id;
  return jsonb_build_object('id', e.id, 'name', e.name, 'description', e.description, 'starts_at', e.starts_at,
    'ends_at', e.ends_at, 'doors_at', e.doors_at, 'address', e.address, 'color', e.color, 'status', e.status,
    'business_name', b.name, 'business_city', b.city, 'cancel_message', e.cancel_message);
end $$;

create or replace function public.pasr_tk_mail_due(p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_ids bigint[];
begin
  with picked as (
    select o.id from public.pasr_tk_outbox o
     where o.mailed_at is null and o.attempts < 5 and o.created_at > now() - interval '3 days'
       and (o.mail_claimed_at is null or o.mail_claimed_at < now() - interval '10 minutes')
     order by o.id limit least(greatest(coalesce(p_limit, 50), 1), 200)
     for update skip locked)
  , claimed as (
  update public.pasr_tk_outbox o set mail_claimed_at = now(), attempts = o.attempts + 1
    from picked where o.id = picked.id returning o.id)
  select array_agg(claimed.id) into v_ids from claimed;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', o.id, 'kind', o.kind, 'to', o.email, 'first_name', g.first_name, 'message', o.message,
      'event', public.pasr_tk_event_json(o.event_id),
      'tickets', coalesce((select jsonb_agg(jsonb_build_object('ticket_id', t.id, 'code', t.code, 'status', t.status,
            'ticket_type', tt.name, 'add_link', public.pasr_tk_add_link(t.id, t.code)) order by t.created_at, t.id)
          from public.pasr_tk_tickets t left join public.pasr_tk_ticket_types tt on tt.id = t.ticket_type_id
         where t.registration_id = o.registration_id and (o.ticket_id is null or t.id = o.ticket_id)), '[]'::jsonb))
      order by o.id)
    from public.pasr_tk_outbox o
    left join public.pasr_tk_registrations g on g.id = o.registration_id
   where o.id = any(coalesce(v_ids, '{}'))), '[]'::jsonb);
end $$;

create or replace function public.pasr_tk_mail_sent(p_ids bigint[]) returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  update public.pasr_tk_outbox set mailed_at = now() where id = any(coalesce(p_ids, '{}'));
  get diagnostics n = row_count;
  return n;
end $$;

-- Apparaten van de Pasr-app van de klant: iOS uit pasr_user_push (account) en pasr_devices (app pasr, APNs of FCM).
create or replace function public.pasr_tk_user_devices(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare a jsonb := '[]'::jsonb; b jsonb := '[]'::jsonb;
begin
  if p_user is null then return '[]'::jsonb; end if;
  begin
    execute 'select coalesce(jsonb_agg(jsonb_build_object(''device_id'', u.device_id, ''token'', u.token, ''provider'', ''apns'',
               ''sandbox'', u.sandbox, ''src'', ''user'')), ''[]''::jsonb) from public.pasr_user_push u where u.user_id = $1'
      into a using p_user;
  exception when others then a := '[]'::jsonb;
  end;
  begin
    execute 'select coalesce(jsonb_agg(jsonb_build_object(''device_id'', d.device_id, ''token'', d.push_token, ''provider'', d.push_provider,
               ''sandbox'', d.push_sandbox, ''src'', ''device'')), ''[]''::jsonb) from public.pasr_devices d
             where d.app = ''pasr'' and d.user_id = $1 and d.push_token is not null and d.push_provider in (''apns'', ''fcm'')'
      into b using p_user;
  exception when others then b := '[]'::jsonb;
  end;
  return a || b;
end $$;

create or replace function public.pasr_tk_push_due(p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_ids bigint[];
begin
  with picked as (
    select o.id from public.pasr_tk_outbox o
     where o.pushed_at is null and o.user_id is not null and o.push_attempts < 5 and o.created_at > now() - interval '3 days'
       and (o.push_claimed_at is null or o.push_claimed_at < now() - interval '10 minutes')
     order by o.id limit least(greatest(coalesce(p_limit, 50), 1), 200)
     for update skip locked)
  , claimed as (
  update public.pasr_tk_outbox o set push_claimed_at = now(), push_attempts = o.push_attempts + 1
    from picked where o.id = picked.id returning o.id)
  select array_agg(claimed.id) into v_ids from claimed;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', o.id, 'kind', o.kind, 'event_id', o.event_id, 'ticket_id', o.ticket_id, 'card_id', o.card_id,
      'member_id', o.member_id, 'message', o.message,
      'title', coalesce(e.name, c.name), 'business', b.name, 'starts_at', e.starts_at, 'doors_at', e.doors_at,
      'tickets', case when o.registration_id is not null then (select count(*) from public.pasr_tk_tickets t
                  where t.registration_id = o.registration_id and t.status in ('registered', 'checked_in')) end,
      'percent', pr.percent, 'label', coalesce(nullif(pr.label, ''), trim(to_char(pr.percent, 'FM990.##')) || '% korting'),
      'ends_on', pr.ends_on, 'to_time', to_char(pr.to_time, 'HH24:MI'),
      'devices', public.pasr_tk_user_devices(o.user_id))
      order by o.id)
    from public.pasr_tk_outbox o
    left join public.pasr_tk_events e on e.id = o.event_id
    left join public.pasr_mc_cards c on c.id = o.card_id
    left join public.pasr_mc_periods pr on pr.id = o.period_id
    left join public.pasr_businesses b on b.id = coalesce(e.business_id, c.business_id)
   where o.id = any(coalesce(v_ids, '{}'))), '[]'::jsonb);
end $$;

create or replace function public.pasr_tk_push_sent(p_ids bigint[]) returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  update public.pasr_tk_outbox set pushed_at = now() where id = any(coalesce(p_ids, '{}'));
  get diagnostics n = row_count;
  return n;
end $$;

-- Gegevens voor een Wallet-pas die de server bijwerkt (functies wallet-pass en google-wallet, service role).
-- p_kind: event_ticket (id = ticket) of member_card (id = lidmaatschap). Nooit geboortedatum of e-mail.
create or replace function public.pasr_tk_pass_data(p_kind text, p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare t public.pasr_tk_tickets; e public.pasr_tk_events; g public.pasr_tk_registrations; m public.pasr_mc_members;
  c public.pasr_mc_cards; b public.pasr_businesses; d jsonb;
begin
  if p_kind = 'event_ticket' then
    select * into t from public.pasr_tk_tickets where id = p_id;
    if t.id is null then return null; end if;
    select * into e from public.pasr_tk_events where id = t.event_id;
    select * into g from public.pasr_tk_registrations where id = t.registration_id;
    select * into b from public.pasr_businesses where id = e.business_id;
    return jsonb_build_object('kind', 'event_ticket', 'ticket_id', t.id, 'code', t.code, 'status', t.status,
      'event_id', e.id, 'event_name', e.name, 'starts_at', e.starts_at, 'ends_at', e.ends_at, 'doors_at', e.doors_at,
      'address', e.address, 'lat', e.lat, 'lng', e.lng, 'color', e.color, 'event_status', e.status,
      'business_name', b.name, 'business_logo', public.pasr_tk_biz_logo(b.id),
      'holder_name', nullif(trim(coalesce(g.first_name, '') || ' ' || coalesce(g.last_name, '')), ''),
      'ticket_type', (select name from public.pasr_tk_ticket_types where id = t.ticket_type_id),
      'index', (select count(*) from public.pasr_tk_tickets x where x.registration_id = t.registration_id and (x.created_at, x.id) <= (t.created_at, t.id)),
      'of', (select count(*) from public.pasr_tk_tickets x where x.registration_id = t.registration_id));
  elsif p_kind = 'member_card' then
    select * into m from public.pasr_mc_members where id = p_id;
    if m.id is null then return null; end if;
    select * into c from public.pasr_mc_cards where id = m.card_id;
    select * into b from public.pasr_businesses where id = c.business_id;
    d := public.pasr_mc_discount(c.id);
    return jsonb_build_object('kind', 'member_card', 'member_id', m.id, 'card_id', c.id, 'name', c.name, 'color', c.color,
      'logo', coalesce(c.logo, public.pasr_tk_biz_logo(b.id)), 'business_name', b.name, 'number', m.number,
      'barcode_type', c.barcode_type, 'member_name', public.pasr_mc_member_name(m.id), 'member_since', m.created_at,
      'discount_now', d->'now', 'next_discount', d->'next', 'saving', public.pasr_mc_saving_json(m.id),
      'active', m.left_at is null and c.status = 'published');
  end if;
  return null;
end $$;

-- ============================================================================================================ beheer (functie admin)
create or replace function public.pasr_admin_tk_business(p_business uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  return jsonb_build_object(
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.name, 'starts_at', e.starts_at,
        'ends_at', e.ends_at, 'address', e.address, 'status', e.status, 'capacity', e.capacity, 'color', e.color,
        'registered', public.pasr_tk_taken(e.id),
        'checked_in', (select count(*) from public.pasr_tk_tickets t where t.event_id = e.id and t.status = 'checked_in'),
        'waitlist', (select count(*) from public.pasr_tk_tickets t where t.event_id = e.id and t.status = 'waitlist'),
        'cancelled', (select count(*) from public.pasr_tk_tickets t where t.event_id = e.id and t.status = 'cancelled'),
        'registrations', (select count(*) from public.pasr_tk_registrations g where g.event_id = e.id),
        'cancelled_at', e.cancelled_at, 'created_at', e.created_at) order by e.starts_at desc)
      from public.pasr_tk_events e where e.business_id = p_business), '[]'::jsonb),
    'member_cards', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'status', c.status,
        'color', c.color, 'barcode_type', c.barcode_type, 'prefix', c.prefix,
        'members', (select count(*) from public.pasr_mc_members m where m.card_id = c.id and m.left_at is null),
        'visits_30d', (select count(*) from public.pasr_mc_visits v where v.card_id = c.id and v.kind = 'visit' and v.at > now() - interval '30 days'),
        'periods', (select count(*) from public.pasr_mc_periods p where p.card_id = c.id),
        'goals', public.pasr_mc_goals_summary(c.id)->'lines', 'archived_at', c.archived_at, 'created_at', c.created_at)
        order by c.created_at)
      from public.pasr_mc_cards c where c.business_id = p_business), '[]'::jsonb));
end $$;

create or replace function public.pasr_admin_event_cancel(p_event uuid, p_message text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.pasr_tk_events where id = p_event) then raise exception 'not_found' using errcode = 'P0002'; end if;
  perform public.pasr_tk_cancel_event(p_event, left(p_message, 500));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.pasr_admin_member_card_archive(p_card uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  update public.pasr_mc_cards set status = 'archived', archived_at = coalesce(archived_at, now()), updated_at = now() where id = p_card;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  perform public.pasr_tk_wallet_kick('MC:' || m.id::text) from public.pasr_mc_members m where m.card_id = p_card and m.left_at is null;
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================================================================ rechten
revoke all on function public.pasr_tk_err(text, text), public.pasr_tk_need(uuid, boolean), public.pasr_tk_biz_color(uuid),
  public.pasr_tk_biz_logo(uuid), public.pasr_tk_code(), public.pasr_tk_add_link(uuid, text), public.pasr_tk_taken(uuid, uuid),
  public.pasr_tk_signup_open(public.pasr_tk_events), public.pasr_tk_kick(), public.pasr_tk_outbox_kick(),
  public.pasr_tk_enqueue(text, uuid, uuid, text), public.pasr_tk_wallet_kick(text), public.pasr_tk_ticket_wallet_trigger(),
  public.pasr_mc_member_wallet_trigger(), public.pasr_tk_promote(uuid), public.pasr_tk_types_json(uuid),
  public.pasr_tk_cancel_event(uuid, text), public.pasr_tk_counts(uuid, uuid), public.pasr_mc_ean_check(text),
  public.pasr_mc_ean_valid(text), public.pasr_mc_new_number(uuid), public.pasr_mc_discount(uuid, timestamptz),
  public.pasr_mc_goals_json(uuid), public.pasr_mc_saving_json(uuid), public.pasr_mc_member_name(uuid),
  public.pasr_mc_goals_summary(uuid), public.pasr_mc_scan_json(public.pasr_mc_members, text), public.pasr_mc_find(uuid, text),
  public.pasr_tk_cron(timestamptz), public.pasr_tk_event_json(uuid), public.pasr_tk_mail_due(integer),
  public.pasr_tk_mail_sent(bigint[]), public.pasr_tk_user_devices(uuid), public.pasr_tk_push_due(integer),
  public.pasr_tk_push_sent(bigint[]), public.pasr_tk_pass_data(text, uuid), public.pasr_admin_tk_business(uuid),
  public.pasr_admin_event_cancel(uuid, text), public.pasr_admin_member_card_archive(uuid)
  from public, anon, authenticated;
grant execute on function public.pasr_tk_mail_due(integer), public.pasr_tk_mail_sent(bigint[]), public.pasr_tk_push_due(integer),
  public.pasr_tk_push_sent(bigint[]), public.pasr_tk_pass_data(text, uuid), public.pasr_admin_tk_business(uuid),
  public.pasr_admin_event_cancel(uuid, text), public.pasr_admin_member_card_archive(uuid), public.pasr_tk_cron(timestamptz)
  to service_role;

revoke all on function public.pasr_business_event_save(uuid, jsonb), public.pasr_business_events(uuid),
  public.pasr_business_event_registrations(uuid, uuid), public.pasr_business_event_cancel(uuid, uuid, text),
  public.pasr_business_event_registration_cancel(uuid, uuid), public.pasr_business_ticket_scan(uuid, text, uuid),
  public.pasr_event_public(uuid), public.pasr_event_register(uuid, text, text, text, date, uuid, integer, text, integer),
  public.pasr_my_event_tickets(), public.pasr_event_ticket_claim(uuid, text), public.pasr_event_ticket_public(uuid, text),
  public.pasr_event_ticket_cancel(uuid, text, text, integer),
  public.pasr_business_member_card_save(uuid, jsonb), public.pasr_business_member_cards(uuid),
  public.pasr_business_member_card_scan(uuid, text), public.pasr_business_member_card_visit(uuid, text, integer),
  public.pasr_business_member_card_redeem(uuid, text), public.pasr_member_card_public(uuid),
  public.pasr_member_card_join(uuid, boolean), public.pasr_my_member_cards(), public.pasr_member_card_leave(uuid),
  public.pasr_member_card_notify(uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.pasr_business_event_save(uuid, jsonb), public.pasr_business_events(uuid),
  public.pasr_business_event_registrations(uuid, uuid), public.pasr_business_event_cancel(uuid, uuid, text),
  public.pasr_business_event_registration_cancel(uuid, uuid), public.pasr_business_ticket_scan(uuid, text, uuid),
  public.pasr_my_event_tickets(), public.pasr_event_ticket_claim(uuid, text),
  public.pasr_business_member_card_save(uuid, jsonb), public.pasr_business_member_cards(uuid),
  public.pasr_business_member_card_scan(uuid, text), public.pasr_business_member_card_visit(uuid, text, integer),
  public.pasr_business_member_card_redeem(uuid, text), public.pasr_member_card_join(uuid, boolean),
  public.pasr_my_member_cards(), public.pasr_member_card_leave(uuid), public.pasr_member_card_notify(uuid, boolean)
  to authenticated;
grant execute on function public.pasr_event_public(uuid), public.pasr_event_register(uuid, text, text, text, date, uuid, integer, text, integer),
  public.pasr_event_ticket_public(uuid, text), public.pasr_event_ticket_cancel(uuid, text, text, integer), public.pasr_member_card_public(uuid)
  to anon, authenticated;
