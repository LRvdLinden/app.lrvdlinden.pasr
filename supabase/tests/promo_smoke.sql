-- Isolated Postgres: owner permissions, safe anonymous catalogs, app-issued PA and PC claims,
-- one-time redemption, post-publication updates and soft-deletion without losing history.
do $$
declare promo jsonb; coupon jsonb; personal jsonb; check_result jsonb;
 v_promo_id uuid; v_coupon_id uuid; pa text; pc text;
begin
 perform set_config('app.user_id','11111111-1111-4111-8111-111111111111',true);
 promo:=public.pasr_business_promo_save(jsonb_build_object(
   'business_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'code','KOFFIE20','title','Korting op koffie','discount_type','percent',
   'discount_value',20,'min_spend',5,
   'starts_at',now()-interval '1 hour','ends_at',now()+interval '1 day',
   'max_uses',2,'active',true));
 v_promo_id:=(promo->>'id')::uuid;
 coupon:=public.pasr_business_coupon_save(jsonb_build_object(
   'business_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'title','Koffievoordeel','description','Alleen via Pasr',
   'discount_type','amount','discount_value',2.5,'min_spend',5,
   'starts_at',now()-interval '1 hour','ends_at',now()+interval '1 day',
   'max_claims',100,'one_per_customer',true,'public',true));
 v_coupon_id:=(coupon->>'id')::uuid;
 if jsonb_array_length(public.pasr_business_promo_public())<>1 then
  raise exception 'Public promo listing failed'; end if;
 if public.pasr_business_promo_public()::text like '%KOFFIE20%' then
  raise exception 'A merchant code leaked via public catalog'; end if;
 if jsonb_array_length(public.pasr_business_coupon_list(null))<>1 then
  raise exception 'Public coupon listing failed'; end if;
 -- Raw merchant code never authorizes redemption.
 begin
   perform public.pasr_business_promo_redeem('KOFFIE20');
   raise exception 'Raw merchant promo was redeemed without Pasr';
 exception when sqlstate 'P0002' then null;
 end;
 perform set_config('app.user_id','33333333-3333-4333-8333-333333333333',true);
 personal:=public.pasr_business_promo_claim(v_promo_id);
 pa:=personal->>'code';
 if pa !~ '^PA[A-HJ-NP-Z2-9]{22}$' then raise exception 'Missing PA claim'; end if;
 if (public.pasr_business_promo_claim(v_promo_id)->>'code') is distinct from pa then
  raise exception 'Duplicate claim issued to same user'; end if;
 pc:=public.pasr_business_coupon_claim(v_coupon_id)->>'code';
 if pc !~ '^PC[A-HJ-NP-Z2-9]{22}$' then raise exception 'Missing PC claim'; end if;
 if jsonb_array_length(public.pasr_business_promo_mine())<>1 then raise exception 'PA missing in app'; end if;
 perform set_config('app.user_id','11111111-1111-4111-8111-111111111111',true);
 check_result:=public.pasr_business_promo_check(pa);
 if (check_result->>'valid')::boolean is not true then raise exception 'Valid PA rejected'; end if;
 perform public.pasr_business_promo_redeem(pa);
 if (select used_count from public.pasr_business_promo_codes where id=v_promo_id)<>1 then
  raise exception 'Wrong promo redemption count'; end if;
 if (public.pasr_business_promo_check(pa)->>'used')::boolean is not true then
  raise exception 'Used promo not marked used'; end if;
 begin
   perform public.pasr_business_promo_redeem(pa);
   raise exception 'PA double redemption succeeded';
 exception when sqlstate '22023' then null;
 end;
 perform public.pasr_business_coupon_redeem(pc);
 if (select redeemed_at from public.pasr_business_coupon_claims where redeem_code=pc) is null then
  raise exception 'PC redemption missing'; end if;
 -- Published offers may be modified, but edits do not erase redemption history.
 perform public.pasr_business_coupon_save(jsonb_build_object(
   'id',v_coupon_id,'business_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'title','Nieuwe titel','description','Aangepast na publicatie',
   'discount_type','amount','discount_value',3,'min_spend',5,
   'starts_at',now()-interval '1 hour','ends_at',now()+interval '2 days',
   'max_claims',100,'one_per_customer',true,'public',true));
 perform public.pasr_business_promo_save(jsonb_build_object(
   'id',v_promo_id,'business_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'code','KOFFIE20','title','Nieuwe actie','discount_type','percent',
   'discount_value',15,'min_spend',5,
   'starts_at',now()-interval '1 hour','ends_at',now()+interval '2 days',
   'max_uses',2,'active',true));
 perform public.pasr_business_discount_remove('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',v_coupon_id,'coupon');
 perform public.pasr_business_discount_remove('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',v_promo_id,'code');
 if jsonb_array_length(public.pasr_business_coupon_list(null))<>0 or
    jsonb_array_length(public.pasr_business_promo_public())<>0 then
    raise exception 'Removed offers are still publicly shown'; end if;
 if (select count(*) from public.pasr_business_coupon_claims where coupon_id=v_coupon_id)<>1 then
  raise exception 'Coupon transaction history lost'; end if;
 if (select count(*) from public.pasr_business_promo_claims where promo_id=v_promo_id)<>1 then
  raise exception 'Promo transaction history lost'; end if;
 perform set_config('app.user_id','22222222-2222-4222-8222-222222222222',true);
 begin
  perform public.pasr_business_discount_remove('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',v_promo_id,'code');
  raise exception 'Different owner removed promo';
 exception when sqlstate '42501' then null;
 end;
 raise notice 'PASR APP-ONLY DISCOUNT AND OWNER EDIT/DELETE TEST PASSED';
end $$;
