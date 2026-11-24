-- Pasr 2026-11-24: manage published coupons/codes; app-issued personal redemptions.
-- Soft deletion preserves the entire redemption audit history. No direct public coupon/code redemption.
alter table public.pasr_business_coupons add column if not exists deleted_at timestamptz;
alter table public.pasr_business_promo_codes add column if not exists deleted_at timestamptz;
alter table public.pasr_business_promo_codes add column if not exists updated_at timestamptz not null default now();
create table if not exists public.pasr_business_promo_claims (
 id uuid primary key default gen_random_uuid(),
 promo_id uuid not null references public.pasr_business_promo_codes(id) on delete restrict,
 user_id uuid not null references auth.users(id) on delete cascade,
 redeem_code text not null unique check(redeem_code ~ '^PA[A-HJ-NP-Z2-9]{22}$'),
 claimed_at timestamptz not null default now(),
 redeemed_at timestamptz,
 redeemed_by uuid references auth.users(id),
 unique(promo_id,user_id)
);
create index if not exists pasr_promo_claims_user_idx on public.pasr_business_promo_claims(user_id,claimed_at desc);
create index if not exists pasr_promo_claims_promo_idx on public.pasr_business_promo_claims(promo_id,claimed_at);
alter table public.pasr_business_promo_claims enable row level security;
revoke all on public.pasr_business_promo_claims from public,anon,authenticated;

-- Only owner receives full merchant codes; public listing exposes titles, discount and branding, never codes.
create or replace function public.pasr_business_promo_public()
returns jsonb language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'business',b.name,'title',p.title,'discount_type',p.discount_type,
  'discount_value',p.discount_value,'min_spend',p.min_spend,'ends_at',p.ends_at,
  'color',coalesce((select bc.color from public.pasr_business_cards bc
    where bc.business_id=b.id and bc.logo is not null order by bc.created_at limit 1),'#6A5CFF'),
  'logo',(select bc.logo from public.pasr_business_cards bc
    where bc.business_id=b.id and bc.logo is not null order by bc.created_at limit 1),
  'status','active') order by p.ends_at),'[]'::jsonb)
 from public.pasr_business_promo_codes p
 join public.pasr_businesses b on b.id=p.business_id
 where p.active and p.deleted_at is null and b.status='approved' and b.listed
  and now() between p.starts_at and p.ends_at and p.used_count<p.max_uses;
$$;

create or replace function public.pasr_business_coupon_list(p_business uuid default null)
returns jsonb language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object(
   'id',c.id,'business_id',b.id,'business',b.name,'city',b.city,
   'title',c.title,'description',c.description,'discount_type',c.discount_type,
   'discount_value',c.discount_value,'min_spend',c.min_spend,
   'starts_at',c.starts_at,'ends_at',c.ends_at,'max_claims',c.max_claims,
   'one_per_customer',c.one_per_customer,'public',c.public,
   'deleted',c.deleted_at is not null,
   'logo',(select bc.logo from public.pasr_business_cards bc
     where bc.business_id=b.id and bc.logo is not null order by bc.created_at limit 1),
   'color',coalesce((select bc.color from public.pasr_business_cards bc
     where bc.business_id=b.id order by bc.created_at limit 1),'#6A5CFF'),
   'claimed',(select count(*) from public.pasr_business_coupon_claims cc where cc.coupon_id=c.id),
   'redeemed',(select count(*) from public.pasr_business_coupon_claims cc
      where cc.coupon_id=c.id and cc.redeemed_at is not null)) order by c.ends_at),'[]'::jsonb)
 from public.pasr_business_coupons c join public.pasr_businesses b on b.id=c.business_id
 where b.status='approved' and (
   (p_business is not null and c.business_id=p_business and b.owner=auth.uid()) or
   (p_business is null and c.deleted_at is null and c.public and b.listed
    and now() between c.starts_at and c.ends_at));
$$;

create or replace function public.pasr_business_coupon_mine()
returns jsonb language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object(
    'id',cc.id,'coupon_id',c.id,
    'code',case when cc.redeemed_at is null and c.deleted_at is null and c.public
                 and now() between c.starts_at and c.ends_at then cc.redeem_code else null end,
    'title',c.title,'business',b.name,'discount_type',c.discount_type,
    'discount_value',c.discount_value,'description',c.description,
    'min_spend',c.min_spend,'ends_at',c.ends_at,
    'redeemed',cc.redeemed_at is not null,'redeemed_at',cc.redeemed_at,
    'disabled',c.deleted_at is not null or not c.public,
    'logo',(select bc.logo from public.pasr_business_cards bc
       where bc.business_id=b.id and bc.logo is not null order by bc.created_at limit 1),
    'color',coalesce((select bc.color from public.pasr_business_cards bc
       where bc.business_id=b.id order by bc.created_at limit 1),'#6A5CFF'))
  order by cc.claimed_at desc),'[]'::jsonb)
 from public.pasr_business_coupon_claims cc
 join public.pasr_business_coupons c on c.id=cc.coupon_id
 join public.pasr_businesses b on b.id=c.business_id where cc.user_id=auth.uid();
$$;

-- An app user may only claim by public product UUID, never read the merchant's shared code.
create or replace function public.pasr_business_promo_claim(p_promo uuid)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare p public.pasr_business_promo_codes; b public.pasr_businesses;
 c public.pasr_business_promo_claims; alphabet text:='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
 v_code text; raw bytea; i int;
begin
 if auth.uid() is null then raise exception 'Log in bij Pasr.' using errcode='28000'; end if;
 select * into p from public.pasr_business_promo_codes where id=p_promo for update;
 if p.id is null then raise exception 'Actiecode niet gevonden.' using errcode='P0002'; end if;
 select * into b from public.pasr_businesses where id=p.business_id;
 if p.deleted_at is not null or not p.active or b.status<>'approved' or not b.listed
   or now() not between p.starts_at and p.ends_at or p.used_count>=p.max_uses then
   raise exception 'Deze actie is niet beschikbaar.' using errcode='22023';
 end if;
 select * into c from public.pasr_business_promo_claims where promo_id=p.id and user_id=auth.uid();
 if c.id is not null then
   return jsonb_build_object('id',c.id,'redeemed',c.redeemed_at is not null,
      'code',case when c.redeemed_at is null then c.redeem_code else null end);
 end if;
 loop
  v_code:='PA';raw:=gen_random_bytes(22);
  for i in 0..21 loop v_code:=v_code||substr(alphabet,(get_byte(raw,i)%32)+1,1);end loop;
  exit when not exists(select 1 from public.pasr_business_promo_claims where redeem_code=v_code);
 end loop;
 insert into public.pasr_business_promo_claims(promo_id,user_id,redeem_code)
 values(p.id,auth.uid(),v_code) returning * into c;
 return jsonb_build_object('id',c.id,'code',c.redeem_code,'redeemed',false);
end $$;

create or replace function public.pasr_business_promo_mine()
returns jsonb language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',c.id,'promo_id',p.id,'business',b.name,'title',p.title,
  'discount_type',p.discount_type,'discount_value',p.discount_value,
  'min_spend',p.min_spend,'ends_at',p.ends_at,
  'code',case when c.redeemed_at is null and p.active and p.deleted_at is null
    and now() between p.starts_at and p.ends_at then c.redeem_code else null end,
  'redeemed',c.redeemed_at is not null,'redeemed_at',c.redeemed_at,
  'disabled',p.deleted_at is not null or not p.active,
  'logo',(select bc.logo from public.pasr_business_cards bc
   where bc.business_id=b.id and bc.logo is not null order by bc.created_at limit 1),
  'color',coalesce((select bc.color from public.pasr_business_cards bc
   where bc.business_id=b.id order by bc.created_at limit 1),'#6A5CFF'))
  order by c.claimed_at desc),'[]'::jsonb)
 from public.pasr_business_promo_claims c
 join public.pasr_business_promo_codes p on p.id=c.promo_id
 join public.pasr_businesses b on b.id=p.business_id
 where c.user_id=auth.uid();
$$;

-- Merchants scan personal PA tokens. Raw reusable HERFST20 codes are never accepted.
create or replace function public.pasr_business_promo_check(p_code text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare c public.pasr_business_promo_claims; p public.pasr_business_promo_codes; b public.pasr_businesses;
begin
 if auth.uid() is null then raise exception 'Log in als ondernemer.' using errcode='28000'; end if;
 select * into c from public.pasr_business_promo_claims where redeem_code=upper(trim(p_code));
 if c.id is null then return jsonb_build_object('valid',false); end if;
 select * into p from public.pasr_business_promo_codes where id=c.promo_id;
 select * into b from public.pasr_businesses where id=p.business_id;
 if b.owner is distinct from auth.uid() and public.pasr_business_role(b.id) is null then
   raise exception 'Deze code hoort niet bij jouw zaak.' using errcode='42501'; end if;
 return jsonb_build_object('valid',c.redeemed_at is null and p.active and p.deleted_at is null
    and b.status='approved' and now() between p.starts_at and p.ends_at
    and p.used_count<p.max_uses,'used',c.redeemed_at is not null,
    'title',p.title,'discount_type',p.discount_type,'discount_value',p.discount_value,
    'min_spend',p.min_spend,'remaining',p.max_uses-p.used_count,'business',b.name);
end $$;

create or replace function public.pasr_business_promo_redeem(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.pasr_business_promo_claims; p public.pasr_business_promo_codes; b public.pasr_businesses;
begin
 if auth.uid() is null then raise exception 'Log in als ondernemer.' using errcode='28000'; end if;
 select * into c from public.pasr_business_promo_claims where redeem_code=upper(trim(p_code)) for update;
 if c.id is null then raise exception 'Scan de persoonlijke code uit de Pasr-app.' using errcode='P0002'; end if;
 select * into p from public.pasr_business_promo_codes where id=c.promo_id for update;
 select * into b from public.pasr_businesses where id=p.business_id;
 if b.owner is distinct from auth.uid() and public.pasr_business_role(b.id) is null then
   raise exception 'Deze actie hoort niet bij jouw zaak.' using errcode='42501'; end if;
 if c.redeemed_at is not null then raise exception 'Deze code is al gebruikt.' using errcode='22023'; end if;
 if p.deleted_at is not null or not p.active or b.status<>'approved'
   or now() not between p.starts_at and p.ends_at or p.used_count>=p.max_uses then
   raise exception 'Deze actie is niet meer geldig.' using errcode='22023'; end if;
 update public.pasr_business_promo_claims set redeemed_at=now(),redeemed_by=auth.uid() where id=c.id;
 update public.pasr_business_promo_codes set used_count=used_count+1,updated_at=now() where id=p.id;
 return jsonb_build_object('ok',true,'title',p.title,'discount_type',p.discount_type,
   'discount_value',p.discount_value,'min_spend',p.min_spend,'remaining',p.max_uses-p.used_count-1);
end $$;

-- Both remove actions are soft deletes; customer claims and usage audit survive.
create or replace function public.pasr_business_discount_remove(p_business uuid,p_id uuid,p_kind text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare affected int;
begin
 if auth.uid() is null or not exists(select 1 from public.pasr_businesses b
   where b.id=p_business and b.owner=auth.uid()) then
    raise exception 'Alleen de eigenaar mag acties verwijderen.' using errcode='42501'; end if;
 if p_kind='coupon' then
   update public.pasr_business_coupons set deleted_at=now(),public=false
    where id=p_id and business_id=p_business and deleted_at is null;
 elsif p_kind='code' then
   update public.pasr_business_promo_codes set deleted_at=now(),active=false,updated_at=now()
    where id=p_id and business_id=p_business and deleted_at is null;
 else raise exception 'Ongeldig actietype.' using errcode='22023'; end if;
 get diagnostics affected=row_count;
 if affected<>1 then raise exception 'Actie niet gevonden.' using errcode='P0002'; end if;
 return jsonb_build_object('ok',true);
end $$;

-- App-only coupons remain readable publicly without any barcode/code;
-- their claims can't be reused after disabling or removing.
create or replace function public.pasr_business_coupon_check(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.pasr_business_coupon_claims; q public.pasr_business_coupons; b public.pasr_businesses;
begin
 if auth.uid() is null then raise exception 'Log in bij Pasr Zakelijk.' using errcode='28000'; end if;
 select * into c from public.pasr_business_coupon_claims where redeem_code=upper(trim(p_code));
 if c.id is null then raise exception 'Onbekende kortingsbon.' using errcode='P0002'; end if;
 select * into q from public.pasr_business_coupons where id=c.coupon_id;
 select * into b from public.pasr_businesses where id=q.business_id;
 if b.owner is distinct from auth.uid() and public.pasr_business_role(b.id) is null then
   raise exception 'Deze bon hoort niet bij jouw zaak.' using errcode='42501'; end if;
 return jsonb_build_object('business',b.name,'title',q.title,'discount_type',q.discount_type,
  'discount_value',q.discount_value,'min_spend',q.min_spend,
  'valid',c.redeemed_at is null and q.deleted_at is null and q.public
     and now() between q.starts_at and q.ends_at,
  'used',c.redeemed_at is not null);
end $$;

-- Legacy coupon claim/redeem functions are overridden below to enforce soft deletion.
create or replace function public.pasr_business_coupon_claim(p_coupon uuid)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare q public.pasr_business_coupons; b public.pasr_businesses; used int;
 code text; alphabet text:='ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; raw bytea; i int;
 claim public.pasr_business_coupon_claims;
begin
 if auth.uid() is null then raise exception 'Log in bij Pasr.' using errcode='28000'; end if;
 select * into q from public.pasr_business_coupons where id=p_coupon for update;
 if q.id is null then raise exception 'Kortingsbon niet gevonden.' using errcode='P0002'; end if;
 select * into b from public.pasr_businesses where id=q.business_id;
 if q.deleted_at is not null or not q.public or b.status<>'approved' or not b.listed
   or now() not between q.starts_at and q.ends_at then
    raise exception 'Deze kortingsbon is niet beschikbaar.' using errcode='22023'; end if;
 if q.one_per_customer then
  select * into claim from public.pasr_business_coupon_claims
    where coupon_id=q.id and user_id=auth.uid() order by claimed_at desc limit 1;
  if claim.id is not null then
    return jsonb_build_object('id',claim.id,'redeemed',claim.redeemed_at is not null,
      'code',case when claim.redeemed_at is null then claim.redeem_code else null end);
  end if;
 end if;
 select count(*) into used from public.pasr_business_coupon_claims where coupon_id=q.id;
 if used>=q.max_claims then raise exception 'Alle bonnen zijn uitgegeven.' using errcode='22023'; end if;
 loop
  code:='PC';raw:=gen_random_bytes(22);
  for i in 0..21 loop code:=code||substr(alphabet,(get_byte(raw,i)%32)+1,1);end loop;
  exit when not exists(select 1 from public.pasr_business_coupon_claims where redeem_code=code);
 end loop;
 insert into public.pasr_business_coupon_claims(coupon_id,user_id,redeem_code)
  values(q.id,auth.uid(),code) returning * into claim;
 return jsonb_build_object('id',claim.id,'code',claim.redeem_code,'redeemed',false);
end $$;

create or replace function public.pasr_business_coupon_redeem(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.pasr_business_coupon_claims; q public.pasr_business_coupons; b public.pasr_businesses;
begin
 if auth.uid() is null then raise exception 'Log in als ondernemer.' using errcode='28000'; end if;
 select * into c from public.pasr_business_coupon_claims where redeem_code=upper(trim(p_code)) for update;
 if c.id is null then raise exception 'Onbekende kortingsbon.' using errcode='P0002'; end if;
 select * into q from public.pasr_business_coupons where id=c.coupon_id;
 select * into b from public.pasr_businesses where id=q.business_id;
 if b.owner is distinct from auth.uid() and public.pasr_business_role(b.id) is null then
  raise exception 'Deze bon hoort niet bij jouw zaak.' using errcode='42501'; end if;
 if c.redeemed_at is not null then raise exception 'Deze bon is al gebruikt.' using errcode='22023'; end if;
 if q.deleted_at is not null or not q.public or b.status<>'approved'
    or now() not between q.starts_at and q.ends_at then
  raise exception 'Deze kortingsbon is niet geldig.' using errcode='22023'; end if;
 update public.pasr_business_coupon_claims set redeemed_at=now(),redeemed_by=auth.uid() where id=c.id;
 return jsonb_build_object('ok',true,'business',b.name,'title',q.title,
  'discount_type',q.discount_type,'discount_value',q.discount_value,'min_spend',q.min_spend);
end $$;

-- Redeeming must never bypass personal app issue merely by knowing a merchant code.
revoke all on function public.pasr_business_discount_remove(uuid,uuid,text),
 public.pasr_business_promo_public(),public.pasr_business_promo_claim(uuid),
 public.pasr_business_promo_mine() from public,anon;
grant execute on function public.pasr_business_discount_remove(uuid,uuid,text),
 public.pasr_business_promo_claim(uuid), public.pasr_business_promo_mine() to authenticated;
grant execute on function public.pasr_business_promo_public() to anon,authenticated;

-- Prevent undeleting removed offers through the save RPC; expose removal status only to owner.
create or replace function public.pasr_business_coupon_save(p_coupon jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare b public.pasr_businesses; cid uuid; c public.pasr_business_coupons;
  t text; desc_text text; typ text; v numeric; m numeric; st timestamptz; en timestamptz;
  maxn int; pub boolean; onep boolean; linked uuid;
begin
  if auth.uid() is null then raise exception 'Log eerst in.' using errcode='28000'; end if;
  if jsonb_typeof(p_coupon)<>'object' or octet_length(p_coupon::text)>4000 then raise exception 'Ongeldige kortingsbon.' using errcode='22023'; end if;
  select * into b from public.pasr_businesses where id=(p_coupon->>'business_id')::uuid and owner=auth.uid();
  if b.id is null or b.status<>'approved' then raise exception 'Je zaak is niet goedgekeurd.' using errcode='42501'; end if;
  cid:=nullif(p_coupon->>'id','')::uuid;
  t:=trim(coalesce(p_coupon->>'title',''));desc_text:=trim(coalesce(p_coupon->>'description',''));
  typ:=p_coupon->>'discount_type';
  v:=(p_coupon->>'discount_value')::numeric;m:=coalesce((p_coupon->>'min_spend')::numeric,0);
  st:=coalesce((p_coupon->>'starts_at')::timestamptz,now());
  en:=(p_coupon->>'ends_at')::timestamptz;
  maxn:=coalesce((p_coupon->>'max_claims')::int,500);
  onep:=coalesce((p_coupon->>'one_per_customer')::boolean,true);
  pub:=coalesce((p_coupon->>'public')::boolean,false);
  linked:=nullif(p_coupon->>'card_id','')::uuid;
  if linked is not null and not exists(select 1 from public.pasr_business_cards where id=linked and business_id=b.id) then
    raise exception 'Kaart hoort niet bij je zaak.' using errcode='42501';
  end if;
  if char_length(t) not between 3 and 80 or char_length(desc_text)>300 or
     typ not in ('amount','percent') or v<=0 or v > (case when typ='percent' then 100 else 100000 end) or
     m<0 or maxn not between 1 and 100000 or en is null or en<=st or en>st+interval '366 days' then
     raise exception 'Controleer bedrag, tekst en datums.' using errcode='22023';
  end if;
  if cid is null then
    insert into public.pasr_business_coupons(business_id,card_id,title,description,discount_type,discount_value,min_spend,starts_at,ends_at,max_claims,one_per_customer,public)
    values(b.id,linked,t,desc_text,typ,v,m,st,en,maxn,onep,pub) returning * into c;
  else
    update public.pasr_business_coupons set title=t,description=desc_text,card_id=linked,discount_type=typ,
       discount_value=v,min_spend=m,starts_at=st,ends_at=en,max_claims=maxn,one_per_customer=onep,public=pub
    where id=cid and business_id=b.id and deleted_at is null returning * into c;
    if c.id is null then raise exception 'Kortingsbon niet gevonden.' using errcode='P0002'; end if;
  end if;
  return jsonb_build_object('id',c.id,'ok',true);
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
   or v_value<=0 or v_value>(case when v_type='percent' then 100 else 100000 end)
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
   where id=v_id and business_id=biz.id and deleted_at is null and used_count<=v_limit
   returning * into existing;
   if existing.id is null then raise exception 'Actiecode niet gevonden of limiet is te laag.' using errcode='P0002'; end if;
 end if;
 return jsonb_build_object('id',existing.id,'code',existing.code,'ok',true);
exception when unique_violation then
 raise exception 'Deze actiecode bestaat al. Kies een andere code.' using errcode='23505';
end $$;


create or replace function public.pasr_business_promo_list(p_business uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not exists(select 1 from public.pasr_businesses b where b.id=p_business and b.owner=auth.uid()) then
   raise exception 'Alleen de eigenaar mag actiecodes beheren.' using errcode='42501';
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
   'id',p.id,'code',p.code,'title',p.title,'discount_type',p.discount_type,
   'discount_value',p.discount_value,'min_spend',p.min_spend,
   'starts_at',p.starts_at,'ends_at',p.ends_at,'max_uses',p.max_uses,
   'used_count',p.used_count,'active',p.active,'deleted',p.deleted_at is not null,
   'logo',(select bc.logo from public.pasr_business_cards bc
      where bc.business_id=p.business_id and bc.logo is not null order by bc.created_at limit 1),
   'color',coalesce((select bc.color from public.pasr_business_cards bc
      where bc.business_id=p.business_id order by bc.created_at limit 1),'#6A5CFF'))
   order by p.created_at desc) from public.pasr_business_promo_codes p
   where p.business_id=p_business),'[]'::jsonb);
end $$;
