-- 0065  catalog_search: one row per clean display name.
-- After v3 normalization, pack SKUs collapse to one name ("1664 Blanc" x3).
-- Keep the best-equipped row per name (image > brewery > abv).
create or replace function public.catalog_search(p_query text DEFAULT NULL, p_style text DEFAULT NULL,
  p_na_only boolean DEFAULT false, p_limit integer DEFAULT 30, p_offset integer DEFAULT 0)
returns table(id uuid, name text, style text, abv numeric, is_na_low boolean,
              brewery_name text, country text, image_url text, total bigint)
language sql stable security definer set search_path to 'public' as $function$
  with base as (
    select bc.id, public.tapt_display_name(bc.name) as name, bc.style, bc.abv, bc.is_na_low,
           b.name as brewery_name, b.country,
           coalesce(bc.cutout_url, bc.label_image_url) as image_url
    from beer_catalog bc
    left join brewery b on b.id = bc.brewery_id
    where public.tapt_name_ok(bc.name)
      and (p_query is null or btrim(p_query) = ''
           or bc.name ilike '%' || p_query || '%'
           or b.name  ilike '%' || p_query || '%')
      and (p_style is null or btrim(p_style) = '' or bc.style ilike '%' || p_style || '%')
      and (not coalesce(p_na_only, false) or bc.is_na_low)
  ),
  deduped as (
    select distinct on (lower(name))
      id, name, style, abv, is_na_low, brewery_name, country, image_url
    from base
    order by lower(name), (image_url is null), (brewery_name is null), (abv is null)
  )
  select id, name, style, abv, is_na_low, brewery_name, country, image_url,
         count(*) over() as total
  from deduped
  order by (image_url is null), (brewery_name is null), (abv is null), (style is null), lower(name)
  limit greatest(1, least(coalesce(p_limit, 30), 60))
  offset greatest(0, coalesce(p_offset, 0));
$function$;
