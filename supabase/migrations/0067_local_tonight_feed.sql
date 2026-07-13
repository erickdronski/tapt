-- 0067_local_tonight_feed.sql
-- Separate verified nearby tap-list truth from the global Beer Market fallback.
-- Coordinates are used only for this request and are never written by these RPCs.

create or replace function public.tonight_feed_v2(
  p_geo_bucket text default null,
  p_limit int default 20,
  p_na_only boolean default false
)
returns table (
  venue_id uuid,
  venue_name text,
  beer_id uuid,
  beer_name text,
  brewery_name text,
  style text,
  image_url text,
  is_na_low boolean,
  source_label text,
  heat_score int,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with latest_snapshots as (
    select distinct on (s.venue_id)
      s.id, s.venue_id, s.observed_at
    from public.venue_tap_snapshot s
    where s.expires_at > now()
    order by s.venue_id, s.observed_at desc, s.id desc
  ),
  tap_rows as (
    select
      v.id as venue_id,
      v.name as venue_name,
      i.beer_id,
      i.beer_name,
      i.brewery_name,
      i.style,
      coalesce(b.cutout_url, b.label_image_url) as image_url,
      coalesce(b.is_na_low, false) as is_na_low,
      'fresh tap list'::text as source_label,
      least(
        100,
        greatest(
          1,
          100 - floor(extract(epoch from (now() - s.observed_at)) / 3600)::int
        )
      ) as heat_score,
      s.observed_at as updated_at
    from latest_snapshots s
    join public.venue v on v.id = s.venue_id
    join public.venue_tap_item i on i.snapshot_id = s.id
    left join public.beer_catalog b on b.id = i.beer_id
    where (p_geo_bucket is null or v.geo_bucket_h3 = p_geo_bucket)
      and (not coalesce(p_na_only, false) or b.is_na_low)
  ),
  trend_rows as (
    select
      null::uuid as venue_id,
      coalesce(t.region, 'Global') as venue_name,
      t.beer_id,
      t.name as beer_name,
      t.brewery_name,
      t.style,
      coalesce(b.cutout_url, b.label_image_url) as image_url,
      coalesce(b.is_na_low, false) as is_na_low,
      'global market heat'::text as source_label,
      greatest(t.momentum, t.popularity, 1) as heat_score,
      t.updated_at
    from public.beer_trend_feed t
    left join public.beer_catalog b on b.id = t.beer_id
    where p_geo_bucket is null
      and (not coalesce(p_na_only, false) or b.is_na_low)
    order by t.momentum desc, t.popularity desc
    limit 12
  )
  select *
  from (
    select * from tap_rows
    union all
    select * from trend_rows
  ) signal
  order by heat_score desc, updated_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

create or replace function public.tonight_feed_near(
  p_lat numeric,
  p_lon numeric,
  p_radius_m int default 40000,
  p_limit int default 20,
  p_na_only boolean default false
)
returns table (
  venue_id uuid,
  venue_name text,
  beer_id uuid,
  beer_name text,
  brewery_name text,
  style text,
  image_url text,
  is_na_low boolean,
  source_label text,
  heat_score int,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with request_point as (
    select
      st_setsrid(st_makepoint(p_lon::double precision, p_lat::double precision), 4326)::geography as geo,
      least(greatest(coalesce(p_radius_m, 40000), 1000), 100000) as radius_m
    where p_lat between -90 and 90 and p_lon between -180 and 180
  ),
  nearby_venues as (
    select v.id, v.name, v.geo,
           st_distance(v.geo, rp.geo) as distance_m
    from public.venue v
    cross join request_point rp
    where st_dwithin(v.geo, rp.geo, rp.radius_m)
  ),
  latest_snapshots as (
    select distinct on (s.venue_id)
      s.id, s.venue_id, s.observed_at
    from public.venue_tap_snapshot s
    join nearby_venues nv on nv.id = s.venue_id
    where s.expires_at > now()
    order by s.venue_id, s.observed_at desc, s.id desc
  )
  select
    nv.id,
    nv.name,
    i.beer_id,
    i.beer_name,
    i.brewery_name,
    i.style,
    coalesce(b.cutout_url, b.label_image_url),
    coalesce(b.is_na_low, false),
    'nearby fresh tap list'::text,
    least(
      100,
      greatest(
        1,
        100 - floor(extract(epoch from (now() - s.observed_at)) / 3600)::int
      )
    ),
    s.observed_at
  from latest_snapshots s
  join nearby_venues nv on nv.id = s.venue_id
  join public.venue_tap_item i on i.snapshot_id = s.id
  left join public.beer_catalog b on b.id = i.beer_id
  where not coalesce(p_na_only, false) or b.is_na_low
  order by 10 desc, nv.distance_m, i.beer_name
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke all on function public.tonight_feed_v2(text, integer, boolean)
  from public, anon, authenticated;
revoke all on function public.tonight_feed_near(numeric, numeric, integer, integer, boolean)
  from public, anon, authenticated;

grant execute on function public.tonight_feed_v2(text, integer, boolean)
  to anon, authenticated;
grant execute on function public.tonight_feed_near(numeric, numeric, integer, integer, boolean)
  to anon, authenticated;
