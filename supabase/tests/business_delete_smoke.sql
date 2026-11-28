-- Zaak permanent verwijderen (20261128-business-delete.sql), met verzonnen zaken en accounts.
-- Draait na beheer_mail_smoke.sql in de PR-check "backend-integration". Alleen testomgeving.
-- Bewaakt: alles van de zaak is weg, geen enkele kolom verwijst nog naar de zaak, andere zaken blijven onaangetast.

-- Wat de echte database wel heeft en de basisfixture niet.
create table if not exists public.pasr_business_staff (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.pasr_businesses(id) on delete cascade,
 user_id uuid references auth.users(id), role text not null default 'staff', revoked_at timestamptz
);

-- De fixture heeft een paar verwijzingen zonder "on delete cascade" die in schema.sql wel cascade zijn: gelijktrekken.
do $$
declare r record;
begin
  -- de enige bewuste uitzondering in de productie-SQL: een uitgegeven beloning blijft staan (set null), nooit "no action"
  if (select confdeltype from pg_constraint where conname = 'pasr_business_community_claims_issued_at_business_fkey') <> 'n' then
    raise exception 'issued_at_business must be on delete set null';
  end if;
  for r in select c.conrelid::regclass t, c.conname, pg_get_constraintdef(c.oid) d from pg_constraint c
            where c.contype = 'f' and c.confdeltype in ('a', 'r')
              and c.confrelid in ('public.pasr_businesses'::regclass, 'public.pasr_business_cards'::regclass, 'public.pasr_business_members'::regclass)
  loop
    execute format('alter table %s drop constraint %I', r.t, r.conname);
    execute format('alter table %s add constraint %I %s on delete cascade', r.t, r.conname, r.d);
  end loop;
end $$;

create or replace function pg_temp.expect(p_sql text, p_code text) returns void language plpgsql as $$
declare m text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics m = message_text;
    if m <> p_code then raise exception 'Expected % but got "%" for: %', p_code, m, p_sql; end if;
    return;
  end;
  raise exception 'Expected % but call succeeded: %', p_code, p_sql;
end $$;

insert into auth.users(id) values
 ('d0000001-0000-4000-8000-000000000001'), ('d0000002-0000-4000-8000-000000000002'),
 ('d0000003-0000-4000-8000-000000000003'), ('d0000004-0000-4000-8000-000000000004')
on conflict (id) do nothing;
-- schoon beginnen (de test mag opnieuw draaien)
delete from public.pasr_businesses where id in ('d1000001-0000-4000-8000-000000000001', 'd1000002-0000-4000-8000-000000000002');
insert into public.pasr_businesses(id, owner, name, city) values
 ('d1000001-0000-4000-8000-000000000001', 'd0000001-0000-4000-8000-000000000001', 'Weg Zaak "Snor" & Zn', 'Apeldoorn'),
 ('d1000002-0000-4000-8000-000000000002', 'd0000002-0000-4000-8000-000000000002', 'Blijf Zaak', 'Apeldoorn');

do $$
declare
 x uuid := 'd1000001-0000-4000-8000-000000000001';   -- wordt verwijderd
 y uuid := 'd1000002-0000-4000-8000-000000000002';   -- blijft
 ux uuid := 'd0000001-0000-4000-8000-000000000001'; uy uuid := 'd0000002-0000-4000-8000-000000000002';
 klant uuid := 'd0000003-0000-4000-8000-000000000003'; staff uuid := 'd0000004-0000-4000-8000-000000000004';
 xcard uuid; ycard uuid; xmem uuid; ymem uuid; xev uuid; yev uuid; xreg uuid; yreg uuid; xmc uuid; ymc uuid;
 xcamp uuid; ycamp uuid; xpromo uuid; ypromo uuid;
 before_y jsonb; after_y jsonb; pv jsonb; res jsonb; n int; r record; ids text[]; cnt int;
begin
 -- ---- zaak X: van alles ----
 insert into public.pasr_business_cards(business_id, name) values (x, 'X-kaart') returning id into xcard;
 insert into public.pasr_business_members(business_card_id, user_id, member_code) values (xcard, klant, 'DELX00000001') returning id into xmem;
 insert into public.pasr_business_programs(card_id) values (xcard);
 insert into public.pasr_business_events(business_card_id, business_id, member_id, kind) values (xcard, x, xmem, 'stamp'), (xcard, x, xmem, 'stamp');
 insert into public.pasr_business_staff(business_id, user_id, role) values (x, staff, 'staff');
 insert into public.pasr_business_coupons(business_id, card_id, title, discount_type, discount_value, starts_at, ends_at)
   values (x, xcard, 'X-bon', 'percent', 10, now(), now() + interval '10 days');
 insert into public.pasr_business_promo_codes(business_id, code, title, discount_type, discount_value, ends_at)
   values (x, 'DELXCODE', 'X-code', 'percent', 10, now() + interval '10 days') returning id into xpromo;
 insert into public.pasr_business_promo_claims(promo_id, user_id, redeem_code) values (xpromo, klant, 'PA' || repeat('A', 22));
 insert into public.pasr_tk_events(business_id, name, starts_at, ends_at, capacity, status)
   values (x, 'X-event', now() + interval '3 days', now() + interval '3 days 2 hours', 50, 'published') returning id into xev;
 insert into public.pasr_tk_events(business_id, name, starts_at, ends_at, capacity, status)
   values (x, 'X-oud-event', now() - interval '3 days', now() - interval '3 days' + interval '2 hours', 50, 'published');
 insert into public.pasr_tk_ticket_types(event_id, name) values (xev, 'Gewoon');
 insert into public.pasr_tk_registrations(event_id, first_name, last_name, email, birth_date, ticket_count, user_id)
   values (xev, 'Piet', 'Puk', 'piet@voorbeeld.example', '1990-01-01', 2, klant) returning id into xreg;
 insert into public.pasr_tk_tickets(registration_id, event_id, code, user_id, status)
   values (xreg, xev, 'AAAAAAAAAAAAAAAAAAAAAA22', klant, 'registered'), (xreg, xev, 'AAAAAAAAAAAAAAAAAAAAAA23', klant, 'registered');
 insert into public.pasr_tk_outbox(kind, event_id, registration_id, user_id) values ('ticket_confirmed', xev, xreg, klant);
 insert into public.pasr_mc_cards(business_id, name) values (x, 'X-klantenkaart') returning id into xmc;
 insert into public.pasr_mc_members(card_id, business_id, user_id, number) values (xmc, x, klant, 'XNUMMER0001');
 insert into public.pasr_mc_visits(card_id, business_id, kind) values (xmc, x, 'join');

 -- ---- zaak Y: hetzelfde, moet blijven ----
 insert into public.pasr_business_cards(business_id, name) values (y, 'Y-kaart') returning id into ycard;
 insert into public.pasr_business_members(business_card_id, user_id, member_code) values (ycard, klant, 'DELY00000001') returning id into ymem;
 insert into public.pasr_business_programs(card_id) values (ycard);
 insert into public.pasr_business_events(business_card_id, business_id, member_id, kind) values (ycard, y, ymem, 'stamp');
 insert into public.pasr_business_staff(business_id, user_id, role) values (y, staff, 'staff');
 insert into public.pasr_business_coupons(business_id, card_id, title, discount_type, discount_value, starts_at, ends_at)
   values (y, ycard, 'Y-bon', 'percent', 10, now(), now() + interval '10 days');
 insert into public.pasr_business_promo_codes(business_id, code, title, discount_type, discount_value, ends_at)
   values (y, 'DELYCODE', 'Y-code', 'percent', 10, now() + interval '10 days') returning id into ypromo;
 insert into public.pasr_business_promo_claims(promo_id, user_id, redeem_code) values (ypromo, klant, 'PA' || repeat('B', 22));
 insert into public.pasr_tk_events(business_id, name, starts_at, ends_at, capacity, status)
   values (y, 'Y-event', now() + interval '3 days', now() + interval '3 days 2 hours', 50, 'published') returning id into yev;
 insert into public.pasr_tk_registrations(event_id, first_name, ticket_count, user_id) values (yev, 'Anna', 1, klant) returning id into yreg;
 insert into public.pasr_tk_tickets(registration_id, event_id, code, user_id, status) values (yreg, yev, 'BBBBBBBBBBBBBBBBBBBBBB22', klant, 'registered');
 insert into public.pasr_mc_cards(business_id, name) values (y, 'Y-klantenkaart') returning id into ymc;
 insert into public.pasr_mc_members(card_id, business_id, user_id, number) values (ymc, y, klant, 'YNUMMER0001');

 -- ---- gezamenlijke acties: X organiseert er één met Y; Y organiseert er één waar X aan meedoet ----
 insert into public.pasr_business_community_campaigns(lead_business_id, name, reward, required_businesses, ends_at)
   values (x, 'Actie van X', 'Gratis koffie', 2, now() + interval '30 days') returning id into xcamp;
 insert into public.pasr_business_community_campaigns(lead_business_id, name, reward, required_businesses, ends_at)
   values (y, 'Actie van Y', 'Gratis taart', 3, now() + interval '30 days') returning id into ycamp;
 insert into public.pasr_business_community_participants(campaign_id, business_id, accepted_by) values
   (xcamp, x, ux), (xcamp, y, uy), (ycamp, y, uy), (ycamp, x, ux);
 insert into public.pasr_business_community_invites(campaign_id, business_id, status, organizer) values
   (xcamp, x, 'accepted', true), (xcamp, y, 'accepted', false), (ycamp, y, 'accepted', true), (ycamp, x, 'accepted', false);
 insert into public.pasr_business_community_outbox(kind, campaign_id, business_id, actor_business_id) values
   ('accepted', ycamp, y, x), ('invite', ycamp, x, y), ('accepted', xcamp, x, y);
 insert into public.pasr_business_community_claims(campaign_id, user_id, issued_by, issued_at_business) values
   (ycamp, klant, ux, x), (xcamp, klant, ux, x);

 -- stand van Y vóór het verwijderen: alles wat aan Y hangt, per tabel
 before_y := (select coalesce(jsonb_object_agg(t, c), '{}') from (
   select 'cards' t, count(*) c from public.pasr_business_cards where business_id = y
   union all select 'members', count(*) from public.pasr_business_members where business_card_id = ycard
   union all select 'log', count(*) from public.pasr_business_events where business_id = y
   union all select 'staff', count(*) from public.pasr_business_staff where business_id = y
   union all select 'coupons', count(*) from public.pasr_business_coupons where business_id = y
   union all select 'promo', count(*) from public.pasr_business_promo_claims where promo_id = ypromo
   union all select 'events', count(*) from public.pasr_tk_events where business_id = y
   union all select 'tickets', count(*) from public.pasr_tk_tickets where event_id = yev
   union all select 'mc_members', count(*) from public.pasr_mc_members where business_id = y
   union all select 'campaign', count(*) from public.pasr_business_community_campaigns where id = ycamp
   union all select 'ycamp_participants_y', count(*) from public.pasr_business_community_participants where campaign_id = ycamp and business_id = y) q);

 -- ---- rechten ----
 if has_function_privilege('authenticated', 'public.pasr_admin_business_delete(uuid)', 'execute')
    or has_function_privilege('anon', 'public.pasr_admin_business_delete(uuid)', 'execute')
    or has_function_privilege('authenticated', 'public.pasr_admin_business_delete_preview(uuid)', 'execute')
    or has_function_privilege('anon', 'public.pasr_admin_business_delete_preview(uuid)', 'execute')
    or has_function_privilege('authenticated', 'public.pasr_admin_business_delete_counts(uuid)', 'execute')
    or has_function_privilege('authenticated', 'public.pasr_admin_business_count(text, text, uuid)', 'execute')
 then raise exception 'Delete functions must not be executable by anon or authenticated'; end if;
 if not (has_function_privilege('service_role', 'public.pasr_admin_business_delete(uuid)', 'execute')
         and has_function_privilege('service_role', 'public.pasr_admin_business_delete_preview(uuid)', 'execute'))
 then raise exception 'service_role must run the delete functions'; end if;

 -- ---- preview: telt, verandert niets ----
 pv := public.pasr_admin_business_delete_preview(x);
 if pv->>'name' <> 'Weg Zaak "Snor" & Zn' or pv->>'status' <> 'approved' then raise exception 'Preview header wrong: %', pv; end if;
 if (pv#>>'{counts,cards}')::int <> 1 or (pv#>>'{counts,members}')::int <> 1 or (pv#>>'{counts,staff}')::int <> 1
    or (pv#>>'{counts,events}')::int <> 2 or (pv#>>'{counts,upcoming_events}')::int <> 1 or (pv#>>'{counts,tickets}')::int <> 2
    or (pv#>>'{counts,member_cards}')::int <> 1 or (pv#>>'{counts,member_card_members}')::int <> 1
    or (pv#>>'{counts,campaigns}')::int <> 1 or (pv#>>'{counts,participations}')::int <> 1
    or (pv#>>'{counts,offers}')::int <> 2 or (pv#>>'{counts,log}')::int <> 2
 then raise exception 'Preview counts wrong: %', pv; end if;
 if (select status from public.pasr_businesses where id = x) <> 'approved' then raise exception 'Preview changed the status'; end if;
 perform pg_temp.expect(format('select public.pasr_admin_business_delete_preview(%L)', gen_random_uuid()), 'not_found');
 perform pg_temp.expect(format('select public.pasr_admin_business_delete(%L)', gen_random_uuid()), 'not_found');
 if not exists (select 1 from public.pasr_businesses where id = x) then raise exception 'X vanished too early'; end if;

 -- ---- verwijderen (een goedgekeurde zaak mag direct) ----
 res := public.pasr_admin_business_delete(x);
 if res->>'deleted' <> 'true' or res->>'id' <> x::text or res->>'name' <> 'Weg Zaak "Snor" & Zn'
    or (res->>'campaigns_cancelled')::int <> 1 or res#>>'{counts,cards}' <> '1' or res#>>'{counts,tickets}' <> '2'
 then raise exception 'Delete result wrong: %', res; end if;

 -- zaak en alles eraan
 if exists (select 1 from public.pasr_businesses where id = x) then raise exception 'Business still there'; end if;
 perform pg_temp.expect(format('select public.pasr_admin_business_delete(%L)', x), 'not_found');
 if exists (select 1 from public.pasr_business_cards where id = xcard) or exists (select 1 from public.pasr_business_members where id = xmem)
    or exists (select 1 from public.pasr_business_programs where card_id = xcard)
    or exists (select 1 from public.pasr_tk_events where id = xev) or exists (select 1 from public.pasr_tk_registrations where id = xreg)
    or exists (select 1 from public.pasr_tk_tickets where event_id = xev) or exists (select 1 from public.pasr_tk_ticket_types where event_id = xev)
    or exists (select 1 from public.pasr_tk_outbox where event_id = xev)
    or exists (select 1 from public.pasr_mc_cards where id = xmc) or exists (select 1 from public.pasr_mc_members where card_id = xmc)
    or exists (select 1 from public.pasr_mc_visits where card_id = xmc)
    or exists (select 1 from public.pasr_business_promo_codes where id = xpromo) or exists (select 1 from public.pasr_business_promo_claims where promo_id = xpromo)
    or exists (select 1 from public.pasr_business_community_campaigns where id = xcamp)
    or exists (select 1 from public.pasr_business_community_participants where campaign_id = xcamp)
    or exists (select 1 from public.pasr_business_community_invites where campaign_id = xcamp)
    or exists (select 1 from public.pasr_business_community_outbox where campaign_id = xcamp)
    or exists (select 1 from public.pasr_business_community_claims where campaign_id = xcamp)
 then raise exception 'Rows of the deleted business are left behind'; end if;

 -- Wat van de zaak in andermans acties zat is weg; de actie van Y loopt door
 if exists (select 1 from public.pasr_business_community_participants where business_id = x)
    or exists (select 1 from public.pasr_business_community_invites where business_id = x)
    or exists (select 1 from public.pasr_business_community_outbox where business_id = x or actor_business_id = x)
 then raise exception 'Participation of the deleted business is left behind'; end if;
 if (select count(*) from public.pasr_business_community_participants where campaign_id = ycamp) <> 1
 then raise exception 'Campaign of Y should now have only Y as participant'; end if;
 if (select state from (select public.pasr_business_community_state(ycamp) state) q) is distinct from 'waiting'
 then raise exception 'Campaign of Y should be waiting again, got %', public.pasr_business_community_state(ycamp); end if;
 -- uitgegeven beloning blijft voor de klant, zonder zaak
 select * into r from public.pasr_business_community_claims where campaign_id = ycamp and user_id = klant;
 if r.campaign_id is null or r.issued_at_business is not null then raise exception 'Issued reward should stay with an empty business'; end if;
 -- de uitgaande meldingen van Y naar anderen zijn ongemoeid, die naar X weg
 if (select count(*) from public.pasr_business_community_outbox where campaign_id = ycamp and business_id = y) <> 1
 then raise exception 'Outbox of Y changed'; end if;

 -- ---- Y onaangetast ----
 after_y := (select coalesce(jsonb_object_agg(t, c), '{}') from (
   select 'cards' t, count(*) c from public.pasr_business_cards where business_id = y
   union all select 'members', count(*) from public.pasr_business_members where business_card_id = ycard
   union all select 'log', count(*) from public.pasr_business_events where business_id = y
   union all select 'staff', count(*) from public.pasr_business_staff where business_id = y
   union all select 'coupons', count(*) from public.pasr_business_coupons where business_id = y
   union all select 'promo', count(*) from public.pasr_business_promo_claims where promo_id = ypromo
   union all select 'events', count(*) from public.pasr_tk_events where business_id = y
   union all select 'tickets', count(*) from public.pasr_tk_tickets where event_id = yev
   union all select 'mc_members', count(*) from public.pasr_mc_members where business_id = y
   union all select 'campaign', count(*) from public.pasr_business_community_campaigns where id = ycamp
   union all select 'ycamp_participants_y', count(*) from public.pasr_business_community_participants where campaign_id = ycamp and business_id = y) q);
 if before_y <> after_y then raise exception 'Other business changed: % -> %', before_y, after_y; end if;
 if (select status from public.pasr_businesses where id = y) <> 'approved' then raise exception 'Y status changed'; end if;

 -- accounts blijven (eigenaar, medewerker, klant); alleen de zaak-koppelingen zijn weg
 select count(*) into n from auth.users where id in (ux, uy, klant, staff);
 if n <> 4 then raise exception 'Accounts must stay'; end if;

 -- ---- geen enkele uuid-kolom in public verwijst nog naar X, zijn kaart, event, lid of actie ----
 ids := array[x::text, xcard::text, xev::text, xmem::text, xcamp::text, xmc::text, xreg::text, xpromo::text];
 for r in select c.table_name, c.column_name from information_schema.columns c
            join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
           where c.table_schema = 'public' and c.data_type = 'uuid' loop
   execute format('select count(*) from public.%I where %I::text = any($1) and %L <> ''id''', r.table_name, r.column_name, r.column_name) using ids into cnt;
   if cnt > 0 then raise exception 'Table %.% still references the deleted business (% rows)', r.table_name, r.column_name, cnt; end if;
 end loop;
end $$;

-- Elke verwijzing naar een zaak is cascade of set null: dan kan de functie nooit blijven hangen op een vreemde sleutel
do $$
declare bad text;
begin
  select string_agg(conrelid::regclass || '.' || conname, ', ') into bad from pg_constraint
   where contype = 'f' and confrelid = 'public.pasr_businesses'::regclass and confdeltype not in ('c', 'n');
  if bad is not null then raise exception 'FK to pasr_businesses without cascade/set null: %', bad; end if;
end $$;
