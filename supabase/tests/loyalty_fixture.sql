-- Alleen testomgeving, geen productiedata.
create extension if not exists pgcrypto;
create role anon;
create role authenticated;
create role service_role;
create schema auth;
create table auth.users(id uuid primary key);
create or replace function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('app.user_id',true),'')::uuid
$$;
create table public.pasr_businesses (
 id uuid primary key default gen_random_uuid(),
 owner uuid not null references auth.users(id),
 name text not null, status text not null default 'approved',
 listed boolean not null default true,
 max_per_scan int not null default 1,
 cooldown_minutes int not null default 0
);
create table public.pasr_business_cards (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.pasr_businesses(id),
 name text not null,
 logo text, color text not null default '#6A5CFF',
 published boolean not null default true,
 stamps_total int not null default 10
);
create table public.pasr_business_members (
 id uuid primary key default gen_random_uuid(),
 business_card_id uuid not null references public.pasr_business_cards(id),
 user_id uuid references auth.users(id),
 member_code text unique not null,
 stamps_count int not null default 0,
 rewards_redeemed int not null default 0,
 last_stamp_at timestamptz,
 updated_at timestamptz not null default now()
);
create table public.pasr_business_events (
 event_id uuid primary key default gen_random_uuid(),
 business_card_id uuid references public.pasr_business_cards(id),
 business_id uuid not null references public.pasr_businesses(id),
 member_id uuid references public.pasr_business_members(id),
 kind text not null,
 amount integer default 1,
 by_user uuid,
 device text,
 stamps_before int,
 stamps_after int,
 undone_at timestamptz,
 at timestamptz not null default now()
);
create table public.pasr_business_programs (
 card_id uuid primary key references public.pasr_business_cards(id),
 settings jsonb not null default '{}'::jsonb
);
create or replace function public.pasr_business_role(p_business uuid)
returns text language sql stable as $$
 select 'owner'::text from public.pasr_businesses b
 where b.id=p_business and b.owner=auth.uid()
$$;
create or replace function public.pasr_business_scan_member(p_code text)
returns table(m public.pasr_business_members,c public.pasr_business_cards,b public.pasr_businesses)
language sql stable as $$
 select m,c,b from public.pasr_business_members m
 join public.pasr_business_cards c on c.id=m.business_card_id
 join public.pasr_businesses b on b.id=c.business_id
 where m.member_code=upper(trim(p_code)) and b.owner=auth.uid()
$$;
create or replace function public.pasr_business_referral_award_internal(
 p_member uuid,p_business uuid,p_card uuid) returns jsonb
language sql as $$ select '{}'::jsonb $$;
create or replace function public.pasr_business_scan_json(
 p_member public.pasr_business_members,p_card public.pasr_business_cards,
 p_business public.pasr_businesses,p_event uuid default null)
returns jsonb language sql as $$
 select jsonb_build_object('member_code',p_member.member_code,'stamps',p_member.stamps_count,
   'event_id',p_event)
$$;
create or replace function public.pasr_admin_notify(p_kind text,p_extra jsonb default '{}'::jsonb)
returns void language sql as $$ select null::void $$;

insert into auth.users(id) values
('11111111-1111-4111-8111-111111111111'),
('22222222-2222-4222-8222-222222222222'),
('33333333-3333-4333-8333-333333333333');
insert into public.pasr_businesses(id,owner,name,max_per_scan) values
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','De Koffiehoek',1),
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','22222222-2222-4222-8222-222222222222','De Bakkerij',1);
insert into public.pasr_business_cards(id,business_id,name) values
('cccccccc-cccc-4ccc-8ccc-cccccccccccc','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Koffiekaart'),
('dddddddd-dddd-4ddd-8ddd-dddddddddddd','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Bakkerkaart');
insert into public.pasr_business_members(id,business_card_id,user_id,member_code,last_stamp_at)
values
('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','cccccccc-cccc-4ccc-8ccc-cccccccccccc',
 '33333333-3333-4333-8333-333333333333','PZABCDEF2345',now()-interval '31 days'),
('ffffffff-ffff-4fff-8fff-ffffffffffff','dddddddd-dddd-4ddd-8ddd-dddddddddddd',
 '33333333-3333-4333-8333-333333333333','PZABCDEF6789',now()-interval '31 days');
insert into public.pasr_business_programs(card_id,settings) values
('cccccccc-cccc-4ccc-8ccc-cccccccccccc',
 '{"retention":{"enabled":true,"days":30},"campaign":{"enabled":true,"weekday":-1,"multiplier":2}}'),
('dddddddd-dddd-4ddd-8ddd-dddddddddddd',
 '{"retention":{"enabled":false}}');

-- Coupon model used by production app-only discount migrations.
create table public.pasr_business_coupons(
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.pasr_businesses(id),
 card_id uuid references public.pasr_business_cards(id),
 title text not null,description text not null default '',
 discount_type text not null,discount_value numeric not null,
 min_spend numeric not null default 0,starts_at timestamptz not null,
 ends_at timestamptz not null,max_claims int not null default 500,
 one_per_customer boolean not null default true,
 public boolean not null default false,
 created_at timestamptz not null default now()
);
create table public.pasr_business_coupon_claims(
 id uuid primary key default gen_random_uuid(),
 coupon_id uuid not null references public.pasr_business_coupons(id),
 user_id uuid not null references auth.users(id),
 redeem_code text unique not null,
 claimed_at timestamptz not null default now(),
 redeemed_at timestamptz,
 redeemed_by uuid references auth.users(id)
);
