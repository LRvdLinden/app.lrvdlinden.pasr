-- Demo-inhoud voor App Review: een gratis testevent en een klantenkaart bij de demo-zaak "Apple Review".
-- Idempotent; vaste id's zodat de links in de review-notities kloppen:
--   https://pasr.nl/add/e/7e5a1c2d-4b6f-4c1a-9d3e-0a1b2c3d4e01
--   https://pasr.nl/add/m/7e5a1c2d-4b6f-4c1a-9d3e-0a1b2c3d4e02
do $$
declare v_biz uuid;
begin
  select id into v_biz from public.pasr_businesses where name = 'Apple Review' order by created_at limit 1;
  if v_biz is null then raise notice 'Apple Review-zaak niet gevonden; overgeslagen'; return; end if;

  insert into public.pasr_tk_events (id, business_id, name, description, starts_at, ends_at, doors_at, address,
    capacity, max_per_person, signup_until, waitlist, reminder, color, status)
  values ('7e5a1c2d-4b6f-4c1a-9d3e-0a1b2c3d4e01', v_biz, 'Pasr testevent',
    'Testevent voor App Review. Aanmelden is gratis; je ticket komt in Pasr en in Wallet.',
    '2027-06-19 16:00 Europe/Amsterdam', '2027-06-19 19:00 Europe/Amsterdam', '2027-06-19 15:30 Europe/Amsterdam',
    'Apeldoorn', 1000, 4, null, true, false, '#22B5A8', 'published')
  on conflict (id) do update set status = 'published', starts_at = excluded.starts_at, ends_at = excluded.ends_at,
    doors_at = excluded.doors_at, cancelled_at = null, cancel_message = null, purged_at = null, updated_at = now();

  insert into public.pasr_tk_ticket_types (id, event_id, name, position)
  values ('7e5a1c2d-4b6f-4c1a-9d3e-0a1b2c3d4e11', '7e5a1c2d-4b6f-4c1a-9d3e-0a1b2c3d4e01', 'Toegang', 0)
  on conflict (id) do update set archived = false;

  insert into public.pasr_mc_cards (id, business_id, name, color, barcode_type, prefix, status, goals)
  values ('7e5a1c2d-4b6f-4c1a-9d3e-0a1b2c3d4e02', v_biz, 'Apple Review Klantenkaart', '#2F6FDE', 'qr', 'AR-', 'published',
    '{"membership":true,"saving":{"enabled":true,"unit":"visits","target":10,"reward":"Gratis koffie"},"fixed_discount":{"enabled":true,"percent":10}}'::jsonb)
  on conflict (id) do update set status = 'published', archived_at = null, updated_at = now();
end $$;
