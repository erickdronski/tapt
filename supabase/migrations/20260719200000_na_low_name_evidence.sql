-- Audit fix (No/Low accuracy): is_na_low was decided by ABV alone
-- (`v_abv is not null and v_abv <= 0.5`) in both ingest paths. Open Food Facts
-- and Wikidata very often carry no ABV at all, so beers that say "Non-Alcoholic"
-- or "0.0" right in the name came in flagged alcoholic: Heineken 0.0
-- Non-Alcoholic, Bavaria 0.0 wit, Holsten Non Alco Beer, Affligem Blond 0.0,
-- Desperados Virgin 0.0, and about 120 more.
--
-- That is not cosmetic. recommend_beer restricts a No/Low drinker's candidates
-- to is_na_low, so every one of those beers was invisible to the people looking
-- for exactly them, and the No/Low passport badge undercounted.
--
-- Reading names is risky in the other direction, though: "Barrel Project 20.07"
-- is 10% ABV and "Bière Blonde Extra Forte 10.0" is 10%, and a naive "0.0"
-- search matches both. Telling someone who is not drinking that a barleywine is
-- alcohol free is the worst failure available here. So the rule is deliberately
-- conservative on both sides:
--   * the "0.0" branch requires a non-digit on each side, which rules out
--     20.07, 10.0 and "0.08 EUR" outright;
--   * a known ABV always wins. If the name says alcohol free but the data says
--     5%, we believe the data and leave the flag off.
create or replace function public.tapt_is_na_low(p_name text, p_abv numeric)
returns boolean
language sql
immutable
as $function$
  select case
    -- Measured alcohol is the strongest evidence we have, in both directions.
    when p_abv is not null then p_abv <= 0.5
    when p_name is null then false
    else
      p_name ~* '(alcohol[ -]?free|alkoholfrei|alcohol[ -]?vrij|sans alcool|sin alcohol|senza alcol|analcolic|bez alkoholu|non[- ]?alco|zero[ -]?alcohol)'
      or p_name ~* '(^|[^0-9.,])0[.,]0([^0-9]|$)'
  end;
$function$;

comment on function public.tapt_is_na_low(text, numeric) is
  'Single source of truth for the No/Low flag. Measured ABV wins; otherwise fall back to explicit non-alcoholic wording in the name. Never infers alcohol-free from a bare number that could be a strength or a price.';

-- Point both live ingest paths at the shared rule. Rewriting only the one
-- assignment keeps the rest of each function exactly as deployed.
do $mig$
declare
  d text;
  n text;
begin
  for n, d in
    select p.proname, pg_get_functiondef(p.oid)
    from pg_proc p join pg_namespace nsp on nsp.oid = p.pronamespace
    where nsp.nspname = 'public'
      and p.proname in ('admin_ingest_beers', 'admin_ingest_wikidata_beers')
  loop
    if d !~ 'v_na\s*:=' then
      raise exception 'expected a v_na assignment in %, refusing to patch blind', n;
    end if;
    d := regexp_replace(d, 'v_na\s*:=[^;]+;',
                        'v_na := public.tapt_is_na_low(v_name, v_abv);');
    execute d;
  end loop;
end
$mig$;

-- Backfill what the ABV-only rule missed. Rows with a known ABV are already
-- correct, so this only ever adds flags where the name is explicit.
update public.beer_catalog b
set is_na_low = true
where not coalesce(b.is_na_low, false)
  and public.tapt_is_na_low(coalesce(nullif(b.display_name, ''), b.name), b.abv);

-- New functions default to EXECUTE for PUBLIC, which would quietly add this to
-- the anon RPC surface (the 0081 gotcha). Every caller is SECURITY DEFINER and
-- runs as the owner, so no client role needs it.
revoke all on function public.tapt_is_na_low(text, numeric) from public;
grant execute on function public.tapt_is_na_low(text, numeric) to service_role;
