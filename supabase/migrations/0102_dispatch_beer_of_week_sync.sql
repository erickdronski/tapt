-- 0102_dispatch_beer_of_week_sync.sql
-- The Tapt Dispatch newsletter must feature the SAME Beer of the Week that the app
-- crowns, so the landing claim ("the same one crowned in the app") is true.
--
-- build_dispatch_content previously picked the featured beer with a weekly-seeded
-- md5 shuffle, which did not match the app's real winner (beer_of_week_winner).
-- Rewrite the `featured` CTE to prefer the app's latest Beer of the Week winner,
-- and keep the deterministic weekly pick only as a fallback so an issue always has
-- a featured beer before any winner exists (pre-launch). Style, country, and image
-- are read the same way the app reads them (style_ref resolved, tapt_trusted_country,
-- cutout over label). Everything else in the builder is unchanged.

create or replace function public.build_dispatch_content()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  with wk as (
    select (extract(isoyear from now())::int * 100 + extract(week from now())::int)::text as w
  ),
  featured as (
    -- 1) the app's real Beer of the Week (latest winner) so app + newsletter match.
    -- 2) fallback: a deterministic weekly pick if no winner exists yet.
    select id, name, style, abv, image, brewery, country
    from (
      select bc.id,
             coalesce(nullif(bc.display_name, ''), bc.name) as name,
             coalesce(nullif(bc.style_ref, ''), bc.style) as style,
             bc.abv,
             coalesce(bc.cutout_url, bc.label_image_url) as image,
             br.name as brewery,
             public.tapt_trusted_country(br.country, br.external_ids) as country,
             1 as pri,
             to_char(w.week_start, 'YYYY-MM-DD') as ord
      from public.beer_of_week_winner w
      join public.beer_catalog bc on bc.id = w.beer_id
      left join public.brewery br on br.id = bc.brewery_id
      union all
      select bc.id,
             coalesce(nullif(bc.display_name, ''), bc.name) as name,
             coalesce(nullif(bc.style_ref, ''), bc.style) as style,
             bc.abv,
             coalesce(bc.cutout_url, bc.label_image_url) as image,
             br.name as brewery,
             public.tapt_trusted_country(br.country, br.external_ids) as country,
             2 as pri,
             md5(bc.id::text || wk.w) as ord
      from public.beer_catalog bc
      join public.brewery br on br.id = bc.brewery_id
      cross join wk
      where coalesce(bc.cutout_url, bc.label_image_url) is not null
        and bc.abv is not null and nullif(bc.style, '') is not null
        and bc.name_ok
        and bc.display_name ~ '^[A-Za-z]' and length(bc.display_name) between 4 and 34
    ) c
    order by pri asc, ord desc
    limit 1
  ),
  style as (
    select style_name, style_family, description, abv_min, abv_max,
           ibu_min, ibu_max, source_url
    from public.beer_style_reference, wk
    where nullif(description, '') is not null
    order by md5(id::text || wk.w)
    limit 1
  )
  select jsonb_build_object(
    'week', (select w from wk),
    'featured', (select row_to_json(f) from featured f),
    'style', (select row_to_json(s) from style s),
    'stats', jsonb_build_object(
      'beers', (select count(*) from public.beer_catalog),
      'breweries', (select count(*) from public.brewery),
      'venues', (select count(*) from public.venue),
      'styles', (select count(*) from public.beer_style_reference),
      'countries', (select count(distinct country) from public.brewery where country is not null)
    )
  );
$function$;
