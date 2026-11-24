-- Pasr Loyalty 2: veilig terugkomoverzicht, zonder klantgegevens of automatische berichten.
-- Handmatige marketing of push mag pas na afzonderlijke opt-in/consent-implementatie.
create or replace function public.pasr_business_retention_overview(p_business uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  response jsonb;
begin
  if auth.uid() is null then
    raise exception 'Log eerst in.' using errcode = '28000';
  end if;
  if not exists (
    select 1 from public.pasr_businesses b
    where b.id = p_business and b.owner = auth.uid() and b.status = 'approved'
  ) then
    raise exception 'Alleen de eigenaar kan terugkominzichten bekijken.' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'card_id', x.card_id,
      'card_name', x.card_name,
      'enabled', x.enabled,
      'days', x.days,
      'members', x.members,
      'active_30d', x.active_30d,
      'inactive', x.inactive,
      'never_visited', x.never_visited
    ) order by x.card_name
  ), '[]'::jsonb)
  into response
  from (
    select c.id as card_id, c.name as card_name,
      coalesce((p.settings->'retention'->>'enabled')::boolean, false) as enabled,
      case when (p.settings->'retention'->>'days') ~ '^[0-9]{1,3}$'
        then least(365, greatest(7, (p.settings->'retention'->>'days')::int))
        else 30 end as days,
      count(m.id)::int as members,
      count(m.id) filter (where m.last_stamp_at >= now() - interval '30 days')::int as active_30d,
      count(m.id) filter (where m.last_stamp_at is null)::int as never_visited,
      count(m.id) filter (
        where m.last_stamp_at is not null and m.last_stamp_at < now() -
          make_interval(days => case
            when (p.settings->'retention'->>'days') ~ '^[0-9]{1,3}$'
              then least(365, greatest(7, (p.settings->'retention'->>'days')::int))
            else 30 end)
      )::int as inactive
    from public.pasr_business_cards c
    left join public.pasr_business_programs p on p.card_id = c.id
    left join public.pasr_business_members m on m.business_card_id = c.id
    where c.business_id = p_business
    group by c.id, c.name, p.settings
  ) x;
  return response;
end $$;

revoke all on function public.pasr_business_retention_overview(uuid) from public, anon;
grant execute on function public.pasr_business_retention_overview(uuid) to authenticated;
