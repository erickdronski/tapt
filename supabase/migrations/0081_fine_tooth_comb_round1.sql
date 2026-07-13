-- 0081  Fine-tooth-comb round 1 (fleet audit wf_88fb4104).
--
-- 1. ANON LOCKDOWN. Postgres grants EXECUTE to PUBLIC on every new function,
--    so "revoke from anon" alone never worked (0067's clean_beer_name revoke
--    was a no-op; the fleet measured 786 anon-executable functions). This
--    captures what authenticated can run today, revokes PUBLIC+anon on every
--    non-extension function in public, restores authenticated exactly, and
--    grants anon the DOCUMENTED guest surface only:
--    catalog_search, venue_brand, venue_menu, venue_events,
--    region_guide_feed, match_beers   (all read-only; guests browse with them)
-- 2. venue: RLS was enabled with ZERO policies, so any direct select (Cellar
--    pour -> venue join) silently returned nothing. Venues are public
--    directory data: explicit read policy + grants.
-- 3. Honest countries: brewery.country from Open Food Facts is the country
--    the product was SCANNED in, not the brewery's home (live proof:
--    "Budweiser" stored as France, "Guiness" as Puerto Rico). New
--    tapt_trusted_country() returns NULL for OFF-sourced breweries; every
--    row-level country a user sees (trend feed, leaderboard, market refresh)
--    goes through it. Blank beats invented. The trend feed still SHELVES
--    OFF beers by scan country (that is real "found in X" signal); the app
--    copy now says "found in", never "from".
-- 4. Leaderboards make sense: styles board resolves through the BJCP
--    reference (no more "5 Beer" / "Beers From Germany" as styles); beers
--    board dedupes by display name, drops raw-junk style fallbacks, requires
--    positive signal (downvote-only beers are not "top"), trusted country.
-- 5. Data repair: 12 OBDB venues with transposed lat/lng + 1 sign-flipped
--    longitude (pins were in the wrong hemisphere/ocean); 49 exact duplicate
--    venues removed (0 dependent rows today); 5 impossible ABVs (>25%)
--    quarantined into external_ids and nulled.

-- ---------------------------------------------------------------- 1. anon
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig,
           has_function_privilege('authenticated', p.oid, 'execute') as auth_ok
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and not exists (select 1 from pg_depend d
                      where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('revoke execute on function %s from public, anon', r.sig);
    if r.auth_ok then
      execute format('grant execute on function %s to authenticated', r.sig);
    end if;
  end loop;

  -- the documented guest surface
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('catalog_search', 'venue_brand', 'venue_menu',
                        'venue_events', 'region_guide_feed', 'match_beers')
  loop
    execute format('grant execute on function %s to anon', r.sig);
  end loop;
end $$;

-- future functions do not leak to PUBLIC (applies to the migration role,
-- which is what creates functions here)
alter default privileges in schema public revoke execute on functions from public;

-- ---------------------------------------------------------------- 2. venue
do $$
begin
  if not exists (select 1 from pg_policies
                 where schemaname = 'public' and tablename = 'venue'
                   and policyname = 'venue_public_read') then
    create policy venue_public_read on public.venue
      for select to anon, authenticated using (true);
  end if;
end $$;
grant select on public.venue to anon, authenticated;

-- ------------------------------------------------------- 3. honest country
create or replace function public.tapt_trusted_country(p_country text, p_external_ids jsonb)
returns text
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select case
    when coalesce(p_external_ids->>'source', '') = 'open_food_facts' then null
    else nullif(btrim(coalesce(p_country, '')), '')
  end
$$;
-- invoked inside security_invoker views, so callers need execute
grant execute on function public.tapt_trusted_country(text, jsonb) to anon, authenticated;

drop view if exists public.beer_trend_feed;
create view public.beer_trend_feed
with (security_invoker = true) as
with current_trends as (
  select distinct on (bt.beer_id, bt.region)
    bt.beer_id,
    coalesce(nullif(b.display_name, ''), b.name) as name,
    b.style, b.abv,
    br.name as brewery_name,
    public.tapt_trusted_country(br.country, br.external_ids) as country,
    bt.region, bt.popularity, bt.momentum, bt.avg_rating, bt.updated_at,
    b.is_na_low
  from beer_trend bt
  join beer_catalog b on b.id = bt.beer_id
  left join brewery br on br.id = b.brewery_id
  order by bt.beer_id, bt.region, bt.updated_at desc nulls last, bt.id desc
)
select beer_id, name, style, abv, brewery_name, country, region,
       popularity, momentum, avg_rating, updated_at, is_na_low
from current_trends
union all
select distinct
  b.id,
  coalesce(nullif(b.display_name, ''), b.name),
  b.style, b.abv,
  br.name,
  public.tapt_trusted_country(br.country, br.external_ids),
  r.region,
  0, 0, null::numeric, b.created_at, b.is_na_low
from beer_catalog b
left join brewery br on br.id = b.brewery_id
cross join lateral (
  -- shelf key stays the scan country ("found in X" is real signal); the one
  -- state/country name collision gets disambiguated so the US-state Georgia
  -- board can never show Caucasus beers
  values (case when coalesce(nullif(br.country, ''), 'Global') = 'Georgia'
               then 'Georgia (country)'
               else coalesce(nullif(br.country, ''), 'Global') end),
         ('Global')
) r(region)
where b.name_ok
  and not exists (select 1 from beer_trend bt2
                  where bt2.beer_id = b.id and bt2.region = r.region);

grant select on public.beer_trend_feed to anon, authenticated;

-- market standings: same trusted-country rule at refresh time
-- (single-line change from 0067: br.country -> tapt_trusted_country)
create or replace function public.refresh_beer_market_standing()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  delete from public.beer_market_standing;

  insert into public.beer_market_standing
    (beer_id, standing, season_pts, award_pts, notability_pts, vote_pts,
     net_votes, votes_count, ups, downs, vol24, change_24h, reason, season_fit, heat,
     display_name, symbol, brewery, style, country, image_url, rot, computed_at)
  with season as (
    select case when extract(month from now()) in (6,7,8) then 'summer'
                when extract(month from now()) in (9,10,11) then 'fall'
                when extract(month from now()) in (12,1,2) then 'winter'
                else 'spring' end s
  ),
  base as (
    select b.id, b.name, b.style, b.brewery_id, b.cutout_url,
           coalesce(b.cutout_url, b.label_image_url) img,
           (select s from season) ssn
    from public.beer_catalog b
    where b.name_ok
      and (
        (nullif(b.style,'') is not null
         and coalesce(b.cutout_url, b.label_image_url) is not null)
        or exists (select 1 from public.beer_award a where a.beer_id = b.id)
        or exists (select 1 from public.beer_vote v where v.beer_id = b.id)
      )
  ),
  award_agg as (
    select beer_id,
      least(60, sum(case lower(medal) when 'gold' then 30 when 'silver' then 20
                                      when 'bronze' then 12 else 8 end))::int award_pts
    from public.beer_award group by beer_id
  ),
  vote_agg as (
    select beer_id, sum(value)::int net_votes, count(*)::int votes_count,
      count(*) filter (where value > 0)::int ups,
      count(*) filter (where value < 0)::int downs
    from public.beer_vote group by beer_id
  ),
  vol_agg as (
    select beer_id, count(*)::int vol24 from (
      select beer_id, coalesce(updated_at, created_at) ts from public.beer_vote
      union all
      select beer_id, coalesce(event_ts, created_at) from public.checkin_event where beer_id is not null
    ) e where ts > now() - interval '24 hours' group by beer_id
  ),
  prev as (
    select beer_id, standing prev_standing
    from public.beer_market_snapshot where snap_date = current_date - 1
  ),
  scored as (
    select bb.id, bb.brewery_id, bb.img, bb.cutout_url,
      bb.ssn,
      coalesce(nullif(b2.display_name,''), b2.name) as dname,
      coalesce(nullif(bb.style,''), 'Beer') as style,
      case
        when bb.ssn='summer' and bb.style ~* 'ipa|pale|wheat|wit|hefe|weiss|weizen|pils|lager|blonde|sour|gose|radler|shandy|session|helles|k(ö|o)lsch' then 40
        when bb.ssn='winter' and bb.style ~* 'stout|porter|barley\s?wine|bock|strong|winter|imperial|quad|dubbel|dark|schwarz' then 40
        when bb.ssn='fall'   and bb.style ~* 'm(ä|a)rzen|oktoberfest|amber|brown|pumpkin|porter|dunkel' then 40
        when bb.ssn='spring' and bb.style ~* 'saison|pale|bock|blonde|farmhouse' then 40
        else 0 end as season_pts,
      coalesce(aw.award_pts, 0) as award_pts,
      (case when bb.cutout_url is not null then 8 else 0 end)
        + (case when bb.brewery_id is not null then 6 else 0 end) as notability_pts,
      coalesce(va.net_votes, 0) * 8 as vote_pts,
      coalesce(va.net_votes, 0) as net_votes,
      coalesce(va.votes_count, 0) as votes_count,
      coalesce(va.ups, 0) as ups,
      coalesce(va.downs, 0) as downs,
      coalesce(vl.vol24, 0) as vol24,
      case
        when bb.style ~* 'non[- ]?alco|alcohol[- ]?free|0[.,]0\s*%' then 'Sober-curious pick'
        when bb.ssn='summer' and bb.style ~* 'ipa|pale|wheat|wit|hefe|weiss|weizen|pils|lager|blonde|sour|gose|radler|shandy|session|helles|k(ö|o)lsch' then 'Summer beer, in season now'
        when bb.ssn='winter' and bb.style ~* 'stout|porter|barley\s?wine|bock|strong|winter|imperial|quad|dubbel|dark|schwarz' then 'Winter beer, in season now'
        when bb.ssn='fall'   and bb.style ~* 'm(ä|a)rzen|oktoberfest|amber|brown|pumpkin|porter|dunkel' then 'Fall beer, in season now'
        when bb.ssn='spring' and bb.style ~* 'saison|pale|bock|blonde|farmhouse' then 'Spring beer, in season now'
        else null end as reason
    from base bb
    join public.beer_catalog b2 on b2.id = bb.id
    left join award_agg aw on aw.beer_id = bb.id
    left join vote_agg  va on va.beer_id = bb.id
    left join vol_agg   vl on vl.beer_id = bb.id
  ),
  standings as (
    select distinct on (lower(dname))
      id, dname, style, brewery_id, img,
      greatest(1, 10 + season_pts + award_pts + notability_pts + vote_pts) as standing,
      season_pts, award_pts, notability_pts, vote_pts,
      net_votes, votes_count, ups, downs, vol24, reason
    from scored
    order by lower(dname),
      greatest(1, 10 + season_pts + award_pts + notability_pts + vote_pts) desc,
      votes_count desc
  )
  select s.id, s.standing, s.season_pts, s.award_pts, s.notability_pts, s.vote_pts,
    s.net_votes, s.votes_count, s.ups, s.downs, s.vol24,
    (s.standing - coalesce(p.prev_standing, s.standing)) as change_24h,
    s.reason,
    case when s.season_pts > 0 then 2 else 0 end as season_fit,
    least(100, round(s.standing::numeric / nullif(max(s.standing) over (), 0) * 100))::int as heat,
    s.dname,
    upper(left(regexp_replace(s.dname, '[^A-Za-z0-9]', '', 'g'), 4)),
    br.name, s.style,
    public.tapt_trusted_country(br.country, br.external_ids),
    s.img,
    abs(('x' || substr(md5(s.id::text), 1, 8))::bit(32)::int % 20),
    now()
  from standings s
  left join public.brewery br on br.id = s.brewery_id
  left join prev p on p.beer_id = s.id;

  get diagnostics n = row_count;

  insert into public.beer_market_snapshot (beer_id, snap_date, standing)
    select beer_id, current_date, standing from public.beer_market_standing
  on conflict (beer_id, snap_date) do update set standing = excluded.standing;

  return n;
end;
$$;
revoke all on function public.refresh_beer_market_standing() from public, anon, authenticated;

-- ---------------------------------------------------------- 4. leaderboards
create or replace function public.leaderboard_beers(p_limit integer default 20, p_na_only boolean default false)
returns table(beer_id uuid, name text, style text, brewery_name text, country text,
              net_votes integer, ups integer, downs integer, checkin_count integer,
              avg_rating numeric, image_url text)
language sql
stable security definer
set search_path to 'public'
as $$
  select t.beer_id, t.name, t.style, t.brewery_name, t.country,
         t.net, t.ups, t.downs, t.checkins, t.avg_rating, t.image_url
  from (
    select distinct on (lower(coalesce(nullif(b.display_name,''), b.name)))
      b.id as beer_id,
      coalesce(nullif(b.display_name,''), b.name) as name,
      -- a style is shown only when it resolves to (or already is) a real
      -- BJCP reference name; raw OFF retail categories stay off the board
      coalesce(sr.style_name,
               case when exists (select 1 from beer_style_reference r2
                                 where r2.style_name = btrim(b.style))
                    then btrim(b.style) end) as style,
      br.name as brewery_name,
      public.tapt_trusted_country(br.country, br.external_ids) as country,
      s.net, s.ups, s.downs, s.checkins, s.avg_rating,
      coalesce(b.cutout_url, b.label_image_url) as image_url,
      (s.net + s.checkins * 2) as rank_score
    from beer_score s
    join beer_catalog b on b.id = s.beer_id
    left join brewery br on br.id = b.brewery_id
    left join beer_style_reference sr
      on sr.style_name = public.tapt_ref_style_name(b.style, b.name)
    where (s.net > 0 or s.checkins > 0)   -- downvote-only is not "top"
      and b.name_ok
      and (not p_na_only or b.is_na_low)
    order by lower(coalesce(nullif(b.display_name,''), b.name)),
             (s.net + s.checkins * 2) desc, b.id
  ) t
  order by t.rank_score desc, t.name
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

create or replace function public.leaderboard_styles(p_limit integer default 20)
returns table(style text, pours integer, avg_rating numeric, last_pour_at timestamp with time zone)
language sql
stable security definer
set search_path to 'public'
as $$
  select
    sr.style_name,
    count(*)::int,
    avg(ce.rating)::numeric(3,2),
    max(ce.event_ts)
  from checkin_event ce
  left join beer_catalog b on b.id = ce.beer_id
  join beer_style_reference sr
    on sr.style_name = public.tapt_ref_style_name(ce.style, b.name)
  where coalesce(ce.style, '') <> ''
    and ce.moderation_status = 'visible'
  group by sr.style_name
  order by count(*) desc, max(ce.event_ts) desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

-- ----------------------------------------------------------- 5. data repair
-- Impossible ABVs (OFF parse junk: 68%, 39.6%, ...). Quarantine, never show.
update public.beer_catalog
set external_ids = coalesce(external_ids, '{}'::jsonb)
      || jsonb_build_object('raw_abv_quarantined', abv::text),
    abv = null
where abv > 25;

-- 12 OBDB venues stored transposed (lat in the lng slot and vice versa)
update public.venue
set geo = st_setsrid(st_makepoint(st_y(geo::geometry), st_x(geo::geometry)), 4326)::geography
where name in ('Berlin Craft Beer Experience','Birgit','BrewDog Berlin Mitte',
               'BRLO Brwhouse','Golgatha Biergarten','Mikkeller Berlin',
               'Prater Beer Garden')
  and st_y(geo::geometry) between 12 and 15
  and st_x(geo::geometry) between 51 and 54;

update public.venue
set geo = st_setsrid(st_makepoint(st_y(geo::geometry), st_x(geo::geometry)), 4326)::geography
where (name = 'Goat Island Brewing'
       and st_y(geo::geometry) between -88 and -85
       and st_x(geo::geometry) between 33 and 36)
   or (name = 'Labyrinth Brewing Company'
       and st_y(geo::geometry) between -74 and -71
       and st_x(geo::geometry) between 40 and 43);

-- Mescan Brewery (Ireland): longitude sign flipped (+9.73 is Kazakhstan-side)
update public.venue
set geo = st_setsrid(st_makepoint(-st_x(geo::geometry), st_y(geo::geometry)), 4326)::geography
where name = 'Mescan Brewery'
  and st_x(geo::geometry) between 9 and 10.5
  and st_y(geo::geometry) between 53 and 54.5;

-- 49 exact duplicate venues (same name+city+country). Keep the richer row;
-- delete losers only when nothing references them (0 references today).
with ranked as (
  select id,
         row_number() over (
           partition by lower(name), external_ids->>'city', external_ids->>'country'
           order by (external_ids->>'website' is not null) desc,
                    (external_ids->>'obdb_id' is not null) desc,
                    created_at, id
         ) as rn
  from public.venue
),
losers as (
  select r.id from ranked r
  where r.rn > 1
    and not exists (select 1 from public.checkin_event t where t.venue_id = r.id)
    and not exists (select 1 from public.featured_partner t where t.venue_id = r.id)
    and not exists (select 1 from public.tasting_session t where t.venue_id = r.id)
    and not exists (select 1 from public.venue_claim t where t.venue_id = r.id)
    and not exists (select 1 from public.venue_correction t where t.venue_id = r.id)
    and not exists (select 1 from public.venue_event t where t.venue_id = r.id)
    and not exists (select 1 from public.venue_tap_snapshot t where t.venue_id = r.id)
)
delete from public.venue v using losers l where v.id = l.id;

-- rebuild market standings under the new country rule
select public.refresh_beer_market_standing();
