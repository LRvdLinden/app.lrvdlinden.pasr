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
