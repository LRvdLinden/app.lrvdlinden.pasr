-- Beheer: acties van een zaak bekijken en zo nodig uitzetten (kortingsbonnen, actiecodes, gezamenlijke acties,
-- vestigingen, vrienden-uitnodigingen). Alleen via de admin-functie (service role). Uitzetten volgt dezelfde regels als
-- in Pasr Zakelijk: een kortingsbon wordt verwijderd (deleted_at, historie blijft), een actiecode wordt gepauzeerd,
-- een gezamenlijke actie geannuleerd. Klantgegevens komen er niet in: alleen aantallen.

create or replace function public.pasr_admin_business_offers(p_business uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'coupons', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'title', c.title, 'description', c.description, 'card_id', c.card_id,
        'discount_type', c.discount_type, 'discount_value', c.discount_value, 'min_spend', c.min_spend,
        'starts_at', c.starts_at, 'ends_at', c.ends_at, 'public', c.public, 'max_claims', c.max_claims,
        'deleted_at', c.deleted_at,
        'claims', (select count(*) from public.pasr_business_coupon_claims k where k.coupon_id = c.id),
        'redeemed', (select count(*) from public.pasr_business_coupon_claims k where k.coupon_id = c.id and k.redeemed_at is not null))
      order by c.created_at desc) from public.pasr_business_coupons c where c.business_id = p_business), '[]'::jsonb),
    'promo_codes', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'code', p.code, 'title', p.title, 'discount_type', p.discount_type, 'discount_value', p.discount_value,
        'starts_at', p.starts_at, 'ends_at', p.ends_at, 'max_uses', p.max_uses, 'used_count', p.used_count,
        'active', p.active, 'deleted_at', p.deleted_at)
      order by p.created_at desc) from public.pasr_business_promo_codes p where p.business_id = p_business), '[]'::jsonb),
    'campaigns', coalesce((select jsonb_agg(jsonb_build_object(
        'id', m.id, 'name', m.name, 'reward', m.reward, 'lead', m.lead_business_id = p_business,
        'required_businesses', m.required_businesses, 'starts_at', m.starts_at, 'ends_at', m.ends_at,
        'cancelled_at', m.cancelled_at,
        'participants', (select count(*) from public.pasr_business_community_participants x where x.campaign_id = m.id),
        'claims', (select count(*) from public.pasr_business_community_claims x where x.campaign_id = m.id))
      order by m.created_at desc)
      from public.pasr_business_community_campaigns m
      where m.lead_business_id = p_business
         or exists (select 1 from public.pasr_business_community_participants x where x.campaign_id = m.id and x.business_id = p_business)),
      '[]'::jsonb),
    'locations', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'address', l.address, 'active', l.active)
      order by l.name) from public.pasr_business_locations l where l.business_id = p_business), '[]'::jsonb),
    'referrals', (select count(*) from public.pasr_business_referrals r
      join public.pasr_business_cards bc on bc.id = r.business_card_id where bc.business_id = p_business),
    'programs', (select count(*) from public.pasr_business_programs g
      join public.pasr_business_cards bc on bc.id = g.card_id where bc.business_id = p_business and g.settings <> '{}'::jsonb));
$$;

create or replace function public.pasr_admin_business_offer_disable(p_kind text, p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if p_kind = 'coupon' then
    update public.pasr_business_coupons set deleted_at = coalesce(deleted_at, now()) where id = p_id;
  elsif p_kind = 'promo_code' then
    update public.pasr_business_promo_codes set active = false, updated_at = now() where id = p_id;
  elsif p_kind = 'campaign' then
    update public.pasr_business_community_campaigns set cancelled_at = coalesce(cancelled_at, now()) where id = p_id;
  else
    raise exception 'bad_kind' using errcode = '22023';
  end if;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.pasr_admin_business_offers(uuid), public.pasr_admin_business_offer_disable(text, uuid)
  from public, anon, authenticated;
grant execute on function public.pasr_admin_business_offers(uuid), public.pasr_admin_business_offer_disable(text, uuid)
  to service_role;
