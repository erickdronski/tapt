-- 0060_overture_beer_places.sql
-- Adds a monthly, provenance-preserving import path for real breweries, pubs,
-- bars, taprooms, beer gardens, and gastropubs from Overture Maps Places.

insert into public.ingestion_source
  (id, name, source_kind, license, homepage_url, ingest_cadence, enabled, notes)
values
  ('overture_places', 'Overture Maps Places', 'venue',
   'Per-record source license; included Tapt sources are Apache-2.0, CDLA-Permissive-2.0, or CC0',
   'https://docs.overturemaps.org/guides/places/', 'monthly', true,
   'High-confidence beer-serving places. Source IDs and release provenance are retained on every venue.')
on conflict (id) do update
set name = excluded.name,
    source_kind = excluded.source_kind,
    license = excluded.license,
    homepage_url = excluded.homepage_url,
    ingest_cadence = excluded.ingest_cadence,
    enabled = excluded.enabled,
    notes = excluded.notes,
    updated_at = now();

create table if not exists public.overture_place_import (
  overture_id text primary key,
  release_id text not null,
  version bigint,
  name text not null,
  category text not null,
  latitude numeric(10,7) not null check (latitude between -90 and 90),
  longitude numeric(10,7) not null check (longitude between -180 and 180),
  h3_cell text not null check (h3_cell ~ '^[0-9a-f]{15}$'),
  address text,
  locality text,
  region text,
  postcode text,
  country text,
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  website_url text,
  phone text,
  confidence numeric(4,3) check (confidence is null or confidence between 0 and 1),
  source_dataset text,
  source_license text,
  date_refreshed date,
  imported_at timestamptz not null default now()
);

alter table public.overture_place_import enable row level security;
revoke all on public.overture_place_import from public, anon, authenticated;
grant select, insert, update, delete on public.overture_place_import to service_role;

create index if not exists overture_place_import_release
on public.overture_place_import (release_id, category);

create unique index if not exists venue_overture_place_unique
on public.venue ((external_ids->>'overture_place'))
where external_ids ? 'overture_place';

create or replace function public.apply_overture_place_import(p_release text)
returns table (
  venues_inserted int,
  venues_updated int,
  venues_matched int,
  source_links_written int
)
language sql
volatile
security definer
set search_path = public
as $$
  with normalized as materialized (
    select
      o.*,
      regexp_replace(lower(trim(o.name)), '[^a-z0-9]+', '', 'g') as normalized_name,
      st_setsrid(st_makepoint(o.longitude, o.latitude), 4326)::geography as place_geo,
      case
        when o.category = 'brewery' then 'brewery'
        when o.category = 'beer_garden' then 'beer_garden'
        when o.category in ('pub', 'irish_pub', 'gastropub') then 'pub'
        when o.category = 'beer_bar' then 'taproom'
        else 'bar'
      end as venue_kind
    from public.overture_place_import o
    where o.release_id = p_release
      and length(trim(o.name)) between 2 and 180
      and coalesce(o.confidence, 0) >= 0.80
      and o.category in (
        'bar', 'bar_and_grill_restaurant', 'beach_bar', 'beer_bar',
        'beer_garden', 'brasserie', 'brewery', 'dive_bar', 'gastropub',
        'hotel_bar', 'irish_pub', 'lounge', 'piano_bar', 'pub',
        'speakeasy', 'sports_bar', 'tiki_bar', 'whiskey_bar'
      )
  ), existing_source as materialized (
    select n.*, v.id as venue_id
    from normalized n
    join public.venue v on v.external_ids->>'overture_place' = n.overture_id
  ), updated_source as (
    update public.venue v
    set name = n.name,
        poi_category = n.venue_kind,
        geo = n.place_geo,
        geo_bucket_h3 = n.h3_cell,
        external_ids = v.external_ids || jsonb_strip_nulls(jsonb_build_object(
          'overture_release', n.release_id,
          'overture_version', n.version,
          'venue_type', n.category,
          'address', n.address,
          'city', n.locality,
          'region', n.region,
          'country', n.country,
          'country_code', n.country_code,
          'postal_code', n.postcode,
          'website_url', n.website_url,
          'phone', n.phone,
          'source_dataset', n.source_dataset,
          'source_license', n.source_license,
          'source_note', 'Overture Maps Places',
          'source_refreshed_at', n.date_refreshed
        )),
        updated_at = now()
    from existing_source n
    where v.id = n.venue_id
    returning v.id, v.external_ids
  ), unlinked as materialized (
    select n.*
    from normalized n
    where not exists (
      select 1 from public.venue v
      where v.external_ids->>'overture_place' = n.overture_id
    )
  ), candidate_scores as materialized (
    select
      n.overture_id,
      v.id as venue_id,
      similarity(lower(v.name), lower(n.name)) as name_score,
      st_distance(v.geo, n.place_geo) as distance_m
    from unlinked n
    join public.venue v
      on v.geo is not null
     and not (v.external_ids ? 'overture_place')
     and st_dwithin(v.geo, n.place_geo, 100)
     and (
       regexp_replace(lower(trim(v.name)), '[^a-z0-9]+', '', 'g') = n.normalized_name
       or similarity(lower(v.name), lower(n.name)) >= 0.78
     )
  ), ranked_sources as materialized (
    select c.*,
      row_number() over (
        partition by c.overture_id
        order by c.name_score desc, c.distance_m asc, c.venue_id
      ) as source_rank
    from candidate_scores c
  ), ranked_venues as materialized (
    select r.*,
      row_number() over (
        partition by r.venue_id
        order by r.name_score desc, r.distance_m asc, r.overture_id
      ) as venue_rank
    from ranked_sources r
    where r.source_rank = 1
  ), selected_matches as materialized (
    select r.overture_id, r.venue_id
    from ranked_venues r
    where r.venue_rank = 1
  ), matched_updates as (
    update public.venue v
    set poi_category = case
          when v.poi_category is null or v.poi_category in ('nightlife', 'bar') then n.venue_kind
          else v.poi_category
        end,
        geo_bucket_h3 = n.h3_cell,
        external_ids = v.external_ids || jsonb_strip_nulls(jsonb_build_object(
          'overture_place', n.overture_id,
          'overture_release', n.release_id,
          'overture_version', n.version,
          'venue_type', n.category,
          'address', coalesce(v.external_ids->>'address', n.address),
          'city', coalesce(v.external_ids->>'city', n.locality),
          'region', coalesce(v.external_ids->>'region', n.region),
          'country', coalesce(v.external_ids->>'country', n.country),
          'country_code', coalesce(v.external_ids->>'country_code', n.country_code),
          'postal_code', coalesce(v.external_ids->>'postal_code', n.postcode),
          'website_url', coalesce(v.external_ids->>'website_url', n.website_url),
          'phone', coalesce(v.external_ids->>'phone', n.phone),
          'source_dataset', n.source_dataset,
          'source_license', n.source_license,
          'source_refreshed_at', n.date_refreshed
        )),
        updated_at = now()
    from selected_matches m
    join unlinked n on n.overture_id = m.overture_id
    where v.id = m.venue_id
    returning v.id, v.external_ids
  ), inserted as (
    insert into public.venue
      (name, poi_category, on_off_premise, geo, geo_bucket_h3, external_ids)
    select
      n.name,
      n.venue_kind,
      'on_premise'::on_off_premise,
      n.place_geo,
      n.h3_cell,
      jsonb_strip_nulls(jsonb_build_object(
        'overture_place', n.overture_id,
        'overture_release', n.release_id,
        'overture_version', n.version,
        'venue_type', n.category,
        'address', n.address,
        'city', n.locality,
        'region', n.region,
        'country', n.country,
        'country_code', n.country_code,
        'postal_code', n.postcode,
        'website_url', n.website_url,
        'phone', n.phone,
        'source_dataset', n.source_dataset,
        'source_license', n.source_license,
        'source_note', 'Overture Maps Places',
        'source_refreshed_at', n.date_refreshed
      ))
    from unlinked n
    where not exists (
      select 1 from selected_matches m where m.overture_id = n.overture_id
    )
    on conflict ((external_ids->>'overture_place'))
      where external_ids ? 'overture_place'
      do nothing
    returning id, external_ids
  ), all_venues as materialized (
    select id, external_ids from updated_source
    union all
    select id, external_ids from matched_updates
    union all
    select id, external_ids from inserted
  ), links as (
    insert into public.source_object_link
      (source_id, object_type, object_id, external_id, external_url,
       confidence, payload, last_seen_at)
    select
      'overture_places', 'venue', av.id,
      av.external_ids->>'overture_place',
      'https://docs.overturemaps.org/guides/places/',
      coalesce((select o.confidence from normalized o
                where o.overture_id = av.external_ids->>'overture_place'), 0.800),
      jsonb_strip_nulls(jsonb_build_object(
        'release', av.external_ids->>'overture_release',
        'version', av.external_ids->>'overture_version',
        'category', av.external_ids->>'venue_type',
        'source_dataset', av.external_ids->>'source_dataset',
        'source_license', av.external_ids->>'source_license'
      )),
      now()
    from all_venues av
    where av.external_ids ? 'overture_place'
    on conflict (source_id, object_type, object_id, external_id) do update
    set confidence = excluded.confidence,
        payload = excluded.payload,
        last_seen_at = excluded.last_seen_at
    returning 1
  )
  select
    (select count(*)::int from inserted),
    (select count(*)::int from updated_source),
    (select count(*)::int from matched_updates),
    (select count(*)::int from links);
$$;

revoke all on function public.apply_overture_place_import(text)
  from public, anon, authenticated;
grant execute on function public.apply_overture_place_import(text) to service_role;

create or replace function public.brewery_map_feed(p_limit int default 500)
returns table (
  venue_id uuid, name text, city text, region text, country text,
  latitude numeric, longitude numeric, source_label text, heat_score int,
  updated_at timestamptz, brewery_type text, website_url text
)
language sql stable security definer set search_path = public
as $$
  select
    v.id, v.name, v.external_ids->>'city', v.external_ids->>'region',
    v.external_ids->>'country', st_y(v.geo::geometry)::numeric,
    st_x(v.geo::geometry)::numeric,
    coalesce(v.external_ids->>'source_note', 'Tapt beer map'),
    greatest(count(c.id)::int * 3 + count(ti.id)::int +
      case when v.external_ids ? 'tapt_seed' then 2 else 1 end, 1),
    greatest(v.updated_at, coalesce(max(c.event_ts), v.updated_at),
      coalesce(max(ts.observed_at), v.updated_at)),
    coalesce(v.external_ids->>'venue_type', v.external_ids->>'brewery_type', v.poi_category),
    v.external_ids->>'website_url'
  from public.venue v
  left join public.checkin_event c
    on c.venue_id = v.id and c.moderation_status = 'visible'
  left join public.venue_tap_snapshot ts
    on ts.venue_id = v.id and ts.expires_at > now()
  left join public.venue_tap_item ti on ti.snapshot_id = ts.id
  where v.poi_category in ('brewery','bar','pub','taproom','beer_garden','nightlife')
    and v.geo is not null
  group by v.id
  order by 9 desc, md5(v.id::text || to_char(now(), 'YYYY-MM-DD'))
  limit least(greatest(coalesce(p_limit, 500), 1), 1000);
$$;

create or replace function public.brewery_map_feed_near(
  p_lat numeric, p_lng numeric, p_km int default 60, p_limit int default 250
)
returns table (
  venue_id uuid, name text, city text, region text, country text,
  latitude numeric, longitude numeric, source_label text, heat_score int,
  updated_at timestamptz, brewery_type text, website_url text
)
language sql stable security definer set search_path = public
as $$
  select
    v.id, v.name, v.external_ids->>'city', v.external_ids->>'region',
    v.external_ids->>'country', st_y(v.geo::geometry)::numeric,
    st_x(v.geo::geometry)::numeric,
    coalesce(v.external_ids->>'source_note', 'Tapt beer map'),
    greatest(count(c.id)::int * 3 + 1, 1),
    greatest(v.updated_at, coalesce(max(c.event_ts), v.updated_at)),
    coalesce(v.external_ids->>'venue_type', v.external_ids->>'brewery_type', v.poi_category),
    v.external_ids->>'website_url'
  from public.venue v
  left join public.checkin_event c
    on c.venue_id = v.id and c.moderation_status = 'visible'
  where v.poi_category in ('brewery','bar','pub','taproom','beer_garden','nightlife')
    and v.geo is not null
    and p_lat between -90 and 90
    and p_lng between -180 and 180
    and st_dwithin(
      v.geo,
      st_setsrid(st_makepoint(p_lng::float8, p_lat::float8), 4326)::geography,
      least(greatest(coalesce(p_km, 60), 1), 500) * 1000.0
    )
  group by v.id
  order by st_distance(
    v.geo,
    st_setsrid(st_makepoint(p_lng::float8, p_lat::float8), 4326)::geography
  ) asc
  limit least(greatest(coalesce(p_limit, 250), 1), 500);
$$;

revoke all on function public.brewery_map_feed(int) from public;
revoke all on function public.brewery_map_feed_near(numeric, numeric, int, int) from public;
grant execute on function public.brewery_map_feed(int) to anon, authenticated;
grant execute on function public.brewery_map_feed_near(numeric, numeric, int, int)
  to anon, authenticated;

notify pgrst, 'reload schema';
