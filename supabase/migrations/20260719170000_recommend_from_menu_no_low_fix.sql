-- Audit fix (responsible framing), twin of recommend_beer: the literal "No / Low"
-- onboarding chip lives in taste_vector.top_styles and was unnested as a BJCP
-- style, so a sober-curious user scanning a bar menu could be handed a
-- full-strength beer. Now it is treated as a preference: stripped from affinity,
-- and when set the menu candidates are restricted to is_na_low. If the menu has
-- no NA option the card simply does not appear, which is the honest outcome --
-- we never push a full-strength pour at someone who asked for No/Low.
create or replace function public.recommend_from_menu(p_user uuid, p_beer_ids uuid[])
 returns table(beer_id uuid, name text, brewery text, style text, country text, image_url text, abv numeric, reason text, match_kind text)
 language sql stable security definer set search_path to 'public'
as $function$
  with
  pref as (
    select bool_or(lower(coalesce(tv.s,'')) ~ 'no\s*/?\s*low|non.?alco|alcohol.?free') as wants_nolow
    from public.taste_vector t, unnest(t.top_styles) tv(s)
    where t.user_id = p_user
  ),
  liked as (
    select tv.s as style_name, 3 as weight
    from public.taste_vector t, unnest(t.top_styles) tv(s)
    where t.user_id = p_user
      and lower(coalesce(tv.s,'')) !~ 'no\s*/?\s*low|non.?alco|alcohol.?free'
    union all
    select b.style_ref, 2 from public.beer_vote v join public.beer_catalog b on b.id = v.beer_id
    where v.user_id = p_user and v.value > 0 and b.style_ref is not null
    union all
    select b.style_ref, 2 from public.checkin_event c join public.beer_catalog b on b.id = c.beer_id
    where c.user_id = p_user and c.rating >= 4 and b.style_ref is not null
  ),
  style_affinity as (
    select style_name, sum(weight)::int as score from liked where coalesce(style_name,'') <> '' group by style_name
  ),
  family_affinity as (
    select distinct sr.style_family from style_affinity a
    join public.beer_style_reference sr on sr.style_name = a.style_name where sr.style_family is not null
  ),
  had as (
    select beer_id from public.beer_vote where user_id = p_user
    union select beer_id from public.checkin_event where user_id = p_user and beer_id is not null
  ),
  signal as (
    select (select count(*) from style_affinity) as styles,
           coalesce((select wants_nolow from pref), false) as nolow
  ),
  scored as (
    select b.id, coalesce(nullif(b.display_name,''), b.name) as dname, br.name as brewery,
      b.style_ref as style, public.tapt_trusted_country(br.country, br.external_ids) as country,
      coalesce(b.cutout_url, b.label_image_url) as image_url, b.abv, sr.style_family,
      case
        when exists (select 1 from style_affinity a where a.style_name = b.style_ref) then 'love'
        when sr.style_family in (select style_family from family_affinity) then 'adjacent'
        else 'wildcard' end as match_kind,
      (case
         when exists (select 1 from style_affinity a where a.style_name = b.style_ref) then 100
         when sr.style_family in (select style_family from family_affinity) then 70 else 20 end)
      + (case when b.id in (select beer_id from had) then 0 else 15 end)
      + (case when exists (select 1 from public.beer_award aw where aw.beer_id = b.id) then 15 else 0 end)
      as score
    from public.beer_catalog b
    left join public.beer_style_reference sr on sr.style_name = b.style_ref
    left join public.brewery br on br.id = b.brewery_id
    where b.id = any(p_beer_ids)
      and b.name_ok
      and ((select styles from signal) > 0 or (select nolow from signal))
      and (not (select nolow from signal) or coalesce(b.is_na_low, false))
  ),
  pick as (select * from scored order by score desc, dname limit 1)
  select p.id, p.dname, p.brewery, p.style, p.country, p.image_url, p.abv,
    case p.match_kind
      when 'love' then 'Your pick here: a ' || coalesce(p.style, 'beer') || coalesce(' from ' || p.brewery, '') || ', right in your wheelhouse.'
      when 'adjacent' then 'Your pick here: this ' || coalesce(p.style, 'beer') || ' is a fresh angle on the ' || p.style_family || ' you lean into.'
      else 'Worth a try off this menu: ' || coalesce(p.style, 'a solid pour') || coalesce(' from ' || p.brewery, '') || '.'
    end as reason,
    p.match_kind
  from pick p;
$function$;