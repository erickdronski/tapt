-- 0094  Make the Overture venue apply batchable per country.
--
-- 119,811 global places (219 countries) were staged in overture_place_import
-- but apply_overture_place_import() 500s: conflating + inserting all ~119K in
-- one call blows the synchronous window (the fuzzy st_dwithin/similarity match
-- against every existing venue is the heavy part). Fix: add an optional
-- p_country_code so each call processes one country, plus statement_timeout 0
-- and a bigger work_mem for the sort/hash. The monthly cron and the driver
-- script loop over countries. Body is otherwise identical to 0069.
create or replace function public.apply_overture_place_import(
  p_release text,
  p_country_code text default null
)
returns table(venues_inserted integer, venues_updated integer, venues_matched integer, source_links_written integer)
language sql
security definer
set search_path to 'public'
set statement_timeout to '0'
set work_mem to '256MB'
as $function$
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
      and (p_country_code is null or o.country_code = p_country_code)
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
$function$;

revoke all on function public.apply_overture_place_import(text, text) from public, anon, authenticated;
grant execute on function public.apply_overture_place_import(text, text) to service_role;
