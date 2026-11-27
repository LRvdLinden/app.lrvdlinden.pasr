-- Pasr Zakelijk: gezamenlijke acties op uitnodiging (27-11-2026). Draait na supabase/loyalty-community.sql
-- (workflow Backend stuurt beide in één verzoek). Idempotent: alles is "if not exists" / "create or replace".
-- Contract met de apps: docs/community-invites.md.
--
-- Wat er verandert:
--  * een zaak doet alleen nog mee na een uitnodiging van de organisator (of, als de organisator dat aanzet, als zaak in
--    dezelfde plaats via pasr_business_community_join);
--  * uitnodigen kan op naam/plaats (bestaande zaak) of met een e-mail/link/QR (zaak die nog niet in Pasr zit, 14 dagen);
--  * een actie start pas als min_participants zaken meedoen (organisator telt mee); daarvoor ziet de klant niets en kan
--    er niets worden uitgegeven;
--  * elke gebeurtenis komt in een outbox: de functie community-mail mailt (Pasr-huisstijl) en de functie admin pusht
--    naar de apparaten van Pasr Zakelijk van de betrokken zaak.
-- Foutcodes (exception message): invite_required, not_owner, already_participant, invite_not_found, invite_expired.

-- ---------------------------------------------------------------------------------------------------------- tabellen
alter table public.pasr_business_community_campaigns add column if not exists invite_only boolean not null default true;
alter table public.pasr_business_community_campaigns add column if not exists open_same_city boolean not null default false;
alter table public.pasr_business_community_campaigns add column if not exists min_participants integer not null default 2;
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public'
                 and table_name = 'pasr_business_community_campaigns' and column_name = 'activated_at') then
    alter table public.pasr_business_community_campaigns add column activated_at timestamptz;
    -- bestaande acties met genoeg deelnemers liepen al: zonder meldingen als gestart markeren
    update public.pasr_business_community_campaigns c set activated_at = c.starts_at
     where (select count(*) from public.pasr_business_community_participants p where p.campaign_id = c.id) >= c.min_participants;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pasr_community_min_participants_check') then
    alter table public.pasr_business_community_campaigns add constraint pasr_community_min_participants_check
      check (min_participants between 2 and 30);
  end if;
end $$;

create table if not exists public.pasr_business_community_invites (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.pasr_business_community_campaigns(id) on delete cascade,
  business_id uuid references public.pasr_businesses(id) on delete cascade,   -- leeg bij een link/e-mail tot hij is gebruikt
  email text check (email is null or (char_length(email) between 3 and 200 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  token_hash text unique check (token_hash is null or token_hash ~ '^[0-9a-f]{64}$'),   -- sha256 van het token, nooit het token
  status text not null default 'invited' check (status in ('invited', 'accepted', 'declined', 'revoked')),
  organizer boolean not null default false,
  invited_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  responded_at timestamptz,
  check (business_id is not null or token_hash is not null)
);
create unique index if not exists pasr_community_invites_one on public.pasr_business_community_invites(campaign_id, business_id)
  where business_id is not null and status in ('invited', 'accepted');
create index if not exists pasr_community_invites_open on public.pasr_business_community_invites(business_id) where status = 'invited';
create index if not exists pasr_community_invites_campaign on public.pasr_business_community_invites(campaign_id, created_at);
alter table public.pasr_business_community_invites enable row level security;
revoke all on public.pasr_business_community_invites from public, anon, authenticated;

-- Bestaande deelnemers (van voor de uitnodigingen) als geaccepteerd, de initiatiefnemer als organisator.
insert into public.pasr_business_community_invites(campaign_id, business_id, status, organizer, invited_by, created_at, responded_at)
select p.campaign_id, p.business_id, 'accepted', c.lead_business_id = p.business_id, p.accepted_by, p.accepted_at, p.accepted_at
  from public.pasr_business_community_participants p
  join public.pasr_business_community_campaigns c on c.id = p.campaign_id
 where not exists (select 1 from public.pasr_business_community_invites i
                   where i.campaign_id = p.campaign_id and i.business_id = p.business_id and i.status = 'accepted');

-- Outbox: één rij per ontvanger en gebeurtenis. community-mail mailt, admin pusht; beide markeren wat ze deden.
create table if not exists public.pasr_business_community_outbox (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('invite', 'invite_email', 'accepted', 'declined', 'active', 'removed', 'revoked')),
  campaign_id uuid not null references public.pasr_business_community_campaigns(id) on delete cascade,
  invite_id uuid references public.pasr_business_community_invites(id) on delete set null,
  business_id uuid references public.pasr_businesses(id) on delete cascade,          -- ontvangende zaak
  email text,                                                                         -- ontvanger zonder zaak
  actor_business_id uuid references public.pasr_businesses(id) on delete set null,   -- wie het deed (leeg = beheer)
  secret text,                                                                        -- token voor de link, weg na mailen
  created_at timestamptz not null default now(),
  attempts integer not null default 0,
  mail_claimed_at timestamptz,
  mailed_at timestamptz,
  push_attempts integer not null default 0,
  push_claimed_at timestamptz,
  pushed_at timestamptz
);
create index if not exists pasr_community_outbox_mail on public.pasr_business_community_outbox(id) where mailed_at is null;
create index if not exists pasr_community_outbox_push on public.pasr_business_community_outbox(id) where pushed_at is null;
alter table public.pasr_business_community_outbox enable row level security;
revoke all on public.pasr_business_community_outbox from public, anon, authenticated;

do $$
begin
  if to_regclass('public.pasr_admin_config') is not null then
    alter table public.pasr_admin_config add column if not exists community_url text;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------- intern
-- Aantal zaken dat meedoet (organisator telt mee).
create or replace function public.pasr_business_community_accepted(p_campaign uuid) returns integer
language plpgsql stable security definer set search_path = '' as $$
begin
  return (select count(*)::integer from public.pasr_business_community_participants p where p.campaign_id = p_campaign);
end $$;

-- waiting | active | ended | cancelled
create or replace function public.pasr_business_community_state(p_campaign uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare c public.pasr_business_community_campaigns;
begin
  select * into c from public.pasr_business_community_campaigns where id = p_campaign;
  if c.id is null then return null; end if;
  if c.cancelled_at is not null then return 'cancelled'; end if;
  if c.ends_at <= now() then return 'ended'; end if;
  if public.pasr_business_community_accepted(c.id) < c.min_participants then return 'waiting'; end if;
  return 'active';
end $$;

create or replace function public.pasr_business_community_hash(p_token text) returns text
language sql immutable set search_path = '' as $$
  select encode(pg_catalog.sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex');
$$;

-- Eigenaar (of medewerker met eigenaarsrol) van een goedgekeurde zaak; anders not_owner.
create or replace function public.pasr_business_community_need_owner(p_business uuid) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or public.pasr_business_role(p_business) is distinct from 'owner'
     or not exists (select 1 from public.pasr_businesses b where b.id = p_business and b.status = 'approved') then
    raise exception 'not_owner' using errcode = '42501', hint = 'not_owner';
  end if;
end $$;

-- De lopende actie van deze organisator, op slot; anders not_owner (of invite_not_found als hij niet meer loopt).
create or replace function public.pasr_business_community_need_lead(p_business uuid, p_campaign uuid)
returns public.pasr_business_community_campaigns
language plpgsql security definer set search_path = '' as $$
declare c public.pasr_business_community_campaigns;
begin
  perform public.pasr_business_community_need_owner(p_business);
  select * into c from public.pasr_business_community_campaigns where id = p_campaign for update;
  if c.id is null or c.lead_business_id is distinct from p_business then
    raise exception 'not_owner' using errcode = '42501', hint = 'not_owner';
  end if;
  if c.cancelled_at is not null or c.ends_at <= now() then
    raise exception 'invite_not_found' using errcode = 'P0002', hint = 'invite_not_found';
  end if;
  return c;
end $$;

create or replace function public.pasr_business_community_enqueue(p_kind text, p_campaign uuid, p_invite uuid,
  p_business uuid, p_email text, p_actor uuid, p_secret text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_business is null and p_email is null then return; end if;
  insert into public.pasr_business_community_outbox(kind, campaign_id, invite_id, business_id, email, actor_business_id, secret, pushed_at)
  values (p_kind, p_campaign, p_invite, p_business, lower(trim(p_email)), p_actor, p_secret,
          case when p_business is null then now() end);   -- zonder zaak geen apparaten: niets te pushen
end $$;

-- Minimum bereikt? Eén keer een melding "actie is gestart" aan alle deelnemers.
create or replace function public.pasr_business_community_check_active(p_campaign uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare c public.pasr_business_community_campaigns; r record;
begin
  select * into c from public.pasr_business_community_campaigns where id = p_campaign for update;
  if c.id is null or c.activated_at is not null or c.cancelled_at is not null or c.ends_at <= now()
     or public.pasr_business_community_accepted(c.id) < c.min_participants then
    return false;
  end if;
  update public.pasr_business_community_campaigns set activated_at = now() where id = c.id;
  for r in select p.business_id from public.pasr_business_community_participants p where p.campaign_id = c.id loop
    perform public.pasr_business_community_enqueue('active', c.id, null, r.business_id, null, c.lead_business_id);
  end loop;
  return true;
end $$;

-- Seintje aan de functies (pg_net verstuurt pas na de commit). Fouten houden een actie nooit tegen.
create or replace function public.pasr_business_community_kick() returns void
language plpgsql security definer set search_path = '' as $$
declare u text; s text;
begin
  begin
    perform public.pasr_admin_notify('community', '{}'::jsonb);
  exception when others then raise warning 'community push kick: %', sqlerrm;
  end;
  begin
    select community_url into u from public.pasr_admin_config where id = 1;
    select hook_secret into s from public.pasr_secret where id = 1;
    if coalesce(u, '') <> '' and s is not null then
      perform net.http_post(url := u, body := jsonb_build_object('action', 'run'),
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-pasr-hook', s),
        timeout_milliseconds := 30000);
    end if;
  exception when others then raise warning 'community mail kick: %', sqlerrm;
  end;
end $$;

create or replace function public.pasr_business_community_outbox_kick() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.pasr_business_community_kick();
  return null;
end $$;
drop trigger if exists pasr_business_community_outbox_kick on public.pasr_business_community_outbox;
create trigger pasr_business_community_outbox_kick after insert on public.pasr_business_community_outbox
  for each statement execute function public.pasr_business_community_outbox_kick();

-- Vangnet: elke 10 minuten opnieuw proberen wat nog openstaat; oude rijen na 30 dagen weg.
create or replace function public.pasr_business_community_cron() returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.pasr_business_community_outbox where created_at < now() - interval '30 days';
  if exists (select 1 from public.pasr_business_community_outbox
             where (mailed_at is null and attempts < 5) or (pushed_at is null and push_attempts < 5)) then
    perform public.pasr_business_community_kick();
  end if;
end $$;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'pasr-community-outbox';
  perform cron.schedule('pasr-community-outbox', '*/10 * * * *', 'select public.pasr_business_community_cron()');
exception when others then
  raise notice 'pg_cron niet beschikbaar: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------------------------------------- aanmaken
drop function if exists public.pasr_business_community_create(uuid, text, text, integer, integer);
create or replace function public.pasr_business_community_create(
  p_business uuid, p_name text, p_reward text, p_required integer, p_days integer default 60,
  p_open_same_city boolean default false, p_min_participants integer default 2)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_owner uuid := auth.uid(); v_min integer := coalesce(p_min_participants, 2);
begin
  if v_owner is null or public.pasr_business_role(p_business) is distinct from 'owner' or not exists(
    select 1 from public.pasr_businesses b where b.id = p_business and b.status = 'approved') then
    raise exception 'Alleen een goedgekeurde ondernemer kan een actie starten.' using errcode = '42501', hint = 'not_owner';
  end if;
  if char_length(trim(coalesce(p_name, ''))) not between 3 and 80
     or char_length(trim(coalesce(p_reward, ''))) not between 3 and 120
     or p_required not between 2 and 20 or p_days not between 1 and 366 or v_min not between 2 and 30 then
    raise exception 'Controleer naam, beloning, aantal ondernemingen, minimum aantal deelnemers en looptijd.' using errcode = '22023';
  end if;
  if (select count(*) from public.pasr_business_community_campaigns
      where lead_business_id = p_business and ends_at > now() and cancelled_at is null) >= 10 then
    raise exception 'Maximaal tien lopende gezamenlijke acties.' using errcode = '22023';
  end if;
  insert into public.pasr_business_community_campaigns(
    lead_business_id, name, reward, required_businesses, ends_at, invite_only, open_same_city, min_participants)
  values (p_business, trim(p_name), trim(p_reward), p_required, now() + make_interval(days => p_days),
          not coalesce(p_open_same_city, false), coalesce(p_open_same_city, false), v_min)
  returning id into v_id;
  insert into public.pasr_business_community_participants(campaign_id, business_id, accepted_by)
  values (v_id, p_business, v_owner);
  insert into public.pasr_business_community_invites(campaign_id, business_id, status, organizer, invited_by, responded_at)
  values (v_id, p_business, 'accepted', true, v_owner, now());
  return jsonb_build_object('id', v_id, 'ok', true, 'state', 'waiting', 'min_participants', v_min,
                            'open_same_city', coalesce(p_open_same_city, false));
end $$;

-- Extra (niet in het contract nodig, wel handig): instellingen van een lopende actie wijzigen (organisator).
create or replace function public.pasr_business_community_settings(p_business uuid, p_campaign uuid,
  p_open_same_city boolean default null, p_min_participants integer default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.pasr_business_community_campaigns;
begin
  c := public.pasr_business_community_need_lead(p_business, p_campaign);
  if p_min_participants is not null and p_min_participants not between 2 and 30 then
    raise exception 'Het minimum aantal deelnemers is 2 tot 30.' using errcode = '22023';
  end if;
  update public.pasr_business_community_campaigns
     set open_same_city = coalesce(p_open_same_city, open_same_city),
         invite_only = not coalesce(p_open_same_city, open_same_city),
         min_participants = coalesce(p_min_participants, min_participants)
   where id = c.id;
  perform public.pasr_business_community_check_active(c.id);
  select * into c from public.pasr_business_community_campaigns where id = p_campaign;
  return jsonb_build_object('ok', true, 'open_same_city', c.open_same_city, 'invite_only', c.invite_only,
    'min_participants', c.min_participants, 'accepted_count', public.pasr_business_community_accepted(c.id),
    'state', public.pasr_business_community_state(c.id));
end $$;

-- ---------------------------------------------------------------------------------------------------------- lijst
create or replace function public.pasr_business_community_list(p_business uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_role text;
begin
  v_role := public.pasr_business_role(p_business);
  if auth.uid() is null or v_role is null then
    raise exception 'Geen toegang tot de samenwerkingen.' using errcode = '42501', hint = 'not_owner';
  end if;
  return coalesce((select jsonb_agg(x.j order by x.live desc, x.created_at desc) from (
    select c.created_at, (c.cancelled_at is null and c.ends_at > now()) live, jsonb_build_object(
      'id', c.id, 'name', c.name, 'reward', c.reward, 'required', c.required_businesses,
      'starts_at', c.starts_at, 'ends_at', c.ends_at, 'cancelled_at', c.cancelled_at,
      'lead_business', b.name, 'lead_city', b.city,
      'is_lead', c.lead_business_id = p_business,
      'role', case when c.lead_business_id = p_business then 'owner' else 'participant' end,
      'invite_only', c.invite_only, 'open_same_city', c.open_same_city, 'min_participants', c.min_participants,
      'accepted_count', public.pasr_business_community_accepted(c.id),
      'state', public.pasr_business_community_state(c.id),
      'activated_at', c.activated_at,
      'participants', public.pasr_business_community_accepted(c.id),
      'participant_names', coalesce((select jsonb_agg(pb.name order by p.accepted_at)
          from public.pasr_business_community_participants p
          join public.pasr_businesses pb on pb.id = p.business_id where p.campaign_id = c.id), '[]'::jsonb),
      'pending_invites', case when c.lead_business_id = p_business then
          (select count(*) from public.pasr_business_community_invites i
            where i.campaign_id = c.id and i.status = 'invited' and (i.expires_at is null or i.expires_at > now())) else 0 end,
      'joined', true,
      'claims_here', (select count(*) from public.pasr_business_community_claims cl
                      where cl.campaign_id = c.id and cl.issued_at_business = p_business),
      'can_manage', v_role = 'owner') j
    from public.pasr_business_community_campaigns c
    join public.pasr_businesses b on b.id = c.lead_business_id
    where exists (select 1 from public.pasr_business_community_participants p
                  where p.campaign_id = c.id and p.business_id = p_business)
      and ((c.cancelled_at is null and c.ends_at > now() - interval '30 days')
           or c.cancelled_at > now() - interval '30 days')) x), '[]'::jsonb);
end $$;

-- Extra: acties in dezelfde plaats die open staan voor zaken uit die plaats (meedoen met pasr_business_community_join).
create or replace function public.pasr_business_community_open(p_business uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_city text;
begin
  if auth.uid() is null or public.pasr_business_role(p_business) is null then
    raise exception 'not_owner' using errcode = '42501', hint = 'not_owner';
  end if;
  select lower(trim(b.city)) into v_city from public.pasr_businesses b where b.id = p_business and b.status = 'approved';
  if coalesce(v_city, '') = '' then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'name', c.name, 'reward', c.reward, 'required', c.required_businesses,
      'starts_at', c.starts_at, 'ends_at', c.ends_at, 'lead_business', b.name, 'lead_city', b.city,
      'min_participants', c.min_participants, 'accepted_count', public.pasr_business_community_accepted(c.id),
      'state', public.pasr_business_community_state(c.id),
      'participant_names', coalesce((select jsonb_agg(pb.name order by p.accepted_at)
          from public.pasr_business_community_participants p
          join public.pasr_businesses pb on pb.id = p.business_id where p.campaign_id = c.id), '[]'::jsonb))
      order by c.ends_at)
    from public.pasr_business_community_campaigns c
    join public.pasr_businesses b on b.id = c.lead_business_id
    where c.open_same_city and c.cancelled_at is null and c.ends_at > now() and b.status = 'approved'
      and lower(trim(b.city)) = v_city and c.lead_business_id <> p_business
      and not exists (select 1 from public.pasr_business_community_participants p
                      where p.campaign_id = c.id and p.business_id = p_business)), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------------------------------------- uitnodigen
create or replace function public.pasr_business_community_search(p_business uuid, p_campaign uuid, p_query text)
returns table (business_id uuid, name text, city text, logo_url text, invite_status text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare q text := nullif(lower(left(regexp_replace(trim(coalesce(p_query, '')), '\s+', ' ', 'g'), 60)), '');
begin
  perform public.pasr_business_community_need_owner(p_business);
  if not exists (select 1 from public.pasr_business_community_campaigns c
                 where c.id = p_campaign and c.lead_business_id = p_business) then
    raise exception 'not_owner' using errcode = '42501', hint = 'not_owner';
  end if;
  return query
  select b.id, b.name::text, b.city::text,
         (select case when card.logo is not null and octet_length(card.logo) <= 40000 then
                   'data:image/' || case when card.logo like '/9j/%' then 'jpeg' else 'png' end || ';base64,' || card.logo end
            from public.pasr_business_cards card
           where card.business_id = b.id and card.logo is not null
           order by card.published desc, card.created_at limit 1)::text,
         (select i.status from public.pasr_business_community_invites i
           where i.campaign_id = p_campaign and i.business_id = b.id
           order by (i.status in ('invited', 'accepted')) desc, i.created_at desc limit 1)::text
    from public.pasr_businesses b
   where b.status = 'approved' and b.listed and b.id <> p_business
     and (q is null or strpos(lower(b.name || ' ' || b.city), q) > 0)
   order by (q is not null and lower(b.name) like q || '%') desc, lower(b.name), lower(b.city)
   limit 25;
end $$;

create or replace function public.pasr_business_community_invite(p_business uuid, p_campaign uuid, p_target uuid)
returns json language plpgsql security definer set search_path = '' as $$
declare c public.pasr_business_community_campaigns; v_id uuid; v_status text;
begin
  c := public.pasr_business_community_need_lead(p_business, p_campaign);
  if p_target is null or p_target = p_business
     or not exists (select 1 from public.pasr_businesses b where b.id = p_target and b.status = 'approved') then
    raise exception 'invite_not_found' using errcode = 'P0002', hint = 'invite_not_found';
  end if;
  if exists (select 1 from public.pasr_business_community_participants p where p.campaign_id = c.id and p.business_id = p_target) then
    raise exception 'already_participant' using errcode = '23505', hint = 'already_participant';
  end if;
  select i.id, i.status into v_id, v_status from public.pasr_business_community_invites i
   where i.campaign_id = c.id and i.business_id = p_target and i.status = 'invited';
  if v_id is not null then return json_build_object('invite_id', v_id, 'status', v_status); end if;
  if (select count(*) from public.pasr_business_community_invites i
       where i.campaign_id = c.id and i.created_at > now() - interval '1 day' and not i.organizer) >= 50 then
    raise exception 'Te veel uitnodigingen vandaag. Probeer het morgen opnieuw.' using errcode = '22023', hint = 'rate_limited';
  end if;
  insert into public.pasr_business_community_invites(campaign_id, business_id, status, invited_by)
  values (c.id, p_target, 'invited', auth.uid()) returning id into v_id;
  perform public.pasr_business_community_enqueue('invite', c.id, v_id, p_target, null, p_business);
  return json_build_object('invite_id', v_id, 'status', 'invited');
end $$;

create or replace function public.pasr_business_community_invite_email(p_business uuid, p_campaign uuid, p_email text)
returns json language plpgsql security definer set search_path = '' as $$
declare c public.pasr_business_community_campaigns; v_id uuid; v_token text; v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
begin
  c := public.pasr_business_community_need_lead(p_business, p_campaign);
  if v_email is not null and (char_length(v_email) > 200 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'Vul een geldig e-mailadres in.' using errcode = '22023', hint = 'bad_email';
  end if;
  if (select count(*) from public.pasr_business_community_invites i
       where i.campaign_id = c.id and i.created_at > now() - interval '1 day' and not i.organizer) >= 50 then
    raise exception 'Te veel uitnodigingen vandaag. Probeer het morgen opnieuw.' using errcode = '22023', hint = 'rate_limited';
  end if;
  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.pasr_business_community_invites(campaign_id, email, token_hash, status, invited_by, expires_at)
  values (c.id, v_email, public.pasr_business_community_hash(v_token), 'invited', auth.uid(), now() + interval '14 days')
  returning id into v_id;
  if v_email is not null then
    perform public.pasr_business_community_enqueue('invite_email', c.id, v_id, null, v_email, p_business, v_token);
  end if;
  return json_build_object('invite_id', v_id, 'token', v_token,
                           'link', 'https://pasr.nl/zakelijk/uitnodiging/?t=' || v_token);
end $$;

create or replace function public.pasr_business_community_invites(p_business uuid, p_campaign uuid)
returns table (invite_id uuid, business_id uuid, name text, city text, email text, status text, created_at timestamptz,
               expires_at timestamptz, organizer boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare v_lead boolean;
begin
  if auth.uid() is null or public.pasr_business_role(p_business) is null then
    raise exception 'not_owner' using errcode = '42501', hint = 'not_owner';
  end if;
  select c.lead_business_id = p_business into v_lead from public.pasr_business_community_campaigns c where c.id = p_campaign;
  if v_lead is null or (not v_lead and not exists (select 1 from public.pasr_business_community_participants p
                                                   where p.campaign_id = p_campaign and p.business_id = p_business)) then
    raise exception 'not_owner' using errcode = '42501', hint = 'not_owner';
  end if;
  return query
  select i.id, i.business_id, coalesce(b.name, i.email, 'Uitnodigingslink')::text, coalesce(b.city, '')::text,
         case when v_lead then i.email end::text, i.status, i.created_at, i.expires_at, i.organizer
    from public.pasr_business_community_invites i
    left join public.pasr_businesses b on b.id = i.business_id
   where i.campaign_id = p_campaign and (v_lead or i.status = 'accepted')
   order by i.organizer desc, i.created_at;
end $$;

create or replace function public.pasr_business_community_revoke(p_business uuid, p_invite uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare i public.pasr_business_community_invites;
begin
  select * into i from public.pasr_business_community_invites where id = p_invite for update;
  if i.id is null then raise exception 'invite_not_found' using errcode = 'P0002', hint = 'invite_not_found'; end if;
  perform public.pasr_business_community_need_lead(p_business, i.campaign_id);
  if i.status <> 'invited' then raise exception 'invite_not_found' using errcode = 'P0002', hint = 'invite_not_found'; end if;
  update public.pasr_business_community_invites set status = 'revoked', responded_at = now() where id = i.id;
  perform public.pasr_business_community_enqueue('revoked', i.campaign_id, i.id, i.business_id,
    case when i.business_id is null then i.email end, p_business);
end $$;

create or replace function public.pasr_business_community_remove(p_business uuid, p_campaign uuid, p_target uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare c public.pasr_business_community_campaigns;
begin
  c := public.pasr_business_community_need_lead(p_business, p_campaign);
  if p_target is null or p_target = p_business then
    raise exception 'not_owner' using errcode = '42501', hint = 'not_owner';
  end if;
  delete from public.pasr_business_community_participants where campaign_id = c.id and business_id = p_target;
  if not found then raise exception 'invite_not_found' using errcode = 'P0002', hint = 'invite_not_found'; end if;
  update public.pasr_business_community_invites set status = 'revoked', responded_at = now()
   where campaign_id = c.id and business_id = p_target and status in ('invited', 'accepted');
  perform public.pasr_business_community_enqueue('removed', c.id, null, p_target, null, p_business);
end $$;

-- ---------------------------------------------------------------------------------------------------------- reageren
create or replace function public.pasr_business_community_my_invites(p_business uuid)
returns table (invite_id uuid, campaign_id uuid, title text, reward text, starts_at timestamptz, ends_at timestamptz,
               initiator_name text, participant_names text[], initiator_city text, required integer,
               min_participants integer, accepted_count integer, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  if auth.uid() is null or public.pasr_business_role(p_business) is null then
    raise exception 'not_owner' using errcode = '42501', hint = 'not_owner';
  end if;
  return query
  select i.id, c.id, c.name, c.reward, c.starts_at, c.ends_at, lb.name::text,
         coalesce((select array_agg(pb.name::text order by p.accepted_at)
                     from public.pasr_business_community_participants p
                     join public.pasr_businesses pb on pb.id = p.business_id where p.campaign_id = c.id), '{}'::text[]),
         lb.city::text, c.required_businesses, c.min_participants, public.pasr_business_community_accepted(c.id), i.created_at
    from public.pasr_business_community_invites i
    join public.pasr_business_community_campaigns c on c.id = i.campaign_id
    join public.pasr_businesses lb on lb.id = c.lead_business_id
   where i.business_id = p_business and i.status = 'invited' and not i.organizer
     and c.cancelled_at is null and c.ends_at > now() and lb.status = 'approved'
   order by i.created_at desc;
end $$;

-- Intern: deze zaak doet nu mee (na accepteren, token of open meedoen).
create or replace function public.pasr_business_community_add(p_campaign uuid, p_business uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if public.pasr_business_community_accepted(p_campaign) >= 30 then
    raise exception 'Maximum aantal deelnemende ondernemingen bereikt.' using errcode = '22023', hint = 'full';
  end if;
  insert into public.pasr_business_community_participants(campaign_id, business_id, accepted_by)
  values (p_campaign, p_business, auth.uid()) on conflict do nothing;
end $$;

create or replace function public.pasr_business_community_respond(p_business uuid, p_invite uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare i public.pasr_business_community_invites; c public.pasr_business_community_campaigns;
begin
  perform public.pasr_business_community_need_owner(p_business);
  select * into i from public.pasr_business_community_invites where id = p_invite for update;
  if i.id is null or i.business_id is distinct from p_business or i.status <> 'invited' or i.organizer then
    raise exception 'invite_not_found' using errcode = 'P0002', hint = 'invite_not_found';
  end if;
  if i.expires_at is not null and i.expires_at <= now() then
    raise exception 'invite_expired' using errcode = '22023', hint = 'invite_expired';
  end if;
  select * into c from public.pasr_business_community_campaigns where id = i.campaign_id for update;
  if c.cancelled_at is not null or c.ends_at <= now() then
    raise exception 'invite_expired' using errcode = '22023', hint = 'invite_expired';
  end if;
  if coalesce(p_accept, false) then
    perform public.pasr_business_community_add(c.id, p_business);
    update public.pasr_business_community_invites set status = 'accepted', responded_at = now() where id = i.id;
    perform public.pasr_business_community_enqueue('accepted', c.id, i.id, c.lead_business_id, null, p_business);
    perform public.pasr_business_community_check_active(c.id);
  else
    update public.pasr_business_community_invites set status = 'declined', responded_at = now() where id = i.id;
    perform public.pasr_business_community_enqueue('declined', c.id, i.id, c.lead_business_id, null, p_business);
  end if;
end $$;

create or replace function public.pasr_business_community_accept_token(p_business uuid, p_token text)
returns json language plpgsql security definer set search_path = '' as $$
declare i public.pasr_business_community_invites; c public.pasr_business_community_campaigns;
begin
  perform public.pasr_business_community_need_owner(p_business);
  if coalesce(p_token, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invite_not_found' using errcode = 'P0002', hint = 'invite_not_found';
  end if;
  select * into i from public.pasr_business_community_invites
   where token_hash = public.pasr_business_community_hash(p_token) for update;
  if i.id is null or i.status in ('revoked', 'declined') or (i.status = 'accepted' and i.business_id is distinct from p_business) then
    raise exception 'invite_not_found' using errcode = 'P0002', hint = 'invite_not_found';
  end if;
  select * into c from public.pasr_business_community_campaigns where id = i.campaign_id for update;
  if c.lead_business_id = p_business
     or exists (select 1 from public.pasr_business_community_participants p where p.campaign_id = c.id and p.business_id = p_business) then
    raise exception 'already_participant' using errcode = '23505', hint = 'already_participant';
  end if;
  if (i.expires_at is not null and i.expires_at <= now()) or c.cancelled_at is not null or c.ends_at <= now() then
    raise exception 'invite_expired' using errcode = '22023', hint = 'invite_expired';
  end if;
  perform public.pasr_business_community_add(c.id, p_business);
  -- een eerdere uitnodiging op naam voor deze zaak vervalt: deze link is nu de uitnodiging
  update public.pasr_business_community_invites set status = 'revoked', responded_at = now()
   where campaign_id = c.id and business_id = p_business and status = 'invited' and id <> i.id;
  update public.pasr_business_community_invites set business_id = p_business, status = 'accepted', responded_at = now()
   where id = i.id;
  perform public.pasr_business_community_enqueue('accepted', c.id, i.id, c.lead_business_id, null, p_business);
  perform public.pasr_business_community_check_active(c.id);
  return json_build_object('campaign_id', c.id);
end $$;

-- Openbaar (ook zonder account): wat de uitnodigingspagina laat zien. Alleen titel, beloning, looptijd, organisator
-- en deelnemers; nooit e-mailadressen.
create or replace function public.pasr_business_community_invite_preview(p_token text)
returns json language plpgsql stable security definer set search_path = '' as $$
declare i public.pasr_business_community_invites; c public.pasr_business_community_campaigns; v_status text;
begin
  if coalesce(p_token, '') !~ '^[0-9a-f]{64}$' then return json_build_object('status', 'not_found'); end if;
  select * into i from public.pasr_business_community_invites where token_hash = public.pasr_business_community_hash(p_token);
  if i.id is null then return json_build_object('status', 'not_found'); end if;
  select * into c from public.pasr_business_community_campaigns where id = i.campaign_id;
  v_status := case
    when i.status = 'accepted' then 'used'
    when i.status <> 'invited' then 'revoked'
    when c.cancelled_at is not null or c.ends_at <= now() or (i.expires_at is not null and i.expires_at <= now()) then 'expired'
    else 'invited' end;
  return json_build_object(
    'status', v_status, 'campaign_id', c.id, 'title', c.name, 'reward', c.reward,
    'starts_at', c.starts_at, 'ends_at', c.ends_at,
    'initiator_name', (select b.name from public.pasr_businesses b where b.id = c.lead_business_id),
    'participant_names', coalesce((select json_agg(pb.name order by p.accepted_at)
        from public.pasr_business_community_participants p
        join public.pasr_businesses pb on pb.id = p.business_id where p.campaign_id = c.id), '[]'::json));
end $$;

-- ---------------------------------------------------------------------------------------------------------- meedoen / uitstappen
-- Meedoen zonder uitnodiging kan alleen bij een actie die open staat voor zaken in dezelfde plaats als de organisator.
-- Staat er een uitnodiging klaar, dan telt dit als accepteren.
create or replace function public.pasr_business_community_join(p_business uuid, p_campaign uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.pasr_business_community_campaigns; v_invite uuid; v_city text; v_lead_city text;
begin
  perform public.pasr_business_community_need_owner(p_business);
  select * into c from public.pasr_business_community_campaigns
   where id = p_campaign and ends_at > now() and cancelled_at is null for update;
  if c.id is null then raise exception 'Actie is verlopen of niet beschikbaar.' using errcode = '22023'; end if;
  if exists (select 1 from public.pasr_business_community_participants p where p.campaign_id = c.id and p.business_id = p_business) then
    return jsonb_build_object('ok', true, 'joined', true, 'campaign_id', p_campaign);
  end if;
  select i.id into v_invite from public.pasr_business_community_invites i
   where i.campaign_id = c.id and i.business_id = p_business and i.status = 'invited';
  if v_invite is not null then
    perform public.pasr_business_community_respond(p_business, v_invite, true);
    return jsonb_build_object('ok', true, 'joined', true, 'campaign_id', p_campaign);
  end if;
  select lower(trim(b.city)) into v_city from public.pasr_businesses b where b.id = p_business;
  select lower(trim(b.city)) into v_lead_city from public.pasr_businesses b where b.id = c.lead_business_id;
  if not c.open_same_city or coalesce(v_city, '') = '' or v_city is distinct from v_lead_city then
    raise exception 'invite_required' using errcode = '42501', hint = 'invite_required';
  end if;
  perform public.pasr_business_community_add(c.id, p_business);
  insert into public.pasr_business_community_invites(campaign_id, business_id, status, invited_by, responded_at)
  values (c.id, p_business, 'accepted', auth.uid(), now());
  perform public.pasr_business_community_enqueue('accepted', c.id, null, c.lead_business_id, null, p_business);
  perform public.pasr_business_community_check_active(c.id);
  return jsonb_build_object('ok', true, 'joined', true, 'campaign_id', p_campaign);
end $$;

create or replace function public.pasr_business_community_leave(p_business uuid, p_campaign uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or public.pasr_business_role(p_business) is distinct from 'owner' then
    raise exception 'Alleen de eigenaar kan namens de zaak uitstappen.' using errcode = '42501', hint = 'not_owner';
  end if;
  if exists (select 1 from public.pasr_business_community_campaigns where id = p_campaign and lead_business_id = p_business) then
    raise exception 'Je bent initiatiefnemer: stop de actie in plaats van uit te stappen.' using errcode = '22023';
  end if;
  delete from public.pasr_business_community_participants where campaign_id = p_campaign and business_id = p_business;
  if not found then
    raise exception 'Je onderneming neemt niet deel aan deze actie.' using errcode = '22023';
  end if;
  update public.pasr_business_community_invites set status = 'declined', responded_at = now()
   where campaign_id = p_campaign and business_id = p_business and status = 'accepted';
  return jsonb_build_object('ok', true, 'joined', false, 'campaign_id', p_campaign);
end $$;

-- ---------------------------------------------------------------------------------------------------------- klant en kassa
-- Alleen acties met genoeg deelnemers (state active) tellen; de klant ziet alleen deelnemende zaken.
create or replace function public.pasr_business_community_progress()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Log in om je winkelstraatacties te zien.' using errcode = '28000'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', c.id, 'name', c.name, 'reward', c.reward, 'required', c.required_businesses, 'ends_at', c.ends_at,
    'visited', public.pasr_business_community_visits(c.id, auth.uid()),
    'claimed', exists(select 1 from public.pasr_business_community_claims cl
                      where cl.campaign_id = c.id and cl.user_id = auth.uid()),
    'businesses', coalesce((select jsonb_agg(jsonb_build_object(
        'name', pb.name, 'city', pb.city,
        'visited', exists(select 1 from public.pasr_business_events e
                          join public.pasr_business_members m on m.id = e.member_id
                          where e.business_id = p.business_id and m.user_id = auth.uid() and e.kind = 'stamp'
                            and e.amount > 0 and e.undone_at is null
                            and e.at >= greatest(c.starts_at, p.accepted_at) and e.at <= c.ends_at))
        order by pb.name)
        from public.pasr_business_community_participants p
        join public.pasr_businesses pb on pb.id = p.business_id
        where p.campaign_id = c.id), '[]'::jsonb))
    order by c.ends_at)
    from public.pasr_business_community_campaigns c
    where c.ends_at > now() and c.cancelled_at is null
      and public.pasr_business_community_accepted(c.id) >= c.min_participants
      and exists(select 1 from public.pasr_business_community_participants p
        join public.pasr_business_members m on m.user_id = auth.uid()
        join public.pasr_business_cards card on card.id = m.business_card_id and card.business_id = p.business_id
        where p.campaign_id = c.id)), '[]'::jsonb);
end $$;

create or replace function public.pasr_business_community_member(p_business uuid, p_member_code text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_user uuid;
begin
  if auth.uid() is null or public.pasr_business_role(p_business) is null then
    raise exception 'Je hoort niet bij deze zaak.' using errcode = '42501';
  end if;
  select m.user_id into v_user
    from public.pasr_business_members m
    join public.pasr_business_cards card on card.id = m.business_card_id
   where m.member_code = upper(trim(coalesce(p_member_code, ''))) and card.business_id = p_business;
  if v_user is null then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', c.id, 'name', c.name, 'reward', c.reward, 'required', c.required_businesses, 'ends_at', c.ends_at,
    'visited', public.pasr_business_community_visits(c.id, v_user),
    'claimed', exists(select 1 from public.pasr_business_community_claims cl
                      where cl.campaign_id = c.id and cl.user_id = v_user))
    order by c.ends_at)
    from public.pasr_business_community_campaigns c
    join public.pasr_business_community_participants own on own.campaign_id = c.id and own.business_id = p_business
   where c.starts_at <= now() and c.ends_at > now() and c.cancelled_at is null
     and public.pasr_business_community_accepted(c.id) >= c.min_participants), '[]'::jsonb);
end $$;

create or replace function public.pasr_business_community_claim(p_campaign uuid, p_business uuid, p_member_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.pasr_business_community_campaigns; v_user uuid; v_count integer;
begin
  if auth.uid() is null or public.pasr_business_role(p_business) is null then
    raise exception 'Alleen bevoegd personeel kan beloningen uitgeven.' using errcode = '42501';
  end if;
  select * into c from public.pasr_business_community_campaigns
   where id = p_campaign and starts_at <= now() and ends_at > now() and cancelled_at is null for update;
  if c.id is null or not exists(select 1 from public.pasr_business_community_participants
                                where campaign_id = p_campaign and business_id = p_business) then
    raise exception 'Actie niet geldig bij deze onderneming.' using errcode = '22023';
  end if;
  if public.pasr_business_community_accepted(c.id) < c.min_participants then
    raise exception 'Deze actie is nog niet gestart: er doen nog te weinig zaken mee.' using errcode = '22023', hint = 'waiting';
  end if;
  select m.user_id into v_user
    from public.pasr_business_members m
    join public.pasr_business_cards card on card.id = m.business_card_id
   where m.member_code = upper(trim(p_member_code)) and card.business_id = p_business;
  if v_user is null then
    raise exception 'De klant moet een gekoppeld Pasr-account en een kaart van deze onderneming hebben.' using errcode = '22023';
  end if;
  v_count := public.pasr_business_community_visits(c.id, v_user);
  if v_count < c.required_businesses then
    raise exception 'Nog niet genoeg verschillende deelnemende winkels bezocht.' using errcode = '22023';
  end if;
  insert into public.pasr_business_community_claims(campaign_id, user_id, issued_by, issued_at_business)
  values (c.id, v_user, auth.uid(), p_business) on conflict do nothing;
  if not found then raise exception 'Deze beloning is al uitgegeven.' using errcode = '22023'; end if;
  return jsonb_build_object('ok', true, 'reward', c.reward, 'visited', v_count, 'required', c.required_businesses);
end $$;

-- ---------------------------------------------------------------------------------------------------------- outbox (service role)
-- Ontvanger van een zaak: het e-mailadres van de zaak, anders dat van het account van de eigenaar.
create or replace function public.pasr_business_community_mail_due(p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_ids bigint[];
begin
  with picked as (
    select o.id from public.pasr_business_community_outbox o
     where o.mailed_at is null and o.attempts < 5 and o.created_at > now() - interval '3 days'
       and (o.mail_claimed_at is null or o.mail_claimed_at < now() - interval '10 minutes')
     order by o.id limit least(greatest(coalesce(p_limit, 50), 1), 200)
     for update skip locked)
  , claimed as (
  update public.pasr_business_community_outbox o set mail_claimed_at = now(), attempts = o.attempts + 1
    from picked where o.id = picked.id returning o.id)
  select array_agg(claimed.id) into v_ids from claimed;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', o.id, 'kind', o.kind,
      'to', case when o.business_id is not null
                 then coalesce(nullif(trim(rb.email), ''), (select u.email from auth.users u where u.id = rb.owner)::text)
                 else o.email end,
      'business', rb.name,
      'actor', ab.name, 'actor_city', ab.city,
      'link', case when o.secret is not null then 'https://pasr.nl/zakelijk/uitnodiging/?t=' || o.secret end,
      'campaign', jsonb_build_object('id', c.id, 'title', c.name, 'reward', c.reward, 'starts_at', c.starts_at,
          'ends_at', c.ends_at, 'required', c.required_businesses, 'min_participants', c.min_participants,
          'accepted_count', public.pasr_business_community_accepted(c.id),
          'organizer', lb.name, 'organizer_city', lb.city),
      'participant_names', coalesce((select jsonb_agg(pb.name order by p.accepted_at)
          from public.pasr_business_community_participants p
          join public.pasr_businesses pb on pb.id = p.business_id where p.campaign_id = c.id), '[]'::jsonb))
      order by o.id)
    from public.pasr_business_community_outbox o
    join public.pasr_business_community_campaigns c on c.id = o.campaign_id
    join public.pasr_businesses lb on lb.id = c.lead_business_id
    left join public.pasr_businesses rb on rb.id = o.business_id
    left join public.pasr_businesses ab on ab.id = o.actor_business_id
   where o.id = any(coalesce(v_ids, '{}'))), '[]'::jsonb);
end $$;

create or replace function public.pasr_business_community_mail_sent(p_ids bigint[]) returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  update public.pasr_business_community_outbox set mailed_at = now(), secret = null where id = any(coalesce(p_ids, '{}'));
  get diagnostics n = row_count;
  return n;
end $$;

-- Apparaten van Pasr Zakelijk van de ontvangende zaak: eigenaar en medewerkers met eigenaarsrol; bij "actie gestart"
-- ook gewone medewerkers (zij geven de beloning uit).
create or replace function public.pasr_business_community_push_due(p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_ids bigint[];
begin
  with picked as (
    select o.id from public.pasr_business_community_outbox o
     where o.pushed_at is null and o.business_id is not null and o.push_attempts < 5 and o.created_at > now() - interval '3 days'
       and (o.push_claimed_at is null or o.push_claimed_at < now() - interval '10 minutes')
     order by o.id limit least(greatest(coalesce(p_limit, 50), 1), 200)
     for update skip locked)
  , claimed as (
  update public.pasr_business_community_outbox o set push_claimed_at = now(), push_attempts = o.push_attempts + 1
    from picked where o.id = picked.id returning o.id)
  select array_agg(claimed.id) into v_ids from claimed;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', o.id, 'kind', o.kind, 'campaign', c.id, 'business_id', o.business_id, 'title', c.name, 'reward', c.reward,
      'actor', ab.name,
      'devices', coalesce((select jsonb_agg(jsonb_build_object('device_id', d.device_id, 'token', d.push_token,
                                'provider', d.push_provider, 'sandbox', d.push_sandbox))
          from public.pasr_devices d
         where d.app = 'zakelijk' and d.push_token is not null and d.push_provider in ('apns', 'fcm')
           and d.user_id in (
             select rb.owner from public.pasr_businesses rb where rb.id = o.business_id
             union
             select s.user_id from public.pasr_business_staff s
              where s.business_id = o.business_id and s.revoked_at is null and s.user_id is not null
                and (s.role = 'owner' or o.kind = 'active'))), '[]'::jsonb))
      order by o.id)
    from public.pasr_business_community_outbox o
    join public.pasr_business_community_campaigns c on c.id = o.campaign_id
    left join public.pasr_businesses ab on ab.id = o.actor_business_id
   where o.id = any(coalesce(v_ids, '{}'))), '[]'::jsonb);
end $$;

create or replace function public.pasr_business_community_push_sent(p_ids bigint[]) returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  update public.pasr_business_community_outbox set pushed_at = now() where id = any(coalesce(p_ids, '{}'));
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------------------------------------------------- beheer (functie admin)
create or replace function public.pasr_admin_community_detail(p_campaign uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare c public.pasr_business_community_campaigns;
begin
  select * into c from public.pasr_business_community_campaigns where id = p_campaign;
  if c.id is null then return null; end if;
  return jsonb_build_object(
    'campaign', jsonb_build_object('id', c.id, 'name', c.name, 'reward', c.reward, 'required', c.required_businesses,
       'starts_at', c.starts_at, 'ends_at', c.ends_at, 'cancelled_at', c.cancelled_at, 'activated_at', c.activated_at,
       'invite_only', c.invite_only, 'open_same_city', c.open_same_city, 'min_participants', c.min_participants,
       'accepted_count', public.pasr_business_community_accepted(c.id), 'state', public.pasr_business_community_state(c.id),
       'lead_business_id', c.lead_business_id,
       'lead_business', (select b.name from public.pasr_businesses b where b.id = c.lead_business_id),
       'claims', (select count(*) from public.pasr_business_community_claims x where x.campaign_id = c.id)),
    'participants', coalesce((select jsonb_agg(jsonb_build_object('business_id', p.business_id, 'name', b.name, 'city', b.city,
         'accepted_at', p.accepted_at, 'organizer', p.business_id = c.lead_business_id) order by p.accepted_at)
       from public.pasr_business_community_participants p join public.pasr_businesses b on b.id = p.business_id
      where p.campaign_id = c.id), '[]'::jsonb),
    'invites', coalesce((select jsonb_agg(jsonb_build_object('invite_id', i.id, 'business_id', i.business_id,
         'name', coalesce(b.name, i.email, 'Uitnodigingslink'), 'city', coalesce(b.city, ''), 'email', i.email,
         'status', i.status, 'created_at', i.created_at, 'expires_at', i.expires_at, 'responded_at', i.responded_at,
         'organizer', i.organizer, 'link', i.token_hash is not null) order by i.organizer desc, i.created_at)
       from public.pasr_business_community_invites i left join public.pasr_businesses b on b.id = i.business_id
      where i.campaign_id = c.id), '[]'::jsonb));
end $$;

create or replace function public.pasr_admin_community_revoke(p_invite uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare i public.pasr_business_community_invites;
begin
  select * into i from public.pasr_business_community_invites where id = p_invite for update;
  if i.id is null or i.status <> 'invited' then raise exception 'not_found' using errcode = 'P0002'; end if;
  update public.pasr_business_community_invites set status = 'revoked', responded_at = now() where id = i.id;
  perform public.pasr_business_community_enqueue('revoked', i.campaign_id, i.id, i.business_id,
    case when i.business_id is null then i.email end, null);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.pasr_admin_community_remove(p_campaign uuid, p_business uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.pasr_business_community_campaigns where id = p_campaign and lead_business_id = p_business) then
    raise exception 'is_lead' using errcode = '22023';
  end if;
  delete from public.pasr_business_community_participants where campaign_id = p_campaign and business_id = p_business;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  update public.pasr_business_community_invites set status = 'revoked', responded_at = now()
   where campaign_id = p_campaign and business_id = p_business and status in ('invited', 'accepted');
  perform public.pasr_business_community_enqueue('removed', p_campaign, null, p_business, null, null);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------------------------------------- rechten
revoke all on function public.pasr_business_community_accepted(uuid), public.pasr_business_community_state(uuid),
  public.pasr_business_community_hash(text), public.pasr_business_community_need_owner(uuid),
  public.pasr_business_community_need_lead(uuid, uuid),
  public.pasr_business_community_enqueue(text, uuid, uuid, uuid, text, uuid, text),
  public.pasr_business_community_check_active(uuid), public.pasr_business_community_kick(),
  public.pasr_business_community_outbox_kick(), public.pasr_business_community_cron(),
  public.pasr_business_community_add(uuid, uuid),
  public.pasr_business_community_mail_due(integer), public.pasr_business_community_mail_sent(bigint[]),
  public.pasr_business_community_push_due(integer), public.pasr_business_community_push_sent(bigint[]),
  public.pasr_admin_community_detail(uuid), public.pasr_admin_community_revoke(uuid),
  public.pasr_admin_community_remove(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.pasr_business_community_mail_due(integer), public.pasr_business_community_mail_sent(bigint[]),
  public.pasr_business_community_push_due(integer), public.pasr_business_community_push_sent(bigint[]),
  public.pasr_admin_community_detail(uuid), public.pasr_admin_community_revoke(uuid),
  public.pasr_admin_community_remove(uuid, uuid)
  to service_role;

revoke all on function public.pasr_business_community_create(uuid, text, text, integer, integer, boolean, integer),
  public.pasr_business_community_settings(uuid, uuid, boolean, integer),
  public.pasr_business_community_list(uuid), public.pasr_business_community_open(uuid),
  public.pasr_business_community_search(uuid, uuid, text), public.pasr_business_community_invite(uuid, uuid, uuid),
  public.pasr_business_community_invite_email(uuid, uuid, text), public.pasr_business_community_invites(uuid, uuid),
  public.pasr_business_community_revoke(uuid, uuid), public.pasr_business_community_remove(uuid, uuid, uuid),
  public.pasr_business_community_my_invites(uuid), public.pasr_business_community_respond(uuid, uuid, boolean),
  public.pasr_business_community_accept_token(uuid, text), public.pasr_business_community_invite_preview(text),
  public.pasr_business_community_join(uuid, uuid), public.pasr_business_community_leave(uuid, uuid),
  public.pasr_business_community_progress(), public.pasr_business_community_member(uuid, text),
  public.pasr_business_community_claim(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.pasr_business_community_create(uuid, text, text, integer, integer, boolean, integer),
  public.pasr_business_community_settings(uuid, uuid, boolean, integer),
  public.pasr_business_community_list(uuid), public.pasr_business_community_open(uuid),
  public.pasr_business_community_search(uuid, uuid, text), public.pasr_business_community_invite(uuid, uuid, uuid),
  public.pasr_business_community_invite_email(uuid, uuid, text), public.pasr_business_community_invites(uuid, uuid),
  public.pasr_business_community_revoke(uuid, uuid), public.pasr_business_community_remove(uuid, uuid, uuid),
  public.pasr_business_community_my_invites(uuid), public.pasr_business_community_respond(uuid, uuid, boolean),
  public.pasr_business_community_accept_token(uuid, text),
  public.pasr_business_community_join(uuid, uuid), public.pasr_business_community_leave(uuid, uuid),
  public.pasr_business_community_progress(), public.pasr_business_community_member(uuid, text),
  public.pasr_business_community_claim(uuid, uuid, text)
  to authenticated;
grant execute on function public.pasr_business_community_invite_preview(text) to anon, authenticated;
