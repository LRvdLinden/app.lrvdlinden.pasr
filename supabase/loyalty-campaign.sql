-- Promo-engine: bestaande scan-RPC blijft exact dezelfde parameters houden.
-- De maximum-per-scan grens geldt voor basisstempels; promotiebonussen tellen erbovenop.
-- Inclusief optionele YYYY-MM-DD begin/eindperiode en -1 voor elke dag.
create or replace function public.pasr_business_stamp(p_code text, p_amount int default 1, p_device text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; m public.pasr_business_members; amt int := coalesce(p_amount, 1); left_s int; ev uuid;
  cfg jsonb; mult int := 1; actual int; today int;
begin
  select * into r from public.pasr_business_scan_member(p_code);
  if amt < 1 then raise exception 'Kies minstens 1 stempel.' using errcode = '22023', hint = 'bad_amount'; end if;
  if amt > (r.b).max_per_scan then
    raise exception 'Je kunt hoogstens % % per keer geven.', (r.b).max_per_scan,
      case when (r.b).max_per_scan = 1 then 'stempel' else 'stempels' end using errcode = '22023', hint = 'too_many';
  end if;
  -- dubbel scannen: binnen 5 seconden nooit nog een keer
  if (r.m).last_stamp_at > now() - interval '5 seconds' then
    raise exception 'Net al een stempel gezet. Wacht een paar seconden.' using errcode = '22023', hint = 'too_soon';
  end if;
  if (r.b).cooldown_minutes > 0 and (r.m).last_stamp_at > now() - make_interval(mins => (r.b).cooldown_minutes) then
    left_s := ceil(extract(epoch from ((r.m).last_stamp_at + make_interval(mins => (r.b).cooldown_minutes) - now())))::int;
    raise exception 'Deze klant kreeg net al een stempel, probeer het over % min opnieuw.', greatest(1, ceil(left_s / 60.0)::int)
      using errcode = '22023', hint = 'cooldown', detail = left_s::text;
  end if;
  -- Tijdelijke stempelactie alleen als de eigenaar hem op deze kaart aanzet.
  select settings->'campaign' into cfg from public.pasr_business_programs where card_id=(r.c).id;
  today := extract(dow from now() at time zone 'Europe/Amsterdam')::int;
  if coalesce((cfg->>'enabled')::boolean,false)
     and (coalesce((cfg->>'weekday')::int,-1)=-1 or (cfg->>'weekday')::int=today)
     and (nullif(cfg->>'start','') is null or
       ((cfg->>'start') ~ '^20[0-9]{2}-[01][0-9]-[0-3][0-9]
  update public.pasr_business_members set stamps_count = least(stamps_count + actual, 1000), last_stamp_at = now(), updated_at = now()
  where id = (r.m).id returning * into m;
  insert into public.pasr_business_events (business_card_id, business_id, member_id, kind, amount, by_user, device, stamps_before, stamps_after)
  values ((r.c).id, (r.b).id, m.id, 'stamp', actual, auth.uid(), nullif(left(trim(coalesce(p_device, '')), 80), ''), (r.m).stamps_count, m.stamps_count)
  returning event_id into ev;
  -- Een uitgenodigde klant krijgt pas bij de eerste echte, door de zaak gescande aankoop een bonus.
  if (r.m).last_stamp_at is null then
    perform public.pasr_business_referral_award_internal(m.id,(r.b).id,(r.c).id);
    select * into m from public.pasr_business_members where id=(r.m).id;
  end if;
  return public.pasr_business_scan_json(m, r.c, r.b, ev) || jsonb_build_object('stamps_added',actual,'campaign_multiplier',mult);
end $$;
        and (cfg->>'start') <= ((now() at time zone 'Europe/Amsterdam')::date)::text))
     and (nullif(cfg->>'end','') is null or
       ((cfg->>'end') ~ '^20[0-9]{2}-[01][0-9]-[0-3][0-9]
  update public.pasr_business_members set stamps_count = least(stamps_count + actual, 1000), last_stamp_at = now(), updated_at = now()
  where id = (r.m).id returning * into m;
  insert into public.pasr_business_events (business_card_id, business_id, member_id, kind, amount, by_user, device, stamps_before, stamps_after)
  values ((r.c).id, (r.b).id, m.id, 'stamp', actual, auth.uid(), nullif(left(trim(coalesce(p_device, '')), 80), ''), (r.m).stamps_count, m.stamps_count)
  returning event_id into ev;
  -- Een uitgenodigde klant krijgt pas bij de eerste echte, door de zaak gescande aankoop een bonus.
  if (r.m).last_stamp_at is null then
    perform public.pasr_business_referral_award_internal(m.id,(r.b).id,(r.c).id);
    select * into m from public.pasr_business_members where id=(r.m).id;
  end if;
  return public.pasr_business_scan_json(m, r.c, r.b, ev) || jsonb_build_object('stamps_added',actual,'campaign_multiplier',mult);
end $$;
        and (cfg->>'end') >= ((now() at time zone 'Europe/Amsterdam')::date)::text))
  then
    mult := greatest(1, least(3,coalesce((cfg->>'multiplier')::int,1)));
  end if;
  -- max_per_scan beperkt hoeveel basisstempels personeel mag uitdelen.
  -- Een door de eigenaar geactiveerde promotie mag die basislimiet overschrijden.
  if (r.m).stamps_count >= 1000 then
    raise exception 'Maximaal aantal stempels bereikt.' using errcode='22023';
  end if;
  actual := least(amt * mult,30,1000-(r.m).stamps_count);
  update public.pasr_business_members set stamps_count = least(stamps_count + actual, 1000), last_stamp_at = now(), updated_at = now()
  where id = (r.m).id returning * into m;
  insert into public.pasr_business_events (business_card_id, business_id, member_id, kind, amount, by_user, device, stamps_before, stamps_after)
  values ((r.c).id, (r.b).id, m.id, 'stamp', actual, auth.uid(), nullif(left(trim(coalesce(p_device, '')), 80), ''), (r.m).stamps_count, m.stamps_count)
  returning event_id into ev;
  -- Een uitgenodigde klant krijgt pas bij de eerste echte, door de zaak gescande aankoop een bonus.
  if (r.m).last_stamp_at is null then
    perform public.pasr_business_referral_award_internal(m.id,(r.b).id,(r.c).id);
    select * into m from public.pasr_business_members where id=(r.m).id;
  end if;
  return public.pasr_business_scan_json(m, r.c, r.b, ev) || jsonb_build_object('stamps_added',actual,'campaign_multiplier',mult);
end $$;

-- CRITICAL: functie heeft dezelfde signature. CREATE OR REPLACE bewaart bestaande EXECUTE-grants.
