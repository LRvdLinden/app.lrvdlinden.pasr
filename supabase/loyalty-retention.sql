-- Pasr Zakelijk: automatische terugkomherinneringen, alleen per expliciet geactiveerde klantenkaart.
-- Klanten moeten zelf toestemmen; geen gegevensuitwisseling met ondernemers.
create table if not exists public.pasr_business_retention_consents (
 member_id uuid primary key references public.pasr_business_members(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 enabled boolean not null default false,
 consented_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 last_attempt_at timestamptz,
 last_sent_at timestamptz,
 last_sent_stamp_at timestamptz
);
create index if not exists pasr_retention_enabled on public.pasr_business_retention_consents(enabled,last_attempt_at);
alter table public.pasr_business_retention_consents enable row level security;
revoke all on public.pasr_business_retention_consents from public,anon,authenticated;

create or replace function public.pasr_business_retention_consent(p_code text,p_enabled boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare m public.pasr_business_members; c public.pasr_business_cards;
  b public.pasr_businesses; configured boolean;
begin
 if auth.uid() is null then raise exception 'Log eerst in bij Pasr.' using errcode='28000'; end if;
 select * into m from public.pasr_business_members
  where member_code=upper(trim(p_code)) and user_id=auth.uid();
 if m.id is null then raise exception 'Deze kaart hoort niet bij jouw account.' using errcode='42501'; end if;
 select * into c from public.pasr_business_cards where id=m.business_card_id;
 select * into b from public.pasr_businesses where id=c.business_id;
 select coalesce((p.settings->'retention'->>'enabled')::boolean,false) into configured
  from public.pasr_business_programs p where p.card_id=c.id;
 if p_enabled and (c.published is not true or b.status<>'approved' or not coalesce(configured,false)) then
  raise exception 'De ondernemer heeft geen terugkomherinneringen actief.' using errcode='22023';
 end if;
 insert into public.pasr_business_retention_consents(member_id,user_id,enabled,consented_at,updated_at)
 values(m.id,auth.uid(),coalesce(p_enabled,false),now(),now())
 on conflict(member_id) do update set enabled=excluded.enabled,consented_at=excluded.consented_at,
   updated_at=now(),last_sent_stamp_at=case when excluded.enabled then null else
     public.pasr_business_retention_consents.last_sent_stamp_at end;
 return jsonb_build_object('enabled',coalesce(p_enabled,false),'card_id',c.id);
end $$;

create or replace function public.pasr_business_retention_status(p_code text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m public.pasr_business_members; cfg jsonb;
begin
 if auth.uid() is null then raise exception 'Log eerst in.' using errcode='28000'; end if;
 select * into m from public.pasr_business_members where member_code=upper(trim(p_code)) and user_id=auth.uid();
 if m.id is null then raise exception 'Deze stempelkaart hoort niet bij je account.' using errcode='42501'; end if;
 select settings->'retention' into cfg from public.pasr_business_programs where card_id=m.business_card_id;
 return jsonb_build_object(
   'available',coalesce((cfg->>'enabled')::boolean,false),
   'days',coalesce((cfg->>'days')::int,30),
   'enabled',coalesce((select enabled from public.pasr_business_retention_consents
      where member_id=m.id),false));
end $$;

-- Alleen service_role haalt dagelijkse ontvangers op. Een claim wordt maximaal eenmaal per dag geprobeerd.
-- Na een succesvolle push wordt precies de huidige stempelbeurt gemarkeerd als verzonden.
create or replace function public.pasr_business_retention_due(p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path = '' as $
declare result jsonb;
begin
 if p_limit not between 1 and 100 then raise exception 'Ongeldige limiet.' using errcode='22023'; end if;
 with eligible as (
     select o.member_id
     from public.pasr_business_retention_consents o
     join public.pasr_business_members m on m.id=o.member_id and m.user_id=o.user_id
     join public.pasr_business_cards c on c.id=m.business_card_id and c.published
     join public.pasr_businesses b on b.id=c.business_id and b.status='approved'
     join public.pasr_business_programs cfg on cfg.card_id=c.id
     where o.enabled and coalesce((cfg.settings->'retention'->>'enabled')::boolean,false)
       and m.last_stamp_at is not null
       and m.last_stamp_at < now()-make_interval(days => least(365,greatest(7,
         coalesce((cfg.settings->'retention'->>'days')::int,30))))
       and o.consented_at < now()-interval '1 day'
       and (o.last_attempt_at is null or o.last_attempt_at < now()-interval '23 hours')
       and (o.last_sent_stamp_at is distinct from m.last_stamp_at)
       and (o.last_sent_at is null or o.last_sent_at < now()-interval '30 days')
     order by coalesce(o.last_attempt_at,'epoch'::timestamptz),m.last_stamp_at
     limit p_limit
     for update of o skip locked
   ), claimed as (
     update public.pasr_business_retention_consents o set last_attempt_at=now()
     from eligible e where o.member_id=e.member_id returning o.member_id
   )
   select jsonb_agg(jsonb_build_object(
      'member_id',m.id,'user_id',m.user_id,'stamp_at',m.last_stamp_at,
      'business',b.name,'card',c.name,
      'days',least(365,greatest(7,coalesce((cfg.settings->'retention'->>'days')::int,30)))
   ))
   from claimed a
   join public.pasr_business_members m on m.id=a.member_id
   join public.pasr_business_cards c on c.id=m.business_card_id
   join public.pasr_businesses b on b.id=c.business_id
   join public.pasr_business_programs cfg on cfg.card_id=c.id
 into result;
 return coalesce(result,'[]'::jsonb);
end $;

create or replace function public.pasr_business_retention_sent(p_member uuid,p_stamp timestamptz)
returns boolean language plpgsql security definer set search_path = '' as $$
declare did uuid;
begin
 update public.pasr_business_retention_consents o
  set last_sent_at=now(),last_sent_stamp_at=p_stamp
  where o.member_id=p_member and o.enabled and exists(
    select 1 from public.pasr_business_members m
    where m.id=o.member_id and m.last_stamp_at=p_stamp)
 returning o.member_id into did;
 return did is not null;
end $$;

-- Beveiligde dagelijkse trigger; de admin-edgefunctie controleert het al bestaande hook-secret.
create or replace function public.pasr_business_retention_kick()
returns void language plpgsql security definer set search_path = '' as $$
begin
 perform public.pasr_admin_notify('retention');
end $$;

revoke all on function public.pasr_business_retention_consent(text,boolean),
 public.pasr_business_retention_status(text),
 public.pasr_business_retention_due(integer),
 public.pasr_business_retention_sent(uuid,timestamptz),
 public.pasr_business_retention_kick() from public,anon,authenticated;
grant execute on function public.pasr_business_retention_consent(text,boolean),
 public.pasr_business_retention_status(text) to authenticated;
grant execute on function public.pasr_business_retention_due(integer),
 public.pasr_business_retention_sent(uuid,timestamptz) to service_role;

do $$
begin
 if to_regnamespace('cron') is not null then
   perform cron.schedule('pasr-business-retention', '15 8 * * *',
     'select public.pasr_business_retention_kick()');
 end if;
exception when others then
 raise warning 'pasr-business-retention scheduling: %',sqlerrm;
end $$;
