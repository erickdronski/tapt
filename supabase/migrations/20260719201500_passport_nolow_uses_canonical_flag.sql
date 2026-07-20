-- Audit fix (badge honesty): the passport's No/Low dimension counted beers by
-- substring, `coalesce(b.style_ref, ce.style, b.name) ~* 'non[- ]?alco|alcohol[-
-- ]?free|0[.,]0'`, and unlike every other No/Low check in the schema that bare
-- `0[.,]0` has no percent sign after it and is also matched against the beer
-- NAME. So logging "Barrel Project 20.07" (10% ABV) or "Biere Blonde Extra Forte
-- 10.0" (10%) credited your No/Low progress, and the opposite miss was just as
-- real: a genuine alcohol-free beer whose resolved style is plain "Lager" was
-- never counted at all.
--
-- ExploreView already states the rule the app follows: "No/Low uses the
-- canonical server field, never substring matching." The passport is now the
-- same. is_na_low is the single source of truth, and 20260719200000 made it
-- accurate for beers whose ABV is missing.
--
-- Patched by rewriting only that one filter in the deployed definition, so the
-- rest of public_profile (including the privacy fix in 20260717140000) stays
-- exactly as it is running.
do $mig$
declare
  d text;
begin
  select pg_get_functiondef(p.oid) into d
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'public_profile';

  if d is null or position('non[- ]?alco|alcohol[- ]?free|0[.,]0' in d) = 0 then
    raise exception 'public_profile does not contain the expected No/Low filter, refusing to patch blind';
  end if;

  d := replace(d,
    'filter (where coalesce(b.style_ref, ce.style, b.name) ~* ''non[- ]?alco|alcohol[- ]?free|0[.,]0'')',
    'filter (where coalesce(b.is_na_low, false))');

  execute d;
end
$mig$;
