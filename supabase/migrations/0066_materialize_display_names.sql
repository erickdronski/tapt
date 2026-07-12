-- 0066  Materialize display names: the v3 normalizer (~12 regexes) is far too
-- heavy per row per request (catalog_search browse hit the API statement
-- timeout). Stored generated columns compute once per row (and automatically
-- for future ingestion); readers hit a plain indexed column. NOTE: changing
-- tapt_display_name/tapt_name_ok later requires dropping + re-adding these
-- columns to recompute.
alter table public.beer_catalog
  add column if not exists display_name text generated always as (public.tapt_display_name(name)) stored,
  add column if not exists name_ok boolean generated always as (public.tapt_name_ok(name)) stored;

create index if not exists beer_catalog_display_name_idx
  on public.beer_catalog (lower(display_name)) where name_ok;

create or replace function public.catalog_search(p_query text DEFAULT NULL, p_style text DEFAULT NULL,
  p_na_only boolean DEFAULT false, p_limit integer DEFAULT 30, p_offset integer DEFAULT 0)
returns table(id uuid, name text, style text, abv numeric, is_na_low boolean,
              brewery_name text, country text, image_url text, total bigint)
language sql stable security definer set search_path to 'public' as $function$
  with base as (
    select bc.id, bc.display_name as name, bc.style, bc.abv, bc.is_na_low,
           b.name as brewery_name, b.country,
           coalesce(bc.cutout_url, bc.label_image_url) as image_url
    from beer_catalog bc
    left join brewery b on b.id = bc.brewery_id
    where bc.name_ok
      and (p_query is null or btrim(p_query) = ''
           or bc.display_name ilike '%' || p_query || '%'
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
