-- The stamp card archive holds the product summary. Removing the live card
-- immediately invalidates its memberships and links through the existing FKs.
create table if not exists public.pasr_business_card_archive (
  id uuid primary key,
  business_id uuid not null references public.pasr_businesses(id) on delete cascade,
  title text not null,
  deleted_at timestamptz not null default now()
);
alter table public.pasr_business_card_archive enable row level security;
alter table public.pasr_business_coupon_claims add column if not exists hidden_at timestamptz;
alter table public.pasr_business_promo_claims add column if not exists hidden_at timestamptz;

-- Purging an offer also purges its claims. Customer-side hiding preserves claim
-- history and the one-per-customer and usage-limit rules.
alter table public.pasr_business_promo_claims drop constraint if exists pasr_business_promo_claims_promo_id_fkey;
alter table public.pasr_business_promo_claims add constraint pasr_business_promo_claims_promo_id_fkey
  foreign key (promo_id) references public.pasr_business_promo_codes(id) on delete cascade;

create or replace function public.pasr_business_trash(p_business uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not exists (select 1 from public.pasr_businesses where id=p_business and owner=auth.uid()) then
    raise exception 'forbidden' using errcode='42501';
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) order by deleted_at desc), '[]'::jsonb) from (
    select id, title, deleted_at, 'card' as kind from public.pasr_business_card_archive where business_id=p_business
    union all
    select id, title, deleted_at, 'coupon' from public.pasr_business_coupons where business_id=p_business and deleted_at is not null
    union all
    select id, title, deleted_at, 'code' from public.pasr_business_promo_codes where business_id=p_business and deleted_at is not null
  ) x);
end $$;

create or replace function public.pasr_business_delete_items(p_business uuid, p_items jsonb, p_permanent boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare item record;
begin
  -- Serialize batches and verify ownership before touching any records.
  perform 1 from public.pasr_businesses where id=p_business and owner=auth.uid() for update;
  if not found then raise exception 'forbidden' using errcode='42501'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' or p_permanent is null then
    raise exception 'bad_items' using errcode='22023';
  end if;
  for item in select distinct id, kind from jsonb_to_recordset(p_items) as x(id uuid, kind text) order by kind,id loop
    if item.id is null or item.kind is null then raise exception 'bad_items' using errcode='22023'; end if;
    case item.kind
    when 'card' then
      if p_permanent then
        delete from public.pasr_business_card_archive where id=item.id and business_id=p_business;
      else
        with removed as (
          delete from public.pasr_business_cards where id=item.id and business_id=p_business returning id,business_id,name
        )
        insert into public.pasr_business_card_archive(id,business_id,title)
          select id,business_id,name from removed on conflict (id) do nothing;
      end if;
    when 'coupon' then
      if p_permanent then
        delete from public.pasr_business_coupons where id=item.id and business_id=p_business and deleted_at is not null;
      else
        update public.pasr_business_coupons set deleted_at=now(),public=false
          where id=item.id and business_id=p_business and deleted_at is null;
      end if;
    when 'code' then
      if p_permanent then
        delete from public.pasr_business_promo_codes where id=item.id and business_id=p_business and deleted_at is not null;
      else
        update public.pasr_business_promo_codes set deleted_at=now(),active=false,updated_at=now()
          where id=item.id and business_id=p_business and deleted_at is null;
      end if;
    else raise exception 'bad_items' using errcode='22023';
    end case;
  end loop;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.pasr_business_card_delete(p_card uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare business uuid;
begin
  select c.business_id into business from public.pasr_business_cards c join public.pasr_businesses b on b.id=c.business_id
    where c.id=p_card and b.owner=auth.uid();
  if business is null then return jsonb_build_object('ok',true); end if;
  return public.pasr_business_delete_items(business, jsonb_build_array(jsonb_build_object('id',p_card,'kind','card')), false);
end $$;

create or replace function public.pasr_customer_hide_used_offers(p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'forbidden' using errcode='42501'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' then raise exception 'bad_items' using errcode='22023'; end if;
  update public.pasr_business_coupon_claims c set hidden_at=now()
    from jsonb_to_recordset(p_items) as x(id uuid,kind text)
    where c.id=x.id and x.kind='coupon' and c.user_id=uid and c.redeemed_at is not null and c.hidden_at is null;
  update public.pasr_business_promo_claims c set hidden_at=now()
    from jsonb_to_recordset(p_items) as x(id uuid,kind text)
    where c.id=x.id and x.kind='code' and c.user_id=uid and c.redeemed_at is not null and c.hidden_at is null;
  return jsonb_build_object('ok',true);
end $$;

revoke all on function public.pasr_business_trash(uuid), public.pasr_business_delete_items(uuid,jsonb,boolean),
  public.pasr_customer_hide_used_offers(jsonb) from public, anon;
grant execute on function public.pasr_business_trash(uuid), public.pasr_business_delete_items(uuid,jsonb,boolean),
  public.pasr_customer_hide_used_offers(jsonb) to authenticated;

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
 join public.pasr_businesses b on b.id=c.business_id where cc.user_id=auth.uid() and cc.hidden_at is null and c.deleted_at is null;
$$;

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
 where c.user_id=auth.uid() and c.hidden_at is null and p.deleted_at is null;
$$;
