-- VIP-beloningsvoordelen configureerbaar per niveau, zonder persoonsgegevens in bedrijfsinzichten.
create or replace function public.pasr_business_vip_status(p_code text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare m public.pasr_business_members; c public.pasr_business_cards; b public.pasr_businesses;
  cfg jsonb; visits int; silver int; gold int; tier text; next_at int; benefit text;
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
  benefit:=case when visits>=gold then nullif(trim(cfg->>'gold_benefit'),'')
                when visits>=silver then nullif(trim(cfg->>'silver_benefit'),'')
                else null end;
  return jsonb_build_object('enabled',true,'tier',tier,'visits',visits,
    'silver_from',silver,'gold_from',gold,'next_at',next_at,
    'benefit',left(coalesce(benefit,''),120));
end $$;
revoke all on function public.pasr_business_vip_status(text) from public;
grant execute on function public.pasr_business_vip_status(text) to anon,authenticated;


