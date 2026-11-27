-- Isolated smoke test for add-on loyalty modules, using fictitious accounts only.
do $$
declare
 campaign uuid;
 progress jsonb;
 result jsonb;
 code text := 'PZABCDEF2345';
begin
 perform set_config('app.user_id','11111111-1111-4111-8111-111111111111',true);
 result := public.pasr_business_community_create(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Winkelstraatpas','Gratis koek',2,30);
 campaign := (result->>'id')::uuid;
 if campaign is null then raise exception 'Community campaign not created'; end if;
 -- Sinds 27-11-2026 alleen op uitnodiging: de organisator nodigt uit, de andere zaak accepteert.
 perform set_config('app.user_id','33333333-3333-4333-8333-333333333333',true);
 if jsonb_array_length(public.pasr_business_community_progress()) <> 0 then raise exception 'Waiting campaign visible to customer'; end if;
 perform set_config('app.user_id','11111111-1111-4111-8111-111111111111',true);
 result := public.pasr_business_community_invite('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',campaign,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')::jsonb;
 perform set_config('app.user_id','22222222-2222-4222-8222-222222222222',true);
 perform public.pasr_business_community_respond('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',(result->>'invite_id')::uuid,true);
 perform set_config('app.user_id','33333333-3333-4333-8333-333333333333',true);
 progress:=public.pasr_business_community_progress();
 if jsonb_array_length(progress) <> 1 then raise exception 'Community progress not visible'; end if;
 if (progress->0->>'visited')::int <> 0 then raise exception 'Community progress should start at zero'; end if;
 perform set_config('app.user_id','11111111-1111-4111-8111-111111111111',true);
 insert into public.pasr_business_events(business_card_id,business_id,member_id,kind,amount,at)
 values('cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','stamp',1,now());
 insert into public.pasr_business_events(business_card_id,business_id,member_id,kind,amount,at)
 values('dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'ffffffff-ffff-4fff-8fff-ffffffffffff','stamp',1,now());
 perform set_config('app.user_id','33333333-3333-4333-8333-333333333333',true);
 progress:=public.pasr_business_community_progress();
 if (progress->0->>'visited')::int <> 2 then raise exception 'Two visited businesses not counted: %',progress; end if;
 perform set_config('app.user_id','11111111-1111-4111-8111-111111111111',true);
 result := public.pasr_business_community_claim(campaign,
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',code);
 if (result->>'ok')::boolean is not true then raise exception 'Community claim failed'; end if;
 begin
  perform public.pasr_business_community_claim(campaign,
     'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',code);
  raise exception 'Duplicate community claim unexpectedly succeeded';
 exception when sqlstate '22023' then null;
 end;
 perform set_config('app.user_id','33333333-3333-4333-8333-333333333333',true);
 progress:=public.pasr_business_community_progress();
 if (progress->0->>'claimed')::boolean is not true then raise exception 'Claim not visible'; end if;

 -- Explicit consent then time-based reminder; no anonymous opt-in.
 result := public.pasr_business_retention_consent(code,true);
 if (result->>'enabled')::boolean is not true then raise exception 'Retention opt-in failed'; end if;
 result := public.pasr_business_retention_status(code);
 if (result->>'enabled')::boolean is not true then raise exception 'Retention status failed'; end if;
 update public.pasr_business_retention_consents
   set consented_at=now()-interval '2 days' where member_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
 result := public.pasr_business_retention_due(50);
 if jsonb_array_length(result) <> 1 then raise exception 'Expected 1 due reminder, got %',result; end if;
 if public.pasr_business_retention_sent(
   'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
   (select last_stamp_at from public.pasr_business_members where member_code=code)) is not true
 then raise exception 'Retention receipt acknowledgement failed'; end if;
 result:=public.pasr_business_retention_due(50);
 if jsonb_array_length(result) <> 0 then raise exception 'Duplicate reminder due: %',result; end if;
 perform public.pasr_business_retention_consent(code,false);

 -- A one-stamp base scan with a double-stamp promo must really add TWO.
 perform set_config('app.user_id','11111111-1111-4111-8111-111111111111',true);
 result:=public.pasr_business_stamp(code,1,'smoke');
 if (result->>'stamps_added')::int <> 2 then raise exception 'Multiplier not applied: %',result; end if;
 if (select stamps_count from public.pasr_business_members where member_code=code) <> 2
 then raise exception 'Stored stamps mismatch'; end if;
 raise notice 'PASR LOYALTY SMOKE TEST PASSED';
end $$;

-- Gezamenlijke acties (herziening 27-11-2026): lijst met rollen, kassa-controle, uitstappen, stoppen.
do $$
declare
 campaign uuid;
 second uuid;
 rows jsonb;
 progress jsonb;
 a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
begin
 perform set_config('app.user_id','11111111-1111-4111-8111-111111111111',true);
 rows := public.pasr_business_community_list(a);
 campaign := (rows->0->>'id')::uuid;
 if (rows->0->>'is_lead')::boolean is not true then raise exception 'Lead flag missing: %',rows; end if;
 if jsonb_array_length(rows->0->'participant_names') <> 2 then raise exception 'Participant names missing: %',rows; end if;
 if (rows->0->>'claims_here')::int <> 1 then raise exception 'Claims at business not counted: %',rows; end if;
 if (rows->0->>'can_manage')::boolean is not true then raise exception 'Owner cannot manage: %',rows; end if;
 rows := public.pasr_business_community_member(a,'pzabcdef2345');
 if jsonb_array_length(rows) <> 1 or (rows->0->>'visited')::int <> 2 or (rows->0->>'claimed')::boolean is not true
 then raise exception 'Register check wrong: %',rows; end if;
 if public.pasr_business_community_member(a,'PZONBEKEND22') <> '[]'::jsonb then raise exception 'Unknown code should be empty'; end if;
 begin
  perform public.pasr_business_community_leave(a,campaign);
  raise exception 'Lead could leave own campaign';
 exception when sqlstate '22023' then null;
 end;

 perform set_config('app.user_id','22222222-2222-4222-8222-222222222222',true);
 rows := public.pasr_business_community_list(b);
 if (rows->0->>'is_lead')::boolean is not false or (rows->0->>'joined')::boolean is not true then raise exception 'Participant view wrong: %',rows; end if;
 begin
  perform public.pasr_business_community_cancel(b,campaign);
  raise exception 'Participant could cancel someone else''s campaign';
 exception when sqlstate '22023' then null;
 end;
 perform public.pasr_business_community_leave(b,campaign);
 perform set_config('app.user_id','33333333-3333-4333-8333-333333333333',true);
 -- Na uitstappen doet alleen de organisator nog mee: onder het minimum, dus de klant ziet de actie niet meer.
 progress := public.pasr_business_community_progress();
 if jsonb_array_length(progress) <> 0 then raise exception 'Campaign below minimum still visible: %',progress; end if;
 perform set_config('app.user_id','11111111-1111-4111-8111-111111111111',true);
 perform public.pasr_business_community_settings(a,campaign,null,2);
 if public.pasr_business_community_list(a)->0->>'state' <> 'waiting' then raise exception 'State should be waiting'; end if;
 perform set_config('app.user_id','33333333-3333-4333-8333-333333333333',true);
 begin
  perform public.pasr_business_community_list(a);
  raise exception 'Customer could list business campaigns';
 exception when sqlstate '42501' then null;
 end;
 begin
  perform public.pasr_business_community_member(a,'PZABCDEF2345');
  raise exception 'Customer could use the register check';
 exception when sqlstate '42501' then null;
 end;

 perform set_config('app.user_id','22222222-2222-4222-8222-222222222222',true);
 begin
  perform public.pasr_business_community_join(b,campaign);
  raise exception 'Joined without invitation';
 exception when sqlstate '42501' then null;
 end;
 perform set_config('app.user_id','11111111-1111-4111-8111-111111111111',true);
 perform public.pasr_business_community_invite(a,campaign,b);
 perform set_config('app.user_id','22222222-2222-4222-8222-222222222222',true);
 perform public.pasr_business_community_join(b,campaign);   -- met een uitnodiging telt meedoen als accepteren
 perform set_config('app.user_id','33333333-3333-4333-8333-333333333333',true);
 progress := public.pasr_business_community_progress();
 if jsonb_array_length(progress) <> 1 or jsonb_array_length(progress->0->'businesses') <> 2 then raise exception 'Rejoined campaign wrong: %',progress; end if;
 -- bezoeken bij de opnieuw toegetreden zaak tellen pas vanaf het nieuwe meedoen
 if (progress->0->>'visited')::int <> 1 or progress->0->>'ends_at' is null
 then raise exception 'Customer business list wrong: %',progress; end if;
 perform set_config('app.user_id','11111111-1111-4111-8111-111111111111',true);
 second := (public.pasr_business_community_create(a,'Kerstroute','Gratis chocolademelk',2,20)->>'id')::uuid;
 perform public.pasr_business_community_invite(a,second,b);
 perform set_config('app.user_id','22222222-2222-4222-8222-222222222222',true);
 perform public.pasr_business_community_respond(b,(select invite_id from public.pasr_business_community_my_invites(b) limit 1),true);
 perform set_config('app.user_id','33333333-3333-4333-8333-333333333333',true);
 if jsonb_array_length(public.pasr_business_community_progress()) <> 2 then raise exception 'Second campaign not visible'; end if;
 perform set_config('app.user_id','11111111-1111-4111-8111-111111111111',true);
 perform public.pasr_business_community_cancel(a,second);
 begin
  perform public.pasr_business_community_join(b,second);
  raise exception 'Joined a cancelled campaign';
 exception when sqlstate '42501' or sqlstate '22023' then null;
 end;
 perform set_config('app.user_id','33333333-3333-4333-8333-333333333333',true);
 if jsonb_array_length(public.pasr_business_community_progress()) <> 1 then raise exception 'Cancelled campaign still visible'; end if;
 raise notice 'PASR COMMUNITY CAMPAIGN TEST PASSED';
end $$;
