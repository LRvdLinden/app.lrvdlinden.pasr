-- ============================================================================================================
-- Anti-bot voor de openbare formulieren van pasr.nl (aanmelden voor een event, ticket afmelden, en wat later komt).
-- Idempotent; draait in de workflow Backend na 20261127-tickets-klantenkaart.sql.
--
-- Op de website: twee honeypots die een mens niet ziet: een verborgen tekstveld "hp_extra" en een verborgen vinkje
-- "nieuwsbrief_extra" ("Stuur mij aanbiedingen"). Is een van beide ingevuld, dan doet de pagina alsof het gelukt is en
-- stuurt ze niets. Er is geen tijdmeting: snel invullen (wachtwoordmanager, automatisch invullen) is gewoon toegestaan.
-- Voor wie de functies rechtstreeks aanroept, controleren pasr_event_register en pasr_event_ticket_cancel hetzelfde
-- via p_hp (niet leeg = bot; achteraan met een standaardwaarde, de apps hoeven niets mee te sturen): stil niets
-- doen, met een gewoon antwoord. p_fill_ms staat nog in de signatuur voor oudere pagina's, maar wordt genegeerd. Daarnaast een rem per e-mailadres (gehasht) naast de bestaande rem per internetadres
-- (pasr_web_rate_hit in schema.sql).
--
-- Er wordt geen e-mail- of IP-adres bewaard: alleen een gezouten hash van het e-mailadres, hoogstens 2 dagen, en per
-- bot-poging het formulier, de reden en het tijdstip (30 dagen, voor het beheer).
-- ============================================================================================================

-- ------------------------------------------------------------------------------------------- logboek van bots
create table if not exists public.pasr_form_bot_log (
  id bigint generated always as identity primary key,
  form text not null check (char_length(form) <= 40),
  reason text not null check (reason in ('honeypot', 'too_fast')),   -- too_fast: alleen nog in oude regels
  at timestamptz not null default now()
);
create index if not exists pasr_form_bot_log_at on public.pasr_form_bot_log (at);
alter table public.pasr_form_bot_log enable row level security;
revoke all on public.pasr_form_bot_log from public, anon, authenticated;

create or replace function public.pasr_form_bot(p_form text, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.pasr_form_bot_log (form, reason)
  values (left(coalesce(p_form, '?'), 40), case when p_reason = 'honeypot' then 'honeypot' else 'too_fast' end);
  delete from public.pasr_form_bot_log where at < now() - interval '30 days';
exception when others then
  raise warning 'pasr_form_bot: % (%)', sqlerrm, sqlstate;   -- het logboek houdt nooit iets tegen
end $$;

-- ------------------------------------------------------------------------------------- rem per sleutel (e-mail)
create table if not exists public.pasr_form_rate (
  bucket text not null,
  key_hash text not null,
  day date not null,
  n integer not null default 0,
  primary key (bucket, key_hash, day)
);
alter table public.pasr_form_rate enable row level security;
revoke all on public.pasr_form_rate from public, anon, authenticated;

-- Telt een poging voor (bucket, sleutel) vandaag; boven p_per_day: 'rate_limited' (zelfde code als pasr_web_rate_hit,
-- de website toont dan "Even rustig aan"). De sleutel (bv. het e-mailadres) gaat gezouten gehasht de tabel in.
create or replace function public.pasr_form_rate_hit(p_bucket text, p_key text, p_per_day integer) returns void
language plpgsql security definer set search_path = '' as $$
declare salt text := ''; h text; used integer; today date := (now() at time zone 'utc')::date;
begin
  if coalesce(btrim(p_key), '') = '' then return; end if;
  if to_regclass('public.pasr_secret') is not null then
    begin
      execute 'select coalesce(hook_secret, '''') from public.pasr_secret where id = 1' into salt;
    exception when others then salt := '';
    end;
  end if;
  h := encode(sha256(convert_to(coalesce(salt, '') || '|' || p_bucket || '|' || lower(btrim(p_key)), 'UTF8')), 'hex');
  insert into public.pasr_form_rate as r (bucket, key_hash, day, n) values (p_bucket, h, today, 1)
    on conflict (bucket, key_hash, day) do update set n = r.n + 1 returning n into used;
  delete from public.pasr_form_rate where day < today - 1;
  if used > p_per_day then
    raise exception 'rate_limited' using errcode = '22023', hint = 'rate_limited';
  end if;
end $$;

-- Tellingen voor het beheer (service role): bot-pogingen per formulier en reden, laatste 24 uur en 7 dagen.
create or replace function public.pasr_form_bot_stats() returns json
language sql stable security definer set search_path = '' as $$
  select json_build_object(
    'day', coalesce((select json_object_agg(form || ':' || reason, n) from (
      select form, reason, count(*) as n from public.pasr_form_bot_log where at > now() - interval '24 hours' group by 1, 2) x), '{}'::json),
    'week', coalesce((select json_object_agg(form || ':' || reason, n) from (
      select form, reason, count(*) as n from public.pasr_form_bot_log where at > now() - interval '7 days' group by 1, 2) y), '{}'::json));
$$;

revoke all on function public.pasr_form_bot(text, text), public.pasr_form_rate_hit(text, text, integer),
  public.pasr_form_bot_stats() from public, anon, authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.pasr_form_bot_stats() to service_role;
    grant select on public.pasr_form_bot_log to service_role;
  end if;
end $$;
