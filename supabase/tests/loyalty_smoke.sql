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
 perform set_config('app.user_id','22222222-2222-4222-8222-222222222222',true);
 perform public.pasr_business_community_join('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',campaign);
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
