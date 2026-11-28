-- Pasr beheer: mails bij het verwijderen van een zaak (28-11-2026), aanvulling op 20261128-business-delete.sql.
-- Herhaalbaar. Draait na business-delete.sql (de workflow Backend doet ze in die volgorde).
--
-- pasr_admin_business_delete_recipients(zaak) verzamelt VOOR het verwijderen wie een mail krijgt:
--   owner      het adres van de eigenaar (adres van de zaak, anders het account), of null
--   campaigns  per lopende gezamenlijke actie van deze zaak: titel, beloning, einde en de adressen van de deelnemende en de
--              uitgenodigde zaken (eigenaar-adres) en van uitnodigingen per e-mail
--   organizers per lopende actie van een andere zaak waaraan deze zaak meedoet: titel en het eigenaar-adres van de organisator
-- De antwoorden van de database met adressen gaan alleen naar de functie admin; die stuurt de mails en geeft het beheer
-- alleen aantallen terug. De bestaande outbox-mail 'removed' gaat naar de verwijderde zaak zelf en meldt de organisator niets;
-- daarom een eigen mail aan de organisator.
-- pasr_admin_business_delete_preview telt mee: mail_participants (aantal mails aan deelnemers en organisatoren) en owner_mail.

-- Adres van de eigenaar van een zaak: adres van de zaak, anders dat van het account; kleine letters; null als er geen is.
create or replace function public.pasr_admin_business_contact(p_business uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  return (select lower(nullif(btrim(coalesce(nullif(btrim(b.email), ''), (select u.email::text from auth.users u where u.id = b.owner))), ''))
            from public.pasr_businesses b where b.id = p_business);
end $$;

create or replace function public.pasr_admin_business_delete_recipients(p_business uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare camps jsonb; orgs jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('title', c.name, 'reward', c.reward, 'ends_at', c.ends_at,
      'recipients', coalesce((select jsonb_agg(distinct x.email) from (
          select public.pasr_admin_business_contact(p.business_id) email
            from public.pasr_business_community_participants p where p.campaign_id = c.id and p.business_id <> p_business
          union
          select public.pasr_admin_business_contact(i.business_id)
            from public.pasr_business_community_invites i
           where i.campaign_id = c.id and i.status = 'invited' and i.business_id is not null and i.business_id <> p_business
             and (i.expires_at is null or i.expires_at > now())
          union
          select lower(i.email)
            from public.pasr_business_community_invites i
           where i.campaign_id = c.id and i.status = 'invited' and i.business_id is null and i.email is not null
             and (i.expires_at is null or i.expires_at > now())) x where x.email is not null), '[]'::jsonb))
      order by c.created_at), '[]'::jsonb) into camps
    from public.pasr_business_community_campaigns c
   where c.lead_business_id = p_business and c.cancelled_at is null and c.ends_at > now();
  select coalesce(jsonb_agg(jsonb_build_object('title', c.name, 'email', public.pasr_admin_business_contact(c.lead_business_id)) order by c.created_at), '[]'::jsonb) into orgs
    from public.pasr_business_community_participants p
    join public.pasr_business_community_campaigns c on c.id = p.campaign_id
   where p.business_id = p_business and c.lead_business_id <> p_business and c.cancelled_at is null and c.ends_at > now()
     and public.pasr_admin_business_contact(c.lead_business_id) is not null;
  return jsonb_build_object('owner', public.pasr_admin_business_contact(p_business), 'campaigns', camps, 'organizers', orgs);
end $$;

-- aantallen voor het venster: de bestaande tellingen plus het aantal mails
create or replace function public.pasr_admin_business_delete_counts(p_business uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare f text := 'select count(*)::integer from '; rec jsonb; mails integer;
begin
  rec := public.pasr_admin_business_delete_recipients(p_business);
  select coalesce(sum(jsonb_array_length(c->'recipients')), 0)::integer + jsonb_array_length(rec->'organizers') into mails
    from jsonb_array_elements(rec->'campaigns') c;
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
    'log', public.pasr_admin_business_count('public.pasr_business_events', f || 'public.pasr_business_events where business_id = $1', p_business),
    'mail_participants', mails,
    'owner_mail', (rec->>'owner') is not null);
end $$;

-- Verwijderen zoals voorheen, plus de ontvangers (verzameld vóór het verwijderen) onder 'notify'.
create or replace function public.pasr_admin_business_delete(p_business uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare b public.pasr_businesses; counts jsonb; rec jsonb;
begin
  select * into b from public.pasr_businesses where id = p_business for update;
  if b.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  update public.pasr_businesses set status = 'blocked' where id = b.id;
  counts := public.pasr_admin_business_delete_counts(b.id);
  rec := public.pasr_admin_business_delete_recipients(b.id);
  delete from public.pasr_businesses where id = b.id;
  return jsonb_build_object('deleted', true, 'id', b.id, 'name', b.name, 'counts', counts,
                            'campaigns_cancelled', coalesce((counts->>'campaigns')::integer, 0), 'notify', rec);
end $$;

revoke all on function public.pasr_admin_business_contact(uuid), public.pasr_admin_business_delete_recipients(uuid),
  public.pasr_admin_business_delete_counts(uuid), public.pasr_admin_business_delete(uuid) from public, anon, authenticated;
grant execute on function public.pasr_admin_business_delete(uuid) to service_role;
