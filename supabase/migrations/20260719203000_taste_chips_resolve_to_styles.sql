-- Audit fix (the recommender barely heard onboarding): the taste chips are
-- family words -- IPA, Lager, Sour, Belgian, Wheat, Pale Ale, Porter, Pilsner --
-- and they go into taste_vector.top_styles verbatim. recommend_beer then builds
-- style_affinity by matching those strings for exact equality against
-- beer_catalog.style_ref, which holds resolved style names like "Hazy IPA",
-- "Witbier", "Gose", "Belgian Tripel", "Munich Helles".
--
-- Measured against the live catalog, of the 11 chips only two ("Hazy IPA" and
-- "Stout") match a single beer by exact style_ref. The other nine, including the
-- most-picked "IPA", match ZERO beers. family_affinity does not save it either,
-- since that joins beer_style_reference on style_name and nine chips are not
-- style names. So for most people the entire onboarding taste step contributed
-- nothing at all: every candidate fell through to "wildcard".
--
-- tapt_taste_chip_styles resolves a chip to the canonical styles it actually
-- means, and both recommenders now expand chips through it. "No / Low"
-- deliberately resolves to nothing here because it is not a flavour preference:
-- it is already handled upstream by restricting candidates to is_na_low.
create or replace function public.tapt_taste_chip_styles(p_label text)
returns setof text
language sql
stable
as $function$
  select r.style_name
  from public.beer_style_reference r
  where case lower(btrim(coalesce(p_label, '')))
    when 'ipa'      then r.style_family = 'IPA'
    when 'hazy ipa' then r.style_name ~* 'hazy|new england|neipa'
    when 'pilsner'  then r.style_name ~* 'pilsner|pils'
    when 'lager'    then r.style_family = 'Lager'
    when 'stout'    then r.style_name ~* 'stout'
    when 'porter'   then r.style_name ~* 'porter'
    when 'sour'     then r.style_family = 'Sour'
    when 'belgian'  then r.style_family = 'Belgian'
    when 'wheat'    then r.style_family = 'Wheat'
    when 'pale ale' then r.style_family = 'Pale Ale'
    else false
  end;
$function$;

comment on function public.tapt_taste_chip_styles(text) is
  'Resolves an onboarding taste chip (a family word) to the canonical style names it covers. Keep in sync with TastePreferences.options in the app.';

-- Add one UNION ALL branch to each recommender's `liked` CTE, in place, so the
-- rest of the scoring stays exactly as deployed.
do $mig$
declare
  d text;
  n text;
  anchor text := 'union all
    select b.style_ref, 2 from public.beer_vote v';
  expansion text := 'union all
    -- a chip like "IPA" or "Sour" is a family word, not a style name: expand it
    -- to the canonical styles it covers, otherwise it matches nothing at all
    select cs, 3
    from public.taste_vector t, unnest(t.top_styles) tv(s),
         lateral public.tapt_taste_chip_styles(tv.s) cs
    where t.user_id = p_user
    union all
    select b.style_ref, 2 from public.beer_vote v';
begin
  for n, d in
    select p.proname, pg_get_functiondef(p.oid)
    from pg_proc p join pg_namespace nsp on nsp.oid = p.pronamespace
    where nsp.nspname = 'public' and p.proname in ('recommend_beer', 'recommend_from_menu')
  loop
    if position(anchor in d) = 0 then
      raise exception 'no liked-CTE anchor in %, refusing to patch blind', n;
    end if;
    if position('tapt_taste_chip_styles' in d) > 0 then
      continue;  -- already expanded
    end if;
    execute replace(d, anchor, expansion);
  end loop;
end
$mig$;

-- Same PUBLIC-grant gotcha: keep this off the anon RPC surface. recommend_beer
-- and recommend_from_menu are SECURITY DEFINER, so they reach it as the owner.
revoke all on function public.tapt_taste_chip_styles(text) from public;
grant execute on function public.tapt_taste_chip_styles(text) to service_role;
