-- Audit fix (responsible framing): a sober-curious user whose taste signal is
-- "No / Low" was handed a full-strength beer (e.g. a 12% barleywine) as their
-- weekly pick. Onboarding stores the literal chip "No / Low" into
-- taste_vector.top_styles, which recommend_beer unnested as if it were a BJCP
-- style_name -- it matches nothing, so every candidate scored as a wildcard and
-- the highest-jitter full-strength beer won. Now: the No/Low chip is detected as
-- a preference (never a style), stripped from affinity, and when set it hard
-- restricts the candidate pool to is_na_low beers. A No/Low-only user still gets
-- a pick (the pool is real NA beer, not empty).
create or replace function public.recommend_beer(p_user uuid)
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
    select b.style_ref, 2
    from public.beer_vote v
    join public.beer_catalog b on b.id = v.beer_id
    where v.user_id = p_user and v.value > 0 and b.style_ref is not null
    union all
    select b.style_ref, 2
    from public.checkin_event c
    join public.beer_catalog b on b.id = c.beer_id
    where c.user_id = p_user and c.rating >= 4 and b.style_ref is not null
  ),
  style_affinity as (
    select style_name, sum(weight)::int as score
    from liked where coalesce(style_name,'') <> ''
    group by style_name
  ),
  family_affinity as (
    select distinct sr.style_family
    from style_affinity a
    join public.beer_style_reference sr on sr.style_name = a.style_name
    where sr.style_family is not null
  ),
  had_ids as (
    select beer_id from public.beer_vote where user_id = p_user
    union select beer_id from public.checkin_event where user_id = p_user and beer_id is not null
  ),
  had_names as (
    select distinct lower(coalesce(nullif(b.display_name,''), b.name)) as dn
    from had_ids h join public.beer_catalog b on b.id = h.beer_id
  ),
  signal as (
    select (select count(*) from style_affinity) as styles,
           coalesce((select wants_nolow from pref), false) as nolow
  ),
  scored as (
    select
      b.id,
      coalesce(nullif(b.display_name,''), b.name) as dname,
      br.name as brewery,
      b.style_ref as style,
      public.tapt_trusted_country(br.country, br.external_ids) as country,
      coalesce(b.cutout_url, b.label_image_url) as image_url,
      b.abv,
      sr.style_family,
      case
        when exists (select 1 from style_affinity a where a.style_name = b.style_ref) then 'love'
        when sr.style_family in (select style_family from family_affinity) then 'adjacent'
        else 'wildcard'
      end as match_kind,
      (case
         when exists (select 1 from style_affinity a where a.style_name = b.style_ref) then 100
         when sr.style_family in (select style_family from family_affinity) then 70
         else 20
       end)
      + (case when exists (select 1 from public.beer_award aw where aw.beer_id = b.id) then 25 else 0 end)
      + (case when b.cutout_url is not null then 10 else 0 end)
      + (abs(('x'||substr(md5(b.id::text || current_date::text),1,6))::bit(24)::int) % 12) as score
    from public.beer_catalog b
    join public.beer_style_reference sr on sr.style_name = b.style_ref
    left join public.brewery br on br.id = b.brewery_id
    where b.name_ok
      and b.style_ref is not null
      and coalesce(b.cutout_url, b.label_image_url) is not null
      and ((select styles from signal) > 0 or (select nolow from signal))
      and (not (select nolow from signal) or coalesce(b.is_na_low, false))
      and b.id not in (select beer_id from had_ids)
      and lower(coalesce(nullif(b.display_name,''), b.name)) not in (select dn from had_names)
  ),
  pick as (
    select * from scored order by score desc, dname limit 1
  )
  select
    p.id, p.dname, p.brewery, p.style, p.country, p.image_url, p.abv,
    case p.match_kind
      when 'love' then
        'Right in your wheelhouse: a ' || p.style
          || coalesce(' from ' || p.brewery, '') || '.'
      when 'adjacent' then
        'You lean into ' || p.style_family || '. This ' || p.style
          || ' is a fresh angle on the same family.'
      else
        'A well-regarded ' || p.style || coalesce(' from ' || p.brewery, '')
          || ' worth a try.'
    end as reason,
    p.match_kind
  from pick p;
$function$;