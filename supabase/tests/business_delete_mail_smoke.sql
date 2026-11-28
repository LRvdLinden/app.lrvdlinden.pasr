-- Mails bij het verwijderen van een zaak (20261128-business-delete-mail.sql): wie krijgt een mail, met verzonnen zaken.
-- Draait na business_delete_smoke.sql in de PR-check "backend-integration". Alleen testomgeving.
alter table auth.users add column if not exists email text;
alter table public.pasr_businesses add column if not exists email text not null default '';

insert into auth.users(id, email) values
 ('e0000001-0000-4000-8000-000000000001', 'eigenaar-x@zaak-x.example'),
 ('e0000002-0000-4000-8000-000000000002', 'Eigenaar-Y@Zaak-Y.example'),
 ('e0000003-0000-4000-8000-000000000003', 'account-z@zaak-z.example'),
 ('e0000004-0000-4000-8000-000000000004', 'eigenaar-w@zaak-w.example'),
 ('e0000005-0000-4000-8000-000000000005', null)
on conflict (id) do update set email = excluded.email;
delete from public.pasr_businesses where id in ('e1000001-0000-4000-8000-000000000001', 'e1000002-0000-4000-8000-000000000002',
  'e1000003-0000-4000-8000-000000000003', 'e1000004-0000-4000-8000-000000000004', 'e1000005-0000-4000-8000-000000000005');
insert into public.pasr_businesses(id, owner, name, city, email) values
 ('e1000001-0000-4000-8000-000000000001', 'e0000001-0000-4000-8000-000000000001', 'Weg <b>Zaak</b>', 'Apeldoorn', 'Info@Zaak-X.example'),
 ('e1000002-0000-4000-8000-000000000002', 'e0000002-0000-4000-8000-000000000002', 'Zaak Y', 'Apeldoorn', ''),             -- adres van het account
 ('e1000003-0000-4000-8000-000000000003', 'e0000003-0000-4000-8000-000000000003', 'Zaak Z', 'Apeldoorn', 'info@zaak-y.example'), -- zelfde adres als Y (na kleine letters): één mail
 ('e1000004-0000-4000-8000-000000000004', 'e0000004-0000-4000-8000-000000000004', 'Zaak W', 'Apeldoorn', 'info@zaak-w.example'),
 ('e1000005-0000-4000-8000-000000000005', 'e0000005-0000-4000-8000-000000000005', 'Zaak V zonder adres', 'Apeldoorn', '');

do $$
declare
 x uuid := 'e1000001-0000-4000-8000-000000000001'; y uuid := 'e1000002-0000-4000-8000-000000000002';
 z uuid := 'e1000003-0000-4000-8000-000000000003'; w uuid := 'e1000004-0000-4000-8000-000000000004';
 v uuid := 'e1000005-0000-4000-8000-000000000005';
 ux uuid := 'e0000001-0000-4000-8000-000000000001';
 xc uuid; xold uuid; xcancel uuid; yc uuid; yend uuid; zc uuid;
 r jsonb; res jsonb; pv jsonb; n int; mails text[];
begin
 -- acties van X: een lopende (deelnemers Y, Z, V; uitgenodigd: W, een adres, een verlopen, een ingetrokken), een afgelopen en een geannuleerde
 insert into public.pasr_business_community_campaigns(lead_business_id, name, reward, required_businesses, starts_at, ends_at)
   values (x, 'Lopende <i>actie</i>', 'Gratis koffie', 3, now() - interval '1 day', now() + interval '30 days') returning id into xc;
 insert into public.pasr_business_community_campaigns(lead_business_id, name, reward, required_businesses, starts_at, ends_at)
   values (x, 'Oude actie', 'Taart', 2, now() - interval '20 days', now() + interval '1 hour') returning id into xold;
 update public.pasr_business_community_campaigns set ends_at = now() - interval '1 hour', starts_at = now() - interval '2 days' where id = xold;
 insert into public.pasr_business_community_campaigns(lead_business_id, name, reward, required_businesses, ends_at, cancelled_at)
   values (x, 'Geannuleerde actie', 'Taart', 2, now() + interval '5 days', now()) returning id into xcancel;
 insert into public.pasr_business_community_participants(campaign_id, business_id, accepted_by) values
   (xc, x, ux), (xc, y, ux), (xc, z, ux), (xc, v, ux), (xold, y, ux), (xcancel, y, ux);
 insert into public.pasr_business_community_invites(campaign_id, business_id, email, status, expires_at, token_hash) values
   (xc, w, null, 'invited', null, null),
   (xc, null, 'Gast@Voorbeeld.example', 'invited', now() + interval '5 days', repeat('1', 64)),
   (xc, null, 'verlopen@voorbeeld.example', 'invited', now() - interval '1 day', repeat('2', 64)),
   (xc, null, 'ingetrokken@voorbeeld.example', 'revoked', null, repeat('3', 64)),
   (xc, y, null, 'accepted', null, null);
 insert into public.pasr_business_community_invites(campaign_id, email, token_hash, status) values (xc, 'ander@voorbeeld.example', repeat('a', 64), 'invited');
 -- acties van anderen waaraan X meedoet: Y organiseert een lopende (X deelnemer), een afgelopen en Z een lopende zonder adres? (Z heeft adres)
 insert into public.pasr_business_community_campaigns(lead_business_id, name, reward, required_businesses, ends_at)
   values (y, 'Actie van Y', 'Thee', 2, now() + interval '10 days') returning id into yc;
 insert into public.pasr_business_community_campaigns(lead_business_id, name, reward, required_businesses, starts_at, ends_at)
   values (y, 'Afgelopen actie van Y', 'Thee', 2, now() - interval '9 days', now() + interval '1 hour') returning id into yend;
 update public.pasr_business_community_campaigns set ends_at = now() - interval '1 hour', starts_at = now() - interval '3 days' where id = yend;
 insert into public.pasr_business_community_campaigns(lead_business_id, name, reward, required_businesses, ends_at)
   values (v, 'Actie van V zonder adres', 'Thee', 2, now() + interval '10 days') returning id into zc;
 insert into public.pasr_business_community_participants(campaign_id, business_id, accepted_by) values (yc, y, ux), (yc, x, ux), (yend, x, ux), (zc, x, ux);

 -- rechten
 if has_function_privilege('authenticated', 'public.pasr_admin_business_delete_recipients(uuid)', 'execute')
    or has_function_privilege('anon', 'public.pasr_admin_business_delete_recipients(uuid)', 'execute')
    or has_function_privilege('authenticated', 'public.pasr_admin_business_contact(uuid)', 'execute')
    or has_function_privilege('anon', 'public.pasr_admin_business_delete(uuid)', 'execute')
 then raise exception 'Recipient functions must not be executable by anon or authenticated'; end if;

 -- adressen: zaak-adres eerst, dan het account; kleine letters; null zonder adres
 if public.pasr_admin_business_contact(x) <> 'info@zaak-x.example' then raise exception 'contact x'; end if;
 if public.pasr_admin_business_contact(y) <> 'eigenaar-y@zaak-y.example' then raise exception 'contact y: %', public.pasr_admin_business_contact(y); end if;
 if public.pasr_admin_business_contact(v) is not null then raise exception 'contact v should be null'; end if;

 r := public.pasr_admin_business_delete_recipients(x);
 if r->>'owner' <> 'info@zaak-x.example' then raise exception 'owner %', r; end if;
 if jsonb_array_length(r->'campaigns') <> 1 or r#>>'{campaigns,0,title}' <> 'Lopende <i>actie</i>' or r#>>'{campaigns,0,reward}' <> 'Gratis koffie'
 then raise exception 'Only the running campaign gets a cancellation: %', r; end if;
 select array_agg(e order by e) into mails from jsonb_array_elements_text(r#>'{campaigns,0,recipients}') e;
 -- Y (account-adres) en Z (zaak-adres dat gelijk is aan dat van Y) tellen één keer; V heeft geen adres; W uitgenodigd; adres-uitnodigingen
 if mails is distinct from array['ander@voorbeeld.example', 'eigenaar-y@zaak-y.example', 'gast@voorbeeld.example', 'info@zaak-w.example', 'info@zaak-y.example']
 then raise exception 'Recipients wrong: %', mails; end if;
 -- organisatoren: alleen lopende acties van anderen waaraan X meedoet, en alleen met een adres
 if jsonb_array_length(r->'organizers') <> 1 or r#>>'{organizers,0,title}' <> 'Actie van Y' or r#>>'{organizers,0,email}' <> 'eigenaar-y@zaak-y.example'
 then raise exception 'Organizers wrong: %', r->'organizers'; end if;

 -- preview telt de mails
 pv := public.pasr_admin_business_delete_preview(x);
 if (pv#>>'{counts,mail_participants}')::int <> 6 or (pv#>>'{counts,owner_mail}')::boolean is not true
    or (pv#>>'{counts,campaigns}')::int <> 3 then raise exception 'Preview counts wrong: %', pv; end if;
 if (public.pasr_admin_business_delete_preview(v)#>>'{counts,owner_mail}')::boolean is not false then raise exception 'owner_mail for V'; end if;

 -- verwijderen geeft de ontvangers terug; daarna is alles weg
 res := public.pasr_admin_business_delete(x);
 if res->'notify' <> r then raise exception 'notify must equal the recipients gathered before: % vs %', res->'notify', r; end if;
 if (res->>'campaigns_cancelled')::int <> 3 then raise exception 'campaigns_cancelled %', res; end if;
 if exists (select 1 from public.pasr_businesses where id = x) or exists (select 1 from public.pasr_business_community_campaigns where lead_business_id = x)
 then raise exception 'X not deleted'; end if;
 -- tweede keer: niet gevonden, dus nooit dubbele mails
 begin perform public.pasr_admin_business_delete(x); raise exception 'second delete succeeded';
 exception when others then if sqlerrm <> 'not_found' then raise; end if; end;
 -- de actie van Y loopt door zonder X
 if (select count(*) from public.pasr_business_community_participants where campaign_id = yc) <> 1 then raise exception 'Y campaign participants'; end if;
end $$;
