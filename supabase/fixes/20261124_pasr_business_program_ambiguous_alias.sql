-- Fix: PL/pgSQL variable b conflicted with table alias b and triggered SQLSTATE 42702.
-- Safe to reapply; the function signature, ownership checks and stored settings remain unchanged.
create or replace function public.pasr_business_program(p_card uuid, p_settings jsonb default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_business public.pasr_businesses; p jsonb; rewards jsonb; v jsonb; n int; prev int := 0;
begin
  select business_row.* into v_business from public.pasr_business_cards card_row
    join public.pasr_businesses business_row on business_row.id=card_row.business_id where card_row.id=p_card;
  if v_business.id is null or v_business.owner is distinct from auth.uid() then
    raise exception 'Alleen de eigenaar kan kaartinstellingen wijzigen.' using errcode='42501';
  end if;
  if p_settings is not null then
    if v_business.status='blocked' or jsonb_typeof(p_settings)<>'object' or octet_length(p_settings::text)>12000 then
      raise exception 'Ongeldige instellingen.' using errcode='22023';
    end if;
    if exists (select 1 from jsonb_object_keys(p_settings) k
      where k not in ('rewards','referral','campaign','vip','retention','locations','marketing','community')) then
      raise exception 'Onbekende instellingen.' using errcode='22023';
    end if;
    -- Een reward is een vast aantal stempels tussen 2 en het kaartmaximum, met eigen titel.
    rewards:=coalesce(p_settings->'rewards','[]'::jsonb);
    if jsonb_typeof(rewards)<>'array' or jsonb_array_length(rewards)>8 then
      raise exception 'Maximaal 8 beloningen.' using errcode='22023';
    end if;
    for v in select value from jsonb_array_elements(rewards) loop
      if jsonb_typeof(v)<>'object' or (v->>'stamps')!~'^[0-9]{1,2}$'
        or char_length(coalesce(v->>'title','')) not between 3 and 80 then
        raise exception 'Controleer de beloningen.' using errcode='22023';
      end if;
      n:=(v->>'stamps')::int;
      if n<=prev or n> (select stamps_total from public.pasr_business_cards where id=p_card) then
        raise exception 'Mijlpalen moeten oplopend en binnen het kaartmaximum liggen.' using errcode='22023';
      end if;
      prev:=n;
    end loop;
    for v in select value from jsonb_each(p_settings) loop
      if jsonb_typeof(v) not in ('object','array') then
        raise exception 'Ongeldige instellingen.' using errcode='22023';
      end if;
    end loop;
    insert into public.pasr_business_programs(card_id,settings,updated_at)
      values(p_card,p_settings,now())
    on conflict(card_id) do update set settings=excluded.settings,updated_at=now();
  end if;
  select settings into p from public.pasr_business_programs where card_id=p_card;
  return jsonb_build_object('card_id',p_card,'settings',coalesce(p,'{}'::jsonb));
end $$;
