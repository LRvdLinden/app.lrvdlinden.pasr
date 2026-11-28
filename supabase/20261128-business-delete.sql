-- Pasr beheer: een zaak (ondernemer) permanent verwijderen, naast blokkeren (28-11-2026).
-- Herhaalbaar ("create or replace" / "if not exists"). Alleen service role (functie admin), nooit anon of authenticated.
--
-- pasr_admin_business_delete_preview(zaak)  -> {id, name, status, counts}   (alleen lezen, voor het bevestigingsvenster)
-- pasr_admin_business_delete(zaak)          -> {deleted, id, name, counts, campaigns_cancelled}
--
-- Wat er verdwijnt: de zaak zelf en, via "on delete cascade", alles wat eraan hangt: stempelkaarten en leden, medewerkers
-- en uitnodigingen, events en tickets (met de persoonsgegevens van aanmeldingen), klantenkaarten en leden, aanbiedingen,
-- locaties, de log, en alles van gezamenlijke acties: acties waarvoor de zaak organisator is (= geannuleerd), deelnames en
-- uitnodigingen aan andere acties, openstaande meldingen in de outbox. Rijen in andere tabellen die naar de zaak wijzen
-- zonder dat ze van de zaak zijn (wie iets deed, een uitgegeven beloning) blijven staan met een lege verwijzing.
-- Wat blijft: het Pasr-account van de eigenaar en de medewerkers, en de eigen (versleutelde) kaarten en Wallet-passen van
-- klanten. Een stempelkaart van de zaak verdwijnt bij de klant bij het volgende verversen: pasr_business_member geeft dan
-- 'not_found' en de app haalt de kaart weg (BusinessCards.refresh).
-- Foutcodes (exception message): not_found, bad_id.

-- Een uitgegeven beloning van een gezamenlijke actie blijft geldig voor de klant als de zaak die hem uitgaf verdwijnt.
alter table public.pasr_business_community_claims alter column issued_at_business drop not null;
alter table public.pasr_business_community_claims drop constraint if exists pasr_business_community_claims_issued_at_business_fkey;
alter table public.pasr_business_community_claims add constraint pasr_business_community_claims_issued_at_business_fkey
  foreign key (issued_at_business) references public.pasr_businesses(id) on delete set null;

-- Telt rijen in een tabel die er misschien niet is (oudere omgevingen): geen tabel = 0. p_sql is altijd een vaste tekst
-- uit deze file, met $1 = zaak.
create or replace function public.pasr_admin_business_count(p_table text, p_sql text, p_business uuid) returns integer
language plpgsql stable security definer set search_path = '' as $$
declare n integer;
begin
  if to_regclass(p_table) is null then return 0; end if;
  execute p_sql using p_business into n;
  return coalesce(n, 0);
end $$;

create or replace function public.pasr_admin_business_delete_counts(p_business uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare f text := 'select count(*)::integer from ';
begin
  return jsonb_build_object(
    'cards', public.pasr_admin_business_count('public.pasr_business_cards', f || 'public.pasr_business_cards where business_id = $1', p_business),
    'members', public.pasr_admin_business_count('public.pasr_business_members', f ||
      'public.pasr_business_members m join public.pasr_business_cards c on c.id = m.business_card_id where c.business_id = $1', p_business),
    'staff', public.pasr_admin_business_count('public.pasr_business_staff', f ||
      'public.pasr_business_staff where business_id = $1 and role = ''staff'' and revoked_at is null', p_business),
    'events', public.pasr_admin_business_count('public.pasr_tk_events', f || 'public.pasr_tk_events where business_id = $1', p_business),
    'upcoming_events', public.pasr_admin_business_count('public.pasr_tk_events', f ||
      'public.pasr_tk_events where business_id = $1 and status = ''published'' and ends_at > now()', p_business),
    'tickets', public.pasr_admin_business_count('public.pasr_tk_tickets', f ||
      'public.pasr_tk_tickets t join public.pasr_tk_events e on e.id = t.event_id where e.business_id = $1', p_business),
    'member_cards', public.pasr_admin_business_count('public.pasr_mc_cards', f || 'public.pasr_mc_cards where business_id = $1', p_business),
    'member_card_members', public.pasr_admin_business_count('public.pasr_mc_members', f || 'public.pasr_mc_members where business_id = $1', p_business),
    'campaigns', public.pasr_admin_business_count('public.pasr_business_community_campaigns', f ||
      'public.pasr_business_community_campaigns where lead_business_id = $1', p_business),
    'participations', public.pasr_admin_business_count('public.pasr_business_community_participants', f ||
      'public.pasr_business_community_participants p join public.pasr_business_community_campaigns c on c.id = p.campaign_id ' ||
      'where p.business_id = $1 and c.lead_business_id <> $1', p_business),
    'offers', public.pasr_admin_business_count('public.pasr_business_coupons', f || 'public.pasr_business_coupons where business_id = $1', p_business)
            + public.pasr_admin_business_count('public.pasr_business_promo_codes', f || 'public.pasr_business_promo_codes where business_id = $1', p_business),
    'log', public.pasr_admin_business_count('public.pasr_business_events', f || 'public.pasr_business_events where business_id = $1', p_business));
end $$;

create or replace function public.pasr_admin_business_delete_preview(p_business uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare b public.pasr_businesses;
begin
  select * into b from public.pasr_businesses where id = p_business;
  if b.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  return jsonb_build_object('id', b.id, 'name', b.name, 'status', b.status, 'counts', public.pasr_admin_business_delete_counts(b.id));
end $$;

create or replace function public.pasr_admin_business_delete(p_business uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare b public.pasr_businesses; counts jsonb;
begin
  -- Vergrendelen: scans en stempels zien de zaak vanaf nu niet meer als goedgekeurd (eerst blokkeren is niet nodig).
  select * into b from public.pasr_businesses where id = p_business for update;
  if b.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  update public.pasr_businesses set status = 'blocked' where id = b.id;
  counts := public.pasr_admin_business_delete_counts(b.id);
  -- Al het andere gaat mee via de foreign keys (on delete cascade); de test supabase/tests/business_delete_smoke.sql
  -- bewaakt dat er geen verwijzing zonder cascade of set null naar de zaak overblijft.
  delete from public.pasr_businesses where id = b.id;
  return jsonb_build_object('deleted', true, 'id', b.id, 'name', b.name, 'counts', counts,
                            'campaigns_cancelled', coalesce((counts->>'campaigns')::integer, 0));
end $$;

revoke all on function public.pasr_admin_business_count(text, text, uuid), public.pasr_admin_business_delete_counts(uuid),
  public.pasr_admin_business_delete_preview(uuid), public.pasr_admin_business_delete(uuid) from public, anon, authenticated;
grant execute on function public.pasr_admin_business_delete_preview(uuid), public.pasr_admin_business_delete(uuid) to service_role;
