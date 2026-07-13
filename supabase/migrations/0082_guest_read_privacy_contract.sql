-- 0082_guest_read_privacy_contract.sql
-- Guest discovery is public, but activity-derived fields must honor the same
-- moderation and current-consent rules as every other aggregate surface.

create or replace function public.beer_detail(p_beer_id uuid)
returns table(id uuid, name text, style text, substyle text, abv numeric, ibu smallint,
  is_na_low boolean, gtin text, label_image_url text, label_image_license text, nutrition jsonb,
  data_source text, brewery_name text, brewery_country text, brewery_website text,
  style_family text, style_name text, style_description text, style_abv_min numeric,
  style_abv_max numeric, style_ibu_min smallint, style_ibu_max smallint, style_srm_min smallint,
  style_srm_max smallint, style_source_url text, ups integer, downs integer, checkin_count integer,
  avg_rating numeric, venues_in_country integer, awards jsonb,
  style_hoppiness smallint, style_bitterness smallint, style_sweetness smallint, style_body smallint,
  style_roast smallint, style_sourness smallint, style_fruitiness smallint,
  style_flavor_notes text, style_ingredients text, style_history text)
language sql stable security definer set search_path to 'public' as $function$
  select
    b.id,
    b.display_name as name,
    coalesce(sr.style_name, nullif(btrim(b.style), '')) as style,
    b.substyle, b.abv, b.ibu, b.is_na_low, b.gtin,
    coalesce(b.cutout_url, b.label_image_url) as label_image_url,
    b.label_image_license,
    b.external_ids->'nutrition' as nutrition,
    b.external_ids->>'source' as data_source,
    br.name,
    public.tapt_trusted_country(br.country, br.external_ids),
    br.website_url,
    sr.style_family, sr.style_name, sr.description,
    sr.abv_min, sr.abv_max, sr.ibu_min, sr.ibu_max,
    sr.color_min_srm, sr.color_max_srm, sr.source_url,
    coalesce((
      select count(*) filter (where bv.value = 1)
      from public.beer_vote bv
      where bv.beer_id = b.id
    ), 0)::int,
    coalesce((
      select count(*) filter (where bv.value = -1)
      from public.beer_vote bv
      where bv.beer_id = b.id
    ), 0)::int,
    coalesce((
      select count(*)
      from public.checkin_event ce
      where ce.beer_id = b.id
        and ce.moderation_status = 'visible'
        and public.has_current_consent(ce.user_id, 'aggregate_analytics')
    ), 0)::int,
    (
      select avg(ce.rating)::numeric(3,2)
      from public.checkin_event ce
      where ce.beer_id = b.id
        and ce.moderation_status = 'visible'
        and public.has_current_consent(ce.user_id, 'aggregate_analytics')
    ),
    case
      when public.tapt_trusted_country(br.country, br.external_ids) is null then 0
      else coalesce((
        select count(*)::int
        from public.venue v
        where v.external_ids->>'country' =
          public.tapt_trusted_country(br.country, br.external_ids)
      ), 0)
    end,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'award_body', a.award_body, 'year', a.year, 'category', a.category,
        'medal', a.medal, 'scope', a.scope, 'region', a.region,
        'source_url', a.source_url, 'note', a.note
      ) order by a.year desc nulls last, a.medal)
      from public.beer_award a where a.beer_id = b.id
    ), '[]'::jsonb),
    sr.hoppiness, sr.bitterness, sr.sweetness, sr.body, sr.roast,
    sr.sourness, sr.fruitiness, sr.flavor_notes, sr.typical_ingredients,
    sr.style_history
  from public.beer_catalog b
  left join public.brewery br on br.id = b.brewery_id
  left join public.beer_style_reference sr
    on sr.style_name = public.tapt_ref_style_name(b.style, b.name)
  where b.id = p_beer_id
    and b.name_ok;
$function$;

create or replace function public.brewery_map_feed(p_limit int default 500)
returns table (
  venue_id uuid, name text, city text, region text, country text,
  latitude numeric, longitude numeric, source_label text, heat_score int,
  updated_at timestamptz, brewery_type text, website_url text
)
language sql stable security definer set search_path = public as $$
  with params as (
    select least(greatest(coalesce(p_limit, 500), 1), 1000) as row_limit
  ), eligible_checkins as materialized (
    select ce.venue_id, count(*)::int as checkins, max(ce.event_ts) as latest
    from public.checkin_event ce
    where ce.venue_id is not null
      and ce.moderation_status = 'visible'
      and public.has_current_consent(ce.user_id, 'aggregate_analytics')
    group by ce.venue_id
  ), active_taps as materialized (
    select s.venue_id, count(i.id)::int as taps, max(s.observed_at) as latest
    from public.venue_tap_snapshot s
    left join public.venue_tap_item i on i.snapshot_id = s.id
    where s.expires_at > now()
    group by s.venue_id
  ), sampled as materialized (
    -- UUID order is already globally mixed and uses the primary-key index.
    -- Include active venues separately so real activity is never sampled out.
    select v.id
    from public.venue v
    where v.poi_category in ('brewery','bar','pub','taproom','beer_garden','nightlife')
      and v.geo is not null
    order by v.id
    limit (select row_limit from params)
  ), candidate_ids as (
    select id from sampled
    union
    select venue_id from eligible_checkins
    union
    select venue_id from active_taps
  )
  select
    v.id, v.name, v.external_ids->>'city', v.external_ids->>'region',
    v.external_ids->>'country', st_y(v.geo::geometry)::numeric,
    st_x(v.geo::geometry)::numeric,
    coalesce(v.external_ids->>'source_note', 'Tapt beer map'),
    coalesce(c.checkins, 0) * 3 + coalesce(t.taps, 0),
    greatest(v.updated_at, coalesce(c.latest, v.updated_at),
      coalesce(t.latest, v.updated_at)),
    coalesce(v.external_ids->>'venue_type',
      v.external_ids->>'brewery_type', v.poi_category),
    v.external_ids->>'website_url'
  from candidate_ids candidate
  join public.venue v on v.id = candidate.id
  left join eligible_checkins c on c.venue_id = v.id
  left join active_taps t on t.venue_id = v.id
  where v.poi_category in ('brewery','bar','pub','taproom','beer_garden','nightlife')
    and v.geo is not null
  order by 9 desc, v.id
  limit (select row_limit from params);
$$;

create or replace function public.brewery_map_feed_near(
  p_lat numeric, p_lng numeric, p_km int default 60, p_limit int default 250
)
returns table (
  venue_id uuid, name text, city text, region text, country text,
  latitude numeric, longitude numeric, source_label text, heat_score int,
  updated_at timestamptz, brewery_type text, website_url text
)
language sql stable security definer set search_path = public as $$
  with params as (
    select
      st_setsrid(st_makepoint(p_lng::float8, p_lat::float8), 4326)::geography as origin,
      least(greatest(coalesce(p_km, 60), 1), 500) * 1000.0 as radius_m,
      least(greatest(coalesce(p_limit, 250), 1), 500) as row_limit
    where p_lat between -90 and 90 and p_lng between -180 and 180
  ), candidates as materialized (
    select v.*, v.geo <-> p.origin as distance_m
    from public.venue v
    cross join params p
    where v.poi_category in ('brewery','bar','pub','taproom','beer_garden','nightlife')
      and v.geo is not null
      and st_dwithin(v.geo, p.origin, p.radius_m)
    order by v.geo <-> p.origin
    limit (select row_limit from params)
  ), eligible_checkins as materialized (
    select ce.venue_id, count(*)::int as checkins, max(ce.event_ts) as latest
    from public.checkin_event ce
    where ce.venue_id in (select id from candidates)
      and ce.moderation_status = 'visible'
      and public.has_current_consent(ce.user_id, 'aggregate_analytics')
    group by ce.venue_id
  )
  select
    candidate.id, candidate.name, candidate.external_ids->>'city',
    candidate.external_ids->>'region', candidate.external_ids->>'country',
    st_y(candidate.geo::geometry)::numeric,
    st_x(candidate.geo::geometry)::numeric,
    coalesce(candidate.external_ids->>'source_note', 'Tapt beer map'),
    coalesce(c.checkins, 0) * 3,
    greatest(candidate.updated_at, coalesce(c.latest, candidate.updated_at)),
    coalesce(candidate.external_ids->>'venue_type',
      candidate.external_ids->>'brewery_type', candidate.poi_category),
    candidate.external_ids->>'website_url'
  from candidates candidate
  left join eligible_checkins c on c.venue_id = candidate.id
  order by candidate.distance_m;
$$;

revoke all on function public.beer_detail(uuid) from public;
revoke all on function public.brewery_map_feed(integer) from public;
revoke all on function public.brewery_map_feed_near(numeric, numeric, integer, integer)
  from public;
grant execute on function public.beer_detail(uuid)
  to anon, authenticated, service_role;
grant execute on function public.brewery_map_feed(integer)
  to anon, authenticated, service_role;
grant execute on function public.brewery_map_feed_near(numeric, numeric, integer, integer)
  to anon, authenticated, service_role;

-- Fail the migration if the production-facing anonymous contract drifts.
do $$
declare
  actual text[];
  expected text[];
begin
  select array_agg(sig order by sig) into actual
  from (
    select p.oid::regprocedure::text as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and not exists (
        select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e'
      )
      and has_function_privilege('anon', p.oid, 'execute')
  ) q;

  select array_agg(sig order by sig) into expected
  from unnest(array[
    'beer_detail(uuid)',
    'beer_of_week_latest_winner()',
    'beer_of_week_standings(integer)',
    'brewery_map_feed(integer)',
    'brewery_map_feed_near(numeric,numeric,integer,integer)',
    'catalog_search(text,text,boolean,integer,integer)',
    'match_beers(text,integer)',
    'region_guide_feed()',
    'tapt_trusted_country(text,jsonb)',
    'venue_brand(uuid)',
    'venue_events(uuid)',
    'venue_menu(uuid)'
  ]) sig;

  if actual is distinct from expected then
    raise exception 'anonymous function contract drift: expected %, got %',
      expected, actual;
  end if;
end $$;

notify pgrst, 'reload schema';
