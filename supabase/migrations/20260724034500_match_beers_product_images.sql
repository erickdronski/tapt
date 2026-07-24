-- Carry exact catalog product art through scan matching. Older clients ignore
-- the additional column; current clients use the standard cutout-first policy.
drop function if exists public.match_beers(text, integer);

create function public.match_beers(p_query text, p_limit integer default 8)
returns table(
  id uuid,
  name text,
  style text,
  abv numeric,
  brewery_name text,
  country text,
  image_url text,
  confidence numeric
)
language sql
stable
set search_path to 'public'
as $function$
  with q as (
    select nullif(left(regexp_replace(trim(p_query), '\s+', ' ', 'g'), 96), '') as value,
           least(greatest(coalesce(p_limit, 8), 1), 12) as max_rows
  )
  select
    b.id,
    public.tapt_scan_name(coalesce(nullif(b.display_name, ''), b.name)) as name,
    b.style_ref as style,
    b.abv,
    br.name as brewery_name,
    public.tapt_trusted_country(br.country, br.external_ids) as country,
    coalesce(nullif(b.cutout_url, ''), nullif(b.label_image_url, '')) as image_url,
    case
      when b.gtin = regexp_replace(q.value, '\D', '', 'g') then 1.0
      else greatest(similarity(b.name, q.value), similarity(coalesce(br.name, ''), q.value))
    end::numeric as confidence
  from q, beer_catalog b
  left join brewery br on br.id = b.brewery_id
  where q.value is not null
    and (
      b.gtin = regexp_replace(q.value, '\D', '', 'g')
      or b.name % q.value
      or br.name % q.value
      or b.name ilike '%' || q.value || '%'
      or br.name ilike '%' || q.value || '%'
    )
  order by
    case when b.gtin = regexp_replace(q.value, '\D', '', 'g') then 0 else 1 end,
    b.name_ok desc,
    confidence desc,
    b.name
  limit (select max_rows from q);
$function$;

revoke all on function public.match_beers(text, integer) from public;
grant execute on function public.match_beers(text, integer) to anon, authenticated;

notify pgrst, 'reload schema';
