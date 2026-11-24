-- Pasr Zakelijk: gezamenlijke winkelstraatacties.
-- Additief, zonder wijzigingen aan bestaande stempelstromen.
-- Ondernemers moeten ieder afzonderlijk opt-in geven; alle klantinzichten zijn eigen-account-only.
create table if not exists public.pasr_business_community_campaigns (
  id uuid primary key default gen_random_uuid(),
  lead_business_id uuid not null references public.pasr_businesses(id) on delete cascade,
  name text not null check(char_length(name) between 3 and 80),
  reward text not null check(char_length(reward) between 3 and 120),
  required_businesses integer not null check(required_businesses between 2 and 20),
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  check(ends_at > starts_at and ends_at <= starts_at + interval '366 days')
);
create index if not exists pasr_community_campaign_expiry on public.pasr_business_community_campaigns(ends_at);
alter table public.pasr_business_community_campaigns enable row level security;
revoke all on public.pasr_business_community_campaigns from public,anon,authenticated;

create table if not exists public.pasr_business_community_participants (
  campaign_id uuid not null references public.pasr_business_community_campaigns(id) on delete cascade,
  business_id uuid not null references public.pasr_businesses(id) on delete cascade,
  accepted_at timestamptz not null default now(),
  accepted_by uuid not null references auth.users(id),
  primary key(campaign_id,business_id)
);
create index if not exists pasr_community_participants_business on public.pasr_business_community_participants(business_id);
alter table public.pasr_business_community_participants enable row level security;
revoke all on public.pasr_business_community_participants from public,anon,authenticated;

create table if not exists public.pasr_business_community_claims (
  campaign_id uuid not null references public.pasr_business_community_campaigns(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  issued_at timestamptz not null default now(),
  issued_by uuid not null references auth.users(id),
  issued_at_business uuid not null references public.pasr_businesses(id),
  primary key(campaign_id,user_id)
);
alter table public.pasr_business_community_claims enable row level security;
revoke all on public.pasr_business_community_claims from public,anon,authenticated;

-- De initiatiefnemer bepaalt doel en beloning, en neemt automatisch deel.
create or replace function public.pasr_business_community_create(
  p_business uuid,p_name text,p_reward text,p_required integer,p_days integer default 60)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_owner uuid := auth.uid();
begin
  if v_owner is null or not exists(
    select 1 from public.pasr_businesses b
    where b.id=p_business and b.owner=v_owner and b.status='approved') then
    raise exception 'Alleen een goedgekeurde ondernemer kan een actie starten.' using errcode='42501';
  end if;
  if char_length(trim(p_name)) not between 3 and 80
     or char_length(trim(p_reward)) not between 3 and 120
     or p_required not between 2 and 20 or p_days not between 1 and 366 then
    raise exception 'Controleer naam, beloning, aantal ondernemingen en looptijd.' using errcode='22023';
  end if;
  if (select count(*) from public.pasr_business_community_campaigns
      where lead_business_id=p_business and ends_at>now() and cancelled_at is null)>=10 then
    raise exception 'Maximaal tien lopende gezamenlijke acties.' using errcode='22023';
  end if;
  insert into public.pasr_business_community_campaigns(
    lead_business_id,name,reward,required_businesses,ends_at)
  values(p_business,trim(p_name),trim(p_reward),p_required,now()+make_interval(days=>p_days))
  returning id into v_id;
  insert into public.pasr_business_community_participants(campaign_id,business_id,accepted_by)
  values(v_id,p_business,v_owner);
  return jsonb_build_object('id',v_id,'ok',true);
end $$;

-- Ondernemers kiezen zelf om mee te doen; een andere ondernemer kan niet voor hen tekenen.
create or replace function public.pasr_business_community_join(p_business uuid,p_campaign uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.pasr_business_community_campaigns;
begin
  if auth.uid() is null or not exists(
    select 1 from public.pasr_businesses b
    where b.id=p_business and b.owner=auth.uid() and b.status='approved') then
    raise exception 'Alleen de eigenaar kan namens de zaak deelnemen.' using errcode='42501';
  end if;
  select * into c from public.pasr_business_community_campaigns
    where id=p_campaign and ends_at>now() and cancelled_at is null for update;
  if c.id is null then raise exception 'Actie is verlopen of niet beschikbaar.' using errcode='22023'; end if;
  if (select count(*) from public.pasr_business_community_participants
      where campaign_id=c.id)>=30 then
    raise exception 'Maximum aantal deelnemende ondernemingen bereikt.' using errcode='22023';
  end if;
  insert into public.pasr_business_community_participants(campaign_id,business_id,accepted_by)
  values(p_campaign,p_business,auth.uid()) on conflict do nothing;
  return jsonb_build_object('ok',true,'joined',true,'campaign_id',p_campaign);
end $$;

-- Alleen de eigenaar van de opgevraagde onderneming kan samenwerkingen bekijken.
create or replace function public.pasr_business_community_list(p_business uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists(
    select 1 from public.pasr_businesses b where b.id=p_business and b.owner=auth.uid()) then
    raise exception 'Geen toegang tot de samenwerkingen.' using errcode='42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',c.id,'name',c.name,'reward',c.reward,'required',c.required_businesses,
    'ends_at',c.ends_at,'lead_business',b.name,
    'participants',(select count(*) from public.pasr_business_community_participants p where p.campaign_id=c.id),
    'joined',exists(select 1 from public.pasr_business_community_participants p
                    where p.campaign_id=c.id and p.business_id=p_business))
    order by c.created_at desc)
    from public.pasr_business_community_campaigns c
    join public.pasr_businesses b on b.id=c.lead_business_id
    where c.ends_at>now() and c.cancelled_at is null and b.status='approved'), '[]'::jsonb);
end $$;

-- Klant ziet uitsluitend eigen voortgang, gebaseerd op stempels van deelnemende zaken.
create or replace function public.pasr_business_community_progress()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Log in om je winkelstraatacties te zien.' using errcode='28000'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',c.id,'name',c.name,'reward',c.reward,'required',c.required_businesses,
    'visited',(
       select count(distinct p.business_id) from public.pasr_business_community_participants p
       join public.pasr_business_events e on e.business_id=p.business_id
       join public.pasr_business_members m on m.id=e.member_id
       where p.campaign_id=c.id and m.user_id=auth.uid() and e.kind='stamp'
         and e.amount>0 and e.undone_at is null
         and e.at>=greatest(c.starts_at,p.accepted_at) and e.at<=c.ends_at
    ),
    'claimed',exists(select 1 from public.pasr_business_community_claims cl
                     where cl.campaign_id=c.id and cl.user_id=auth.uid()))
    order by c.ends_at)
    from public.pasr_business_community_campaigns c
    where c.ends_at>now() and c.cancelled_at is null
      and exists(select 1 from public.pasr_business_community_participants p
        join public.pasr_business_members m on m.user_id=auth.uid()
        join public.pasr_business_cards card on card.id=m.business_card_id and card.business_id=p.business_id
        where p.campaign_id=c.id)),'[]'::jsonb);
end $$;

-- Alleen bevoegd personeel bij deelnemende zaken kan de beloning uitgeven.
-- Een klant kan nooit eigen claims aanmaken en een beloning kan maar één keer worden uitgegeven.
create or replace function public.pasr_business_community_claim(
 p_campaign uuid,p_business uuid,p_member_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.pasr_business_community_campaigns; v_user uuid; v_count integer;
begin
  if auth.uid() is null or public.pasr_business_role(p_business) is null then
    raise exception 'Alleen bevoegd personeel kan beloningen uitgeven.' using errcode='42501';
  end if;
  select * into c from public.pasr_business_community_campaigns
    where id=p_campaign and starts_at<=now() and ends_at>now()
      and cancelled_at is null for update;
  if c.id is null or not exists(select 1 from public.pasr_business_community_participants
                                where campaign_id=p_campaign and business_id=p_business) then
    raise exception 'Actie niet geldig bij deze onderneming.' using errcode='22023';
  end if;
  select m.user_id into v_user
    from public.pasr_business_members m
    join public.pasr_business_cards card on card.id=m.business_card_id
    where m.member_code=upper(trim(p_member_code)) and card.business_id=p_business;
  if v_user is null then
    raise exception 'De klant moet een gekoppeld Pasr-account en een kaart van deze onderneming hebben.' using errcode='22023';
  end if;
  select count(distinct p.business_id) into v_count
    from public.pasr_business_community_participants p
    join public.pasr_business_events e on e.business_id=p.business_id
    join public.pasr_business_members m on m.id=e.member_id
    where p.campaign_id=c.id and m.user_id=v_user and e.kind='stamp'
      and e.amount>0 and e.undone_at is null
      and e.at>=greatest(c.starts_at,p.accepted_at) and e.at<=c.ends_at;
  if v_count<c.required_businesses then
    raise exception 'Nog niet genoeg verschillende deelnemende winkels bezocht.' using errcode='22023';
  end if;
  insert into public.pasr_business_community_claims(
    campaign_id,user_id,issued_by,issued_at_business)
  values(c.id,v_user,auth.uid(),p_business) on conflict do nothing;
  if not found then raise exception 'Deze beloning is al uitgegeven.' using errcode='22023'; end if;
  return jsonb_build_object('ok',true,'reward',c.reward,'visited',v_count,'required',c.required_businesses);
end $$;

revoke all on function public.pasr_business_community_create(uuid,text,text,integer,integer),
 public.pasr_business_community_join(uuid,uuid),
 public.pasr_business_community_list(uuid),
 public.pasr_business_community_progress(),
 public.pasr_business_community_claim(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.pasr_business_community_create(uuid,text,text,integer,integer),
 public.pasr_business_community_join(uuid,uuid),
 public.pasr_business_community_list(uuid),
 public.pasr_business_community_progress(),
 public.pasr_business_community_claim(uuid,uuid,text) to authenticated;
