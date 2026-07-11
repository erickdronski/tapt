-- 0050: catalog_search hides junk names + shows clean display names + cutouts.
-- my_beer_activity surfaces the caller's own notes & votes for their profile.
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
  )
  select id, name, style, abv, is_na_low, brewery_name, country, image_url,
         count(*) over() as total
  from base
  order by (image_url is null), (brewery_name is null), (abv is null), (style is null), lower(name)
  limit greatest(1, least(coalesce(p_limit, 30), 60))
  offset greatest(0, coalesce(p_offset, 0));
$function$;

create or replace function public.my_beer_activity()
returns table(beer_id uuid, name text, image_url text, style text,
              note text, vote smallint, updated_at timestamptz)
language sql stable security definer set search_path to 'public' as $function$
  with u as (select auth.uid() uid),
  acts as (
    select beer_id, note, null::smallint vote, updated_at
      from beer_note where user_id = (select uid from u)
    union all
    select beer_id, null::text, value, coalesce(updated_at, created_at)
      from beer_vote where user_id = (select uid from u)
  ),
  merged as (
    select beer_id, max(note) note, max(vote) vote, max(updated_at) updated_at
    from acts group by beer_id
  )
  select b.id, public.tapt_display_name(b.name),
         coalesce(b.cutout_url, b.label_image_url),
         coalesce(sr.style_name, nullif(btrim(b.style),'')),
         m.note, m.vote, m.updated_at
  from merged m
  join beer_catalog b on b.id = m.beer_id
  left join beer_style_reference sr on sr.style_name = public.tapt_ref_style_name(b.style, b.name)
  order by m.updated_at desc nulls last
  limit 100;
$function$;
grant execute on function public.my_beer_activity() to authenticated;
