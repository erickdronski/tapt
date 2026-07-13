-- 0079_catalog_search_quality.sql
-- Keep licensed source rows intact while making consumer search return the
-- cleanest canonical package first. Targeted searches collapse exact display-
-- name duplicates across source brewery variants; unfiltered browsing keeps
-- same-named beers from distinct breweries.

create index if not exists beer_catalog_display_name_trgm
  on public.beer_catalog using gin (display_name gin_trgm_ops)
  where name_ok;

create or replace function public.catalog_search(
  p_query text default null,
  p_style text default null,
  p_na_only boolean default false,
  p_limit integer default 30,
  p_offset integer default 0
)
returns table (
  id uuid,
  name text,
  style text,
  abv numeric,
  is_na_low boolean,
  brewery_name text,
  country text,
  image_url text,
  total bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with input as (
    select btrim(coalesce(p_query, '')) as query
  ),
  candidates as (
    select
      bc.id,
      bc.display_name as name,
      bc.style,
      bc.abv,
      bc.is_na_low,
      b.name as brewery_name,
      b.country,
      coalesce(bc.cutout_url, bc.label_image_url) as image_url,
      bc.cutout_url is not null as has_cutout,
      case
        when input.query = '' then 0
        when lower(bc.display_name) = lower(input.query) then 0
        when bc.display_name ilike input.query || '%' then 1
        when bc.display_name ilike '%' || input.query || '%' then 2
        when b.name ilike '%' || input.query || '%' then 3
        else 4
      end as match_rank,
      row_number() over (
        partition by
          lower(bc.display_name),
          coalesce(bc.brewery_id::text, lower(b.name), '')
        order by
          (bc.cutout_url is not null) desc,
          (bc.label_image_url is not null) desc,
          (bc.abv is not null) desc,
          (nullif(bc.style, '') is not null) desc,
          bc.updated_at desc,
          bc.id
      ) as package_rank
    from public.beer_catalog bc
    left join public.brewery b on b.id = bc.brewery_id
    cross join input
    where bc.name_ok
      and length(bc.display_name) between 2 and 80
      and bc.display_name !~* '(€|\m(zzgl|pfand|packung)\M)'
      and (
        input.query = ''
        or bc.display_name ilike '%' || input.query || '%'
        or bc.name ilike '%' || input.query || '%'
        or b.name ilike '%' || input.query || '%'
      )
      and (p_style is null or btrim(p_style) = '' or bc.style ilike '%' || p_style || '%')
      and (not coalesce(p_na_only, false) or bc.is_na_low)
  ),
  package_canonical as (
    select
      id, name, style, abv, is_na_low, brewery_name, country, image_url,
      has_cutout, match_rank
    from candidates
    where package_rank = 1
  ),
  query_state as (
    select exists (
      select 1
      from package_canonical
      cross join input
      where package_canonical.has_cutout
        and lower(package_canonical.name) = lower(input.query)
    ) as has_reviewed_exact
  ),
  search_ranked as (
    select
      package_canonical.*,
      row_number() over (
        partition by lower(name)
        order by
          match_rank,
          has_cutout desc,
          (image_url is not null) desc,
          (brewery_name is not null) desc,
          (abv is not null) desc,
          (nullif(style, '') is not null) desc,
          id
      ) as searched_name_rank
    from package_canonical
  ),
  canonical as (
    select search_ranked.*
    from search_ranked
    cross join input
    cross join query_state
    where (input.query = '' or searched_name_rank = 1)
      and (
        not query_state.has_reviewed_exact
        or lower(search_ranked.name) = lower(input.query)
      )
  )
  select
    canonical.id,
    canonical.name,
    canonical.style,
    canonical.abv,
    canonical.is_na_low,
    canonical.brewery_name,
    canonical.country,
    canonical.image_url,
    count(*) over() as total
  from canonical
  order by
    canonical.match_rank,
    (canonical.image_url is null),
    (canonical.brewery_name is null),
    (canonical.abv is null),
    (canonical.style is null),
    lower(canonical.name)
  limit greatest(1, least(coalesce(p_limit, 30), 60))
  offset greatest(0, coalesce(p_offset, 0));
$$;

revoke all on function public.catalog_search(text, text, boolean, integer, integer)
  from public, anon, authenticated;
grant execute on function public.catalog_search(text, text, boolean, integer, integer)
  to anon, authenticated;
