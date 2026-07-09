-- 0010_map_feed_global_spread.sql
-- With ~8.7k venues ingested from Open Brewery DB, the map feed needs:
--   1. A geographically diverse global sample (the old tail ordering was
--      alphabetical by country, so a limited fetch returned only A-countries).
--      The sample now rotates daily via a deterministic hash — every venue in
--      the radar gets surfaced over time, still cache-friendly within a day.
--   2. A proximity feed for "near me" surfaces: brewery_map_feed_near.

create or replace function brewery_map_feed(
  p_limit int default 500
)
returns table (
  venue_id uuid,
  name text,
  city text,
  region text,
  country text,
  latitude numeric,
  longitude numeric,
  source_label text,
  heat_score int,
  updated_at timestamptz,
  brewery_type text,
  website_url text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    v.id as venue_id,
    v.name,
    v.external_ids->>'city' as city,
    v.external_ids->>'region' as region,
    v.external_ids->>'country' as country,
    st_y(v.geo::geometry)::numeric as latitude,
    st_x(v.geo::geometry)::numeric as longitude,
    coalesce(v.external_ids->>'source_note', 'Tapt brewery map') as source_label,
    greatest(count(c.id)::int * 3 + count(ti.id)::int + case when v.external_ids ? 'tapt_seed' then 2 else 1 end, 1) as heat_score,
    greatest(v.updated_at, coalesce(max(c.event_ts), v.updated_at), coalesce(max(ts.observed_at), v.updated_at)) as updated_at,
    v.external_ids->>'brewery_type' as brewery_type,
    v.external_ids->>'website_url' as website_url
  from venue v
  left join checkin_event c on c.venue_id = v.id and c.moderation_status = 'visible'
  left join venue_tap_snapshot ts on ts.venue_id = v.id and ts.expires_at > now()
  left join venue_tap_item ti on ti.snapshot_id = ts.id
  where v.poi_category in ('brewery','bar','taproom','nightlife')
    and v.geo is not null
  group by v.id
  order by heat_score desc, md5(v.id::text || to_char(now(), 'YYYY-MM-DD'))
  limit least(greatest(coalesce(p_limit, 500), 1), 1000);
$$;

revoke execute on function brewery_map_feed(int) from public;
grant execute on function brewery_map_feed(int) to anon, authenticated;

create or replace function brewery_map_feed_near(
  p_lat numeric,
  p_lng numeric,
  p_km int default 60,
  p_limit int default 250
)
returns table (
  venue_id uuid,
  name text,
  city text,
  region text,
  country text,
  latitude numeric,
  longitude numeric,
  source_label text,
  heat_score int,
  updated_at timestamptz,
  brewery_type text,
  website_url text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    v.id as venue_id,
    v.name,
    v.external_ids->>'city' as city,
    v.external_ids->>'region' as region,
    v.external_ids->>'country' as country,
    st_y(v.geo::geometry)::numeric as latitude,
    st_x(v.geo::geometry)::numeric as longitude,
    coalesce(v.external_ids->>'source_note', 'Tapt brewery map') as source_label,
    greatest(count(c.id)::int * 3 + 1, 1) as heat_score,
    greatest(v.updated_at, coalesce(max(c.event_ts), v.updated_at)) as updated_at,
    v.external_ids->>'brewery_type' as brewery_type,
    v.external_ids->>'website_url' as website_url
  from venue v
  left join checkin_event c on c.venue_id = v.id and c.moderation_status = 'visible'
  where v.poi_category in ('brewery','bar','taproom','nightlife')
    and v.geo is not null
    and p_lat between -90 and 90
    and p_lng between -180 and 180
    and st_dwithin(
      v.geo,
      st_setsrid(st_makepoint(p_lng::float8, p_lat::float8), 4326)::geography,
      least(greatest(coalesce(p_km, 60), 1), 500) * 1000.0
    )
  group by v.id
  order by st_distance(v.geo, st_setsrid(st_makepoint(p_lng::float8, p_lat::float8), 4326)::geography) asc
  limit least(greatest(coalesce(p_limit, 250), 1), 500);
$$;

revoke all on function brewery_map_feed_near(numeric, numeric, int, int) from public;
grant execute on function brewery_map_feed_near(numeric, numeric, int, int) to anon, authenticated;
