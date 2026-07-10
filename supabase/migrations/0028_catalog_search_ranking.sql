-- Rank the catalog by quality, not just alphabetically: imaged beers with a real
-- (letter-initial) name, a brewery, an ABV and a style come first, so OFF's messy
-- crowd-sourced junk (blank/number/symbol names) sinks to the bottom.
create or replace function catalog_search(
  p_query   text default null,
  p_style   text default null,
  p_na_only boolean default false,
  p_limit   int default 30,
  p_offset  int default 0
)
returns table (
  id uuid, name text, style text, abv numeric, is_na_low boolean,
  brewery_name text, country text, image_url text, total bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with base as (
    select bc.id, bc.name, bc.style, bc.abv, bc.is_na_low,
           b.name as brewery_name, b.country, bc.label_image_url as image_url
    from beer_catalog bc
    left join brewery b on b.id = bc.brewery_id
    where (p_query is null or btrim(p_query) = ''
           or bc.name ilike '%' || p_query || '%'
           or b.name  ilike '%' || p_query || '%')
      and (p_style is null or btrim(p_style) = '' or bc.style ilike '%' || p_style || '%')
      and (not coalesce(p_na_only, false) or bc.is_na_low)
  )
  select id, name, style, abv, is_na_low, brewery_name, country, image_url,
         count(*) over() as total
  from base
  order by
    (image_url is null),
    (name !~ '^[A-Za-z]'),
    (brewery_name is null),
    (abv is null),
    (style is null),
    lower(name)
  limit greatest(1, least(coalesce(p_limit, 30), 60))
  offset greatest(0, coalesce(p_offset, 0));
$$;

grant execute on function catalog_search(text, text, boolean, int, int) to anon, authenticated;
