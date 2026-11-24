-- Fictieve ondernemers en transacties; draait alleen in geïsoleerd CI-Postgres.
do $$
declare p jsonb; state jsonb; promo_id uuid;
begin
 perform set_config('app.user_id','11111111-1111-4111-8111-111111111111',true);
 p:=public.pasr_business_promo_save(jsonb_build_object(
   'business_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'code','KOFFIE20','title','Korting op koffie','discount_type','percent',
   'discount_value',20,'min_spend',5,
   'starts_at',now()-interval '1 hour','ends_at',now()+interval '1 day',
   'max_uses',2,'active',true));
 if (p->>'ok')::boolean is not true then raise exception 'Promo insert failed: %',p; end if;
 promo_id:=(p->>'id')::uuid;
 if jsonb_array_length(public.pasr_business_promo_list('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'))<>1 then
   raise exception 'Promo not visible for owner';
 end if;
 state:=public.pasr_business_promo_check('koffie20');
 if (state->>'valid')::boolean is not true then raise exception 'Valid promotion was rejected'; end if;
 perform public.pasr_business_promo_redeem('KOFFIE20');
 perform public.pasr_business_promo_redeem('KOFFIE20');
 if (select used_count from public.pasr_business_promo_codes where id=promo_id)<>2 then
   raise exception 'Wrong usage count';
 end if;
 state:=public.pasr_business_promo_check('KOFFIE20');
 if (state->>'valid')::boolean is true then raise exception 'Exhausted code still valid'; end if;
 begin
   perform public.pasr_business_promo_redeem('KOFFIE20');
   raise exception 'Third redemption unexpectedly allowed';
 exception when sqlstate '22023' then null;
 end;
 perform set_config('app.user_id','22222222-2222-4222-8222-222222222222',true);
 begin
   perform public.pasr_business_promo_list('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
   raise exception 'Other owner can see promo codes';
 exception when sqlstate '42501' then null;
 end;
 begin
   perform public.pasr_business_promo_redeem('KOFFIE20');
   raise exception 'Other business can redeem promo code';
 exception when sqlstate '42501' then null;
 end;
 raise notice 'PASR PROMO SMOKE TEST PASSED';
end $$;
